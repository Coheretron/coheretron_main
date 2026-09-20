#!/usr/bin/env bash
set -euo pipefail

# Verify that pinned commits still exist in their upstream repositories.
# Requires network access and git.

check_pin() {
  local label="$1"
  local repo="$2"
  local branch="$3"
  local sha="$4"

  printf 'Checking %-12s %s @ %s ... ' "$label" "$repo" "$sha"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  git -C "$tmp" init -q
  git -C "$tmp" remote add upstream "$repo"

  if git -C "$tmp" fetch -q --depth=1 upstream "$sha"; then
    actual="$(git -C "$tmp" rev-parse FETCH_HEAD)"
    if [[ "$actual" == "$sha" ]]; then
      echo "OK"
    else
      echo "MISMATCH ($actual)"
      return 1
    fi
  else
    echo "NOT FOUND"
    return 1
  fi

  rm -rf "$tmp"
  trap - RETURN
}

check_pin gitlab https://github.com/gitlabhq/gitlabhq.git master 90edc25f8dc901b2ace05aab9b11665da6cb768d
check_pin gosh https://github.com/gosh-sh/gosh.git dev 7620917af0992257a4cbb25e2c48b9b7f948f70b
check_pin alligator https://github.com/voteagora/optimism-governor.git main cc8e959dcf2daa022c2a370a82394b12565843b1

echo "All upstream pins are resolvable."
