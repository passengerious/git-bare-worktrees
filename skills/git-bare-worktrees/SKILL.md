---
name: git-bare-worktrees
description: >
  Manage standard and stacked Git worktrees in bare-repository projects.
  Use when creating feature worktrees, provisioning self-subagent workspaces,
  synchronizing parent branches, rebasing dependent work, handling squash
  merges, or safely cleaning up worktrees.
---

# Git Bare Worktree Management

## Purpose

Manage isolated Git worktrees in projects using a bare repository and a dedicated `main/` checkout.

Support both independent feature development and stacked feature branches based on unmerged parent branches.

Prioritize preservation of existing work, verified ancestry, and predictable failure recovery.

## 1. Repository Architecture

Expected layout:

```text
<project-root>/
├── .bare/                 # Bare repository, sometimes .git/
├── main/                  # Main agent workspace
└── wt/
    ├── feature-a/         # Independent feature
    ├── feature-b/         # Stacked feature
    └── task-123/          # Self-subagent workspace
```

### Execution model

**Main agent**

- Starts inside `main/`.
- Owns worktree provisioning and cleanup.
- Selects branch bases.
- Coordinates stacked branches.
- May delegate development to self-subagents.

**Self-subagent**

- Starts inside a worktree provisioned by the main agent.
- Develops and tests within its assigned worktree.
- May create commits on its assigned branch.
- Must not restructure shared repository state without explicit delegation.
- Reports completion, commit SHA, and outstanding changes to the main agent.

Git worktrees isolate working directories but share Git refs, objects, and repository metadata.

Do not treat separate worktrees as independent repositories.

## 2. Repository Discovery

Run from `main/` or the assigned worktree.

```bash
GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
```

Validate the repository:

```bash
git --git-dir="$GIT_DIR" rev-parse --is-bare-repository
git --git-dir="$GIT_DIR" worktree list --porcelain
```

For the main agent, verify that the current worktree is the expected `main/` checkout.

Determine the project root as the parent directory of the verified `main/` worktree.

```bash
PROJECT_ROOT="$(dirname "$WORKTREE_ROOT")"
```

Do not apply this project-root derivation inside a feature worktree.

If the expected layout is not present, stop and inspect rather than guessing.

## 3. Mandatory Safety Invariants

Before modifying Git state:

1. Verify repository identity.
2. Verify current worktree and branch.
3. Verify the target branch and path.
4. Check for uncommitted changes when rewriting history.
5. Check for unfinished Git operations.
6. Confirm the intended branch base.
7. Preserve existing local commits.
8. Never overwrite an existing worktree.

The following operations require explicit authorization:

- `git reset --hard`
- Destructive `git clean`
- Unconditional force-push
- Force-delete branch
- Force-remove worktree
- Discard uncommitted changes
- Rewrite a branch owned by another active agent

If verification fails, stop without attempting speculative recovery.

## 4. Helper Automation Scripts

The plugin bundles five zero-dependency Bash scripts in `./scripts/` covering the full bare-worktree lifecycle:

- **Initialize Bare Worktree Repo:** [`bare-wt-init.sh`](./scripts/bare-wt-init.sh) — Bootstraps a new bare repository (`.bare/`, `.git` pointer, `main/` worktree, and `wt/` directory) in an empty project directory.
- **Initialize Agent Instructions:** [`agent-init.sh`](./scripts/agent-init.sh) — Idempotently creates or appends core agent safety and worktree rules to `main/AGENTS.md` after verifying bare-worktree Git metadata.
- **Configure Shared Hooks & CI Wizard:** [`setup-bare-wt-hooks.sh`](./scripts/setup-bare-wt-hooks.sh) — Interactive wizard that installs shared `pre-commit` (whitespace/conflict check + optional Gitleaks) and `pre-push` (Python Ruff/pytest, TypeScript/pnpm/Turbo typecheck & tests, custom schema checker) into `.bare/hooks/` via `core.hooksPath`, plus an optional GitHub Actions workflow.
- **Add Feature Worktree:** [`worktree-add.sh`](./scripts/worktree-add.sh) `<name> [base-branch] [branch-name]` — Provisions `wt/<name>`, mirrors root `node_modules` safely for pnpm v12+, symlinks subpackage `node_modules`, copies untracked `.env`/`.env.local` files from `main/`, and runs optional post-add hooks.
- **Drop Feature Worktree:** [`worktree-drop.sh`](./scripts/worktree-drop.sh) `<name> [--delete-branch|-d] [--force|-f]` — Verifies worktree cleanliness, unlinks mirrored `node_modules` and untracked `.env` files, and safely removes the worktree (refusing destructive removal or unmerged branch deletion unless `--force` is explicitly authorized).

