---
name: agent-cli
description: Run the in-cluster `agent` Go binary from this PC via local wrappers `bin/agent-cli.ps1` (PowerShell) and `bin/agent-cli.sh` (bash). Covers all 23 top-level verbs — audit, chat, cluster, dispatch, hive, llm, memory, migrate, policy, provision, repo, scan, secret, service, session, skill, test, ticket, tool, trace, vars, workflow, ws. Auth + operator identity + dispatch URL are baked in. Use when the user says "run agent X", "chat with a workspace", "scan a prompt / Prompt Guard", "drive a flow", "publish to hive", "list/show/set/clear/trace/lock/unlock/inventory/revoke policy", "set a workspace var or secret", "dispatch any op", "author a new skill / service", or any operation that maps to an `agent <subcommand>` invocation against PROD.
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

## Subcommand reference — 23 top-level verbs

Run `<wrapper> <subcommand> --help` for real flags. Bold = most useful in the demo.

| Subcommand | Purpose | Notable flags |
|---|---|---|
| **`dispatch`** | Generic HMAC-signed dispatch. Any registered op: `llm_call`, `service_call`, `tool_call`, `hive_publish`, `cap_check`, `cluster_info`, `workspace_create`, `provision_workspace`, `prompt_template_list/get/set/delete`, `prompt_expand`, etc. | `--workspace`, `--op`, `--params`, `--raw`, `--url` |
| **`policy`** | All 8 verbs: `show`, `trace`, `set`, `clear`, `lock`, `unlock`, `inventory`, `revoke`. See the "Policy cascade" section below for recipes. | `--workspace`, `--field`, `--value`, `--kind`, `--key`, `--target-tier`, `--target-id`, `--reason`, `--json` |
| **`vars`** | Manage workspace-tier vars (PVC-backed). Verbs: `set`, `get`, `list`, `delete`. Key vars: `system_prompt`, `chatbot` (chat persona), `expand_model` (Smart Expand LLM, e.g. `deepseek-chat`). | `--workspace`, `--key`, `--value`, `--type {text\|secret}` |
| **`secret`** | Manage age-encrypted secrets. Verbs: `set`, `get-meta` (value NEVER returned), `list`, `delete`. | `--workspace`, `--repo`, `--key`, `--value`, `--service` |
| **`ticket`** | Internal ticket operations (D-054/D-057). Verbs: `list`, `show`, `create`, `comment`, `status` (change status), `assign`, `handoff`, `link`, `claim`, `release`. **D-057 auto-link:** `workflow run --ticket <TCK>` auto-links the run + workflow definition to that ticket; `create_task` payload `ticket_id` auto-links a vibekanban job. Both best-effort (link failure never fails the run/job). | `--workspace`, `--json`; list filters `--mine`/`--status`/`--tag`; `--link-type`/`--target` (link); `--ticket` (on `workflow run`). **No `--limit`/`--offset`; `create` has no `--tag`.** |
| **`tool`** | Manage per-workspace tools (D-046). Verbs: `list`, `add`, `remove`, `allow`, `deny`, `undeny`. `deny`/`undeny` are company-tier only (`--workspace workspace-company`). | `--workspace`, `--name`, `--kind`, `--source`, `--version`, `--target` |
| **`llm bench`** | Benchmark LLM speed/cost from production Jaeger traces (`llm.call` spans, aggregated by model). `llm` is the parent command. | `--workspace`, `--model`, `--days`, `--limit`, `--sort` |
| **`workflow`** | Full DAG lifecycle. Verbs: `list`, `create`, `edit`, `duplicate`, `delete`, `run`, `validate`, `export`, `import`, `status`, `logs`, `cancel`/`stop`, `approve`, `reject`, `resume`, `retry`, `build`, `catalog`, `output`, `schedule {list\|enable\|disable}`. Per-workspace user pack when `--workspace` is set; global base pack otherwise. `run --ticket <TCK>` auto-links a jira (D-057). `stop <run-id>` is an operator-friendly alias for `cancel <run-id>`. `retry <run-id>` re-enters the DAG at the first failed node (succeeded nodes keep outputs). `catalog` lists workflow DEFINITIONS (not runs — `workflow list` shows runs). `output <run-id>` prints the terminal node's deliverable. | `--workspace`, `--id`, `--input`, `--worktree`, `--session`, `--resume`, `--reset-session`, `--ticket` |
| **`skill`** | Inspect/manage skill registry + versions. Actions/subcommands: `list`, `show`, `activate` (defaults `--dry-run`), `create`, `register`, `insert` (alias for register), `edit`, `validate`, `fork`, `delete`, `version-list`, `version-save`, `version-set-active`, `restore`, `trash-list`, `promote`. `create --tier workspace` lands on PVC; `create --tier company` and `register --tier company` land in the runtime PVC overlay and floor-union to workspaces. `fork` is the CLI analogue of GUI Customize. | `--action`, `--id`, `--workspace`, `--tier`, `--parent`, `--new-id`, `--name`, `--description`, `--vault-refs`, `--body`, `--body-file`, `--file`, `--version`, `--note` |
| **`hive`** | Cross-workspace messaging. Verbs: `publish`, `read`, `poll-mentions`. Default topic `hivemind/feed`. | `--workspace`, `--topic`, `--payload`, `--limit`, `--since`, `--mark-seen` |
| **`chat`** | Talk to a workspace's chatbot. Verbs: `send`, `commands`, `history`. Each workspace has its own persona (`vars.chatbot`), model (`chat_model`), session namespace, and Iris memory. CLI-created sessions appear in the GUI chat tab automatically (same Redis namespace). See the "Chat" section below for recipes. | `--workspace`, `--message`, `--session`, `--json` |
| **`scan`** | Prompt-injection scanning + scan-pattern registry (Prompt Guard — the CLI peer of the GUI Prompt Guard view). Verbs: `run` (regex-scan a prompt, observe-only), `verify` (on-demand LLM judge, advisory), `list` (recent injection-scan events = the timeline), `pattern {list\|add\|delete}` (workspace scan families — baked families can't be deleted, regex validated server-side). | `--workspace`, `--prompt`, `--id` |
| **`session`** | Inspect / manage pi_direct + chat sessions (same Redis namespace). Verbs: `list`, `show`, `delete`, `reset`. Answers "what did Bob do today?". Backed by `lib.session_manager`. | `--workspace`, `--state running\|paused\|completed\|errored` (list); `<session-id>` (show/delete/reset) |
| **`trace`** | Query/assert + **live control**. `get <id>` prints span tree; `assert` exits 0 when all `--has-span`/`--has-attr` hold. **`enable`/`disable`/`level <story\|eng\|infra>`/`status`** flip tracing on/off + verbosity **with no pod restart** (see "Tracing control" below). | `--trace-id`, `--has-span`, `--has-attr`, `--workspace` |
| **`audit verify`** | Validate HMAC chain via `AuditLog.validate()`. | `--workspace` |
| **`memory forget`** | Hard-delete chat-agent long-term memories (Redis Iris). | `--workspace`, `--all`, `--id` |
| **`service`** | Inspect/manage service definitions. **Uses `--action`, NOT a positional verb.** | `--action {list\|show\|validate\|create\|edit\|delete}`, `--id <service>`, `--workspace`, `--from-file` (create/edit). `delete` refuses git-seed services (`error_class: not_overlay`). |
| **`cluster`** | Operator-plane: `--action {health\|nodes\|models\|freeze\|unfreeze}`. Freeze is the killswitch drill. | `--action` |
| **`provision`** | Workspace lifecycle via `provision_workspace` dispatch op: `--action {list\|create\|update\|delete}`. | `--action`, `--workspace`, `--company`, `--repo`, `--overrides`, `--template` |
| **`test run`** | Run a cluster test suite by name. | `--suite`, `--workspace` |
| **`migrate verify-los-empty`** | Verify legacy company/LOS secret declarations + values are empty. | `--workspace` |
| **`ws ...`** | Workspace operations. Sub-verbs: `bootstrap-cert`, `claude`, `commit-policy`, `create`, `delete`, `duplicate`, `exec`, `promote-policy`, `purge`, `restore`, `run`, `set-primary`, `shell`, `skill`, `trash-list`. See "Workspace operations" below. | see per-verb help |
| **`repo register`** | Register a customer/external repo in the registry (`repos.<id>` + `github_token` declaration). **Build-free** — writes the PVC runtime overlay (G-139), no git commit, resolves on next dispatch. Derives the id from the URL. | `--url` (required), `--id`, `--company` |
| **`quota`** | Show workspace rate-limit usage. Verbs: `show`. Returns current tool/llm/service per-minute counters (weighted sliding window). D-060. | `--workspace` |
| **`budget`** | Show workspace USD spend vs caps. Verbs: `show`. Returns daily/monthly/total spend + remaining budget. D-060. | `--workspace` |
| **`usage`** | Show workspace resource consumption. Disk MB, runs, sessions, audit log, memory. D-060. | `--workspace` |


## Doctor + Probe — preflight and smoke test for the CLI path
```bash
# DOCTOR — preflight (2–10s). Checks every hop the wrapper depends on:
#   ssh key, operator registry, ssh reachable, agent pod Running, dispatch-http pod Running, agent binary --help.
bash bin/agent-cli-doctor.sh      # linux/wsl
# Expected: 6/6 pass

# PROBE — all-verb smoke (15–30s). Runs `agent <verb> --help` for every top-level verb
# + key sub-trees (ticket, tool, ws, ws skill, skill, workflow, llm, audit). No dispatch, no LLM,
# no state mutation. Validates the Cobra wire-up after any cmd/agent/cmd/ reorg.
bash bin/agent-cli-probe.sh       # linux/wsl
# Expected: 96/96 pass (23 top-level + 73 sub-verbs/aliases)
```

Both use the same SSH defaults/env overrides as the `agent-cli.sh` wrapper. The doctor
stops fast on SSH breakage (bounded timeouts, ~2s verdict) instead of blocking for
minutes like `kubectl exec` on a missing pod. **Run the doctor** before reporting a
CLI hang, and **run the probe** after adding or renaming a Cobra command.

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

`agent prompt` typed verbs are on the growth list. Until they ship, use `agent dispatch` above. See `skill-sync.md` Rule 4 for inventory ownership.

## Customer onboarding (D-048) — a workflow, not a verb

A customer IS a workspace. Onboarding is the `customer-onboard` **DAG workflow**
(deterministic dispatch nodes + a `pi` summary), run under `workspace-company`.
The token + extra profile are CLI follow-ups (the token must never flow through
workflow inputs). Every step is build-free (G-139).

```powershell
# 1. Store the customer's repo token in vault (secret inject; age-encrypted,
#    runtime-injected). NEVER inline — env/1Password ref. repo_id derives from the URL.
$env:TOK = (op read "op://vault/<customer>-github/token")
.\bin\agent-cli.ps1 secret set --workspace workspace-<name> --repo <repo_id> `
    --key github_token --value $env:TOK --service github

# 2. Run the onboarding workflow (registers repo → creates workspace attached →
#    sets profile.name → LLM summary). repo_id is derived from the URL.
.\bin\agent-cli.ps1 workflow run customer-onboard --workspace workspace-company `
    --input name=<name> --input repo=https://github.com/<owner>/<repo>.git

# 3. Extra profile fields (optional — cascade default is empty)
.\bin\agent-cli.ps1 policy set --workspace workspace-<name> --field profile.contact --value "..."
.\bin\agent-cli.ps1 policy set --workspace workspace-<name> --field profile.branding.facebook_url --value "..."

# 4. Second workspace for the same customer = duplicate (inherits the repo cert)
.\bin\agent-cli.ps1 ws duplicate --from workspace-<name> --workspace workspace-<name>-dev
```

Services / skills / tools **cascade from `workspace-company` by default**; customize
per customer with the existing verbs (`ws skill --action add/remove`,
`agent tool allow/deny`, narrow `allowed_services` via `policy set`). To register a
repo on its own (outside the workflow): `agent repo register --url <git-url>`.
Customer onboarding = workspace lifecycle — flagged for future phase (see `CONTRACTX.md` legacy map).

> **Deploy boundary:** `CONTRACTX/cross-cutting/service-skill-cli.md` §Deploy boundary — PVC overlay = live, git/config/** = NOT CLI-authoring. No CLI op triggers a build.

## Workspace operations (`ws`)

```powershell
# Bootstrap a new workspace. Seeds identity/operational/vars/skill-scope/secret-decls
# from workspace-company. Idempotent. UC-0 fields required only for workspace-company itself.
.\bin\agent-cli.ps1 ws create --workspace workspace-alice2 --repo agent-platform `
    --skills github,knowledge_base
# Other flags: --company --owner-email --model --chat-model --model-fallback --allowed-services

# Clone an existing workspace (PVC + git durable). Refuses workspace-company source/dest.
.\bin\agent-cli.ps1 ws duplicate --from workspace-alice --workspace workspace-alice-clone

# Soft-delete a workspace (30-day recycle window). Non-scratch → recycle bin.
# Scratch workspaces hard-delete immediately. Use --force to skip recycle.
.\bin\agent-cli.ps1 ws delete --workspace workspace-alice-clone
.\bin\agent-cli.ps1 ws delete --workspace workspace-alice-clone --force

# List soft-deleted workspaces
.\bin\agent-cli.ps1 ws trash-list

# Restore a soft-deleted workspace from recycle (PVC + vault + Redis + PG)
.\bin\agent-cli.ps1 ws restore --workspace workspace-alice-clone

# Permanently delete from recycle bin (no undo)
.\bin\agent-cli.ps1 ws purge --workspace workspace-alice-clone

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
.\bin\agent-cli.ps1 ws skill {add|insert|remove|list} --workspace workspace-alice --id github

# Commit + push .platform.yml using a human-supplied GitHub PAT (paste/env/stdin — never disk)
.\bin\agent-cli.ps1 ws commit-policy --workspace workspace-alice --message "..." --token-paste

# Issue a single-use bootstrap cert for cold-start attachment registration
.\bin\agent-cli.ps1 ws bootstrap-cert --workspace workspace-alice --provider github

# Promote PVC policy.override.yaml into the git baseline (D-022)
.\bin\agent-cli.ps1 ws promote-policy --workspace workspace-alice
```


## Skills — three activation paths in one paragraph

A workspace can use a skill via: (1) **membership** — `ws skill add <id>` or `ws skill insert <id>` writes `workspaces.<ws>.overrides.skills` in policy. Gates *availability* but doesn't activate. (2) **Pre-activation before turn 0** — `ws run --skills slack,github` or `requires_skills:` / `skills:` in the workflow YAML. Pi-direct emits one `skill_activated` span before the first `llm.call`. (3) **LLM self-activation** — every workspace has the `activate_skill` tool by default; the LLM calls `activate_skill(skill_id="...")` mid-flow. Vault tokens NEVER enter the LLM message context — `vault_refs` resolve at HTTP request time inside `ext.call`. If the LLM tries to activate a skill the workspace lacks membership for, dispatch refuses with `error_class=policy_rejection`.

## Tracing control (live on/off + level — no pod restart)

Tracing is **OFF by default in prod** (it adds ≈3-9s/dispatch at infra level — the Cloudflare 504 cause). The master on/off and the level are now a **live redis flag the span sampler reads**, so you flip them from the CLI and every process (`agent` + `dispatch-http`) picks it up within ~5s — **no restart**. `Trace: (none)` on every call means tracing is OFF; enable it first.

```powershell
.\bin\agent-cli.ps1 trace status                 # ON/OFF + level
.\bin\agent-cli.ps1 trace enable                  # turn ON (live)
.\bin\agent-cli.ps1 trace level story             # story|eng|infra (live)
# ... run the flow you want to trace, grab the trace_id from Jaeger ...
.\bin\agent-cli.ps1 trace disable                 # turn OFF when done
```

Levels (span volume / latency): **story** ≈10-20 spans (workflow + pi turns + llm.call) · **eng** ≈20-50 (+ dispatch/tools/ext/hive) · **infra** ≈50-150 (+ vault.* + policy_resolution). Use `story` for the lightest footprint; `infra` only for cascade/secret debugging. **Disable when finished** — leaving it on (esp. infra) reintroduces dispatch latency. The toggle is cluster-wide operator-plane; `--workspace` only fills the dispatch envelope (defaults `workspace-company`).

## Tracing — what to expect

> Spans only appear when tracing is enabled (`agent trace enable`). With tracing OFF (prod default) every call prints `Trace: (none)` — that is expected, not a failure.

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


## Tickets (D-054/D-057) — internal jira-like work tracking

```powershell
# List open tickets for a workspace (filters: --mine, --status open,blocked, --tag bug)
.\bin\agent-cli.ps1 ticket list --workspace workspace-alice

# Show one with full history + links
.\bin\agent-cli.ps1 ticket show TCK-000004 --workspace workspace-alice

# Create a ticket (NOTE: typed `ticket create` has NO --tag; pass tags via dispatch)
.\bin\agent-cli.ps1 ticket create --workspace workspace-alice --title "Investigate timeout" --description "…"
# With tags: route through dispatch (params accept tags[])
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op ticket_create --params '{"title":"Investigate timeout","description":"…","tags":["bug","investigate"]}'

# Change status + comment
.\bin\agent-cli.ps1 ticket status TCK-000004 --workspace workspace-alice --status in_progress
.\bin\agent-cli.ps1 ticket comment TCK-000004 --workspace workspace-alice --body "looking into this"

# Claim a ticket (30m TTL lease — auto-released on expiry)
.\bin\agent-cli.ps1 ticket claim TCK-000004 --workspace workspace-alice
.\bin\agent-cli.ps1 ticket release TCK-000004 --workspace workspace-alice

# Link to a workflow run or vibekanban job (manual: optional — auto-link is D-057)
.\bin\agent-cli.ps1 ticket link TCK-000004 --link-type workflow_run --target <run_id> --workspace workspace-alice
.\bin\agent-cli.ps1 ticket link TCK-000004 --link-type vibekanban_task --target <job_id> --workspace workspace-alice

# D-057 auto-link: run a workflow under a ticket — links are automatic
.\bin\agent-cli.ps1 workflow run smoke-dag --workspace workspace-alice --ticket TCK-000004
# Verify the links landed:
.\bin\agent-cli.ps1 ticket show TCK-000004 --workspace workspace-alice
```

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
.\bin\agent-cli.ps1 ws skill {list|add|insert|remove} --workspace workspace-alice --id slack

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

**`workflow list` shows RUNS, not workflow definitions.** Column header reads `WORKFLOW` but each row is a `RUN_ID`. To list available workflow IDs, use `agent workflow catalog --workspace <ws>`. `workflow catalog` lists DEFINITIONS (scope + valid/enabled/schedule); `workflow list` lists run instances.

**`workflow run --input` takes ONE JSON object, not `k=v` pairs.** The flag is parsed with `json.Unmarshal`, so use `--input '{"start_url":"https://x","max_pages":2}'`. The `--input name=foo --input repo=bar` form does NOT work (last value wins, and it isn't valid JSON).

**`ws exec -- <cmd>` can't pass dash-flags to the inner command.** Cobra parses any `-x` after `--` as its own flag (`bash -c`, `bash -lc`, `find -type` all fail with "unknown flag"). Workarounds: run dash-free commands (`ls <path>`), or use raw `kubectl exec` via the `cluster`/`hetzner-ssh` skill for anything needing flags.

**Creating a workflow from a local YAML:** `workflow import`/`edit <path>` resolve the path *inside the agent pod*, not your PC. To ship a local definition, `workflow create <id> --workspace <ws>` (scaffold) then `dispatch --op workflow_edit --params '{"workflow_id":"…","workspace_id":"…","workflow":{…}}'` (the wrapper sends `--params` as a JSON file, so the multiline prompt survives).

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
  agent-cli-doctor.sh    preflight: validate SSH + pod + binary before any long dispatch
  agent-cli-probe.sh     smoke: `agent <verb> --help` for all 96 verb/variants (PROD only)
```

Both wrappers do exactly the same thing: serialize args as JSON, scp to Hetzner, run a tiny remote python that execs `kubectl exec -n platform deploy/agent -- env OPERATOR_NAME=… DISPATCH_URL=… /usr/local/bin/agent <args>`. Exit code and signals pass through.
The doctor and probe use the same SSH defaults + env overrides; they work from WSL (copy key to `/tmp` for correct permissions) and Linux.
**How tracing surfacing works under the hood:** `lib/dispatch.py` writes `result["trace_id"]` on every dispatch envelope from inside the dispatch span. The Go CLI (`cmd/agent/cmd/dispatch.go` + `cmd/agent/cmd/common.go:BuildDispatchScript`) emits `[TRACE] <id>` on stderr when the result carries one. The wrapper filters that line, formats as a Jaeger URL, and optionally appends to the sidecar.

