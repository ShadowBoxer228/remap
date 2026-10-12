# Architecture

ReMap separates the local learning workspace from network coaching. Maps and
source documents remain useful when cloud services are unavailable.

## Native application

| Layer | Responsibility |
| :--- | :--- |
| `App` and `Model` | App state, saved sessions and map data |
| `Features/Collect` and `Services` | Import, PDF text/OCR and source context |
| `Features/Sort` and `Features/Session` | Learning stages and transitions |
| `Features/Canvas` | Placement, camera, Pencil input and connections |
| `Features/Coach` | Conversation, review, source references and validated commands |
| `Features/Voice` | Audio capture/playback, transport and lifecycle |
| `DesignSystem` | Paper styling, components, motion and platform compatibility |

`SessionModel` coordinates updates. Coach commands operate on a candidate map and
validate the batch before committing one undoable change. A stale revision or
invalid operation must not leave a partially changed map.

PDF context retains actual page numbers. Retrieval selects bounded excerpts and may attach a relevant page image to preserve visual relationships in tables;
references are checked against the current document before opening a page. Source
text is evidence for conversation, not authority to change app behavior.

## Gateway and providers

The Hono gateway authenticates access, reserves usage and constructs provider
requests. Text and live coaching share server-owned learning policy. The app uses
temporary credentials for a direct Realtime audio connection; provider keys never
cross that boundary.

Postgres stores access records, counters and cover-job metadata. Optional covers
use a separate image provider. A successful build does not establish live provider
availability.

## Compatibility and persistence

iPadOS 17 is primary. Newer visual and on-device-model APIs remain optional.
Saved sessions and user documents must survive upgrades; a data reset is not a
migration strategy. See [privacy](PRIVACY.md), [backend configuration](../backend/README.md)
and [platform verification](../IOS17.md).
