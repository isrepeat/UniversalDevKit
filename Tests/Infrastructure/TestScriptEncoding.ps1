param([string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$files = @(& git -C $RepositoryPath ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate repository scripts.' }
$checked = 0
foreach ($file in ($files | Sort-Object -Unique)) {
    if ($file -notmatch '\.(ps1|psm1|cmd|bat)$') { continue }
    $path = Join-Path $RepositoryPath $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    # Строгое декодирование выявляет повреждённый UTF-8; BOM разрешён.
    $text = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($path)).TrimStart([char]0xFEFF)
    if ($file -match '\.ps(m)?1$') {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "PowerShell syntax error: $file" }
        $strings = $ast.FindAll({ param($node)
            ($node -is [Management.Automation.Language.StringConstantExpressionAst] -or $node -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and $node.Extent.Text -match '[^\x00-\x7F]'
        }, $true)
        if ($strings.Count) { throw "Non-English string literal: $file, line $($strings[0].Extent.StartLineNumber)" }
    }
    else {
        foreach ($line in ($text -split '\r?\n')) {
            if ($line -match '^\s*(rem\b|::)' ) { continue }
            if ($line -match '[^\x00-\x7F]') { throw "Non-English CMD text: $file" }
        }
    }
    $checked++
}
Write-Output "Script encoding and English strings validated: $checked files."