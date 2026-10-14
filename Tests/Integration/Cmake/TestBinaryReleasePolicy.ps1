param([string]$CMake)

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
$run = Join-Path $repository ('!artifacts/tests/release-policy-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$fixture = Join-Path $repository 'Tests/Fixtures/BinaryReleasePolicy/Check.cmake'
function CheckCase([string[]]$Options, [string]$ExpectedError) {
    $ErrorActionPreference = 'Continue'
    $output = & $CMake "-DREPOSITORY=$repository" "-DWORKSPACE=$run" '-DRUNTIME=Dynamic' @Options -P $fixture 2>&1
    $code = $LASTEXITCODE
    if ($ExpectedError) {
        if ($code -eq 0 -or ($output -join "`n") -notmatch $ExpectedError) { throw "Expected rejection: $ExpectedError; $output" }
    }
    elseif ($code -ne 0) { throw "Unexpected failure: $output" }
}
# Оба CRT и повторное использование неизменного идентификатора должны проходить.
CheckCase @() ''
CheckCase @() ''
CheckCase @('-DRUNTIME=Static') ''
foreach ($field in @('platforms', 'architectures', 'compilerIds', 'compilerVersions', 'toolsets', 'runtimes', 'configurations', 'variants')) {
    CheckCase @("-DREJECT_FIELD=$field") "release $field mismatch"
}
# Изменение любого параметра выполняется на уровне того же guard, что использует UDK.
foreach ($case in @('Compiler', 'CompilerVersion', 'Architecture', 'Runtime')) {
    CheckCase @("-DIDENTITY_CASE=$case") 'compiler/architecture/runtime changed'
}
Write-Output 'Binary release policy and build identity checks passed.'