#!/bin/bash
set -euo pipefail
#
# base/update.sh — THiNX base-image rebuild + auto-version-bump + atomic commit
#
# Hardened per BASE-IMG-01 (Phase 11, v1.9 milestone). Replaces the previous
# 18-line fire-and-forget script with strict error handling, CLI args,
# pre/post image digest logging, and exactly ONE atomic GPG-signed commit
# (`chore: base version bump`) on success.
#
# Operator-facing CLI:
#   base/update.sh [--tag <tag>] [--owner <owner>] [--dry-run] [--help]
#

usage() {
  cat <<'EOF'
Usage: base/update.sh [--tag <tag>] [--owner <owner>] [--dry-run] [--help]

Options:
  --tag <tag>      Base image tag (default: alpine)
  --owner <owner>  Docker Hub owner / namespace (default: thinxcloud)
  --dry-run        Run all checks + version bump + digest reads,
                   skip docker buildx build, docker push, and git commit
  --help           Print this usage block and exit 0
EOF
}

# -----------------------------------------------------------------------------
# (3) Default values
# -----------------------------------------------------------------------------
TAG="alpine"
OWNER="thinxcloud"
DRY_RUN=0

# -----------------------------------------------------------------------------
# (4) Arg parsing — long-form flags via manual case loop (getopts is
#     short-flag-only without GNU extensions, hence not used here).
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "☣ --tag requires a value" >&2
        usage >&2
        exit 64
      fi
      TAG="$2"
      shift 2
      ;;
    --owner)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "☣ --owner requires a value" >&2
        usage >&2
        exit 64
      fi
      OWNER="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "☣ Unknown arg: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

echo "▶ Tag:   $TAG"
echo "▶ Owner: $OWNER"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "▶ Mode:  DRY-RUN (no docker build, no docker push, no git commit)"
else
  echo "▶ Mode:  full run"
fi

# -----------------------------------------------------------------------------
# (5) Locate repo root — fails fast under set -e if not in a git repo.
# -----------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "▶ Repo root: $REPO_ROOT"

# -----------------------------------------------------------------------------
# (6) Pre-build digest probe — best-effort, non-fatal. The `|| true` is
#     deliberately scoped to this single command: on a clean machine where
#     the image has never been built, `docker image inspect` exits 1 and
#     that is expected. Subsequent commands remain under `set -e`.
#
#     Note: `docker image inspect` emits a stray newline on stdout before
#     failing for missing images, so we strip any stray whitespace and
#     fall back to a human-readable placeholder if the captured value is
#     blank — keeping the log line single-line and operator-friendly.
# -----------------------------------------------------------------------------
PRE_DIGEST="$(docker image inspect "$OWNER/base:$TAG" --format='{{index .RepoDigests 0}}' 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$PRE_DIGEST" ]]; then
  PRE_DIGEST="none (first build or local-only)"
fi
echo "▶ Pre-build digest: $PRE_DIGEST"

# -----------------------------------------------------------------------------
# (7) Auto patch-version bump on the REPO-ROOT package.json.
#     `npm version patch --no-git-tag-version` mutates the version field
#     and (if package-lock.json exists) the lockfile, with NO auto-commit
#     and NO auto-tag — this script owns the commit boundary.
# -----------------------------------------------------------------------------
pushd "$REPO_ROOT" >/dev/null
BEFORE_VERSION="$(node -p "require('./package.json').version")"
if [[ $DRY_RUN -eq 0 ]]; then
  npm version patch --no-git-tag-version >/dev/null
fi
AFTER_VERSION="$(node -p "require('./package.json').version")"
echo "▶ Version bump: $BEFORE_VERSION → $AFTER_VERSION"
popd >/dev/null

# -----------------------------------------------------------------------------
# (8) Build steps — run from base/ (where the Dockerfile lives).
#
#     The `rm -rf ./node_modules/` and `rm -rf ./package-lock.json` lines
#     are preserved from the original script. They target the BASE/
#     subdirectory's node_modules + package-lock (relative paths), NOT the
#     parent repo's. This is the intentional clean-rebuild pattern: every
#     base-image build starts from a fresh lockfile so transitive deps are
#     re-resolved against the latest npm registry view.
# -----------------------------------------------------------------------------
cd "$(dirname "$0")"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "▶ DRY-RUN: skipping rm -rf ./node_modules/, rm -rf ./package-lock.json, npm install, npm audit fix, docker buildx, docker push"
  POST_DIGEST="(dry-run — image not rebuilt)"
else
  rm -rf ./node_modules/
  rm -rf ./package-lock.json
  npm install . --omit=dev
  npm audit fix
  docker buildx build --platform=linux/amd64 -t "$OWNER/base:$TAG" .
  docker push "$OWNER/base:$TAG"

  # ---------------------------------------------------------------------------
  # (9) Post-build digest probe — `|| true` scoped to this single command for
  #     the same reason as the pre-build probe (registry round-trip may briefly
  #     fail; the operator still gets a non-empty audit line). Same
  #     stray-newline workaround as the pre-build probe.
  # ---------------------------------------------------------------------------
  POST_DIGEST="$(docker image inspect "$OWNER/base:$TAG" --format='{{index .RepoDigests 0}}' 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -z "$POST_DIGEST" ]]; then
    POST_DIGEST="unknown"
  fi
fi
echo "▶ Post-build digest: $POST_DIGEST"

# -----------------------------------------------------------------------------
# (10) Atomic commit — staging ONLY the root package.json (+ root
#      package-lock.json if regenerated). node_modules is gitignored. The
#      commit is GPG-signed per project convention (Phase 5–10 precedent).
# -----------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
  cd "$REPO_ROOT"
  git add package.json
  if [[ -f package-lock.json ]]; then
    git add package-lock.json
  fi
  git commit -S -m "chore: base version bump"
  echo "✔ Committed: chore: base version bump ($BEFORE_VERSION → $AFTER_VERSION, image $OWNER/base:$TAG digest $POST_DIGEST)"
fi

# -----------------------------------------------------------------------------
# (11) Final summary
# -----------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "✔ DRY-RUN complete — would have bumped $BEFORE_VERSION → next patch, built $OWNER/base:$TAG"
else
  echo "✔ Done — $OWNER/base:$TAG ($AFTER_VERSION) pushed; digest $POST_DIGEST."
fi
