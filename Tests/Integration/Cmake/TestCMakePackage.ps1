param([string]$CMake = 'cmake', [string]$Generator = 'Visual Studio 18 2026')

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$run = Join-Path $repository ('!artifacts/Windows-x64/cmake/PackageTest-' + [Guid]::NewGuid().ToString('N'))
$build = Join-Path $run 'build'
$install = Join-Path $run 'install'
$relocated = Join-Path $run 'relocated'
$consumer = Join-Path $run 'consumer'

function InvokeCMake([string[]]$Arguments) {
    & $CMake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed: $($Arguments -join ' ')"
    }
}

# Verify both configurations in one installed package.
InvokeCMake @('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$install")
foreach ($configuration in @('Debug', 'Release')) {
    InvokeCMake @('--build', $build, '--config', $configuration)
    InvokeCMake @('--install', $build, '--config', $configuration)
}

# Relocate only the installed package; the original prefix no longer exists.
$runPrefix = [IO.Path]::GetFullPath($run).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
foreach ($packageDirectory in @($install, $relocated)) {
    if (-not [IO.Path]::GetFullPath($packageDirectory).StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package directory is outside the test workspace: $packageDirectory"
    }
}
Move-Item -LiteralPath $install -Destination $relocated
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Consumers/CmakePackage'), '-B', $consumer, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug;Release', "-DCMAKE_PREFIX_PATH=$relocated")
foreach ($configuration in @('Debug', 'Release')) {
    InvokeCMake @('--build', $consumer, '--config', $configuration)
    $ctest = Join-Path (Split-Path -Parent (Get-Command $CMake).Source) 'ctest.exe'
    & $ctest --test-dir $consumer -C $configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) {
        throw "Package consumer failed: $configuration"
    }
}

# Header-only Meta must remain usable after installation without a binary target.
$metaConsumer = Join-Path $run 'meta-consumer'
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Consumers/MetaPackage'), '-B', $metaConsumer, '-G', $Generator, '-A', 'x64', "-DCMAKE_PREFIX_PATH=$relocated")
InvokeCMake @('--build', $metaConsumer, '--config', 'Release')
& $ctest --test-dir $metaConsumer -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) {
    throw 'Installed Meta package consumer failed.'
}

# Verify Math fixes through an independent consumer of the installed package.
$mathConsumer = Join-Path $run 'math-consumer'
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Consumers/MathPackage'), '-B', $mathConsumer, '-G', $Generator, '-A', 'x64', "-DCMAKE_PREFIX_PATH=$relocated")
foreach ($configuration in @('Debug', 'Release')) {
    InvokeCMake @('--build', $mathConsumer, '--config', $configuration)
    & $ctest --test-dir $mathConsumer -C $configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw "Installed Math package consumer failed: $configuration" }
}
if (Test-Path (Join-Path $relocated 'include/UniversalDevKit/Helpers/Math/Differentation.h')) {
    throw 'Installed Math package contains the obsolete Differentation.h header.'
}

# Reject unknown required components during configuration.
& $CMake -S (Join-Path $repository 'Tests/Fixtures/Consumers/CmakePackage') -B (Join-Path $run 'invalid') -G $Generator -A x64 "-DCMAKE_PREFIX_PATH=$relocated" -DUDK_TEST_COMPONENT=Unknown
if ($LASTEXITCODE -eq 0) {
    throw 'Unknown component was accepted.'
}
function AssertConfigurationFails([string]$Scenario, [string[]]$Arguments, [string]$ExpectedMessage) {
    # Windows PowerShell must not interrupt collection of expected stderr diagnostics.
    $ErrorActionPreference = 'Continue'
    $output = & $CMake @Arguments 2>&1
    $result = $LASTEXITCODE
    if ($result -eq 0) {
        throw "Unexpected configuration success: $Scenario"
    }
    if (($output -join "`n") -notmatch $ExpectedMessage) {
        throw "Unexpected error in ${Scenario}: $($output -join '`n')"
    }
    Write-Output "Expected rejection: $Scenario"
}

