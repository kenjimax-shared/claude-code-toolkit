param([string]$SoundPath)
Add-Type -AssemblyName PresentationCore
$player = New-Object System.Windows.Media.MediaPlayer
$player.Open([Uri]::new($SoundPath))
$player.Play()
Start-Sleep -Milliseconds 3000
$player.Close()
