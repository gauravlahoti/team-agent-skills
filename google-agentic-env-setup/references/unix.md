# Linux + macOS reference

Exact commands and platform quirks. The `scripts/setup.sh` automates the
non-gated steps below; this file is the source of truth if you need to do a step
by hand or explain it.

When running these commands by hand (or having the agent run them on the user's
behalf), follow the SKILL.md transparency contract: announce the command, run
it, and then report what changed (e.g. *"Installed uv 0.4.x into
`~/.local/bin/uv` and added a line to `~/.zshrc`"*).

## Step order

1. **git** — package manager (`apt`/`dnf`/`pacman`) on Linux; on macOS, running
   `git` triggers the Command Line Tools installer (`xcode-select --install`),
   which is a GUI prompt the user must complete.
2. **uv** — official standalone installer, no sudo. `setup.sh` downloads the
   installer to a temp file, prints its SHA-256, and executes it from disk.
   Do NOT pipe it directly to sh. To pin a specific version set
   `UV_INSTALL_VERSION=0.7.8` (verify hashes at
   https://github.com/astral-sh/uv/releases). The installer edits your shell
   profile; `uv` only appears in new shells unless you
   `export PATH="$HOME/.local/bin:$PATH"` in the current one.
   To skip PATH edits: `UV_NO_MODIFY_PATH=1`. Self-update: `uv self update`.
3. **Python** — `uv python install 3.12` (minimum 3.10 required by ADK; 3.12 recommended).
   uv-managed interpreters are separate from any system Python and won't disturb it.
4. **google-adk + adk CLI** — install isolated so the CLI lands on PATH:
   ```
   uv tool install google-adk
   ```
   `google-adk` is the package; it provides both the importable `google.adk`
   library and the `adk` command. For extras (e.g. MCP, A2A, eval), the package
   exposes optional groups such as `google-adk[a2a]`, `[mcp]`, `[eval]`,
   `[gcp]`, `[all]`. Install an extra with
   `uv tool install "google-adk[mcp]"` only if the user asks for it.
5. **google-agents-cli + agents-cli command** — separate package, also isolated:
   ```
   uv tool install google-agents-cli
   ```
   This is the higher-level workflow CLI per
   https://google.github.io/agents-cli/guide/getting-started/ — used for
   scaffold, deploy, publish, and observability. Alternative install methods
   from the docs: `pipx install google-agents-cli`, `pip install
   google-agents-cli`, or the one-shot ephemeral `uvx google-agents-cli setup`.

   After install, an OPTIONAL user-driven step registers Google's bundled ADK
   skills with the user's coding agent (workflow, adk-code, scaffold, eval,
   deploy, publish, observability):
   ```
   agents-cli setup
   ```
   This command is interactive — do NOT auto-run it. Suggest it to the user.
6. **Agent Skills scaffold** — `~/.agent/skills` with a README explaining the
   one-folder-per-skill, SKILL.md-with-frontmatter convention. This is for the
   user's OWN custom skills and is independent of the bundled skills installed
   by `agents-cli setup`.
7. **gcloud** — see `gcp-setup.md`. On Linux/macOS the command is `gcloud`.

## Verify

```
git --version
uv --version
uv run python -c "import google.adk; print('adk import OK')"
adk --version
agents-cli --version
```

## Common snags

- **`adk: command not found` right after install** — open a new terminal, or
  `export PATH="$HOME/.local/bin:$PATH"`. uv tool binaries live there.
- **Corporate proxy / TLS** — set `HTTP_PROXY` / `HTTPS_PROXY` before running
  `setup.sh`, or install uv via `pipx install uv` from an internal package
  mirror. For a private PyPI index set `UV_INDEX_URL=https://your-mirror/simple`
  before running `uv tool install`.
- **Don't `sudo` the whole setup.** uv and adk are per-user installs; sudo would
  put them under root and break PATH expectations.
- **Verify uv installer hash** — `setup.sh` prints the SHA-256 of the downloaded
  installer. Cross-check it at https://github.com/astral-sh/uv/releases before
  allowing the install to proceed.
- **ADC credentials** — `gcloud auth application-default login` writes a
  long-lived token to `~/.config/gcloud/application_default_credentials.json`.
  Run `chmod 600` on that file and revoke with
  `gcloud auth application-default revoke` when no longer needed.
