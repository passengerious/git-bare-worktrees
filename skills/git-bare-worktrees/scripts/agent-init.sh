#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

(( $# == 0 )) || die "usage: $(basename "$0")"
command -v git >/dev/null 2>&1 || die 'git is required.'

CURRENT_DIR="$(pwd -P)"

# Return the verified main worktree for a supported bare repository container.
# This checks Git metadata, rather than trusting directory names alone.
find_bare_main() {
  local container="$1" bare_dir common_dir expected_dir main_dir
  main_dir="$container/main"
  [[ -d "$main_dir" ]] || return 1

  for bare_dir in "$container/.bare" "$container/.git"; do
    [[ -d "$bare_dir" ]] || continue
    [[ "$(git --git-dir="$bare_dir" rev-parse --is-bare-repository 2>/dev/null)" == true ]] || continue

    common_dir="$(git -C "$main_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
    expected_dir="$(cd "$bare_dir" && pwd -P)"
    [[ "$(cd "$common_dir" && pwd -P)" == "$expected_dir" ]] || continue

    # Ensure main/ is the worktree root, not merely a directory within one.
    [[ "$(git -C "$main_dir" rev-parse --show-toplevel 2>/dev/null)" == "$(cd "$main_dir" && pwd -P)" ]] || continue
    printf '%s\n' "$(cd "$main_dir" && pwd -P)"
    return 0
  done
  return 1
}

if PROJECT_ROOT="$(find_bare_main "$CURRENT_DIR")"; then
  LAYOUT_MODE='bare-worktree'
elif [[ "$(basename "$CURRENT_DIR")" == main ]] && \
     PROJECT_ROOT="$(find_bare_main "$(dirname "$CURRENT_DIR")")"; then
  LAYOUT_MODE='bare-worktree'
elif git rev-parse --is-inside-work-tree 2>/dev/null | grep -qx true; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel)"
  LAYOUT_MODE='standard-git'

  # Do not initialize AGENTS.md inside a managed feature worktree.
  COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
  CONTAINER="$(dirname "$COMMON_DIR")"
  if MANAGED_MAIN="$(find_bare_main "$CONTAINER")"; then
    [[ "$(cd "$PROJECT_ROOT" && pwd -P)" == "$MANAGED_MAIN" ]] || \
      die 'Run from the project root or main/, not a feature worktree.'
    PROJECT_ROOT="$MANAGED_MAIN"
    LAYOUT_MODE='bare-worktree'
  fi
else
  die 'Run from a Git checkout, or the root of a supported bare-worktree project.'
fi

AGENTS_FILE="$PROJECT_ROOT/AGENTS.md"
HEADING='## Core Rules for Agents'

# Never follow a symlink to rewrite an instruction file outside this checkout.
[[ ! -L "$AGENTS_FILE" ]] || die "AGENTS.md is a symlink; refusing to modify: $AGENTS_FILE"
[[ ! -e "$AGENTS_FILE" || -f "$AGENTS_FILE" ]] || die "Not a regular file: $AGENTS_FILE"

# Idempotent: preserve any existing core rules (including user customizations).
if [[ -f "$AGENTS_FILE" ]] && grep -Fxq "$HEADING" "$AGENTS_FILE"; then
  printf 'Core Rules already present; left AGENTS.md unchanged.\n'
  printf 'Path: %s\n' "$AGENTS_FILE"
  exit 0
fi

if [[ ! -e "$AGENTS_FILE" ]]; then
  printf '# Agent Instructions\n' > "$AGENTS_FILE"
  ACTION='created'
else
  ACTION='appended'
fi

# Append *outside* any Turborepo or other managed section. A leading blank
# line also handles an existing AGENTS.md with no trailing newline.
cat >> "$AGENTS_FILE" <<'EOF'

## Core Rules for Agents

- **Scope:** Make the smallest coherent change that satisfies the task. Avoid unrelated refactors and speculative architecture.
- **Workflow:** Follow applicable project specifications and installed engineering skills. Use SDD/TDD when appropriate; do not duplicate skill workflows here.
- **Commits:** Prefer small, reviewable Conventional Commits. Commit and push only when authorized.
- **Invariants:** Preserve existing architecture, documented domain invariants, and security boundaries.
- **Dependencies:** Do not add or upgrade dependencies without explicit necessity and authorization.
- **Secrets:** Never read, print, expose, or commit `.env` files or credentials. Document variable names in `.env.example` without actual secrets.
- **Validation:** Run relevant project-defined typechecks, linting, and tests; report checks that could not run.
- **Worktree Boundary:** Keep implementation changes within the active Git worktree. Use the `git-bare-worktrees` skill for worktree creation, reconciliation, and cleanup.
- **Security:** Before pushing or opening a PR affecting database schemas, RLS, authentication, or server-side mutations, request a read-only diff audit from the configured security-auditor subagent. If unavailable, report that the audit was not completed.

Follow project-specific instructions and applicable domain documentation when present.
EOF

printf 'Core Rules %s in AGENTS.md.\n' "$ACTION"
printf 'Layout: %s\n' "$LAYOUT_MODE"
printf 'Path:   %s\n' "$AGENTS_FILE"
