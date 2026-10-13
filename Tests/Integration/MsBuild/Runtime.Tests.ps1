param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)

$arguments = @{
    SolutionPath = Join-Path $Workspace.Consumer 'Consumer.sln'
    ProjectPath = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
    Components = @('Diagnostic', 'Helpers')
    ComponentModes = @{ Diagnostic = 'Dynamic'; Helpers = 'Static' }
}
if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
& (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') @arguments | Out-Host

foreach ($configuration in @('Debug', 'Release')) {
    foreach ($runtime in @('Dynamic', 'Static')) {
        # Общий параметр сборки передаётся всем библиотечным ссылкам.
        $runtimeLibrary = if ($configuration -eq 'Debug') { 'MultiThreadedDebug' } else { 'MultiThreaded' }
        if ($runtime -eq 'Dynamic') { $runtimeLibrary += 'DLL' }
        & $MSBuild $arguments.ProjectPath /m /nologo /v:minimal "/p:Configuration=$configuration" /p:Platform=x64 "/p:TestRuntimeLibrary=$runtimeLibrary" "/p:UniversalDevKitRuntime=$runtime" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Runtime build failed: $configuration/$runtime" }
        Invoke-TestApplication (Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/App1/bin/App1.exe") 'App1 passed'
    }
}

# Оба варианта должны сохраняться одновременно, а не заменять друг друга.
$artifacts = Join-Path $Workspace.Library '!artifacts/Windows-x64/msbuild'
foreach ($runtimeDirectory in @('md', 'mt')) {
    $binaries = @(Get-ChildItem $artifacts -Recurse -Filter 'UniversalDevKit.Diagnostic.Dynamic.dll' |
        Where-Object { $_.FullName -match "[\\/]$runtimeDirectory[\\/]" })
    if ($binaries.Count -ne 2) { throw "Expected Debug/Release DLLs in $runtimeDirectory" }
}

# Явно противоречащий выбор отклоняется до компиляции consumer.
$output = & $MSBuild $arguments.ProjectPath /nologo /v:minimal /p:Configuration=Release /p:Platform=x64 /p:TestRuntimeLibrary=MultiThreaded /p:UniversalDevKitRuntime=Dynamic 2>&1
if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'conflicts with consumer RuntimeLibrary') {
    throw 'Expected explicit CRT conflict rejection'
}

$output = & $MSBuild $arguments.ProjectPath /nologo /v:minimal /p:Configuration=Release /p:Platform=x64 /p:TestRuntimeLibrary=MultiThreadedDebugDLL 2>&1
if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'debug/release variant does not match') {
    throw 'Expected debug CRT conflict rejection'
}