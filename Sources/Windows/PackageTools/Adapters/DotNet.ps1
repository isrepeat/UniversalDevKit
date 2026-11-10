function Invoke-UdkDotNetProject($Project, $Context) {
    $output = Reset-UdkArtifactDirectory -Root $Context.WorkDirectory -Path (Join-Path $Context.WorkDirectory 'output')
    $arguments = @($Project.operation, (Join-Path $Context.RepositoryPath $Project.project), '-c', $Project.configuration, '--output', $output, '--nologo')
    if ($Project.runtime) {
        $arguments += @('--runtime', $Project.runtime)
    }
    if ($null -ne $Project.selfContained) {
        $arguments += @('--self-contained', $Project.selfContained.ToString().ToLowerInvariant())
    }
    Invoke-UdkBuildTool 'dotnet' $arguments
    return @{
        output = $output
    }
}