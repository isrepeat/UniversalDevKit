function Reset-UdkArtifactDirectory {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if (-not $target.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact directory must be below its root: $target"
    }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Cannot reset an artifact directory link: $target"
        }
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
    [void][IO.Directory]::CreateDirectory($target)
    return $target
}