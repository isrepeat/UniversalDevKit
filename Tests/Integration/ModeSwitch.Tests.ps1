param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
# Каждый переход выполняет настоящий Connect и повторно проверяет сборку и запуск.
foreach ($linkage in @('Shared', 'Static', 'Dynamic', 'Shared')) {
    Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath $linkage
}