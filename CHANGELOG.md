# Changelog

## [1.0.0] — 2026-05-20

### Added
- `google-agentic-env-setup` skill — enterprise-grade bootstrap for Google ADK
  development environments on Linux, macOS, and Windows (WSL 2).

### Security
- uv installer downloaded to temp file with SHA-256 display; no `curl | sh` or `irm | iex`.
- `UV_INSTALL_VERSION` env var for reproducible, pinned installs.
- API keys created with `--api-target` restrictions (not unrestricted).
- Key written directly from `gcloud` output to `chmod 600 .env` — never passes
  through shell arguments or history.
- `.gitignore` verified before key write; stale duplicate lines removed.
- ADC credentials location and revocation documented.
- Service account alternative documented for headless/CI environments.
- APT keyring `signed-by=` reference corrected for Debian/Ubuntu gcloud install.

### Changed
- Four human gates → five: `agents-cli setup` (coding-agent config mutation)
  added as Gate 5 with explicit pre-confirmation requirements.
- macOS git install now exits cleanly instead of silently falling through.
- PowerShell `setup.ps1` now checks `$LASTEXITCODE` after every native
  executable call (winget, uv, etc.) — fixes silent false-success bug.
- Full audit log added: `setup.sh` tees to `~/.agent/skills/logs/`; `setup.ps1`
  uses `Start-Transcript`.
- Verify step corrected: `adk run --help` replaces broken
  `uv run python -c "import google.adk"` (adk is a uv tool, not in project venv).
- Python minimum version clarified: 3.10 minimum, 3.12 recommended.
- `env-inspect` scripts now warn when system Python is below 3.10.
- `env-inspect.ps1` warns when only `gcloud.cmd` is present (not `gcloud`).
