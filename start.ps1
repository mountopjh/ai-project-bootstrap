[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "快速启动需要 PowerShell 7 或以上版本（当前：$($PSVersionTable.PSVersion)）。也可运行 python start.py。"
    exit 1
}

$projectRoot = $PSScriptRoot
$bootstrapScript = Join-Path $projectRoot 'AI_PROJECT_BOOTSTRAP\bootstrap.ps1'
$metadataPath = Join-Path $projectRoot '.ai-project-bootstrap.json'
$pwshCommand = Get-Command pwsh -ErrorAction Stop

if (-not (Test-Path -LiteralPath $bootstrapScript)) {
    Write-Error "未找到启动器核心脚本：$bootstrapScript"
    exit 1
}

function Invoke-LocalBootstrap {
    param([Parameter(Mandatory = $true)][string]$Action)

    $output = & $pwshCommand.Source -NoProfile -File $bootstrapScript $Action -TargetPath $projectRoot 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
    if ($exitCode -ne 0) {
        [Console]::Error.WriteLine($jsonText)
        exit $exitCode
    }
    return $jsonText | ConvertFrom-Json
}

$mode = if (Test-Path -LiteralPath $metadataPath) { 'repair' } else { 'init' }
$result = Invoke-LocalBootstrap -Action $mode
$check = Invoke-LocalBootstrap -Action 'check'

if (-not $check.ok) {
    [ordered]@{
        action = 'start'
        ok = $false
        mode = $mode
        project_root = $projectRoot
        issues = @($check.issues)
    } | ConvertTo-Json -Depth 20
    exit 1
}

[ordered]@{
    action = 'start'
    ok = $true
    mode = $mode
    project_root = $projectRoot
    changed = @($result.changed)
    ai_entry = (Join-Path $projectRoot 'START_HERE.md')
    hook_config = (Join-Path $projectRoot '.codex\hooks.json')
    hook_trust_required = $true
    message = '启动完成。AI 只需先读取项目根目录 START_HERE.md；无需逐个分析 AI_PROJECT_BOOTSTRAP 源码。Codex 自动对话归档仍需用户审核并信任 .codex/hooks.json，然后在新会话中生效。'
} | ConvertTo-Json -Depth 20
