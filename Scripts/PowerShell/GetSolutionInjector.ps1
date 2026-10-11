param([string]$LocalPath, [scriptblock]$ProgressCallback)

$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifest = Get-Content (Join-Path $repositoryPath 'Scripts/Tools/SolutionInjector.json') -Raw | ConvertFrom-Json

function SendToolProgress([string]$Stage, [long]$Completed, [long]$Total, [bool]$Finished = $false) {
    if ($ProgressCallback) {
        & $ProgressCallback ([pscustomobject]@{
            Stage = $Stage
            Completed = $Completed
            Total = $Total
            Finished = $Finished
        }) | Out-Null
    }
}

function DownloadToolArchive([string]$Url, [string]$Destination) {
    Add-Type -AssemblyName System.Net.Http
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        # Заголовки получаем отдельно, чтобы читать ответ порциями и показывать реальные байты.
        $response = $client.GetAsync($Url, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
        $total = if ($response.Content.Headers.ContentLength) { [long]$response.Content.Headers.ContentLength } else { -1L }
        $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [IO.File]::Create($Destination)
        $buffer = [byte[]]::new(131072)
        $completed = 0L
        $timer = [Diagnostics.Stopwatch]::StartNew()
        SendToolProgress 'Downloading SolutionInjector' 0 $total
        while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $count)
            $completed += $count
            if ($timer.ElapsedMilliseconds -ge 100) {
                SendToolProgress 'Downloading SolutionInjector' $completed $total
                $timer.Restart()
            }
        }
        SendToolProgress 'Downloading SolutionInjector' $completed $total $true
    }
    finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
    }
}

function ExpandToolArchive([string]$Path, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        # Считаем объём распакованных данных, чтобы размер файлов учитывался в процентах.
        $total = 0L
        foreach ($entry in $zip.Entries) { $total += $entry.Length }
        $completed = 0L
        $buffer = [byte[]]::new(131072)
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $timer = [Diagnostics.Stopwatch]::StartNew()
        SendToolProgress 'Extracting SolutionInjector' 0 $total
        foreach ($entry in $zip.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Archive entry is outside the tool directory.'
            }
            if (-not $entry.Name) {
                [void][IO.Directory]::CreateDirectory($target)
                continue
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $inputStream = $entry.Open()
            $outputStream = $null
            try {
                $outputStream = [IO.File]::Create($target)
                while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $outputStream.Write($buffer, 0, $count)
                    $completed += $count
                    if ($timer.ElapsedMilliseconds -ge 100) {
                        SendToolProgress 'Extracting SolutionInjector' $completed $total
                        $timer.Restart()
                    }
                }
            }
            finally {
                if ($outputStream) { $outputStream.Dispose() }
                $inputStream.Dispose()
            }
        }
        SendToolProgress 'Extracting SolutionInjector' $completed $total $true
    }
    finally { $zip.Dispose() }
}

function AssertExecutable([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "SolutionInjector not found: $Path" }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $manifest.exeSha256) {
        throw 'SolutionInjector executable SHA-256 mismatch.'
    }
}

# Локальный путь позволяет работать без сети с тем же проверенным бинарником.
if ($LocalPath) {
    $executable = (Resolve-Path -LiteralPath $LocalPath).Path
    AssertExecutable $executable
    return $executable
}

$toolDirectory = Join-Path $repositoryPath ('!tools/SolutionInjector/' + $manifest.version)
$archive = Join-Path $toolDirectory 'distribution.zip'
$executable = Join-Path $toolDirectory 'SolutionInjector.exe'
New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
if (Test-Path -LiteralPath $archive) {
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $manifest.archiveSha256) {
        throw "Cached archive SHA-256 mismatch: $archive"
    }
}
else {
    # Сначала проверяем временный архив; неполная загрузка не становится кешем.
    $temporaryArchive = Join-Path $toolDirectory ([Guid]::NewGuid().ToString() + '.zip')
    try {
        DownloadToolArchive $manifest.url $temporaryArchive
        if ((Get-FileHash -LiteralPath $temporaryArchive -Algorithm SHA256).Hash -ne $manifest.archiveSha256) {
            throw 'Downloaded archive SHA-256 mismatch.'
        }
        Move-Item -LiteralPath $temporaryArchive -Destination $archive
    }
    finally {
        if (Test-Path -LiteralPath $temporaryArchive) { Remove-Item -LiteralPath $temporaryArchive }
    }
}
# Распаковываем проверенный архив повторно, восстанавливая также runtime DLL.
ExpandToolArchive $archive $toolDirectory
AssertExecutable $executable
return $executable