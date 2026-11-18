param()

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('UdkSolutionInjector.' + [Guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA
$progress = [Collections.Generic.List[object]]::new()
$callback = { param($value) $progress.Add($value) }
try {
    $env:LOCALAPPDATA = $temporary
    $projectTools = Join-Path $repository 'Sources/Windows/UdkCli/Tools/ProjectTools/Private/GetSolutionInjector.ps1'
    $connect = Join-Path $repository 'Scripts/PowerShell/GetSolutionInjector.ps1'
    $manifest = Get-Content (Join-Path $repository 'Sources/Windows/UdkCli/Tools/SolutionInjector.json') -Raw | ConvertFrom-Json
    $projectExecutable = & $projectTools -ProgressCallback $callback
    if ((Get-FileHash -LiteralPath $projectExecutable).Hash -ne $manifest.exeSha256 -or
        -not @($progress | Where-Object Stage -eq 'Downloading SolutionInjector').Count) { throw 'The shared loader did not download and verify the release.' }
    $progress.Clear()
    $connectExecutable = & $connect -ProgressCallback $callback
    if ($connectExecutable -cne $projectExecutable -or @($progress | Where-Object Stage -eq 'Downloading SolutionInjector').Count) { throw 'Connect did not reuse the same verified cache.' }
    $localExecutable = & $connect -LocalPath $projectExecutable
    if ($localExecutable -cne $projectExecutable) { throw 'LocalPath did not return the verified executable.' }
    $badExecutable = Join-Path $temporary 'invalid.exe'
    [IO.File]::WriteAllBytes($badExecutable, [byte[]]@(1, 2, 3))
    $rejected = $false
    try { & $projectTools -LocalPath $badExecutable | Out-Null } catch { $rejected = $_.Exception.Message -match 'SHA-256 mismatch' }
    if (-not $rejected) { throw 'An unverified local executable was accepted.' }
    Remove-Item -LiteralPath $projectExecutable
    if ((& $connect) -cne $connectExecutable -or -not (Test-Path -LiteralPath $projectExecutable)) { throw 'The executable was not restored from the cached archive.' }
    $archive = Join-Path (Split-Path -Parent $projectExecutable) 'distribution.zip'
    $bytes = [IO.File]::ReadAllBytes($archive)
    $bytes[0] = $bytes[0] -bxor 1
    [IO.File]::WriteAllBytes($archive, $bytes)
    $rejected = $false
    try { & $connect | Out-Null } catch { $rejected = $_.Exception.Message -match 'Cached archive SHA-256 mismatch' }
    if (-not $rejected) { throw 'A corrupted cached archive was accepted.' }
    Write-Host 'PASS: common release download, shared cache, offline reuse, LocalPath verification and archive integrity.'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'UdkSolutionInjector.*') { throw 'Unexpected loader test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}