## 5. Standard Feature Worktree Creation

Use for an independent feature based on `main` or another explicitly selected stable branch.

### Inputs

- `BASE_REF`
- `FEATURE_BRANCH`
- `WORKTREE_NAME`

Example:

```bash
BASE_REF="refs/remotes/origin/main"
FEATURE_BRANCH="feature/search"
WORKTREE_NAME="search"
WORKTREE_PATH="$PROJECT_ROOT/wt/$WORKTREE_NAME"
```

### Procedure

Fetch remote state when required:

```bash
git --git-dir="$GIT_DIR" fetch origin
```

Do not overwrite local branches with fetched remote refs.

Validate branch names:

```bash
git --git-dir="$GIT_DIR" check-ref-format --branch "$FEATURE_BRANCH"
```

Verify that the feature branch does not exist:

```bash
git --git-dir="$GIT_DIR" show-ref --verify --quiet \
  "refs/heads/$FEATURE_BRANCH"
```

If this succeeds, stop because the branch already exists.

Verify that the target worktree path does not exist.

Resolve the intended base:

```bash
BASE_SHA="$(
  git --git-dir="$GIT_DIR" rev-parse \
    --verify "$BASE_REF^{commit}"
)"
```

Create the worktree:

```bash
git --git-dir="$GIT_DIR" worktree add \
  -b "$FEATURE_BRANCH" \
  "$WORKTREE_PATH" \
  "$BASE_SHA"
```

Verify:

```bash
git -C "$WORKTREE_PATH" status --short --branch
git -C "$WORKTREE_PATH" rev-parse HEAD
git -C "$WORKTREE_PATH" branch --show-current
```

Success requires the correct branch, expected HEAD, and clean working tree.

Do not automatically change branches inside `main/`.

## 6. Stacked Feature Worktree Creation

Use when a new feature depends on an unmerged parent feature.

Example:

```text
main
  └── feature/phase1
        └── feature/phase2
```

### Inputs

```bash
PARENT_BRANCH="feature/phase1"
CHILD_BRANCH="feature/phase2"
CHILD_WORKTREE="$PROJECT_ROOT/wt/phase2"
```

### Select parent

Prefer the local parent branch if it exists.

```bash
git --git-dir="$GIT_DIR" show-ref --verify --quiet \
  "refs/heads/$PARENT_BRANCH"
```

If present:

```bash
PARENT_REF="refs/heads/$PARENT_BRANCH"
```

Otherwise fetch and verify:

```bash
git --git-dir="$GIT_DIR" fetch origin
```

Use:

```bash
PARENT_REF="refs/remotes/origin/$PARENT_BRANCH"
```

only after verifying that the remote-tracking reference exists.

Do not silently overwrite or reset the local parent branch.

### Create child

Resolve the exact parent commit:

```bash
PARENT_BASE_SHA="$(
  git --git-dir="$GIT_DIR" rev-parse \
    --verify "$PARENT_REF^{commit}"
)"
```

Validate the child branch name, confirm that its local ref does not exist, and verify that the target path is unused.

```bash
git --git-dir="$GIT_DIR" worktree add \
  -b "$CHILD_BRANCH" \
  "$CHILD_WORKTREE" \
  "$PARENT_BASE_SHA"
```

