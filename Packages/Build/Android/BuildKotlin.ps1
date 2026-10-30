param(
    [ValidateSet('AndroidCoreSdk', 'AndroidAppKit')][string]$Package = 'AndroidCoreSdk',
    [string]$OutputDirectory,
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$Gradle
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repositoryRoot 'Scripts/Android/ResolveToolchain.ps1')
$toolchain = Resolve-UdkAndroidToolchain -AndroidSdk $AndroidSdk -JavaHome $JavaHome -Gradle $Gradle -ForConsumer -WithoutNdk
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot '!artifacts/packages/maven' }
$feed = [IO.Path]::GetFullPath($OutputDirectory)
$savedEnvironment = @{}
foreach ($name in @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:JAVA_HOME = $toolchain.JavaHome
    $env:ANDROID_HOME = $toolchain.AndroidSdk
    $env:ANDROID_SDK_ROOT = $toolchain.AndroidSdk
    $packages = @('AndroidCoreSdk')
    if ($Package -eq 'AndroidAppKit') { $packages += 'AndroidAppKit' }
    foreach ($name in $packages) {
        $packageRoot = Join-Path $repositoryRoot "Packages/Android/$name"
        $delivery = Get-Content (Join-Path $packageRoot 'Delivery/Android/Delivery.json') -Raw | ConvertFrom-Json
        if ($delivery.adapter -ne 'kotlin-aar') { throw "Unsupported delivery adapter for ${name}." }
        $project = [IO.Path]::GetFullPath((Join-Path $packageRoot "Delivery/Android/$($delivery.project)"))
        $properties = ConvertFrom-StringData (Get-Content (Join-Path $project 'gradle.properties') -Raw)
        $version = $properties.packageVersion
        if ($properties.packageGroup -ne $delivery.groupId) { throw "Maven group mismatch for ${name}." }
        $artifact = $delivery.artifactId
        $destination = Join-Path $feed "$($delivery.groupId.Replace('.', '/'))/$artifact/$version"
        if ((Test-Path -LiteralPath $destination) -and $name -ne $Package) {
            foreach ($extension in @('aar', 'pom', 'module')) {
                if (-not (Test-Path -LiteralPath (Join-Path $destination "$artifact-$version.$extension"))) {
                    throw "Incomplete dependency publication: $destination"
                }
            }
            Write-Host "Using published dependency ${name} ${version}: $destination"
            continue
        }
        $buildRoot = Join-Path $feed "build-gradle/$name"
        & $toolchain.Gradle --project-dir $project --project-cache-dir "$buildRoot/cache" `
            "-PudkBuildRoot=$($buildRoot.Replace('\', '/'))" `
            "-PandroidPackagesFeedPath=$($feed.Replace('\', '/'))" `
            ":${artifact}:publishReleasePublicationToAndroidPackagesFeedRepository" --console=plain
        if ($LASTEXITCODE -ne 0) { throw "Gradle failed for $name with exit code $LASTEXITCODE." }
        foreach ($extension in @('aar', 'pom', 'module')) {
            if (-not (Test-Path -LiteralPath (Join-Path $destination "$artifact-$version.$extension"))) {
                throw "Published $extension was not found for $name $version."
            }
        }
        Write-Host "Published ${name} ${version}: $destination"
    }
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}