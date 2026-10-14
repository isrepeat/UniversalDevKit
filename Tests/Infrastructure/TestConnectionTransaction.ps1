param()
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Module.Udk.Connection.psm1') -Force
$module = Get-Module Module.Udk.Connection
$workspace = Join-Path $repository ('!artifacts/tests/transaction-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
$project = Join-Path $workspace 'Consumer.vcxproj'
$solution = Join-Path $workspace 'Consumer.sln'
$projectBytes = [byte[]]@(239, 187, 191, 65, 13, 10, 66)
$solutionBytes = [byte[]]@(67, 10, 68)
[IO.File]::WriteAllBytes($project, $projectBytes)
[IO.File]::WriteAllBytes($solution, $solutionBytes)
$projectHash = (Get-FileHash $project).Hash
$solutionHash = (Get-FileHash $solution).Hash

& $module {
    param($project, $solution, $projectHash, $solutionHash)
    foreach ($stage in @('SolutionWrite', 'ProjectWrite', 'Cleanup')) {
        $failed = $false
        try {
            Invoke-UdkConnectionTransaction $project $solution {
                [IO.File]::WriteAllText($solution, 'changed solution')
                if ($stage -eq 'SolutionWrite') { throw 'Injected failure' }
                [IO.File]::WriteAllText($project, 'changed project')
                if ($stage -eq 'Cleanup') { [IO.File]::Delete($project) }
                throw 'Injected failure'
            }
        }
        catch {
            if ($_.Exception.Message -notmatch 'Injected failure') { throw }
            $failed = $true
        }
        if (-not $failed -or (Get-FileHash $project).Hash -cne $projectHash -or (Get-FileHash $solution).Hash -cne $solutionHash) { throw "Rollback assertion failed: $stage" }
        if (Test-Path ($project + '.UniversalDevKit.transaction')) { throw 'Completed rollback left a snapshot.' }
    }
    # Имитируем аварийное прерывание: сохраняем снимок и намеренно прерываем откат.
    $script:transactionTestLock = $null
    try {
        try {
            Invoke-UdkConnectionTransaction $project $solution {
                [IO.File]::WriteAllText($project, 'changed project')
                $script:transactionTestLock = [IO.File]::Open($project, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                throw 'Injected failure'
            }
        } catch { if ($_.Exception.Message -notmatch 'Rollback failed') { throw } }
        if (-not (Test-Path ($project + '.UniversalDevKit.transaction/manifest.json'))) { throw 'Failed rollback lost its snapshot.' }
        try {
            Invoke-UdkConnectionTransaction $project $solution { throw 'Action must not run' }
            throw 'Pending transaction was not detected.'
        } catch { if ($_.Exception.Message -notmatch 'Unfinished transaction detected') { throw } }
    }
    finally { if ($script:transactionTestLock) { $script:transactionTestLock.Dispose() } }
    Restore-UdkConnectionTransaction $project $solution
    if ((Get-FileHash $project).Hash -cne $projectHash -or (Get-FileHash $solution).Hash -cne $solutionHash) { throw 'Manual recovery assertion failed.' }
    Invoke-UdkConnectionTransaction $project $solution {
        [IO.File]::WriteAllText($project, 'committed project')
        [IO.File]::WriteAllText($solution, 'committed solution')
    }
    if ([IO.File]::ReadAllText($project) -cne 'committed project' -or (Test-Path ($project + '.UniversalDevKit.transaction'))) { throw 'Commit assertion failed.' }
} $project $solution $projectHash $solutionHash
Write-Output "Connection transaction tests passed. Workspace: $workspace"