Verify the new worktree's branch, HEAD, and clean status.

### Record metadata

```yaml
branch: feature/phase2
parent_branch: feature/phase1
parent_base_sha: <full-commit-sha>
worktree_path: <absolute-path>
state: active
```

Store metadata outside tracked product files.

The `parent_base_sha` is the boundary separating parent commits from child-only commits.

Update it only after successful reconciliation.

## 7. Self-Subagent Provisioning

The main agent provisions an isolated worktree before spawning a self-subagent.

Procedure:

1. Determine the subagent's task.
2. Choose a unique branch and worktree path.
3. Select the correct base commit.
4. Create the worktree.
5. Verify the worktree.
6. Spawn the subagent with its assigned path and branch.

The main agent must communicate:

- Absolute worktree path.
- Assigned branch.
- Development task.
- Expected deliverables.
- Git operation restrictions.

The self-subagent must not switch branches or modify other worktrees.

### Completion handoff

The self-subagent reports:

- Task outcome.
- Current branch.
- Final commit SHA.
- Working-tree cleanliness.
- Tests executed and results.
- Remaining issues.

The main agent verifies this information against Git state.

Do not assume that subagent completion means its worktree is safe to remove.

## 8. Parent Update Reconciliation

Use when an unmerged parent receives additional commits.

The main agent owns reconciliation unless explicitly delegated.

### Preconditions

- Child worktree is clean.
- No Git operation is in progress.
- Recorded parent boundary is available.
- Child HEAD descends from the recorded boundary.
- New parent HEAD descends from the recorded boundary.

Fetch as appropriate:

```bash
git -C "$CHILD_WORKTREE" fetch origin
```

Resolve the intended new parent tip to `NEW_PARENT_SHA`.

Verify:

```bash
git -C "$CHILD_WORKTREE" merge-base --is-ancestor \
  "$PARENT_BASE_SHA" HEAD

git -C "$CHILD_WORKTREE" merge-base --is-ancestor \
  "$PARENT_BASE_SHA" "$NEW_PARENT_SHA"
```

Both commands must succeed.

Rebase child-only commits:

```bash
git -C "$CHILD_WORKTREE" rebase --onto \
  "$NEW_PARENT_SHA" \
  "$PARENT_BASE_SHA" \
  "$CHILD_BRANCH"
```

After success:

1. Verify that the new parent SHA is an ancestor of child HEAD.
2. Review the resulting commit range.
3. Run relevant tests.
4. Update stack metadata.

If ancestry validation fails, stop.

Do not automatically infer a new boundary from `merge-base`.

## 9. Parent Squash-Merge Reconciliation

Use after the parent PR is squash-merged into `main`.

A squash merge preserves changes but rewrites commit identity.

### Preconditions

- Parent merge is confirmed.
- Destination main contains the final parent changes.
- Child worktree is clean.
- Recorded parent boundary is verified.
- All parent commits are excluded from the child-only replay range.
- No unfinished Git operation exists.

Fetch main:

```bash
git -C "$CHILD_WORKTREE" fetch origin
```

Resolve:

```bash
NEW_MAIN_SHA="$(
  git -C "$CHILD_WORKTREE" rev-parse \
    --verify "origin/main^{commit}"
)"
```

Verify the recorded parent boundary:

```bash
git -C "$CHILD_WORKTREE" merge-base --is-ancestor \
  "$PARENT_BASE_SHA" HEAD
```

If the boundary accurately separates all parent commits from child-only commits:

```bash
git -C "$CHILD_WORKTREE" rebase --onto \
  "$NEW_MAIN_SHA" \
  "$PARENT_BASE_SHA" \
  "$CHILD_BRANCH"
```

Do not execute this command if the parent advanced beyond the recorded boundary without the child incorporating those changes.

After rebase:

- Inspect the child diff against main.
- Check for duplicated parent changes.
- Run tests.
- Verify feature behavior.
- Confirm that the child no longer requires the old parent history.

