#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from coheretron.gitops import GitObjectStore
from coheretron.node import CoheretronNode


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize one canonical Git commit")
    parser.add_argument("--name", required=True)
    parser.add_argument("--document-id", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--object-store", required=True, help="git or gosh:// remote URL")
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--publish-dir", required=True)
    parser.add_argument("--canonical-state")
    parser.add_argument("--document-path", default="document.md")
    args = parser.parse_args()

    node = CoheretronNode(
        name=args.name,
        object_store=GitObjectStore(args.object_store),
        workdir=Path(args.workdir),
        publish_dir=Path(args.publish_dir),
        canonical_state_path=Path(args.canonical_state) if args.canonical_state else None,
        document_path=args.document_path,
    )
    result = node.sync(args.document_id, args.commit)
    print(f"{result.node}: published {result.document_id}@{result.commit} sha256={result.content_sha256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
