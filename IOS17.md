# Primary platform: iPadOS 17

The minimum deployment target is **17.0**. iPadOS 17 is the primary runtime target
for core flows, coaching, voice, enrollment, gestures and persistence.

The SDK version is a build-tool choice, not the minimum OS. Newer APIs require
availability guards and a working fallback through `PlatformCompatibility.swift`.
Foundation Models and newer visual effects are optional enhancements.

## What establishes compatibility

Run the actual app on a 17.x iPad device or simulator. Record its OS, app build and
observed results. Check startup and changed flows. Physical Pencil and acoustic
behavior require a real device.

| Evidence | What it proves |
| :--- | :--- |
| Compilation with deployment target 17.0 | Build compatibility |
| Run on a newer simulator | Behavior on that simulator's OS |
| Run on an actual 17.x runtime | Observed behavior on iPadOS 17 |
| Signed archive / Apple receipt | Packaging / delivery, not runtime behavior |

## Current limitation

Actual iPadOS 17 execution has **not yet been verified** in the recorded development
checks. Simulator runs used a newer OS. Physical Pencil/acoustic and fresh
TestFlight enrollment checks also need their own evidence. These are pending
checks, not passes, and do not change the deployment target.

A Library scrolling crash was reported on a physical iPadOS 17 device. Build 5
adds bounded thumbnail caching, finite layout guards and a row-based card layout.
Scrolling and rotation with 32 cards were checked on iPadOS 27. The original
17.x crash cause and its resolution are **not confirmed** without device evidence.
