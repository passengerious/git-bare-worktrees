#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
BASE="${2:-main}"
BRANCH="${3:-${NAME}}"

if [ -z "$NAME" ]; then
  echo "Usage: worktree-add.sh <worktree-name> [base-branch] [branch-name]"
  exit 1
fi

GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "Error: Not inside a Git repository."
  exit 1
fi

PROJECT_ROOT="$(dirname "$GIT_COMMON_DIR")"
MAIN_DIR="${PROJECT_ROOT}/main"
WT_DIR="${PROJECT_ROOT}/wt/${NAME}"

if [ -d "${WT_DIR}" ]; then
  echo "Error: Worktree path already exists at ${WT_DIR}."
  exit 1
fi

echo "Creating worktree at ${WT_DIR}..."
if git --git-dir="$GIT_COMMON_DIR" show-ref --quiet "refs/heads/${BRANCH}"; then
  echo "Attaching worktree to existing branch '${BRANCH}'..."
  git --git-dir="$GIT_COMMON_DIR" worktree add "${WT_DIR}" "${BRANCH}"
else
  echo "Creating branch '${BRANCH}' from base '${BASE}'..."
  git --git-dir="$GIT_COMMON_DIR" worktree add "${WT_DIR}" -b "${BRANCH}" "${BASE}"
fi

# Mirror root node_modules safely for pnpm v12 (directory with symlinked entries)
if [ -d "${MAIN_DIR}/node_modules" ]; then
  echo "Mirroring root node_modules..."
  mkdir -p "${WT_DIR}/node_modules"
  for item in "${MAIN_DIR}/node_modules"/* "${MAIN_DIR}/node_modules"/.*; do
    base="$(basename "$item")"
    if [ "$base" != "." ] && [ "$base" != ".." ] && [ "$base" != ".pnpm-task-run-state-v1" ] && [ "$base" != ".pnpm-workspace-state-v1.json" ] && [ -e "$item" ]; then
      ln -sf "$item" "${WT_DIR}/node_modules/$base"
    fi
  done
fi

# Dynamically symlink subpackage node_modules across any monorepo structure
if [ -d "${MAIN_DIR}" ]; then
  find "${MAIN_DIR}" -mindepth 2 -maxdepth 3 -type d -name "node_modules" ! -path "*/node_modules/*" 2>/dev/null | while read -r pkg_nm; do
    rel="${pkg_nm#"${MAIN_DIR}/"}"
    target_parent="${WT_DIR}/$(dirname "$rel")"
    if [ -d "$target_parent" ]; then
      echo "Symlinking $rel..."
      ln -sf "$pkg_nm" "${WT_DIR}/$rel"
    fi
  done
fi

# Dynamically copy local .env files (without exposing contents)
if [ -d "${MAIN_DIR}" ]; then
  echo "Copying local environment files..."
  find "${MAIN_DIR}" -maxdepth 3 -type f \( -name ".env" -o -name ".env.local" \) ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | while read -r env_file; do
    rel="${env_file#"${MAIN_DIR}/"}"
    target_file="${WT_DIR}/$rel"
    if [ -d "$(dirname "$target_file")" ]; then
      echo "Copying $rel..."
      cp "$env_file" "$target_file"
    fi
  done
fi

# Optional project hooks
if [ -x "${WT_DIR}/scripts/worktree-post-add.sh" ]; then
  echo "Executing project post-add hook..."
  bash "${WT_DIR}/scripts/worktree-post-add.sh" "${WT_DIR}"
elif [ -x "${PROJECT_ROOT}/.agents/hooks/post-worktree-add.sh" ]; then
  echo "Executing agent post-add hook..."
  bash "${PROJECT_ROOT}/.agents/hooks/post-worktree-add.sh" "${WT_DIR}"
fi

echo "Worktree ready at ${WT_DIR}"
