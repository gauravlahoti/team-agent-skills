# =============================================================================
# setup.ps1
# -----------------------------------------------------------------------------
# Purpose : Idempotent installer for the local agentic toolchain on Windows.
#           Installs what is missing; upgrades what is present. Safe to re-run.
#
# Scope   : Does NOT touch gcloud auth, projects, billing, or API keys. Those
#           are handled in the gated Step 3 (see references/gcp-setup.md), each
#           with an explicit human approval gate.
#
# Privilege model:
#           This script is NEVER invoked under Administrator. It elevates only
#           through `winget`, which prompts the user itself. uv, Python,
#           google-adk, and the Agent Skills scaffold are all per-user installs.
#
# Transparency contract:
#           1. Prints the full PLAN of steps before doing anything.
#           2. Prints the exact command it is about to execute before each
#              install action (so the user can see what changed and re-run by
#              hand if desired).
#           3. Tracks every step's outcome (SKIPPED, INSTALLED, UPGRADED, or
#              FAILED) and prints a SUMMARY at the end that lists exactly what
#              changed on disk in this run.
#           4. Writes all output to a transcript log file for audit trails.
#
# Configuration (environment variables):
#   UV_INSTALL_VERSION  — pin the uv installer to a specific release, e.g.
#                         "0.7.8". Leave unset for latest (less reproducible;
#                         not recommended for enterprise). Verify hashes at:
#                         https://github.com/astral-sh/uv/releases
#   AGENT_SETUP_LOG     — override the log file path.
#   AGENT_SKILLS_DIR    — override the Agent Skills scaffold location.
#
# Run     : powershell -ExecutionPolicy Bypass -File scripts/setup.ps1
# =============================================================================

# Stop on cmdlet errors so failures are surfaced; external executables are
# checked via $LASTEXITCODE after each call (PowerShell does not auto-throw
# on non-zero exit codes from native tools).
$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Output helpers — used purely for human-readable logging.
# -----------------------------------------------------------------------------
function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  ok: $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !!: $m" -ForegroundColor Yellow }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Show-Cmd($cmd) { Write-Host "    > $cmd" -ForegroundColor DarkGray }

# Assert-ExitCode — call immediately after every native executable to convert
# non-zero exit codes into thrown exceptions that try/catch can handle.
function Assert-ExitCode($description) {
    if ($LASTEXITCODE -ne 0) {
        throw "$description exited with code $LASTEXITCODE"
    }
}

# -----------------------------------------------------------------------------
# Audit log — Start-Transcript captures all output (stdout + stderr) to a
# timestamped file. This gives enterprise teams a complete audit trail.
# -----------------------------------------------------------------------------
$logDir  = if ($env:AGENT_SETUP_LOG) { Split-Path $env:AGENT_SETUP_LOG } `
           else { Join-Path $env:USERPROFILE ".agent\skills\logs" }
$logFile = if ($env:AGENT_SETUP_LOG) { $env:AGENT_SETUP_LOG } `
           else { Join-Path $logDir ("setup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log") }
New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -Path $logFile -Append

# -----------------------------------------------------------------------------
# uv version pin. Set the UV_INSTALL_VERSION env var to a specific release tag
# (e.g. "0.7.8") for reproducible enterprise installs.
# -----------------------------------------------------------------------------
$uvInstallVersion = $env:UV_INSTALL_VERSION

# -----------------------------------------------------------------------------
# Track every step's outcome (for the per-step SUMMARY) and the subset of
# steps that actually MUTATED the system (for the changes-on-disk SUMMARY).
# -----------------------------------------------------------------------------
$completedSteps = [System.Collections.Generic.List[string]]::new()
$changes        = [System.Collections.Generic.List[string]]::new()

