# Guided Google Cloud + Gemini API key setup (gated)

This is the part of the setup that a human must be present for. It is written as
a conversation the operating agent walks the user through, **pausing at each gate
for explicit approval in chat**. Do not wrap these into one unattended script —
the gates exist precisely so a person makes the consent, legal, cost, and secret
decisions.

### Transparency contract for this gated flow

For every command in the sections below, the operating agent MUST:

1. **Announce intent.** Before running anything, state what the command will do
   in plain language (e.g. *"I'm going to create a Google Cloud project named
   `adk-dev-123`. This is reversible. OK to proceed?"*).
2. **Show the exact command.** Print the literal `gcloud ...` invocation before
   running it.
3. **Wait for explicit approval at each GATE** below.
4. **Report the resulting change.** After the command runs, narrate what
   changed (project created, billing linked, API enabled, key created and
   written to `.env`). For the API key, narrate *that* it was written and to
   *which file*, but never echo the key value itself.
5. **End with a SUMMARY.** At the end of the gated flow, list everything that
   was created or modified in the user's Google Cloud account and on disk.

OS note: commands below use `gcloud`. On Windows in deploy/automation contexts,
substitute `gcloud.cmd`. Interactive use of `gcloud` in a shell is fine on Windows.

---

## Install gcloud (not gated, but choose one method and stick to it)

- **macOS:** `brew install --cask google-cloud-sdk`
  (Homebrew must already be installed. Verify with `brew --version`.)
- **Linux (Debian/Ubuntu):**
  ```bash
  sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
  # Import the Google Cloud signing key into the dedicated keyring directory
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  # Add the repo, referencing the keyring so apt trusts the packages
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get update && sudo apt-get install -y google-cloud-cli
  ```
- **Windows:** download and run the GoogleCloudSDKInstaller from
  https://cloud.google.com/sdk/docs/install (the installer needs admin rights to
  edit PATH; check "Cloud Tools for PowerShell").

Open a new terminal afterward, then `gcloud version` to confirm.

Mixing install methods creates two gcloud copies at different versions. Pick one.

---

## GATE 1 — Authenticate (browser OAuth)

Explain: this opens a browser so the user signs in with their Google account and
grants gcloud access. Only the user can complete it.

Ask the user to run (it is interactive by design — let them do it):
```
gcloud auth login
```
On a headless box, use `gcloud auth login --no-launch-browser` and have the user
complete the flow in any browser, then paste the code back.

> **Headless / CI alternative (service account):** If this machine is a CI
> runner or a server without a browser, use a service account instead:
> ```
> gcloud auth activate-service-account --key-file=/path/to/sa-key.json
> ```
> The service account key file is a secret — store it in a secrets manager or
> mount it as an environment variable, never commit it to version control.

Also set application-default credentials if ADK will use ADC locally:
```
gcloud auth application-default login
```

> **ADC credentials location:** `gcloud auth application-default login` writes a
> long-lived OAuth refresh token to
> `~/.config/gcloud/application_default_credentials.json`. Treat this file like
> a password — it grants API access without further authentication. Protect it:
> ```
> chmod 600 ~/.config/gcloud/application_default_credentials.json
> ```
> Revoke it when no longer needed:
> ```
> gcloud auth application-default revoke
> ```

Wait for the user to confirm they are signed in before continuing.

---

## GATE 2 — Accept Terms of Service / pick the account context

If this is a brand-new Google Cloud account, the user must accept the Cloud
Terms of Service in the browser once. This is a legal agreement — only the user
can accept it. Confirm they have an active account:
```
gcloud auth list
```

---

## GATE 3 — Create or choose a project, then link billing

Confirm with the user **which** to do — reuse an existing project or create a new
one — and, if creating, confirm the exact project ID (globally unique, lowercase,
6–30 chars). Then:

```bash
# See what already exists
gcloud projects list

# Create (only after confirming the ID with the user)
gcloud projects create YOUR_PROJECT_ID --name="Agent Dev"

# Make it the default for subsequent commands
gcloud config set project YOUR_PROJECT_ID
```

**Billing is the cost gate.** Generative AI API usage can incur charges. Before
linking, tell the user this has cost implications and confirm which billing
account to attach:
```bash
# List billing accounts the user can see
gcloud billing accounts list

# Link (only after the user confirms the billing account ID)
gcloud billing projects link YOUR_PROJECT_ID --billing-account=XXXXXX-XXXXXX-XXXXXX
```

Then enable the API the agent will call. For Gemini via the Generative Language
API:
```bash
gcloud services enable generativelanguage.googleapis.com
```
If the user is going the Vertex AI route instead of an API key, enable
`aiplatform.googleapis.com` and skip the API-key gate — Vertex uses ADC from
GATE 1, which is the **more secure path for production**.

