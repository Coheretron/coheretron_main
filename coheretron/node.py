from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import tempfile

from .gitops import GitObjectStore


@dataclass(frozen=True)
class SyncResult:
    node: str
    document_id: str
    commit: str
    content_sha256: str
    published_path: Path


class CoheretronNode:
    def __init__(
        self,
        *,
        name: str,
        object_store: GitObjectStore,
        workdir: str | Path,
        publish_dir: str | Path,
        document_path: str = "document.md",
        canonical_state_path: str | Path | None = None,
    ):
        self.name = name
        self.object_store = object_store
        self.workdir = Path(workdir)
        self.publish_dir = Path(publish_dir)
        self.document_path = document_path
        self.canonical_state_path = Path(canonical_state_path) if canonical_state_path else None

    @staticmethod
    def _atomic_write(path: Path, data: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
            tmp.write(data)
            tmp.flush()
            tmp_path = Path(tmp.name)
        tmp_path.replace(path)

    def sync(self, document_id: str, oid: str) -> SyncResult:
        repo_dir = self.workdir / "repo"
        self.object_store.fetch_to(oid, repo_dir)
        content = (repo_dir / self.document_path).read_bytes()
        content_hash = sha256(content).hexdigest()

        current = self.publish_dir / "current.md"
        metadata = self.publish_dir / "current.json"
        self._atomic_write(current, content)
        self._atomic_write(
            metadata,
            json.dumps(
                {
                    "node": self.name,
                    "document_id": document_id,
                    "commit": oid,
                    "content_sha256": content_hash,
                },
                sort_keys=True,
                indent=2,
            ).encode(),
        )

        if self.canonical_state_path:
            self._atomic_write(
                self.canonical_state_path,
                json.dumps(
                    {"documents": {document_id: {"commit": oid}}},
                    sort_keys=True,
                    indent=2,
                ).encode(),
            )

        return SyncResult(
            node=self.name,
            document_id=document_id,
            commit=oid,
            content_sha256=content_hash,
            published_path=current,
        )
