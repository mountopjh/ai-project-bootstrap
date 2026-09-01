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

function Get-RecordInputValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }
    return [string]$property.Value
}

$recordRawSessionId = Get-RecordInputValue -InputObject $recordInput -Name 'session_id'
$recordSessionId = if (-not [string]::IsNullOrWhiteSpace($recordRawSessionId)) { $recordRawSessionId } else { 'generic-' + [guid]::NewGuid().ToString('N') }
$recordRawTurnId = Get-RecordInputValue -InputObject $recordInput -Name 'turn_id'
$recordTurnId = if (-not [string]::IsNullOrWhiteSpace($recordRawTurnId)) { $recordRawTurnId } else { 'turn-' + [guid]::NewGuid().ToString('N') }
$recordRawModel = Get-RecordInputValue -InputObject $recordInput -Name 'model'
$recordModel = if (-not [string]::IsNullOrWhiteSpace($recordRawModel)) { $recordRawModel } else { 'generic-ai' }
$recordPromptEvent = [ordered]@{
    session_id = $recordSessionId
    turn_id = $recordTurnId
    cwd = $recordProjectRoot
    hook_event_name = 'UserPromptSubmit'
    model = $recordModel
    permission_mode = 'default'
    prompt = [string](Get-RecordInputValue -InputObject $recordInput -Name 'user')
} | ConvertTo-Json -Compress
$recordStopEvent = [ordered]@{
    session_id = $recordSessionId
    turn_id = $recordTurnId
    cwd = $recordProjectRoot
    hook_event_name = 'Stop'
    model = $recordModel
    permission_mode = 'default'
    stop_hook_active = $false
    last_assistant_message = [string](Get-RecordInputValue -InputObject $recordInput -Name 'assistant')
} | ConvertTo-Json -Compress

$recordPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
$recordExe = if ($recordPwsh) { $recordPwsh.Source } else { (Get-Command powershell).Source }
$recordPromptEvent | & $recordExe -NoProfile -File $recordHookPath -ProjectRootOverride $recordProjectRoot | Out-Null
$recordStopEvent | & $recordExe -NoProfile -File $recordHookPath -ProjectRootOverride $recordProjectRoot | Out-Null
exit 0
