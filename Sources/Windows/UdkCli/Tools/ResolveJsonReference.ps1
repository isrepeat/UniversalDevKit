function Resolve-UdkJsonReference([string]$RepositoryRoot, $Value, [string]$Location) {
    if ($Value -isnot [string] -or -not $Value.Contains('${')) {
        return ,$Value
    }
    if ($Value -cnotmatch '^\$\{([A-Z][A-Z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\}$') {
        throw "Invalid JSON reference '$Value' in $Location."
    }
    $alias = $Matches[1]
    $fields = $Matches[2].Split('.')
    $mapPath = Join-Path $RepositoryRoot 'JsonReferences.json'
    $map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    $path = ($map.PSObject.Properties | Where-Object Name -CEQ $alias).Value
    if ($path -isnot [string] -or -not $path) {
        throw "Unknown JSON reference '$Value' in $Location."
    }
    if ($path -match '[\\:$@%*?;\r\n]' -or @($path.Split('/') | Where-Object {
        $_ -in @('', '.', '..')
    }).Count -or $path -notlike '*.json') {
        throw "Invalid path for JSON reference '$Value' in $Location."
    }
    $node = Get-Content -LiteralPath (Join-Path $RepositoryRoot $path) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    foreach ($field in $fields) {
        $property = $node.PSObject.Properties | Where-Object Name -CEQ $field
        if ($node -isnot [pscustomobject] -or $null -eq $property) {
            throw "Missing field in JSON reference '$Value' in $Location."
        }
        $node = $property.Value
    }
    return ,$node
}

function Resolve-UdkDescriptionVersion([string]$RepositoryRoot, $Description, [string]$Path, [string]$Field = 'version') {
    if (-not $Description.PSObject.Properties[$Field]) {
        throw "Missing field '$Field': $Path"
    }
    $version = Resolve-UdkJsonReference $RepositoryRoot $Description.$Field "$Path ($Field)"
    if ($version -isnot [string] -or $version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][A-Za-z0-9.-]+)?$') {
        throw "Invalid ${Field}: $Path"
    }
    $Description.$Field = $version
}

function Resolve-UdkDescriptionAbiVersion([string]$RepositoryRoot, $Description, [string]$Path) {
    if ($Description.PSObject.Properties['abiVersion']) {
        $abiVersion = Resolve-UdkJsonReference $RepositoryRoot $Description.abiVersion "$Path (abiVersion)"
        if (($abiVersion -isnot [int] -and $abiVersion -isnot [long]) -or $abiVersion -lt 0) {
            throw "Invalid abiVersion: $Path"
        }
        $Description.abiVersion = $abiVersion
    }
}