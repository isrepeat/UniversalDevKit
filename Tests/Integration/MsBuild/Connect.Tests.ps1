function Test-ComponentConnection {
    param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath, [ValidateSet('Shared', 'Static', 'Dynamic')][string]$Linkage)
    $consumer = $Workspace.Consumer
    $project = Join-Path $consumer 'App1/App1.vcxproj'
    $otherProject = Join-Path $consumer 'App2/App2.vcxproj'
    $otherHash = (Get-FileHash -LiteralPath $otherProject).Hash
    $connect = Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1'
    $arguments = @{
        SolutionPath = Join-Path $consumer 'Consumer.sln'
        ProjectPath = $project
        Components = @('HeleprsTest', 'DiagnosticTest')
        ComponentModes = @{ DiagnosticTest = $Linkage; HeleprsTest = $(if ($Linkage -eq 'Dynamic') { 'Static' } else { $Linkage }) }
    }
    if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
    & $connect @arguments | Out-Host
    $before = [IO.File]::ReadAllText($project)
    $solutionBefore = [IO.File]::ReadAllText($arguments.SolutionPath)
    & $connect @arguments | Out-Host
    [xml]$beforeXml = $before
    [xml]$xml = [IO.File]::ReadAllText($project)
    if ($xml.OuterXml -cne $beforeXml.OuterXml) { throw 'Repeated Apply changed consumer settings.' }
    # The tool may rewrite section order and solution folders; verify actual references.
    $solutionAfter = [IO.File]::ReadAllText($arguments.SolutionPath)
    $pattern = '^Project\(.*\).*\.(vcxproj|vcxitems)"|SharedItemsImports ='
    $linksBefore = @(($solutionBefore -split '\r?\n') | Where-Object { $_ -match $pattern } | Sort-Object)
    $linksAfter = @(($solutionAfter -split '\r?\n') | Where-Object { $_ -match $pattern } | Sort-Object)
    if (($linksBefore -join "`n") -cne ($linksAfter -join "`n")) { throw 'Repeated Apply changed solution references.' }
    if ($before -cne [IO.File]::ReadAllText($project) -or $solutionBefore -cne $solutionAfter) {
        Write-Host 'NOTE: repeated Apply rewrote formatting or solution folders; effective references are unchanged.'
    }
    $imports = @($xml.SelectNodes('//*[local-name()="Import"]') | Where-Object { $_.GetAttribute('Project') -match 'UniversalDevKit\.(HeleprsTest|DiagnosticTest)\.Shared\.vcxitems$' })
    if ($Linkage -eq 'Shared') {
        if ($imports.Count -ne 2 -or @($imports | ForEach-Object { $_.GetAttribute('Project') } | Sort-Object -Unique).Count -ne 2) {
            throw 'Expected exactly one Shared import per component.'
        }
    }
    else {
        if ($imports.Count) { throw 'Binary connection still imports Shared sources.' }
        $references = @($xml.SelectNodes('//*[local-name()="ProjectReference"]'))
        if ($references.Count -ne 2 -or @($references | ForEach-Object { $_.GetAttribute('Include') } | Sort-Object -Unique).Count -ne 2) {
            throw 'Expected exactly two unique library references.'
        }
    }
    if ((Get-FileHash -LiteralPath $otherProject).Hash -cne $otherHash) { throw 'Connect modified App2.' }
    foreach ($configuration in @('Debug', 'Release')) {
        Invoke-TestBuild $MSBuild $arguments.SolutionPath $configuration (Join-Path $Workspace.Root "logs/$Linkage")
        foreach ($app in @('App1', 'App2')) {
            Invoke-TestApplication (Join-Path $consumer "!artifacts/x64/$configuration/$app/bin/$app.exe") "$app passed"
        }
        if ($Linkage -eq 'Dynamic' -and -not (Test-Path -LiteralPath (Join-Path $consumer "!artifacts/x64/$configuration/App1/bin/UniversalDevKit.DiagnosticTest.Dynamic.dll"))) {
            throw 'DiagnosticTest runtime DLL was not delivered.'
        }
    }
}