[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TestBootstrapRoot = Split-Path -Parent $PSScriptRoot
$TestBootstrapScript = Join-Path $TestBootstrapRoot 'bootstrap.ps1'
$TestStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$TestPrefix = 'AI_PROJECT_BOOTSTRAP_TEST_' + $TestStamp + '_'
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ($TestPrefix + [guid]::NewGuid().ToString('N'))
$psCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$psExe = if ($psCmd) { $psCmd.Source } else { (Get-Command powershell).Source }

function Invoke-TestProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$InputText = '',
        [int]$ExpectedExitCode = 0
    )
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $escapedArgs = $Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
    $start.Arguments = $escapedArgs -join ' '
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $process.Start() | Out-Null
    if ($InputText) {
        $inputBytes = [Text.UTF8Encoding]::new($false).GetBytes($InputText)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.BaseStream.Flush()
    }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne $ExpectedExitCode) {
        throw "退出码 $($process.ExitCode)，预期 $ExpectedExitCode；stdout=$stdout；stderr=$stderr"
    }
    return [pscustomobject]@{
        Output = $stdout
        ErrorOutput = $stderr
        ExitCode = $process.ExitCode
    }
}

function Invoke-TestBootstrap {
    param(
        [string]$Mode,
        [switch]$Force,
        [int]$ExpectedExitCode = 0
    )
    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($item in @('-NoProfile', '-File', $TestBootstrapScript, $Mode, '-TargetPath', $TestRoot)) {
        $arguments.Add($item)
    }
    if ($Force) {
        $arguments.Add('-Force')
    }
    $result = Invoke-TestProcess -FilePath $psExe -Arguments $arguments.ToArray() -ExpectedExitCode $ExpectedExitCode
    $jsonText = if ($result.Output.Trim()) { $result.Output } else { $result.ErrorOutput }
    return $jsonText | ConvertFrom-Json
}

try {
    [IO.Directory]::CreateDirectory($TestRoot) | Out-Null
    if (-not (Invoke-TestBootstrap -Mode 'init').ok) {
        throw 'init 未成功'
    }
    if (-not (Invoke-TestBootstrap -Mode 'check').ok) {
        throw '首次 check 未通过'
    }
    [IO.File]::Delete((Join-Path $TestRoot 'START_HERE.md'))
    $repair = Invoke-TestBootstrap -Mode 'repair'
    if ('START_HERE.md' -notin $repair.changed) {
        throw 'repair 未补齐文件'
    }

    [IO.File]::Delete((Join-Path $TestRoot '.ai-project-bootstrap.json'))
    $staleHookMarker = 'C:\stale-machine\wrong-project\archive-conversation.ps1'
    [IO.File]::WriteAllText((Join-Path $TestRoot '.codex/hooks.json'), $staleHookMarker)
    $localRepair = Invoke-TestBootstrap -Mode 'repair'
    if ('.codex/hooks.json' -notin $localRepair.changed) {
        throw 'repair 未重新生成本机 hooks 配置'
    }
    $repairedHook = [IO.File]::ReadAllText((Join-Path $TestRoot '.codex/hooks.json'))
    if ($repairedHook -like "*$staleHookMarker*") {
        throw 'repair 后 hooks 配置仍包含旧机器路径'
    }
    $localCheck = Invoke-TestBootstrap -Mode 'check'
    if (-not $localCheck.ok -or @($localCheck.issues) -like '*未指向当前项目*') {
        throw 'repair 后 check 仍报告 hooks 未指向当前项目'
    }

    $stateMarker = [Environment]::NewLine + '测试状态必须保留。' + [Environment]::NewLine
    $managedMarker = [Environment]::NewLine + '测试人工修改。' + [Environment]::NewLine
    [IO.File]::AppendAllText((Join-Path $TestRoot 'DEVELOPMENT_MAP.md'), $stateMarker)
    [IO.File]::AppendAllText((Join-Path $TestRoot 'AGENTS.md'), $managedMarker)
    $conflict = Invoke-TestBootstrap -Mode 'upgrade' -ExpectedExitCode 1
    if ($conflict.ok -or $conflict.error -notlike '*人工修改*') {
        throw 'upgrade 未阻止人工修改'
    }
    $upgrade = Invoke-TestBootstrap -Mode 'upgrade' -Force
    if (-not $upgrade.ok -or -not $upgrade.backup) {
        throw '强制升级未创建备份'
    }
    if (([IO.File]::ReadAllText((Join-Path $TestRoot 'DEVELOPMENT_MAP.md'))) -notlike '*测试状态必须保留*') {
        throw '升级覆盖了状态文件'
    }
    if (([IO.File]::ReadAllText((Join-Path $upgrade.backup 'AGENTS.md'))) -notlike '*测试人工修改*') {
        throw '备份未保留人工修改'
    }
    if (-not (Invoke-TestBootstrap -Mode 'check').ok) {
        throw '最终 check 未通过'
    }

    $payload = [ordered]@{
        session_id = 'test-' + [guid]::NewGuid().ToString('N')
        turn_id = 'turn-' + [guid]::NewGuid().ToString('N')
        model = 'local-test'
        user = '验证通用记录工具'
        assistant = '记录成功'
    } | ConvertTo-Json -Compress
    $recorder = Join-Path $TestRoot 'tools/record-conversation.ps1'
    Invoke-TestProcess -FilePath $psExe -Arguments @('-NoProfile', '-File', $recorder, '-ProjectRootOverride', $TestRoot) -InputText $payload | Out-Null
    $conversations = @(
        Get-ChildItem -LiteralPath (Join-Path $TestRoot 'archive/conversations') -Filter '*.md' |
            Where-Object Name -ne 'INDEX.md'
    )
    if ($conversations.Count -ne 1 -or $conversations[0].Name -notmatch '^\d{8}-\d{6}_.+\.md$') {
        throw '对话文件名或数量无效'
    }
    $archiveText = [IO.File]::ReadAllText($conversations[0].FullName)
    if ($archiveText -notlike '*验证通用记录工具*' -or $archiveText -notlike '*记录成功*') {
        throw '对话正文缺少测试内容'
    }

    $minimalPayload = [ordered]@{
        user = '缺少会话标识的最小请求'
        assistant = '仍应成功归档'
        model = 'kiro'
    } | ConvertTo-Json -Compress
    $minimalResult = Invoke-TestProcess -FilePath $psExe -Arguments @('-NoProfile', '-File', $recorder, '-ProjectRootOverride', $TestRoot) -InputText $minimalPayload
    if ($minimalResult.ExitCode -ne 0) {
        throw "缺少 session_id/turn_id 时记录工具失败：$($minimalResult.ErrorOutput)"
    }
    $minimalConversations = @(
        Get-ChildItem -LiteralPath (Join-Path $TestRoot 'archive/conversations') -Filter '*.md' |
            Where-Object { $_.Name -ne 'INDEX.md' -and $_.Name -notin $conversations.Name }
    )
    if ($minimalConversations.Count -ne 1) {
        throw '缺少 session_id/turn_id 的对话未被归档'
    }
    $minimalText = [IO.File]::ReadAllText($minimalConversations[0].FullName)
    if ($minimalText -notlike '*缺少会话标识的最小请求*' -or $minimalText -notlike '*仍应成功归档*') {
        throw '最小请求的对话正文缺少测试内容'
    }
    'POWERSHELL_TESTS_OK'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolved = [IO.Path]::GetFullPath($TestRoot)
    if (
        (Split-Path -Parent $resolved) -eq $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -and
        (Split-Path -Leaf $resolved).StartsWith($TestPrefix, [StringComparison]::Ordinal)
    ) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
