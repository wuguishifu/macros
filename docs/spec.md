# Macros — v1 spec

Macros is a macOS menu bar app for recording and replaying ad-hoc keyboard and mouse macros, modelled on vim's
`q`/`@` registers.

Motivating use case: changing the same settings on 20+ GitHub repos open in browser tabs. Record the whole job once on
one tab (ending with "switch to next tab"), then replay it 20 times.

## Product

| | |
|---|---|
| Name | Macros |
| Bundle ID | `dev.wuguishifu.macros` |
| Platform | macOS 14 (Sonoma)+ |
| Form | Menu bar only (`LSUIElement`), no Dock icon |
| Stack | Native Swift 6 (strict concurrency), SwiftUI + AppKit |
| Distribution | Developer ID–signed, notarized, direct download (DMG/zip). Not the Mac App Store — the sandbox forbids posting input to other apps. No auto-update in v1. |
| License | MIT, open source — https://github.com/wuguishifu/macros |

## Chords

Two configurable **leaders**. Defaults: `⌃⌘M` (record) and `⌃⌘N` (play).

| Chord | Effect |
|---|---|
| `Rec`, `a`–`z` | Start recording into that register (overwrites) |
| `Rec`, `⇧` + letter | Start recording, **appending** to that register |
| `Rec` (while recording) | Stop recording |
| `Play`, `a`–`z` | Play register once |
| `Play`, `1`–`999`, `a`–`z` | Play register N times |
| `Play`, [N], `Play` | Replay the last-played register (N times) |
| `Esc` (while a chord is pending) | Cancel the chord |

- A pending chord is cancelled after a timeout (default 3 s, configurable). Each key typed into the chord resets it.
- Count digits are capped at 3 (max 999). Extra digits are ignored.
- Register keys are matched by the character on the current keyboard layout. `⌘`/`⌃`/`⌥` are ignored; only `⇧` matters (append).
- Leaders are matched by physical key code + exact `⌘⌃⌥⇧` modifier set, and must include at least one of `⌘⌃⌥`.
- Any other key in a pending chord cancels it, with a HUD notice.
- **All chord keys are swallowed.** They never reach the frontmost app and are never recorded. Their key-ups (and any
  auto-repeats) are swallowed too.
- `Play` is ignored while recording (HUD: "can't play while recording"). `Rec` is ignored while playing.

## Recording

- Captured: key down/up (physical **key codes**, plus modifier flags), modifier changes, mouse moves, button down/up
  (left/right/other, with click count), drags, scroll wheel (pixel deltas). Mouse positions are **absolute global
  screen coordinates**.
- **Leading clean-up:** modifier *releases* left over from the start chord (e.g. letting go of `⌃⌘` after
  `⌃⌘M, a`) are dropped until the first real event.
- **Trailing clean-up:** the presses of the stop leader's modifiers at the end of the recording (e.g. pressing `⌃`,
  `⌘` just before `M`) are dropped, along with anything after them.
- **Leading gap** (start chord → first event) is dropped. **Trailing gap** (last kept event → start of stop chord)
  is kept and becomes a built-in wait at the end of every iteration.
- Stopping with nothing captured leaves the register unchanged (HUD: "empty — discarded").
- While recording, if Secure Event Input is active (password fields, some terminals), the HUD warns that keys are not
  being captured.
- Quitting or crashing mid-recording discards the partial recording.

## Playback

- Real timing, with global settings:
  - **Speed:** 1× / 2× / 4× (default 1×)
  - **Idle-gap cap:** off / 1 s / 3 s / 5 s (default off). Any single gap longer than the cap, including the trailing
    gap, is shortened to the cap.
  - **Inter-iteration gap:** extra fixed wait between repeats (default 0 ms, not affected by speed)
- Events are scheduled against a monotonic clock, relative to each iteration's start, so timing doesn't drift.
- Replayed events are tagged (`eventSourceUserData`) so the tap can tell them apart from physical input.
- **During playback, all physical input is blocked**, except:
  - physical `Esc` → abort
  - the `Play` leader → abort
- **Stuck-key safety:** when playback finishes or is aborted, the player sends key-up, mouse-up and modifier-release
  events for anything a macro left held.
- Playing an empty register shows "@a is empty" and does nothing.
- If Accessibility permission is revoked while running: stop everything, release held keys, return to the warning state.

## UI

- **Menu bar icon** states: idle, chord pending, recording, playing, needs permission.
- **HUD:** a small click-through floating panel (top-right of the main screen) shown while a chord is pending,
  recording or playing, and briefly for notices. Examples: `● REC @a`, `▶ @a 3/12 — Esc to stop`, `Play 12_`.
