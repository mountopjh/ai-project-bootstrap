[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('init', 'check', 'upgrade', 'repair')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$TargetPath,

    [switch]$Force
)

Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "AI_PROJECT_BOOTSTRAP 需要 PowerShell 7 或以上版本（当前：$($PSVersionTable.PSVersion)）。请使用 pwsh 运行本脚本。"
    exit 1
}
$ErrorActionPreference = 'Stop'
$BootstrapRoot = $PSScriptRoot
$MetadataName = '.ai-project-bootstrap.json'
$ArchiveDirectories = @(
    'archive/development',
    'archive/code',
    'archive/conversations',
    'archive/bootstrap'
)

function Get-ExactTimestamp {
    Get-Date -Format 'yyyyMMdd-HHmmss'
}

function Test-ExactTimestamp {
    param([string]$Value)
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyyMMdd-HHmmss',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Resolve-TargetRoot {
    param([string]$RawPath)
    if ([IO.Path]::IsPathRooted($RawPath)) {
        return [IO.Path]::GetFullPath($RawPath)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $RawPath))
}

function Read-Utf8Text {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}

function Write-AtomicBytes {
    param(
        [string]$Path,
        [byte[]]$Bytes
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $temporary = Join-Path $parent (
        '.' + [IO.Path]::GetFileName($Path) + '.' + (Get-ExactTimestamp) + '.' + $PID + '.tmp'
    )
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Write-AtomicText {
    param(
        [string]$Path,
        [string]$Text
    )
    Write-AtomicBytes -Path $Path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-ByteHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash($Bytes)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-PathHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BootstrapManifest {
    $path = Join-Path $BootstrapRoot 'manifest.json'
    $value = Read-Utf8Text -Path $path | ConvertFrom-Json
    if ($value.name -ne 'AI_PROJECT_BOOTSTRAP' -or $null -eq $value.files) {
        throw 'manifest.json 无效'
    }
    return $value
}

function ConvertTo-JsonStringContent {
    param([string]$Value)
    $encoded = ConvertTo-Json $Value -Compress
    return $encoded.Substring(1, $encoded.Length - 2)
}

function Get-RenderContext {
    param(
        [string]$TargetRoot,
        [object]$Manifest,
        [string]$Timestamp
    )
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        $pwsh = Get-Command powershell -ErrorAction Stop
    }
    $hook = Join-Path $TargetRoot '.codex/hooks/archive-conversation.ps1'
    $command = '"' + $pwsh.Source.Replace('"', '\"') + '" -NoProfile -File "' + $hook.Replace('"', '\"') + '"'
    $encoded = ConvertTo-JsonStringContent -Value $command
    return @{
        '{{TIMESTAMP}}' = $Timestamp
        '{{PROJECT_NAME}}' = Split-Path -Leaf $TargetRoot
        '{{PROJECT_ROOT}}' = $TargetRoot
        '{{BOOTSTRAP_VERSION}}' = [string]$Manifest.version
        '{{HOOK_COMMAND_JSON}}' = $encoded
        '{{HOOK_COMMAND_WINDOWS_JSON}}' = $encoded
    }
}

function Get-EntryBytes {
    param(
        [object]$Entry,
        [hashtable]$Context
    )
    $source = Join-Path $BootstrapRoot $Entry.source
    if (-not [IO.File]::Exists($source)) {
        throw "初始化器源文件缺失：$source"
    }
    $bytes = [IO.File]::ReadAllBytes($source)
    if (-not $Entry.render) {
        return $bytes
    }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    foreach ($item in $Context.GetEnumerator()) {
        $text = $text.Replace([string]$item.Key, [string]$item.Value)
    }
    $unresolved = @(
        [regex]::Matches($text, '{{[A-Z0-9_]+}}') |
            ForEach-Object Value |
            Sort-Object -Unique
    )
    if ($unresolved.Count -gt 0) {
        throw "$($Entry.source) 仍有变量：$($unresolved -join ', ')"
    }
    return [Text.UTF8Encoding]::new($false).GetBytes($text)
}

function Add-RequiredLines {
    param(
        [string]$Path,
        [byte[]]$Bytes
    )
    $required = [Text.UTF8Encoding]::new($false).GetString($Bytes) -split '\r?\n' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $current = if ([IO.File]::Exists($Path)) { Read-Utf8Text -Path $Path } else { '' }
    $lines = $current -split '\r?\n'
    $missing = @($required | Where-Object { $_ -notin $lines })
    if ($missing.Count -eq 0) {
        return $false
    }
    $lineFeed = [char]10
    $prefix = $current.TrimEnd([char]13, [char]10)
    $updated = if ($prefix) {
        $prefix + $lineFeed + ($missing -join $lineFeed) + $lineFeed
    }
    else {
        ($missing -join $lineFeed) + $lineFeed
    }
    Write-AtomicText -Path $Path -Text $updated
    return $true
}

function Initialize-ArchiveDirectories {
    param([string]$TargetRoot)
    foreach ($relative in $ArchiveDirectories) {
        [IO.Directory]::CreateDirectory((Join-Path $TargetRoot $relative)) | Out-Null
    }
}

function Get-MetadataPath {
    param([string]$TargetRoot)
    return Join-Path $TargetRoot $MetadataName
}

function Read-Metadata {
    param(
        [string]$TargetRoot,
        [switch]$Required
    )
    $path = Get-MetadataPath -TargetRoot $TargetRoot
    if (-not [IO.File]::Exists($path)) {
        if ($Required) {
            throw "缺少 $MetadataName；请先 init，或用 repair 补齐登记"
        }
        return $null
    }
    return Read-Utf8Text -Path $path | ConvertFrom-Json
}

function Get-ManagedHashes {
    param(
        [string]$TargetRoot,
        [object]$Manifest
    )
    $result = [ordered]@{}
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        if ($entry.policy -eq 'managed' -and [IO.File]::Exists($path)) {
            $result[$entry.target] = Get-PathHash -Path $path
        }
    }
    return $result
}

function Write-Metadata {
    param(
        [string]$TargetRoot,
        [object]$Manifest,
        [string]$InstalledAt,
        [string]$UpdatedAt,
        [System.Collections.IDictionary]$Hashes
    )
    $value = [ordered]@{
        name = $Manifest.name
        version = $Manifest.version
        installed_at = $InstalledAt
        updated_at = $UpdatedAt
        target_root = $TargetRoot
        managed_files = $Hashes
    }
    $json = (ConvertTo-Json $value -Depth 20) + [Environment]::NewLine
    Write-AtomicText -Path (Get-MetadataPath -TargetRoot $TargetRoot) -Text $json
}

function Get-RecordedHash {
    param(
        [object]$Metadata,
        [string]$Relative
    )
    if ($null -eq $Metadata -or $null -eq $Metadata.managed_files) {
        return $null
    }
    $property = $Metadata.managed_files.PSObject.Properties[$Relative]
    if ($null -eq $property) {
        return $null
    }
    return [string]$property.Value
}

function Invoke-Init {
    param(
        [string]$TargetRoot,
        [object]$Manifest
    )
    $conflicts = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Manifest.files) {
        if ($entry.policy -ne 'append' -and (Test-Path -LiteralPath (Join-Path $TargetRoot $entry.target))) {
            $conflicts.Add($entry.target)
        }
    }
    if ([IO.File]::Exists((Get-MetadataPath -TargetRoot $TargetRoot))) {
        $conflicts.Add($MetadataName)
    }
    if ($conflicts.Count -gt 0) {
        throw 'init 已停止，避免覆盖：' + (($conflicts | Sort-Object -Unique) -join ', ')
    }
    $stamp = Get-ExactTimestamp
    [IO.Directory]::CreateDirectory($TargetRoot) | Out-Null
    Initialize-ArchiveDirectories -TargetRoot $TargetRoot
    $context = Get-RenderContext -TargetRoot $TargetRoot -Manifest $Manifest -Timestamp $stamp
    $changed = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        $bytes = Get-EntryBytes -Entry $entry -Context $context
        if ($entry.policy -eq 'append') {
            if (Add-RequiredLines -Path $path -Bytes $bytes) {
                $changed.Add($entry.target)
            }
        }
        else {
            Write-AtomicBytes -Path $path -Bytes $bytes
            $changed.Add($entry.target)
        }
    }
    $hashes = Get-ManagedHashes -TargetRoot $TargetRoot -Manifest $Manifest
    Write-Metadata -TargetRoot $TargetRoot -Manifest $Manifest -InstalledAt $stamp -UpdatedAt $stamp -Hashes $hashes
    return [ordered]@{ action = 'init'; ok = $true; target = $TargetRoot; changed = $changed }
}