# -----------------------------------------------------------------------------
# Plan banner — printed once up front so the user knows the full scope before
# any side-effect happens.
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================="
Info "Agentic Environment Setup Plan (Windows)"
Write-Host "============================================="
Write-Host "This script will verify and install (if missing) or upgrade (if present):"
Write-Host "  1. git                            (via winget, Git.Git)"
Write-Host "  2. uv                             (Astral Python & tool manager, %USERPROFILE%\.local\bin)"
Write-Host "  3. Python 3.12                    (managed by uv, isolated from system Python)"
Write-Host "  4. google-adk + adk CLI           (uv tool; 'adk.exe' on PATH)"
Write-Host "  5. google-agents-cli + CLI        (uv tool; 'agents-cli.exe' on PATH)"
Write-Host "  6. %USERPROFILE%\.agent\skills    (Agent Skills scaffold directory + README)"
Write-Host ""
Write-Host "This script will NOT:"
Write-Host "  - run gcloud auth login, create projects, link billing, or create keys"
Write-Host "    (those steps are gated; see references/gcp-setup.md)"
Write-Host "  - run 'agents-cli setup' (interactive, Gate 5 — left to the user)"
Write-Host "  - run as Administrator / elevate the whole shell"
Write-Host ""
Warn "Per Google docs, google-agents-cli is officially supported on macOS, Linux,"
Warn "and Windows via WSL 2. Native PowerShell is NOT officially supported."
Warn "This script will still attempt the install on native Windows; if you hit"
Warn "issues, switch to a WSL 2 shell and re-run scripts/setup.sh there."
Write-Host ""
Write-Host ("Detected OS: Windows {0}" -f [System.Environment]::OSVersion.Version)
Info "Log file: $logFile"
if ($uvInstallVersion) {
    Info "uv version pin: $uvInstallVersion"
} else {
    Warn "UV_INSTALL_VERSION is unset — will install the latest uv release."
    Warn "For reproducible enterprise installs, set UV_INSTALL_VERSION to a tag"
    Warn "from https://github.com/astral-sh/uv/releases before running this script."
}
Write-Host "============================================="
Write-Host ""

