[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $encoding
[Console]::OutputEncoding = $encoding
$OutputEncoding = $encoding
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$artifactRoot = Join-Path $repository '!artifacts'
$mappings = @{}
foreach ($line in @(& subst)) {
    if ($line -match '^([A-Za-z]:)\\: => (.+)$') {
        $mappings[$matches[1].ToUpperInvariant()] = $matches[2]
    }
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate substituted drives.' }

# Раскрываем вложенные подключения ANGLE до физического пути.
function ResolveDriveTarget([string]$Path) {
    $visited = @{}
    while ($Path -match '^([A-Za-z]:)[\\/]') {
        $drive = $matches[1].ToUpperInvariant()
        if (-not $mappings.ContainsKey($drive)) { break }
        if ($visited.ContainsKey($drive)) { throw "Circular drive mapping: $drive" }
        $visited[$drive] = $true
        $Path = [IO.Path]::Combine($mappings[$drive] + '\', $Path.Substring(3))
    }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

$locks = @{}
$candidates = @()
try {
    foreach ($drive in @($mappings.Keys | Sort-Object)) {
        $target = ResolveDriveTarget ($drive + '\')
        if (-not $target.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and $target -ine $artifactRoot) { continue }
        $directory = $target
        while ($directory -and $directory.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $lockPath = Join-Path $directory '.build.lock'
            if ((Test-Path -LiteralPath $lockPath -PathType Leaf) -and -not $locks.ContainsKey($lockPath)) {
                try {
                    $locks[$lockPath] = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                } catch { throw "Build is active or its lock is inaccessible: $directory. Stop the build before resetting drives." }
            }
            if ($directory -ieq $artifactRoot) { break }
            $directory = [IO.Path]::GetDirectoryName($directory)
        }
        $candidates += [pscustomobject]@{ Drive = $drive; Target = $target }
    }
    # Сначала снимаем более глубокие подключения; файлы и маркеры сохраняются.
    foreach ($candidate in ($candidates | Sort-Object { $_.Target.Length } -Descending)) {
        if ($PSCmdlet.ShouldProcess("$($candidate.Drive) => $($candidate.Target)", 'Remove substituted build drive')) {
            & subst $candidate.Drive /d | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Cannot release build drive $($candidate.Drive)." }
            Write-Host "Released $($candidate.Drive) => $($candidate.Target)"
        }
    }
    if (-not $candidates.Count) { Write-Host 'No substituted drives for this repository artifacts were found.' }
} finally {
    foreach ($handle in $locks.Values) { $handle.Dispose() }
}