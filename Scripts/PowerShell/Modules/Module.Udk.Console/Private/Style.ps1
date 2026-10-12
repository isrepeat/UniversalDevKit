function Write-UdkConsoleText {
    param([string]$Text, [string]$Role = 'Text', [switch]$NoNewline)

    # RGB-палитра Olive; для консоли без ANSI используем ближайшие стандартные цвета.
    $palette = @{
        Title = @{ Rgb = '166;185;129'; Fallback = 'DarkGreen' }
        Text = @{ Rgb = '170;170;170'; Fallback = 'Gray' }
        Hint = @{ Rgb = '119;119;119'; Fallback = 'DarkGray' }
        Mark = @{ Rgb = '180;204;149'; Fallback = 'Green' }
        Focus = @{ Rgb = '216;196;120'; Fallback = 'Yellow' }
        Progress = @{ Rgb = '216;196;120'; Fallback = 'DarkYellow' }
        Blocked = @{ Rgb = '220;105;105'; Fallback = 'Red' }
    }
    $color = $palette[$Role]
    if ($Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected) {
        $escape = [char]27
        $background = if ($Role -eq 'Focus') {
            "$escape[48;2;36;39;31m"
        } else {
            ''
        }
        Write-Host ("$escape[38;2;$($color.Rgb)m$background$Text$escape[0m") -NoNewline:$NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor $color.Fallback -NoNewline:$NoNewline
    }
}

function ReadMenuPath([string]$Prompt) {
    Write-UdkConsoleText ($Prompt + ': ') Title -NoNewline
    return (Read-Host).Trim('"')
}

function Write-UdkConsoleProgress {
    param($Progress, [hashtable]$State)

    # При перенаправлении вывода оставляем только начало и конец этапа без управляющих символов.
    if ([Console]::IsOutputRedirected -and -not $Progress.Finished -and $State.Stage -eq $Progress.Stage) {
        return
    }
    if ($State.Open -and $State.Stage -ne $Progress.Stage) {
        Write-Host ''; $State.Open = $false
    }
    $State.Stage = $Progress.Stage
    $width = 80
    if (-not [Console]::IsOutputRedirected) {
        try { $width = [Math]::Max(20, [Console]::WindowWidth) } catch { }
    }
    $barWidth = [Math]::Max(4, [Math]::Min(28, $width - 48))
    $knownTotal = $Progress.Total -gt 0
    $percent = if ($knownTotal) {
        [Math]::Min(100, [Math]::Floor(100.0 * $Progress.Completed / $Progress.Total))
    } else {
        $null
    }
    if ($knownTotal) {
        $filled = [int][Math]::Floor($barWidth * $percent / 100)
        $bar = ('=' * $filled) + (' ' * ($barWidth - $filled))
        $detail = ' {0,3}%' -f $percent
    }
    else {
        # Без известного размера показываем движение и объём, не выдумывая процент.
        $position = $State.Frame % $barWidth
        $State.Frame++
        $bar = (' ' * $position) + '=' + (' ' * ($barWidth - $position - 1))
        $detail = ' {0:N1} MiB' -f ($Progress.Completed / 1MB)
        if ($Progress.Finished) {
            $bar = '=' * $barWidth; $detail += ' done'
        }
    }
    $titleWidth = [Math]::Max(0, $width - $barWidth - $detail.Length - 5)
    $title = $Progress.Stage
    if ($title.Length -gt $titleWidth) {
        $title = $title.Substring(0, $titleWidth)
    }
    if (-not [Console]::IsOutputRedirected) {
        Write-Host "`r" -NoNewline
    }
    Write-UdkConsoleText ($title + ' [') Text -NoNewline
    Write-UdkConsoleText $bar Progress -NoNewline
    Write-UdkConsoleText (']' + $detail) Text -NoNewline
    $lineLength = $title.Length + $barWidth + $detail.Length + 3
    if ($State.Length -gt $lineLength) {
        Write-Host (' ' * ($State.Length - $lineLength)) -NoNewline
    }
    $State.Length = $lineLength
    $State.Open = -not $Progress.Finished -and -not [Console]::IsOutputRedirected
    if ($Progress.Finished -or [Console]::IsOutputRedirected) {
        Write-Host ''; $State.Length = 0
    }
}

function Invoke-UdkConsoleProgress {
    param([scriptblock]$Action)

    # Состояние индикатора принадлежит одной операции; при ошибке завершаем его строку.
    $state = @{ Stage = ''; Frame = 0; Length = 0; Open = $false }
    $callback = {
        param($Progress)
        Module.Udk.Console\Write-UdkConsoleProgress -Progress $Progress -State $state
    }.GetNewClosure()
    $previousPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { & $Action $callback }
    finally {
        if ($state.Open) {
            Write-Host ''
        }
        $ProgressPreference = $previousPreference
    }
}