function Invoke-Repair {
    param(
        [string]$TargetRoot,
        [object]$Manifest
    )
    $stamp = Get-ExactTimestamp
    [IO.Directory]::CreateDirectory($TargetRoot) | Out-Null
    Initialize-ArchiveDirectories -TargetRoot $TargetRoot
    $context = Get-RenderContext -TargetRoot $TargetRoot -Manifest $Manifest -Timestamp $stamp
    $metadata = Read-Metadata -TargetRoot $TargetRoot
    $changed = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        $bytes = Get-EntryBytes -Entry $entry -Context $context
        if ($entry.policy -eq 'append') {
            if (Add-RequiredLines -Path $path -Bytes $bytes) {
                $changed.Add($entry.target)
            }
        }
        elseif ($entry.policy -eq 'local') {
            $expected = Get-ByteHash -Bytes $bytes
            $actual = if (Test-Path -LiteralPath $path) { Get-PathHash -Path $path } else { $null }
            if ($actual -ne $expected) {
                Write-AtomicBytes -Path $path -Bytes $bytes
                $changed.Add($entry.target)
            }
        }
        elseif (-not (Test-Path -LiteralPath $path)) {
            Write-AtomicBytes -Path $path -Bytes $bytes
            $changed.Add($entry.target)
        }
    }
    $hashes = [ordered]@{}
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        if ($entry.policy -ne 'managed' -or -not [IO.File]::Exists($path)) {
            continue
        }
        $actual = Get-PathHash -Path $path
        $expected = Get-ByteHash -Bytes (Get-EntryBytes -Entry $entry -Context $context)
        $recorded = Get-RecordedHash -Metadata $metadata -Relative $entry.target
        if ($null -ne $recorded -or $entry.target -in $changed -or $actual -eq $expected) {
            $hashes[$entry.target] = $actual
        }
    }
    $installed = if ($null -ne $metadata -and $metadata.installed_at) {
        [string]$metadata.installed_at
    }
    else {
        $stamp
    }
    Write-Metadata -TargetRoot $TargetRoot -Manifest $Manifest -InstalledAt $installed -UpdatedAt $stamp -Hashes $hashes
    return [ordered]@{ action = 'repair'; ok = $true; target = $TargetRoot; changed = $changed }
}

