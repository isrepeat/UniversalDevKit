param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)

$arguments = @{
    SolutionPath = Join-Path $Workspace.Consumer 'Consumer.sln'
    ProjectPath = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
    Components = @('Diagnostic', 'Helpers')
    ComponentModes = @{ Diagnostic = 'Dynamic'; Helpers = 'Static' }
}
if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
& (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') @arguments | Out-Host

# Consumers in one solution build common projects with independent global properties.
$arguments.ProjectPath = Join-Path $Workspace.Consumer 'App2/App2.vcxproj'
& (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') @arguments | Out-Host
foreach ($configuration in @('Debug', 'Release')) {
    & $MSBuild $arguments.SolutionPath /m /nologo /v:minimal /p:TestMixedRuntime=true "/p:Configuration=$configuration" /p:Platform=x64 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Mixed consumer CRT build failed: $configuration" }
    foreach ($app in @('App1', 'App2')) {
        $outDir = Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/$app/bin"
        Invoke-TestApplication (Join-Path $outDir "$app.exe") "$app passed"
        $runtimeDirectory = if ($app -eq 'App1') { 'md' } else { 'mt' }
        $expected = @(Get-ChildItem (Join-Path $Workspace.Library '!artifacts/Windows-x64/msbuild') -Recurse -Filter 'UniversalDevKit.Diagnostic.Dynamic.dll' |
            Where-Object { $_.FullName -match "[\\/]$runtimeDirectory[\\/]Diagnostic.Dynamic[\\/]$configuration[\\/]bin[\\/]" })
        if ($expected.Count -ne 1) { throw "Missing unique DLL for $app/$configuration/$runtimeDirectory" }
        $actual = Join-Path $outDir 'UniversalDevKit.Diagnostic.Dynamic.dll'
        if ((Get-FileHash $actual).Hash -ne (Get-FileHash $expected[0].FullName).Hash) {
            throw "Wrong CRT DLL copied to $app"
        }
    }
}

$arguments.ProjectPath = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
foreach ($configuration in @('Debug', 'Release')) {
    foreach ($runtime in @('Dynamic', 'Static')) {
        # An explicit setting is allowed when it matches the consumer CRT.
        $runtimeLibrary = if ($configuration -eq 'Debug') { 'MultiThreadedDebug' } else { 'MultiThreaded' }
        if ($runtime -eq 'Dynamic') { $runtimeLibrary += 'DLL' }
        & $MSBuild $arguments.ProjectPath /m /nologo /v:minimal "/p:Configuration=$configuration" /p:Platform=x64 "/p:TestRuntimeLibrary=$runtimeLibrary" "/p:UniversalDevKitRuntime=$runtime" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Runtime build failed: $configuration/$runtime" }
        Invoke-TestApplication (Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/App1/bin/App1.exe") 'App1 passed'
    }
}

# Both variants must coexist without overwriting each other.
$artifacts = Join-Path $Workspace.Library '!artifacts/Windows-x64/msbuild'
foreach ($runtimeDirectory in @('md', 'mt')) {
    $binaries = @(Get-ChildItem $artifacts -Recurse -Filter 'UniversalDevKit.Diagnostic.Dynamic.dll' |
        Where-Object { $_.FullName -match "[\\/]$runtimeDirectory[\\/]" })
    if ($binaries.Count -ne 2) { throw "Expected Debug/Release DLLs in $runtimeDirectory" }
}

# Reject conflicting settings before compiling the consumer.
$output = & $MSBuild $arguments.ProjectPath /nologo /v:minimal /p:Configuration=Release /p:Platform=x64 /p:TestRuntimeLibrary=MultiThreaded /p:UniversalDevKitRuntime=Dynamic 2>&1
if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'conflicts with consumer RuntimeLibrary') {
    throw 'Expected explicit CRT conflict rejection'
}

$output = & $MSBuild $arguments.ProjectPath /nologo /v:minimal /p:Configuration=Release /p:Platform=x64 /p:TestRuntimeLibrary=MultiThreadedDebugDLL 2>&1
if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'debug/release variant does not match') {
    throw 'Expected debug CRT conflict rejection'
}