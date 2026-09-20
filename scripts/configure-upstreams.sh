#!/usr/bin/env bash
set -euo pipefail

# Configure coordination remotes for the Coheretron integration monorepo.
# These remotes point at the three upstream source repositories and the
# expected Coheretron forks. The source trees are not vendored here.

ensure_remote() {
  local name="$1"
  local url="$2"

  if git remote get-url "$name" >/dev/null 2>&1; then
    git remote set-url "$name" "$url"
  else
    git remote add "$name" "$url"
  fi
}

ensure_remote gitlab-upstream https://github.com/gitlabhq/gitlabhq.git
ensure_remote gitlab-fork https://github.com/Coheretron/gitlabhq.git

ensure_remote gosh-upstream https://github.com/gosh-sh/gosh.git
ensure_remote gosh-fork https://github.com/Coheretron/gosh.git

ensure_remote alligator-upstream https://github.com/voteagora/optimism-governor.git
ensure_remote alligator-fork https://github.com/Coheretron/optimism-governor.git

cat <<'EOF'
Configured Coheretron remotes:

  gitlab-upstream
  gitlab-fork
  gosh-upstream
  gosh-fork
  alligator-upstream
  alligator-fork

Run:
  git remote -v

Pinned source SHAs are recorded in upstreams/manifest.yaml.
EOF
