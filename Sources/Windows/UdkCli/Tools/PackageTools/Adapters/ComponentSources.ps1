function Invoke-UdkComponentSourcesProject($Project, $Context) {
    # Resolve the component's file list.
    $root = $Context.RepositoryPath
    if ($Project.adapter -eq 'udk-component-sources') {
        . (Join-Path $PSScriptRoot '../../ProjectTools/Private/Contract.ps1')
        $model = Read-ProjectToolsModel (Join-Path $root 'Components.json')
        $components = @($model.Components.Values | Where-Object name -eq $Project.component)
        if ($components.Count -ne 1 -or $components[0].platformSources) {
            throw "Expected one native component without platformSources: $($Project.component)"
        }
        $component = $components[0]
    } else {
        $componentPath = Resolve-UdkBuildPath $root $root $Project.component -Existing
        $component = Read-UdkBuildJson $componentPath
    }

    # Stage sources and headers in the package layout.
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
                # Match paths like FileSystemName: * does not match across directory separators.
                $regex = '^' + [regex]::Escape($pattern).Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
                if ($relative -cmatch $regex) {
                    $public = $true
                    break
                }
            }
        }
        $destination = if ($public) {
            $headerPath = Resolve-UdkBuildPath $includeRoot $root $file -Existing
            Join-Path $Project.headerDestination $headerPath.Substring($includeRoot.Length + 1)
        } else {
            Join-Path $Project.sourceDestination $relative
        }
        $target = Resolve-UdkBuildPath $output $output $destination
        if ($seen.ContainsKey($target)) {
            throw "Duplicate source distribution path: $destination"
        }
        $seen[$target] = $true
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath $source -Destination $target
    }

    # Write the file manifest for package consumers.
    $manifest = Resolve-UdkBuildPath $output $output $Project.manifestDestination
    if ($seen.ContainsKey($manifest)) {
        throw 'Component manifest collides with source files.'
    }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $manifest))
    if ($Project.adapter -eq 'udk-component-sources') {
        $manifestJson = [ordered]@{ headers = @($component.headers); sources = @($component.sources) } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($manifest, $manifestJson, [Text.UTF8Encoding]::new($false))
    } else {
        Copy-Item -LiteralPath $componentPath -Destination $manifest
    }
    return @{
        output = $output
    }
}