- **Menu:**
  - Status line
  - Register list: letter, optional label, duration, event count, recorded date. Each row has Play / Rename label… /
    Clear… actions.
  - "Grant Accessibility Access…" (only when missing)
  - Settings… (`⌘,`), Quit (`⌘Q`)
- No per-event editor in v1. Trimming is the first editor feature if one is needed.
- **Settings window:** record/play leader recorders, chord timeout, speed, idle-gap cap, inter-iteration gap, launch at
  login (`SMAppService`, default off). The engine is suspended while a shortcut recorder is capturing.
- **Permissions window:** shown on launch whenever Accessibility is missing. It explains why the permission is needed,
  has a button that triggers the system prompt / opens the right System Settings pane, polls, and closes itself once
  access is granted.

## Architecture

```
apps/mac (Macros.app)                     libs/core (MacrosCore, SwiftPM)
┌──────────────────────────────┐          ┌──────────────────────────────────┐
│ EventTap (tap thread)  ──────┼─ handle ─▶ MacroEngine  (chords, state)     │
│   CGEvent ⇄ MacroEvent       │          │   Recorder   (clean-up, gaps)    │
│ CGEventSink ◀────────────────┼── post ──┤   Player     (timing, held keys) │
│ KeyTranslator (layout chars) │          │   PlaybackSchedule (speed, caps) │
│ AppController / AppModel     │◀ status ─┤   RegisterBank / RegisterStore   │
│ MenuBarExtra, HUD, Settings  │          │   protocols: EventSink,          │
│ Permissions, AppSettings     │          │     TimeSource, PlaybackRunner   │
└──────────────────────────────┘          └──────────────────────────────────┘
```

- **Tap thread:** a dedicated thread with its own run loop hosts an *active* `CGEventTap` at the session level. The
  callback converts the event, asks the engine whether to swallow it, and returns. If macOS disables the tap
  (`tapDisabledByTimeout`/`ByUserInput`), it is re-enabled.
- **Player thread:** one thread per playback. It sleeps toward each event's deadline in ≤10 ms slices, checking a
  cancellation flag.
- **Engine:** lock-protected and callable from any thread. Callbacks (status, notices, starting playback) run outside
  the lock. UI updates hop to the main thread.
- **Swift 6 language mode** throughout. Thread-confined or lock-protected types are explicitly `@unchecked Sendable`.
- Logging: `os.Logger`, subsystem `dev.wuguishifu.macros`.

### Storage

- `~/Library/Application Support/Macros/registers/<letter>.json`, one file per register, written atomically on a
  background queue.
- Format:

  ```json
  {
    "schemaVersion": 1,
    "register": "a",
    "label": "github settings",
    "recordedAt": "2026-11-21T22:00:00Z",
    "trailingGapMs": 850,
    "events": [
      { "t": 0, "kind": "mouseMove", "flags": 256, "x": 812.5, "y": 440 },
      { "t": 120, "kind": "mouseDown", "flags": 256, "x": 812.5, "y": 440, "button": 0, "clickCount": 1 },
      { "t": 310, "kind": "keyDown", "flags": 1048840, "keyCode": 48 }
    ]
  }
  ```

  `t` is ms since the first event. `flags` is the raw `CGEventFlags`. Optional fields are omitted when unused. Files
  with a newer `schemaVersion` than the app understands are skipped.
- Settings live in `UserDefaults`.

## Permissions

- **Accessibility** is required for both the active (swallowing) event tap and posting events.
- macOS ties the grant to the code signature, so debug builds are signed with the Apple Development certificate for
  team `7C3LJCLXTY` to keep a stable identity across rebuilds.

## Repo

```
apps/mac/            Nx project "mac": XcodeGen project.yml, app sources, QA.md
libs/core/           Nx project "core": MacrosCore Swift package + tests
docs/spec.md         this file
```

Nx targets (`nx:run-commands`):

| Project | Targets |
|---|---|
| `mac` | `generate` (xcodegen), `build`, `run`, `lint`, `format`, `release` |
| `core` | `build`, `test`, `lint`, `format` |

- The generated `Macros.xcodeproj` is gitignored.
- Unit tests (Swift Testing) cover the engine/chords, recorder, schedule, player and storage, using fake
  `EventSink`/`TimeSource`/`PlaybackRunner`.
- The real tap, permissions and HUD are covered by the manual checklist in `apps/mac/QA.md`.
- CI is deferred until the app works locally.

## Deferred / future

- CI (GitHub Actions: lint/test/build on PR; run `mac:release` with API-key secrets on tag), Sparkle
- Website with download page (`apps/web`)
- Playing registers from inside a recording (as references, with recursion guards)
- Window-relative mouse coordinates
- Event editor (trim first)
