function New-UdkArtifactDrive {
    param([Parameter(Mandatory)][string]$Path)
    $mutex = [Threading.Mutex]::new($false, 'Local\UniversalDevKit.ArtifactDriveAllocation')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(30000) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Timed out waiting for build drive allocation.' }
        return New-UdkArtifactDriveCore -Path $Path
    } finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function New-UdkArtifactDriveCore {
    param([Parameter(Mandatory)][string]$Path)
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return [pscustomobject]@{ Path = $target; Drive = $null }
    }
    [void][IO.Directory]::CreateDirectory($target)
    # Stable letters preserve absolute paths in incremental CMake caches.
    $marker = Join-Path $target '.udk-build-drive'
    $drive = if (Test-Path -LiteralPath $marker) { [IO.File]::ReadAllText($marker) } else { $null }
    if ($drive -and $drive -cnotmatch '^[D-Z]:$') { throw "Invalid build drive marker: $marker" }
    $mappings = @(& subst)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect temporary build drives.' }
    if (-not $drive) {
        $occupied = @([IO.DriveInfo]::GetDrives().Name)
        # Reserve letters recorded by sibling builds even while they are idle.
        $parent = [IO.Path]::GetDirectoryName($target)
        foreach ($directory in Get-ChildItem -LiteralPath $parent -Directory -Force) {
            $siblingMarker = Join-Path $directory.FullName '.udk-build-drive'
            if (Test-Path -LiteralPath $siblingMarker -PathType Leaf) {
                $occupied += [IO.File]::ReadAllText($siblingMarker) + '\'
            }
        }
        foreach ($letter in 90..68) {
            $candidate = ([char]$letter).ToString() + ':'
            if ($occupied -notcontains "$candidate\" -and -not @($mappings | Where-Object { $_.StartsWith($candidate, [StringComparison]::OrdinalIgnoreCase) }).Count) {
                $drive = $candidate
                break
            }
        }
        if (-not $drive) { throw "No free build drive is available for $target." }
    }
    foreach ($mapping in $mappings) {
        if ($mapping -match ('^' + [regex]::Escape($drive) + '\\: => (.*)$')) {
            if ($matches[1].TrimEnd('\', '/') -ieq $target) {
                return [pscustomobject]@{ Path = "$drive\"; Drive = $null }
            }
            throw "Build drive $drive is already mapped. Release it before building $target."
        }
    }
    if ([IO.DriveInfo]::GetDrives().Name -contains "$drive\") {
        throw "Build drive $drive is occupied. A stable free drive is required for $target."
    }
    & subst $drive $target | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not map build drive $drive to $target." }
    try { [IO.File]::WriteAllText($marker, $drive, [Text.UTF8Encoding]::new($false)) }
    catch {
        & subst $drive /d | Out-Host
        throw
    }
    return [pscustomobject]@{ Path = "$drive\"; Drive = $drive }
}

function Remove-UdkArtifactDrive {
    param([Parameter(Mandatory)]$Mapping)
    if ($Mapping.Drive) {
        & subst $Mapping.Drive /d | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Warning "Could not release build drive $($Mapping.Drive)." }
    }
}

function Reset-UdkArtifactDirectory {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if (-not $target.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact directory must be below its root: $target"
    }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Cannot reset an artifact directory link: $target"
        }
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
    [void][IO.Directory]::CreateDirectory($target)
    return $target
}