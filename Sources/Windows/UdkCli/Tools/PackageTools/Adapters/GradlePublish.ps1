function Invoke-UdkGradlePublishProject($Project, $Context) {
    $repository = $Context.RepositoryPath
    . (Join-Path $repository $Project.toolchain)
    $toolchain = Resolve-UdkAndroidToolchain -AndroidSdk $Context.Options.AndroidSdk -JavaHome $Context.Options.JavaHome -Gradle $Context.Options.Gradle -ForConsumer -WithoutNdk
    $projectRoot = Resolve-UdkBuildPath $repository $repository $Project.projectDirectory -Existing
    $publication = Reset-UdkArtifactDirectory -Root $Context.WorkDirectory -Path (Join-Path $Context.WorkDirectory 'repository')
    # Keep existing Maven versions when Gradle publishes to a separate directory.
    $coordinatePath = $Context.Delivery.groupId.Replace('.','/') + '/' + $Context.Delivery.artifactId
    $existing = Join-Path $Context.OutputDirectory $coordinatePath
    if (Test-Path -LiteralPath $existing -PathType Container) {
        $target = Join-Path $publication $coordinatePath
        [void][IO.Directory]::CreateDirectory($target)
        Get-ChildItem -LiteralPath $existing -Force | Copy-Item -Destination $target -Recurse -Force
    }
    $arguments = @('--project-dir', $projectRoot, '--project-cache-dir', (Join-Path $Context.WorkDirectory 'cache'), "-PudkBuildRoot=$($Context.WorkDirectory.Replace('\','/'))/build", "-PandroidPackagesFeedPath=$($Context.OutputDirectory.Replace('\','/'))", "-PudkPublicationFeedPath=$($publication.Replace('\','/'))", '--console=plain')
    $arguments += "-PpackageVersion=$($Context.Version)"
    $arguments += $Project.tasks
    if ($Project.refreshDependencies) {
        $arguments += '--refresh-dependencies'
    }
    $saved = @{}
    try {
        foreach ($name in @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $env:JAVA_HOME = $toolchain.JavaHome
        $env:ANDROID_HOME = $toolchain.AndroidSdk
        $env:ANDROID_SDK_ROOT = $toolchain.AndroidSdk
        Invoke-UdkBuildTool $toolchain.Gradle $arguments
        $delivery = $Context.Delivery
        $coordinate = Join-Path $publication ($delivery.groupId.Replace('.','/') + '/' + $delivery.artifactId + '/' + $Context.Version)
        foreach ($extension in @('aar', 'pom', 'module')) {
            $file = Join-Path $coordinate ($delivery.artifactId + '-' + $Context.Version + '.' + $extension)
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Missing Gradle publication: $file"
            }
        }
        return @{
            output = $publication
        }
    } finally {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
        }
    }
}