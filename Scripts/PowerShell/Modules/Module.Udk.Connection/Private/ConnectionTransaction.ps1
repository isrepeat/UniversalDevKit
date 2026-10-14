function Get-UdkTransactionPaths {
    param([string]$ProjectPath, [string]$SolutionPath)
    $paths = @([IO.Path]::GetFullPath($ProjectPath))
    if ($SolutionPath) { $paths += [IO.Path]::GetFullPath($SolutionPath) }
    return @($paths | Select-Object -Unique)
}

function Restore-UdkConnectionTransaction {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [string]$SolutionPath)
    $ErrorActionPreference = 'Stop'
    $paths = @(Get-UdkTransactionPaths $ProjectPath $SolutionPath)
    $directory = $paths[0] + '.UniversalDevKit.transaction'
    $manifestPath = Join-Path $directory 'manifest.json'
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or @($manifest.files).Count -ne $paths.Count) { throw "Invalid transaction manifest: $manifestPath" }
    # Проверяем весь снимок до первой записи; пути ограничены явно указанными файлами.
    $snapshots = @()
    for ($index = 0; $index -lt $paths.Count; $index++) {
        $entry = $manifest.files[$index]
        if ($entry.path -cne $paths[$index] -or $entry.snapshot -cne "$index.bin") { throw "Unexpected transaction path: $manifestPath" }
        $snapshot = Join-Path $directory "$index.bin"
        if ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -cne $entry.hash) { throw "Corrupt transaction snapshot: $snapshot" }
        $snapshots += ,([IO.File]::ReadAllBytes($snapshot))
    }
    $failures = @()
    for ($index = 0; $index -lt $paths.Count; $index++) {
        try {
            # Не перезаписываем неизменённый файл, который может быть открыт только для чтения.
            if (-not (Test-Path -LiteralPath $paths[$index] -PathType Leaf) -or (Get-FileHash -LiteralPath $paths[$index] -Algorithm SHA256).Hash -cne $manifest.files[$index].hash) {
                [IO.File]::WriteAllBytes($paths[$index], $snapshots[$index])
            }
        }
        catch { $failures += "$($paths[$index]): $($_.Exception.Message)" }
    }
    if ($failures.Count) { throw "Rollback failed. Snapshots retained at $directory. $($failures -join '; ')" }
    Remove-UdkTransactionSnapshot $directory $paths.Count
}

function Remove-UdkTransactionSnapshot {
    param([string]$Directory, [int]$Count)
    # Удаляем только известные файлы снимка, не используя рекурсивное удаление.
    for ($index = 0; $index -lt $Count; $index++) { [IO.File]::Delete((Join-Path $Directory "$index.bin")) }
    [IO.File]::Delete((Join-Path $Directory 'manifest.json'))
    [IO.Directory]::Delete($Directory)
}

function Invoke-UdkConnectionTransaction {
    param([string]$ProjectPath, [string]$SolutionPath, [scriptblock]$Action)
    $ErrorActionPreference = 'Stop'
    $paths = @(Get-UdkTransactionPaths $ProjectPath $SolutionPath)
    $directory = $paths[0] + '.UniversalDevKit.transaction'
    if (Test-Path -LiteralPath $directory) {
        throw "Unfinished transaction detected: $directory. Run Restore-UdkConnectionTransaction with the same ProjectPath and SolutionPath before retrying."
    }
    # Снимки создаются до запуска кода, изменяющего solution или consumer.
    $entries = @()
    $bytes = @()
    foreach ($path in $paths) { $bytes += ,([IO.File]::ReadAllBytes($path)) }
    [void][IO.Directory]::CreateDirectory($directory)
    for ($index = 0; $index -lt $paths.Count; $index++) {
        $snapshot = Join-Path $directory "$index.bin"
        $stream = [IO.File]::Open($snapshot, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes[$index], 0, $bytes[$index].Length) }
        finally { $stream.Dispose() }
        $entries += [pscustomobject]@{ path = $paths[$index]; snapshot = "$index.bin"; hash = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash }
    }
    $manifest = [pscustomobject]@{ schemaVersion = 1; files = $entries }
    [IO.File]::WriteAllText((Join-Path $directory 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    try { & $Action }
    catch {
        $operationError = $_
        try { Restore-UdkConnectionTransaction -ProjectPath $ProjectPath -SolutionPath $SolutionPath }
        catch { throw "Connection failed: $($operationError.Exception.Message). $($_.Exception.Message)" }
        throw $operationError
    }
    # Удаление снимка выполняется после всей операции, включая очистку solution.
    Remove-UdkTransactionSnapshot $directory $paths.Count
}