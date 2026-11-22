# Macros

Vim-style keyboard and mouse macros for macOS. Record once into a register, then replay it as many times as you need.

| Keys | Does |
|---|---|
| `⌃⌘M`, `a` | Record into register `a` (`⇧A` appends) |
| `⌃⌘M` | Stop recording |
| `⌃⌘N`, `a` | Play `a` |
| `⌃⌘N`, `12`, `a` | Play `a` 12 times |
| `⌃⌘N`, `⌃⌘N` | Replay the last register |
| `Esc` | Cancel a chord / stop playback |

Lives in the menu bar. Requires macOS 14+ and Accessibility permission. Both shortcuts are configurable.

## Development

Requires Xcode 26+, pnpm and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
pnpm install
pnpm nx test core       # unit tests
pnpm nx run mac:run     # build and launch
pnpm nx run-many -t lint
```

See [`docs/spec.md`](docs/spec.md) for the full spec and [`apps/mac/QA.md`](apps/mac/QA.md) for the manual test
checklist.

## License

MIT