$contractSource = Join-Path $repository 'Tests/Fixtures/Consumers/CmakeContract'
# Verify headers without binaries and access only to the selected component and Core.
$headerBuild = Join-Path $run 'header-isolation'
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Consumers/HeaderIsolation'), '-B', $headerBuild, '-G', $Generator, '-A', 'x64')
InvokeCMake @('--build', $headerBuild, '--config', 'Release')
& (Join-Path $headerBuild 'Release/header_isolation.exe')
if ($LASTEXITCODE -ne 0) {
    throw 'Header isolation consumer failed.'
}
AssertConfigurationFails 'Changed runtime in existing build tree' @('-S', $repository, '-B', $build, '-DUniversalDevKitRuntime=Static') 'separate build\s+directory'
AssertConfigurationFails 'Invalid runtime choice' @('-S', $repository, '-B', (Join-Path $run 'invalid-runtime'), '-G', $Generator, '-A', 'x64', '-DUniversalDevKitRuntime=Unknown') 'UniversalDevKitRuntime must be'
$contractArguments = @('-S', $contractSource, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release')

# Verify direct and transitive conflicts in the installed package.
AssertConfigurationFails 'Installed variant conflict' ($contractArguments + @('-B', (Join-Path $run 'conflict'), "-DCMAKE_PREFIX_PATH=$relocated", '-DTEST_CONFLICT=HeleprsTest.Dynamic')) 'UDK_COMPONENT_VARIANT_HeleprsTest'
AssertConfigurationFails 'Direct variant conflict' ($contractArguments + @('-B', (Join-Path $run 'direct-conflict'), "-DCMAKE_PREFIX_PATH=$relocated", '-DTEST_CHECK=DirectConflict', '-DTEST_CONFLICT=HeleprsTest.Dynamic')) 'UDK_COMPONENT_VARIANT_HeleprsTest'
AssertConfigurationFails 'Private DLL dependency conflict' ($contractArguments + @('-B', (Join-Path $run 'private-conflict'), "-DCMAKE_PREFIX_PATH=$relocated", '-DTEST_TARGET=DiagnosticTest.Dynamic', '-DTEST_CONFLICT=HeleprsTest.Dynamic')) 'UDK_COMPONENT_VARIANT_HeleprsTest'
AssertConfigurationFails 'Source variant conflict' ($contractArguments + @('-B', (Join-Path $run 'source-conflict'), '-DTEST_CHECK=SourceConflict', '-DTEST_CONFLICT=HeleprsTest.Dynamic')) 'UDK_COMPONENT_VARIANT_HeleprsTest'

# Create a separate Release-only package containing HeleprsTest.Static.
$limitedBuild = Join-Path $run 'limited-build'
$limitedInstall = Join-Path $run 'limited-install'
InvokeCMake @('-S', $repository, '-B', $limitedBuild, '-G', $Generator, '-A', 'x64', '-DUniversalDevKit_COMPONENTS=HeleprsTest', '-DUniversalDevKit_BUILD_DYNAMIC=OFF', "-DCMAKE_INSTALL_PREFIX=$limitedInstall")
InvokeCMake @('--build', $limitedBuild, '--config', 'Release')
InvokeCMake @('--install', $limitedBuild, '--config', 'Release')
if (Test-Path -LiteralPath (Join-Path $limitedInstall 'include/UniversalDevKit/DiagnosticTest')) {
    throw 'Limited package contains excluded DiagnosticTest headers.'
}
$limitedConsumer = Join-Path $run 'limited-consumer'
InvokeCMake ($contractArguments + @('-B', $limitedConsumer, "-DCMAKE_PREFIX_PATH=$limitedInstall"))
InvokeCMake @('--build', $limitedConsumer, '--config', 'Release')
& (Join-Path $limitedConsumer 'Release/contract.exe')
if ($LASTEXITCODE -ne 0) {
    throw 'Limited package consumer failed.'
}
AssertConfigurationFails 'Excluded component' ($contractArguments + @('-B', (Join-Path $run 'excluded'), "-DCMAKE_PREFIX_PATH=$limitedInstall", '-DTEST_COMPONENT=DiagnosticTest')) 'NOT FOUND|not FOUND'
AssertConfigurationFails 'Unavailable Dynamic variant' ($contractArguments + @('-B', (Join-Path $run 'missing-variant'), "-DCMAKE_PREFIX_PATH=$limitedInstall", '-DTEST_TARGET=HeleprsTest.Dynamic')) 'HeleprsTest.Dynamic'
AssertConfigurationFails 'Missing Debug configuration' (@('-S', $contractSource, '-B', (Join-Path $run 'missing-debug'), '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug', "-DCMAKE_PREFIX_PATH=$limitedInstall")) 'IMPORTED_LOCATION|IMPORTED_IMPLIB'
AssertConfigurationFails 'Incompatible x86 architecture' (@('-S', $contractSource, '-B', (Join-Path $run 'wrong-architecture'), '-G', $Generator, '-A', 'Win32', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$limitedInstall")) '64bit|not compatible|not accepted'
Write-Output 'Package contract checks passed.'

# The new component checks C++20, threads, system libraries and a dynamic service.
InvokeCMake @('-P', (Join-Path $repository 'Tests/Integration/Cmake/RequirementValidation.cmake'))
$requirementsBuild = Join-Path $run 'requirements-build'
$requirementsInstall = Join-Path $run 'requirements-install'
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Libraries/Registry'), '-B', $requirementsBuild, '-G', $Generator, '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$requirementsInstall")
InvokeCMake @('--build', $requirementsBuild, '--config', 'Release')
& $ctest --test-dir $requirementsBuild -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) {
    throw 'Component requirements fixture failed.'
}
InvokeCMake @('--install', $requirementsBuild, '--config', 'Release')
$requirementsConsumer = Join-Path $run 'requirements-consumer'
InvokeCMake @('-S', (Join-Path $repository 'Tests/Fixtures/Consumers/RequirementsPackage'), '-B', $requirementsConsumer, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$requirementsInstall")
InvokeCMake @('--build', $requirementsConsumer, '--config', 'Release')
& $ctest --test-dir $requirementsConsumer -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) {
    throw 'Installed component requirements failed.'
}