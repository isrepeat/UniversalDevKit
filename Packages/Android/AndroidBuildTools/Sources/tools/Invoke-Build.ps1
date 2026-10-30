[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Position = 0)]
    [ValidateSet('restore', 'get-configuration-path', 'get-configuration-value', 'build-android', 'build-and-distribute', 'build-for-drive', 'build-all', 'bump-version', 'generate-xaml', 'upload-apk-to-drive', 'run-android-app-previewer')]
    [string]$Command = 'build-android',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration,
    [ValidateSet('arm64-v8a')]
    [string]$Architecture,
    [ValidateSet('Local', 'Drive')]
    [string]$Destination,
    [switch]$Clean,
    [switch]$NativeOnly,
    [switch]$KeepVersion,
    [int]$AppVersionCode,
    [string]$AppVersionName,
    [string]$SigningProperties,
    [string]$TargetsConfigUrl,
    [string]$Name,
    [string]$ApkPath,
    [string]$FilePath,
    [string]$MimeType,
    [string]$OAuthClientPath,
    [string]$TokenPath,
    [string[]]$DrivePath,
    [string]$DriveFileName,
    [int]$ParentProcessId,
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'

# Это конфигурация конкретного приложения. В пакете нет имён модулей, путей к
# ресурсам или секретов: они всегда берутся из android-build.psd1 потребителя.
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot

# $PSScriptRoot указывает на <пакет>/tools. Поднимаемся на один уровень, чтобы
# построить пути к другим scripts и вернуть корень пакета для команды restore.
$packageRoot = Split-Path -Parent $PSScriptRoot

# $PSBoundParameters содержит только параметры, которые пользователь указал
# явно. Собираем их в отдельную таблицу для передачи следующему script.
# Command выбирает действие, а ProjectRoot добавляется ниже автоматически, поэтому
# оба параметра не должны попадать в параметры целевой команды.
$parameters = @{}
foreach ($name in $PSBoundParameters.Keys) {
    if ($name -notin @('Command', 'ProjectRoot')) {
        $parameters[$name] = $PSBoundParameters[$name]
    }
}

# restore — служебная команда для CMake и Gradle. Им нужен только путь к уже
# восстановленному пакету, чтобы подключить его CMake-модули или Gradle plugins.
# Другие параметры в этом режиме означали бы ошибку вызова.
if ($Command -eq 'restore') {
    if ($parameters.Count -gt 0) {
        throw 'The restore command does not accept build parameters.'
    }
    return $packageRoot
}

# Эти два имени оставлены как короткие ярлыки для .bat-файлов. Реальную работу
# выполняет одна команда: собрать versioned APK и отправить его в Google Drive.
if ($Command -in @('build-for-drive', 'build-all')) {
    $Command = 'build-and-distribute'
    $parameters.Destination = 'Drive'
}

# Имя команды соответствует имени файла в tools, например build-android
# превращается в tools/build-android.ps1.
$script = Join-Path $packageRoot "tools\$Command.ps1"
if ($Command -eq 'upload-apk-to-drive' -and $parameters.ContainsKey('ApkPath')) {
    if ($parameters.ContainsKey('FilePath')) {
        throw 'Specify either ApkPath or FilePath, not both.'
    }
    $parameters.FilePath = $parameters.ApkPath
    $parameters.Remove('ApkPath')
}

# Сначала читаем контракт выбранного script. Это не даёт случайно передать
# параметр не той команде и получить непонятную ошибку уже внутри неё.
$metadata = Get-Command -Name $script -ErrorAction Stop
foreach ($name in $parameters.Keys) {
    if (-not $metadata.Parameters.ContainsKey($name)) {
        throw "The $Command command does not accept -$name."
    }
}

# У upload-apk-to-drive нет ProjectRoot: ему достаточно файла APK и реквизитов
# Google Drive. Если пути OAuth и Drive не переданы в командной строке, берём
# значения из секции Drive конфигурации приложения.
if ($Command -eq 'upload-apk-to-drive') {
    foreach ($name in @('OAuthClientPath', 'TokenPath')) {
        if (-not $parameters.ContainsKey($name)) {
            $parameters[$name] = $androidProjectSharedConfig.Paths[('Drive' + $name)]
        }
    }
    if (-not $parameters.ContainsKey('DrivePath')) {
        $parameters.DrivePath = $androidProjectConfig.Drive.Path
    }
} else {
    # Остальные команды работают с проектом, поэтому всегда получают его корень,
    # даже если пользователь не писал -ProjectRoot вручную.
    $parameters.ProjectRoot = $ProjectRoot
}

# Оператор & запускает выбранный PowerShell script. @parameters разворачивает
# хеш-таблицу в именованные параметры: @{ Configuration = 'Debug' } превращается
# в -Configuration Debug.
& $script @parameters