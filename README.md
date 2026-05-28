# agent-cli

Operator-side wrapper for the `agent` Go binary running inside the production cluster at `tools.be-mcp.com`. Two scripts, no other dependencies.

The wrappers SSH into the cluster, run the binary inside the `agent` pod with your operator identity stamped on every dispatch, and stream output back to your terminal. Inline JSON in `--params` works correctly (args ship as a JSON file via scp).

## Prerequisites (ask the cluster admin)

1. **SSH private key** for `webmcp@37.27.188.52`. Save as `auth cloud/id_ed25519` in this repo root (or set `SSH_KEY` in `bin/agent-cli.env`). The path is gitignored — never commit it.
2. **Operator identity** registered server-side. The admin adds your public key + a name to `config/operators.yaml` on the cluster. Set `OPERATOR_NAME=<your-name>` in `bin/agent-cli.env`.

Until both exist, every call fails fast.

## Install

```bash
git clone https://github.com/gadofir/agent-cli.git
cd agent-cli
cp bin/agent-cli.env.example bin/agent-cli.env   # edit if defaults don't match
```

Defaults match the production cluster — most operators only need to change `OPERATOR_NAME`.

## Hello world

```powershell
# Windows
.\bin\agent-cli.ps1 audit verify --workspace workspace-alice
.\bin\agent-cli.ps1 policy show --workspace workspace-alice
.\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"hi","max_tokens":16}'
```

```bash
# macOS / Linux / WSL
./bin/agent-cli.sh audit verify --workspace workspace-alice
./bin/agent-cli.sh policy show --workspace workspace-alice
./bin/agent-cli.sh dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"hi","max_tokens":16}'
```

Every invocation prints a `Trace: <jaeger_url>` line to stderr (suppress with `AGENT_CLI_QUIET=1`).

## Full reference

The Claude Code skill at [`.claude/skills/agent-cli/SKILL.md`](.claude/skills/agent-cli/SKILL.md) is the canonical reference. It covers all 17 top-level verbs (audit, cluster, dispatch, hive, memory, migrate, policy, provision, secret, service, session, skill, test, trace, vars, workflow, ws), the policy cascade contract, session admin, tracing patterns, and the common gotchas.

If you use Claude Code, this skill will load automatically when you operate against the cluster from this repo.

## License

MIT.
