param(
    [string]$ProjectPath,
    [string[]]$Components,
    [hashtable]$ComponentModes = @{},
    [string]$SolutionPath,
    [string]$SolutionInjectorPath,
    [switch]$ProjectOnly,
    [switch]$Disconnect
)

$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Import-Module (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Module.Udk.Connection.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Modules/Module.Udk.Console/Module.Udk.Console.psm1') -ErrorAction Stop

# 1. Получаем реестр компонентов и запрос без изменения проектов.
$componentRegistry = Module.Udk.Connection\Get-UdkComponentRegistry -RepositoryPath $repositoryPath
$request = Module.Udk.Console\Show-UdkConnectionWizard @PSBoundParameters -RepositoryPath $repositoryPath -ComponentRegistry $componentRegistry
if ($null -eq $request) {
    return
}

# 2. Рассчитываем и проверяем итоговую схему подключения.
$state = Module.Udk.Connection\Get-UdkConnectionState -ProjectPath $request.ProjectPath
$plan = Module.Udk.Connection\New-UdkConnectionPlan -Request $request -State $state -ComponentRegistry $componentRegistry -RepositoryPath $repositoryPath

# 3. Применяем план, передавая оформление сообщений из консольного модуля.
$writeStatus = { param($Text, $Role) Module.Udk.Console\Write-UdkConsoleText $Text $Role }
$resolveTool = {
    param($RepositoryPath, $LocalPath)
    Module.Udk.Console\Invoke-UdkConsoleProgress -Action ({
        param($ProgressCallback)
        & (Join-Path $RepositoryPath 'Scripts/PowerShell/GetSolutionInjector.ps1') -LocalPath $LocalPath -ProgressCallback $ProgressCallback
    }.GetNewClosure())
}
Module.Udk.Connection\Invoke-UdkConnectionPlan -Plan $plan -WriteStatus $writeStatus -ResolveTool $resolveTool