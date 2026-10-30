[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('ApkPath')]
    [string]$FilePath,

    [string]$MimeType = 'application/vnd.android.package-archive',

    [Parameter(Mandatory)]
    [string]$OAuthClientPath,

    [Parameter(Mandatory)]
    [string]$TokenPath,

    # Относительный путь от корня «Мой диск», а не путь локальной синхронизации.
    [Parameter(Mandatory)]
    [string[]]$DrivePath,

    # Пустое значение сохраняет имя локального APK, включая версию релиза.
    [string]$DriveFileName
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
function ConvertTo-Base64Url {
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-AuthorizationCode {
    param(
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$CodeChallenge
    )

    Add-Type -AssemblyName System.Web
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        $redirectUri = "http://127.0.0.1:$port/"
        $stateBytes = [byte[]]::new(32)
        $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $random.GetBytes($stateBytes)
        } finally {
            $random.Dispose()
        }
        $state = ConvertTo-Base64Url $stateBytes
        $parameters = @{
            access_type = 'offline'
            client_id = $ClientId
            code_challenge = $CodeChallenge
            code_challenge_method = 'S256'
            prompt = 'consent'
            redirect_uri = $redirectUri
            response_type = 'code'
            scope = 'https://www.googleapis.com/auth/drive'
            state = $state
        }
        $query = ($parameters.GetEnumerator() | ForEach-Object {
            "$([Uri]::EscapeDataString($_.Key))=$([Uri]::EscapeDataString($_.Value))"
        }) -join '&'
        Start-Process "https://accounts.google.com/o/oauth2/v2/auth?$query"
        Write-Host 'Complete Google Drive authorization in the browser.'

        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            while ($reader.ReadLine()) {
            }
            $requestTarget = $requestLine.Split(' ')[1]
            $callbackUri = [Uri]"http://127.0.0.1:$port$requestTarget"
            $callback = [System.Web.HttpUtility]::ParseQueryString($callbackUri.Query)
            $message = if ($callback['error']) {
                "Authorization failed: $($callback['error'])"
            } else {
                'Authorization completed. You can close this browser tab.'
            }
            $body = [System.Text.Encoding]::UTF8.GetBytes("<html><body>$message</body></html>")
            $header = [System.Text.Encoding]::ASCII.GetBytes(
                "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            )
            $stream.Write($header, 0, $header.Length)
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()

            if ($callback['error']) {
                throw "Google authorization failed: $($callback['error'])"
            }
            if ($callback['state'] -ne $state) {
                throw 'Google authorization returned an invalid state value.'
            }
            return @{
                Code = $callback['code']
                RedirectUri = $redirectUri
            }
        } finally {
            $client.Dispose()
        }
    } finally {
        $listener.Stop()
    }
}

function Get-AccessToken {
    param(
        [Parameter(Mandatory)] [pscustomobject]$OAuthClient,
        [Parameter(Mandatory)] [string]$TokenFile
    )

    if (Test-Path -LiteralPath $TokenFile) {
        $savedToken = Get-Content -LiteralPath $TokenFile -Raw | ConvertFrom-Json
        $response = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body @{
            client_id = $OAuthClient.client_id
            client_secret = $OAuthClient.client_secret
            grant_type = 'refresh_token'
            refresh_token = $savedToken.refresh_token
        }
        return $response.access_token
    }

    $verifierBytes = [byte[]]::new(64)
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($verifierBytes)
    } finally {
        $random.Dispose()
    }
    $codeVerifier = ConvertTo-Base64Url $verifierBytes
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($codeVerifier))
    } finally {
        $sha256.Dispose()
    }
    $authorization = Get-AuthorizationCode $OAuthClient.client_id (ConvertTo-Base64Url $challengeBytes)
    $response = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body @{
        client_id = $OAuthClient.client_id
        client_secret = $OAuthClient.client_secret
        code = $authorization.Code
        code_verifier = $codeVerifier
        grant_type = 'authorization_code'
        redirect_uri = $authorization.RedirectUri
    }
    if (-not $response.refresh_token) {
        throw 'Google did not return a refresh token.'
    }
    $tokenDirectory = Split-Path -Parent $TokenFile
    New-Item -ItemType Directory -Path $tokenDirectory -Force | Out-Null
    $tokenJson = @{ refresh_token = $response.refresh_token } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($TokenFile, $tokenJson, [System.Text.UTF8Encoding]::new($false))
    return $response.access_token
}

