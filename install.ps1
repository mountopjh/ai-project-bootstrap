[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$ProfilePath = ''
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bootstrapScript = Join-Path $ScriptDir 'AI_PROJECT_BOOTSTRAP\bootstrap.ps1'

if (-not (Test-Path $bootstrapScript)) {
    Write-Error "未找到脚手架核心脚本：$bootstrapScript"
    exit 1
}

$params = @('install')
if ($Uninstall) { $params += '-Uninstall' }
if ($ProfilePath) { $params += @('-ProfilePath', $ProfilePath) }

pwsh -NoProfile -File $bootstrapScript @params
