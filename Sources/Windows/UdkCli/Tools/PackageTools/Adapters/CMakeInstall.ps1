function Invoke-UdkCMakeInstallProject($Project, $Context) {
    $cmake = Resolve-UdkCMake $Context.CMake
    $isInstall = $Project.adapter -eq 'cmake-install'
    $install = if ($isInstall) {
        Reset-UdkArtifactDirectory -Root $Context.WorkDirectory -Path (Join-Path $Context.WorkDirectory 'install')
    } else {
        $null
    }
    $roots = @{}
    if ($isInstall) {
        $roots.install = $install
    }
    $variables = @{}
    foreach ($variable in $Project.variables.PSObject.Properties) {
        $variables[$variable.Name] = $variable.Value
    }

    # The dependency setup script returns named properties.
    if ($Project.preparation) {
        $preparation = $Project.preparation
        $prepared = @{}
        $missing = @($preparation.properties | Where-Object {
            -not $Context.Properties.ContainsKey($_)
        })
        if ($missing.Count) {
            $parameters = @{
                RepositoryPath = $Context.RepositoryPath
                WorkDirectory = Join-Path $Context.WorkDirectory 'dependencies'
                Configurations = $Project.configurations
                Generator = $Project.generator
            }
            foreach ($parameter in $preparation.parameters.PSObject.Properties) {
                if ($parameters.ContainsKey($parameter.Name)) {
                    throw "Reserved preparation parameter: $($parameter.Name)"
                }
                $parameters[$parameter.Name] = $parameter.Value
            }
            $prepared = & (Join-Path $Context.RepositoryPath $preparation.script) @parameters
        }
        foreach ($property in $preparation.properties) {
            $value = if ($Context.Properties.ContainsKey($property)) {
                $Context.Properties[$property]
            } else {
                $prepared[$property]
            }
            if (-not $value -or -not (Test-Path -LiteralPath $value -PathType Container)) {
                throw "Preparation did not provide a directory: $property"
            }
            $roots[$property] = (Resolve-Path -LiteralPath $value).Path
            $variables[$property] = $roots[$property]
        }
    }
    $build = Join-Path $Context.WorkDirectory 'build'
    $roots.build = $build
    $arguments = @('-S', (Join-Path $Context.RepositoryPath $Project.sourceDirectory), '-B', $build, '-G', $Project.generator, '-A', $Project.architecture)
    if ($isInstall) {
        $arguments += "-DCMAKE_INSTALL_PREFIX=$install"
    }
    foreach ($name in ($variables.Keys | Sort-Object)) {
        $arguments += "-D$name=$($variables[$name])"
    }
    Invoke-UdkBuildTool $cmake $arguments
    foreach ($configuration in $Project.configurations) {
        Invoke-UdkBuildTool $cmake @('--build', $build, '--config', $configuration, '--parallel', [string]$Project.parallel)
        if ($isInstall) {
            Invoke-UdkBuildTool $cmake @('--install', $build, '--config', $configuration)
        }
    }
    return $roots
}