param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$SolutionInjectorPath,
    [switch]$Check,
    [switch]$Clean,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
foreach ($module in @('Contract', 'Linkage', 'MsBuild', 'Solution')) {
    . (Join-Path $PSScriptRoot "Private/$module.ps1")
}
$model = Read-ProjectToolsModel $ManifestPath
$versionPath = Join-Path $model.Root '.udk-version'
if ($Clean -and ($Check -or $PassThru)) {
    throw 'Clean cannot be combined with Check or PassThru.'
}
if ($Clean) {
    $projectPlan = New-ProjectToolsMsBuildPlan $model @()
    $projectPaths = @($projectPlan.Projects.Path)
    $solution = Resolve-ProjectToolsPath $model.Root $model.Settings.solution
    if (Test-Path -LiteralPath $solution -PathType Leaf) {
        $original = [IO.File]::ReadAllText($solution)
        $ownership = [regex]::Match($original, '(?m)^[ \t]*GlobalSection\(SolutionInjectorProjectOwnership\) = preSolution\r?\n([\s\S]*?)^[ \t]*EndGlobalSection')
        foreach ($entry in [regex]::Matches($ownership.Groups[1].Value, '(?m)^[ \t]*\{[^}]+\} = ProjectTools\|\{[^}]+\}\|([^\r\n]+)')) {
            $relativePath = $entry.Groups[1].Value.Replace('\', '/')
            if ($relativePath -match '\.(csproj|vcxproj|vcxitems)$') {
                $projectPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $solution) $relativePath))
                $projectPaths += (Get-ProjectToolsRelativePath $model.Root $projectPath).Replace('\', '/')
            }
        }
        $executable = & (Join-Path $PSScriptRoot 'Private/GetSolutionInjector.ps1') -LocalPath $SolutionInjectorPath
        $update = Get-ProjectToolsSolutionUpdate $model $projectPlan.Projects $executable -Clean
        if ([IO.File]::ReadAllText($solution) -cne $original) {
            throw "File changed during cleanup: $($model.Settings.solution)"
        }
    }
    $cleanupPaths = foreach ($projectPath in $projectPaths | Sort-Object -Unique) {
        $path = Resolve-ProjectToolsPath $model.Root $projectPath
        $path
        $path + '.filters'
        $path + '.user'
    }
    foreach ($path in $cleanupPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
            Write-Host ('Removed: ' + (Get-ProjectToolsRelativePath $model.Root $path))
        }
    }
    if ($update) {
        [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
        Write-Host ('Updated: ' + $update.RelativePath)
    }
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        Remove-Item -LiteralPath $versionPath -Force
    }
    Write-Host 'ProjectTools solution cleanup completed.'
    return
}
$udkPlan = if ($model.Integration -or $model.Profile -eq 'udk') {
    @(& (Join-Path $PSScriptRoot 'Profiles/Udk.ps1') -Model $model)
} else {
    @()
}
$plan = New-ProjectToolsMsBuildPlan $model $udkPlan
$executable = & (Join-Path $PSScriptRoot 'Private/GetSolutionInjector.ps1') -LocalPath $SolutionInjectorPath
$solutionUpdate = Get-ProjectToolsSolutionUpdate $model $plan.Projects $executable
if ($solutionUpdate) {
    $plan.Files.Add($solutionUpdate)
}
$updates = @($plan.Files | Where-Object {
    $null -eq $_.Original -or $_.Original.Replace("`r`n", "`n") -cne $_.Content.Replace("`r`n", "`n")
})
if ($PassThru) {
    return $updates
}
if ($Check -and $updates.Count) {
    throw ('Generated projects are out of date: ' + (($updates | ForEach-Object RelativePath) -join ', '))
}
if (-not $Check) {
    foreach ($update in $updates) {
        $current = if (Test-Path -LiteralPath $update.Path) {
            [IO.File]::ReadAllText($update.Path)
        } else {
            $null
        }
        if ($current -cne $update.Original) {
            throw "File changed during generation: $($update.RelativePath)"
        }
    }
    foreach ($update in $updates) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $update.Path))
        [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
        Write-Host ('Updated: ' + $update.RelativePath)
    }
}
if ($model.Integration -or $model.Profile -eq 'udk') {
    & (Join-Path $PSScriptRoot 'Private/UpdateProjectFilters.ps1') -RepositoryRoot $model.Root -Check:$Check
}
Write-Host 'ProjectTools generation completed.'