Only then retarget the child PR to main.

If the correct boundary cannot be established, stop.

## 10. Conflict Recovery

On rebase conflict:

1. Inspect `git status`.
2. Identify conflicting files.
3. Determine whether the intended resolution is unambiguous.
4. Resolve only understood conflicts.
5. Stage resolved files.
6. Continue the rebase.
7. Run tests after completion.

```bash
git -C "$CHILD_WORKTREE" rebase --continue
```

If resolution is ambiguous, stop and report.

`git rebase --abort` is permitted only when the active rebase belongs to the current agent operation and aborting will preserve unrelated work.

Never automatically run:

```bash
git reset --hard
git clean -fd
git rebase --skip
```

Do not update stack metadata after an unsuccessful rebase.

## 11. Commit and Push Safety

Agents may commit on their assigned branches as authorized by the task.

Before committing:

```bash
git status
git diff --check
```

Stage only intended files.

Normal pushes may be performed when authorized.

After rebasing, a history rewrite may require a force-with-lease push.

Never use unconditional `--force`.

For an authorized rewrite, verify the expected remote tip and use an explicit lease:

```bash
git push \
  --force-with-lease="refs/heads/$CHILD_BRANCH:$EXPECTED_REMOTE_SHA" \
  origin "$CHILD_BRANCH"
```

Do not push rewritten history when remote ownership or state is uncertain.

## 12. Worktree Cleanup

Cleanup is owned by the main agent unless explicitly delegated.

### Preconditions

- The work is confirmed merged or abandonment is authorized.
- The worktree is clean.
- No Git operation is active.
- No self-subagent is still using the worktree.
- The path and branch match the intended target.
- Required commits are preserved.

Inspect:

```bash
git -C "$CHILD_WORKTREE" status --porcelain
git --git-dir="$GIT_DIR" worktree list --porcelain
```

Remove:

```bash
git --git-dir="$GIT_DIR" worktree remove \
  "$CHILD_WORKTREE"
```

Verify removal:

```bash
git --git-dir="$GIT_DIR" worktree list --porcelain
```

Branch deletion is separate and must be independently authorized or verified safe.

Squash-merged branches may not appear merged by Git ancestry.

Do not force-delete a branch merely because the PR was squash-merged.

Pruning is not required after normal successful worktree removal.

## 13. Decision Rules

### Standard feature

- Explicit base provided: use it.
- No base provided: use the project's established default after verification.
- Branch already exists: inspect; do not overwrite.
- Target path occupied: stop.

### Stacked feature

- Local parent exists: prefer local parent.
- Only remote parent exists: use verified remote-tracking ref.
- Parent missing: stop.
- Parent history rewritten: stop and reassess.

### Self-subagent

- Main agent provisions worktree.
- Subagent works only on assigned branch.
- Main agent verifies completion.
- Main agent performs cleanup after the subagent has finished.

### Reconciliation

- Dirty child: stop.
- Parent fast-forwarded: use verified rebase boundary.
- Parent rewritten: stop.
- Squash merge confirmed: verify boundary and replay child-only commits.
- Boundary uncertain: stop.

### Cleanup

- Active subagent: preserve.
- Dirty worktree: preserve.
- Unmerged work: preserve unless abandonment authorized.
- Verified completed work: remove worktree safely.

## 14. Completion Criteria

An operation is complete only when:

- Repository identity is verified.
- Correct branch and worktree are selected.
- Existing work is preserved.
- Commit ancestry matches expectations.
- No unfinished Git operation remains.
- Relevant tests pass or failures are reported.
- Stack metadata is consistent with verified state.
- The main agent receives the operation outcome.

## Core Operating Rule

**Inspect → Validate → Execute → Verify → Record**

The main agent owns repository structure.

Self-subagents own implementation within their assigned worktrees.

When Git state is ambiguous, preserve work and stop rather than attempting speculative repair.
