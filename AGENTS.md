# Repository Guidelines

## Project Structure & Module Organization
- Source lives at the root in `sp3arbr3aker.lua` (Roblox LocalScript).
- If you split code, use `src/` for reusable modules and keep the entrypoint at root:
  - Examples: `src/ui.lua`, `src/aim.lua`, `src/esp.lua`; require them from `sp3arbr3aker.lua`.
- Keep module names descriptive and short; prefer `sb3_<area>.lua` for internal modules.

## Build, Test, and Development Commands
- Build: none. This script runs directly in Roblox Studio.
- Run (Studio): place `sp3arbr3aker.lua` as a LocalScript under `StarterPlayerScripts` or `PlayerGui`, then click Play. The guide header “Sp3arBr3ak3r 1.12b” should appear.
- Format (optional): `stylua sp3arbr3aker.lua` or `stylua .`
- Lint (optional): `luacheck sp3arbr3aker.lua`

## Coding Style & Naming Conventions
- Indentation: tabs; target ≤100‑char lines; no trailing whitespace.
- Constants: `UPPER_SNAKE_CASE` (e.g., `ESP_ENABLED`, `SP3AR_MAX_RANGE`).
- Locals/functions: `lowerCamelCase` (e.g., `ensureGuide`, `safeDestroy`, `disconnectAll`).
- Roblox services: keep canonical names (`Players`, `RunService`, `Lighting`).
- Patterns: small helpers, explicit side effects, `pcall` for destructive operations, nil‑checks before access.

## Testing Guidelines
- Manual smoke tests in Studio:
  - Toggles: `Ctrl+E` ESP, `Ctrl+Enter` Br3ak3r, `Ctrl+K` AutoClick, `Ctrl+H` Headshot, `Ctrl+C` Auto‑F, `Ctrl+L` Sky, `Ctrl+F` Sp3ar, `Ctrl+6` Killswitch.
  - Verify MouseBehavior restores on release/killswitch and no orphaned instances remain (Explorer clean; connections disconnected).
- Performance: avoid per‑frame allocations; reuse UI elements; keep expensive queries off render‑step when possible.
- Unit tests: not configured; PRs adding TestEZ for pure helpers are welcome (avoid Roblox‑specific globals in unit tests).

## Commit & Pull Request Guidelines
- Commits: follow Conventional Commits (e.g., `feat:`, `fix:`, `refactor:`, `docs:`); keep diffs focused.
- PRs must include: clear description, before/after behavior, any keybind/UX changes, test notes (Studio version, scenarios), and screenshots/short clips when UI changes.
- Backward compatibility: maintain existing keybinds and defaults; call out breaking changes in the PR title.

## Security & Configuration Tips
- Client‑only: do not add network calls, remote loaders, or server‑side assumptions.
- Cleanup: ensure killswitch fully disconnects connections and destroys created instances.
- Respect Roblox ToS; use responsibly for educational/testing in controlled environments.