function Get-DriveItem {
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$ParentId,
        [Parameter(Mandatory)] [string]$Name,
        [string]$MimeType
    )

    $escapedName = $Name.Replace("'", "\\'")
    $query = "'$ParentId' in parents and name = '$escapedName' and trashed = false"
    if ($MimeType) {
        $query += " and mimeType = '$MimeType'"
    }
    $uri = 'https://www.googleapis.com/drive/v3/files?spaces=drive&fields=files(id,name,mimeType)&q=' + [Uri]::EscapeDataString($query)
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $AccessToken" }
    return @($response.files)[0]
}

function Get-DriveFolderId {
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string[]]$PathSegments
    )

    $parentId = 'root'
    foreach ($segment in $PathSegments) {
        $folder = Get-DriveItem -AccessToken $AccessToken -ParentId $parentId -Name $segment -MimeType 'application/vnd.google-apps.folder'
        if ($null -eq $folder) {
            # Первая публикация может выполняться до ручного создания папки.
            $folder = New-DriveFolder -AccessToken $AccessToken -ParentId $parentId -Name $segment
        }
        $parentId = $folder.id
    }
    return $parentId
}

function New-DriveFolder {
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$ParentId,
        [Parameter(Mandatory)] [string]$Name
    )

    $metadata = @{
        mimeType = 'application/vnd.google-apps.folder'
        name = $Name
        parents = @($ParentId)
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri 'https://www.googleapis.com/drive/v3/files?fields=id,name' -Headers @{
        Authorization = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    } -Body $metadata
}

function Send-FileToDrive {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$DestinationFolderId,
        [Parameter(Mandatory)] [string]$DestinationFileName,
        [Parameter(Mandatory)] [string]$MimeType
    )

    $file = Get-Item -LiteralPath $FilePath
    $boundary = "AndroidBuildTools$([Guid]::NewGuid().ToString('N'))"
    $existingFile = Get-DriveItem -AccessToken $AccessToken -ParentId $DestinationFolderId -Name $DestinationFileName
    $metadata = @{
        mimeType = $MimeType
        name = $DestinationFileName
    }
    if ($null -eq $existingFile) {
        $metadata.parents = @($DestinationFolderId)
    }
    $metadataJson = $metadata | ConvertTo-Json -Compress
    $prefix = [System.Text.Encoding]::UTF8.GetBytes(
        "--$boundary`r`nContent-Type: application/json; charset=UTF-8`r`n`r`n$metadataJson`r`n--$boundary`r`nContent-Type: $MimeType`r`n`r`n"
    )
    $suffix = [System.Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n")
    $requestUri = if ($null -eq $existingFile) {
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name'
    } else {
        "https://www.googleapis.com/upload/drive/v3/files/$($existingFile.id)?uploadType=multipart&fields=id,name"
    }
    $request = [System.Net.HttpWebRequest]::Create($requestUri)
    $request.Method = if ($null -eq $existingFile) { 'POST' } else { 'PATCH' }
    $request.ContentType = "multipart/related; boundary=$boundary"
    $request.Headers['Authorization'] = "Bearer $AccessToken"
    $request.ContentLength = $prefix.Length + $file.Length + $suffix.Length
    $requestStream = $request.GetRequestStream()
    try {
        $requestStream.Write($prefix, 0, $prefix.Length)
        $fileStream = $file.OpenRead()
        try {
            $fileStream.CopyTo($requestStream)
        } finally {
            $fileStream.Dispose()
        }
        $requestStream.Write($suffix, 0, $suffix.Length)
    } finally {
        $requestStream.Dispose()
    }
    $response = $request.GetResponse()
    try {
        $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
        try {
            return $reader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $reader.Dispose()
        }
    } finally {
        $response.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "File not found: $FilePath"
}
if (-not (Test-Path -LiteralPath $OAuthClientPath)) {
    throw "Desktop OAuth client JSON not found: $OAuthClientPath"
}

$oauthDocument = Get-Content -LiteralPath $OAuthClientPath -Raw | ConvertFrom-Json
$oauthClient = $oauthDocument.installed
if ($null -eq $oauthClient) {
    throw 'OAuth JSON must contain Desktop app credentials in the installed section.'
}
$accessToken = Get-AccessToken $oauthClient $TokenPath
$destinationFolderId = Get-DriveFolderId $accessToken $DrivePath
if ([string]::IsNullOrWhiteSpace($DriveFileName)) {
    $DriveFileName = (Get-Item -LiteralPath $FilePath).Name
}
$uploadedFile = Send-FileToDrive $FilePath $accessToken $destinationFolderId $DriveFileName $MimeType
Write-Host "Google Drive upload completed: $($uploadedFile.name) ($($uploadedFile.id))"
return $uploadedFile