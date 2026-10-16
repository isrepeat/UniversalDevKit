param(
    [string]$BatDir = $null,
    [string]$Head = $null,
    [string]$Base = $null,
    [string]$Title = $null,
    [string]$NewBranch = $null,
    [switch]$ReplaceRemoteHead
)

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'

$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding

$callerLocation = Get-Location

$modulePath = Join-Path $PSScriptRoot "Modules"
if (-not ($env:PSModulePath -split ';' | Where-Object { $_ -eq $modulePath })) {
    $env:PSModulePath = "$modulePath;$env:PSModulePath"
}

Import-Module -Name MessagingModule -Prefix m:: -ErrorAction Stop

function ExitWithError {
    param([string]$Message)

    m::MessageError $Message
    exit 1
}

function Test-LocalBranch {
    param([string]$Branch)

    git show-ref --verify --quiet "refs/heads/$Branch"
    return $LASTEXITCODE -eq 0
}

function Test-RemoteBranch {
    param([string]$Branch)

    git show-ref --verify --quiet "refs/remotes/origin/$Branch"
    return $LASTEXITCODE -eq 0
}

function New-DefaultPullRequestTitle {
    param(
        [Parameter(Mandatory)] [string]$BaseBranch,
        [Parameter(Mandatory)] [string]$HeadBranch
    )

    # Compare the source changes since its common ancestor with the target:
    # this matches the set of files a Pull Request shows to its reviewer.
    $changedFiles = @(git diff --name-only "origin/$BaseBranch...origin/$HeadBranch")
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to get the list of changed files for the Pull Request title."
    }

    if ($changedFiles.Count -lt 5) {
        if ($changedFiles.Count -eq 0) {
            return "No file changes"
        }
        return "Changed: $($changedFiles -join ', ')"
    }

    return "Changed files: $($changedFiles.Count)"
}

