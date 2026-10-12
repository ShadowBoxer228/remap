import { readFileSync } from 'node:fs';
import { createHash, createHmac } from 'node:crypto';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { neon } from '@neondatabase/serverless';

export const BUNDLE_ID = 'com.selimtatar.ReMap';
export const ACCESS_DAYS = 30;
const roots = ['AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer']
  .map(name => readFileSync(new URL(`./certificates/${name}`, import.meta.url)));
const hash = value => createHash('sha256').update(value).digest('hex');

// TestFlight uses Apple's sandbox signatures. Never accept Xcode/local unsigned data.
export function appleInstallationVerifier() {
  const verifier = new SignedDataVerifier(roots, true, Environment.SANDBOX, BUNDLE_ID);
  return async proof => verifiedAppleIdentity(await verifier.verifyAndDecodeAppTransaction(proof));
}

// Only call after Apple's cryptographic verifier succeeds. Sandbox AppTransaction
// deliberately omits appAppleId; the signed bundle ID is the application binding.
export function verifiedAppleIdentity(transaction) {
    if (transaction.receiptType !== Environment.SANDBOX || transaction.bundleId !== BUNDLE_ID ||
        !/^[0-9]{1,128}$/.test(transaction.appTransactionId ?? '') ||
        !Number.isFinite(transaction.receiptCreationDate) ||
        transaction.receiptCreationDate > Date.now() + 300_000 || transaction.appRevocationDate) {
      throw new Error('invalid_installation');
    }
    return transaction.appTransactionId;
}

export function enrollmentDatabase(url) {
  const sql = (strings, ...values) => neon(url, { fetchOptions: { signal: AbortSignal.timeout(8000) } })(strings, ...values);
  return {
    async reserveVerification() {
      const rows = await sql`UPDATE remap_enrollment_limits SET
        window_used = CASE WHEN window_started <= now() - interval '1 minute' THEN 1 ELSE window_used + 1 END,
        window_started = CASE WHEN window_started <= now() - interval '1 minute' THEN now() ELSE window_started END
        WHERE id = 1 AND (window_started <= now() - interval '1 minute' OR window_used < 20) RETURNING id`;
      return rows.length === 1;
    },
    async enroll(subject, installation, tokenHash, expiresAt) {
      const [row] = await sql`SELECT remap_enroll(${subject}, ${installation}, ${tokenHash}, ${new Date(expiresAt).toISOString()}) AS status`;
      return row.status;
    },
    async authorize(tokenHash) {
      const rows = await sql`SELECT t.token_hash FROM remap_access_tokens t
        JOIN remap_access_subjects s ON s.subject_hash = t.subject_hash
        WHERE t.token_hash = ${tokenHash} AND t.expires_at > now()
          AND t.revoked_at IS NULL AND s.revoked_at IS NULL LIMIT 1`;
      return rows.length === 1;
    }
  };
}

export function installationAccess({ secret, repository, verify, now = Date.now }) {
  const configured = typeof secret === 'string' && secret.length >= 43 && repository && verify;
  return {
    configured: Boolean(configured),
    async enroll(input) {
      if (!configured) return { status: 503, body: { error: 'enrollment_unavailable' } };
      if (!input || Object.keys(input).some(k => !['installationID', 'appTransaction'].includes(k)) ||
          !/^[a-f0-9]{64}$/.test(input.installationID ?? '') ||
          typeof input.appTransaction !== 'string' || input.appTransaction.length < 100 || input.appTransaction.length > 24_000) {
        return { status: 400, body: { error: 'invalid_enrollment' } };
      }
      if (!await repository.reserveVerification()) return { status: 429, body: { error: 'enrollment_limit' } };
      let identity;
      try { identity = await verify(input.appTransaction); }
      catch { return { status: 403, body: { error: 'installation_not_verified' } }; }
      const subject = createHmac('sha256', secret).update(`subject:${identity}`).digest('hex');
      const installation = hash(input.installationID);
      // Stable for this install: retry after a lost response doesn't create another credential.
      const token = 'rm1_' + createHmac('sha256', secret).update(`access:${subject}:${installation}`).digest('base64url');
      const expiresAt = now() + ACCESS_DAYS * 86400_000;
      const status = await repository.enroll(subject, installation, hash(token), expiresAt);
      if (status !== 'ok') return { status: status === 'revoked' ? 403 : 429, body: { error: status === 'revoked' ? 'access_revoked' : 'enrollment_limit' } };
      return { status: 200, body: { token, expiresAt: Math.floor(expiresAt / 1000) } };
    },
    async authorize(token) {
      if (!configured || !/^rm1_[A-Za-z0-9_-]{43}$/.test(token)) return false;
      return repository.authorize(hash(token));
    }
  };
}
