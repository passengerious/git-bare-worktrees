# Git Bare Worktree Rules

These rules apply to any repository using the Git bare-repository architecture layout.

## 1. Expected Repository Architecture

```text
<project-root>/
├── .bare/                 # Bare Git repository (shared Git database)
├── main/                  # Main workspace checkout (default branch)
└── wt/
    ├── <feature-a>/       # Feature worktrees
    └── <feature-b>/
```

## 2. Core Worktree Invariants

- **Isolation:** Never switch branches inside `main/` to perform feature development. Feature work must occur inside dedicated worktrees under `wt/<name>`.
- **Single Source of Truth:** `main/` represents the trunk and serves as the baseline for shared dependencies and environment configs.
- **Dependency & Env Mirroring:** New worktrees under `wt/<name>` should mirror root `node_modules` and subpackage dependencies, as well as local `.env` files from `main/`.
- **Worktree Cleanup:** Worktree directories must be cleanly unlinked and removed when work is merged or abandoned. Branches must only be deleted after confirming merge status or explicit user authorization.
- **Tooling:** Use the `git-bare-worktrees` skill scripts (`bare-wt-init.sh`, `agent-init.sh`, `setup-bare-wt-hooks.sh`, `worktree-add.sh`, and `worktree-drop.sh`) to bootstrap repositories, configure shared `.bare/hooks`, and provision or decommission worktrees reliably.
