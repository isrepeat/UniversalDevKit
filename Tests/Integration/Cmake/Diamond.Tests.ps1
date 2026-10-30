param(
    [ValidateSet('Checkout', 'Installed', 'NuGet')][string[]]$Delivery = @('Checkout', 'Installed', 'NuGet'),
    [ValidateSet('Static', 'Dynamic', 'PrivateAllStatic', 'PrivateDynamic', 'PrivateStatic', 'PublicStaticDynamic')][string[]]$Variant = @('Static', 'Dynamic', 'PrivateAllStatic', 'PrivateDynamic', 'PrivateStatic', 'PublicStaticDynamic'),
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [switch]$PackageReference
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
if ($PackageReference -and 'NuGet' -notin $Delivery) { throw 'PackageReference requires NuGet in Delivery.' }
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$NuGet = & (Join-Path $repository 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
. (Join-Path $repository 'Tests/Infrastructure/BuildTools.ps1')
$msbuild = Get-TestMSBuild
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
$run = Join-Path $repository ('!artifacts/dm-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($run)
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/Diamond'
$results = @()
function InvokeChecked([string]$Tool, [string[]]$Arguments, [string]$Log) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Tool @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "Command failed: $Tool. See $Log" }
}
function AssertConflict([string]$Tool, [string[]]$Arguments, [string]$Log) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $text = (& $Tool @Arguments 2>&1 | Out-String)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    [IO.File]::WriteAllText($Log, $text, [Text.UTF8Encoding]::new($false))
    if ($code -eq 0 -or $text -notmatch '(?i)conflict|INTERFACE_UDK_COMPONENT_VARIANT|RequiredVariant|incompatible.*variant') { throw "Expected variant conflict: $Log; $text" }
}
function CheckRuntime([string]$Bin, [string]$App, [string[]]$Components, [string]$Clean) {
    $dlls = @(Get-ChildItem -LiteralPath $Bin -Filter '*.dll' | ForEach-Object Name | Sort-Object)
    if ($dlls.Count -ne $Components.Count) { throw "Runtime count mismatch: $App; $dlls" }
    foreach ($component in $Components) {
        if (@($dlls | Where-Object { $_ -match "(?i)^universaldevkit_${component}_dynamicd?\.dll$" }).Count -ne 1) { throw "Missing runtime $component in $Bin" }
    }
    [void][IO.Directory]::CreateDirectory($Clean)
    Copy-Item -LiteralPath (Join-Path $Bin "$App.exe") -Destination $Clean
    foreach ($dll in $dlls) { Copy-Item -LiteralPath (Join-Path $Bin $dll) -Destination $Clean }
    $oldPath = $env:PATH
    try {
        $env:PATH = [Environment]::SystemDirectory
        Invoke-TestApplication (Join-Path $Clean "$App.exe") "$App passed"
    }
    finally { $env:PATH = $oldPath }
}
try {
    foreach ($caseName in $Variant) {
        $case = Join-Path $run $caseName
        $library = Join-Path $case 'udk'
        [void][IO.Directory]::CreateDirectory($library)
        # Git выбирает исходники рабочей версии; библиотеки Diamond накладываются только в копию.
        $files = @(& git -C $repository -c core.quotepath=false ls-files --cached --others --exclude-standard)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate repository files.' }
        foreach ($file in ($files | Sort-Object -Unique)) {
            if ($file -match '^Tests/' -or -not (Test-Path -LiteralPath (Join-Path $repository $file) -PathType Leaf)) { continue }
            $destination = Join-Path $library $file
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            Copy-Item -LiteralPath (Join-Path $repository $file) -Destination $destination
        }
        foreach ($directory in @('Includes', 'Sources', 'Projects')) {
            Copy-Item -LiteralPath (Join-Path $fixture $directory) -Destination $library -Recurse -Force
        }
        foreach ($file in @('Components.json', 'UniversalDevKit.sln')) { Copy-Item -LiteralPath (Join-Path $fixture $file) -Destination $library -Force }
        if ($caseName -in @('PrivateStatic', 'PublicStaticDynamic')) {
            foreach ($component in @('A', 'C')) { Copy-Item (Join-Path $fixture "PrivateStatic/$component.json") (Join-Path $library "Projects/Components/$component.json") -Force }
            if ($caseName -eq 'PublicStaticDynamic') {
                $registryPath = Join-Path $library 'Projects/Components/A.json'
                $registry = [IO.File]::ReadAllText($registryPath) | ConvertFrom-Json
                $registry.dependencies[0].visibility = 'public'
                [IO.File]::WriteAllText($registryPath, ($registry | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
            }
        }
        elseif ($caseName -in @('PrivateAllStatic', 'PrivateDynamic')) {
            $registryPath = Join-Path $library 'Projects/Components/A.json'
            $registryText = [IO.File]::ReadAllText($registryPath).Replace('"public"', '"private"')
            [IO.File]::WriteAllText($registryPath, $registryText, [Text.UTF8Encoding]::new($false))
        }
        & (Join-Path $library 'Scripts/PowerShell/GenerateComponentProjects.ps1') -RepositoryRoot $library | Out-Host
        $version = (Get-Content (Join-Path $library 'Version.json') -Raw | ConvertFrom-Json).version
        $mode = if ($caseName -in @('Static', 'PrivateAllStatic')) { 'Static' } else { 'Dynamic' }
        $private = if ($caseName -like 'Private*') { 'ON' } else { 'OFF' }
        $consumer = Join-Path $case 'consumer'
        Copy-Item -LiteralPath (Join-Path $fixture 'Consumer') -Destination $consumer -Recurse
        foreach ($deliveryName in $Delivery) {
            if ($PackageReference) { continue }
            if ($deliveryName -eq 'NuGet') { continue }
            $build = Join-Path $case $deliveryName
            $args = @('-S', $consumer, '-B', $build, '-G', 'Visual Studio 18 2026', '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug;Release', "-DDIAMOND_MODE=$mode", "-DDIAMOND_PRIVATE_STATIC=$private")
            if ($caseName -eq 'PublicStaticDynamic') { $args += '-DDIAMOND_PUBLIC_STATIC=ON' }
            if ($deliveryName -eq 'Checkout') { $args += "-DDIAMOND_CHECKOUT=$library" }
            else {
                $packageBuild = Join-Path $library '!artifacts/package'
                $install = Join-Path $case 'install'
                InvokeChecked $CMake @('-S', $library, '-B', $packageBuild, '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$install") (Join-Path $case 'package-configure.log')
                foreach ($configuration in @('Debug', 'Release')) {
                    InvokeChecked $CMake @('--build', $packageBuild, '--config', $configuration) (Join-Path $case "package-build-$configuration.log")
                    InvokeChecked $CMake @('--install', $packageBuild, '--config', $configuration) (Join-Path $case "package-install-$configuration.log")
                }
                $relocated = Join-Path $case 'relocated'
                Copy-Item -LiteralPath $install -Destination $relocated -Recurse
                $args += "-DCMAKE_PREFIX_PATH=$relocated"
            }
            InvokeChecked $CMake $args (Join-Path $case "$deliveryName-configure.log")
            foreach ($configuration in @('Debug', 'Release')) {
                InvokeChecked $CMake @('--build', $build, '--config', $configuration) (Join-Path $case "$deliveryName-$configuration.log")
                foreach ($app in @('App1', 'App2')) {
                    $expected = if ($mode -eq 'Static') { @() } elseif ($caseName -in @('PrivateStatic', 'PublicStaticDynamic')) { if ($app -eq 'App1') { @('A','C') } else { @('C') } } elseif ($app -eq 'App1') { @('A','B','C','D') } else { @('C','D') }
                    CheckRuntime (Join-Path $build "bin/$app/$configuration") $app $expected (Join-Path $case "run-$deliveryName-$configuration-$app")
                }
                # App2 собирается отдельно, без зависимости от сборки App1.
                InvokeChecked $CMake @('--build', $build, '--config', $configuration, '--target', 'App2') (Join-Path $case "$deliveryName-App2-$configuration.log")
            }
            $conflictArgs = @($args)
            $conflictArgs[3] = Join-Path $case "$deliveryName-conflict"
            $conflictArgs += '-DDIAMOND_CONFLICT=ON'
            AssertConflict $CMake $conflictArgs (Join-Path $case "$deliveryName-conflict.log")
            $results += [pscustomobject]@{ Delivery=$deliveryName; Variant=$caseName; Status='Passed' }
        }
        if ('NuGet' -in $Delivery) {
            # Пакетные определения используют штатную интеграцию; исходники компонентов остаются в fixture.
            $basePackage = Join-Path $repository 'Packages/CrossPlatform/HeleprsTest'
            foreach ($component in @('A','B','C','D')) {
                $packageRoot = Join-Path $library "Packages/CrossPlatform/$component"
                foreach ($file in (Get-ChildItem -LiteralPath $basePackage -File -Recurse)) {
                    $relative = $file.FullName.Substring($basePackage.Length+1).Replace('HeleprsTest', $component)
                    $destination = Join-Path $packageRoot $relative
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                    $text = [IO.File]::ReadAllText($file.FullName).Replace('HeleprsTest', $component)
                    [IO.File]::WriteAllText($destination, $text, [Text.UTF8Encoding]::new($false))
                }
            }
            $feed = Join-Path $library '!artifacts/nuget'
            & (Join-Path $repository 'Packages/Build/NuGet/Build.ps1') -RepositoryPath $library -Components A -LicenseFile (Join-Path $repository 'LICENSE') -OutputDirectory $feed -CMake $CMake -NuGet $NuGet | Out-Host
            foreach ($runtime in @('Dynamic','Static')) {
                foreach ($app in @('App1','App2')) {
                    $component = if ($app -eq 'App1') { 'A' } else { 'C' }
                    $appRoot = Join-Path $case "ng-$runtime-$app"
                    [void][IO.Directory]::CreateDirectory($appRoot)
                    Copy-Item (Join-Path $consumer "$app/Main.cpp") (Join-Path $appRoot 'Main.cpp')
                    if (-not $PackageReference) {
                        & $NuGet install "UniversalDevKit.$component" -Version $version -Source $feed -OutputDirectory (Join-Path $appRoot 'packages') -NoHttpCache -DirectDownload -NonInteractive -ForceEnglishOutput | Out-Host
                        if ($LASTEXITCODE -ne 0) { throw 'Diamond NuGet restore failed.' }
                    }
                    # packages.config требует явных импортов props/targets восстановленных зависимостей.
                    $dependencies = if ($component -eq 'A') { @('B','C','D') } else { @('D') }
                    $props = @($dependencies | ForEach-Object { '  <Import Project="packages\UniversalDevKit.' + $_ + '.' + $version + '\build\native\UniversalDevKit.' + $_ + '.props" />' }) -join "`r`n"
                    $targets = @($dependencies | ForEach-Object { '  <Import Project="packages\UniversalDevKit.' + $_ + '.' + $version + '\build\native\UniversalDevKit.' + $_ + '.targets" />' }) -join "`r`n"
                    $text = [IO.File]::ReadAllText((Join-Path $repository 'Tests/Fixtures/Consumers/NuGet/Consumer.vcxproj.in')).Replace('HeleprsTest', $component).Replace('{{VERSION}}', $version).Replace('{{DIAGNOSTIC_IMPORT}}',$targets).Replace('{{DIAGNOSTIC_PROPS}}',$props).Replace('{{ROOTS}}',$component)
                    $publicB = if ($caseName -like 'Private*') { 0 } else { 1 }
                    $definitions = "DIAMOND_TEST_BOUNDARIES=1;DIAMOND_TEST_HEADER_ISOLATION=1;DIAMOND_TEST_PUBLIC_B=$publicB" + $(if ($mode -eq 'Dynamic') { ';DIAMOND_TEST_DYNAMIC=1' } else { '' })
                    if ($caseName -eq 'PublicStaticDynamic') { $definitions += ';DIAMOND_TEST_PUBLIC_STATIC=1' }
                    $text = $text.Replace('{{TEST_DEFINITIONS}}', $definitions)
                    if ($PackageReference) {
                        $text = [IO.File]::ReadAllText((Join-Path $repository 'Tests/Fixtures/Consumers/NuGet/PackageReference.vcxproj.in')).Replace('{{VERSION}}', $version).Replace('{{COMPONENT}}', $component).Replace('{{RUNTIME}}', $runtime).Replace('{{LINKAGE}}', $mode).Replace('{{DEFINITIONS}}', $definitions)
                    }
                    $project = Join-Path $appRoot "$app.vcxproj"
                    [IO.File]::WriteAllText($project, $text, [Text.UTF8Encoding]::new($false))
                    if ($app -eq 'App1') {
                        $conflictProject = Join-Path $appRoot 'Conflict.vcxproj'
                        $conflictText = $text.Replace('<UniversalDevKitComponents>A</UniversalDevKitComponents>', '<UniversalDevKitComponents>A;C</UniversalDevKitComponents>')
                        [IO.File]::WriteAllText($conflictProject, $conflictText, [Text.UTF8Encoding]::new($false))
                    }
                    $restoreArguments = @()
                    if ($PackageReference) {
                        $cache = Join-Path $appRoot 'cache'
                        $configPath = Join-Path $appRoot 'NuGet.Config'
                        $configText = '<configuration><packageSources><clear/><add key="local" value="' + [Security.SecurityElement]::Escape($feed) + '"/></packageSources></configuration>'
                        [IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
                        $restoreArguments = @("/p:RestorePackagesPath=$cache", "/p:RestoreConfigFile=$configPath", '/p:NuGetAudit=false')
                        $restoreProjects = @($project)
                        if ($app -eq 'App1') { $restoreProjects += $conflictProject }
                        foreach ($restoreProject in $restoreProjects) {
                            InvokeChecked $msbuild (@($restoreProject, '/nologo', '/v:minimal', '/t:Restore', '/p:Configuration=Debug', '/p:Platform=x64', '/p:RestoreNoCache=true') + $restoreArguments) (Join-Path $appRoot ((Split-Path $restoreProject -Leaf) + '-restore.log'))
                        }
                        $assets = Get-Content -LiteralPath (Join-Path $appRoot 'obj/project.assets.json') -Raw | ConvertFrom-Json
                        foreach ($dependency in (@($component) + $dependencies)) {
                            if (-not $assets.libraries.PSObject.Properties["UniversalDevKit.$dependency/$version"]) { throw "Missing transitive PackageReference dependency: $dependency" }
                        }
                    }
                    foreach ($configuration in @('Debug','Release')) {
                        $buildArgs = @($project, '/m','/nologo','/v:minimal','/t:Rebuild','/p:Platform=x64',"/p:Configuration=$configuration","/p:UniversalDevKitRuntime=$runtime","/p:UniversalDevKit${component}Linkage=$mode")
                        $buildArgs += $restoreArguments
                        InvokeChecked $msbuild $buildArgs (Join-Path $case "NuGet-$runtime-$app-$configuration.log")
                        $expected = if ($mode -eq 'Static') { @() } elseif ($caseName -in @('PrivateStatic', 'PublicStaticDynamic')) { if ($app -eq 'App1') { @('A','C') } else { @('C') } } elseif ($app -eq 'App1') { @('A','B','C','D') } else { @('C','D') }
                        $bin = Join-Path $appRoot "out/$configuration"
                        $exe = Join-Path $bin "$app.exe"
                        if (-not (Test-Path $exe)) { throw "Missing NuGet consumer: $exe" }
                        CheckRuntime $bin $app $expected (Join-Path $case "run-NuGet-$runtime-$configuration-$app")
                        if ($app -eq 'App1') {
                            $oppositeMode = if ($mode -eq 'Dynamic') { 'Static' } else { 'Dynamic' }
                            $conflictArgs = @($buildArgs)
                            $conflictArgs[0] = $conflictProject
                            $conflictArgs += "/p:UniversalDevKitCLinkage=$oppositeMode"
                            AssertConflict $msbuild $conflictArgs (Join-Path $case "NuGet-conflict-$runtime-$configuration.log")
                        }
                    }
                }
            }
            $results += [pscustomobject]@{ Delivery=$(if ($PackageReference) { 'NuGetPackageReference' } else { 'NuGet' }); Variant=$caseName; Status='Passed' }
        }
    }
}
catch {
    $results += [pscustomobject]@{ Delivery='Run'; Variant=''; Status='Failed: '+$_.Exception.Message }
    throw
}
finally {
    $results | Export-Csv -LiteralPath (Join-Path $run 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Diamond matrix workspace: $run"
}