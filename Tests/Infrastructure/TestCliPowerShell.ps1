param([Parameter(Mandatory)][string]$Executable)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('UdkCliHost.' + [Guid]::NewGuid().ToString('N'))
$originalModulePath = $env:PSModulePath
try {
    Copy-Item -LiteralPath (Join-Path $repository 'Tests/Fixtures/UdkCli') -Destination $temporary -Recurse
    $executablePath = (Resolve-Path -LiteralPath $Executable).Path
    Copy-Item -LiteralPath $executablePath -Destination (Join-Path $temporary 'udk.exe')
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $executablePath) 'UniversalDevKit.Diagnostic.Dynamic.dll') -Destination $temporary
    $modules = Join-Path $temporary 'Modules'
    $utility = Join-Path $modules 'Microsoft.PowerShell.Utility'
    [void][IO.Directory]::CreateDirectory($utility)
    [IO.File]::WriteAllText((Join-Path $utility 'Fake.psm1'), '# This test module deliberately does not export Get-FileHash.')
    [IO.File]::WriteAllText((Join-Path $utility 'Microsoft.PowerShell.Utility.psd1'), "@{ ModuleVersion='99.0.0'; RootModule='Fake.psm1'; FunctionsToExport=@(); CmdletsToExport=@() }")
    $env:PSModulePath = $modules + ';' + $originalModulePath
    & (Join-Path $temporary 'udk.exe') project check (Join-Path $temporary 'Components.xml')
    if ($LASTEXITCODE) { throw 'CLI module resolution failed with a conflicting inherited PSModulePath.' }
    $env:PSModulePath = $null
    & (Join-Path $temporary 'udk.exe') project check (Join-Path $temporary 'Components.xml')
    if ($LASTEXITCODE) { throw 'CLI module resolution failed with an empty PSModulePath.' }
    $env:PSModulePath = $originalModulePath
    Write-Host 'PASS: CLI uses native Windows PowerShell modules before inherited modules.'
} finally {
    $env:PSModulePath = $originalModulePath
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'UdkCliHost.*') { throw 'Unexpected CLI test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}