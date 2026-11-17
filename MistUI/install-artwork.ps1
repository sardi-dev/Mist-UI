# Copyright (c) 2026 sardi-dev. Licensed under the MIT License; see LICENSE.
#
# Downloads the texture files Mist-UI draws with from DragonUI's public repository and copies
# them into the MistUI and MistUI_Options folders next to this one. The artwork belongs to the
# game's publisher, so it cannot ship with Mist-UI itself (see docs/ARTWORK.md).
#
# Players start it with Install-Artwork.cmd. Windows PowerShell 5.1 is enough.
#   -Source   a DragonUI zip or an unpacked DragonUI folder to use instead of downloading
#   -Target   the folder that holds MistUI and MistUI_Options (default: the parent of this folder)

param(
    [string]$Source,
    [string]$Target
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Find-Manifest {
    $candidates = @(
        (Join-Path $PSScriptRoot 'art-manifest.json'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\art-manifest.json')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    throw 'art-manifest.json was not found next to this script.'
}

function Get-PortablePath([string]$Path) {
    return $Path.Replace('\', '/').ToLowerInvariant()
}

function Test-Covered([string]$Key, [object[]]$Entries) {
    foreach ($entry in $Entries) {
        $portable = Get-PortablePath $entry
        if ($Key -eq $portable -or $Key.StartsWith("$portable/")) { return $true }
    }
    return $false
}

# The archive holds one top folder (DragonUI-<commit>); the copy rules start below it.
function Get-UpstreamRoot([string]$Folder) {
    $top = @(Get-ChildItem -LiteralPath $Folder -Directory)
    if ($top.Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $Folder 'DragonUI'))) {
        return $top[0].FullName
    }
    return $Folder
}

function Get-Upstream($Manifest, [string]$WorkDir) {
    if ($Source -and (Test-Path -LiteralPath $Source -PathType Container)) {
        return (Resolve-Path -LiteralPath $Source).Path
    }
    $zip = Join-Path $WorkDir 'dragonui.zip'
    if ($Source) {
        Copy-Item -LiteralPath $Source -Destination $zip
    } else {
        $repo = $Manifest.upstream.repository.TrimEnd('/')
        $url = "$repo/archive/$($Manifest.upstream.commit).zip"
        Write-Host "Downloading the artwork from $url ..."
        # Windows PowerShell 5.1 does not offer TLS 1.2 by default, and GitHub requires it.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    }
    $unpacked = Join-Path $WorkDir 'unpacked'
    Write-Host 'Unpacking ...'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    return Get-UpstreamRoot $unpacked
}

# The list of (source, destination) pairs the manifest rules select.
function Get-CopyPlan($Manifest, [string]$UpstreamRoot, [string]$TargetRoot) {
    # Every source folder is checked before the first copy, so a wrong download changes nothing.
    foreach ($rule in $Manifest.copy) {
        if (-not (Test-Path -LiteralPath (Join-Path $UpstreamRoot $rule.from) -PathType Container)) {
            throw "The download has no folder $($rule.from)."
        }
    }
    $plan = New-Object System.Collections.ArrayList
    foreach ($rule in $Manifest.copy) {
        $fromDir = Join-Path $UpstreamRoot $rule.from
        $excluded = @()
        $included = @()
        if ($rule.PSObject.Properties['exclude']) { $excluded = @($rule.exclude) }
        if ($rule.PSObject.Properties['include']) { $included = @($rule.include) }
        $fromFull = (Resolve-Path -LiteralPath $fromDir).Path.TrimEnd('\')
        foreach ($file in Get-ChildItem -LiteralPath $fromFull -Recurse -File) {
            $relative = $file.FullName.Substring($fromFull.Length + 1)
            $key = Get-PortablePath $relative
            if ((Test-Covered $key $excluded) -and -not (Test-Covered $key $included)) { continue }
            $destination = Join-Path (Join-Path $TargetRoot $rule.to) $relative
            [void]$plan.Add(@($file.FullName, $destination))
        }
    }
    return ,$plan
}

# Copies the plan; a file it would overwrite is saved first, so a failure part way (a locked file,
# a full disk) puts the previous artwork back instead of leaving a mix of old and new files.
function Copy-Artwork($Plan, [string]$BackupDir) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $saved = New-Object System.Collections.ArrayList
    $created = New-Object System.Collections.ArrayList
    $index = 0
    try {
        foreach ($step in $Plan) {
            $destination = $step[1]
            $folder = Split-Path $destination -Parent
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                $backup = Join-Path $BackupDir ([string]$index)
                Copy-Item -LiteralPath $destination -Destination $backup
                [void]$saved.Add(@($destination, $backup))
            } elseif (-not (Test-Path -LiteralPath $destination)) {
                [void]$created.Add($destination)
            }
            Copy-Item -LiteralPath $step[0] -Destination $destination -Force
            $index++
        }
    } catch {
        Write-Host 'The copy failed; putting the previous artwork back ...'
        $notRestored = 0
        foreach ($path in $created) {
            try { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } } catch { $notRestored++ }
        }
        foreach ($pair in $saved) {
            try { Copy-Item -LiteralPath $pair[1] -Destination $pair[0] -Force } catch { $notRestored++ }
        }
        if ($notRestored -gt 0) { Write-Warning "$notRestored files could not be put back; run the script again." }
        throw
    }
    return $index
}

$targetRoot = $Target
if (-not $targetRoot) { $targetRoot = Split-Path $PSScriptRoot -Parent }
foreach ($addon in 'MistUI', 'MistUI_Options') {
    if (-not (Test-Path -LiteralPath (Join-Path $targetRoot $addon) -PathType Container)) {
        throw "The folder $addon was not found in $targetRoot. Keep MistUI and MistUI_Options side by side in Interface\AddOns."
    }
}

$manifest = Get-Content -LiteralPath (Find-Manifest) -Raw | ConvertFrom-Json
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("mistui-artwork-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir | Out-Null
try {
    $upstream = Get-Upstream $manifest $workDir
    $plan = Get-CopyPlan $manifest $upstream $targetRoot
    $count = Copy-Artwork $plan (Join-Path $workDir 'previous')
    Write-Host "Done: $count artwork files copied. Start the game to see them (if it is running, close it first: it only finds new files when it starts)."
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
