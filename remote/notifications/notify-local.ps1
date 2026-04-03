# Play notification sound locally ONLY if Windows console is active and unlocked.
# This runs on the Windows side via powershell.exe from WSL.
# Place your notification sound at ~\.claude\notify-sound.mp3

$consoleActive = query session 2>$null | Select-String 'console\s+\S*\s*\d+\s+Active'
$locked = Get-Process LogonUI -ErrorAction SilentlyContinue
if ($consoleActive -and -not $locked) {
    Add-Type -AssemblyName PresentationCore
    $p = New-Object System.Windows.Media.MediaPlayer
    $soundPath = Join-Path $env:USERPROFILE ".claude\notify-sound.mp3"
    $p.Open([uri]"file:///$($soundPath -replace '\\','/')")
    $p.Play()
    Start-Sleep -Milliseconds 2000
    $p.Close()
}
