# =============================================================================
# env-inspect.ps1
# -----------------------------------------------------------------------------
# Purpose : Read-only inspection of the agentic toolchain on Windows.
# Behavior: DETECTS state only. Never installs, modifies, or removes anything.
# Output  : Prints (a) what it is about to check, (b) per-component result,
#           (c) a final SUMMARY listing present components, missing components,
#           and any gcloud account/project context found.
# Exit    : Always 0 — the printed report is the product, not the exit code.
# Run     : powershell -ExecutionPolicy Bypass -File scripts/env-inspect.ps1
# =============================================================================

# Use SilentlyContinue so a missing tool does not throw — we want a clean report.
$ErrorActionPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# State tracked across the checks so we can show a clear SUMMARY at the end.
# -----------------------------------------------------------------------------
$present = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()

# -----------------------------------------------------------------------------
# Test-Tool <display-name> <command-on-PATH> <version-args>
#   - Prints a single line per component with [OK] or [--] and a version blurb.
#   - Records the outcome into $present / $missing for the SUMMARY block.
# -----------------------------------------------------------------------------
function Test-Tool($name, $cmd, $versionArgs) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        $ver = (& $cmd $versionArgs 2>$null | Select-Object -First 1)
        Write-Host ("  [OK] {0,-12} {1}" -f $name, $ver) -ForegroundColor Green
        $present.Add("$name ($ver)") | Out-Null
    } else {
        Write-Host ("  [--] {0,-12} not found" -f $name) -ForegroundColor Red
        $missing.Add($name) | Out-Null
    }
}

# -----------------------------------------------------------------------------
# Intro: tell the user exactly what this script will and will not do.
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================="
Write-Host "  Agentic Environment Inspector (read-only)" -ForegroundColor Cyan
Write-Host "============================================="
Write-Host "This diagnostic will inspect the following on your system:"
Write-Host "  - git, uv, python, adk, agents-cli, gcloud (presence + version)"
Write-Host "  - The Agent Skills scaffold directory"
Write-Host "  - gcloud's current account / project context (if gcloud is present)"
Write-Host ""
Write-Host "It will NOT install, modify, or remove anything."
Write-Host ("OS: Windows {0}" -f [System.Environment]::OSVersion.Version)
Write-Host "---------------------------------------------"

# -----------------------------------------------------------------------------
# Tool presence checks (in the same order as the install plan).
# -----------------------------------------------------------------------------
Test-Tool "git"    "git"    "--version"
Test-Tool "uv"     "uv"     "--version"
Test-Tool "python" "python" "--version"

# Validate that the system python (if present) meets the ADK minimum of 3.10.
# The uv-managed Python installed by setup.ps1 is separate and unaffected.
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyOk = (python -c "import sys; print('ok' if sys.version_info >= (3,10) else 'old')" 2>$null)
    if ($pyOk -eq "old") {
        $pyVer = (python -c "import sys; print(sys.version.split()[0])" 2>$null)
        Write-Host ("  [WRN] {0,-12} {1}" -f "python ver", "system python $pyVer is below ADK minimum (3.10); uv-managed Python (setup.ps1 step 3) is not affected") -ForegroundColor Yellow
    }
}

Test-Tool "adk"        "adk"        "--version"
Test-Tool "agents-cli" "agents-cli" "--version"
Test-Tool "gcloud"     "gcloud"     "--version"

# On Windows, gcloud may be installed as gcloud.cmd. Warn if only gcloud.cmd is
# found (common when gcloud was installed but not added to PATH as 'gcloud').
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    if (Get-Command gcloud.cmd -ErrorAction SilentlyContinue) {
        Write-Host ("  [WRN] {0,-12} {1}" -f "gcloud.cmd", "gcloud.cmd found but 'gcloud' is not on PATH — in deploy/automation contexts use 'gcloud.cmd'") -ForegroundColor Yellow
    }
}

Write-Host "---------------------------------------------"

# -----------------------------------------------------------------------------
# Agent Skills scaffold check. Resolves the directory the same way setup.ps1
# does so the two scripts agree on location.
# -----------------------------------------------------------------------------
$skillsDir = if ($env:AGENT_SKILLS_DIR) { $env:AGENT_SKILLS_DIR } else { Join-Path $env:USERPROFILE ".agent\skills" }
if (Test-Path $skillsDir) {
    Write-Host ("  [OK] {0,-12} {1}" -f "skills dir", $skillsDir) -ForegroundColor Green
    $present.Add("skills dir ($skillsDir)") | Out-Null
} else {
    Write-Host ("  [--] {0,-12} not created ({1})" -f "skills dir", $skillsDir) -ForegroundColor Red
    $missing.Add("skills dir") | Out-Null
}

# -----------------------------------------------------------------------------
# Read-only inspection of gcloud's current context (if gcloud is installed).
# Uses `gcloud config get-value` which never mutates state.
# -----------------------------------------------------------------------------
$gcloudAccount = ""
$gcloudProject = ""
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    $gcloudAccount = (gcloud config get-value account 2>$null)
    $gcloudProject = (gcloud config get-value project 2>$null)
    if ($gcloudAccount -and $gcloudAccount -ne "(unset)") {
        Write-Host ("       account: {0}" -f $gcloudAccount)
    }
    if ($gcloudProject -and $gcloudProject -ne "(unset)") {
        Write-Host ("       project: {0}" -f $gcloudProject)
    }
}

# -----------------------------------------------------------------------------
# SUMMARY block — gives the user a single place to see overall state and
# clearly indicates that nothing on disk was changed.
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================="
Write-Host "  Inspection SUMMARY" -ForegroundColor Cyan
Write-Host "============================================="
Write-Host ("Components PRESENT ({0}):" -f $present.Count)
if ($present.Count -eq 0) {
    Write-Host "  (none)"
} else {
    foreach ($item in $present) { Write-Host "  - $item" }
}
Write-Host ""
Write-Host ("Components MISSING ({0}):" -f $missing.Count)
if ($missing.Count -eq 0) {
    Write-Host "  (none — environment looks complete)"
} else {
    foreach ($item in $missing) { Write-Host "  - $item" }
}
Write-Host ""
if (($gcloudAccount -and $gcloudAccount -ne "(unset)") -or ($gcloudProject -and $gcloudProject -ne "(unset)")) {
    Write-Host "gcloud context:"
    if ($gcloudAccount -and $gcloudAccount -ne "(unset)") { Write-Host "  - account: $gcloudAccount" }
    if ($gcloudProject -and $gcloudProject -ne "(unset)") { Write-Host "  - project: $gcloudProject" }
    Write-Host ""
}
Write-Host "Changes made to your system by this script: NONE (read-only)."
if ($missing.Count -gt 0) {
    Write-Host "Next step: run scripts/setup.ps1 to install the MISSING components."
}
Write-Host "============================================="
Write-Host ""
