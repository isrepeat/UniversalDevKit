[CmdletBinding()]
param([string]$ApkPath, [string]$SigningProperties, [string]$JavaHome, [string]$AndroidSdk, [ValidateSet('Debug', 'Release')] [string]$Configuration = 'Debug')
$ErrorActionPreference = 'Stop'
$signing = ConvertFrom-StringData ([IO.File]::ReadAllText($SigningProperties))
$prefix = if ($Configuration -eq 'Debug') { 'debug' } else { '' }
$storeKey = if ($prefix) { 'debugStoreFile' } else { 'storeFile' }
$passwordKey = if ($prefix) { 'debugStorePassword' } else { 'storePassword' }
$aliasKey = if ($prefix) { 'debugKeyAlias' } else { 'keyAlias' }
foreach ($key in @($storeKey, $passwordKey, $aliasKey)) {
    if ([string]::IsNullOrWhiteSpace($signing[$key])) {
        throw "Required signing setting is missing: $key"
    }
}
$keytool = Join-Path $JavaHome 'bin\keytool.exe'
$java = Join-Path $JavaHome 'bin\java.exe'
$apksigner = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'lib\apksigner.jar') -PathType Leaf } |
    Sort-Object { [version]($_.Name.Split('-')[0]) } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $apksigner) {
    throw "apksigner was not found in $AndroidSdk"
}
$apksigner = Join-Path $apksigner 'lib\apksigner.jar'

# Пароль передаётся через временную переменную окружения, а не аргументы процесса.
$previousPassword = $env:ANDROID_CERTIFICATE_STORE_PASSWORD
$env:ANDROID_CERTIFICATE_STORE_PASSWORD = $signing[$passwordKey]
try {
    $certificateOutput = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -list -v -keystore $signing[$storeKey] -alias $signing[$aliasKey] -storepass:env ANDROID_CERTIFICATE_STORE_PASSWORD 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the shared signing certificate with keytool.'
    }
} finally {
    $env:ANDROID_CERTIFICATE_STORE_PASSWORD = $previousPassword
}
$certificateMatch = [regex]::Match(($certificateOutput -join "`n"), 'SHA256:\s*([0-9A-Fa-f:]+)')
if (-not $certificateMatch.Success) {
    throw 'Shared certificate SHA-256 fingerprint was not found.'
}
$expectedFingerprint = $certificateMatch.Groups[1].Value.Replace(':', '').ToLowerInvariant()
    if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        return $false
    }
    $output = & $java -jar $apksigner verify --print-certs $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    $fingerprints = [regex]::Matches(($output -join "`n"), '(?m)^Signer #\d+ certificate SHA-256 digest:\s*([0-9A-Fa-f]+)\s*$')
    return $fingerprints.Count -eq 1 -and $fingerprints[0].Groups[1].Value.ToLowerInvariant() -eq $expectedFingerprint