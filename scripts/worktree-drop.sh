#!/usr/bin/env bash
set -euo pipefail

FORCE=0
NAME=""
DELETE_BRANCH=0

for arg in "$@"; do
  case "$arg" in
    --force|-f)
      FORCE=1
      ;;
    --delete-branch|-d)
      DELETE_BRANCH=1
      ;;
    -h|--help)
      echo "Usage: worktree-drop.sh <worktree-name> [--delete-branch|-d] [--force|-f]"
      echo ""
      echo "Options:"
      echo "  --delete-branch, -d   Also delete the associated local branch (safe -d unless --force)"
      echo "  --force, -f           Force removal even if worktree has untracked/modified files or unmerged commits"
      exit 0
      ;;
    *)
      if [ -z "$NAME" ]; then
        NAME="$arg"
      else
        echo "Error: Unexpected argument '$arg'." >&2
        echo "Usage: worktree-drop.sh <worktree-name> [--delete-branch|-d] [--force|-f]" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Usage: worktree-drop.sh <worktree-name> [--delete-branch|-d] [--force|-f]" >&2
  exit 1
fi

GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "Error: Not inside a Git repository." >&2
  exit 1
fi

PROJECT_ROOT="$(dirname "$GIT_COMMON_DIR")"
WT_DIR="${PROJECT_ROOT}/wt/${NAME}"

if [ ! -d "${WT_DIR}" ]; then
  echo "Worktree directory ${WT_DIR} not found."
  exit 0
fi

# Safety Check: Verify clean status before touching symlinks unless --force is explicitly authorized
if [ "$FORCE" -eq 0 ] && git -C "${WT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  DIRTY_STATUS="$(git -C "${WT_DIR}" status --porcelain)"
  if [ -n "$DIRTY_STATUS" ]; then
    echo "Error: Worktree '${WT_DIR}' has uncommitted or untracked changes:" >&2
    echo "$DIRTY_STATUS" >&2
    echo "Refusing destructive removal. Commit/stash your work, or pass --force if abandonment is authorized." >&2
    exit 1
  fi
fi

echo "Cleaning up worktree at ${WT_DIR}..."

# Clean up mirrored root node_modules symlinks/directory
[ -L "${WT_DIR}/node_modules" ] && unlink "${WT_DIR}/node_modules" || true
[ -d "${WT_DIR}/node_modules" ] && rm -rf "${WT_DIR}/node_modules" || true

# Clean up any subpackage node_modules symlinks
find "${WT_DIR}" -mindepth 2 -maxdepth 3 -type l -name "node_modules" 2>/dev/null | while read -r symlink; do
  unlink "$symlink" || true
done

# Clean up copied untracked .env / .env.local files so safe `git worktree remove` succeeds
find "${WT_DIR}" -maxdepth 3 -type f \( -name ".env" -o -name ".env.local" \) ! -path "*/.git/*" 2>/dev/null | while read -r env_file; do
  if ! git -C "${WT_DIR}" ls-files --error-unmatch "$env_file" >/dev/null 2>&1; then
    rm -f "$env_file"
  fi
done

if git -C "${WT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$FORCE" -eq 1 ]; then
    git -C "${WT_DIR}" clean -fdx || true
    git --git-dir="$GIT_COMMON_DIR" worktree remove --force "${WT_DIR}"
  else
    git --git-dir="$GIT_COMMON_DIR" worktree remove "${WT_DIR}"
  fi
fi

if [ -d "${WT_DIR}" ] && [ "$FORCE" -eq 1 ]; then
  rm -rf "${WT_DIR}" || true
fi

# Optional branch deletion (requires --delete-branch; uses safe -d unless --force is also passed)
if [ "$DELETE_BRANCH" -eq 1 ]; then
  BRANCH_FLAG="-d"
  [ "$FORCE" -eq 1 ] && BRANCH_FLAG="-D"

  for candidate in "${NAME}" "feat/${NAME}" "feature/${NAME}"; do
    if git --git-dir="$GIT_COMMON_DIR" show-ref --quiet "refs/heads/${candidate}"; then
      echo "Deleting branch '${candidate}' (${BRANCH_FLAG})..."
      git --git-dir="$GIT_COMMON_DIR" branch "${BRANCH_FLAG}" "${candidate}"
      break
    fi
  done
fi

echo "Worktree '${NAME}' removed successfully."
