# Sort editorial collage

Three original raster illustrations generated with the built-in `image_gen` tool
for ReMap's native Sort screen on 2026-10-12.

| Master / asset name | Meaning |
| --- | --- |
| `sort_backbone.png` / `sort_backbone` | Three large paper idea cards supported by a bold central ink structure |
| `sort_topic.png` / `sort_topic` | A smaller hub branching into related paper ideas |
| `sort_detail.png` / `sort_detail` | One fact card inspected through a halftone magnifier |

Exact prompts: [PROMPTS.md](PROMPTS.md). First reference was the app's
`collect_reading` illustration. Topic and Detail additionally used the generated
Backbone master to maintain the same print treatment. The original generated
files remain in Codex's generated_images folder; these copies are the permanent
workspace masters. Matching imagesets contain byte-identical PNGs.

Format: 1254 × 1254, 8-bit RGBA PNG with actual transparent pixels. UI display is
72–88 pt, reduced to 52 pt in accessibility layout. Text is never embedded in the
artwork; names, hints, counters and cards are native SwiftUI content.

The screen uses static cream paper, a restrained butter marker under Backbone,
and graphically cut edges. No looping grain, glow, halo or rasterized UI. A
successful placement gives the role artwork a 0.32-second stepped lift/settle;
Reduce Motion uses opacity only.

Implementation is local to SortView and SortCollageComponents. Collect's shared
HeadlineChip, session models, stored roles and all assignment/coach handlers are
preserved. QA evidence lives in `../../build/QA/sort-collage/` (ignored build output).
