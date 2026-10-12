# ReMap app icon

The user selected **Connected ideas** on 2026-10-12: a compact paper mind map,
with cream nodes and a butter-yellow focal idea on an olive paper background.

- Generated master: `remap-connected-ideas.png`.
- Generation: built-in `image_gen`, with the app's existing paper illustrations as style references.
- Exact prompt: `remap-connected-ideas.prompt.md`.
- App asset: `../../ReMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Earlier concepts and original icon are preserved in `../archive/`.

Export from the repository root:

```sh
swift tools/make_icon.swift
```

The exporter resizes the generated master to 1024×1024 opaque sRGB PNG. It does
not redraw the old node/reload symbol. Leave the square corners intact for the
system icon mask.

Validation on 2026-10-12:

- Export inspected: 1024×1024, no alpha channel, sRGB IEC61966-2.1.
- Visually inspected at 60×60 and 167×167: nodes and connecting strokes remain readable.
- Xcode `actool` compiled the asset catalog for iPad / iOS Simulator, deployment
  target 26.0, without warnings or errors. Log: `../../build/QA/app-icon/actool.log`.
- Full simulator build succeeded using `build/IconPreviewDerivedData`; log:
  `../../build/QA/app-icon/rebuild.log`.
- Installed and launched on iPad Air (5th generation), iPadOS 27.0,
  `28324744-9B9A-43DD-B50B-C4EC5A4CC5FE`. Visually confirmed the new icon on the
  actual simulator Home Screen. Screenshot: `../../build/QA/app-icon/ipad-home-screen.png`.
- No App Store upload was performed.

App asset SHA-256:
`dc0cd35a7843d834d0a87032bd01a31c25b6264502283d311e9a59ebe0f19c7a`
