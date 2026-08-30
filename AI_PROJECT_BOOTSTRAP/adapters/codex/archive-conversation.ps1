[CmdletBinding()]
param(
    [string]$ProjectRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$archiveUtf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $archiveUtf8
[Console]::InputEncoding = $archiveUtf8
[Console]::OutputEncoding = $archiveUtf8

function Write-AtomicUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $archiveDirectory = [System.IO.Path]::GetDirectoryName($Path)
    [System.IO.Directory]::CreateDirectory($archiveDirectory) | Out-Null
    $archiveTemporaryPath = Join-Path $archiveDirectory ('.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($archiveTemporaryPath, $Content, $script:archiveUtf8)
        [System.IO.File]::Move($archiveTemporaryPath, $Path, $true)
    }
    finally {
        if ([System.IO.File]::Exists($archiveTemporaryPath)) {
            [System.IO.File]::Delete($archiveTemporaryPath)
        }
    }
}

function ConvertTo-SafeIdentifier {
    param([AllowEmptyString()][string]$Value)

    $archiveIdentifier = [regex]::Replace([string]$Value, '[^\p{L}\p{Nd}._-]+', '_').Trim('_', '.')
    if ([string]::IsNullOrWhiteSpace($archiveIdentifier)) {
        return 'unknown'
    }
    return $archiveIdentifier
}

function Get-ConversationTitle {
    param([AllowEmptyString()][string]$Prompt)

    $archiveTitle = [string]$Prompt
    $archiveTitle = [regex]::Replace($archiveTitle, '(?s)<environment_context>.*?</environment_context>', ' ')
    $archiveTitle = [regex]::Replace($archiveTitle, '(?s)```.*?```', ' ')
    $archiveTitle = [regex]::Replace($archiveTitle, '(?m)^\s{0,3}#{1,6}\s*', '')
    $archiveTitle = [regex]::Replace($archiveTitle, '\[([^\]]+)\]\([^)]+\)', '$1')
    $archiveTitle = [regex]::Replace($archiveTitle, '^\s*执行任务[。.!！]?\s*', '')
    $archiveTitle = [regex]::Replace($archiveTitle, '^(请你?|麻烦你?|请帮我|帮我|我想要?|我需要|需要|希望|做个|创建|实现)\s*', '')
    $archiveTitle = [regex]::Replace($archiveTitle, '[<>:"/\\|?*\x00-\x1F]+', ' ')
    $archiveTitle = [regex]::Replace($archiveTitle, '\s+', ' ').Trim(' ', '.')

    if ([string]::IsNullOrWhiteSpace($archiveTitle)) {
        return '未命名对话'
    }
    if ($archiveTitle.Length -gt 48) {
        $archiveTitle = $archiveTitle.Substring(0, 48).Trim()
    }
    return $archiveTitle
}

function Get-MutexName {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $archiveHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $archiveHashBytes = $archiveHasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant()))
        $archiveHash = ([System.BitConverter]::ToString($archiveHashBytes)).Replace('-', '').Substring(0, 20)
        return 'Local\CodexConversationArchive_' + $archiveHash
    }
    finally {
        $archiveHasher.Dispose()
    }
}

