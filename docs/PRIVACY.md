# Data boundaries

| Data | Handling |
| :--- | :--- |
| Maps, source PDFs and Pencil sketches | Stored locally by the app |
| Relevant excerpts, map context and recent conversation | Sent for enabled cloud coaching |
| Map image, a relevant PDF page image and structured ink context | May accompany source-aware coaching |
| Microphone audio | Streamed during an active cloud voice session |
| Installation credential | Stored in Keychain |
| Provider credentials | Kept in the backend environment |
| Access, usage counters and cover-job metadata | Stored by the gateway in Postgres |

Original PDFs remain local; this does **not** mean their content never leaves the
device. Relevant passages and a bounded page image can be sent for coaching, including table layout. Map snapshots may include
handwriting. Optional covers send a prompt to the configured image provider.

Cloud coach can be disabled in Library settings. Closing voice, muting and moving
to the background control microphone use. On-device fallback is more limited than
cloud conversation.

No advertising or analytics SDK is included. Provider retention follows the
configured accounts; this project does not claim zero retention. The app privacy
manifest is [PrivacyInfo.xcprivacy](../ReMap/Resources/PrivacyInfo.xcprivacy).

Public bug reports should use synthetic documents. User maps, recordings, app
containers and operational release evidence are excluded from Git.
