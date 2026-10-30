function Resolve-UdkAndroidToolchain {
    param([string]$AndroidNdk, [string]$AndroidSdk, [string]$JavaHome, [string]$Gradle, [switch]$ForConsumer, [switch]$WithoutNdk)
    $profile = Get-Content (Join-Path $PSScriptRoot 'Toolchain.json') -Raw | ConvertFrom-Json
    function Find-Installation([string]$Explicit, [object[]]$Candidates, [string]$Marker, [string]$Name) {
        if ($Explicit) {
            if (-not (Test-Path -LiteralPath (Join-Path $Explicit $Marker))) { throw "Invalid $Name installation: $Explicit" }
            return (Resolve-Path -LiteralPath $Explicit).Path
        }
        foreach ($candidate in $Candidates) {
            if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate $Marker))) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
        throw "$Name was not found. Pass its path explicitly."
    }
    $sdkCandidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA/Android/Sdk", "${env:ProgramFiles(x86)}/Android/android-sdk", "$env:ProgramFiles/Android/Sdk")
    if ($ForConsumer -or $AndroidSdk) { $AndroidSdk = Find-Installation $AndroidSdk $sdkCandidates 'platform-tools/adb.exe' 'Android SDK' }
    if (-not $WithoutNdk) {
        $ndkCandidates = @($env:ANDROID_NDK_HOME, $env:ANDROID_NDK_ROOT)
        foreach ($sdk in @($AndroidSdk) + $sdkCandidates) {
            if ($sdk) { $ndkCandidates += Join-Path $sdk "ndk/$($profile.ndkVersion)" }
        }
        $ndkCandidates += "${env:ProgramFiles(x86)}/Android/AndroidNDK/android-ndk-r27c"
        if (-not $AndroidNdk) {
            $AndroidNdk = @($ndkCandidates | Where-Object {
                $_ -and (Test-Path -LiteralPath (Join-Path $_ 'source.properties')) -and
                ((Get-Content (Join-Path $_ 'source.properties') -Raw) -match ('(?m)^Pkg.Revision\s*=\s*' + [regex]::Escape($profile.ndkVersion) + '\s*$'))
            } | Select-Object -First 1)[0]
        }
        $AndroidNdk = Find-Installation $AndroidNdk @() 'build/cmake/android.toolchain.cmake' 'Android NDK'
        $revision = ((Get-Content (Join-Path $AndroidNdk 'source.properties') | Where-Object { $_ -match '^Pkg.Revision\s*=' }) -split '=')[1].Trim()
        if ($revision -ne $profile.ndkVersion) { throw "UDK requires NDK $($profile.ndkVersion); found $revision at $AndroidNdk." }
    }
    if ($ForConsumer) {
        $javaCandidates = @($env:JAVA_HOME, $env:JDK_HOME)
        foreach ($root in @("$env:ProgramFiles/Android/openjdk", "$env:ProgramFiles/Java", "$env:ProgramFiles/Eclipse Adoptium")) {
            if (Test-Path -LiteralPath $root) { $javaCandidates += @(Get-ChildItem -LiteralPath $root -Directory | Select-Object -ExpandProperty FullName) }
        }
        $javaCandidates += "$env:ProgramFiles/Android/Android Studio/jbr"
        if (-not $JavaHome) {
            $JavaHome = @($javaCandidates | Where-Object {
                $_ -and (Test-Path -LiteralPath (Join-Path $_ 'release')) -and
                ((Get-Content (Join-Path $_ 'release') -Raw) -match ('JAVA_VERSION="' + $profile.javaMajor + '(\.|\")'))
            } | Select-Object -First 1)[0]
        }
        $JavaHome = Find-Installation $JavaHome @() 'bin/java.exe' 'JDK'
        if ((Get-Content (Join-Path $JavaHome 'release') -Raw) -notmatch ('JAVA_VERSION="' + $profile.javaMajor + '(\.|\")')) { throw "UDK requires JDK $($profile.javaMajor): $JavaHome" }
        if (-not $Gradle) {
            $wrapperProperties = Get-Content (Join-Path $PSScriptRoot 'Gradle/gradle/wrapper/gradle-wrapper.properties') -Raw
            if ($wrapperProperties -notmatch ('gradle-' + [regex]::Escape($profile.gradleVersion) + '-bin\.zip')) { throw 'Gradle Wrapper does not match Toolchain.json.' }
            $Gradle = Join-Path $PSScriptRoot 'Gradle/gradlew.bat'
        }
        $Gradle = (Resolve-Path -LiteralPath $Gradle).Path
    }
    [pscustomobject]@{ AndroidNdk = $AndroidNdk; AndroidSdk = $AndroidSdk; JavaHome = $JavaHome; Gradle = $Gradle }
}