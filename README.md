# ReMap

A native iPad learning canvas. Collect headings from a PDF or pasted notes, sort
them into backbone/topic/detail ideas, draw a map, and explain its relationships
to a Socratic coach. Maps and Pencil sketches persist locally. The example topic
is endocrine regulation; calcitonin lowers blood calcium and parathormone raises it.

## Run

Requires Xcode 27, iOS 26+ and an iPad. Open `ReMap.xcodeproj` and select the ReMap
scheme. This generated project is ignored by Git; run `xcodegen generate` on a
fresh checkout. New Swift files in synchronized source folders need no regeneration.

```sh
xcodebuild -project ReMap.xcodeproj -scheme ReMap \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/CoreDerivedData build
```

Before using a simulator in this shared checkout, read `COORDINATION.md`. For
tests, replace the destination with an explicit available iPad simulator UUID and
use `test`. Unit tests cover map rules, layout, camera transforms, persistence,
grouping, placement undo, flow transitions, atomic coach commands and PCM audio decoding. Tests use isolated local stores.

## Coach and voice

Cloud coach is on by default for the approved internal build. Users can switch it
off in Library settings. Foundation Models provides short questions and
relationship checks when Apple Intelligence is available; otherwise deterministic
questions and a limited relationship heuristic are used. The heuristic is not a
general fact checker. The demo's questions remain deterministic.

The cloud coach uses **OpenAI Realtime (`gpt-realtime-2.1`)**. A private
Vercel gateway handles text questions, judgments and conversation, and issues 60-second client
secrets for direct iPad audio connections. The OpenAI project key never enters
the app. Judgments use a forced `record_verdict` function with a boolean argument;
malformed output fails closed. Open conversation uses a bounded board snapshot and
recent chat history. Explicit edit requests may produce typed board commands: the
app validates the latest request, map revision and every operation before applying
one undoable transaction. Commands include grouping, arrow direction, highlighting
and undo. Highlights preserve the map and camera. Explanations alone must not edit
the board. Active review answers have a separate validated route, so other questions
and commands remain available during placement.

The approved internal DEBUG installation provisions access automatically to
`https://remap-coach.vercel.app`. The maintainer's tester credential stays in
ignored, owner-readable local files and the app's Keychain. The app has no manual
URL or credential form. Never enter an OpenAI key in the app.

Cloud consent covers relevant map labels, relationships, positions, recent messages
and microphone audio. Continuous voice streams the microphone until muted or closed.
PDFs and sketches stay local. Disable cloud coach in Library settings to
return to on-device operation. Structured review questions/checks fall back locally; open conversation and cloud
voice failures show an explicit message rather than silently changing provider.

Voice uses semantic voice activity detection to commit each spoken turn. The app
waits for transcription, attaches the current board and requests a response. It
streams actual assistant captions and mono PCM at 24 kHz. Speaking interrupts
playback and removes unplayed response audio from conversation history. Mute,
retry, close and background shutdown are explicit. Voice closes after five minutes;
the legacy push-to-talk transport also limits a recording to 45 seconds.

The server secret's 60-second TTL controls connection establishment, not session
duration. These client controls are not a hard provider billing cap. The current
WebSocket transport still needs physical-device audio/route/echo testing.

For the approved internal DEBUG build, `tools/prepare_internal_library.py` can
provision the existing tester credential into the app's data container. The app
moves it to Keychain and deletes the provisioning file. No secret enters the binary;
subsequent launches respect the user's settings.

## Backend

See [backend/README.md](backend/README.md) for configuration, request caps and
deployment. Coach calls are billed to OpenAI. The separately approved topic-cover
feature uses fal.ai nano-banana-2, one 1K image per job, behind its own 100-job cap.
It requires FAL_KEY in Vercel; it cannot use the desktop connector as an app credential.
The isolated Neon database holds counters and cover-job metadata, not full maps or audio.
No analytics or advertising SDK is included. The privacy manifest declares
optional audio/user content for app functionality and UserDefaults reason CA92.1.
Provider retention follows the configured OpenAI account policies; this app does
not claim zero retention. App Store privacy answers must reflect that setup.

## Release

Bundle ID `com.selimtatar.ReMap`, team `334SK39CVZ`, version 1.0.0, build 1.
Create the **ReMap** iOS app record in App Store Connect with that exact bundle ID.
The archive/export workflow and current evidence are tracked in `HANDOFF.md`.
Upload to internal TestFlight requires explicit user confirmation; no upload is
performed by building or archiving. Increment the build number for each upload.
Fresh Release/TestFlight installations still need an approved tester enrollment
path: the current automatic provisioning is DEBUG-only. A signed archive alone
does not establish cloud access for new TestFlight testers.

Physical iPad verification remains necessary for Pencil/handwriting, audio route
changes, Apple Intelligence and the 60fps performance target. Simulator/API tests
do not establish those results. See `build/QA/core-*` and the other agents' status
files for timestamped evidence. There is no commit or remote push yet.

The selected icon and its source prompt are documented in
[art/branding/README.md](art/branding/README.md). Third-party font licensing is in
`Licenses/`.
