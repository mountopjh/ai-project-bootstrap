[CmdletBinding()]
param(
    [string]$ProjectRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$recordUtf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $recordUtf8
[Console]::InputEncoding = $recordUtf8
[Console]::OutputEncoding = $recordUtf8

$recordInputText = [Console]::In.ReadToEnd().Trim([char]0xFEFF)
if ([string]::IsNullOrWhiteSpace($recordInputText)) {
    exit 0
}
$recordInput = $recordInputText | ConvertFrom-Json
$recordProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRootOverride)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    [System.IO.Path]::GetFullPath($ProjectRootOverride)
}
$recordHookPath = Join-Path $recordProjectRoot '.codex\hooks\archive-conversation.ps1'
if (-not [System.IO.File]::Exists($recordHookPath)) {
    throw '未找到项目对话归档器。'
}

$recordSessionId = if ($null -ne $recordInput.session_id -and -not [string]::IsNullOrWhiteSpace([string]$recordInput.session_id)) { [string]$recordInput.session_id } else { 'generic-' + [guid]::NewGuid().ToString('N') }
$recordTurnId = if ($null -ne $recordInput.turn_id -and -not [string]::IsNullOrWhiteSpace([string]$recordInput.turn_id)) { [string]$recordInput.turn_id } else { 'turn-' + [guid]::NewGuid().ToString('N') }
$recordModel = if ($null -ne $recordInput.model) { [string]$recordInput.model } else { 'generic-ai' }
$recordPromptEvent = [ordered]@{
    session_id = $recordSessionId
    turn_id = $recordTurnId
    cwd = $recordProjectRoot
    hook_event_name = 'UserPromptSubmit'
    model = $recordModel
    permission_mode = 'default'
    prompt = [string]$recordInput.user
} | ConvertTo-Json -Compress
$recordStopEvent = [ordered]@{
    session_id = $recordSessionId
    turn_id = $recordTurnId
    cwd = $recordProjectRoot
    hook_event_name = 'Stop'
    model = $recordModel
    permission_mode = 'default'
    stop_hook_active = $false
    last_assistant_message = [string]$recordInput.assistant
} | ConvertTo-Json -Compress

$recordPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
$recordExe = if ($recordPwsh) { $recordPwsh.Source } else { (Get-Command powershell).Source }
$recordPromptEvent | & $recordExe -NoProfile -File $recordHookPath -ProjectRootOverride $recordProjectRoot | Out-Null
$recordStopEvent | & $recordExe -NoProfile -File $recordHookPath -ProjectRootOverride $recordProjectRoot | Out-Null
exit 0
