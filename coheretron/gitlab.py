from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


class GitLabWebhookError(ValueError):
    pass


@dataclass(frozen=True)
class MergeRequestCandidate:
    project_id: int
    mr_iid: int
    candidate_sha: str
    target_branch: str
    repository_url: str
    action: str


def parse_merge_request_webhook(payload: dict[str, Any]) -> MergeRequestCandidate:
    if payload.get("object_kind") != "merge_request":
        raise GitLabWebhookError("expected merge_request webhook")

    attrs = payload.get("object_attributes") or {}
    project = payload.get("project") or {}
    last_commit = attrs.get("last_commit") or {}
    sha = last_commit.get("id")
    if not sha or not isinstance(sha, str):
        raise GitLabWebhookError("merge request webhook has no last_commit.id")

    repo_url = project.get("git_http_url") or project.get("git_ssh_url")
    if not repo_url:
        raise GitLabWebhookError("project repository URL missing")

    return MergeRequestCandidate(
        project_id=int(project["id"]),
        mr_iid=int(attrs["iid"]),
        candidate_sha=sha,
        target_branch=str(attrs.get("target_branch") or "main"),
        repository_url=str(repo_url),
        action=str(attrs.get("action") or "unknown"),
    )


class GovernedBranchGuard:
    def __init__(self, state_path: str | Path):
        self.state_path = Path(state_path)

    def expected(self, document_id: str) -> str:
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        try:
            return str(state["documents"][document_id]["commit"])
        except KeyError as exc:
            raise GitLabWebhookError(f"canonical state missing for {document_id}") from exc

    def assert_allowed(self, document_id: str, new_sha: str) -> None:
        expected = self.expected(document_id)
        if new_sha != expected:
            raise GitLabWebhookError(
                f"governed branch requires canonical commit {expected}, received {new_sha}"
            )
