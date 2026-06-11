#!/bin/bash
# agent-cli.sh — PC-side wrapper for the in-cluster `agent` binary.
# Bash counterpart to bin/agent-cli.ps1; same defaults, same config-file lookup.
#
# Usage:
#   ./bin/agent-cli.sh workflow run alice-e2e --workspace workspace-alice
#   ./bin/agent-cli.sh hive publish --workspace workspace-alice --topic hivemind/feed --payload 'hi'
#   ./bin/agent-cli.sh dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"hi","max_tokens":16}'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Defaults ─────────────────────────────────────────────────────────────────
SSH_KEY="$REPO_ROOT/auth cloud/id_ed25519"
SSH_HOST="webmcp@37.27.188.52"
OPERATOR_NAME="gadofir"
DISPATCH_URL="http://dispatch-http:8080"
POD_LABEL="app=agent"

# ─── Config file (bin/agent-cli.env) ─────────────────────────────────────────
CONFIG_FILE="$SCRIPT_DIR/agent-cli.env"
if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r key value; do
        key="$(echo "$key" | xargs)"
        value="$(echo "$value" | xargs | sed 's/^["'"'"']//; s/["'"'"']$//')"
        [[ -z "$key" || "$key" == \#* ]] && continue
        case "$key" in
            SSH_KEY)       SSH_KEY="$value" ;;
            SSH_HOST)      SSH_HOST="$value" ;;
            OPERATOR_NAME) OPERATOR_NAME="$value" ;;
            DISPATCH_URL)  DISPATCH_URL="$value" ;;
            POD_LABEL)     POD_LABEL="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# ─── Env-var overrides (highest priority) ────────────────────────────────────
[[ -n "${OPERATOR_NAME_OVERRIDE:-}" ]] && OPERATOR_NAME="$OPERATOR_NAME_OVERRIDE"
[[ -n "${AGENT_CLI_SSH_KEY:-}" ]] && SSH_KEY="$AGENT_CLI_SSH_KEY"
[[ -n "${AGENT_CLI_HOST:-}" ]] && SSH_HOST="$AGENT_CLI_HOST"

# ─── Sanity ──────────────────────────────────────────────────────────────────
if [[ ! -f "$SSH_KEY" ]]; then
    echo "ERROR: SSH key not found: $SSH_KEY" >&2
    echo "       Set SSH_KEY in bin/agent-cli.env or AGENT_CLI_SSH_KEY env var." >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: agent-cli <subcommand> [flags]

Common subcommands:
  workflow run <id> --workspace <ws>  — drive a workflow DAG
  hive publish|read|poll-mentions     — cross-workspace messaging
  dispatch --op <op> --params <json>  — generic dispatch
  skill --action list|show|activate   — skill registry
  cluster --action health|nodes       — operator-plane
  session list|show|delete            — inspect pi_direct sessions
  ws run|exec|shell|create            — workspace lifecycle

Run 'agent-cli <subcommand> --help' for flags.

Resolved config:
  SSH_KEY        = $SSH_KEY
  SSH_HOST       = $SSH_HOST
  OPERATOR_NAME  = $OPERATOR_NAME
  DISPATCH_URL   = $DISPATCH_URL
EOF
    exit 0
fi

# Special-case: 'agent-cli config'
if [[ "$1" == "config" ]]; then
    echo "SSH_KEY        = $SSH_KEY"
    echo "SSH_HOST       = $SSH_HOST"
    echo "OPERATOR_NAME  = $OPERATOR_NAME"
    echo "DISPATCH_URL   = $DISPATCH_URL"
    echo "POD_LABEL      = $POD_LABEL"
    echo "CONFIG_FILE    = $CONFIG_FILE $([[ -f "$CONFIG_FILE" ]] && echo '(loaded)' || echo '(absent)')"
    exit 0
fi