# The .bat launcher may be located in the repository or next to the submodule.
if ($BatDir) {
    $BatDir = $BatDir.Trim().Trim('"')
    try {
        $workDir = (Resolve-Path -LiteralPath $BatDir).Path
    }
    catch {
        ExitWithError "Incorrect path BatDir: '$BatDir'"
    }
}
else {
    $workDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$gitRoot = [string](& git -C "$workDir" rev-parse --show-toplevel 2>$null)
$gitRoot = $gitRoot.Trim()
if (-not $gitRoot) {
    ExitWithError "Not a Git repository at: $workDir"
}

Push-Location $gitRoot
$env:GH_REPO = (& git config --get remote.origin.url 2>$null).Trim()

try {
    m::Message "Working repo: $gitRoot"
    if ($env:GH_REPO) {
        m::Message "Remote: $env:GH_REPO"
    }
    m::NewLine

    # GitHub CLI may have been installed after the parent process started,
    # so also check the standard winget installation path.
    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCommand) {
        $gh = $ghCommand.Source
    }
    else {
        $standardGhPath = Join-Path $env:ProgramFiles "GitHub CLI\gh.exe"
        if (Test-Path -LiteralPath $standardGhPath) {
            $gh = $standardGhPath
        }
        else {
            ExitWithError "GitHub CLI (gh) was not found. Install it and run 'gh auth login'."
        }
    }

    & $gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "GitHub CLI is not authenticated. Run 'gh auth login'."
    }

    # Arguments can be supplied on the command line. When the .bat file is
    # started directly, missing values are requested interactively.
    if ([string]::IsNullOrWhiteSpace($Head)) {
        $Head = Read-Host "Enter Source Branch (head)"
    }
    if ([string]::IsNullOrWhiteSpace($Base)) {
        $Base = Read-Host "Enter Target Branch (base)"
    }
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = Read-Host "Enter Pull Request Title (empty = automatic)"
    }
    if ($null -eq $NewBranch) {
        $NewBranch = Read-Host "Enter branch to recreate from target HEAD (empty = source branch)"
    }

    $Head = $Head.Trim()
    $Base = $Base.Trim()
    $Title = $Title.Trim()
    $NewBranch = if ([string]::IsNullOrWhiteSpace($NewBranch)) { $Head } else { $NewBranch.Trim() }

    if ([string]::IsNullOrWhiteSpace($Head)) {
        ExitWithError "Head branch is required."
    }
    if ([string]::IsNullOrWhiteSpace($Base)) {
        ExitWithError "Base branch is required."
    }
    if ($Head -ieq $Base) {
        ExitWithError "Head and Base must be different branches."
    }

    if ($NewBranch -ieq $Base) {
        ExitWithError "NewBranch must not be the target branch."
    }
    foreach ($branch in @($Head, $Base, $NewBranch)) {
        git check-ref-format --branch "$branch" | Out-Null
        if ($LASTEXITCODE -ne 0) { ExitWithError "Invalid branch name: $branch" }
    }

    # Recreating a branch requires switching the checkout. Do not risk local
    # uncommitted files even when Git would technically allow the switch.
    $dirtyFiles = @(git status --porcelain)
    if ($dirtyFiles.Count -gt 0) {
        ExitWithError "Working tree is not clean. Commit or stash local changes first."
    }

    m::MessageAction "Fetching remote branches..."
    git fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to fetch remote branches."
    }

    if (-not (Test-RemoteBranch $Base)) {
        ExitWithError "Target branch 'origin/$Base' does not exist."
    }

    # The source may exist only on the remote. Create a local branch so the
    # workflow behaves consistently regardless of the current branch.
    if (-not (Test-LocalBranch $Head)) {
        if (-not (Test-RemoteBranch $Head)) {
            ExitWithError "Source branch '$Head' does not exist locally or on origin."
        }

        m::MessageAction "Creating local '$Head' from 'origin/$Head'..."
        git branch --track "$Head" "origin/$Head"
        if ($LASTEXITCODE -ne 0) {
            ExitWithError "Failed to create local branch '$Head'."
        }
    }

    # A fully published branch is a normal state here: Git reports
    # Everything up-to-date and the workflow continues. A stale remote working
    # branch may belong to an earlier cycle. Replace it only when its fetched
    # commit still matches the expected value (--force-with-lease).
    m::MessageAction "Publishing '$Head' to origin..."
    $useForceWithLease = $false
    $remoteHeadCommit = $null
    if (Test-RemoteBranch $Head) {
        $remoteHeadCommit = (git rev-parse "origin/$Head").Trim()
        git merge-base --is-ancestor "origin/$Head" "$Head"
        $useForceWithLease = $LASTEXITCODE -ne 0
    }

    if ($useForceWithLease -and -not $ReplaceRemoteHead) {
        ExitWithError "Remote head diverged. Review it before using -ReplaceRemoteHead."
    }
    if ($NewBranch -ine $Head -and (Test-LocalBranch $NewBranch)) {
        git merge-base --is-ancestor "$NewBranch" "origin/$Base"
        if ($LASTEXITCODE -ne 0) { ExitWithError "NewBranch contains commits absent from the target; refusing to overwrite it." }
    }
    if ($useForceWithLease) {
        m::Message "Remote '$Head' is from an earlier workflow cycle; replacing it with lease protection."
        git push --force-with-lease="refs/heads/$Head`:$remoteHeadCommit" origin "$Head`:$Head"
    }
    else {
        git push origin "$Head`:$Head"
    }
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to push '$Head' to origin."
    }

    git fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to refresh remote branches after push."
    }

    $publishedHead = [string](git rev-parse "origin/$Head")
    $publishedHead = $publishedHead.Trim()
    $commitsToMerge = [int](git rev-list --count "origin/$Base..origin/$Head")
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to compare 'origin/$Head' with 'origin/$Base'."
    }

    if ($commitsToMerge -gt 0) {
        if ([string]::IsNullOrWhiteSpace($Title)) {
            $Title = New-DefaultPullRequestTitle -BaseBranch $Base -HeadBranch $Head
            m::Message "Automatic Pull Request title: $Title"
        }

        # A repeated run must reuse a Pull Request that is already open.
        $prNumber = [string](& $gh pr list `
            --state open `
            --base "$Base" `
            --head "$Head" `
            --json number `
            --jq ".[0].number" 2>$null)
        if ($LASTEXITCODE -ne 0) { ExitWithError 'Failed to query open Pull Requests.' }
        $prNumber = $prNumber.Trim()

        if ([string]::IsNullOrWhiteSpace($prNumber)) {
            m::MessageAction "Creating Pull Request '$Head' -> '$Base'..."
            $prCreationOutput = & $gh pr create `
                --title "$Title" `
                --body "Auto-generated PR from AutoPrMerge workflow." `
                --base "$Base" `
                --head "$Head" 2>&1

            if ($LASTEXITCODE -ne 0) {
                ExitWithError "Failed to create Pull Request.`n$prCreationOutput"
            }

            if ($prCreationOutput -match '/pull/(\d+)\b') {
                $prNumber = $matches[1]
            }
            else {
                $prNumber = [string](& $gh pr list `
                    --state open `
                    --base "$Base" `
                    --head "$Head" `
                    --json number `
                    --jq ".[0].number" 2>$null)
                if ($LASTEXITCODE -ne 0) { ExitWithError 'Failed to query the created Pull Request.' }
                $prNumber = $prNumber.Trim()
            }
        }
        else {
            m::Message "Using existing Pull Request #$prNumber."
        }

        if ([string]::IsNullOrWhiteSpace($prNumber)) {
            ExitWithError "Unable to resolve Pull Request number."
        }

        m::MessageAction "Merging Pull Request #$prNumber..."
        & $gh pr merge $prNumber --merge --match-head-commit "$publishedHead" --subject "Merge PR #$prNumber $Title"
        if ($LASTEXITCODE -ne 0) {
            ExitWithError "Failed to merge Pull Request #$prNumber."
        }
        $mergeState = & $gh pr view $prNumber --json state --jq .state
        if ($LASTEXITCODE -ne 0 -or $mergeState -ne 'MERGED') {
            ExitWithError "Merge is not confirmed. Source branches are retained; rerun after the PR is merged."
        }
        m::Message "Pull Request #$prNumber successfully merged."
    }
    else {
        # GitHub cannot create a Pull Request without differences. This is not
        # an error; synchronize the working branch with the target HEAD.
        m::Message "No commits to merge from '$Head' into '$Base'. Pull Request is not required."
    }

    m::MessageAction "Refreshing merged target 'origin/$Base'..."
    git fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to refresh 'origin/$Base' after merge."
    }

    git merge-base --is-ancestor "$publishedHead" "origin/$Base"
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Published source commits are absent from the target; refusing branch cleanup."
    }

    $currentHead = [string](git rev-parse "$Head")
    if ($LASTEXITCODE -ne 0 -or $currentHead.Trim() -ne $publishedHead -or @(git status --porcelain).Count -gt 0) {
        ExitWithError 'Local source changed during the workflow; refusing branch cleanup.'
    }

    # Delete the old remote source branch as in the original workflow. The
    # recreated branch can then be published with a regular, non-forced push.
    if (Test-RemoteBranch $Head) {
        m::MessageAction "Deleting old remote branch '$Head'..."
        git push --force-with-lease="refs/heads/$Head`:$publishedHead" origin ":refs/heads/$Head"
        if ($LASTEXITCODE -ne 0) {
            ExitWithError "Failed to delete remote branch '$Head'."
        }
    }

    git fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to prune deleted remote branch '$Head'."
    }

    # Recreate the branch at the exact target HEAD. A detached checkout allows
    # the branch to be moved safely even when it was the current branch.
    m::MessageAction "Recreating '$NewBranch' from 'origin/$Base'..."
    git switch --detach "origin/$Base"
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to switch to 'origin/$Base'."
    }

    if (Test-LocalBranch $NewBranch) {
        git branch -f "$NewBranch" "origin/$Base"
    }
    else {
        git branch "$NewBranch" "origin/$Base"
    }
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to create local branch '$NewBranch' from 'origin/$Base'."
    }

    git switch "$NewBranch"
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to switch to '$NewBranch'."
    }

    # When the new working branch has a different name, remove the obsolete
    # local source branch after switching successfully.
    if (($NewBranch -ine $Head) -and (Test-LocalBranch $Head)) {
        git branch -D "$Head"
        if ($LASTEXITCODE -ne 0) {
            ExitWithError "Failed to delete old local branch '$Head'."
        }
    }

    m::MessageAction "Publishing recreated branch '$NewBranch'..."
    git push -u origin "$NewBranch`:$NewBranch"
    if ($LASTEXITCODE -ne 0) {
        ExitWithError "Failed to publish recreated branch '$NewBranch'."
    }

    m::NewLine
    m::Message "Done. 'origin/$Base' and 'origin/$NewBranch' now point to the same commit."
}
finally {
    Pop-Location
}