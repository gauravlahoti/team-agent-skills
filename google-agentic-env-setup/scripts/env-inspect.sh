#!/usr/bin/env bash
# =============================================================================
# env-inspect.sh
# -----------------------------------------------------------------------------
# Purpose : Read-only inspection of the agentic toolchain on Linux / macOS.
# Behavior: DETECTS state only. Never installs, modifies, or removes anything.
# Output  : Prints (a) what it is about to check, (b) per-component result,
#           (c) a final SUMMARY listing present components, missing components,
#           and any gcloud account/project context found.
# Exit    : Always 0 — the printed report is the product, not the exit code.
# Re-run  : Safe at any time; the script touches no files on disk.
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Color helpers. Used purely for human-readable output; no behavioral effect.
# -----------------------------------------------------------------------------
green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }
bold()  { printf '\033[1m%s\033[0m' "$1"; }

# -----------------------------------------------------------------------------
# State tracked across the checks so we can show a clear SUMMARY at the end.
# PRESENT / MISSING are flat arrays of "name|version" or "name" entries.
# -----------------------------------------------------------------------------
PRESENT=()
MISSING=()

# -----------------------------------------------------------------------------
# check <display-name> <command-on-PATH> <version-command>
#   - Prints a single line per component with [OK] or [--] and a version blurb.
#   - Records the outcome into PRESENT / MISSING for the SUMMARY block.
# -----------------------------------------------------------------------------
check() {
  local name="$1" cmd="$2" version_cmd="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver="$(eval "$version_cmd" 2>/dev/null | head -n1)"
    printf '  [%s] %-12s %s\n' "$(green OK)" "$name" "$(dim "${ver:-installed}")"
    PRESENT+=("$name (${ver:-installed})")
  else
    printf '  [%s] %-12s %s\n' "$(red '--')" "$name" "$(dim 'not found')"
    MISSING+=("$name")
  fi
}

# -----------------------------------------------------------------------------
# Intro: tell the user exactly what this script will and will not do.
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
bold "  Agentic Environment Inspector (read-only)"; echo ""
echo "============================================="
echo "This diagnostic will inspect the following on your system:"
echo "  - git, uv, python3, adk, agents-cli, gcloud (presence + version)"
echo "  - The Agent Skills scaffold directory"
echo "  - gcloud's current account / project context (if gcloud is present)"
echo ""
echo "It will NOT install, modify, or remove anything."
echo "OS: $(uname -s) $(uname -m)"
echo "---------------------------------------------"

# -----------------------------------------------------------------------------
# Tool presence checks (in the same order as the install plan).
# -----------------------------------------------------------------------------
check "git"      "git"     "git --version"
check "uv"       "uv"      "uv --version"
check "python"   "python3" "python3 --version"

# Validate that the system python3 (if present) meets the ADK minimum of 3.10.
# The uv-managed Python installed by setup.sh is separate and unaffected by this.
if command -v python3 >/dev/null 2>&1; then
  _PY_OK="$(python3 -c 'import sys; print("ok" if sys.version_info >= (3,10) else "old")' 2>/dev/null || echo "unknown")"
  if [ "$_PY_OK" = "old" ]; then
    _PY_VER="$(python3 -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo "?")"
    printf '  [%s] %-12s %s\n' "$(red WRN)" "python ver" \
      "$(dim "system python3 $_PY_VER is below ADK minimum (3.10); uv-managed Python (setup.sh step 3) is not affected")"
  fi
fi

check "adk"        "adk"        "adk --version"
check "agents-cli" "agents-cli" "agents-cli --version"
check "gcloud"     "gcloud"     "gcloud --version"
echo "---------------------------------------------"

# -----------------------------------------------------------------------------
# Agent Skills scaffold check. Resolves the directory the same way setup.sh
# does so the two scripts agree on location.
# -----------------------------------------------------------------------------
SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agent-skills}"
if [ -d "$SKILLS_DIR" ]; then
  printf '  [%s] %-12s %s\n' "$(green OK)" "skills dir" "$(dim "$SKILLS_DIR")"
  PRESENT+=("skills dir ($SKILLS_DIR)")
else
  printf '  [%s] %-12s %s\n' "$(red '--')" "skills dir" "$(dim "not created ($SKILLS_DIR)")"
  MISSING+=("skills dir")
fi

# -----------------------------------------------------------------------------
# Read-only inspection of gcloud's current context (if gcloud is installed).
# Uses `gcloud config get-value` which never mutates state.
# -----------------------------------------------------------------------------
GCLOUD_ACCOUNT=""
GCLOUD_PROJECT=""
if command -v gcloud >/dev/null 2>&1; then
  GCLOUD_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
  GCLOUD_PROJECT="$(gcloud config get-value project 2>/dev/null)"
  [ -n "$GCLOUD_ACCOUNT" ] && [ "$GCLOUD_ACCOUNT" != "(unset)" ] && \
    printf '       %s %s\n' "$(dim 'account:')" "$GCLOUD_ACCOUNT"
  [ -n "$GCLOUD_PROJECT" ] && [ "$GCLOUD_PROJECT" != "(unset)" ] && \
    printf '       %s %s\n' "$(dim 'project:')" "$GCLOUD_PROJECT"
fi

# -----------------------------------------------------------------------------
# SUMMARY block — gives the user a single place to see overall state and
# clearly indicates that nothing on disk was changed.
# -----------------------------------------------------------------------------
echo ""
echo "============================================="
bold "  Inspection SUMMARY"; echo ""
echo "============================================="
echo "Components PRESENT (${#PRESENT[@]}):"
if [ "${#PRESENT[@]}" -eq 0 ]; then
  echo "  (none)"
else
  for item in "${PRESENT[@]}"; do echo "  - $item"; done
fi
echo ""
echo "Components MISSING (${#MISSING[@]}):"
if [ "${#MISSING[@]}" -eq 0 ]; then
  echo "  (none — environment looks complete)"
else
  for item in "${MISSING[@]}"; do echo "  - $item"; done
fi
echo ""
if [ -n "$GCLOUD_ACCOUNT$GCLOUD_PROJECT" ]; then
  echo "gcloud context:"
  [ -n "$GCLOUD_ACCOUNT" ] && [ "$GCLOUD_ACCOUNT" != "(unset)" ] && echo "  - account: $GCLOUD_ACCOUNT"
  [ -n "$GCLOUD_PROJECT" ] && [ "$GCLOUD_PROJECT" != "(unset)" ] && echo "  - project: $GCLOUD_PROJECT"
  echo ""
fi
echo "Changes made to your system by this script: NONE (read-only)."
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Next step: run scripts/setup.sh to install the MISSING components."
fi
echo "============================================="
echo ""
