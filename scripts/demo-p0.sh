#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$ROOT"
TMP="$(mktemp -d -t coheretron-p0-XXXXXX)"
ANVIL_PID=""
cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then kill "$ANVIL_PID" >/dev/null 2>&1 || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

RPC="http://127.0.0.1:8545"
PK_ADMIN="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
PK_ALICE="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
PK_BOB="0x5de4111afa1c4b3daadb870b03e76cc11901083fbaa436415a33b3b3422386"
ADMIN="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
ALICE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
BOB="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

log() { printf '\n==> %s\n' "$*"; }

log "1/8 Create GitLab-like repo and candidate MR commit"
WORK="$TMP/working"
mkdir -p "$WORK"
git -C "$WORK" init -q
git -C "$WORK" config user.email mvp@example.invalid
git -C "$WORK" config user.name "Coheretron MVP"
printf '# Rulebook\n\nVersion A\n' > "$WORK/document.md"
git -C "$WORK" add document.md
git -C "$WORK" commit -q -m 'canonical A'
PARENT="$(git -C "$WORK" rev-parse HEAD)"

git init --bare -q "$TMP/gitlab.git"
git -C "$WORK" remote add origin "$TMP/gitlab.git"
git -C "$WORK" push -q origin "$PARENT:refs/heads/main"
git -C "$WORK" checkout -q -b amendment-1
printf '# Rulebook\n\nVersion B — approved by consensus\n' > "$WORK/document.md"
git -C "$WORK" add document.md
git -C "$WORK" commit -q -m 'candidate B'
CANDIDATE="$(git -C "$WORK" rev-parse HEAD)"
git -C "$WORK" push -q origin "$CANDIDATE:refs/heads/amendment-1"
cat > "$TMP/mr.json" <<JSON
{"object_kind":"merge_request","project":{"id":1,"git_http_url":"$TMP/gitlab.git"},"object_attributes":{"iid":7,"action":"update","target_branch":"main","last_commit":{"id":"$CANDIDATE"}}}
JSON

log "2/8 Publish exact candidate to GOSH-compatible object store and verify round-trip"
git init --bare -q "$TMP/gosh.git"
MANIFEST="$(python3 "$ROOT/services/governance-adapter/prepare.py" \
  --webhook "$TMP/mr.json" \
  --document-id rulebook \
  --canonical-parent "$PARENT" \
  --source-repo "$WORK" \
  --object-store "$TMP/gosh.git" \
  --quorum-bps 10000 \
  --approval-bps 7500)"
AVAILABILITY="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["availability_hash"])' "$MANIFEST")"
printf 'candidate=%s\navailability=%s\n' "$CANDIDATE" "$AVAILABILITY"

log "3/8 Start local EVM and deploy canonical registry + ballot/delegation governor"
anvil --silent --host 127.0.0.1 --port 8545 >"$TMP/anvil.log" 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 30); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
cast block-number --rpc-url "$RPC" >/dev/null

cd "$ROOT"
forge build -q
REGISTRY_JSON="$(forge create contracts/src/CanonicalHeadRegistry.sol:CanonicalHeadRegistry --rpc-url "$RPC" --private-key "$PK_ADMIN" --broadcast --json)"
REGISTRY="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])' <<<"$REGISTRY_JSON")"
GOV_JSON="$(forge create contracts/src/CoheretronGovernor.sol:CoheretronGovernor --rpc-url "$RPC" --private-key "$PK_ADMIN" --broadcast --json --constructor-args "$REGISTRY")"
GOVERNOR="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])' <<<"$GOV_JSON")"
cast send "$REGISTRY" 'setGovernor(address)' "$GOVERNOR" --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null

DOC_ID="$(cast keccak 'rulebook')"
PAD='000000000000000000000000'
PARENT32="0x${PARENT}${PAD}"
CANDIDATE32="0x${CANDIDATE}${PAD}"
AVAIL32="0x${AVAILABILITY}"
cast send "$REGISTRY" 'initializeDocument(bytes32,(uint8,uint8,bytes32))' "$DOC_ID" "(1,20,$PARENT32)" --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null

log "4/8 Create ballot and configure fractional multi-hop delegation"
cast send "$GOVERNOR" 'createBallot(bytes32,(uint8,uint8,bytes32),(uint8,uint8,bytes32),bytes32,uint16,uint16)' \
  "$DOC_ID" "(1,20,$PARENT32)" "(1,20,$CANDIDATE32)" "$AVAIL32" 10000 7500 \
  --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null
