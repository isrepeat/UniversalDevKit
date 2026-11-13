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

function Invoke-UdkComponentDotNetProject($Project, $Context) {
    $projectTools = Join-Path $PSScriptRoot '../../ProjectTools/Private'
    . (Join-Path $projectTools 'Contract.ps1')
    . (Join-Path $projectTools 'MsBuild.ps1')

    $model = Read-ProjectToolsModel (Join-Path $Context.RepositoryPath 'Components.json')
    $matches = @(@($model.ManagedLibraries.Values) + @($model.Applications.Values) | Where-Object {
        $_.language -eq 'csharp' -and $_.name -eq $Project.component -and
        (-not $Project.projectId -or $_.projectId -eq $Project.projectId)
    })
    if ($matches.Count -eq 0) {
        throw "No C# project matches component '$($Project.component)' and projectId '$($Project.projectId)'."
    }
    if ($matches.Count -gt 1) {
        throw "Component '$($Project.component)' has several C# projects. Specify projectId."
    }

    $path = Get-ProjectToolsDotNetLocation $model $matches[0]
    $absolute = Resolve-UdkBuildPath $model.Root $model.Root $path
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "Generated project is missing: $path. Run ProjectTools generation for Components.json."
    }
    $configuration = if ($Project.configuration) { $Project.configuration } else { 'Release' }
    Invoke-UdkDotNetProject @{
        project = $path
        operation = 'build'
        configuration = $configuration
    } $Context
}