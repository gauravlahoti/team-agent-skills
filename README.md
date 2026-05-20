# Team Agent Skills

Ready-to-use skills for your coding agent. Clone once, stay updated with `git pull`.

> **Prerequisite:** You need a coding agent installed —
> [Claude Code](https://claude.ai/code), [Antigravity CLI](https://antigravity.google) (successor to Gemini CLI), or Gemini CLI.

---

## Install

```bash
git clone https://github.com/gauravlahoti/team-agent-skills.git ~/.agent/skills
```

That's it. Your coding agent picks up the skills automatically on next launch.

> Already have your own skills in `~/.agent/skills`? Add just this skill instead:
> ```bash
> git clone https://github.com/gauravlahoti/team-agent-skills.git ~/team-agent-skills
> ln -s ~/team-agent-skills/google-agentic-env-setup ~/.agent/skills/google-agentic-env-setup
> ```

---

## How to use a skill

Once installed, just talk to your coding agent:

### Claude Code
```
> Set up my Google ADK development environment
```
Claude Code will find the `google-agentic-env-setup` skill and walk you through it step by step.

### Antigravity CLI / Gemini CLI
```
> Set up my Google ADK development environment
```
The skill loads automatically from `~/.agent/skills`. Same prompt, same guided flow.

> **How it works:** Skills are instruction files your coding agent reads before responding.
> The agent uses the skill to know exactly what to install, what to ask you, and what
> never to do automatically (like creating billing accounts without your OK).

---

## Stay updated

```bash
cd ~/.agent/skills && git pull
```

---

## Available skills

| Skill | What it does |
|-------|-------------|
| [google-agentic-env-setup](./google-agentic-env-setup/SKILL.md) | Sets up a full Google ADK dev environment: git, uv, Python, `google-adk`, `google-agents-cli`, `gcloud`, and a Gemini API key. Works on macOS, Linux, and Windows (WSL 2). |

---

## Contributing

Changes to skills affect everyone's agent — open a PR and get a review before merging to `main`.
