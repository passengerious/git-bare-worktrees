#!/usr/bin/env bash
# Interactive, per-repository hooks wizard for bare Git + main/ + wt/ layouts.
# Run from <project-root>/; installs directly into <project-root>/.bare/hooks/.
# Does not install dependencies, stage changes, or make commits.
set -euo pipefail

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ask() {
  local reply
  if ! IFS= read -r -p "$1" reply; then die 'Input ended; no changes made (unless previously confirmed).'; fi
  REPLY_TEXT="${reply:-${2:-}}"
}
yesno() {
  local prompt="$1" default="${2:-n}" choice
  while :; do
    if [[ "$default" == y ]]; then ask "$prompt [Y/n]: " y; else ask "$prompt [y/N]: " n; fi
    choice="${REPLY_TEXT,,}"
    case "$choice" in y|yes) return 0;; n|no) return 1;; *) warn 'Enter y or n.';; esac
  done
}
choice() {
  local prompt="$1" accepted="$2" default="$3" x
  while :; do
    ask "$prompt [$accepted] (default $default): " "$default"
    x="$REPLY_TEXT"
    case " $accepted " in *" $x "*) CHOICE="$x"; return 0;; esac
    warn "Choose one of: $accepted"
  done
}
usage() {
  cat <<'USAGE'
Usage: bash setup-bare-wt-hooks.sh

Run interactively from <project-root>/ (NOT main/) in a repository with:
  <project-root>/.bare/ (or bare .git/), main/, wt/

Creates .bare/hooks/{pre-commit,pre-push,run-checks.sh,config.sh,README.md}
(or .git/hooks), configures a shared absolute core.hooksPath to the same
bare hooks directory, and optionally generates a self-contained GitHub Actions
workflow in main/.github/workflows/git-guards.yml.
No dependencies are installed and no files are staged, committed, or pushed.
USAGE
}
if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then usage; exit 0; fi
[[ $# -eq 0 ]] || { usage; exit 2; }
command -v git >/dev/null || die 'git is required.'

PROJECT_ROOT="$(pwd -P)"
if [[ -d "$PROJECT_ROOT/.bare" ]]; then
  GIT_COMMON="$PROJECT_ROOT/.bare"
elif [[ -d "$PROJECT_ROOT/.git" ]]; then
  GIT_COMMON="$PROJECT_ROOT/.git"
else
  die 'Run from <project-root>/ with .bare/ (or a bare .git/) and main/.'
fi
[[ ! -L "$GIT_COMMON" ]] || die "Refusing symlinked common git dir: $GIT_COMMON"
GIT_COMMON="$(cd "$GIT_COMMON" && pwd -P)"
[[ "$(git --git-dir="$GIT_COMMON" rev-parse --is-bare-repository 2>/dev/null)" == true ]] || die "Not a bare repository: $GIT_COMMON"
MAIN_ROOT="$PROJECT_ROOT/main"
[[ -d "$MAIN_ROOT" ]] || die "Expected main/ checkout: $MAIN_ROOT"
[[ ! -L "$MAIN_ROOT" ]] || die "Refusing symlinked main/ checkout: $MAIN_ROOT"
MAIN_ROOT="$(cd "$MAIN_ROOT" && pwd -P)"
MAIN_TOP="$(git -C "$MAIN_ROOT" rev-parse --show-toplevel 2>/dev/null)" || die 'main/ is not a Git worktree.'
[[ "$(cd "$MAIN_TOP" && pwd -P)" == "$MAIN_ROOT" ]] || die 'main/ is not the worktree root.'
MAIN_COMMON="$(git -C "$MAIN_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die 'Failed to locate main/ common git dir.'
[[ "$(cd "$MAIN_COMMON" && pwd -P)" == "$GIT_COMMON" ]] || die 'main/ belongs to a different repository.'
[[ "$(git -C "$MAIN_ROOT" rev-parse --is-bare-repository)" == false ]] || die 'main/ is not a linked worktree.'
HOOK_DIR="$GIT_COMMON/hooks"
[[ ! -L "$HOOK_DIR" ]] || die "Refusing to write through symlinked hook directory: $HOOK_DIR"
WORKFLOW="$MAIN_ROOT/.github/workflows/git-guards.yml"

say ''
say 'Bare-worktree Git hooks setup'
say '-----------------------------'
say "Repository : $PROJECT_ROOT"
say "Main       : $MAIN_ROOT"
say "Bare Git   : $GIT_COMMON"
say "Hooks      : $HOOK_DIR"
if [[ -n "$(git -C "$MAIN_ROOT" status --porcelain)" ]]; then
  warn 'main/ has existing uncommitted/untracked files. The wizard will not stage or commit them.'
fi

PY_ENABLED=0 PY_BACKEND=off PY_RUFF=0 PY_TESTS=0
TS_ENABLED=0 TS_MODE=off TS_TYPECHECK=0 TS_TESTS=0
GITLEAKS=0 SCHEMA_SCRIPT='' CI_ENABLED=0
CI_PYTHON_VERSION=3.12 CI_NODE_VERSION=22 CI_PNPM_VERSION=10 CI_INSTALL=''

say ''
say '[1/4] Python checks'
PY_DEFAULT=n
[[ -f "$MAIN_ROOT/pyproject.toml" || -f "$MAIN_ROOT/pytest.ini" || -f "$MAIN_ROOT/requirements.txt" ]] && PY_DEFAULT=y
if yesno 'Enable Python checks?' "$PY_DEFAULT"; then
  PY_ENABLED=1
  BACKEND_DEFAULT=python
  [[ -d "$MAIN_ROOT/.venv" ]] && BACKEND_DEFAULT=venv
  [[ -f "$MAIN_ROOT/uv.lock" ]] && BACKEND_DEFAULT=uv
  choice 'Python runner (uv=offline/no-sync; venv=.venv; python=python3)' 'uv venv python' "$BACKEND_DEFAULT"
  PY_BACKEND="$CHOICE"
  if yesno 'Run Ruff lint on pre-push?' y; then PY_RUFF=1; fi
  if yesno 'Run pytest -q on pre-push? (can be slow)' n; then PY_TESTS=1; fi
fi

say ''
say '[2/4] TypeScript checks'
TS_DEFAULT=n
[[ -f "$MAIN_ROOT/package.json" || -f "$MAIN_ROOT/pnpm-workspace.yaml" ]] && TS_DEFAULT=y
if yesno 'Enable TypeScript/pnpm checks?' "$TS_DEFAULT"; then
  TS_ENABLED=1
  TS_MODE_DEFAULT=scripts
  [[ -f "$MAIN_ROOT/turbo.json" || -f "$MAIN_ROOT/turbo.jsonc" ]] && TS_MODE_DEFAULT=turbo
  choice 'TS runner (turbo=pnpm exec turbo run; scripts=pnpm run)' 'turbo scripts' "$TS_MODE_DEFAULT"
  TS_MODE="$CHOICE"
  if yesno 'Run TS typecheck on pre-push?' y; then TS_TYPECHECK=1; fi
  if yesno 'Run TS tests on pre-push? (can be slow)' n; then TS_TESTS=1; fi
fi

say ''
say '[3/4] Security and schema checks'
SECRET_DEFAULT=n
if command -v gitleaks >/dev/null 2>&1; then SECRET_DEFAULT=y; fi
if yesno 'Run Gitleaks on staged changes in pre-commit?' "$SECRET_DEFAULT"; then
  GITLEAKS=1
  command -v gitleaks >/dev/null 2>&1 || warn 'Gitleaks is not installed now; commits will fail until it is installed.'
fi
if yesno 'Run a project-owned schema/contract check on pre-push?' n; then
  ask 'Relative path to existing Bash checker, e.g. scripts/check-schema.sh: ' ''
  SCHEMA_SCRIPT="$REPLY_TEXT"
  [[ "$SCHEMA_SCRIPT" =~ ^[a-zA-Z0-9._/-]+$ && "$SCHEMA_SCRIPT" != /* && "$SCHEMA_SCRIPT" != ../* && "$SCHEMA_SCRIPT" != */../* && "$SCHEMA_SCRIPT" != */.. ]] || die 'Schema checker path must be a safe relative path inside the worktree.'
  [[ -f "$MAIN_ROOT/$SCHEMA_SCRIPT" ]] || die "Schema checker not found: $MAIN_ROOT/$SCHEMA_SCRIPT"
fi

say ''
say '[4/4] Continuous integration'
if yesno 'Generate optional GitHub Actions CI workflow?' n; then
  CI_ENABLED=1
  if [[ "$PY_ENABLED" -eq 1 ]]; then
    ask 'Python version for CI [3.12]: ' 3.12; CI_PYTHON_VERSION="$REPLY_TEXT"
    [[ "$CI_PYTHON_VERSION" =~ ^3\.[0-9]{1,2}$ ]] || die 'Expected a Python version such as 3.12.'
  fi
  if [[ "$TS_ENABLED" -eq 1 ]]; then
    ask 'Node major version for CI [22]: ' 22; CI_NODE_VERSION="$REPLY_TEXT"
    [[ "$CI_NODE_VERSION" =~ ^[0-9]{2}$ ]] || die 'Expected a Node major version such as 22.'
    ask 'pnpm major version for CI [10]: ' 10; CI_PNPM_VERSION="$REPLY_TEXT"
    [[ "$CI_PNPM_VERSION" =~ ^[0-9]{1,2}$ ]] || die 'Expected a pnpm major version such as 10.'
  fi
  INSTALL_SUGGESTION=''
  if [[ "$PY_ENABLED" -eq 1 ]]; then
    case "$PY_BACKEND" in
      uv) INSTALL_SUGGESTION='uv sync --frozen';;
      venv) INSTALL_SUGGESTION="python -m venv .venv && .venv/bin/python -m pip install -e '.[dev]'";;
      python) INSTALL_SUGGESTION="python -m pip install -e '.[dev]'";;
    esac
  fi
  if [[ "$TS_ENABLED" -eq 1 ]]; then
    if [[ -n "$INSTALL_SUGGESTION" ]]; then INSTALL_SUGGESTION+=' && '; fi
    INSTALL_SUGGESTION+='pnpm install --frozen-lockfile'
  fi
  say 'CI requires installed project dependencies. Review/edit this suggested command.'
  ask "CI dependency setup command [$INSTALL_SUGGESTION]: " "$INSTALL_SUGGESTION"
  CI_INSTALL="$REPLY_TEXT"
  [[ -n "$CI_INSTALL" && "$CI_INSTALL" != *$'\n'* && "$CI_INSTALL" != *$'\r'* ]] || die 'CI install command must be a nonempty single line.'
