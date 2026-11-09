function Invoke-UdkNuGetRestoreProject($Project, $Context) {
    $packages = Join-Path $Context.WorkDirectory 'packages'
    $package = Join-Path $packages ($Project.id + '.' + $Project.version)
    $arguments = @('install', $Project.id, '-Version', $Project.version, '-OutputDirectory', $packages, '-NonInteractive', '-ForceEnglishOutput', '-DirectDownload', '-NoCache', '-PackageSaveMode', 'nuspec')
    $source = if ($Context.PackageSources) { $Context.PackageSources } else { $Project.sources -join ';' }
    if ($source) { $arguments += @('-Source', $source) }
    $config = Join-Path $Context.RepositoryPath 'NuGet.Config'
    if (Test-Path -LiteralPath $config -PathType Leaf) { $arguments += @('-ConfigFile', $config) }
    Invoke-UdkBuildTool $Context.NuGet $arguments
    if (-not (Test-Path -LiteralPath $package -PathType Container)) { throw "Package restore did not provide $package" }
    return @{ package = $package }
}