---

## GATE 4 — Generate the API key and store it safely (secret)

> **Recommended for production: use Vertex AI + ADC (Gate 1) and skip this gate
> entirely.** A raw API key is a long-lived, hard-to-rotate credential — prefer
> Secret Manager or ADC for anything beyond local experimentation.

This produces a secret. The operating agent MUST follow every rule in this
section or STOP and alert the user.

### Pre-flight: protect the `.env` file BEFORE the key exists

Run this BEFORE creating the key — do not proceed past this block until both
checks pass:

```bash
cd /path/to/your/agent/project

# 1. Add .env to .gitignore BEFORE writing any secret
grep -qxF '.env' .gitignore 2>/dev/null || { echo '.env' >> .gitignore; echo "Added .env to .gitignore."; }

# 2. Verify .env is NOT already tracked by git (would leak the key on next push)
if git -C . ls-files --error-unmatch .env 2>/dev/null; then
  echo "ERROR: .env is already tracked by git. Remove it from tracking first:"
  echo "  git rm --cached .env && git commit -m 'stop tracking .env'"
  exit 1
fi

echo "Pre-flight passed: .gitignore protects .env."
```

### Create the key with API restrictions

**Always restrict the key to the specific API it will call.** An unrestricted
key is a wide-open credential that can be abused in full if leaked.

```bash
# Create the key, restricted to the Generative Language API only
gcloud services api-keys create \
  --display-name="adk-local-dev" \
  --api-target=service=generativelanguage.googleapis.com
```

Note the `name` field in the output (format:
`projects/PROJECT_NUMBER/locations/global/keys/KEY_ID`). Extract the KEY_ID:

```bash
KEY_ID=$(gcloud services api-keys list \
  --filter="displayName=adk-local-dev" \
  --format="value(name)" | awk -F/ '{print $NF}')
echo "Key resource ID: $KEY_ID"
```

### Write the key to `.env` without it touching shell history

**Do NOT paste the key value into any command argument.** It would land in shell
history (`~/.zsh_history`, `~/.bash_history`) and any terminal logging tools.
Write the key directly from `gcloud` output to the file instead:

```bash
# Ensure the file exists with restrictive permissions before any write
touch .env && chmod 600 .env

# Remove any pre-existing GOOGLE_API_KEY line to avoid stale duplicates
grep -v '^GOOGLE_API_KEY=' .env > .env.tmp && mv .env.tmp .env && chmod 600 .env

# Ensure the file ends with a newline if it already has content
[ -s .env ] && echo >> .env 2>/dev/null || true

# Write the variable name prefix, then pipe the key value from gcloud directly
# into the file — the key value NEVER passes through a shell variable or argument
printf 'GOOGLE_API_KEY=' >> .env
gcloud services api-keys get-key-string "$KEY_ID" \
  --format='value(keyString)' >> .env
chmod 600 .env
echo "Key written to .env (permissions: 600). Not echoing the value."
```

> **Console alternative (more cautious):** the user can generate the key in the
> Cloud Console under **APIs & Services → Credentials → Create credentials → API
> key**, then copy-paste it directly into their terminal's `.env` editor
> (`nano .env` or `code .env`) without it passing through any shell command
> argument at all. Offer this as the preferred option.

ADK reads `.env` automatically via python-dotenv. Confirm the project has a
`.gitignore` containing `.env` BEFORE the key is written (the pre-flight above
ensures this).

---

## GATE 5 — `agents-cli setup` (coding-agent config)

`agents-cli setup` registers Google's bundled ADK skills (workflow, adk-code,
scaffold, eval, deploy, publish, observability) with the user's coding agent
(e.g., Claude Code, Cursor). This writes to the coding agent's configuration
files (for Claude Code: `~/.claude/settings.json`).

Before the user runs this:

1. **Name the target coding agent** — ask which coding agent to configure.
2. **Show what will change** — run `agents-cli setup --help` (or dry-run if
   available) and surface the output to the user.
3. **Confirm explicitly** — this modifies config outside the current project and
   is not automatically reversible without manual file editing.

```bash
# Let the user run this — do not auto-run it
agents-cli setup
```

---

## Verify the cloud setup

```bash
gcloud config list
adk --version
# Verify adk can import (from within the adk tool's own environment)
adk run --help
```

If you want to confirm the key works without printing it, run a tiny ADK sample
agent (`adk run` / `adk web`) from the project directory and check it reaches the
model. Do not echo `GOOGLE_API_KEY` in any verification output or summary.
