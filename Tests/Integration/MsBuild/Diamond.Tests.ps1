param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$fixture = Join-Path $repositoryPath 'Tests/Fixtures/Libraries/Diamond'
foreach ($variant in @('Shared', 'Static', 'Dynamic', 'PrivateStatic')) {
    $case = New-TestWorkspace $repositoryPath $Workspace.Mode $Revision -Name "Diamond-$variant"
    Write-Host "Diamond $variant workspace: $($case.Root)"
    # Install the registry and sources only in the UDK copy; preserve the consumer project template.
    foreach ($directory in @('Includes', 'Sources', 'Projects')) {
        Copy-Item -LiteralPath (Join-Path $fixture $directory) -Destination $case.Library -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $fixture 'Components.json') -Destination $case.Library -Force
    Copy-Item -LiteralPath (Join-Path $fixture 'UniversalDevKit.sln') -Destination $case.Library -Force
    if ($variant -eq 'PrivateStatic') {
        foreach ($name in @('A', 'C')) {
            Copy-Item -LiteralPath (Join-Path $fixture "PrivateStatic/$name.json") -Destination (Join-Path $case.Library "Projects/Components/$name.json") -Force
        }
    }
    foreach ($app in @('App1', 'App2')) {
        Copy-Item -LiteralPath (Join-Path $fixture "Consumer/$app/Main.cpp") -Destination (Join-Path $case.Consumer "$app/Main.cpp") -Force
    }
    & (Join-Path $case.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1') | Out-Host
    $mode = if ($variant -eq 'PrivateStatic') { 'Dynamic' } else { $variant }
    $connect = Join-Path $case.Library 'Scripts/PowerShell/Connect.ps1'
    $solution = Join-Path $case.Consumer 'Consumer.sln'
    foreach ($app in @('App1', 'App2')) {
        $component = if ($app -eq 'App1') { 'A' } else { 'C' }
        $arguments = @{
            SolutionPath = $solution
            ProjectPath = Join-Path $case.Consumer "$app/$app.vcxproj"
            Components = @($component)
            ComponentModes = @{ $component = $mode }
        }
        if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
        & $connect @arguments | Out-Host
    }
    [xml]$xml = [IO.File]::ReadAllText((Join-Path $case.Consumer 'App1/App1.vcxproj'))
    $references = @($xml.SelectNodes('//*[local-name()="ProjectReference"]'))
    if ($variant -eq 'Shared') {
        $imports = @($xml.SelectNodes('//*[local-name()="Import"]') | Where-Object { $_.Project -match 'UniversalDevKit\.[ABCD]\.Shared\.vcxitems$' })
        if ($imports.Count -ne 4 -or @($imports.Project | Sort-Object -Unique).Count -ne 4) { throw 'Diamond Shared imports are duplicated or missing.' }
    }
    if ($variant -in @('Dynamic', 'PrivateStatic')) {
        $b = @($references | Where-Object { $_.Include -match 'UniversalDevKit\.B\.' })
        $definitions = @($xml.SelectNodes('//*[local-name()="PreprocessorDefinitions"]') | ForEach-Object InnerText) -join ';'
        if ($b.Count -ne 1) { throw 'Missing or duplicate B reference.' }
        if ($variant -eq 'PrivateStatic') {
            if ($b[0].LinkLibraryDependencies -ne 'false' -or $definitions -match 'UNIVERSALDEVKIT_B_DYNAMIC') { throw 'Private static B leaked into consumer linkage/imports.' }
        }
        elseif ($b[0].LinkLibraryDependencies -ne 'true' -or $definitions -notmatch 'UNIVERSALDEVKIT_B_DYNAMIC') { throw 'Public dynamic B requirements are missing.' }
    }
    foreach ($configuration in @('Debug', 'Release')) {
        Invoke-TestBuild $MSBuild $solution $configuration (Join-Path $case.Root 'logs')
        foreach ($app in @('App1', 'App2')) {
            $bin = Join-Path $case.Consumer "!artifacts/x64/$configuration/$app/bin"
            $expected = if ($mode -ne 'Dynamic') { @() } elseif ($variant -eq 'PrivateStatic') { if ($app -eq 'App1') { @('A', 'C') } else { @('C') } } elseif ($app -eq 'App1') { @('A', 'B', 'C', 'D') } else { @('C', 'D') }
            $actual = @(Get-ChildItem -LiteralPath $bin -Filter '*.dll' | ForEach-Object Name | Sort-Object)
            $dlls = @($expected | ForEach-Object { "UniversalDevKit.$_.Dynamic.dll" } | Sort-Object)
            if (($actual -join ';') -cne ($dlls -join ';')) { throw "Incorrect runtime set: $variant/$app ($actual)" }
            # Run only the EXE and delivered DLLs in a separate directory without library search paths.
            $clean = Join-Path $case.Root "run/$configuration/$app"
            [void][IO.Directory]::CreateDirectory($clean)
            Copy-Item -LiteralPath (Join-Path $bin "$app.exe") -Destination $clean
            foreach ($dll in $dlls) { Copy-Item -LiteralPath (Join-Path $bin $dll) -Destination $clean }
            $oldPath = $env:PATH
            try {
                $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
                Invoke-TestApplication (Join-Path $clean "$app.exe") "$app passed"
            }
            finally { $env:PATH = $oldPath }
        }
    }
    if ($variant -eq 'Dynamic') {
        $project = Join-Path $case.Consumer 'App1/App1.vcxproj'
        $beforeProject = (Get-FileHash -LiteralPath $project).Hash
        $beforeSolution = (Get-FileHash -LiteralPath $solution).Hash
        $rejected = $false
        try {
            & $connect -SolutionPath $solution -ProjectPath $project -Components A,C -ComponentModes @{ A = 'Dynamic'; C = 'Static' } -SolutionInjectorPath $SolutionInjectorPath | Out-Host
        }
        catch {
            if ($_.Exception.Message -notmatch 'Conflicting linkage') { throw }
            $rejected = $true
        }
        if (-not $rejected -or (Get-FileHash -LiteralPath $project).Hash -ne $beforeProject -or (Get-FileHash -LiteralPath $solution).Hash -ne $beforeSolution) { throw 'Conflict was not rejected without file changes.' }
        & $connect -SolutionPath $solution -ProjectPath $project -Components A -Disconnect -SolutionInjectorPath $SolutionInjectorPath | Out-Host
        Invoke-TestBuild $MSBuild (Join-Path $case.Consumer 'App2/App2.vcxproj') Release (Join-Path $case.Root 'logs/AfterDisconnect')
        Invoke-TestApplication (Join-Path $case.Consumer '!artifacts/x64/Release/App2/bin/App2.exe') 'App2 passed'
    }
    Write-Host "PASS: Diamond $variant"
    if ($CleanOnSuccess) { Remove-TestWorkspace $repositoryPath $case }
}