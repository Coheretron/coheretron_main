from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
import tempfile


class GitError(RuntimeError):
    pass


def _run_git(*args: str, cwd: Path | None = None) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise GitError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


@dataclass(frozen=True)
class AvailabilityProof:
    oid: str
    ref: str
    verified: bool


class GitRepository:
    def __init__(self, path: str | Path):
        self.path = Path(path)

    def head(self) -> str:
        return _run_git("rev-parse", "HEAD", cwd=self.path)

    def ensure_commit(self, oid: str) -> None:
        actual = _run_git("rev-parse", f"{oid}^{{commit}}", cwd=self.path)
        if actual != oid:
            raise GitError(f"expected commit {oid}, got {actual}")

    def show_file(self, oid: str, relative_path: str) -> bytes:
        proc = subprocess.run(
            ["git", "show", f"{oid}:{relative_path}"],
            cwd=str(self.path),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            raise GitError(proc.stderr.decode().strip())
        return proc.stdout


class GitObjectStore:
    """Git remote adapter used by P0.

    A local bare Git repository can be used in tests. A GOSH URL works through
    Git's remote-helper mechanism when git-remote-gosh is installed.
    """

    def __init__(self, remote_url: str):
        self.remote_url = remote_url

    @staticmethod
    def candidate_ref(oid: str) -> str:
        return f"refs/coheretron/candidates/{oid}"

    def _validate_runtime(self) -> None:
        if self.remote_url.startswith("gosh://") and shutil.which("git-remote-gosh") is None:
            raise GitError("gosh:// remote requires git-remote-gosh in PATH")

    def publish(self, source_repo: str | Path, oid: str) -> AvailabilityProof:
        self._validate_runtime()
        repo = GitRepository(source_repo)
        repo.ensure_commit(oid)
        ref = self.candidate_ref(oid)
        _run_git("push", self.remote_url, f"{oid}:{ref}", cwd=repo.path)
        self.verify(oid)
        return AvailabilityProof(oid=oid, ref=ref, verified=True)

    def verify(self, oid: str) -> None:
        self._validate_runtime()
        ref = self.candidate_ref(oid)
        with tempfile.TemporaryDirectory(prefix="coheretron-verify-") as tmp:
            path = Path(tmp)
            _run_git("init", "-q", cwd=path)
            _run_git("remote", "add", "store", self.remote_url, cwd=path)
            _run_git("fetch", "-q", "store", ref, cwd=path)
            actual = _run_git("rev-parse", "FETCH_HEAD", cwd=path)
            if actual != oid:
                raise GitError(f"OID mismatch: expected {oid}, got {actual}")
            _run_git("cat-file", "-e", f"{oid}^{{commit}}", cwd=path)
            _run_git("fsck", "--strict", "--no-reflogs", cwd=path)

    def fetch_to(self, oid: str, target: str | Path) -> Path:
        self._validate_runtime()
        target = Path(target)
        target.mkdir(parents=True, exist_ok=True)
        if not (target / ".git").exists():
            _run_git("init", "-q", cwd=target)
            _run_git("remote", "add", "store", self.remote_url, cwd=target)
        else:
            remotes = _run_git("remote", cwd=target).splitlines()
            if "store" in remotes:
                _run_git("remote", "set-url", "store", self.remote_url, cwd=target)
            else:
                _run_git("remote", "add", "store", self.remote_url, cwd=target)

        ref = self.candidate_ref(oid)
        _run_git("fetch", "-q", "store", ref, cwd=target)
        actual = _run_git("rev-parse", "FETCH_HEAD", cwd=target)
        if actual != oid:
            raise GitError(f"OID mismatch: expected {oid}, got {actual}")
        _run_git("checkout", "-q", "--detach", oid, cwd=target)
        _run_git("fsck", "--strict", "--no-reflogs", cwd=target)
        return target
