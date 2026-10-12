import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { installationAccess, appleInstallationVerifier, verifiedAppleIdentity } from './enrollment.mjs';
import { gateway } from './server.mjs';

const input = { installationID: 'a'.repeat(64), appTransaction: 'signed'.repeat(40) };
function fixture(options = {}) {
  const tokens = new Set(); let verified = 0, enrollments = 0;
  const repository = {
    reserveVerification: async () => true,
    enroll: async (_subject, _installation, token) => { enrollments++; tokens.add(token); return 'ok'; },
    authorize: async token => tokens.has(token), ...options.repository
  };
  const access = installationAccess({ secret: 's'.repeat(64), repository,
    verify: async () => { verified++; return '123456789'; }, ...options.access });
  return { access, tokens, counts: () => ({ verified, enrollments }) };
}

test('signed-installation exchange returns bounded reusable credential, never raw proof or subject', async () => {
  const { access, tokens } = fixture();
  const first = await access.enroll(input), second = await access.enroll(input);
  assert.equal(first.status, 200); assert.match(first.body.token, /^rm1_[\w-]{43}$/);
  assert.equal(second.body.token, first.body.token); assert.equal(tokens.size, 1);
  assert.equal(await access.authorize(first.body.token), true);
  assert.deepEqual(Object.keys(first.body).sort(), ['expiresAt','token']);
  assert.ok(first.body.expiresAt > Date.now()/1000 + 29*86400);
  assert.equal(await access.authorize('rm1_'+'z'.repeat(43)), false);
});
test('different installations get different credentials', async () => {
  const { access } = fixture();
  assert.notEqual((await access.enroll(input)).body.token,
    (await access.enroll({...input,installationID:'b'.repeat(64)})).body.token);
});
test('invalid or unverified proof cannot enroll or spend a coach quota', async () => {
  const invalid = fixture({access:{verify:async()=>{throw Error('do not expose provider detail');}}});
  assert.deepEqual(await invalid.access.enroll(input), {status:403,body:{error:'installation_not_verified'}});
  assert.equal(invalid.counts().enrollments,0);
  for (const value of [null,{}, {...input, installationID:'not-an-id'}, {...input, appTransaction:'x'.repeat(24001)}, {...input, model:'anything'}]) {
    assert.equal((await invalid.access.enroll(value)).status,400);
  }
});
test('rate limit is enforced before signature verification', async () => {
  const f=fixture({repository:{reserveVerification:async()=>false}});
  assert.equal((await f.access.enroll(input)).status,429); assert.equal(f.counts().verified,0);
});
test('revoked and capped installs cannot be renewed', async () => {
  for(const [value,status] of [['revoked',403],['limited',429]]) {
    const f=fixture({repository:{enroll:async()=>value}});
    const reply=await f.access.enroll(input); assert.equal(reply.status,status); assert.equal(reply.body.token,undefined);
  }
});
test('Apple verifier rejects unsigned Xcode, malformed and fabricated Sandbox signatures', async () => {
  const verify=appleInstallationVerifier();
  const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  for(const receiptType of ['Xcode','Sandbox','Production']) {
    const fake=`${encode({alg:'none'})}.${encode({receiptType,bundleId:'com.selimtatar.ReMap',appTransactionId:'123'})}.`;
    await assert.rejects(verify(fake));
  }
  await assert.rejects(verify('invalid'));
});
test('verified Sandbox proof omits App Store numeric ID and still binds exact app and environment', () => {
  const signed = { receiptType: 'Sandbox', bundleId: 'com.selimtatar.ReMap',
    appTransactionId: '123456789', receiptCreationDate: Date.now() };
  assert.equal(verifiedAppleIdentity(signed), '123456789');
  for (const patch of [{bundleId:'another.app'}, {receiptType:'Production'},
    {receiptType:'Xcode'}, {appTransactionId:undefined}, {appRevocationDate:Date.now()},
    {receiptCreationDate:Date.now()+600000}]) {
    assert.throws(()=>verifiedAppleIdentity({...signed,...patch}));
  }
});
test('gateway enrollment does not require old tester token; paid routes require new credential', async () => {
  const f=fixture(); let paid=0;
  const app=gateway({key:'server-key',token:'l'.repeat(40),reserve:async()=>{paid++;return true;},
    inferFn:async()=>({message:'real route'}),access:f.access});
  const response=await app.request('/access/enroll',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
  assert.equal(response.status,200); assert.equal(response.headers.get('Cache-Control'),'no-store'); assert.equal(paid,0);
  const {token}=await response.json();
  const request=credential=>app.request('/coach',{method:'POST',headers:{'Content-Type':'application/json','X-ReMap-Token':credential},body:JSON.stringify({operation:'conversation',context:JSON.stringify({message:'Hello',history:[],map:{revision:'11111111-1111-4111-8111-111111111111',title:'Test',nodes:[],edges:[]}})})});
  assert.equal((await request('bad')).status,401); assert.equal(paid,0);
  assert.equal((await request(token)).status,200); assert.equal(paid,1);
  f.tokens.delete(createHash('sha256').update(token).digest('hex'));
  assert.equal((await request(token)).status,401); assert.equal(paid,1);
  assert.equal((await app.request('/access/enroll',{method:'POST',body:'x'.repeat(32769)})).status,413);
});
