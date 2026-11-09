function Invoke-UdkFilesProject($Project, $Context) {
    $root = $Context.RepositoryPath
    $output = Reset-UdkArtifactDirectory -Root $Context.WorkDirectory -Path (Join-Path $Context.WorkDirectory 'output')
    $seen = @{}
    foreach ($mapping in $Project.mappings) {
        $source = Resolve-UdkBuildPath $root $root $mapping.source -Existing
        $destination = Resolve-UdkBuildPath $output $output $mapping.destination
        $directory = Test-Path -LiteralPath $source -PathType Container
        $files = if ($directory) { @(Get-ChildItem -LiteralPath $source -Recurse -File -Force) } else { @(Get-Item -LiteralPath $source) }
        foreach ($file in $files) {
            $target = if ($directory) {
                Resolve-UdkBuildPath $output $destination $file.FullName.Substring($source.TrimEnd('\', '/').Length + 1)
            } else { $destination }
            if ($seen.ContainsKey($target)) { throw "Duplicate file mapping: $target" }
            $seen[$target] = $true
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    return @{ output = $output }
}