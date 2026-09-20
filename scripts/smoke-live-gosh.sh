#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$ROOT"

: "${GOSH_REMOTE:?Set GOSH_REMOTE to gosh://SYSTEM_CONTRACT/DAO/REPO}"
SOURCE_REPO="${SOURCE_REPO:-.}"
CANDIDATE="${CANDIDATE:-$(git -C "$SOURCE_REPO" rev-parse HEAD)}"

if ! command -v git-remote-gosh >/dev/null 2>&1; then
  echo "git-remote-gosh is required for a live GOSH smoke test" >&2
  exit 2
fi

python3 - "$SOURCE_REPO" "$GOSH_REMOTE" "$CANDIDATE" <<'PY'
import sys
from coheretron.gitops import GitObjectStore

source_repo, remote, oid = sys.argv[1:4]
proof = GitObjectStore(remote).publish(source_repo, oid)
print(f"GOSH live smoke OK: oid={proof.oid} ref={proof.ref} verified={proof.verified}")
PY