# -----------------------------------------------------------------------------
# Step 1: git
#   Installed via winget (ships on Windows 10/11). winget prompts for any
#   elevation it needs; this script does not.
#   NOTE: winget does NOT refresh the current session's PATH. After installing
#   git, the user must open a new terminal to use the git command.
# -----------------------------------------------------------------------------
Info "Step 1/6: Verifying Git installation..."
if (Have git) {
    $gitVer = (git --version)
    Assert-ExitCode "git --version"
    Ok "git already installed ($gitVer) — no change"
    $completedSteps.Add("git: SKIPPED (already installed: $gitVer)")
} else {
    Info "git not found. Installing git via winget..."
    if (Have winget) {
        try {
            Show-Cmd "winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements"
            winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
            Assert-ExitCode "winget install Git.Git"
            $completedSteps.Add("git: INSTALLED via winget")
            $changes.Add("git installed via winget (Git.Git)")
            Warn "git was just installed. Open a NEW terminal before using the git command."
        } catch {
            Warn "Failed to install git via winget: $_"
            $completedSteps.Add("git: FAILED (winget install error: $_)")
        }
    } else {
        Warn "winget not available. Install Git from https://git-scm.com/download/win then re-run."
        $completedSteps.Add("git: FAILED (winget not present)")
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# Step 2: uv (Astral's Python + tool manager)
#   The official installer drops `uv.exe` into %USERPROFILE%\.local\bin and
#   edits the user PATH. New shells will see uv automatically; for THIS shell
#   we prepend the bin directory so the steps below can find uv.
#
#   SECURITY: the installer is downloaded to a temp file first, its SHA-256 is
#   printed so the user can verify it against the GitHub release page, and it
#   is executed from disk — not piped into iex. If UV_INSTALL_VERSION is set,
#   the version-pinned URL is used for reproducibility.
# -----------------------------------------------------------------------------
Info "Step 2/6: Verifying uv installation..."
if (Have uv) {
    $uvVer = (uv --version)
    Assert-ExitCode "uv --version"
    Ok "uv already installed ($uvVer) — no change"
    $completedSteps.Add("uv: SKIPPED (already installed: $uvVer)")
} else {
    Info "uv not found. Installing uv via Astral's standalone installer..."
    if ($uvInstallVersion) {
        $uvUrl = "https://astral.sh/uv/$uvInstallVersion/install.ps1"
        Info "Using version-pinned installer: $uvInstallVersion"
    } else {
        $uvUrl = "https://astral.sh/uv/install.ps1"
    }
    $uvTmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("uv-install-" + [System.Guid]::NewGuid().ToString("N") + ".ps1")
    try {
        Info "Downloading: $uvUrl"
        Show-Cmd "Invoke-WebRequest -Uri '$uvUrl' -OutFile '$uvTmpFile' -UseBasicParsing"
        Invoke-WebRequest -Uri $uvUrl -OutFile $uvTmpFile -UseBasicParsing
        # Compute and display SHA-256 for manual verification
        $hash = (Get-FileHash -Path $uvTmpFile -Algorithm SHA256).Hash
        Info "Installer SHA-256 : $hash"
        Info "Verify this hash at: https://github.com/astral-sh/uv/releases"
        Info "Executing installer (modifies %USERPROFILE%\.local\bin and user PATH)..."
        Show-Cmd "powershell -ExecutionPolicy Bypass -File '$uvTmpFile'"
        powershell -ExecutionPolicy Bypass -File $uvTmpFile
        Assert-ExitCode "uv installer"
        Remove-Item -Force $uvTmpFile -ErrorAction SilentlyContinue
        # Make uv available in THIS shell for the remaining steps.
        $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
        if (Have uv) {
            $uvVer = (uv --version)
            Ok "uv installed successfully ($uvVer)"
            $completedSteps.Add("uv: INSTALLED ($uvVer) into %USERPROFILE%\.local\bin")
            $changes.Add("uv installed at %USERPROFILE%\.local\bin (per-user); user PATH updated by installer")
        } else {
            Warn "uv installer ran but 'uv' is not on PATH for the current shell."
            $completedSteps.Add("uv: INSTALLED but PATH not yet active — open a new terminal")
            $changes.Add("uv installed at %USERPROFILE%\.local\bin (per-user); new shell required")
        }
    } catch {
        Warn "Failed to install uv: $_"
        Warn "Corporate proxy? Set HTTP_PROXY / HTTPS_PROXY, or install via: pip install uv"
        Remove-Item -Force $uvTmpFile -ErrorAction SilentlyContinue
        $completedSteps.Add("uv: FAILED ($_)")
    }
}

# Belt-and-braces: ensure uv is reachable for the rest of the script.
if (-not (Have uv)) { $env:Path = "$env:USERPROFILE\.local\bin;$env:Path" }
Write-Host ""

# -----------------------------------------------------------------------------
# Step 3: managed Python via uv
#   `uv python install 3.12` downloads a self-contained interpreter into uv's
#   data directory. It does NOT replace or modify the system Python.
# -----------------------------------------------------------------------------
Info "Step 3/6: Ensuring a managed Python 3.12 interpreter via uv..."
if (Have uv) {
    try {
        Show-Cmd "uv python install 3.12"
        uv python install 3.12
        Assert-ExitCode "uv python install 3.12"
        Ok "Python 3.12 ready via uv"
        $completedSteps.Add("Python: 3.12 READY via uv (system Python untouched)")
        $changes.Add("Python 3.12 installed in uv's managed Python cache (does not affect system Python)")
    } catch {
        Warn "Failed to install Python 3.12 via uv: $_"
        Warn "ADK requires Python >= 3.10."
        $completedSteps.Add("Python: FAILED to install 3.12 via uv ($_)")
    }
} else {
    Warn "uv is not on PATH yet. Open a NEW terminal and re-run this script."
    $completedSteps.Add("Python: SKIPPED (uv not yet on PATH)")
    Write-Host ""
    Write-Host "============================================="
    Info "Setup halted because uv is not yet usable in this shell."
    Info "Log saved to: $logFile"
    Write-Host "============================================="
    Stop-Transcript
    exit 0
}
Write-Host ""

# -----------------------------------------------------------------------------
# Step 4: google-adk (ships the 'adk' CLI)
#   Installed as an ISOLATED uv tool — meaning google-adk lives in its own
#   virtualenv and its `adk.exe` entry point is in the uv tool bin directory.
# -----------------------------------------------------------------------------
Info "Step 4/6: Checking google-adk and the 'adk' CLI..."
if (Have adk) {
    $adkVer = (adk --version 2>$null | Select-Object -First 1)
    Ok "adk CLI already installed ($adkVer) — will attempt to upgrade"
    try {
        Show-Cmd "uv tool upgrade google-adk"
        uv tool upgrade google-adk
        Assert-ExitCode "uv tool upgrade google-adk"
        $newAdkVer = (adk --version 2>$null | Select-Object -First 1)
        Ok "google-adk now at $newAdkVer"
        $completedSteps.Add("google-adk: UPGRADED (was: $adkVer, now: $newAdkVer)")
        if ($adkVer -ne $newAdkVer) {
            $changes.Add("google-adk upgraded from $adkVer to $newAdkVer")
        }
    } catch {
        Warn "Failed to upgrade google-adk; keeping existing version ($adkVer): $_"
        $completedSteps.Add("google-adk: KEPT existing ($adkVer) — upgrade attempt failed")
    }
} else {
    try {
        Show-Cmd "uv tool install google-adk"
        uv tool install google-adk
        Assert-ExitCode "uv tool install google-adk"
        $newAdkVer = (adk --version 2>$null | Select-Object -First 1)
        Ok "google-adk installed successfully ($newAdkVer); 'adk.exe' is on PATH"
        $completedSteps.Add("google-adk: INSTALLED ($newAdkVer)")
        $changes.Add("google-adk installed as a uv tool; 'adk.exe' entry point added")
    } catch {
        Warn "Failed to install google-adk: $_"
        $completedSteps.Add("google-adk: FAILED to install ($_)")
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# Step 5: google-agents-cli (ships the 'agents-cli' command)
#   Separate package from google-adk. Provides the higher-level workflow CLI.
#   We deliberately do NOT auto-run 'agents-cli setup' — that command is
#   interactive, modifies the user's coding-agent config, and is a separate
#   human gate (Gate 5 in SKILL.md).
#
#   NOTE: Per Google docs, native Windows is not officially supported (WSL 2
#   is the supported path). We still attempt the install here.
# -----------------------------------------------------------------------------
Info "Step 5/6: Checking google-agents-cli and the 'agents-cli' CLI..."
if (Have agents-cli) {
    $agentsCliVer = (agents-cli --version 2>$null | Select-Object -First 1)
    Ok "agents-cli already installed ($agentsCliVer) — will attempt to upgrade"
    try {
        Show-Cmd "uv tool upgrade google-agents-cli"
        uv tool upgrade google-agents-cli
        Assert-ExitCode "uv tool upgrade google-agents-cli"
        $newAgentsCliVer = (agents-cli --version 2>$null | Select-Object -First 1)
        Ok "google-agents-cli now at $newAgentsCliVer"
        $completedSteps.Add("google-agents-cli: UPGRADED (was: $agentsCliVer, now: $newAgentsCliVer)")
        if ($agentsCliVer -ne $newAgentsCliVer) {
            $changes.Add("google-agents-cli upgraded from $agentsCliVer to $newAgentsCliVer")
        }
    } catch {
        Warn "Failed to upgrade google-agents-cli; keeping existing version ($agentsCliVer): $_"
        $completedSteps.Add("google-agents-cli: KEPT existing ($agentsCliVer) — upgrade attempt failed")
    }
} else {
    try {
        Show-Cmd "uv tool install google-agents-cli"
        uv tool install google-agents-cli
        Assert-ExitCode "uv tool install google-agents-cli"
        $newAgentsCliVer = (agents-cli --version 2>$null | Select-Object -First 1)
        Ok "google-agents-cli installed successfully ($newAgentsCliVer); 'agents-cli.exe' is on PATH"
        Info "Next (user-driven, Gate 5): run 'agents-cli setup' to register the bundled ADK skills"
        Info "  with your coding agent. Review what it will write before confirming."
        $completedSteps.Add("google-agents-cli: INSTALLED ($newAgentsCliVer)")
        $changes.Add("google-agents-cli installed as a uv tool; 'agents-cli.exe' entry point added")
    } catch {
        Warn "Failed to install google-agents-cli: $_"
        Warn "Native Windows is not officially supported; if this persists, retry from WSL 2."
        $completedSteps.Add("google-agents-cli: FAILED to install (try WSL 2 if on native Windows)")
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# Step 6: Agent Skills scaffold
#   Creates a single directory and one README. No code, no secrets, no PATH
#   changes — purely a convention-establishing folder for the user's OWN
#   custom skills.
# -----------------------------------------------------------------------------
Info "Step 6/6: Checking the Agent Skills scaffold..."
$skillsDir = if ($env:AGENT_SKILLS_DIR) { $env:AGENT_SKILLS_DIR } else { Join-Path $env:USERPROFILE ".agent\skills" }
if (Test-Path $skillsDir) {
    Ok "Agent Skills directory already exists ($skillsDir) — no change"
    $completedSteps.Add("Agent Skills scaffold: SKIPPED (already exists at $skillsDir)")
} else {
    try {
        Show-Cmd "New-Item -ItemType Directory -Path $skillsDir -Force"
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
        Info "Writing README into $skillsDir\README.md"
@"
# Agent Skills

Drop one folder per skill here. Each skill folder needs a SKILL.md with YAML
frontmatter (name + description) and optional scripts/ references/ assets/.
"@ | Set-Content -Path (Join-Path $skillsDir "README.md")
        Ok "Scaffold created at $skillsDir"
        $completedSteps.Add("Agent Skills scaffold: CREATED at $skillsDir")
        $changes.Add("Created directory $skillsDir and wrote $skillsDir\README.md")
    } catch {
        Warn "Failed to create Agent Skills scaffold: $_"
        $completedSteps.Add("Agent Skills scaffold: FAILED to create ($_)")
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# SUMMARY block — the canonical record of what this run did.
# Splits into two sections:
#   1. Per-step outcome (SKIPPED / INSTALLED / UPGRADED / FAILED)
#   2. CHANGES — the explicit list of files / directories / packages mutated.
# -----------------------------------------------------------------------------
Write-Host "============================================="
Info "Setup SUMMARY — outcome per step"
Write-Host "============================================="
foreach ($step in $completedSteps) { Ok " - $step" }
Write-Host ""
Write-Host "============================================="
Info "Setup SUMMARY — actual changes to your system"
Write-Host "============================================="
if ($changes.Count -eq 0) {
    Ok " - No changes were made (everything was already present)."
} else {
    foreach ($change in $changes) { Ok " - $change" }
}
Write-Host "============================================="
Write-Host ""
Info "Local toolchain step is done."
Write-Host "    Log saved to: $logFile"
Write-Host "    If 'adk', 'agents-cli', or 'uv' is not found in this shell, open a NEW"
Write-Host "    terminal so PATH updates from the uv installer take effect."
Write-Host "    Optional (user-driven, Gate 5): run 'agents-cli setup' to register"
Write-Host "    Google's bundled ADK skills with your coding agent."
Write-Host "    Next: run the guided Google Cloud setup (see references/gcp-setup.md)."

Stop-Transcript