fi

say ''
say 'Selected configuration:'
say "  Python     : $PY_BACKEND (Ruff=$PY_RUFF, pytest=$PY_TESTS)"
say "  TypeScript : $TS_MODE (typecheck=$TS_TYPECHECK, tests=$TS_TESTS)"
say "  Gitleaks   : $GITLEAKS"
say "  Schema     : ${SCHEMA_SCRIPT:-disabled}"
say "  GitHub CI  : $CI_ENABLED"
say "  Hooks path : $HOOK_DIR (shared by linked worktrees)"

EXISTING_PATH="$(git -C "$MAIN_ROOT" config --show-origin --get core.hooksPath || true)"
CURRENT_EFFECTIVE="$(git -C "$MAIN_ROOT" config --get core.hooksPath || true)"
if [[ -n "$CURRENT_EFFECTIVE" && "$CURRENT_EFFECTIVE" != "$HOOK_DIR" ]]; then
  warn "core.hooksPath currently points elsewhere: $EXISTING_PATH"
  warn "The wizard will set shared core.hooksPath to $HOOK_DIR."
fi
# A per-worktree override can supersede shared core.hooksPath. Refuse to claim
# that all worktrees are covered while such an override is present.
while IFS= read -r worktree_line; do
  [[ "$worktree_line" == worktree\ * ]] || continue
  wt="${worktree_line#worktree }"
  [[ -d "$wt" ]] || continue
  if wt_file="$(git -C "$wt" rev-parse --git-path config.worktree 2>/dev/null)" && [[ -f "$wt_file" ]]; then
    if git config --file "$wt_file" --get core.hooksPath >/dev/null 2>&1; then
      die "Per-worktree core.hooksPath override detected in $wt_file. Remove/review it before installation."
    fi
  fi
