# Contributing to ReMap

Keep changes focused on the learning experience and preserve existing maps and
source documents. Explain the problem, resulting behavior and actual validation.

## Development

1. Install the toolchain listed in [README.md](README.md).
2. Run `xcodegen generate` after changing `project.yml` or on a fresh clone.
3. Use your own signing team and a separate DerivedData directory.
4. Keep the deployment target at **17.0** and use `PlatformCompatibility.swift`
   for newer APIs.

List available simulators, then select an explicit iPad UUID:

```sh
xcrun simctl list devices available
xcodebuild -project ReMap.xcodeproj -scheme ReMap -destination 'platform=iOS Simulator,id=YOUR_IPAD_SIMULATOR_UUID' -derivedDataPath build/ContributorDerivedData test
```

Run backend tests from `backend/` with `npm ci` and `npm test`. Use synthetic
documents, isolated app data and your own backend for live checks. Never erase a
shared simulator or overwrite saved maps to prepare a test.

## Before a pull request

- Report limitations and distinguish compilation, simulator behavior, physical
  device behavior and TestFlight availability.
- Include meaningful checks for changed model, command, source or lifecycle behavior.
- Preserve atomic edits, Undo, cloud opt-out and saved-session compatibility.
- Keep credentials, private documents, local logs and build products out of the
  diff. Review `git diff --cached` before committing.
- Document new configuration with empty placeholders in `.env.example`.

Use a demo map for screenshots. For vulnerabilities, follow [SECURITY.md](SECURITY.md).
