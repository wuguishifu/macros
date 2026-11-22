# Manual QA checklist

Unit tests cover the engine, recorder, timing and storage (`pnpm nx test core`). These checks cover what they can't:
the real event tap, permissions, posting events and the UI. Run `pnpm nx run mac:run` and go through them before a
release.

Logs: `/usr/bin/log stream --predicate 'subsystem == "dev.wuguishifu.macros"' --level debug`

## Permissions

- [ ] Fresh install (or `tccutil reset Accessibility dev.wuguishifu.macros`): the permissions window opens on launch
      and the menu bar icon shows ⚠.
- [ ] "Request Access" shows the system prompt. Granting access in System Settings closes the window within ~1 s, and
      the icon returns to normal.
- [ ] Rebuild and relaunch: access is still granted (stable signing identity).
- [ ] Revoke access while the app is running: the icon shows ⚠ within ~1 s and input is never stuck. Re-grant:
      capture resumes.

## Recording

- [ ] `⌃⌘M` shows "● Record into…" in the HUD. `Esc` cancels. Waiting 3 s cancels.
- [ ] `⌃⌘M, a` shows "● REC @a". Neither the `a` nor the `M` reaches the frontmost app.
- [ ] Type some text, click, drag and scroll, then `⌃⌘M`: the HUD says "Recorded @a" and the menu lists @a with a
      sensible duration and event count.
- [ ] The register file `~/Library/Application Support/Macros/registers/a.json` is readable JSON. It doesn't start
      with ⌃/⌘ releases and doesn't end with ⌃/⌘ presses.
- [ ] `⌃⌘M, ⇧A` appends: the duration grows and the HUD says "Appended to @a".
- [ ] Stopping straight away gives "Empty recording — @a unchanged", and the old macro is still intact.
- [ ] Focus a password field while recording: the HUD shows the secure-input warning.
- [ ] `⌃⌘N` while recording shows "Can't play while recording", and nothing plays.

## Playback

- [ ] `⌃⌘N, a` replays with the original timing. Mouse clicks land in the same places.
- [ ] `⌃⌘N, 3, a` shows "▶ @a 1/3" → "3/3" and repeats 3 times, honouring the trailing gap.
- [ ] `⌃⌘N, ⌃⌘N` replays the last register.
- [ ] Physical keys and clicks during playback are ignored. `Esc` stops it ("Playback stopped").
- [ ] Record a macro that holds ⌘ through a long pause and abort during the pause: ⌘ is not stuck afterwards.
- [ ] Speed 2×/4×, the idle cap and the gap between repeats in Settings visibly change playback.
- [ ] The GitHub-tabs scenario: open 3+ similar tabs, record "action + ⌃⇥" on one, play ×(N−1).

## Settings and menu

- [ ] Changing the record shortcut works immediately, and the old one no longer triggers. A shortcut without ⌘⌃⌥, or
      one equal to the other leader, is rejected.
- [ ] While the shortcut recorder is capturing, pressing the current leader doesn't start a recording.
- [ ] Rename sets a label shown in the menu. Clear… asks for confirmation, then removes the register and its file.
- [ ] Launch at login toggles and survives a relaunch.
- [ ] Quitting and relaunching keeps all registers.
- [ ] The HUD never steals focus or clicks, and appears on every Space and over full-screen apps.
