param(
    [ValidateSet('Windows', 'Android', 'All')][string]$Group = 'Windows',
    [string[]]$Test,
    [string]$CMake,
    [string]$AndroidNdk,
    [string]$Gradle,
    [string]$GradleCache,
    [string]$JavaHome,
    [string]$AndroidSdk,
    [switch]$ListOnly
)
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $CMake) {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { $CMake = $command.Source }
    else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe' | Select-Object -First 1)[0]
        }
    }
}
$cases = @(
    @{ Name = 'ScriptEncoding'; Group = 'Windows'; Path = 'Tests/Infrastructure/TestScriptEncoding.ps1'; Args = @() }
    @{ Name = 'ComponentGeneration'; Group = 'Windows'; Path = 'Scripts/PowerShell/GenerateComponentProjects.ps1'; Args = @('-Check') }
    @{ Name = 'RegistryContract'; Group = 'Windows'; Path = 'Tests/Infrastructure/TestRegistryContract.ps1'; Args = @('-CMake', $CMake) }
    @{ Name = 'ComponentRegistry'; Group = 'Windows'; Path = 'Tests/Infrastructure/TestComponentRegistry.ps1'; Args = @() }
    @{ Name = 'BuildExtensions'; Group = 'Windows'; Path = 'Tests/Infrastructure/TestBuildExtensions.ps1'; Args = @('-CMake', $CMake) }
    @{ Name = 'ConnectAndPublicHeaders'; Group = 'Windows'; Path = 'Tests/Scripts/PowerShell/RunTests.ps1'; Args = @(); Engine = 'powershell.exe' }
    @{ Name = 'CMakePackage'; Group = 'Windows'; Path = 'Tests/Integration/Cmake/TestCMakePackage.ps1'; Args = @('-CMake', $CMake) }
    @{ Name = 'BinaryCompatibility'; Group = 'Windows'; Path = 'Tests/Integration/Cmake/TestBinaryCompatibility.ps1'; Args = @('-CMake', $CMake) }
    @{ Name = 'NativeNuGet'; Group = 'Windows'; Path = 'Tests/Integration/Packages/NuGet.Tests.ps1'; Args = @('-LicenseFile', (Join-Path $repository 'LICENSE'), '-CMake', $CMake) }
    @{ Name = 'NuGetRegistry'; Group = 'Windows'; Path = 'Tests/Integration/Packages/NuGet.Registry.Tests.ps1'; Args = @('-CMake', $CMake) }
    @{ Name = 'PackageDelivery'; Group = 'Windows'; Path = 'Tests/Integration/Packages/PackageDelivery.Tests.ps1'; Args = @() }
    @{ Name = 'WinRtDelivery'; Group = 'Windows'; Path = 'Tests/Integration/Packages/PackageDelivery.Tests.ps1'; Args = @('-Family', 'WinRt', '-CMake', $CMake) }
    @{ Name = 'AndroidNativeDelivery'; Group = 'Android'; Path = 'Tests/Integration/Packages/PackageDelivery.Tests.ps1'; Args = @('-Family', 'AndroidNative', '-CMake', $CMake, '-AndroidNdk', $AndroidNdk) }
    @{ Name = 'AndroidMavenDelivery'; Group = 'Android'; Path = 'Tests/Integration/Packages/PackageDelivery.Tests.ps1'; Args = @('-Family', 'AndroidMaven', '-Gradle', $Gradle, '-JavaHome', $JavaHome, '-AndroidSdk', $AndroidSdk) }
)
if ($GradleCache) { $cases[-1].Args += @('-GradleCache', $GradleCache) }
foreach ($name in $Test) {
    if ($name -notin @($cases | ForEach-Object { $_.Name })) { throw "Unknown test: $name" }
}
$selected = @($cases | Where-Object { ($Group -eq 'All' -or $_.Group -eq $Group) -and (-not $Test -or $_.Name -in $Test) })
if (-not $selected.Count) { throw 'No tests selected.' }
if ($ListOnly) { $selected | ForEach-Object { Write-Output "$($_.Group): $($_.Name)" }; exit 0 }
$report = Join-Path $repository ('!artifacts/tests/all-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
[void][IO.Directory]::CreateDirectory($report)
$results = @($cases | ForEach-Object {
    [pscustomobject]@{ Test = $_.Name; Status = if ($_ -in $selected) { 'NotRun' } else { 'NotSelected' }; ExitCode = ''; Log = ''; Error = '' }
})
# Дочерние процессы изолируют exit и изменения окружения отдельных сценариев.
foreach ($case in $selected) {
    $record = $results | Where-Object Test -eq $case.Name
    $record.Status = 'Running'
    $record.Log = Join-Path $report ($case.Name + '.log')
    $results | Export-Csv (Join-Path $report 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "RUN: $($case.Name)"
    try {
        $engine = if ($case.Engine) { $case.Engine } else { 'pwsh.exe' }
        if (-not (Get-Command $engine -ErrorAction SilentlyContinue)) { throw "Required engine missing: $engine" }
        if (@($case.Args | Where-Object { $null -eq $_ -or "$_" -eq '' }).Count) { throw 'Required tool path or parameter is missing.' }
        $previousPreference = $ErrorActionPreference
        try {
            # stderr может содержать предупреждения успешной сборки; результат задаёт exit code.
            $ErrorActionPreference = 'Continue'
            & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repository $case.Path) @($case.Args) 2>&1 |
                Tee-Object -FilePath $record.Log | Out-Host
        }
        finally { $ErrorActionPreference = $previousPreference }
        $record.ExitCode = $LASTEXITCODE
        $record.Status = if ($LASTEXITCODE -eq 0) { 'Passed' } else { 'Failed' }
    }
    catch { $record.Status = 'Failed'; $record.Error = $_.Exception.Message; Write-Host $record.Error }
    $results | Export-Csv (Join-Path $report 'summary.csv') -NoTypeInformation -Encoding UTF8
}
$results | Format-Table Test, Status, ExitCode -AutoSize
Write-Host "Report: $report"
if (@($results | Where-Object Status -in @('Failed', 'NotRun', 'Running')).Count) { exit 1 }
exit 0