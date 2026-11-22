<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- For navigating/exploring the workspace, invoke the `nx-workspace` skill first - it has patterns for querying projects, targets, and dependencies
- When running tasks (for example build, lint, test, e2e, etc.), always prefer running the task through `nx` (i.e. `nx run`, `nx run-many`, `nx affected`) instead of using the underlying tooling directly
- Prefix nx commands with the workspace's package manager (e.g., `pnpm nx build`, `npm exec nx test`) - avoids using globally installed CLI
- You have access to the Nx MCP server and its tools, use them to help the user
- For Nx plugin best practices, check `node_modules/@nx/<plugin>/PLUGIN.md`. Not all plugins have this file - proceed without it if unavailable.
- NEVER guess CLI flags - always check nx_docs or `--help` first when unsure

## Scaffolding & Generators

- For scaffolding tasks (creating apps, libs, project structure, setup), ALWAYS invoke the `nx-generate` skill FIRST before exploring or calling MCP tools

## When to use nx_docs

- USE for: advanced config options, unfamiliar flags, migration guides, plugin configuration, edge cases
- DON'T USE for: basic generator syntax (`nx g @nx/react:app`), standard commands, things you already know
- The `nx-generate` skill handles generator discovery internally - don't call nx_docs just to look up generator syntax

<!-- nx configuration end-->

# Macros

macOS menu bar app for recording and replaying vim-style keyboard/mouse macros in registers. Full spec:
`docs/spec.md`. Read it before changing behaviour.

## Layout

- `libs/core/` (Nx `core`): `MacrosCore` Swift package. Engine/chord state machine, recorder, player, schedule,
  storage. No AppKit. All logic that can be unit-tested lives here.
- `apps/mac/` (Nx `mac`): the app. XcodeGen `project.yml` → `Macros.xcodeproj` (generated, gitignored). Event tap,
  CGEvent conversion, HUD, menu, settings, permissions. Manual checklist in `apps/mac/QA.md`.

## Commands

- `pnpm nx test core`: unit tests (Swift Testing)
- `pnpm nx run mac:build`: regenerates the Xcode project, then builds Debug into `dist/apps/mac`
- `pnpm nx run mac:run`: build, kill any running copy, launch
- `pnpm nx run-many -t lint` / `-t format`: `swift format` with the root `.swift-format`
- Requires Xcode 26+ and `xcodegen` (Homebrew)

## Conventions and gotchas

- Swift 6 language mode with complete strict concurrency. Types shared across the tap, player and main threads are
  lock-protected `@unchecked Sendable`. Keep the tap callback fast: macOS disables slow taps.
- Signing: always team `7C3LJCLXTY`. Never use the other Apple Development identity in the keychain. Debug builds
  must be dev-signed (not ad-hoc), or the Accessibility grant is lost on every rebuild.
- Events Macros posts are tagged with `SyntheticTag.value` in `eventSourceUserData`. The engine passes tagged events
  through and never records them.
- Register files are JSON with `schemaVersion`. Bump `Macro.currentSchemaVersion` and add migration if the format
  changes.
- `pnpm nx run mac:release` (`apps/mac/scripts/release.sh`): archive → Developer ID export → notarize + staple app → DMG → sign, notarize + staple DMG → `dist/apps/mac/release/Macros-<version>.{dmg,zip}`. Uses the `macros-notary` notarytool keychain profile, or `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` env vars (for CI). Bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `apps/mac/project.yml` per release.
- No CI yet.
