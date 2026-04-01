## Play a notification sound on Windows (used by notification cascade)
## Called from WSL via: powershell.exe -File win-play.ps1 -SoundPath "C:\path\to\sound.mp3"

param([string]$SoundPath)
Add-Type -AssemblyName PresentationCore
$player = New-Object System.Windows.Media.MediaPlayer
$player.Open([Uri]::new($SoundPath))
$player.Play()
Start-Sleep -Milliseconds 3000
$player.Close()
