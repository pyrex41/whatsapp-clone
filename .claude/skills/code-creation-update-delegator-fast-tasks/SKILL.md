---
name: Code Creation and Update Delegator for Fast Targeted Tasks
description: Delegates code creation (greenfield) and targeted updates to Zen MCP's grok-code-fast-1 for rapid, detailed generation.
---

# Code Creation and Update Delegator for Fast Targeted Tasks Skill

## When to Use This Skill
This skill delegates code tasks to grok-code-fast-1 on the running Zen MCP server (integrated in Claude Code), focusing on creation and updates rather than broad edits:
- **Creation/Greenfield**: Building new codebases, functions, or modules from detailed specs (e.g., "Create a full Express.js middleware for auth with JWT and role-based access").
- **Targeted Updates**: Enhancing existing code with specific additions or refinements (e.g., "Update this React hook to support offline mode with localStorage sync").
- Triggers: Phrases like "create new code for [feature]", "update with [specifics]", "generate targeted [component/module]", or intent for fast creation/updates.

Claude delegates automatically: Detect → Spec Prompt → Offload → Integrate.

## Core Workflow (Delegation Pattern)
1. **Detect & Delegate**: Match task to creation or update; route to grok-code-fast-1 for speed.
2. **Prepare Spec Prompt**: Build dense, instruction-rich prompts for high-fidelity outputs.
3. **Call Zen MCP**: Invoke pre-integrated tools for sub-second execution.
4. **Receive & Refine**: Incorporate generated/updated code, validate, and loop if needed.
5. **Fallback**: For non-targeted ideation, handle locally.

Optimizes for grok-code-fast-1's strengths in fresh creation and precise updates.

## Prompt Engineering Guidelines
Tailored for grok-code-fast-1's rapid handling of creation and updates:
- **Structure**: JSON for clear delegation.
  Example template (creation):
