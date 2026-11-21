# Git Bare Worktrees Manager (`git-bare-worktrees`)

An **AI Agent Plugin** (Rules + Skill + Lifecycle Automation Scripts) for managing isolated and stacked Git worktrees in bare-repository projects (`.bare/`, `main/`, `wt/<feature>`).

Designed for multi-agent parallel development, stacked PR workflows, and zero-pollution trunk management.

---

## Why Bare Repositories + Linked Worktrees for AI Agents?

Standard single-checkout repositories force developers and AI subagents to stash, switch branches, or clone duplicate repositories when working on parallel tasks. By structuring a project around a shared bare Git database (`.bare/`), a dedicated trunk checkout (`main/`), and isolated feature worktrees (`wt/<name>`):

```text
<project-root>/
├── .bare/                 # Shared bare Git database (refs, objects, shared hooks)
├── .git                   # Pointer file ("gitdir: .bare")
├── main/                  # Trunk checkout (baseline dependencies & .env)
└── wt/
    ├── feature-auth/      # Isolated feature worktree
    ├── feature-billing/   # Stacked child worktree
    └── subagent-task-42/  # Dedicated self-subagent workspace
```

- **Zero Context Collisions:** The coordinator agent stays in `main/` while parallel subagents execute concurrently inside `wt/<task>` without file lock or index contention.
- **Instant Dependency & Env Mirroring:** Provisioning a new worktree takes <1 second by symlinking root/monorepo `node_modules` (pnpm v12+ safe) and mirroring local `.env` files from `main/`.
- **Single Shared Hook Enforcement:** Pre-commit and pre-push checks live once in `.bare/hooks/` (`core.hooksPath`) and automatically guard every worktree (`main/` and `wt/*`).

---

## What's Included

### 1. Always-On Workspace Rule (`rules/AGENTS.md`)
Enforces core bare-worktree invariants whenever the plugin is active:
- Never switch branches inside `main/` for feature work.
- Treat `main/` as the Single Source of Truth for baseline dependencies and `.env` configurations.
- Require verified merge status or explicit authorization before deleting branches or dirty worktrees.

### 2. Progressive-Disclosure Skill (`skills/bare-worktree-workflow/SKILL.md`)
Comprehensive 14-section operational runbook covering:
- Bare repository discovery and verification (`--git-common-dir`, `--is-bare-repository`).
- Standard feature worktree creation and stacked branch creation (`parent_base_sha` boundary tracking).
- Self-subagent workspace provisioning and completion handoff verification.
- Parent update reconciliation (`git rebase --onto`) and parent squash-merge reconciliation.
- Safe conflict recovery, `--force-with-lease` push leases, and verified cleanup.

### 3. Five Zero-Dependency Lifecycle Scripts (`scripts/`)

| Script | Purpose |
| :--- | :--- |
| [`bare-wt-init.sh`](./scripts/bare-wt-init.sh) | Initializes a brand-new bare worktree project (`.bare/`, `.git`, `main/`, `wt/`) in an empty directory with an initial commit. |
| [`agent-init.sh`](./scripts/agent-init.sh) | Verifies bare-worktree metadata and idempotently initializes or appends `## Core Rules for Agents` in `main/AGENTS.md`. |
| [`setup-bare-wt-hooks.sh`](./scripts/setup-bare-wt-hooks.sh) | Interactive wizard that installs shared `pre-commit` (whitespace/conflict check + Gitleaks) and `pre-push` (Python Ruff/pytest, TypeScript/pnpm/Turbo typecheck & tests, custom schema checker) into `.bare/hooks/` and optionally generates `main/.github/workflows/git-guards.yml`. |
| [`worktree-add.sh`](./scripts/worktree-add.sh) | Creates `wt/<name>` from a base ref or existing branch, mirrors root `node_modules` safely for pnpm v12+, symlinks nested monorepo `node_modules`, copies local `.env`/`.env.local` files from `main/`, and runs optional post-add hooks. |
| [`worktree-drop.sh`](./scripts/worktree-drop.sh) | Verifies worktree cleanliness, unlinks mirrored `node_modules` and untracked `.env` files, and removes `wt/<name>`. Supports `--delete-branch` (`-d`) and `--force` (`-f`). |

---

## Installation

### Global Installation (All Projects)
Clone or symlink into your global agent plugins directory:
```bash
git clone https://github.com/passengerious/git-bare-worktrees.git ~/.gemini/config/plugins/git-bare-worktrees
```

### Workspace Installation (Project-Specific)
Clone directly into your project's `.agents` directory:
```bash
git clone https://github.com/passengerious/git-bare-worktrees.git .agents/plugins/git-bare-worktrees
```

---

## Quickstart Workflow

```bash
# 1. Bootstrap a new bare-worktree repository in an empty folder
mkdir my-project && cd my-project
bash ~/.gemini/config/plugins/git-bare-worktrees/scripts/bare-wt-init.sh

# 2. Initialize Core Agent Rules in main/AGENTS.md
bash ~/.gemini/config/plugins/git-bare-worktrees/scripts/agent-init.sh

# 3. (Optional) Configure shared pre-commit & pre-push hooks across all worktrees
bash ~/.gemini/config/plugins/git-bare-worktrees/scripts/setup-bare-wt-hooks.sh

# 4. Provision a feature worktree (from inside main/ or any worktree)
cd main
bash ~/.gemini/config/plugins/git-bare-worktrees/scripts/worktree-add.sh auth-flow main feat/auth-flow

# 5. Safely tear down the worktree once merged
bash ~/.gemini/config/plugins/git-bare-worktrees/scripts/worktree-drop.sh auth-flow --delete-branch
```

---

## License

MIT
