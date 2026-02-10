# matrix-slack-bridge - issues

## 2026-02-10
- `make check` runs `nix flake check --all-systems` (via `modules/commands.nix`) and can fail on linux if darwin outputs require unavailable system features. For local verification, `nix flake check --impure` (current system only) succeeds.
