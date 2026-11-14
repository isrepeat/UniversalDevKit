param(
    [string]$PackagePath,
    [switch]$All,
    [string]$RepositoryPath,
    [string]$Delivery,
    [string]$OutputDirectory,
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [string]$PackageSources,
    [hashtable]$Properties = @{},
    [string]$AndroidNdk,
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$Gradle,
    [string]$Ninja,
    [ValidateSet('Debug','Release')][string]$Configuration,
    [ValidateSet('arm64-v8a','x86_64')][string[]]$Abi,
    [ValidateRange(24,35)][Nullable[int]]$ApiLevel,
    [switch]$Plan
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'Sources/Windows/UdkCli/Tools/ReadManifest.ps1')
if (-not $RepositoryPath) {
    $RepositoryPath = $root
}
if ($All -and $PackagePath) {
    throw 'Choose -All or -PackagePath.'
}
if (-not $All -and -not $PackagePath) {
    throw 'Specify -PackagePath or -All.'
}
$arguments = @{
    RepositoryPath=$RepositoryPath
    OutputDirectory=$OutputDirectory
    CMake=$CMake
    NuGet=$NuGet
    PackageSources=$PackageSources
    Properties=$Properties
    AndroidNdk=$AndroidNdk
    AndroidSdk=$AndroidSdk
    JavaHome=$JavaHome
    Gradle=$Gradle
    Ninja=$Ninja
    Configuration=$Configuration
    Abi=$Abi
    ApiLevel=$ApiLevel
    Plan=$Plan
    ReleaseState=@{}
}
foreach ($key in @('Abi','Configuration','ApiLevel')) {
    if (-not $arguments[$key]) {
        $arguments.Remove($key)
    }
}
if (-not $All) {
    & (Join-Path $root 'Sources/Windows/UdkCli/Tools/PackageTools/Build.ps1') -PackagePath $PackagePath -Delivery $Delivery @arguments
    return
}
foreach ($file in Get-UdkPackageManifests (Join-Path $RepositoryPath 'Packages')) {
    $definition = Read-UdkManifest $file.FullName 'Package'
    $relative = $file.FullName.Substring([IO.Path]::GetFullPath($RepositoryPath).TrimEnd('\').Length+1)
    foreach ($name in $definition.deliveries.PSObject.Properties.Name) {
        if ($Delivery -and $Delivery -ne $name) {
            continue
        }
        & (Join-Path $root 'Sources/Windows/UdkCli/Tools/PackageTools/Build.ps1') -PackagePath $relative -Delivery $name @arguments
    }
}