done < <(git --git-dir="$GIT_COMMON" worktree list --porcelain)
if [[ "$CI_ENABLED" -eq 1 && -e "$WORKFLOW" ]]; then warn "Existing CI file will be replaced: $WORKFLOW"; fi
[[ ! -L "$WORKFLOW" ]] || die "Refusing to overwrite a symlinked workflow: $WORKFLOW"
for file in config.sh run-checks.sh pre-commit pre-push README.md; do
  [[ ! -L "$HOOK_DIR/$file" ]] || die "Refusing to overwrite symlink: $HOOK_DIR/$file"
done
for file in config.sh run-checks.sh pre-commit pre-push README.md; do
  if [[ -e "$HOOK_DIR/$file" ]]; then
    warn "Existing hook asset $HOOK_DIR/$file will be backed up and replaced."
  fi
done
if ! yesno 'Apply this configuration?' n; then say 'Cancelled; no changes made.'; exit 0; fi

# Back up only the files we overwrite. Bare directory is outside the tracked worktree.
BACKUP_DIR="$GIT_COMMON/hooks-wizard-backups/$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_CREATED=0
backup() {
  local target="$1" relative
  if [[ -e "$target" ]]; then
    relative="${target#"$PROJECT_ROOT"/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
    cp -p "$target" "$BACKUP_DIR/$relative"
    BACKUP_CREATED=1
  fi
}
for file in config.sh run-checks.sh pre-commit pre-push README.md; do backup "$HOOK_DIR/$file"; done
if [[ "$CI_ENABLED" -eq 1 ]]; then backup "$WORKFLOW"; fi
mkdir -p "$HOOK_DIR"

