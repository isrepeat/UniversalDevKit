[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string]$Command = 'build-android',
    [string]$BuildToolsVersion
)

dynamicparam {
    $ErrorActionPreference = 'Stop'
    # До restore модуль AndroidBuildTools ещё не существует в проекте.
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
    $OutputEncoding = $utf8Encoding

    $androidProjectConfig = & ([scriptblock]::Create([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'android-build.psd1'))))
    . (Join-Path $PSScriptRoot 'Scripts\PowerShell\Read-AndroidSharedProps.ps1')
    $androidProjectSharedConfig = Read-AndroidSharedProps -ProjectRoot $PSScriptRoot
    $packagesRoot = Join-Path $PSScriptRoot $androidProjectConfig.PackageDirectories.AndroidBuildTools
    $packageName = 'AndroidBuildTools'
    $source = if ($env:ANDROID_BUILD_TOOLS_SOURCE) { $env:ANDROID_BUILD_TOOLS_SOURCE } else { $androidProjectSharedConfig.Paths.PackagesFeed }
    $packageVersion = $androidProjectConfig.AndroidBuildToolsVersion
    if ($Command -eq 'update-build-tools') {
        $nuget = (Get-Command nuget.exe -ErrorAction Stop).Source
        # Обновление выполняет загрузчик независимо от возможностей старого пакета.
        if ($BuildToolsVersion) {
            $packageVersion = $BuildToolsVersion
        } else {
            $availablePackages = & $nuget list $packageName -Source $source -AllVersions -NonInteractive -ForceEnglishOutput 2>&1
            if ($LASTEXITCODE -ne 0) { throw "AndroidBuildTools version lookup failed for $source." }
            $packageVersion = $availablePackages | ForEach-Object {
                $match = [regex]::Match($_.ToString(), '^\s*AndroidBuildTools\s+(\d+(?:\.\d+){2,3})\s*$')
                if ($match.Success) { [version]$match.Groups[1].Value }
            } | Sort-Object -Descending | Select-Object -First 1
        }
    } elseif ($BuildToolsVersion) {
        throw 'BuildToolsVersion is only supported by update-build-tools.'
    }
    if (-not $packageVersion) { throw 'AndroidBuildToolsVersion is required. Run update-build-tools.' }
    $packageVersion = $packageVersion.ToString()

    $entryPoint = Join-Path $packagesRoot "$packageName.$packageVersion\tools\Invoke-Build.ps1"
    # Закреплённую распакованную версию повторно не восстанавливаем.
    if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
        $nuget = (Get-Command nuget.exe -ErrorAction Stop).Source
        & $nuget install $packageName -Version $packageVersion -Source $source -OutputDirectory $packagesRoot -NonInteractive -DirectDownload -NoHttpCache -ForceEnglishOutput -Verbosity quiet | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "$packageName $packageVersion restore failed with exit code $LASTEXITCODE."
        }
    }
    if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
        throw "$packageName $packageVersion did not provide tools\Invoke-Build.ps1 in $packagesRoot."
    }

    # Получаем параметры из пакета: загрузчик не содержит списка команд и опций.
    $metadata = Get-Command -Name $entryPoint -ErrorAction Stop
    $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    $parameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    foreach ($parameter in $metadata.Parameters.Values) {
        if ($parameter.Name -notin @('ProjectRoot', 'Command') -and $parameter.Name -notin $common) {
            $parameters.Add($parameter.Name, [System.Management.Automation.RuntimeDefinedParameter]::new($parameter.Name, $parameter.ParameterType, $parameter.Attributes))
        }
    }
    $parameters
}

end {
    # Прямой запуск CMake из IDE использует тот же feed, что и сборочные команды.
    if ($Command -eq 'get-packages-feed') {
        Write-Output $androidProjectSharedConfig.Paths.PackagesFeed
        return
    }
    if ($Command -eq 'update-build-tools') {
        $configurationPath = Join-Path $PSScriptRoot 'android-build.psd1'
        $text = [System.IO.File]::ReadAllText($configurationPath)
        $assignment = "    AndroidBuildToolsVersion = '$packageVersion'"
        if ($text -match '(?m)^\s*AndroidBuildToolsVersion\s*=') {
            $text = [regex]::Replace($text, '(?m)^[ \t]*AndroidBuildToolsVersion\s*=[^\r\n]*', $assignment)
        } else {
            $text = [regex]::new('@\{').Replace($text, "@{`r`n$assignment", 1)
        }
        [System.IO.File]::WriteAllText($configurationPath, $text.TrimEnd(), [System.Text.UTF8Encoding]::new($false))
        Write-Host "AndroidBuildToolsVersion updated to $packageVersion."
        return
    }
    # Сценарий приложения проверяет Updater; общий сборщик не знает о зависимых проектах.
    $command = if ($PSBoundParameters.Command) { $PSBoundParameters.Command } else { 'build-android' }
    if ($command -in @('build-android', 'build-and-distribute', 'build-for-drive', 'build-all')) {
        $configuration = if ($PSBoundParameters.Configuration) { $PSBoundParameters.Configuration } elseif ($command -eq 'build-android') { 'Debug' } else { 'Release' }
        $buildToolsRoot = Split-Path -Parent (Split-Path -Parent $entryPoint)
        Import-Module (Join-Path $buildToolsRoot 'tools\Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
        Module.AndroidBuildTools\Show-AndroidBuildInputs -ProjectRoot $PSScriptRoot -Configuration $configuration
        if (-not $PSBoundParameters.NativeOnly -and $androidProjectConfig.RequireUpdater) {
            $signingProperties = if ($PSBoundParameters.SigningProperties) { $PSBoundParameters.SigningProperties } else { $androidProjectSharedConfig.Paths.SigningProperties }
            & (Join-Path $PSScriptRoot 'Scripts\PowerShell\ensure-apk-updater.ps1') -ApkUpdaterProjectRoot $androidProjectSharedConfig.Paths.ApkUpdaterProjectRoot -SigningProperties $signingProperties -BuildToolsRoot $buildToolsRoot -Configuration $configuration
        }
    }
    & $entryPoint -ProjectRoot $PSScriptRoot @PSBoundParameters
}