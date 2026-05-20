# Team Agent Skills

Shared AI agent skills for the team. Each skill folder contains a `SKILL.md`
with frontmatter and optional `scripts/` and `references/` directories.

## Setup

Clone this repo into your local Agent Skills directory:

```bash
# Option A — use as your entire skills directory
git clone https://github.com/gauravlahoti/team-agent-skills.git ~/.agent-skills

# Option B — symlink individual skills alongside your own
git clone https://github.com/gauravlahoti/team-agent-skills.git ~/team-agent-skills
ln -s ~/team-agent-skills/google-agentic-env-setup ~/.agent-skills/google-agentic-env-setup
```

## Updating

```bash
cd ~/.agent-skills   # or ~/team-agent-skills
git pull
```

## Skills

| Skill | Description |
|-------|-------------|
| [google-agentic-env-setup](./google-agentic-env-setup/SKILL.md) | Bootstrap a Google ADK development environment (git, uv, Python, google-adk, google-agents-cli, gcloud, Gemini API key) on Linux, macOS, or Windows (WSL 2). |

## Contributing

- Open a PR for any changes to skill logic, gates, or scripts.
- Main branch is protected — all skill changes require review before they ship
  to teammates' agents.
- Update `CHANGELOG.md` with a summary of what changed and why.
