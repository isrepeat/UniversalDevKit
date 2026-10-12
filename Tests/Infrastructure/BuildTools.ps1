function Get-TestMSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer/vswhere is required.' }
    $paths = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\**\Bin\MSBuild.exe')
    if ($LASTEXITCODE -ne 0 -or -not $paths.Count) { throw 'MSBuild with Visual C++ tools is required.' }
    return $paths[0]
}

function Invoke-TestBuild {
    param([string]$MSBuild, [string]$Project, [string]$Configuration, [string]$LogDirectory)
    [void][IO.Directory]::CreateDirectory($LogDirectory)
    $name = [IO.Path]::GetFileNameWithoutExtension($Project)
    $log = Join-Path $LogDirectory "$name-$Configuration.log"
    $binlog = Join-Path $LogDirectory "$name-$Configuration.binlog"
    & $MSBuild $Project /m /nologo /v:minimal /t:Rebuild "/p:Configuration=$Configuration" /p:Platform=x64 "/bl:$binlog" 2>&1 | Tee-Object -FilePath $log | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $Project ($Configuration). See $log" }
}

function Invoke-TestApplication {
    param([string]$Executable, [string]$ExpectedOutput)
    # stderr содержит обычный Diagnostic Log; PowerShell 5.1 не должен считать его ошибкой теста.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($Executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw "Application timeout: $Executable" }
        $output = $stdout.Result + $stderr.Result
        if ($process.ExitCode -ne 0 -or $output -notmatch [regex]::Escape($ExpectedOutput)) {
            throw "Application failed: $Executable; $output"
        }
        Write-Host $output.TrimEnd()
    }
    finally { $process.Dispose() }
}