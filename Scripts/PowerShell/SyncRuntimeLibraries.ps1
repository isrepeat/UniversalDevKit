param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$SourceList
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# MSBuild может наследовать PSModulePath от pwsh; загружаем Utility текущего host.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility') -ErrorAction Stop
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
if ((Get-Item -LiteralPath $output).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime output directory must not be a reparse point.' }
$state = Join-Path $output '.UniversalDevKitRuntime'
if (Test-Path -LiteralPath $state) {
    if ((Get-Item -LiteralPath $state).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime state directory must not be a reparse point.' }
}
[void][IO.Directory]::CreateDirectory($state)
$hasher = [Security.Cryptography.SHA256]::Create()
try { $key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Owner))).Replace('-', '') }
finally { $hasher.Dispose() }
$manifest = Join-Path $state ($key + '.json')
$lock = $null
try {
    # Блокировка сериализует владельцев общего OutDir; другие каталоги независимы.
    for ($attempt = 0; $attempt -lt 100 -and -not $lock; $attempt++) {
        try { $lock = [IO.File]::Open((Join-Path $state 'sync.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] { Start-Sleep -Milliseconds 100 }
    }
    if (-not $lock) { throw 'Runtime delivery is busy; retry the build.' }
    $previous = @()
    $others = @()
    foreach ($file in Get-ChildItem -LiteralPath $state -Filter '*.json' -File) {
        $record = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
        if ($record.schemaVersion -ne 1) { throw 'Unsupported runtime manifest.' }
        foreach ($entry in $record.files) {
            if ($entry.name -ne [IO.Path]::GetFileName($entry.name) -or $entry.name -notmatch '^[^\\/:*?"<>|]+\.dll$' -or $entry.hash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid runtime manifest entry.' }
        }
        if ($file.FullName -eq $manifest) { $previous = @($record.files) } else { $others += @($record.files) }
    }
    $current = @{}
    foreach ($source in [IO.File]::ReadAllLines($SourceList)) {
        if (-not $source.Trim()) { continue }
        $name = [IO.Path]::GetFileName($source)
        if ([IO.Path]::GetExtension($name) -ine '.dll') { throw 'Only DLL files may be delivered.' }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($current.ContainsKey($name) -and $current[$name].hash -ne $hash) { throw "Conflicting DLL sources: $name" }
        if (@($others | Where-Object { $_.name -ieq $name -and $_.hash -ne $hash }).Count) { throw "Another consumer requires a different DLL: $name. Use separate OutDir values." }
        $target = Join-Path $output $name
        $managed = $true
        if (Test-Path -LiteralPath $target) {
            if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "DLL must not be a reparse point: $name" }
            $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $owned = @($previous + $others | Where-Object { $_.name -ieq $name -and $_.hash -eq $targetHash -and $_.managed -ne $false }).Count
            if ($targetHash -ne $hash -and -not $owned) { throw "Refusing to overwrite an unowned or modified DLL: $name" }
            $managed = [bool]$owned
        }
        $current[$name] = [pscustomobject]@{ name = $name; hash = $hash; source = $source; managed = $managed }
    }
    # Копируем после проверки всего набора; изменённые вручную файлы не удаляем.
    foreach ($entry in $current.Values) {
        $target = Join-Path $output $entry.name
        if (-not (Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.hash) {
            Copy-Item -LiteralPath $entry.source -Destination $target
        }
    }
    foreach ($entry in $previous) {
        if ($entry.managed -eq $false) { continue }
        if ($current.ContainsKey($entry.name) -or @($others | Where-Object { $_.name -ieq $entry.name }).Count) { continue }
        $target = Join-Path $output $entry.name
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $entry.hash) {
            Remove-Item -LiteralPath $target
            Write-Output "Removed stale runtime DLL: $($entry.name)"
        }
        else { Write-Warning "Preserved modified runtime DLL: $($entry.name)" }
    }
    $record = @{ schemaVersion = 1; owner = $Owner; files = @($current.Values | Sort-Object name | Select-Object name, hash, managed) }
    $temporary = $manifest + '.tmp'
    [IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $manifest) { [IO.File]::Replace($temporary, $manifest, ($manifest + '.bak')) }
    else { [IO.File]::Move($temporary, $manifest) }
}
finally { if ($lock) { $lock.Dispose() } }