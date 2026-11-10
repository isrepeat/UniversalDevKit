function Invoke-UdkMavenDelivery($Plan, [string]$Stage, [string]$OutputDirectory) {
    $payload = Join-Path $Stage 'payload'
    if ($Plan.Delivery.adapter -eq 'maven-repository') {
        foreach ($file in Get-ChildItem -LiteralPath $payload -Recurse -File) {
            $relative = $file.FullName.Substring($payload.Length + 1)
            $target = Resolve-UdkBuildPath $OutputDirectory $OutputDirectory $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
        return Join-Path $OutputDirectory ($Plan.Delivery.groupId.Replace('.','/') + '/' + $Plan.Delivery.artifactId + '/' + $Plan.Version)
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($variant in Get-ChildItem -LiteralPath $payload -Directory) {
        $contract = Read-UdkBuildJson (Join-Path $variant.FullName 'udk-release.json')
        $artifact = $Plan.Delivery.artifactPrefix + '-' + $variant.Name.ToLowerInvariant() + '-' + $contract.configuration.ToLowerInvariant()
        $destination = Join-Path $OutputDirectory ($Plan.Delivery.groupId.Replace('.','/') + '/' + $artifact + '/' + $Plan.Version)
        [void][IO.Directory]::CreateDirectory($destination)
        $aar = Join-Path $destination ($artifact + '-' + $Plan.Version + '.aar')
        $stream = [IO.File]::Open($aar, [IO.FileMode]::Create)
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in Get-ChildItem -LiteralPath $variant.FullName -Recurse -File) {
                $relative = $file.FullName.Substring($variant.FullName.Length + 1).Replace('\','/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative)
            }
        } finally {
            $archive.Dispose()
            $stream.Dispose()
        }
        $pom = '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>' + $Plan.Delivery.groupId + '</groupId><artifactId>' + $artifact + '</artifactId><version>' + $Plan.Version + '</version><packaging>aar</packaging><licenses><license><name>MIT</name><url>https://opensource.org/licenses/MIT</url></license></licenses></project>'
        [IO.File]::WriteAllText((Join-Path $destination ($artifact + '-' + $Plan.Version + '.pom')), $pom, [Text.UTF8Encoding]::new($false))
        Write-Output $aar
    }
}