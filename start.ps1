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

$isKiroIde = $env:TERM_PROGRAM -eq 'kiro'
$kiroHookPath = Join-Path $projectRoot '.kiro\hooks\archive-conversation.kiro.hook'
$kiroHookReady = $isKiroIde -and (Test-Path -LiteralPath $kiroHookPath)

$hookStatusMessage = if ($isKiroIde -and $kiroHookReady) {
    '检测到 Kiro 环境：.kiro/hooks/archive-conversation.kiro.hook 已生成并默认启用，每轮对话结束会自动归档，无需额外信任步骤。'
}
elseif ($isKiroIde) {
    '检测到 Kiro 环境，但未能确认 .kiro/hooks/archive-conversation.kiro.hook 已生成；请运行 repair 后重试，或改用 tools/record-conversation.ps1 手动归档。'
}
else {
    '未检测到已知的自动钩子环境（当前 TERM_PROGRAM 非 kiro）。Codex 用户可信任 .codex/hooks.json 后自动归档；其他 IDE 请在每轮结束后手动运行 tools/record-conversation.ps1 或 tools/record_conversation.py。'
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
    detected_ide = if ($isKiroIde) { 'kiro' } else { 'unknown' }
    kiro_hook_active = $kiroHookReady
    hook_status_message = $hookStatusMessage
    message = '启动完成。AI 只需先读取项目根目录 START_HERE.md；无需逐个分析 AI_PROJECT_BOOTSTRAP 源码。Codex 自动对话归档仍需用户审核并信任 .codex/hooks.json，然后在新会话中生效。'
} | ConvertTo-Json -Depth 20
