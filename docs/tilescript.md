# TileScript: Demo & Test Automation System

## Goals
1. **Demo automation** — Hand-authored YAML scripts drive the app hands-free for live presentations
2. **Test harness** — Programmatically generated bulk scenarios (e.g., 200K cache entries) for scale testing
3. **Debugger-style stepping** — Pause, step over/into, continue, rewind for fine-grained control

## Script Format (YAML via Yams SPM)

```yaml
name: Basic AAC Demo
description: Child requesting food from mom
audio: on
tileWait: .human
sentenceWait: .human

script:
  - tiles:
    - <home>, mom, <food>, pizza
    - pizza, fries
    - pizza, fries
    - <home>, mom, <places>, playground
  - comment: Now bulk loading
  - tileWait: .instant
  - sentenceWait: .instant
  - tiles: {count: 20000, source: most-common, length: 2-4}
```

### Tiles syntax
- Each row = one utterance: optional `<page>` nav mixed with tile keys
- Auto-clear after each row's sentence completes
- `<angle_brackets>` = navigate to page
- Bare words = tile taps via `engine.addTile()`
- Repeated rows test escalation naturally

### Timing presets
| Preset | tileWait | sentenceWait |
|--------|----------|--------------|
| `.human` | ~800ms | ~3s |
| `.fast` | ~100ms | ~500ms |
| `.instant` | 0ms | 0ms |
| explicit | `500ms`, `2s` | `500ms`, `2s` |

### Global settings (overridable inline)
| Setting | Values | Effect |
|---------|--------|--------|
| `audio` | `on`/`off` | Toggle engine audioEnabled |
| `tileWait` | preset or duration | Delay between tile taps |
| `sentenceWait` | preset or duration | Delay after sentence generates |
| `provider` | `mock`/`openai` | Switch sentence provider |
| `scene` | scene name | Activate a named scene |

### Inline commands
| Command | Effect |
|---------|--------|
| `tiles:` (rows) | Sequence of utterances |
| `tiles:` (bulk) | `{count, source, length}` → BulkCacheGenerator |
| `clear` | Explicit clearSelection() |
| `comment` | Show text overlay on HUD |
| `wait` | Explicit pause |
| `screenshot` | Capture the screen to `Documents/Screenshots/<name>.png` |
| Settings | Override globals mid-script |

### Screenshots

`- screenshot: name` writes a PNG of the current screen.

```yaml
  - tiles:
    - mom, <food>, pizza
  - screenshot: 03-sentence-ready
```

**Why capture from inside the app.** `xcrun simctl io … screenshot` can
photograph a simulator at any moment, but it cannot know *when* the app has
reached the state worth photographing. The interesting states — an overlay up, a
sentence mid-generation, a board scrolled past page 1 — last a few hundred
milliseconds and are reached by the script itself. Capturing in-script means the
script picks the moment. It also works on a **real device**, which matters
because App Store assets have to come from real hardware.

Captures are full native resolution (bounds × screen scale), rendered with
`drawHierarchy` so blurs, materials and popovers appear — `layer.render(in:)`
drops exactly those, which is most of what a screenshot is for.

Repeating a name never overwrites: the second capture becomes `name-2.png`, so
re-running a script cannot destroy the evidence from the run before it.

Retrieving them:

```bash
# simulator
open "$(xcrun simctl get_app_container booted app.blasterai.ios data)/Documents/Screenshots"
```

On a device: Files → On My iPad → Blaster → Screenshots.

`Resources/Scripts/shots_child_surface.yaml` is a worked example that walks the
board through five states and captures each.

## Demo Sources

### Built-in Demos
Curated YAML scripts bundled in `Resources/Scripts/`. Hand-authored to showcase specific scenarios (food ordering, basic AAC interaction, escalation). Available in the TileScript tab under "Curated Demos" with Step and Run buttons.

### User-Recorded Demos
Users can record their own demos by tapping a Record button on the Home tab, interacting with the app naturally, then stopping and saving. The recorder captures tile taps and page navigations as they happen, grouping them into YAML rows using `clearSelection()` as the row boundary. The generated sentence for each utterance is saved as a YAML comment for readability.

Recordings are stored as `RecordedScript` SwiftData models (syncs across devices via CloudKit). They appear in the TileScript tab under "My Recordings" with the same Step/Run controls as curated demos. Recordings can be exported as `.yaml` files for sharing.

**Recording flow:**
1. Tap the red Record button on the Home tab
2. Interact naturally — navigate pages, tap tiles, let sentences generate
3. Each `clearSelection()` (user X button or idle timer) finalizes one YAML row
4. Tap Stop → name the recording → Save
5. The recording is now playable via TileScriptRunner like any other script

## Architecture

### Key Types
- **NavigationCoordinator** — Shared nav state extracted from TileGridView
- **TileScript** — Parsed script model
- **TileScriptParser** — YAML → TileScript (Yams)
- **TileScriptSerializer** — TileScript → YAML (inverse of parser)
- **TileScriptRunner** — @Observable execution engine with debugger-style stepping
- **TileScriptRecorder** — @Observable recording state machine
- **BulkCacheGenerator** — Cache population for bulk test scenarios
- **RecordedScript** — SwiftData model for user recordings

### Stepping Model
Position tracked as `(commandIndex, rowIndex)`:
- **Step Over**: Execute current row/command, pause at next
- **Step Into**: Execute one action within a row
- **Continue**: Finish current tiles block, pause at next top-level command
- **Play**: Resume continuous execution

### UI
- **TileScriptView** — TileScript tab: curated demos, user recordings, test generator
- **TileScriptPlaybackOverlay** — Floating HUD on Home tab during playback
- **TileScriptRecordingOverlay** — Record button + recording indicator on Home tab

## Files
```
claudeBlast/Engine/TileScript/
  TileScriptCommand.swift
  TileScript.swift
  TileScriptParser.swift
  TileScriptSerializer.swift
  TileScriptRunner.swift
  TileScriptRecorder.swift
  BulkCacheGenerator.swift
  NavigationCoordinator.swift

claudeBlast/Models/
  RecordedScript.swift

claudeBlast/Views/
  TileScriptView.swift
  TileScriptPlaybackOverlay.swift
  TileScriptRecordingOverlay.swift

claudeBlast/Resources/Scripts/
  demo_basic.yaml
  demo_food.yaml
```
