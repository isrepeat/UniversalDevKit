function Resolve-UdkCMake([string]$Path) {
    if ($Path) {
        return (Get-Command $Path -ErrorAction Stop).Source
    }
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $found = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
    if (-not $found.Count) {
        throw 'CMake was not found. Pass -CMake.'
    }
    return $found[0]
}

function Resolve-UdkNinja([string]$Path, [string]$CMake) {
    if ($Path) {
        return (Get-Command $Path -ErrorAction Stop).Source
    }
    foreach ($candidate in @((Join-Path (Split-Path $CMake -Parent) 'ninja.exe'), (Join-Path (Split-Path (Split-Path (Split-Path $CMake -Parent) -Parent) -Parent) 'Ninja/ninja.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return (Get-Command ninja.exe -ErrorAction Stop).Source
}