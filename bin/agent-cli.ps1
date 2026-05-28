# agent-cli.ps1 — PC-side wrapper for the in-cluster `agent` binary
#
# Usage from this repo root:
#   .\bin\agent-cli.ps1 workflow run alice-e2e --workspace workspace-alice
#   .\bin\agent-cli.ps1 hive publish --workspace workspace-alice --topic hivemind/feed --payload 'hello'
#   .\bin\agent-cli.ps1 dispatch --workspace workspace-alice --op llm_call --params '{"prompt":"hi","max_tokens":16}'
#   .\bin\agent-cli.ps1 skill --action list --workspace workspace-alice
#   .\bin\agent-cli.ps1 session list --workspace workspace-bob
#
# Defaults (override via bin/agent-cli.env or env vars):
#   SSH_KEY        = .\auth cloud\id_ed25519       (relative to repo root)
#   SSH_HOST       = webmcp@37.27.188.52
#   OPERATOR_NAME  = gadofir                       (must exist in config/operators.yaml)
#   DISPATCH_URL   = http://dispatch-http:8080     (inside the cluster)
#   AGENT_POD_LABEL = app=agent
#
# Inline JSON in --params works — we ship args as a base64 JSON array
# through SSH and unpack remotely with python, sidestepping every layer
# of shell-escaping hell.

[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$AgentArgs
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# ─── Defaults ─────────────────────────────────────────────────────────────────
$SshKey       = Join-Path $RepoRoot "auth cloud\id_ed25519"
$SshHost      = "webmcp@37.27.188.52"
$OperatorName = "gadofir"
$DispatchUrl  = "http://dispatch-http:8080"
$PodLabel     = "app=agent"

# ─── Config file overrides (bin/agent-cli.env) ────────────────────────────────
$ConfigFile = Join-Path $PSScriptRoot "agent-cli.env"
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { return }
        $name, $value = $line.Split("=", 2)
        $name = $name.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        switch ($name) {
            "SSH_KEY"       { $script:SshKey       = $value }
            "SSH_HOST"      { $script:SshHost      = $value }
            "OPERATOR_NAME" { $script:OperatorName = $value }
            "DISPATCH_URL"  { $script:DispatchUrl  = $value }
            "POD_LABEL"     { $script:PodLabel     = $value }
        }
    }
}

# ─── Env-var overrides (highest priority) ─────────────────────────────────────
if ($env:OPERATOR_NAME)     { $OperatorName = $env:OPERATOR_NAME }
if ($env:AGENT_CLI_SSH_KEY) { $SshKey       = $env:AGENT_CLI_SSH_KEY }
if ($env:AGENT_CLI_HOST)    { $SshHost      = $env:AGENT_CLI_HOST }

# ─── Sanity ───────────────────────────────────────────────────────────────────
if (-not (Test-Path $SshKey)) {
    Write-Error "SSH key not found: $SshKey"
    Write-Error "Set SSH_KEY in bin/agent-cli.env or AGENT_CLI_SSH_KEY env var."
    exit 2
}
if (-not $AgentArgs -or $AgentArgs.Count -eq 0) {
    Write-Host "Usage: agent-cli <subcommand> [flags]"
    Write-Host ""
    Write-Host "Common subcommands:"
    Write-Host "  workflow run <id> --workspace <ws>  — drive a workflow DAG"
    Write-Host "  hive publish|read|poll-mentions     — cross-workspace messaging"
    Write-Host "  dispatch --op <op> --params <json>  — generic dispatch"
    Write-Host "  skill --action list|show|activate   — skill registry"
    Write-Host "  cluster --action health|nodes       — operator-plane"
    Write-Host "  session list|show|delete            — inspect pi_direct sessions"
    Write-Host "  ws run|exec|shell|create            — workspace lifecycle"
    Write-Host ""
    Write-Host "Run 'agent-cli <subcommand> --help' for flags."
    Write-Host ""
    Write-Host "Resolved config:"
    Write-Host "  SSH_KEY        = $SshKey"
    Write-Host "  SSH_HOST       = $SshHost"
    Write-Host "  OPERATOR_NAME  = $OperatorName"
    Write-Host "  DISPATCH_URL   = $DispatchUrl"
    exit 0
}

# ─── Special-case: `agent-cli config` prints resolved config and exits ────────
if ($AgentArgs[0] -eq "config") {
    Write-Host "SSH_KEY        = $SshKey"
    Write-Host "SSH_HOST       = $SshHost"
    Write-Host "OPERATOR_NAME  = $OperatorName"
    Write-Host "DISPATCH_URL   = $DispatchUrl"
    Write-Host "POD_LABEL      = $PodLabel"
    Write-Host "CONFIG_FILE    = $ConfigFile $(if (Test-Path $ConfigFile) { '(loaded)' } else { '(absent)' })"
    exit 0
}

