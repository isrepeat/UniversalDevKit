param(
    [string]$Feed,
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [ValidateSet('DiagnosticTest', 'HeleprsTest', 'Helpers', 'Diagnostic')]
    [string[]]$Components = @('DiagnosticTest', 'HeleprsTest', 'Helpers', 'Diagnostic')
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Tests/Infrastructure/BuildTools.ps1')
$msbuild = Get-TestMSBuild
$run = Join-Path $repository ('!artifacts/tests/pr-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($run)
$results = @()
function InvokeChecked([string[]]$Arguments, [string]$Log, [string]$ExpectedError = '') {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $msbuild @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    [IO.File]::WriteAllText($Log, $output, [Text.UTF8Encoding]::new($false))
    if ($ExpectedError) {
        if ($code -eq 0 -or $output -notmatch $ExpectedError) { throw "Expected rejection: $ExpectedError. See $Log; $output" }
    }
    elseif ($code -ne 0) { throw "MSBuild failed. See $Log; $output" }
}
try {
    if (-not $Feed) {
        $Feed = Join-Path $run 'feed'
        $packArguments = @{ LicenseFile = (Join-Path $repository 'LICENSE'); OutputDirectory = $Feed; NuGet = $NuGet; Components = $Components }
        if ($CMake) { $packArguments.CMake = $CMake }
        & (Join-Path $repository 'Packages/Build/NuGet/Build.ps1') @packArguments | Out-Host
    }
    $Feed = (Resolve-Path -LiteralPath $Feed).Path
    $version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version
    $fixture = Join-Path $repository 'Tests/Fixtures/Consumers/NuGet'
    foreach ($runtime in @('Dynamic', 'Static')) {
        foreach ($component in $Components) {
            $linkages = if ($component -eq 'Helpers') { @('Shared') } elseif ($component -eq 'Diagnostic') { @('Dynamic') } else { @('Static', 'Dynamic') }
            foreach ($linkage in $linkages) {
                $name = "$runtime-$component-$linkage"
                $consumer = Join-Path $run $name
                [void][IO.Directory]::CreateDirectory($consumer)
                $cache = Join-Path $consumer 'cache'
                Copy-Item -LiteralPath (Join-Path $fixture 'PackageReference.Main.cpp') -Destination (Join-Path $consumer 'Main.cpp')
                $definitions = if ($component -eq 'HeleprsTest') { 'UDK_TEST_HELEPRSTEST_ONLY=1;' } else { '' }
                if ($component -eq 'Helpers') { $definitions = 'UDK_TEST_HEADER_HELPERS=1;' }
                if ($component -eq 'Diagnostic') { $definitions = 'UDK_TEST_DIAGNOSTIC=1;' }
                if ($linkage -eq 'Dynamic') { $definitions += 'UDK_TEST_DYNAMIC=1;' }
                $text = [IO.File]::ReadAllText((Join-Path $fixture 'PackageReference.vcxproj.in')).Replace('{{VERSION}}', $version).Replace('{{COMPONENT}}', $component).Replace('{{RUNTIME}}', $runtime).Replace('{{LINKAGE}}', $linkage).Replace('{{DEFINITIONS}}', $definitions)
                $project = Join-Path $consumer 'Consumer.vcxproj'
                [IO.File]::WriteAllText($project, $text, [Text.UTF8Encoding]::new($false))
                $config = '<configuration><packageSources><clear/><add key="local" value="' + [Security.SecurityElement]::Escape($Feed) + '"/></packageSources></configuration>'
                $configPath = Join-Path $consumer 'NuGet.Config'
                [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
                $common = @($project, '/nologo', '/v:minimal', '/p:Platform=x64', "/p:RestorePackagesPath=$cache", "/p:RestoreConfigFile=$configPath", '/p:NuGetAudit=false')
                # Восстановление отдельно от сборки, только из локального feed и в пустой кеш.
                InvokeChecked ($common + @('/t:Restore', '/p:Configuration=Debug', '/p:RestoreNoCache=true')) (Join-Path $consumer 'restore.log')
                $assetsPath = Join-Path $consumer 'obj/project.assets.json'
                if (-not (Test-Path -LiteralPath $assetsPath)) { throw 'Native PackageReference restore did not produce project.assets.json. A supporting Visual Studio is required.' }
                $assets = Get-Content -LiteralPath $assetsPath -Raw | ConvertFrom-Json
                $expectedPackages = if ($component -eq 'DiagnosticTest') { @('DiagnosticTest', 'HeleprsTest') } elseif ($component -eq 'Diagnostic') { @('Diagnostic', 'Helpers') } else { @($component) }
                foreach ($package in $expectedPackages) {
                    if (-not $assets.libraries.PSObject.Properties["UniversalDevKit.$package/$version"]) { throw "Missing restored dependency: $package" }
                }
                if ($component -eq 'Diagnostic' -and $runtime -eq 'Static') {
                    InvokeChecked ($common + @('/t:Rebuild', '/p:Configuration=Debug')) (Join-Path $consumer 'unsupported-crt.log') 'Diagnostic requires Dynamic CRT'
                    $results += [pscustomobject]@{ Runtime = $runtime; Component = $component; Linkage = $linkage; Configuration = 'Debug'; Status = 'RejectedUnsupportedCrt' }
                    Write-Host "PASS: Diagnostic rejects static CRT before compilation"
                    continue
                }
                foreach ($configuration in @('Debug', 'Release')) {
                    InvokeChecked ($common + @('/t:Rebuild', "/p:Configuration=$configuration")) (Join-Path $consumer "$configuration.log")
                    $bin = Join-Path $consumer "out/$configuration"
                    $dlls = @(Get-ChildItem -LiteralPath $bin -Filter '*.dll')
                    $expectedCount = if ($linkage -eq 'Dynamic') { 1 } else { 0 }
                    if ($dlls.Count -ne $expectedCount) { throw "Unexpected runtime DLL count: $name/$configuration" }
                    if ($expectedCount -and $dlls[0].Name -notmatch "(?i)^universaldevkit_${component}_dynamicd?\.dll$") { throw 'Wrong runtime DLL delivered.' }
                    $clean = Join-Path $consumer "clean-$configuration"
                    [void][IO.Directory]::CreateDirectory($clean)
                    Copy-Item -LiteralPath (Join-Path $bin 'Consumer.exe') -Destination $clean
                    foreach ($dll in $dlls) { Copy-Item -LiteralPath $dll.FullName -Destination $clean }
                    $oldPath = $env:PATH
                    try {
                        $env:PATH = [Environment]::SystemDirectory
                        Invoke-TestApplication (Join-Path $clean 'Consumer.exe') 'PackageReference consumer passed'
                    }
                    finally { $env:PATH = $oldPath }
                    $results += [pscustomobject]@{ Runtime = $runtime; Component = $component; Linkage = $linkage; Configuration = $configuration; Status = 'Passed' }
                }
                if ($runtime -eq 'Dynamic' -and $component -ne 'Helpers') {
                    InvokeChecked ($common + @('/t:Rebuild', '/p:Configuration=Release', '/p:UdkTestWrongCrt=true')) (Join-Path $consumer 'wrong-crt.log') 'CRT mismatch'
                }
                if ($component -eq 'DiagnosticTest') {
                    InvokeChecked ($common + @('/t:Rebuild', '/p:Configuration=Release', '/p:UniversalDevKitComponents=HeleprsTest', '/p:UniversalDevKitHeleprsTestLinkage=Shared')) (Join-Path $consumer 'wrong-linkage.log') 'unsupported linkage'
                }
                if ($component -eq 'Helpers') {
                    InvokeChecked ($common + @('/t:Rebuild', '/p:Configuration=Release', '/p:UniversalDevKitHelpersLinkage=Dynamic')) (Join-Path $consumer 'wrong-linkage.log') 'unsupported linkage'
                }
                if ($component -eq 'Diagnostic') {
                    InvokeChecked ($common + @('/t:Rebuild', '/p:Configuration=Release', '/p:UniversalDevKitDiagnosticLinkage=Static')) (Join-Path $consumer 'wrong-linkage.log') 'unsupported linkage'
                }
                Write-Host "PASS: $name Debug/Release"
            }
        }
    }
}
catch {
    $results += [pscustomobject]@{ Runtime = $runtime; Component = $component; Linkage = $linkage; Configuration = ''; Status = 'Failed: ' + $_.Exception.Message }
    throw
}
finally {
    $results | Export-Csv -LiteralPath (Join-Path $run 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "PackageReference workspace: $run"
}