function Update-ConversationIndex {
    param(
        [Parameter(Mandatory = $true)][string]$IndexPath,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $archiveMutex = New-Object System.Threading.Mutex($false, (Get-MutexName -ProjectRoot $ProjectRoot))
    $archiveLockAcquired = $false
    try {
        try {
            $archiveLockAcquired = $archiveMutex.WaitOne(3000)
        }
        catch [System.Threading.AbandonedMutexException] {
            $archiveLockAcquired = $true
        }
        if (-not $archiveLockAcquired) {
            throw '无法在限定时间内取得对话索引写锁。'
        }

        $archiveRows = @()
        if ([System.IO.File]::Exists($IndexPath)) {
            $archiveExistingIndex = [System.IO.File]::ReadAllText($IndexPath, $script:archiveUtf8)
            $archiveRows = @([regex]::Split($archiveExistingIndex, '\r?\n') | Where-Object { $_ -match '^\| `\d{8}-\d{6}` \|' })
        }

        $archiveDisplayTitle = $Title.Replace('|', '\|').Replace('[', '\[').Replace(']', '\]')
        $archiveRows += '| `' + $Timestamp + '` | ' + $archiveDisplayTitle + ' | [' + $FileName + '](<' + $FileName + '>) |'
        $archiveIndexContent = '# 对话归档索引' + "`n`n" +
            '更新时间：`' + $Timestamp + '`' + "`n`n" +
            '| 时间 | 核心内容 | 文件 |' + "`n" +
            '| --- | --- | --- |' + "`n" +
            ($archiveRows -join "`n") + "`n"
        Write-AtomicUtf8 -Path $IndexPath -Content $archiveIndexContent
    }
    finally {
        if ($archiveLockAcquired) {
            $archiveMutex.ReleaseMutex()
        }
        $archiveMutex.Dispose()
    }
}

$archiveEventName = $null
$archiveProjectRoot = $null

try {
    $archiveInputText = [Console]::In.ReadToEnd().Trim([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($archiveInputText)) {
        exit 0
    }
    $archiveEvent = $archiveInputText | ConvertFrom-Json
    $archiveEventName = [string]$archiveEvent.hook_event_name

    if ([string]::IsNullOrWhiteSpace($ProjectRootOverride)) {
        $archiveProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    else {
        $archiveProjectRoot = [System.IO.Path]::GetFullPath($ProjectRootOverride)
    }

    $archiveRoot = Join-Path $archiveProjectRoot 'archive\conversations'
    $archivePendingRoot = Join-Path $archiveRoot '.pending'
    $archiveStateRoot = Join-Path $archiveRoot '.state'
    $archiveErrorRoot = Join-Path $archiveRoot '.errors'
    [System.IO.Directory]::CreateDirectory($archivePendingRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($archiveStateRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($archiveErrorRoot) | Out-Null

    $archiveSessionId = ConvertTo-SafeIdentifier -Value ([string]$archiveEvent.session_id)
    $archiveTurnId = ConvertTo-SafeIdentifier -Value ([string]$archiveEvent.turn_id)
    $archivePendingPath = Join-Path $archivePendingRoot ($archiveSessionId + '_' + $archiveTurnId + '.json')
    $archiveStatePath = Join-Path $archiveStateRoot ($archiveSessionId + '.json')

    if ($archiveEventName -eq 'UserPromptSubmit') {
        $archiveTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $archivePrompt = [string]$archiveEvent.prompt
        $archivePromptWithoutAuthorization = [regex]::Replace($archivePrompt, '^\s*执行任务[。.!！]?\s*$', '')
        if ([string]::IsNullOrWhiteSpace($archivePromptWithoutAuthorization) -and [System.IO.File]::Exists($archiveStatePath)) {
            $archivePreviousState = [System.IO.File]::ReadAllText($archiveStatePath, $archiveUtf8) | ConvertFrom-Json
            $archiveTitle = [string]$archivePreviousState.title + '-执行'
        }
        else {
            $archiveTitle = Get-ConversationTitle -Prompt $archivePrompt
            $archiveState = [ordered]@{ title = $archiveTitle } | ConvertTo-Json -Compress
            Write-AtomicUtf8 -Path $archiveStatePath -Content $archiveState
        }

        $archiveRecord = [ordered]@{
            timestamp = $archiveTimestamp
            title = $archiveTitle
            prompt = $archivePrompt
            session_id = [string]$archiveEvent.session_id
            turn_id = [string]$archiveEvent.turn_id
            model = [string]$archiveEvent.model
        } | ConvertTo-Json -Depth 4
        Write-AtomicUtf8 -Path $archivePendingPath -Content $archiveRecord
        exit 0
    }

    if ($archiveEventName -eq 'Stop') {
        if ([System.IO.File]::Exists($archivePendingPath)) {
            $archiveRecord = [System.IO.File]::ReadAllText($archivePendingPath, $archiveUtf8) | ConvertFrom-Json
        }
        else {
            $archiveRecord = [pscustomobject]@{
                timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                title = '未匹配对话'
                prompt = '[未获取到用户消息]'
                session_id = [string]$archiveEvent.session_id
                turn_id = [string]$archiveEvent.turn_id
                model = [string]$archiveEvent.model
            }
        }

        $archiveTimestamp = [string]$archiveRecord.timestamp
        $archiveTitle = Get-ConversationTitle -Prompt ([string]$archiveRecord.title)
        $archiveFileName = $archiveTimestamp + '_' + $archiveTitle + '.md'
        $archiveFinalPath = Join-Path $archiveRoot $archiveFileName
        if ([System.IO.File]::Exists($archiveFinalPath)) {
            $archiveShortTurn = $archiveTurnId.Substring(0, [Math]::Min(8, $archiveTurnId.Length))
            $archiveFileName = $archiveTimestamp + '_' + $archiveTitle + '_' + $archiveShortTurn + '.md'
            $archiveFinalPath = Join-Path $archiveRoot $archiveFileName
        }

        $archiveAnswer = [string]$archiveEvent.last_assistant_message
        if ([string]::IsNullOrWhiteSpace($archiveAnswer)) {
            $archiveAnswer = '[未获取到AI回答]'
        }
        $archiveConversationContent = '# ' + $archiveTitle + "`n`n" +
            '记录时间：`' + $archiveTimestamp + '`' + "`n`n" +
            '会话标识：`' + [string]$archiveRecord.session_id + '`' + "`n`n" +
            '轮次标识：`' + [string]$archiveRecord.turn_id + '`' + "`n`n" +
            '模型：`' + [string]$archiveRecord.model + '`' + "`n`n" +
            '## 用户' + "`n`n" + [string]$archiveRecord.prompt + "`n`n" +
            '## AI' + "`n`n" + $archiveAnswer + "`n"
        Write-AtomicUtf8 -Path $archiveFinalPath -Content $archiveConversationContent
        Update-ConversationIndex -IndexPath (Join-Path $archiveRoot 'INDEX.md') -Timestamp $archiveTimestamp -Title $archiveTitle -FileName $archiveFileName -ProjectRoot $archiveProjectRoot

        if ([System.IO.File]::Exists($archivePendingPath)) {
            [System.IO.File]::Delete($archivePendingPath)
        }
        [Console]::Out.WriteLine('{"continue":true}')
        exit 0
    }
}
catch {
    try {
        if (-not [string]::IsNullOrWhiteSpace($archiveProjectRoot)) {
            $archiveFailureTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $archiveFailureRoot = Join-Path $archiveProjectRoot 'archive\conversations\.errors'
            [System.IO.Directory]::CreateDirectory($archiveFailureRoot) | Out-Null
            $archiveFailurePath = Join-Path $archiveFailureRoot ($archiveFailureTimestamp + '_archive-error.log')
            $archiveFailureContent = '时间：' + $archiveFailureTimestamp + "`n事件：" + [string]$archiveEventName + "`n错误：" + $_.Exception.ToString() + "`n"
            [System.IO.File]::WriteAllText($archiveFailurePath, $archiveFailureContent, $archiveUtf8)
        }
    }
    catch {
    }
    if ($archiveEventName -eq 'Stop') {
        [Console]::Out.WriteLine('{"continue":true}')
    }
    exit 0
}
