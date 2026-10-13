param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
# Each transition invokes real Connect and verifies the build and execution.
foreach ($linkage in @('Shared', 'Static', 'Dynamic', 'Shared')) {
    Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath $linkage
}