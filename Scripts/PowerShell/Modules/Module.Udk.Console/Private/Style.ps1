function Write-UdkConsoleText {
    param([string]$Text, [string]$Role = 'Text', [switch]$NoNewline)

    # RGB-палитра Olive; для консоли без ANSI используем ближайшие стандартные цвета.
    $palette = @{
        Title = @{ Rgb = '166;185;129'; Fallback = 'DarkGreen' }
        Text = @{ Rgb = '170;170;170'; Fallback = 'Gray' }
        Hint = @{ Rgb = '119;119;119'; Fallback = 'DarkGray' }
        Mark = @{ Rgb = '180;204;149'; Fallback = 'Green' }
        Focus = @{ Rgb = '216;196;120'; Fallback = 'Yellow' }
    }
    $color = $palette[$Role]
    if ($Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected) {
        $escape = [char]27
        $background = if ($Role -eq 'Focus') { "$escape[48;2;36;39;31m" } else { '' }
        Write-Host ("$escape[38;2;$($color.Rgb)m$background$Text$escape[0m") -NoNewline:$NoNewline
    }
    else { Write-Host $Text -ForegroundColor $color.Fallback -NoNewline:$NoNewline }
}

function ReadMenuPath([string]$Prompt) {
    Write-UdkConsoleText ($Prompt + ': ') Title -NoNewline
    return (Read-Host).Trim('"')
}

function Invoke-UdkConsoleProgress {
    param([scriptblock]$Action)

    # Встроенный прогресс загрузки и распаковки оформляем без постоянного изменения консоли.
    $foreground = $Host.PrivateData.ProgressForegroundColor
    $background = $Host.PrivateData.ProgressBackgroundColor
    $style = $null
    if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $style = $PSStyle.Progress.Style }
    try {
        $Host.PrivateData.ProgressForegroundColor = 'DarkGreen'
        $Host.PrivateData.ProgressBackgroundColor = 'Black'
        if ($null -ne $style) { $PSStyle.Progress.Style = "$([char]27)[38;2;166;185;129m" }
        & $Action
    }
    finally {
        $Host.PrivateData.ProgressForegroundColor = $foreground
        $Host.PrivateData.ProgressBackgroundColor = $background
        if ($null -ne $style) { $PSStyle.Progress.Style = $style }
    }
}