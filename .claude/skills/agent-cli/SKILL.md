---
name: agent-cli
description: Run the in-cluster `agent` Go binary from this PC via local wrappers `bin/agent-cli.ps1` (PowerShell) and `bin/agent-cli.sh` (bash). Covers all 19 top-level verbs — audit, chat, cluster, dispatch, hive, memory, migrate, policy, provision, scan, secret, service, session, skill, test, trace, vars, workflow, ws. Auth + operator identity + dispatch URL are baked in. Use when the user says "run agent X", "chat with a workspace", "scan a prompt / Prompt Guard", "drive a flow", "publish to hive", "list/show/set/clear/trace/lock/unlock/inventory/revoke policy", "set a workspace var or secret", "dispatch any op", or any operation that maps to an `agent <subcommand>` invocation against PROD.
argument-hint: "<subcommand> [flags]  — e.g. 'workflow run alice-e2e --workspace workspace-alice', 'policy inventory --workspace workspace-company --kind vars', 'hive read --workspace workspace-bob --topic hivemind/feed'"
---

# agent-cli — operator-side wrapper for the in-cluster `agent` binary

The `agent` binary (Go, in `cmd/agent/`) lives at `/usr/local/bin/agent` inside the agent pod on Hetzner. Two PC wrappers ship in `bin/`:

| Platform | Wrapper |
|---|---|
| Windows PowerShell | `.\bin\agent-cli.ps1` |
| macOS / Linux / WSL | `./bin/agent-cli.sh` |

Both take any `agent` subcommand + flags, ship them through SSH+kubectl, and run the binary inside the cluster with the operator's identity stamped on every dispatch. Output streams back to the local terminal exactly as if you ran it locally.

## Setup (one-time per laptop)

1. **SSH key at `auth cloud/id_ed25519`** — gitignored, never committed. Ask the cluster admin to generate one and register your public key on `webmcp@37.27.188.52`.
2. **(Optional) `bin/agent-cli.env`** — copy `bin/agent-cli.env.example` if you need to override any default. Gitignored.

Defaults match PROD:

| Default | Value |
|---|---|
| `SSH_KEY` | `<repo>/auth cloud/id_ed25519` |
| `SSH_HOST` | `webmcp@37.27.188.52` |
| `OPERATOR_NAME` | `gadofir` (must exist in `config/operators.yaml`) |
| `DISPATCH_URL` | `http://dispatch-http:8080` |

Verify with `.\bin\agent-cli.ps1 config`.

## Subcommand reference — 19 top-level verbs

Run `<wrapper> <subcommand> --help` for real flags. Bold = most useful in the demo.