BALLOT=1
TOTAL=100000000000000000000
cast send "$GOVERNOR" 'setEntitlement(uint256,address,uint256)' "$BALLOT" "$ALICE" "$TOTAL" --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null
cast send "$GOVERNOR" 'setDelegation(uint256,address,uint16)' "$BALLOT" "$BOB" 6000 --rpc-url "$RPC" --unlocked --from "$ALICE" >/dev/null
cast send "$GOVERNOR" 'setDelegation(uint256,address,uint16)' "$BALLOT" "$ADMIN" 5000 --rpc-url "$RPC" --unlocked --from "$BOB" >/dev/null
cast send "$GOVERNOR" 'openVoting(uint256,uint64)' "$BALLOT" 30 --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null

log "5/8 Cast 40% direct + 30% one-hop + 30% two-hop votes"
cast send "$GOVERNOR" 'castVote(uint256,address,address[],uint8,uint256)' "$BALLOT" "$ALICE" "[$ALICE]" 1 40000000000000000000 --rpc-url "$RPC" --unlocked --from "$ALICE" >/dev/null
cast send "$GOVERNOR" 'castVote(uint256,address,address[],uint8,uint256)' "$BALLOT" "$ALICE" "[$ALICE,$BOB]" 1 30000000000000000000 --rpc-url "$RPC" --unlocked --from "$BOB" >/dev/null
cast send "$GOVERNOR" 'castVote(uint256,address,address[],uint8,uint256)' "$BALLOT" "$ALICE" "[$ALICE,$BOB,$ADMIN]" 1 30000000000000000000 --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null
cast rpc --rpc-url "$RPC" evm_increaseTime 31 >/dev/null
cast rpc --rpc-url "$RPC" evm_mine >/dev/null
cast send "$GOVERNOR" 'finalize(uint256)' "$BALLOT" --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null
cast send "$GOVERNOR" 'execute(uint256)' "$BALLOT" --rpc-url "$RPC" --unlocked --from "$ADMIN" >/dev/null

HEAD_OUT="$(cast call "$REGISTRY" 'head(bytes32)(uint8,uint8,bytes32)' "$DOC_ID" --rpc-url "$RPC")"
DIGEST="$(printf '%s\n' "$HEAD_OUT" | tail -n 1 | awk '{print $1}')"
if [[ "${DIGEST:2:40}" != "$CANDIDATE" ]]; then
  echo "canonical head mismatch: $DIGEST vs $CANDIDATE" >&2
  exit 1
fi

log "6/8 Two independent Coheretron nodes fetch and publish the canonical document"
python3 "$ROOT/services/node/run.py" --name node-a --document-id rulebook --commit "$CANDIDATE" --object-store "$TMP/gosh.git" --workdir "$TMP/node-a/work" --publish-dir "$TMP/node-a/public" --canonical-state "$TMP/node-a/canonical.json"
python3 "$ROOT/services/node/run.py" --name node-b --document-id rulebook --commit "$CANDIDATE" --object-store "$TMP/gosh.git" --workdir "$TMP/node-b/work" --publish-dir "$TMP/node-b/public" --canonical-state "$TMP/node-b/canonical.json"
cmp "$TMP/node-a/public/current.md" "$TMP/node-b/public/current.md"
cmp "$TMP/node-a/public/current.md" "$WORK/document.md"

log "7/8 GitLab governed-branch hook accepts only the canonical SHA"
printf '%s %s refs/heads/main\n' "$PARENT" "$CANDIDATE" | COHERETRON_CANONICAL_STATE="$TMP/node-a/canonical.json" COHERETRON_DOCUMENT_ID=rulebook python3 "$ROOT/integrations/gitlab/hooks/pre_receive.py"
if printf '%s %s refs/heads/main\n' "$CANDIDATE" "$PARENT" | COHERETRON_CANONICAL_STATE="$TMP/node-a/canonical.json" COHERETRON_DOCUMENT_ID=rulebook python3 "$ROOT/integrations/gitlab/hooks/pre_receive.py"; then
  echo "governed hook accepted non-canonical SHA" >&2
  exit 1
fi

log "8/8 P0 proof complete"
printf 'GitLab MR candidate: %s\nCanonical HEAD:      %s\nNode A/B publication: identical\n' "$CANDIDATE" "$CANDIDATE"