# ─── Serialize args as JSON ──────────────────────────────────────────────────
# PowerShell's native-arg parser strips inner quotes no matter how we escape,
# so we ship the args as a JSON file via scp and invoke a remote python that
# reads them from the file. Bulletproof: zero PS→ssh→bash escape layers.
$argsArray = @($AgentArgs)
$argsJson  = $argsArray | ConvertTo-Json -Compress -Depth 1

# Local + remote temp paths
$id        = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$localTmp  = Join-Path $env:TEMP "agent-cli-args-$id.json"
$remoteTmp = "/tmp/agent-cli-args-$id"

[IO.File]::WriteAllText($localTmp, $argsJson, [Text.UTF8Encoding]::new($false))

try {
    & scp -i $SshKey -o StrictHostKeyChecking=no -o LogLevel=ERROR -q $localTmp "${SshHost}:${remoteTmp}.json" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "scp failed (key path? host reachable?)"
        exit 3
    }

    # Write the runner script to the same /tmp prefix so we only need one ssh
    # call. Heredoc is safe here because we're inside SSH's single command
    # buffer; bash interprets it locally on Hetzner.
    $sshScript = @"
cat > ${remoteTmp}.py <<'PYEOF'
import os, sys, json
with open('${remoteTmp}.json') as f:
    args = json.load(f)
os.execvp('kubectl', [
    'kubectl', 'exec', '-n', 'platform', '-c', 'agent', 'deploy/agent', '--',
    'env',
    'OPERATOR_NAME=$OperatorName',
    'DISPATCH_URL=$DispatchUrl',
    '/usr/local/bin/agent',
] + args)
PYEOF
python3 ${remoteTmp}.py
EC=`$?
rm -f ${remoteTmp}.json ${remoteTmp}.py
exit `$EC
"@

    # D-015 Step 1: capture ssh stderr via System.Diagnostics.Process so we can
    # filter [TRACE] lines without PowerShell 5.1's `2>` wrapping each stderr
    # line as a NativeCommandError object (CLAUDE.md cross-service note).
    # Stdout streams through to console verbatim. Stderr is filtered:
    #   [TRACE] <id>  →  `Trace: <jaeger_url>` (or appended to sidecar)
    #   everything else  →  passthrough to caller's stderr.
    # Quote arguments for the legacy Arguments-string API (PS 5.1 has no ArgumentList).
    # Escape embedded double quotes for ssh's remote command string.
    function _QuoteArg([string]$s) {
        if ($s -match '\s|"') {
            $escaped = $s -replace '"', '\"'
            return "`"$escaped`""
        }
        return $s
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ssh"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = @(
        "-i", (_QuoteArg $SshKey),
        "-o", "StrictHostKeyChecking=no",
        "-o", "LogLevel=ERROR",
        (_QuoteArg $SshHost),
        (_QuoteArg $sshScript)
    ) -join " "

    $proc = [System.Diagnostics.Process]::Start($psi)
    # Read both streams to end concurrently (avoid deadlock on full pipes)
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdoutText = $stdoutTask.Result
    $stderrText = $stderrTask.Result
    $sshExit = $proc.ExitCode

    if ($stdoutText) { [Console]::Out.Write($stdoutText) }

    $traceIds = @()
    if ($stderrText) {
        foreach ($line in ($stderrText -split "`r?`n")) {
            if ($line -match '^\[TRACE\]\s+([0-9a-fA-F]+)\s*$') {
                $traceIds += $matches[1]
            } elseif ($line) {
                [Console]::Error.WriteLine($line)
            }
        }
    }

    # Emit Trace URLs (suppress with AGENT_CLI_QUIET=1) + optional sidecar append
    $sidecarPath = $env:AGENT_CLI_TRACE_SIDECAR
    $isQuiet     = [bool]$env:AGENT_CLI_QUIET
    if (-not $isQuiet -or $sidecarPath) {
        $ts = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
        $workspace = ""
        for ($i = 0; $i -lt $AgentArgs.Count; $i++) {
            if ($AgentArgs[$i] -eq "--workspace" -and $i + 1 -lt $AgentArgs.Count) {
                $workspace = $AgentArgs[$i + 1]
            }
        }
        $opName = ($AgentArgs -join " ")
        if ($traceIds.Count -gt 0) {
            foreach ($tid in $traceIds) {
                $url = "https://tools.be-mcp.com/jaeger/trace/$tid"
                if (-not $isQuiet) { [Console]::Error.WriteLine("Trace: $url") }
                if ($sidecarPath) {
                    $entry = @{ ts = $ts; op = $opName; trace_id = $tid; exit_code = $sshExit; workspace = $workspace } | ConvertTo-Json -Compress
                    Add-Content -Path $sidecarPath -Value $entry
                }
            }
        } else {
            if (-not $isQuiet) { [Console]::Error.WriteLine("Trace: (none)") }
            if ($sidecarPath) {
                $entry = @{ ts = $ts; op = $opName; trace_id = ""; exit_code = $sshExit; workspace = $workspace } | ConvertTo-Json -Compress
                Add-Content -Path $sidecarPath -Value $entry
            }
        }
    }

    exit $sshExit
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $localTmp
}
