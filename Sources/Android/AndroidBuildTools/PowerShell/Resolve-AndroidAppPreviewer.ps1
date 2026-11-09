[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PackagesRoot,
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [ValidatePattern('^\d+(\.\d+){2,3}$')] [string]$Version
)

$ErrorActionPreference = 'Stop'
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
$packageName = 'UniversalDevKit.AndroidAppPreviewer'
$packagesDirectory = [IO.Path]::GetFullPath($PackagesRoot)
$previewer = Join-Path $packagesDirectory "$packageName.$Version\tools\win-x64\AndroidAppPreviewer.exe"
if (-not (Test-Path -LiteralPath $previewer -PathType Leaf)) {
    $nuget = (Get-Command nuget.exe -ErrorAction Stop).Source
    & $nuget install $packageName -Version $Version -Source $Source -OutputDirectory $packagesDirectory -NonInteractive -ForceEnglishOutput -Verbosity quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "UDK previewer $Version restore failed." }
}
if (-not (Test-Path -LiteralPath $previewer -PathType Leaf)) {
    throw "UDK previewer package $Version did not provide tools\win-x64\AndroidAppPreviewer.exe."
}
return $previewer