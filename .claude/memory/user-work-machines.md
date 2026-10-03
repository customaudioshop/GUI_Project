---
name: user-work-machines
description: "User codes on a home Mac and on both a Windows PC and a Mac at the office; repo and memory are shared via private GitHub"
metadata:
  type: user
---

The user works on this project at home (Mac) and at the office, where they have both a Windows PC and a Mac (stated 2026-10-04). The repo (private GitHub, customaudioshop/GUI_Project) carries the Claude memory in `.claude/memory/`, symlinked from `~/.claude/projects/<path>/memory` on each machine.

**Why:** Anything that only works on macOS (symlinks, shell commands, paths) breaks on the office Windows PC.
**How to apply:** Keep tooling cross-platform. The shared `gui_core` symlinks need Windows Developer Mode + `core.symlinks=true`; setup is in docs/Dev-setup.md. Give Windows commands alongside Mac ones when explaining setup. See [[gui-builder-project-overview]].
