. (Join-Path $PSScriptRoot "common.ps1")

$values = Show-SecretDialog (Read-SecretEnv)
if (-not $values) { exit 0 }

Write-SecretEnv $values
Restart-Device
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("保存しました。電話機が動いていれば、新しい設定で動き直します。", "$AppName の設定") | Out-Null
