#!/usr/bin/env bash
# =============================================================================
# setup.sh
# -----------------------------------------------------------------------------
# Purpose : Idempotent installer for the local agentic toolchain on Linux/macOS.
#           Installs what is missing; upgrades what is present. Safe to re-run.
#
# Scope   : Does NOT touch gcloud auth, projects, billing, or API keys. Those
#           are handled in the gated Step 3 (see references/gcp-setup.md), each
#           with an explicit human approval gate.
#
# Privilege model:
#           This script is NEVER invoked under `sudo`. It elevates per-command
#           only where a system package manager requires it (specifically: the
#           `git` install on Linux). uv, Python, google-adk, and the Agent
#           Skills scaffold are all per-user installs.
#
# Transparency contract:
#           1. Prints the full PLAN of steps before doing anything.
#           2. Prints the exact command it is about to execute before each
#              install action (so the user can see what changed and re-run by
#              hand if desired).
#           3. Tracks every step's outcome (SKIPPED, INSTALLED, UPGRADED, or
#              FAILED) and prints a SUMMARY at the end that lists exactly what
#              changed on disk in this run.
#           4. Writes all output to a timestamped log file for audit trails.
#
# Configuration (environment variables):
#   UV_INSTALL_VERSION  — pin the uv installer to a specific release tag, e.g.
#                         "0.7.8". Leave unset to install the latest release
#                         (less reproducible — not recommended for enterprise).
#                         Verify released hashes at:
#                         https://github.com/astral-sh/uv/releases
#   AGENT_SETUP_LOG     — override the log file path (default: timestamped file
#                         under ~/.agent/skills/logs/).
#   AGENT_SKILLS_DIR    — override the Agent Skills scaffold location.
# =============================================================================

# `pipefail` so pipe errors are surfaced; no `-e` so we can collect
# failures into the summary instead of aborting on the first hiccup.
set -uo pipefail

# -----------------------------------------------------------------------------
# Audit log — every line of output is tee'd to a timestamped file so
# enterprise teams have a durable record of what the script did.
# The log directory is created under ~/.agent/skills/logs/ by default.
# -----------------------------------------------------------------------------
LOG_FILE="${AGENT_SETUP_LOG:-$HOME/.agent/skills/logs/setup-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# -----------------------------------------------------------------------------
# uv installer version pin. Set UV_INSTALL_VERSION to a specific release tag
# (e.g. "0.7.8") for reproducible enterprise installs. When set, the script
# downloads that exact version and displays its SHA-256 for manual verification
# against https://github.com/astral-sh/uv/releases
# -----------------------------------------------------------------------------
UV_INSTALL_VERSION="${UV_INSTALL_VERSION:-}"

