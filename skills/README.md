# Peekie skills

Official skill packs that teach LLM coding agents how to use the `peekie` CLI without re-explaining it every session.

## Claude Code

`skills/claude/peekie/` is a [Claude Code skill](https://code.claude.com/docs/en/skills.md).

To install locally:

```bash
mkdir -p ~/.claude/skills/peekie
cp -R skills/claude/peekie/* ~/.claude/skills/peekie/
```

The skill activates automatically when the agent encounters an `.xcresult` path or a request about tests / warnings / coverage in an iOS/macOS project.

## Cursor

`skills/cursor/peekie.mdc` is a Cursor [rule file](https://docs.cursor.com/context/rules-for-ai). It scopes to `**/*.xcresult` paths so it activates only when relevant.

To install locally:

```bash
mkdir -p .cursor/rules
cp skills/cursor/peekie.mdc .cursor/rules/peekie.mdc
```

Or place it in `~/.cursor/rules/` for project-wide availability.

## Marketplaces

- **Claude Code marketplace**: submission pending Anthropic's stable submission flow. Track [`anthropics/claude-code`](https://github.com/anthropics/claude-code) for the canonical path.
- **Cursor directory** (https://cursor.directory): submission pending.

## Maintenance

The skill content must stay in lock-step with the CLI surface. When you change a subcommand name, default format, or option, update both `skills/claude/peekie/SKILL.md` and `skills/cursor/peekie.mdc` in the same PR.
