param(
    [Parameter(Mandatory = $true)][string]$LicenseFile,
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [string]$Feed
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Tests/Infrastructure/BuildTools.ps1')
$msbuild = Get-TestMSBuild
$run = Join-Path $repository ('!artifacts/tests/nuget-' + [Guid]::NewGuid().ToString('N'))
if (-not $Feed) {
    $Feed = Join-Path $run 'feed'
    & (Join-Path $repository 'Packages/NuGet/Build.ps1') -LicenseFile $LicenseFile -CMake $CMake -NuGet $NuGet -OutputDirectory $Feed
}
$version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version
$fixture = Join-Path $repository 'Tests/Fixtures/Consumers/NuGet'
foreach ($runtime in @('Dynamic', 'Static')) {
    foreach ($scenario in @('BothStatic', 'DiagnosticDynamic', 'HelpersDynamic')) {
        $linkage = if ($scenario -eq 'BothStatic') { 'Static' } else { 'Dynamic' }
        $helperLinkage = if ($scenario -eq 'HelpersDynamic') { 'Dynamic' } else { 'Static' }
        $roots = if ($scenario -eq 'HelpersDynamic') { 'Helpers' } else { 'Diagnostic;Helpers' }
        $consumer = Join-Path $run "consumer-$runtime-$scenario"
        [void][IO.Directory]::CreateDirectory($consumer)
        Copy-Item -LiteralPath (Join-Path $fixture 'Main.cpp') -Destination $consumer
        foreach ($file in @('Consumer.vcxproj', 'packages.config')) {
            $text = (Get-Content (Join-Path $fixture "$file.in") -Raw).Replace('{{VERSION}}', $version)
            $import = if ($scenario -ne 'HelpersDynamic') { '  <Import Project="packages\UniversalDevKit.Diagnostic.' + $version + '\build\native\UniversalDevKit.Diagnostic.targets" />' } else { '' }
            $props = $import.Replace('.targets', '.props')
            $define = if ($scenario -eq 'HelpersDynamic') { 'UDK_TEST_HELPERS_ONLY' } else { '' }
            $text = $text.Replace('{{DIAGNOSTIC_IMPORT}}', $import).Replace('{{DIAGNOSTIC_PROPS}}', $props).Replace('{{TEST_DEFINITIONS}}', $define).Replace('{{ROOTS}}', $roots)
            [IO.File]::WriteAllText((Join-Path $consumer $file), $text.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
        }
        # Restore использует только локальный feed, без внешних источников и кеша.
        & $NuGet restore (Join-Path $consumer 'packages.config') -PackagesDirectory (Join-Path $consumer 'packages') -Source $Feed -NoCache -DirectDownload -NonInteractive | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'NuGet restore failed.' }
        foreach ($configuration in @('Debug', 'Release')) {
            $project = Join-Path $consumer 'Consumer.vcxproj'
            & $msbuild $project /nologo /v:minimal /t:Rebuild /p:Platform=x64 "/p:Configuration=$configuration" "/p:UniversalDevKitRuntime=$runtime" "/p:UniversalDevKitDiagnosticLinkage=$linkage" "/p:UniversalDevKitHelpersLinkage=$helperLinkage" "/bl:$consumer/$configuration.binlog" | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "NuGet consumer failed: $runtime/$linkage/$configuration" }
            $expectedOutput = if ($scenario -eq 'HelpersDynamic') { '' } else { 'NuGet consumer passed' }
            Invoke-TestApplication (Join-Path $consumer "out/$configuration/Consumer.exe") $expectedOutput
            $dlls = @(Get-ChildItem (Join-Path $consumer "out/$configuration") -Filter '*.dll')
            $expected = if ($linkage -eq 'Dynamic') { 1 } else { 0 }
            if ($dlls.Count -ne $expected) { throw 'Unexpected runtime DLL set.' }
        }
        # Несовместимый STL ABI должен отклоняться при реальной компиляции.
        $failure = & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Platform=x64 /p:Configuration=Release "/p:UniversalDevKitRuntime=$runtime" /p:UdkTestWrongAbi=true 2>&1
        if ($LASTEXITCODE -eq 0 -or ($failure -join "`n") -notmatch 'STL iterator ABI mismatch') { throw 'Incompatible STL ABI was not rejected.' }
        foreach ($negative in @(
            @{ Argument = '/p:Platform=Win32'; Message = 'only Windows x64' },
            @{ Argument = '/p:UniversalDevKitRuntime=Unknown'; Message = 'UniversalDevKitRuntime must be' },
            @{ Argument = '/p:UniversalDevKitHelpersLinkage=Shared'; Message = 'unsupported linkage' }
        )) {
            $failure = & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Configuration=Release /p:Platform=x64 $negative.Argument 2>&1
            if ($LASTEXITCODE -eq 0 -or ($failure -join "`n") -notmatch $negative.Message) { throw "Expected NuGet rejection: $($negative.Argument)" }
        }
        if ($runtime -eq 'Dynamic') {
            $failure = & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Platform=x64 /p:Configuration=Release /p:UniversalDevKitRuntime=Dynamic /p:UdkTestWrongCrt=true 2>&1
            if ($LASTEXITCODE -eq 0 -or ($failure -join "`n") -notmatch 'CRT mismatch') { throw 'Actual incompatible CRT was not rejected.' }
        }
        if ($scenario -ne 'HelpersDynamic') {
            $failure = & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Platform=x64 /p:Configuration=Release /p:UniversalDevKitHelpersLinkage=Dynamic 2>&1
            if ($LASTEXITCODE -eq 0 -or ($failure -join "`n") -notmatch 'Conflicting NuGet linkage') { throw 'Conflicting component linkage was not rejected.' }
        }
    }
}
# Проверяем разрешение точной зависимости из одного корневого пакета.
& $NuGet install UniversalDevKit.Diagnostic -Version $version -Source $Feed -OutputDirectory (Join-Path $run 'dependency-restore') -NoCache -DirectDownload -NonInteractive | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $run "dependency-restore/UniversalDevKit.Helpers.$version"))) { throw 'Diagnostic did not restore its Helpers dependency.' }
Write-Host "PASS: NuGet Windows x64 MD/MT Static/Dynamic Debug/Release. Workspace: $run"