# %q produces Bash-escaped config values; no eval and no project-supplied code executed by setup.
{
  say '# Generated by setup-bare-wt-hooks.sh. LOCAL bare repository hooks config; not Git-tracked. No secrets.'
  for key in PY_BACKEND PY_RUFF PY_TESTS TS_MODE TS_TYPECHECK TS_TESTS GITLEAKS SCHEMA_SCRIPT; do
    printf '%s=%q\n' "$key" "${!key}"
  done
} > "$HOOK_DIR/config.sh"

cat > "$HOOK_DIR/run-checks.sh" <<'RUNNER'
#!/usr/bin/env bash
# Called by Git in the calling worktree; scripts themselves live in <bare>/hooks.
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPTS_DIR/config.sh"
mode="${1:-}"
case "$mode" in pre-commit|pre-push|ci) ;; *) echo 'Usage: run-checks.sh {pre-commit|pre-push|ci}' >&2; exit 2;; esac
command -v git >/dev/null || { echo 'git is missing' >&2; exit 1; }
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo 'Not in a Git worktree' >&2; exit 1; }
CURRENT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
SOURCE_COMMON="$(cd "$SCRIPTS_DIR/.." && pwd -P)"
CURRENT_COMMON="$(cd "$CURRENT_COMMON" && pwd -P)"
SOURCE_COMMON="$(cd "$SOURCE_COMMON" && pwd -P)"
[[ "$CURRENT_COMMON" == "$SOURCE_COMMON" ]] || { echo 'Refusing to run hooks for a different repository.' >&2; exit 1; }
cd "$CURRENT_ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { printf 'Missing required executable: %s\n' "$1" >&2; return 1; }; }
check_python() {
  local module="$1"; shift
  case "$PY_BACKEND" in
    uv)
      need uv
      # Local hooks never sync dependencies or download Python interpreters.
      UV_PYTHON_DOWNLOADS=never uv run --offline --no-sync python -m "$module" "$@"
      ;;
    venv)
      [[ -x .venv/bin/python ]] || { echo 'Missing .venv/bin/python in the active worktree' >&2; return 1; }
      .venv/bin/python -m "$module" "$@"
      ;;
    python)
      need python3
      python3 -m "$module" "$@"
      ;;
    *) echo "Unsupported Python runner: $PY_BACKEND" >&2; return 1;;
  esac
}
check_ts() {
  local task="$1"
  need pnpm
  case "$TS_MODE" in
    turbo) CI=1 pnpm exec turbo run "$task";;
    scripts) CI=1 pnpm run "$task";;
    *) echo "Unsupported TS runner: $TS_MODE" >&2; return 1;;
  esac
}