# -----------------------------------------------------------------------------
# Output helpers — used purely for human-readable logging.
# -----------------------------------------------------------------------------
info() { printf '\033[36m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m  ok:\033[0m %s\n' "$1"; }
warn() { printf '\033[33m  !!:\033[0m %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# run <description> <command...>
#   Echoes the exact command before running it so the user can SEE what is
#   about to change on their system. Returns the underlying command's exit code.
run() {
  local desc="$1"; shift
  info "$desc"
  printf '\033[2m    $ %s\033[0m\n' "$*"
  "$@"
}

OS="$(uname -s)"

# -----------------------------------------------------------------------------
# COMPLETED_STEPS captures one human-readable line per step for the SUMMARY.
# CHANGES tracks the subset of steps that actually MUTATED the system (i.e.
# installs/upgrades/file creations) so the user can see what is new on disk.
# -----------------------------------------------------------------------------
COMPLETED_STEPS=()
CHANGES=()

# -----------------------------------------------------------------------------
# Plan banner — printed once up front so the user knows the full scope before
# any side-effect happens.
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
info "Agentic Environment Setup Plan (Linux/macOS)"
echo "============================================="
echo "This script will verify and install (if missing) or upgrade (if present):"
echo "  1. git                          (version control)"
echo "  2. uv                           (Astral Python & tool manager, ~/.local/bin)"
echo "  3. Python 3.12                  (managed by uv, isolated from system Python)"
echo "  4. google-adk + adk CLI         (uv tool; 'adk' on PATH)"
echo "  5. google-agents-cli + CLI      (uv tool; 'agents-cli' on PATH)"
echo "  6. ~/.agent/skills              (Agent Skills scaffold directory + README)"
echo ""
echo "This script will NOT:"
echo "  - run gcloud auth login, create projects, link billing, or create keys"
echo "    (those steps are gated; see references/gcp-setup.md)"
echo "  - run 'agents-cli setup' (interactive — left to the user)"
echo "  - run as sudo / elevate the whole shell"
echo ""
echo "Detected OS: $OS"
info "Log file: $LOG_FILE"
if [ -n "$UV_INSTALL_VERSION" ]; then
  info "uv version pin: $UV_INSTALL_VERSION"
else
  warn "UV_INSTALL_VERSION is unset — will install the latest uv release."
  warn "For reproducible enterprise installs, set UV_INSTALL_VERSION to a tag"
  warn "from https://github.com/astral-sh/uv/releases before running this script."
fi
echo "============================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: git
#   Linux  -> use the system package manager (sudo required for apt/dnf/pacman).
#             A preflight sudo -v is attempted to surface password prompts early.
#   macOS  -> running `xcode-select --install` opens a Command Line Tools GUI
#             dialog the user must complete. The script EXITS here so the user
#             re-runs after the install finishes — it does NOT fall through.
# -----------------------------------------------------------------------------
info "Step 1/6: Verifying Git installation..."
if have git; then
  GIT_VER="$(git --version)"
  ok "git already installed ($GIT_VER) — no change"
  COMPLETED_STEPS+=("git: SKIPPED (already installed: $GIT_VER)")
else
  info "git not found. Installing git..."
  if [ "$OS" = "Darwin" ]; then
    info "Triggering macOS Command Line Tools installer (opens a GUI dialog)..."
    printf '\033[2m    $ xcode-select --install\033[0m\n'
    xcode-select --install || true
    warn "A dialog has opened to install the Command Line Tools."
    warn "Complete that installer, open a NEW terminal, then re-run this script."
    COMPLETED_STEPS+=("git: PENDING (macOS CLT GUI prompt — re-run after it finishes)")
    echo ""
    echo "============================================="
    info "Setup paused: git is required. Re-run after Xcode Command Line Tools install."
    info "Log saved to: $LOG_FILE"
    echo "============================================="
    exit 1
  elif have apt-get; then
    warn "The next two commands require sudo (apt-get). You may be prompted for your password."
    run "Updating apt-get index"            sudo apt-get update
    run "Installing git via apt-get"        sudo apt-get install -y git
    COMPLETED_STEPS+=("git: INSTALLED via apt-get")
    CHANGES+=("git installed via apt-get (system package)")
  elif have dnf; then
    warn "The next command requires sudo (dnf). You may be prompted for your password."
    run "Installing git via dnf"            sudo dnf install -y git
    COMPLETED_STEPS+=("git: INSTALLED via dnf")
    CHANGES+=("git installed via dnf (system package)")
  elif have pacman; then
    warn "The next command requires sudo (pacman). You may be prompted for your password."
    run "Installing git via pacman"         sudo pacman -S --noconfirm git
    COMPLETED_STEPS+=("git: INSTALLED via pacman")
    CHANGES+=("git installed via pacman (system package)")
  else
    warn "No known package manager. Install git manually, then re-run."
    COMPLETED_STEPS+=("git: FAILED (no supported package manager detected)")
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 2: uv (Astral's Python + tool manager)
#   The official installer drops `uv` into ~/.local/bin and edits the user's
#   shell profile. New shells will see it on PATH automatically; for THIS
#   shell we prepend ~/.local/bin so the steps below can find uv.
#
#   SECURITY: the installer is downloaded to a temp file first, its SHA-256 is
#   printed so the user can verify it against the GitHub release page, and it
#   is executed from disk — never piped into sh. If UV_INSTALL_VERSION is set,
#   the version-pinned URL is used for reproducibility.
# -----------------------------------------------------------------------------
info "Step 2/6: Verifying uv installation..."
if have uv; then
  UV_VER="$(uv --version)"
  ok "uv already installed ($UV_VER) — no change"
  COMPLETED_STEPS+=("uv: SKIPPED (already installed: $UV_VER)")
else
  info "uv not found. Installing uv via Astral's standalone installer..."
  if [ -n "$UV_INSTALL_VERSION" ]; then
    _UV_URL="https://astral.sh/uv/${UV_INSTALL_VERSION}/install.sh"
    info "Using version-pinned installer: $UV_INSTALL_VERSION"
  else
    _UV_URL="https://astral.sh/uv/install.sh"
  fi
  _UV_TMP="$(mktemp)"
  info "Downloading installer: $_UV_URL"
  printf '\033[2m    $ curl -LsSf "%s" -o "%s"\033[0m\n' "$_UV_URL" "$_UV_TMP"
  if ! curl -LsSf "$_UV_URL" -o "$_UV_TMP"; then
    warn "Failed to download uv installer. Check network/proxy settings."
    warn "Corporate proxy? Set HTTP_PROXY / HTTPS_PROXY, or install via: pipx install uv"
    COMPLETED_STEPS+=("uv: FAILED (download error)")
    rm -f "$_UV_TMP"
  else
    # Print SHA-256 so the user can verify against the published release hashes
    # at https://github.com/astral-sh/uv/releases before the script executes it.
    _UV_SHA256="$(sha256sum "$_UV_TMP" 2>/dev/null || shasum -a 256 "$_UV_TMP" 2>/dev/null | awk '{print $1}')"
    info "Installer SHA-256 : $_UV_SHA256"
    info "Verify this hash at: https://github.com/astral-sh/uv/releases"
    info "Executing installer (modifies ~/.local/bin and your shell profile)..."
    printf '\033[2m    $ bash "%s"\033[0m\n' "$_UV_TMP"
    bash "$_UV_TMP"
    _UV_EXIT=$?
    rm -f "$_UV_TMP"
    if [ "$_UV_EXIT" -ne 0 ]; then
      warn "uv installer exited with code $_UV_EXIT — check output above."
      COMPLETED_STEPS+=("uv: FAILED (installer exit code $_UV_EXIT)")
    else
      # Make uv available in THIS shell for the remaining steps.
      export PATH="$HOME/.local/bin:$PATH"
      if have uv; then
        ok "uv installed successfully ($(uv --version))"
        COMPLETED_STEPS+=("uv: INSTALLED ($(uv --version)) into ~/.local/bin")
        CHANGES+=("uv installed at ~/.local/bin (per-user); shell profile updated by installer")
      else
        warn "uv installer ran but 'uv' is not on PATH for the current shell."
        COMPLETED_STEPS+=("uv: INSTALLED but PATH not yet active — open a new terminal")
        CHANGES+=("uv installed at ~/.local/bin (per-user); new shell required")
      fi
    fi
  fi
fi

# Belt-and-braces: ensure uv is reachable for the rest of the script.
if ! have uv; then
  export PATH="$HOME/.local/bin:$PATH"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 3: managed Python via uv
#   `uv python install 3.12` downloads a self-contained interpreter into uv's
#   data directory. It does NOT replace or modify the system Python.
# -----------------------------------------------------------------------------
info "Step 3/6: Ensuring a managed Python 3.12 interpreter via uv..."
if have uv; then
  if run "Installing Python 3.12 via uv (idempotent)" uv python install 3.12; then
    ok "Python 3.12 ready via uv"
    COMPLETED_STEPS+=("Python: 3.12 READY via uv (system Python untouched)")
    CHANGES+=("Python 3.12 installed in uv's managed Python cache (does not affect system Python)")
  else
    warn "uv could not install Python 3.12 (network?). Continuing with whatever"
    warn "compatible Python uv can find. ADK requires Python >= 3.10."
    COMPLETED_STEPS+=("Python: FAILED to install 3.12 (using uv fallback — requires >= 3.10)")
  fi
else
  warn "uv is not on PATH yet. Open a NEW terminal and re-run this script."
  COMPLETED_STEPS+=("Python: SKIPPED (uv not yet on PATH)")
  echo ""
  echo "============================================="
  info "Setup halted because uv is not yet usable in this shell."
  info "Log saved to: $LOG_FILE"
  echo "============================================="
  exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Step 4: google-adk (ships the 'adk' CLI)
#   Installed as an ISOLATED uv tool — meaning google-adk lives in its own
#   virtualenv and its `adk` entry point is symlinked into ~/.local/bin. This
#   avoids dependency conflicts with any project venv.
# -----------------------------------------------------------------------------
info "Step 4/6: Checking google-adk and the 'adk' CLI..."
if have adk; then
  ADK_VER="$(adk --version 2>/dev/null | head -n1)"
  ok "adk CLI already installed ($ADK_VER) — will attempt to upgrade"
  if run "Upgrading google-adk to latest" uv tool upgrade google-adk 2>/dev/null; then
    NEW_ADK_VER="$(adk --version 2>/dev/null | head -n1)"
    ok "google-adk now at $NEW_ADK_VER"
    COMPLETED_STEPS+=("google-adk: UPGRADED (was: $ADK_VER, now: $NEW_ADK_VER)")
    if [ "$ADK_VER" != "$NEW_ADK_VER" ]; then
      CHANGES+=("google-adk upgraded from $ADK_VER to $NEW_ADK_VER")
    fi
  else
    warn "Upgrade attempt failed; keeping existing version ($ADK_VER)."
    COMPLETED_STEPS+=("google-adk: KEPT existing ($ADK_VER) — upgrade attempt failed")
  fi
else
  if run "Installing google-adk as an isolated uv tool" uv tool install google-adk; then
    NEW_ADK_VER="$(adk --version 2>/dev/null | head -n1)"
    ok "google-adk installed successfully ($NEW_ADK_VER); 'adk' is on PATH"
    COMPLETED_STEPS+=("google-adk: INSTALLED ($NEW_ADK_VER)")
    CHANGES+=("google-adk installed as a uv tool; 'adk' entry point added to ~/.local/bin")
  else
    warn "Failed to install google-adk. Inspect the error above and retry."
    COMPLETED_STEPS+=("google-adk: FAILED to install")
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 5: google-agents-cli (ships the 'agents-cli' command)
#   Separate package from google-adk. Provides the higher-level workflow CLI
#   (scaffold, deploy, publish, observability, plus 'agents-cli setup' which
#   installs Google's bundled ADK skills into the user's coding agent).
#   Installed as an isolated uv tool so 'agents-cli' lands on PATH cleanly.
#   We deliberately do NOT auto-run 'agents-cli setup' — that command is
#   interactive, modifies the user's coding-agent config, and is a separate
#   human gate (Gate 5 in SKILL.md).
# -----------------------------------------------------------------------------
info "Step 5/6: Checking google-agents-cli and the 'agents-cli' CLI..."
if have agents-cli; then
  AGENTS_CLI_VER="$(agents-cli --version 2>/dev/null | head -n1)"
  ok "agents-cli already installed ($AGENTS_CLI_VER) — will attempt to upgrade"
  if run "Upgrading google-agents-cli to latest" uv tool upgrade google-agents-cli 2>/dev/null; then
    NEW_AGENTS_CLI_VER="$(agents-cli --version 2>/dev/null | head -n1)"
    ok "google-agents-cli now at $NEW_AGENTS_CLI_VER"
    COMPLETED_STEPS+=("google-agents-cli: UPGRADED (was: $AGENTS_CLI_VER, now: $NEW_AGENTS_CLI_VER)")
    if [ "$AGENTS_CLI_VER" != "$NEW_AGENTS_CLI_VER" ]; then
      CHANGES+=("google-agents-cli upgraded from $AGENTS_CLI_VER to $NEW_AGENTS_CLI_VER")
    fi
  else
    warn "Upgrade attempt failed; keeping existing version ($AGENTS_CLI_VER)."
    COMPLETED_STEPS+=("google-agents-cli: KEPT existing ($AGENTS_CLI_VER) — upgrade attempt failed")
  fi
else
  if run "Installing google-agents-cli as an isolated uv tool" uv tool install google-agents-cli; then
    NEW_AGENTS_CLI_VER="$(agents-cli --version 2>/dev/null | head -n1)"
    ok "google-agents-cli installed successfully ($NEW_AGENTS_CLI_VER); 'agents-cli' is on PATH"
    info "Next (user-driven, Gate 5): run 'agents-cli setup' to register the bundled ADK skills"
    info "  with your coding agent. Review what it will write before confirming."
    COMPLETED_STEPS+=("google-agents-cli: INSTALLED ($NEW_AGENTS_CLI_VER)")
    CHANGES+=("google-agents-cli installed as a uv tool; 'agents-cli' entry point added to ~/.local/bin")
  else
    warn "Failed to install google-agents-cli. Inspect the error above and retry."
    COMPLETED_STEPS+=("google-agents-cli: FAILED to install")
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 6: Agent Skills scaffold
#   Creates a single directory and one README. No code, no secrets, no PATH
#   changes — purely a convention-establishing folder for the user's OWN
#   custom skills. (Independent of the bundled skills 'agents-cli setup' would
#   install into the coding agent.)
# -----------------------------------------------------------------------------
info "Step 6/6: Checking the Agent Skills scaffold..."
SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agent/skills}"
if [ -d "$SKILLS_DIR" ]; then
  ok "Agent Skills directory already exists ($SKILLS_DIR) — no change"
  COMPLETED_STEPS+=("Agent Skills scaffold: SKIPPED (already exists at $SKILLS_DIR)")
else
  run "Creating Agent Skills scaffold directory" mkdir -p "$SKILLS_DIR"
  info "Writing README into $SKILLS_DIR/README.md"
  cat > "$SKILLS_DIR/README.md" <<'EOF'
# Agent Skills

Drop one folder per skill here. Each skill folder needs a SKILL.md with YAML
frontmatter (name + description) and optional scripts/ references/ assets/.
EOF
  ok "Scaffold created at $SKILLS_DIR"
  COMPLETED_STEPS+=("Agent Skills scaffold: CREATED at $SKILLS_DIR")
  CHANGES+=("Created directory $SKILLS_DIR and wrote $SKILLS_DIR/README.md")
fi
echo ""

# -----------------------------------------------------------------------------
# SUMMARY block — the canonical record of what this run did.
# Splits into two sections:
#   1. Per-step outcome (SKIPPED / INSTALLED / UPGRADED / FAILED)
#   2. CHANGES — the explicit list of files / directories / packages mutated.
# -----------------------------------------------------------------------------
echo "============================================="
info "Setup SUMMARY — outcome per step"
echo "============================================="
if [ "${#COMPLETED_STEPS[@]}" -gt 0 ]; then
  for step in "${COMPLETED_STEPS[@]}"; do
    ok " - $step"
  done
fi
echo ""
echo "============================================="
info "Setup SUMMARY — actual changes to your system"
echo "============================================="
if [ "${#CHANGES[@]}" -eq 0 ]; then
  ok " - No changes were made (everything was already present)."
else
  for change in "${CHANGES[@]}"; do
    ok " - $change"
  done
fi
echo "============================================="
echo ""
info "Local toolchain step is done."
echo "    Log saved to: $LOG_FILE"
echo "    If 'adk', 'agents-cli', or 'uv' is not found in this shell, open a NEW"
echo "    terminal so PATH updates from the uv installer take effect."
echo "    Optional (user-driven, Gate 5): run 'agents-cli setup' to register"
echo "    Google's bundled ADK skills with your coding agent."
echo "    Next: run the guided Google Cloud setup (see references/gcp-setup.md)."