# ─── Auto-stage local files (G-198) ──────────────────────────────────────────
# Make file-input verbs (skill register --file, secret/service --from-file, skill
# --body-file, workflow edit/import <path>) fully CLI-native: when the flag/arg
# value is a LOCAL file, ship it into the agent pod and rewrite the arg to the
# pod-side path. No local file ⇒ unchanged behavior (the value ships verbatim).
FILE_FLAGS=("--file" "--from-file" "--body-file")
STAGED_PODPATHS=()
NEW_ARGS=()
STAGE_ID="$(date +%s)$$"
STAGE_SEQ=0
ORIG_ARGS=("$@")
ARG_N=${#ORIG_ARGS[@]}
ai=0
while (( ai < ARG_N )); do
    cur="${ORIG_ARGS[$ai]}"
    NEW_ARGS+=("$cur")
    candidate=""
    is_flag_value=0
    for ff in "${FILE_FLAGS[@]}"; do
        if [[ "$cur" == "$ff" ]] && (( ai + 1 < ARG_N )); then
            candidate="${ORIG_ARGS[$((ai+1))]}"; is_flag_value=1; break
        fi
    done
    if [[ -z "$candidate" && $ARG_N -ge 3 && "${ORIG_ARGS[0]}" == "workflow" \
          && ( "${ORIG_ARGS[1]}" == "edit" || "${ORIG_ARGS[1]}" == "import" ) && $ai -eq 2 ]]; then
        candidate="$cur"
    fi
    if [[ -n "$candidate" && -f "$candidate" ]]; then
        pod_path="/tmp/agent-cli-stage-${STAGE_ID}-${STAGE_SEQ}"
        STAGE_SEQ=$((STAGE_SEQ + 1))
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR -q "$candidate" "${SSH_HOST}:${pod_path}"
        STAGED_PODPATHS+=("$pod_path")
        if (( is_flag_value )); then
            NEW_ARGS+=("$pod_path"); ai=$((ai + 1))
        else
            NEW_ARGS[${#NEW_ARGS[@]}-1]="$pod_path"
        fi
    fi
    ai=$((ai + 1))
done
set -- "${NEW_ARGS[@]}"
if (( ${#STAGED_PODPATHS[@]} > 0 )); then
    STAGED_JSON=$(python3 -c 'import sys, json; print(json.dumps(sys.argv[1:]))' "${STAGED_PODPATHS[@]}")
else
    STAGED_JSON="[]"
fi
STAGED_B64=$(echo -n "$STAGED_JSON" | base64 -w0 2>/dev/null || echo -n "$STAGED_JSON" | base64)

# ─── Serialize args as base64 JSON (dodges every layer of shell escaping) ────
ARGS_JSON=$(python3 -c 'import sys, json; print(json.dumps(sys.argv[1:]))' "$@")
ARGS_B64=$(echo -n "$ARGS_JSON" | base64 -w0 2>/dev/null || echo -n "$ARGS_JSON" | base64)

REMOTE_CMD=$(cat <<EOF
python3 -c "
import os, sys, base64, json, subprocess
args = json.loads(base64.b64decode('$ARGS_B64').decode())
staged = json.loads(base64.b64decode('$STAGED_B64').decode())
if staged:
    pod = subprocess.check_output(['kubectl','get','pod','-n','platform','-l','app=agent','-o','jsonpath={.items[0].metadata.name}']).decode().strip()
    for p in staged:
        subprocess.run(['kubectl','cp', p, 'platform/%s:%s' % (pod, p), '-c', 'agent'], check=True)
os.execvp('kubectl', [
    'kubectl', 'exec', '-n', 'platform', '-c', 'agent', 'deploy/agent', '--',
    'env',
    'OPERATOR_NAME=$OPERATOR_NAME',
    'DISPATCH_URL=$DISPATCH_URL',
    '/usr/local/bin/agent',
] + args)
"
EOF
)

# D-015 Step 1: capture stderr to a temp file so we can filter [TRACE] lines.
# Non-TRACE stderr is passthrough'd verbatim AFTER ssh exits; [TRACE] <id>
# lines become `Trace: <jaeger_url>`. Stdout streams through unmodified.
STDERR_FILE="$(mktemp -t agent-cli-stderr.XXXXXX)"
trap 'rm -f "$STDERR_FILE"' EXIT

SSH_EXIT=0
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o LogLevel=ERROR "$SSH_HOST" "$REMOTE_CMD" 2> "$STDERR_FILE" || SSH_EXIT=$?

# Separate [TRACE] lines from normal stderr and emit normal stderr verbatim.
TRACE_IDS=()
if [[ -s "$STDERR_FILE" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[TRACE\][[:space:]]+([0-9a-fA-F]+)[[:space:]]*$ ]]; then
            TRACE_IDS+=("${BASH_REMATCH[1]}")
        else
            printf '%s\n' "$line" >&2
        fi
    done < "$STDERR_FILE"
fi

# Emit Trace URLs (suppress with AGENT_CLI_QUIET=1) + optional sidecar append.
SIDECAR_PATH="${AGENT_CLI_TRACE_SIDECAR:-}"
IS_QUIET="${AGENT_CLI_QUIET:-}"
if [[ -z "$IS_QUIET" || -n "$SIDECAR_PATH" ]]; then
    TS="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
    WS=""
    PREV=""
    for arg in "$@"; do
        if [[ "$PREV" == "--workspace" ]]; then
            WS="$arg"
        fi
        PREV="$arg"
    done
    OP_NAME="$*"
    emit_sidecar() {
        local tid="$1"
        [[ -z "$SIDECAR_PATH" ]] && return
        printf '{"ts":"%s","op":"%s","trace_id":"%s","exit_code":%d,"workspace":"%s"}\n' \
            "$TS" "$OP_NAME" "$tid" "$SSH_EXIT" "$WS" >> "$SIDECAR_PATH"
    }
    if [[ ${#TRACE_IDS[@]} -gt 0 ]]; then
        for tid in "${TRACE_IDS[@]}"; do
            [[ -z "$IS_QUIET" ]] && echo "Trace: https://tools.be-mcp.com/jaeger/trace/$tid" >&2
            emit_sidecar "$tid"
        done
    else
        [[ -z "$IS_QUIET" ]] && echo "Trace: (none)" >&2
        emit_sidecar ""
    fi
fi

exit $SSH_EXIT
