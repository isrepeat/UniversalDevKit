function Invoke-TestGit {
    param([string]$Directory, [string[]]$Arguments)
    & git -C $Directory @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($Arguments -join ' ')" }
}

function New-TestWorkspace {
    param([string]$RepositoryPath, [ValidateSet('WorkingTree', 'Submodule')][string]$Mode, [string]$Revision)
    $root = Join-Path $RepositoryPath ('!artifacts/tests/' + [Guid]::NewGuid().ToString('N'))
    $consumer = Join-Path $root 'Consumer'
    $library = Join-Path $consumer 'external/UniversalDevKit'
    [void][IO.Directory]::CreateDirectory($consumer)
    # Copy only the template, independently of previous build artifacts.
    Get-ChildItem -LiteralPath (Join-Path $RepositoryPath 'Tests/Fixtures/Consumers/MsBuild') -Force | Copy-Item -Destination $consumer -Recurse
    Invoke-TestGit $consumer @('init', '-b', 'test')
    if ($Mode -eq 'Submodule') {
        Invoke-TestGit $consumer @('-c', 'protocol.file.allow=always', 'submodule', 'add', '--', $RepositoryPath, 'external/UniversalDevKit')
        Invoke-TestGit $library @('checkout', '--detach', $Revision)
        Invoke-TestGit $consumer @('add', '--', 'external/UniversalDevKit')
    }
    else {
        [void][IO.Directory]::CreateDirectory($library)
        # Git selects modified and untracked files, excluding ignored files.
        $files = @(& git -C $RepositoryPath -c core.quotepath=false ls-files --cached --others --exclude-standard)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate UDK files.' }
        foreach ($file in ($files | Sort-Object -Unique)) {
            if ($file -match '^Tests/') { continue }
            $source = Join-Path $RepositoryPath $file
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $destination = Join-Path $library $file
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            Copy-Item -LiteralPath $source -Destination $destination
        }
    }
    return [pscustomobject]@{ Root = $root; Consumer = $consumer; Library = $library; Mode = $Mode }
}

function Remove-TestWorkspace {
    param([string]$RepositoryPath, $Workspace)
    # Allow deletion only of the specific run directory under the dedicated root.
    $parent = [IO.Path]::GetFullPath((Join-Path $RepositoryPath '!artifacts/tests')).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Workspace.Root).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($target) -cne $parent -or [IO.Path]::GetFileName($target) -notmatch '^[0-9a-f]{32}$') {
        throw "Unsafe test workspace: $target"
    }
    Remove-Item -LiteralPath $target -Recurse -Force
}