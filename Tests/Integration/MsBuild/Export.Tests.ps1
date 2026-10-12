param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)

$fixture = Join-Path $repositoryPath 'Tests/Fixtures/Libraries/Export'
foreach ($directory in @('Includes', 'Sources', 'Projects')) {
    Copy-Item -LiteralPath (Join-Path $fixture $directory) -Destination $Workspace.Library -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $fixture 'Components.json') -Destination $Workspace.Library -Force
Copy-Item -LiteralPath (Join-Path $fixture 'Main.cpp') -Destination (Join-Path $Workspace.Consumer 'App1/Main.cpp') -Force
& (Join-Path $Workspace.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1') | Out-Host

# Проверяем согласованность с единственным источником версии выпуска.
$version = Get-Content -LiteralPath (Join-Path $Workspace.Library 'Version.json') -Raw | ConvertFrom-Json
$versionHeader = [IO.File]::ReadAllText((Join-Path $Workspace.Library 'Includes/UniversalDevKit/Version.h'))
[xml]$versionProps = [IO.File]::ReadAllText((Join-Path $Workspace.Library 'Projects/MsBuild/UniversalDevKit.Version.props'))
if ($versionHeader -notmatch [regex]::Escape('"' + $version.version + '"') -or $versionProps.Project.PropertyGroup.UniversalDevKitVersion -ne $version.version -or $versionProps.Project.PropertyGroup.UniversalDevKitAbiVersion -ne [string]$version.abiVersion) {
    throw 'Generated version metadata is inconsistent.'
}

# ProjectOnly здесь не нужен: consumer связывается с готовым проектом, независимо от дерева solution.
foreach ($mode in @('Static', 'Dynamic')) {
    $project = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
    # Используем модуль и режим решения; сгенерированный проект присутствует в UDK solution.
    & (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') -SolutionPath (Join-Path $Workspace.Consumer 'Consumer.sln') -ProjectPath $project -Components ExportProbe -ComponentModes @{ ExportProbe = $mode } -SolutionInjectorPath $SolutionInjectorPath | Out-Host
    foreach ($configuration in @('Debug', 'Release')) {
        Invoke-TestBuild $MSBuild $project $configuration (Join-Path $Workspace.Root "logs/$mode")
        $bin = Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/App1/bin"
        Invoke-TestApplication (Join-Path $bin 'App1.exe') 'App1 passed'
        if ($mode -eq 'Dynamic') {
            $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
            $tools = @(& $vswhere -latest -products '*' -find 'VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe')
            if (-not $tools.Count) { throw 'dumpbin is required to inspect exports.' }
            $exports = @(& $tools[0] /exports (Join-Path $bin 'UniversalDevKit.ExportProbe.Dynamic.dll')) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $exports -notmatch '\bUdkPublicProbe\b' -or $exports -match '\bUdkInternalProbe\b') { throw 'Unexpected DLL export table.' }
        }
    }
}