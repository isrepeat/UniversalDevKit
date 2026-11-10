function Invoke-UdkNuGetDelivery($Plan, [string]$Stage, [string]$OutputDirectory, [string]$NuGet) {
    $spec = [IO.File]::ReadAllText($Plan.Nuspec).Replace('{{VERSION}}', $Plan.Version).Replace('{{COMPONENT}}', $Plan.Package.name).Replace('{{PACKAGE_ID}}', $Plan.Delivery.id)
    $dependencies = @($Plan.Delivery.dependencies | ForEach-Object {
        '<dependency id="' + [Security.SecurityElement]::Escape($_.id) + '" version="[' + [Security.SecurityElement]::Escape($_.version) + ']" />'
    }) -join ''
    $spec = $spec.Replace('{{DEPENDENCIES}}', $dependencies)
    $path = Join-Path $Stage 'package.nuspec'
    [IO.File]::WriteAllText($path, $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
    $arguments = @('pack', $path, '-BasePath', $Stage, '-OutputDirectory', $OutputDirectory, '-NonInteractive', '-ForceEnglishOutput')
    if ($Plan.Delivery.noDefaultExcludes) {
        $arguments += '-NoDefaultExcludes'
    }
    if ($Plan.Delivery.noWarn) {
        $arguments += @('-Properties', ('NoWarn=' + ($Plan.Delivery.noWarn -join ';')))
    }
    Invoke-UdkBuildTool $NuGet $arguments
    $result = Join-Path $OutputDirectory ($Plan.Delivery.id + '.' + $Plan.Version + '.nupkg')
    if (-not (Test-Path -LiteralPath $result -PathType Leaf)) {
        throw "NuGet did not produce the expected package: $result"
    }
    return $result
}