if [[ "$mode" == pre-commit ]]; then
  echo '[pre-commit] staged whitespace / conflict marker checks'
  git diff --cached --check
  if [[ "$GITLEAKS" == 1 ]]; then
    echo '[pre-commit] Gitleaks staged secret scan'
    need gitleaks
    gitleaks git --pre-commit --staged --redact --no-banner
  fi
  echo '[pre-commit] OK'
  exit 0
fi

# Consume pre-push hook input to avoid leaving Git's pipe unread.
if [[ "$mode" == pre-push ]]; then cat >/dev/null; fi

if [[ "$PY_BACKEND" != off ]]; then
  if [[ "$PY_RUFF" == 1 ]]; then
    echo "[$mode] Python Ruff check"
    check_python ruff check .
  fi
  if [[ "$PY_TESTS" == 1 ]]; then
    echo "[$mode] Python pytest"
    CI=1 check_python pytest -q
  fi
fi
if [[ "$TS_MODE" != off ]]; then
  if [[ "$TS_TYPECHECK" == 1 ]]; then
    echo "[$mode] TS typecheck"
    check_ts typecheck
  fi
  if [[ "$TS_TESTS" == 1 ]]; then
    echo "[$mode] TS tests"
    check_ts test
  fi
fi
if [[ -n "$SCHEMA_SCRIPT" ]]; then
  [[ -f "$SCHEMA_SCRIPT" ]] || { echo "Missing schema checker in active worktree: $SCHEMA_SCRIPT" >&2; exit 1; }
  echo "[$mode] schema/contract check: $SCHEMA_SCRIPT"
  bash "./$SCHEMA_SCRIPT"
fi
echo "[$mode] OK"
RUNNER

cat > "$HOOK_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$SCRIPTS_DIR/run-checks.sh" pre-commit
HOOK
cat > "$HOOK_DIR/pre-push" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$SCRIPTS_DIR/run-checks.sh" pre-push
HOOK
chmod 755 "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push" "$HOOK_DIR/run-checks.sh"
chmod 644 "$HOOK_DIR/config.sh"
cat > "$HOOK_DIR/README.md" <<'DOC'
# Shared hooks: bare Git + linked-worktree repository

Installed directly in the common Git directory (`.bare/hooks/` or `.git/hooks/`).
All linked worktrees share these files. The wizard sets the shared repository
`core.hooksPath` to this absolute directory so prior overrides do not mask it.
Hooks run checks against the **calling** worktree, not `main/`.

- `pre-commit`: `git diff --cached --check` (staged whitespace/conflict markers),
  optionally `gitleaks git --pre-commit --staged --redact --no-banner`.
- `pre-push`: selected Python Ruff/pytest; pnpm/Turbo typecheck/tests; and an
  optional project-owned Bash schema checker.
- `run-checks.sh ci`: manually run the same pre-push validations from any worktree.
- `config.sh`: local wizard configuration, not Git-tracked. No secrets.

Run manually from an existing linked worktree:

```bash
bash "$(git rev-parse --git-common-dir)/hooks/run-checks.sh" ci
```

Hooks do **not** install packages or sync lockfiles. If a selected tool is
missing, the check fails. Python `uv` uses `--offline --no-sync` to avoid
implicit installation. Project-owned schema/contract checks must be
implemented and available in every worktree where they run.

The optional GitHub Actions workflow is **self-contained**, because CI checkouts
will not have this local bare hooks directory. Review CI installs and checks.
Gitleaks staged scanning runs locally at pre-commit, not in the generated CI;
configure separate CI secret scanning/branch protection if enforcement is needed.

