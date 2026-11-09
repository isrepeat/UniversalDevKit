function Read-AndroidSharedProps {
    param([Parameter(Mandatory)] [string]$ProjectRoot)

    # Ближайший файл целиком заменяет родительский; пути привязаны к его каталогу.
    $directory = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($ProjectRoot))
    while ($null -ne $directory) {
        $path = Join-Path $directory.FullName 'Android.SharedProps.json'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "Invalid Android.SharedProps.json at ${path}: $($_.Exception.Message)"
            }
            if ($data -isnot [pscustomobject] -or $data.Paths -isnot [pscustomobject]) {
                throw "Android.SharedProps.json must contain an object with a Paths object: $path"
            }
            if ($null -ne $data.Properties -and $data.Properties -isnot [pscustomobject]) {
                throw "Android.SharedProps.json Properties must be an object: $path"
            }
            if (($data.SchemaVersion -isnot [int] -and $data.SchemaVersion -isnot [long]) -or $data.SchemaVersion -ne 1) {
                throw "Android.SharedProps.json must define SchemaVersion = 1: $path"
            }
            $result = @{ FilePath = $path; Paths = @{}; Properties = @{} }
            foreach ($name in @('SecretsRoot', 'SigningProperties', 'DriveOAuthClientPath', 'DriveTokenPath', 'PackagesFeed', 'PreviewerDebugExecutablePath', 'PreviewerReleaseExecutablePath')) {
                $value = $data.Paths.$name
                if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                    throw "Android.SharedProps.json must define Paths.${name}: $path"
                }
            }
            foreach ($property in $data.Paths.PSObject.Properties) {
                $name = $property.Name
                $value = $property.Value
                if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                    throw "Android.SharedProps.json path must be a non-empty string: Paths.$name in $path"
                }
                $result.Paths[$name] = if ([IO.Path]::IsPathRooted($value)) {
                    [IO.Path]::GetFullPath($value)
                } else {
                    [IO.Path]::GetFullPath((Join-Path $directory.FullName $value))
                }
            }
            if ($null -ne $data.Properties) {
                foreach ($property in $data.Properties.PSObject.Properties) {
                    $result.Properties[$property.Name] = $property.Value
                }
            }
            return $result
        }
        $directory = $directory.Parent
    }
    throw "Android.SharedProps.json was not found above project root: $ProjectRoot"
}