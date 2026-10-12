# Session journey — V3 top icon bar

Current API: `SessionJourneyProgressBar(model:)` in `SessionJourneyProgress.swift`. Shared SessionHeader owns its wide420pt placement and compact second row. Both parent screens no longer render the V2 left rail. V1/V2 wrapper views remain unused compatibility code.

Five phase icons with adaptive captions, a segmented progress track and a yellow paper current-stage tab. Icons remain visible at narrow widths; full captions fit first, then only current caption, then icons alone. Touch targets stay at least44pt. Visited stages navigate directly; the current stage reveals the labeled paper menu below the strip. Future stages stay disabled. VoiceOver states, Reduce Motion and the generated menu collage remain. The final Mind map icon is a brain, distinct from the Backbone structure icon.

## Evidence

- iOS component typecheck PASS: `build/QA/journey-progress/typecheck-v3.log`.
- Actual native SwiftUI content preview at580/420/290pt: `native-preview-v3.png`; offscreen macOS adapters, not an iPad screenshot.
- Integrated simulator build PASS at13:48:38 with zero before/after source drift: `build/QA/journey-progress/integrated-v3-checkpoint/result.json`; immutable app and bundle manifest alongside. This is build evidence only until installed verification is added.
- Runtime/capture scenario: `build/QA/journey-progress/QA-v3.md`.
- V2 installation and screenshot remain historical in installed-verification-v2.json and ipad-menu-open-v2.png.

Artwork provenance: `journey-collage-master.png` is unchanged built-in image_gen output copied to journey_collage.imageset. Exact prompts are in PROMPT.md. Opaque cream output was selected after rejecting transparency halo attempts.