function Invoke-Upgrade {
    param(
        [string]$TargetRoot,
        [object]$Manifest,
        [bool]$ForceOverwrite
    )
    $metadata = Read-Metadata -TargetRoot $TargetRoot -Required
    $stamp = Get-ExactTimestamp
    $context = Get-RenderContext -TargetRoot $TargetRoot -Manifest $Manifest -Timestamp $stamp
    $replacements = [Collections.Generic.List[object]]::new()
    $conflicts = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Manifest.files) {
        if ($entry.policy -ne 'managed') {
            continue
        }
        $path = Join-Path $TargetRoot $entry.target
        $bytes = Get-EntryBytes -Entry $entry -Context $context
        if (-not [IO.File]::Exists($path)) {
            $replacements.Add([pscustomobject]@{ Entry = $entry; Bytes = $bytes; Existed = $false })
            continue
        }
        $actual = Get-PathHash -Path $path
        if ($actual -eq (Get-ByteHash -Bytes $bytes)) {
            continue
        }
        if ((Get-RecordedHash -Metadata $metadata -Relative $entry.target) -ne $actual) {
            $conflicts.Add($entry.target)
        }
        $replacements.Add([pscustomobject]@{ Entry = $entry; Bytes = $bytes; Existed = $true })
    }
    if ($conflicts.Count -gt 0 -and -not $ForceOverwrite) {
        throw (
            '检测到人工修改，upgrade 已停止：' + ($conflicts -join ', ') +
            '；确认覆盖时使用 -Force，原文件会先归档'
        )
    }
    Initialize-ArchiveDirectories -TargetRoot $TargetRoot
    $backupRoot = Join-Path $TargetRoot ('archive/bootstrap/' + $stamp)
    $changed = [Collections.Generic.List[string]]::new()
    $backedUp = $false
    foreach ($replacement in $replacements) {
        $entry = $replacement.Entry
        $path = Join-Path $TargetRoot $entry.target
        if ($replacement.Existed) {
            $backup = Join-Path $backupRoot $entry.target
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            Copy-Item -LiteralPath $path -Destination $backup
            $backedUp = $true
        }
        Write-AtomicBytes -Path $path -Bytes $replacement.Bytes
        $changed.Add($entry.target)
    }
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        $bytes = Get-EntryBytes -Entry $entry -Context $context
        if ($entry.policy -eq 'state' -and -not (Test-Path -LiteralPath $path)) {
            Write-AtomicBytes -Path $path -Bytes $bytes
            $changed.Add($entry.target)
        }
        elseif ($entry.policy -eq 'append' -and (Add-RequiredLines -Path $path -Bytes $bytes)) {
            $changed.Add($entry.target)
        }
        elseif ($entry.policy -eq 'local') {
            $expected = Get-ByteHash -Bytes $bytes
            $actual = if (Test-Path -LiteralPath $path) { Get-PathHash -Path $path } else { $null }
            if ($actual -ne $expected) {
                Write-AtomicBytes -Path $path -Bytes $bytes
                $changed.Add($entry.target)
            }
        }
    }
    $installed = if ($metadata.installed_at) { [string]$metadata.installed_at } else { $stamp }
    $hashes = Get-ManagedHashes -TargetRoot $TargetRoot -Manifest $Manifest
    Write-Metadata -TargetRoot $TargetRoot -Manifest $Manifest -InstalledAt $installed -UpdatedAt $stamp -Hashes $hashes
    $result = [ordered]@{ action = 'upgrade'; ok = $true; target = $TargetRoot; changed = $changed }
    if ($backedUp) {
        $result.backup = $backupRoot
    }
    return $result
}

