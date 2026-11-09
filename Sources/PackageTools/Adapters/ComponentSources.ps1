function Invoke-UdkComponentSourcesProject($Project, $Context) {
    # Публичные и внутренние заголовки выбираем только из реестра компонента.
    $root = $Context.RepositoryPath
    $componentPath = Resolve-UdkBuildPath $root $root $Project.component -Existing
    $component = Read-UdkBuildJson $componentPath
    $sourceRoot = Resolve-UdkBuildPath $root $root $Project.sourceRoot -Existing
    $includeRoot = Resolve-UdkBuildPath $root $root $Project.includeRoot -Existing
    $output = Reset-UdkArtifactDirectory -Root $Context.WorkDirectory -Path (Join-Path $Context.WorkDirectory 'output')
    $seen = @{}
    foreach ($file in @($component.headers) + @($component.sources)) {
        $source = Resolve-UdkBuildPath $sourceRoot $root $file -Existing
        $relative = $source.Substring($sourceRoot.Length + 1).Replace('\', '/')
        $public = $false
        if ($file -in $component.headers) {
            foreach ($pattern in $Project.publicHeaders) {
                # FileSystemName-подобное сопоставление: * не пересекает каталог.
                $regex = '^' + [regex]::Escape($pattern).Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
                if ($relative -cmatch $regex) { $public = $true; break }
            }
        }
        $destination = if ($public) {
            $headerPath = Resolve-UdkBuildPath $includeRoot $root $file -Existing
            Join-Path $Project.headerDestination $headerPath.Substring($includeRoot.Length + 1)
        } else { Join-Path $Project.sourceDestination $relative }
        $target = Resolve-UdkBuildPath $output $output $destination
        if ($seen.ContainsKey($target)) { throw "Duplicate source distribution path: $destination" }
        $seen[$target] = $true
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath $source -Destination $target
    }
    $manifest = Resolve-UdkBuildPath $output $output $Project.manifestDestination
    if ($seen.ContainsKey($manifest)) { throw 'Component manifest collides with source files.' }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $manifest))
    Copy-Item -LiteralPath $componentPath -Destination $manifest
    return @{ output = $output }
}