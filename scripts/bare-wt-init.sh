#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if ! command -v git >/dev/null 2>&1; then
  die "git is required but was not found in PATH."
fi

PROJECT_ROOT="$(pwd)"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LOCAL_SCRIPT_PATH="$PROJECT_ROOT/$(basename "$0")"

if [ -e "$PROJECT_ROOT/.git" ] || [ -e "$PROJECT_ROOT/.bare" ] || [ -e "$PROJECT_ROOT/main" ] || [ -e "$PROJECT_ROOT/wt" ]; then
  die "target directory already contains .git, .bare, main, or wt; run this only from a blank project directory."
fi

while IFS= read -r entry; do
  if [ "$SCRIPT_PATH" = "$LOCAL_SCRIPT_PATH" ] && [ "$entry" = "$LOCAL_SCRIPT_PATH" ]; then
    continue
  fi

  die "target directory is not blank; only $(basename "$0") may exist when running a local copy."
done < <(find "$PROJECT_ROOT" -mindepth 1 -maxdepth 1 -print)

mkdir wt

git init --bare -b main .bare
printf 'gitdir: .bare\n' > .git

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config --get user.name || printf 'agent-init')}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config --get user.email || printf 'agent-init@example.invalid')}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

README_BLOB="$(printf '### README.md\n' | git --git-dir=.bare hash-object -w --stdin)"
README_TREE="$(printf '100644 blob %s\tREADME.md\n' "$README_BLOB" | git --git-dir=.bare mktree)"
INITIAL_COMMIT="$(printf 'initial commit\n' | git --git-dir=.bare commit-tree "$README_TREE")"

git --git-dir=.bare config core.bare true
git --git-dir=.bare config --unset core.worktree >/dev/null 2>&1 || true
git --git-dir=.bare symbolic-ref HEAD refs/heads/main
git --git-dir=.bare update-ref refs/heads/main "$INITIAL_COMMIT"
git worktree add main main

printf 'Initialized bare worktree project at %s\n' "$PROJECT_ROOT"
git worktree list