function Add-TimeIssue {
    param(
        [Collections.Generic.List[string]]$Issues,
        [string]$Path,
        [string]$Label
    )
    if (-not [IO.File]::Exists($Path)) {
        return
    }
    $pattern = [regex]::Escape($Label) + '\s*\x60?([^\x60\s]+)\x60?'
    $match = [regex]::Match((Read-Utf8Text -Path $Path), $pattern)
    if (-not $match.Success) {
        $Issues.Add(([IO.Path]::GetFileName($Path) + " 缺少时间字段：$Label"))
    }
    elseif (-not (Test-ExactTimestamp -Value $match.Groups[1].Value)) {
        $Issues.Add(([IO.Path]::GetFileName($Path) + ' 时间格式无效：' + $match.Groups[1].Value))
    }
}

function Invoke-Check {
    param(
        [string]$TargetRoot,
        [object]$Manifest
    )
    $issues = [Collections.Generic.List[string]]::new()
    $context = Get-RenderContext -TargetRoot $TargetRoot -Manifest $Manifest -Timestamp (Get-ExactTimestamp)
    if (-not [IO.Directory]::Exists($TargetRoot)) {
        $issues.Add('目标目录不存在')
    }
    foreach ($entry in $Manifest.files) {
        $path = Join-Path $TargetRoot $entry.target
        if (-not [IO.File]::Exists($path)) {
            $issues.Add("缺少文件：$($entry.target)")
            continue
        }
        if ($entry.policy -eq 'append') {
            $requiredText = [Text.UTF8Encoding]::new($false).GetString(
                (Get-EntryBytes -Entry $entry -Context $context)
            )
            $required = $requiredText -split '\r?\n' |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $current = (Read-Utf8Text -Path $path) -split '\r?\n'
            foreach ($line in $required) {
                if ($line -notin $current) {
                    $issues.Add("$($entry.target) 缺少条目：$line")
                }
            }
        }
        elseif ($entry.render) {
            $unresolved = [regex]::Matches((Read-Utf8Text -Path $path), '{{[A-Z0-9_]+}}')
            if ($unresolved.Count -gt 0) {
                $issues.Add("$($entry.target) 存在未解析变量")
            }
        }
    }
    foreach ($relative in $ArchiveDirectories) {
        if (-not [IO.Directory]::Exists((Join-Path $TargetRoot $relative))) {
            $issues.Add("缺少目录：$relative")
        }
    }
    Add-TimeIssue -Issues $issues -Path (Join-Path $TargetRoot 'PROJECT_INDEX.md') -Label '更新时间：'
    Add-TimeIssue -Issues $issues -Path (Join-Path $TargetRoot 'DEVELOPMENT_MAP.md') -Label '更新时间：'
    Add-TimeIssue -Issues $issues -Path (Join-Path $TargetRoot 'CODE_MAP.md') -Label '更新时间：'
    Add-TimeIssue -Issues $issues -Path (Join-Path $TargetRoot 'archive/conversations/INDEX.md') -Label '更新时间：'
    $hooksPath = Join-Path $TargetRoot '.codex/hooks.json'
    if ([IO.File]::Exists($hooksPath)) {
        try {
            $hooks = Read-Utf8Text -Path $hooksPath | ConvertFrom-Json
            foreach ($event in @('UserPromptSubmit', 'Stop')) {
                $eventProperty = $hooks.hooks.PSObject.Properties[$event]
                if ($null -eq $eventProperty) {
                    $issues.Add(".codex/hooks.json 缺少 $event 命令")
                    continue
                }
                $item = $eventProperty.Value[0].hooks[0]
                $command = if ($item.commandWindows) { $item.commandWindows } else { $item.command }
                if (-not $command) {
                    $issues.Add(".codex/hooks.json 的 $event 命令为空")
                }
                elseif ($command.Replace('\', '/').ToLowerInvariant() -notlike (
                    '*' + $TargetRoot.Replace('\', '/').ToLowerInvariant() + '*'
                )) {
                    $issues.Add(".codex/hooks.json 的 $event 未指向当前项目")
                }
            }
        }
        catch {
            $issues.Add('.codex/hooks.json 无效：' + $_.Exception.Message)
        }
    }
    $metadata = Read-Metadata -TargetRoot $TargetRoot
    if ($null -eq $metadata) {
        $issues.Add("缺少 $MetadataName")
    }
    else {
        if ($metadata.name -ne $Manifest.name) {
            $issues.Add('初始化器登记名称不匹配')
        }
        if ([string]$metadata.target_root -ne $TargetRoot) {
            $issues.Add('初始化器登记路径不匹配')
        }
        foreach ($field in @('installed_at', 'updated_at')) {
            if (-not (Test-ExactTimestamp -Value ([string]$metadata.$field))) {
                $issues.Add("$MetadataName 的 $field 无效")
            }
        }
        foreach ($entry in $Manifest.files) {
            $path = Join-Path $TargetRoot $entry.target
            if ($entry.policy -ne 'managed' -or -not [IO.File]::Exists($path)) {
                continue
            }
            $recorded = Get-RecordedHash -Metadata $metadata -Relative $entry.target
            if ($null -eq $recorded) {
                $issues.Add("受管理文件未登记：$($entry.target)")
            }
            elseif ($recorded -ne (Get-PathHash -Path $path)) {
                $issues.Add("受管理文件已被修改：$($entry.target)")
            }
        }
    }
    return [ordered]@{ action = 'check'; ok = ($issues.Count -eq 0); target = $TargetRoot; issues = $issues }
}

try {
    $BootstrapManifest = Get-BootstrapManifest
    $TargetRoot = Resolve-TargetRoot -RawPath $TargetPath
    $result = switch ($Action) {
        'init' { Invoke-Init -TargetRoot $TargetRoot -Manifest $BootstrapManifest }
        'check' { Invoke-Check -TargetRoot $TargetRoot -Manifest $BootstrapManifest }
        'repair' { Invoke-Repair -TargetRoot $TargetRoot -Manifest $BootstrapManifest }
        'upgrade' {
            Invoke-Upgrade -TargetRoot $TargetRoot -Manifest $BootstrapManifest -ForceOverwrite $Force.IsPresent
        }
    }
    $result | ConvertTo-Json -Depth 20
    if (-not $result.ok) {
        exit 1
    }
}
catch {
    [ordered]@{
        action = $Action
        ok = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 20
    exit 1
}
