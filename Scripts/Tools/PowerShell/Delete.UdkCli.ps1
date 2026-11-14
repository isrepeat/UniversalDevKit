$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function Read-UdkVersion([string]$Prompt) {
    $inputVersion = (Read-Host $Prompt).Trim()
    if ($inputVersion -notmatch '\A[0-9]+\.[0-9]+(?:\.[0-9]+)?\z') {
        throw "Invalid version '$inputVersion'. Enter major.minor or major.minor.patch."
    }
    $version = [version]$inputVersion
    return [version]::new($version.Major, $version.Minor, [Math]::Max(0, $version.Build))
}

$from = Read-UdkVersion 'From version (inclusive)'
$to = Read-UdkVersion 'To version (inclusive)'
if ($from -gt $to) {
    throw 'The start version must be less than or equal to the end version.'
}

$repository = 'isrepeat/UniversalDevKit'
$releaseTags = & gh.exe api "repos/$repository/releases?per_page=100" --paginate --jq '.[].tag_name'
if ($LASTEXITCODE -ne 0) {
    throw 'Could not list GitHub releases.'
}

$selected = @(foreach ($tag in $releaseTags) {
    if ($tag -cmatch '\Audk-cli-v([0-9]+\.[0-9]+\.[0-9]+)\z') {
        $version = [version]$Matches[1]
        if ($version -ge $from -and $version -le $to) {
            [pscustomobject]@{ Tag = $tag; Version = $version }
        }
    }
})
if ($selected.Count -eq 0) {
    Write-Host "No stable UDK CLI releases found between $from and $to."
    return
}

$tags = @($selected | Sort-Object Version | ForEach-Object {
    $_.Tag
})
Write-Host "Stable UDK CLI releases to delete from $repository (Git tags are kept):"
$tags | ForEach-Object {
    Write-Host "  $_"
}
if ((Read-Host "Delete these $($tags.Count) releases? [y/N]") -notin @('y', 'yes')) {
    Write-Host 'Deletion cancelled.'
    return
}

foreach ($tag in $tags) {
    & gh.exe release delete $tag --repo $repository --yes
    if ($LASTEXITCODE -ne 0) {
        throw "Could not delete release $tag. Earlier deletions have already been applied."
    }
    Write-Host "Deleted $tag."
}