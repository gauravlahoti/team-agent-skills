# Windows reference

Exact commands and quirks. `scripts/setup.ps1` automates the non-gated steps.
Run scripts with `powershell -ExecutionPolicy Bypass -File <script>` so an
unsigned local script can run without changing the machine's global policy.

When running these commands by hand (or having the agent run them on the user's
behalf), follow the SKILL.md transparency contract: announce the command, run
it, and then report what changed (e.g. *"Installed uv into
`%USERPROFILE%\.local\bin\uv.exe` and prepended it to the user PATH"*).

## Step order

1. **git** — via winget (ships on Windows 10/11):
   ```
   winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
   ```
   If winget is absent, install from https://git-scm.com/download/win.
   **Important:** winget does NOT refresh the current session's PATH. Open a
   new terminal after installing git before using it.
2. **uv** — `setup.ps1` downloads the official installer to a temp `.ps1` file,
   prints its SHA-256, and executes it from disk. Do NOT pipe it via `iex`.
   To pin a version set the env var `UV_INSTALL_VERSION=0.7.8` (verify hashes
   at https://github.com/astral-sh/uv/releases). Installs `uv.exe` to
   `%USERPROFILE%\.local\bin`. PATH updates apply to *new* shells; for the
   current session prepend `$env:Path = "$env:USERPROFILE\.local\bin;$env:Path"`.
3. **Python** — `uv python install 3.12`.
4. **google-adk + adk CLI** — `uv tool install google-adk` (puts `adk.exe` on
   PATH). Same package/extras notes as the Unix reference.
5. **google-agents-cli + agents-cli command** — `uv tool install
   google-agents-cli` (puts `agents-cli.exe` on PATH).

   **WSL 2 caveat.** Per
   https://google.github.io/agents-cli/guide/getting-started/, the officially
   supported Windows path for `google-agents-cli` is **WSL 2**, not native
   PowerShell. The install command above usually works on native Windows, but
   if it fails or behaves unexpectedly, retry from a WSL 2 shell using
   `scripts/setup.sh`.

   Optional user-driven follow-on (interactive — do not auto-run):
   ```
   agents-cli setup
   ```
   Registers Google's bundled ADK skills with the user's coding agent.
6. **Agent Skills scaffold** — `%USERPROFILE%\.agent-skills`. This is for the
   user's OWN custom skills and is independent of the bundled skills installed
   by `agents-cli setup`.
7. **gcloud** — see `gcp-setup.md`. **On Windows, deployment/automation contexts
   may need `gcloud.cmd` instead of `gcloud`** (notably when invoked by tools like
   ADK's deploy commands). Interactive shell use of `gcloud` is fine.

## Verify

```
git --version
uv --version
uv run python -c "import google.adk; print('adk import OK')"
adk --version
agents-cli --version
```

## Common snags

- **`adk` or `git` not recognized after install** — open a new terminal so the
  PATH edit takes effect. winget and uv installs do not refresh the current
  session's PATH.
- **Execution policy errors** — use the `-ExecutionPolicy Bypass` flag on the
  invocation rather than changing `Set-ExecutionPolicy` machine-wide.
- **winget missing on older builds** — update App Installer from the Microsoft
  Store, or install git manually.
- **Corporate proxy / TLS** — set `HTTP_PROXY` / `HTTPS_PROXY` before running
  `setup.ps1`, or set `UV_INDEX_URL` for a private PyPI mirror.
- **Verify uv installer hash** — `setup.ps1` prints the SHA-256 of the
  downloaded installer. Cross-check it at
  https://github.com/astral-sh/uv/releases before confirming the install.
- **Don't run the whole thing as Administrator.** These are per-user installs.
- **`gcloud` vs `gcloud.cmd`** — in deploy/automation contexts on Windows the
  command is `gcloud.cmd`. Interactive shell use of `gcloud` is fine.
  `env-inspect.ps1` will warn if `gcloud.cmd` is present but `gcloud` is not.