This setup is local to this Git repository; fresh clones need to rerun the wizard.
Git hooks can be bypassed, so require CI/branch protection for enforcement.
DOC

if [[ "$CI_ENABLED" -eq 1 ]]; then
  mkdir -p "$(dirname "$WORKFLOW")"
  {
    cat <<'YAML'
name: Git guards
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
    if [[ "$PY_ENABLED" -eq 1 ]]; then
      printf "      - uses: actions/setup-python@v5\n        with:\n          python-version: '%s'\n" "$CI_PYTHON_VERSION"
      if [[ "$PY_BACKEND" == uv ]]; then
        say '      - uses: astral-sh/setup-uv@v6'
      fi
    fi
    if [[ "$TS_ENABLED" -eq 1 ]]; then
      printf '      - uses: actions/setup-node@v4\n        with:\n          node-version: %s\n' "$CI_NODE_VERSION"
      printf '      - uses: pnpm/action-setup@v4\n        with:\n          version: %s\n          run_install: false\n' "$CI_PNPM_VERSION"
    fi
    say '      - name: Install project dependencies'
    say '        shell: bash'
    say '        run: |'
    printf '          %s\n' "$CI_INSTALL"
    say '      - name: Run configured checks'
    say '        shell: bash'
    say '        env:'
    say '          CI: "true"'
    say '        run: |'
    if [[ "$PY_ENABLED" -eq 1 ]]; then
      case "$PY_BACKEND" in
        uv) PY_CI_CMD='UV_PYTHON_DOWNLOADS=never uv run --offline --no-sync python -m';;
        venv) PY_CI_CMD='.venv/bin/python -m';;
        python) PY_CI_CMD='python3 -m';;
      esac
      [[ "$PY_RUFF" -eq 1 ]] && printf '          %s ruff check .\n' "$PY_CI_CMD"
      [[ "$PY_TESTS" -eq 1 ]] && printf '          %s pytest -q\n' "$PY_CI_CMD"
    fi
    if [[ "$TS_ENABLED" -eq 1 ]]; then
      if [[ "$TS_MODE" == turbo ]]; then
        TS_CI_CMD='pnpm exec turbo run'
      else
        TS_CI_CMD='pnpm run'
      fi
      [[ "$TS_TYPECHECK" -eq 1 ]] && printf '          %s typecheck\n' "$TS_CI_CMD"
      [[ "$TS_TESTS" -eq 1 ]] && printf '          %s test\n' "$TS_CI_CMD"
    fi
    if [[ -n "$SCHEMA_SCRIPT" ]]; then
      printf "          bash './%s'\n" "$SCHEMA_SCRIPT"
    fi
    if [[ "$PY_RUFF" == 0 && "$PY_TESTS" == 0 && "$TS_TYPECHECK" == 0 && "$TS_TESTS" == 0 && -z "$SCHEMA_SCRIPT" ]]; then
      say "          echo 'No CI checks selected.'"
    fi
  } > "$WORKFLOW"
fi

# Explicit shared hooks path prevents global/core.hooksPath from shadowing
# the bare hooks directory. All linked worktrees inherit this local setting.
git -C "$MAIN_ROOT" config --local core.hooksPath "$HOOK_DIR"

say ''
say 'Installed successfully.'
say "  core.hooksPath: $(git -C "$MAIN_ROOT" config --local --get core.hooksPath)"
say '  pre-commit and pre-push apply to main/ and wt/ worktrees.'
say '  No dependencies installed; no files staged, committed, or pushed.'
if [[ "$BACKUP_CREATED" -eq 1 ]]; then say "  Backups: $BACKUP_DIR"; else rmdir "$BACKUP_DIR" 2>/dev/null || true; fi
say ''
say 'Next steps:'
say '  1. Review generated bare hooks/config.sh and scripts.'
say '  2. Install or activate the selected project tools yourself.'
say "  3. Test from main/: bash $HOOK_DIR/run-checks.sh ci"
say '  4. Hooks are local-only; stage the optional .github/workflows/git-guards.yml if desired.'
say '  5. Commit the optional workflow only when explicitly ready.'