| Subcommand | Purpose | Notable flags |
|---|---|---|
| **`dispatch`** | Generic HMAC-signed dispatch. Any registered op: `llm_call`, `service_call`, `tool_call`, `hive_publish`, `cap_check`, `cluster_info`, `workspace_create`, `provision_workspace`, `prompt_template_list/get/set/delete`, `prompt_expand`, etc. | `--workspace`, `--op`, `--params`, `--raw`, `--url` |
| **`policy`** | All 8 verbs: `show`, `trace`, `set`, `clear`, `lock`, `unlock`, `inventory`, `revoke`. See the "Policy cascade" section below for recipes. | `--workspace`, `--field`, `--value`, `--kind`, `--key`, `--target-tier`, `--target-id`, `--reason`, `--json` |
| **`vars`** | Manage workspace-tier vars (PVC-backed). Verbs: `set`, `get`, `list`, `delete`. Key vars: `system_prompt`, `chatbot` (chat persona), `expand_model` (Smart Expand LLM, e.g. `deepseek-chat`). | `--workspace`, `--key`, `--value`, `--type {text\|secret}` |
| **`secret`** | Manage age-encrypted secrets. Verbs: `set`, `get-meta` (value NEVER returned), `list`, `delete`. | `--workspace`, `--repo`, `--key`, `--value`, `--service` |
| **`workflow`** | Full DAG lifecycle. Verbs: `list`, `create`, `edit`, `duplicate`, `delete`, `run`, `validate`, `export`, `import`, `status`, `logs`, `cancel`, `approve`, `reject`, `resume`, `build`, `schedule {list\|enable\|disable}`. Per-workspace user pack when `--workspace` is set; global base pack otherwise. GUI Flows tab is a 1:1 view. | `--workspace`, `--id`, `--input`, `--worktree`, `--session`, `--resume`, `--reset-session` |
| **`skill`** | Inspect/manage skill registry + versions. Actions: `list`, `show`, `activate` (defaults `--dry-run`), `create`, `fork`, `delete`, `version-list`, `version-save`, `version-set-active`, `restore`, `trash-list`, `promote`. `create --tier workspace` lands on PVC; `--tier company` writes in-repo (PR-driven). `fork` is the CLI analogue of GUI Customize. | `--action`, `--id`, `--workspace`, `--tier`, `--parent`, `--new-id`, `--name`, `--description`, `--vault-refs`, `--body`, `--version`, `--note` |
| **`hive`** | Cross-workspace messaging. Verbs: `publish`, `read`, `poll-mentions`. Default topic `hivemind/feed`. | `--workspace`, `--topic`, `--payload`, `--limit`, `--since`, `--mark-seen` |
| **`chat`** | Talk to a workspace's chatbot. Verbs: `send`, `commands`, `history`. Each workspace has its own persona (`vars.chatbot`), model (`chat_model`), session namespace, and Iris memory. CLI-created sessions appear in the GUI chat tab automatically (same Redis namespace). See the "Chat" section below for recipes. | `--workspace`, `--message`, `--session`, `--json` |
| **`scan`** | Prompt-injection scanning + scan-pattern registry (Prompt Guard — the CLI peer of the GUI Prompt Guard view). Verbs: `run` (regex-scan a prompt, observe-only), `verify` (on-demand LLM judge, advisory), `list` (recent injection-scan events = the timeline), `pattern {list\|add\|delete}` (workspace scan families — baked families can't be deleted, regex validated server-side). | `--workspace`, `--prompt`, `--id` |
| **`session`** | Inspect / manage pi_direct + chat sessions (same Redis namespace). Verbs: `list`, `show`, `delete`, `reset`. Answers "what did Bob do today?". Backed by `lib.session_manager`. | `--workspace`, `--state running\|paused\|completed\|errored` (list); `<session-id>` (show/delete/reset) |
| **`trace`** | Query/assert against Jaeger. `get <id>` prints span tree + tags; `assert` exits 0 when all `--has-span`/`--has-attr` hold. | `--trace-id`, `--has-span`, `--has-attr`, `--workspace` |
| **`audit verify`** | Validate HMAC chain via `AuditLog.validate()`. | `--workspace` |
| **`memory forget`** | Hard-delete chat-agent long-term memories (Redis Iris). | `--workspace`, `--all`, `--id` |
| **`service`** | Inspect service definitions. **Uses `--action`, NOT a positional verb.** | `--action {list\|show\|validate}`, `--id <service>`, `--workspace` |
| **`cluster`** | Operator-plane: `--action {health\|nodes\|models\|freeze\|unfreeze}`. Freeze is the killswitch drill. | `--action` |
| **`provision`** | Workspace lifecycle via `provision_workspace` dispatch op: `--action {list\|create\|update\|delete}`. | `--action`, `--workspace`, `--company`, `--repo`, `--overrides`, `--template` |
| **`test run`** | Run a cluster test suite by name. | `--suite`, `--workspace` |
| **`migrate verify-los-empty`** | Verify legacy company/LOS secret declarations + values are empty. | `--workspace` |
| **`ws ...`** | Workspace operations. Sub-verbs: `bootstrap-cert`, `claude`, `commit-policy`, `create`, `delete`, `duplicate`, `exec`, `promote-policy`, `run`, `set-primary`, `shell`, `skill`. See "Workspace operations" below. | see per-verb help |

Bash is identical — swap the prefix: `./bin/agent-cli.sh hive read --workspace ...`.

**Inline `--params` JSON works correctly.** The wrapper ships args as a JSON file via scp, sidestepping PS/bash/ssh escape layers. Pass anything `agent dispatch` accepts inline without backslash-soup.

## Policy cascade — all 8 verbs

The 4 read/scalar-write verbs:

```powershell
# 1. SHOW — effective policy + rejected + per-field mutability class + vars
.\bin\agent-cli.ps1 policy show --workspace workspace-alice

# 2. TRACE — walk ONE field through every tier (company → repo → workspace → effective).
# Special-cased for vars.X / secrets.X dotted notation.
.\bin\agent-cli.ps1 policy trace --workspace workspace-alice --field model
.\bin\agent-cli.ps1 policy trace --workspace workspace-alice --field budget.daily_usd
.\bin\agent-cli.ps1 policy trace --workspace workspace-alice --field vars.system_prompt

# 3. SET — workspace-tier scalar override. --value parses as JSON literal first
# (numbers/bool/null), falls back to string. Writes to PVC override file; resolver
# picks it up on next dispatch (no pod restart).
.\bin\agent-cli.ps1 policy set --workspace workspace-alice --field temperature --value 0.3
.\bin\agent-cli.ps1 policy set --workspace workspace-alice --field model --value claude-haiku-4-5

# What `policy set` REJECTS (exits non-zero, prints error_class=policy_rejected):
#   - compliance-class fields (audit_logging, max_tokens_limit, prompt_injection.*)
#     -> "company-only — edit config/policy.yaml at the company tier"
#   - collection-class fields (vars.X, secrets.X, skills)
#     -> "git-managed — use `agent vars set` / `agent secret set` / repo .platform.yml"
#   - operational fields with intersection_only: true (budget.*, quota.*, allowed_services)
#     when the candidate exceeds upstream
#     -> "intersection_only: workspace value X exceeds upstream ceiling Y"

# 4. CLEAR — remove an override. Effective falls back to upstream tier.
.\bin\agent-cli.ps1 policy clear --workspace workspace-alice --field temperature
```

The 2 workspace-company lock verbs (toggle a soft lock without deleting lower overrides):

```powershell
# 5. LOCK — workspace-company adds a soft lock; lower-tier overrides are rejected on next resolve.
.\bin\agent-cli.ps1 policy lock --workspace workspace-company --field temperature --reason "pinned for rollout"

# 6. UNLOCK — remove the lock; lower-tier overrides reapply.
.\bin\agent-cli.ps1 policy unlock --workspace workspace-company --field temperature
```

The 2 newest verbs — company-tier visibility + soft-revoke (shipped 2026-05-28):

```powershell
# 7. INVENTORY — company-tier read-only view of what lower tiers added/overrode.
# kind: vars | secrets | skills | policy. Secret VALUES are NEVER returned.
.\bin\agent-cli.ps1 policy inventory --workspace workspace-company --kind vars
.\bin\agent-cli.ps1 policy inventory --workspace workspace-company --kind secrets --json
.\bin\agent-cli.ps1 policy inventory --workspace workspace-company --kind skills
.\bin\agent-cli.ps1 policy inventory --workspace workspace-company --kind policy

# 8. REVOKE — workspace-company-issued soft tombstone. Stored in PVC overrides.
# Replaces same (kind, key, target_tier, target_id) tuple. Physical delete is separate.
.\bin\agent-cli.ps1 policy revoke --workspace workspace-company `
    --kind var --key OLD_VAR `
    --target-tier workspace --target-id workspace-alice `
    --reason "removed by compliance"
.\bin\agent-cli.ps1 policy revoke --workspace workspace-company `
    --kind secret --key linkedin_token `
    --target-tier workspace --target-id workspace-alice `
    --reason "rotated centrally"
.\bin\agent-cli.ps1 policy revoke --workspace workspace-company `
    --kind skill --key devto `
    --target-tier repo --target-id agent-platform `
    --reason "deprecated"
```

The `policy set` write path re-resolves with the candidate in memory before writing to disk. If the simulated resolve produces a rejection for the same field, the write is refused — so `set` never persists a value that would have been rejected at enforcement time.

The cascade is 3-tier (company -> repo -> workspace). Every field belongs to ONE of 4 mutability classes: `compliance` (company-only, lower tiers rejected), `identity` (workspace can pin), `operational` (last-writer-wins), `collection` (vars/secrets/skills, split-by-kind). `intersection_only` fields (`budget.*`, `quota.*`, `allowed_services`) can only NARROW, never widen.

## Chat — per-workspace chatbot

Each workspace has its OWN chatbot. The persona comes from `vars.chatbot` (falls back to `vars.system_prompt`), the model from `chat_model` (decoupled from the workflow-driving `model`), sessions live under workspace-prefixed Redis keys (`sess-<workspace>-<id>`), and long-term memory namespaces are per workspace (Redis Iris, D-032). Slash messages (`/help`, `/skills`, `/clear`) short-circuit before the LLM in the `chat_send` handler — they don't consume tokens or LLM quota.

**GUI continuity:** sessions are stored under workspace-prefixed Redis keys keyed only by `session_id`. Anything written through `chat_send` from EITHER the CLI or the GUI shows up in `agent session list --workspace <ws>` and in the GUI chat tab's session sidebar without further work. Copy the `session_id` from CLI output and paste it into the GUI to resume the same conversation.

```powershell
# One-shot — mints a new session, prints session_id + reply
.\bin\agent-cli.ps1 chat send --workspace workspace-alice --message "who are you?"

# Resume the same conversation in another turn (paste the session_id from the previous send)
.\bin\agent-cli.ps1 chat send --workspace workspace-alice --message "continue please" `
    --session sess-alice-1723bda1398a

# Slash command — no LLM call, no quota consumed
.\bin\agent-cli.ps1 chat send --workspace workspace-alice --message "/skills"

# List all slash commands the chat surface supports
.\bin\agent-cli.ps1 chat commands --workspace workspace-alice

# Replay an existing session as a USER / ASSISTANT transcript
.\bin\agent-cli.ps1 chat history --workspace workspace-alice --session sess-alice-1723bda1398a
```

`chat history` reuses `scripts/session_admin show` (the same code path that backs `agent session show` and the GUI chat tab). Reformats the output as chat turns instead of an ops-style record. Vision-routing content blocks (`[{type:'text',text:'...'}, ...]`) are flattened.

## Prompt templates + Smart Expand (D-038)

Prompt templates are cascade-backed (`config/policy.yaml companies.LOS.prompt_templates`). Every workspace inherits 8 company-tier locked templates automatically. Workspace-tier overrides are stored in the workspace PVC (`policy.override.yaml`) and are fully isolated — changing alice's template never affects bob.

```powershell
# List all effective prompt templates for a workspace
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op prompt_template_list --params '{}'

# Get one template (full body + config)
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op prompt_template_get `
    --params '{"id":"usg-smart-expand"}'

# Override a template body at workspace tier (locked=true only blocks delete, not override)
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op prompt_template_set `
    --params '{"id":"usg-smart-expand","body":"Custom body with {{SCHEMA}}","closing":""}'

# Reset to company default: delete the workspace override (cascade falls back to company)
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op prompt_template_delete `
    --params '{"id":"usg-smart-expand"}'

# Server-side expand: resolve template + substitute context + call LLM
# This is what the GUI Smart Expand button calls (no clipboard needed)
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op prompt_expand `
    --params '{"template_id":"usg-smart-expand","context":{"SCHEMA":"...","CURRENT_WORKSPACE_JSON":"..."}}'
```

**Model for expand:** reads `vars.expand_model` → `chat_model` → `model`. Override per workspace:
```powershell
.\bin\agent-cli.ps1 vars set --workspace workspace-alice --key expand_model --value deepseek-chat
```

`agent prompt {list,show,set,delete}` typed verbs are on the growth list (CLI_CONTRACT). Until they ship, use `agent dispatch` above.

## Workspace operations (`ws`)

```powershell
# Bootstrap a new workspace. Seeds identity/operational/vars/skill-scope/secret-decls
# from workspace-company. Idempotent. UC-0 fields required only for workspace-company itself.
.\bin\agent-cli.ps1 ws create --workspace workspace-alice2 --repo agent-platform `
    --skills github,knowledge_base
# Other flags: --company --owner-email --model --chat-model --model-fallback --allowed-services

# Clone an existing workspace (PVC + git durable). Refuses workspace-company source/dest.
.\bin\agent-cli.ps1 ws duplicate --from workspace-alice --workspace workspace-alice-clone

# Hard delete a workspace (PVC + vault keys + git entry).
.\bin\agent-cli.ps1 ws delete --workspace workspace-alice-clone

# One-shot command under workspace identity (vault env merged in)
.\bin\agent-cli.ps1 ws exec --workspace workspace-alice -- python3 -c "import os; print(os.environ.get('LITELLM_API_KEY','')[:6])"

# Bash with same env
.\bin\agent-cli.ps1 ws shell --workspace workspace-alice

# Claude Code under the workspace's .claude/ preset
.\bin\agent-cli.ps1 ws claude --workspace workspace-alice

# Autonomous pi_direct run (LLM-driven). --session attaches; --resume strict-loads.
.\bin\agent-cli.ps1 ws run --workspace workspace-alice --prompt "..." --skills slack,github

# Set the primary attached repo (writes workspaces.<ws>.repo in central policy)
.\bin\agent-cli.ps1 ws set-primary agent-platform --workspace workspace-alice

# Workspace-scoped skill membership (gates which skills may activate)
.\bin\agent-cli.ps1 ws skill --action {add|remove|list} --workspace workspace-alice --id github

# Commit + push .platform.yml using a human-supplied GitHub PAT (paste/env/stdin — never disk)
.\bin\agent-cli.ps1 ws commit-policy --workspace workspace-alice --message "..." --token-paste

# Issue a single-use bootstrap cert for cold-start attachment registration
.\bin\agent-cli.ps1 ws bootstrap-cert --workspace workspace-alice --provider github

# Promote PVC policy.override.yaml into the git baseline (D-022)
.\bin\agent-cli.ps1 ws promote-policy --workspace workspace-alice
```

## Skills — three activation paths in one paragraph

A workspace can use a skill via: (1) **membership** — `ws skill --action add` writes `workspaces.<ws>.overrides.skills` in policy. Gates *availability* but doesn't activate. (2) **Pre-activation before turn 0** — `ws run --skills slack,github` or `requires_skills:` / `skills:` in the workflow YAML. Pi-direct emits one `skill_activated` span before the first `llm.call`. (3) **LLM self-activation** — every workspace has the `activate_skill` tool by default; the LLM calls `activate_skill(skill_id="...")` mid-flow. Vault tokens NEVER enter the LLM message context — `vault_refs` resolve at HTTP request time inside `ext.call`. If the LLM tries to activate a skill the workspace lacks membership for, dispatch refuses with `error_class=policy_rejection`.

## Tracing — what to expect

Every wrapper invocation prints `Trace: <jaeger_url>` to **stderr** after the call. If no span was emitted, the wrapper prints `Trace: (none)` instead of silently dropping. Suppress with `AGENT_CLI_QUIET=1`.

**Sidecar mode** (opt-in) — every CLI invocation appends one JSON line to `$AGENT_CLI_TRACE_SIDECAR`:

```powershell
$env:AGENT_CLI_TRACE_SIDECAR = "runs/r1/flow_A/jaeger_links.jsonl"
.\bin\agent-cli.ps1 vars list --workspace workspace-alice
# Appends: {"ts":"...","op":"vars list --workspace workspace-alice","trace_id":"...","exit_code":0,"workspace":"workspace-alice"}
```

Used by `tests/e2e_contract_sweep.py` to materialize per-flow trace indexes.

### Span hierarchy (workflow-driven autonomous run)

```
workflow.run                                      ← root span
  ├── workflow.node (one per node)
  │     └── pi_direct.agent_loop                  ← only for pi nodes
  │         ├── skill_activated [<id>]            ← one per pre-activated skill
  │         ├── pi_direct.turn.0
  │         │   ├── llm.call                      ← provider call
  │         │   └── pi_direct.tool.<name>         ← LLM-chosen tool
  │         │       └── dispatch_execute          ← governance boundary
  │         │           └── ext.call              ← external HTTP
  │         ├── pi_direct.turn.1
  │         │   ...
```

### Top critical span attributes

| Span | Key attributes |
|---|---|
| every span | `service.name=agent-platform` |
| `workflow.run` | `workflow.id`, `workflow.run_id`, `trigger.source=cli\|gui`, `auth.principal.id=operator:<name>`, `workspace_id`, `session.mode=fresh\|attach\|resume\|reset` |
| `dispatch_execute` | `auth.principal.id`, `auth.principal.role`, `workspace_id`, `operation`, `policy_source_file`, `model`, `company`, `repo` |
| `skill_activated` | `skill.id`, `skill.vars.resolved` (count), `skill.vault.resolved` (count — proves vault token resolved without leaking it) |
| `llm.call` | `provider.model.requested`, `provider.model.actual`, `provider.fallback_chain` (only on failover), `finish_reason`, `llm.outcome`, plus pi/dispatch-path-specific extras |
| `pi_direct.tool.<name>` | `tool.name`, `tool.args` (≤500 chars), `tool.result_len`, `tool.rejected_reason` (when policy blocks) |
| `ext.call` | `service`, `endpoint`, `method`, `status_code`, `latency_ms`, `traceparent` |

Open any captured trace_id in the Jaeger UI: `https://tools.be-mcp.com/jaeger/trace/<trace_id>`.

### Reading + asserting traces from the CLI

```powershell
# Full span tree + tag dump
.\bin\agent-cli.ps1 trace get <trace-id>

# Assert structure (exits 0 on pass, 1 on fail)
.\bin\agent-cli.ps1 trace assert --trace-id <id> --has-span pi_direct.turn.0,pi_direct.turn.1
.\bin\agent-cli.ps1 trace assert --trace-id <id> --has-attr trigger.source=cli
.\bin\agent-cli.ps1 trace assert --trace-id <id> --has-attr provider.model.actual=glm-4.7

# Audit chain validation
.\bin\agent-cli.ps1 audit verify --workspace workspace-alice
```

## Session context-survival + admin

Every `llm.call` carries `session.context_source` ∈ {`fresh`, `attached:<sid>`, `resumed:<sid>`, `reset:<sid>`}, plus `session.context_carries` and `session.previous_turn_count`. Three flags on `ws run` and `workflow run` control session reuse:

```powershell
# Mint / attach to a named session — future runs reuse history
.\bin\agent-cli.ps1 ws run --workspace workspace-bob --prompt "..." --session bob-demo-1

# Strict resume — load or fail (no silent fresh-start)
.\bin\agent-cli.ps1 workflow run alice-devto-update --workspace workspace-alice --session demo-1 --resume

# Reset — wipe prior history before turn 0 (mutually exclusive with --resume)
.\bin\agent-cli.ps1 ws run --workspace workspace-bob --prompt "..." --session bob-demo-1 --reset-session
```

Inspect what's there:

```powershell
.\bin\agent-cli.ps1 session list --workspace workspace-bob              # all
.\bin\agent-cli.ps1 session list --workspace workspace-bob --state running   # stuck
.\bin\agent-cli.ps1 session show <session-id> --workspace workspace-bob
.\bin\agent-cli.ps1 session delete <session-id> --workspace workspace-bob
.\bin\agent-cli.ps1 session reset <session-id> --workspace workspace-bob
```

Sessions live in Redis with `SESSION_TTL_HOURS` (default 24h). Workspace prefix in the Redis key is the gate.

## Common recipes (one-liners)

```powershell
# Cross-workspace hive demo
.\bin\agent-cli.ps1 hive publish --workspace workspace-alice --topic hivemind/feed --payload "hi @workspace-bob"
.\bin\agent-cli.ps1 hive read    --workspace workspace-bob   --topic hivemind/feed --limit 5
.\bin\agent-cli.ps1 hive poll-mentions --workspace workspace-bob --mark-seen

# Real LLM call (returns trace_id)
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"hi","max_tokens":16}'

# Drive an E2E flow
.\bin\agent-cli.ps1 workflow run alice-devto-update --workspace workspace-alice

# Scheduled (cron) workflow runs
.\bin\agent-cli.ps1 workflow schedule list    --workspace workspace-alice
.\bin\agent-cli.ps1 workflow schedule enable  alice-e2e --workspace workspace-alice

# Round-trip a workflow YAML
.\bin\agent-cli.ps1 workflow export alice-e2e --workspace workspace-alice > alice-e2e.yaml
.\bin\agent-cli.ps1 workflow import alice-e2e.yaml --id alice-e2e-copy --workspace workspace-alice --force

# Workspace-scoped skill membership
.\bin\agent-cli.ps1 ws skill --action {list|add|remove} --workspace workspace-alice --id slack

# Killswitch drill
.\bin\agent-cli.ps1 cluster --action freeze
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"x"}'   # error_class=killswitch
.\bin\agent-cli.ps1 cluster --action unfreeze
```

For the canonical Alice-Dev.to demo flow, see `tests/alice_backend_baseline.py` (cheap, no LLM) + `tests/e2e_workspace_lifecycle.py` (full LLM + workflow + Jaeger round-trip).

## Common gotchas

**`operator_ssh_not_configured: operator=gadofir has no pubkey in registry`** — fires only on local-Python paths inside the binary (`cluster --action health`, `skill --action list`). Workaround: `OPERATOR_NAME= .\bin\agent-cli.ps1 cluster --action health`. Dispatch-based paths are unaffected.

**Z.AI 429 on autonomous `ws run` / `workflow run`** — Z.AI Coding Plan quota exhausts. LiteLLM auto-rolls to DeepSeek (PR 2.7 fallback). If both throttle: TimeoutError, wait 10 min.

**`workflow` writes to per-workspace user pack only when `--workspace` is set.** Bare `agent workflow create my-flow` lands in the GLOBAL base pack (admin mode). To match GUI scope, always pass `--workspace <ws>`. `workflow list` tags each with `scope: base|user`.

**`workflow list` shows RUNS, not workflow definitions.** Column header reads `WORKFLOW` but each row is a `RUN_ID`. To list available workflow IDs, use `workflow schedule list` or `workflow export <id>`.

**`cluster --action nodes` / `--action models` return empty output today.** The handlers exist but data is not populated — open issue. `cluster --action health` works.

**`provision --action list` returns a partial workspace set + blank COMPANY column.** Some workspaces are visible only via the policy resolver (workspaces under workspace-company never show), and the company tier isn't carried through. Prefer `policy show --workspace <ws>` per-workspace for authoritative state.

**`migrate verify-los-empty` exits 1 in the CURRENT state.** This is by design — LOS still carries LinkedIn/Slack/Memory secret declarations + values (per `config/policy.yaml`). The probe is a migration completion check; it stays red until those declarations move to per-workspace tiers. Don't treat as a regression.

**`policy show` redacts vault-sourced var values to `***`.** A var whose value came from a `vault://` reference returns `***` and is flagged in `vars_vault_resolved` (boolean map). Use `agent vars get --key <name>` if you legitimately need the resolved value for a single var — that path is policy-gated.

**Cross-service `signature_invalid` after a deploy** — when `lib/auth.py` changes, both `web-ui` and `dispatch-http` rebuild via auto-deploy. There's a 1-2 minute drift window where one side is on the new HMAC version. See your cluster admin §HMAC auth protocol for the freeze/unfreeze recipe.

## When NOT to use the wrapper

The wrapper is for `agent <subcommand>` invocations only. For anything else (raw `kubectl`, bare SSH, Jaeger UI deep-dives, dashboard issues), use the standard tool directly against the cluster -- you'll need the SSH key + cluster admin access for those.

## File map

```
bin/
  agent-cli.ps1          PowerShell wrapper (Windows)
  agent-cli.sh           bash wrapper (mac/linux/wsl)
  agent-cli.env.example  config template (copy to agent-cli.env, gitignored)
```

Both wrappers do exactly the same thing: serialize args as JSON, scp to Hetzner, run a tiny remote python that execs `kubectl exec -n platform deploy/agent -- env OPERATOR_NAME=… DISPATCH_URL=… /usr/local/bin/agent <args>`. Exit code and signals pass through.

**How tracing surfacing works under the hood:** `lib/dispatch.py` writes `result["trace_id"]` on every dispatch envelope from inside the dispatch span. The Go CLI (`cmd/agent/cmd/dispatch.go` + `cmd/agent/cmd/common.go:BuildDispatchScript`) emits `[TRACE] <id>` on stderr when the result carries one. The wrapper filters that line, formats as a Jaeger URL, and optionally appends to the sidecar.

