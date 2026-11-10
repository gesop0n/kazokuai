. (Join-Path $PSScriptRoot "common.ps1")
Add-Type -AssemblyName System.Windows.Forms

$answer = [System.Windows.Forms.MessageBox]::Show(
    "$AppName をアンインストールしますか?`n電話機の中身(ホームのファイル、電話機の ID)も消えます。",
    "$AppName のアンインストール", "YesNo", "Question")
if ($answer -ne "Yes") { exit 0 }

$keepSecret = [System.Windows.Forms.MessageBox]::Show(
    "サーバーの URL とシークレットの設定を残しますか?`n(もう一度インストールしたときに、そのまま使えます)",
    "$AppName のアンインストール", "YesNo", "Question")

if (Test-DockerRunning) {
    Write-Host "==> 電話機を止めて消します"
    $ErrorActionPreference = "Continue"
    Push-Location $InstallDir
    docker compose down -v --rmi local 2>&1 | Out-Host
    Pop-Location
    $ErrorActionPreference = "Stop"
} else {
    Write-Host "Docker Desktop が動いていないので、電話機の中身は消せませんでした。あとで次を実行してください:"
    Write-Host "  docker rm -f kazokuai-pi; docker volume rm kazokuai-pi_pi-home kazokuai-pi_pi-state kazokuai-pi_pi-cache kazokuai-pi_pi-modules; docker image rm kazokuai-pi-sim:latest"
}

$desktop = [Environment]::GetFolderPath("Desktop")
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $desktop "$AppName.lnk"), (Join-Path $desktop "$AppName の設定.lnk")

$backup = $null
if ($keepSecret -eq "Yes" -and (Test-Path $SecretEnv)) {
    $backup = [System.IO.File]::ReadAllBytes($SecretEnv)
}
Set-Location $env:TEMP
Remove-Item -Recurse -Force $InstallDir
if ($backup) {
    New-Item -ItemType Directory -Force (Split-Path $SecretEnv) | Out-Null
    [System.IO.File]::WriteAllBytes($SecretEnv, $backup)
    Write-Host "==> 設定だけ残しました: $SecretEnv"
}

Write-Host "==> アンインストールできました"
