$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Test-Docker {
    $ErrorActionPreference = "Continue"
    docker info 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

if (-not (Test-Docker)) {
    Write-Host "Docker が動いていません。Docker Desktop を起動して、左下が「Engine running」になってから、もう一度実行してください。"
    exit 1
}
New-Item -ItemType Directory -Force share, secret | Out-Null
$secretEnv = Join-Path $PSScriptRoot "secret\.env"
if (-not (Test-Path $secretEnv)) {
    [System.IO.File]::WriteAllText($secretEnv, "")
    Write-Host "==> kazokuai-device の設定ファイルを空で作りました: $secretEnv"
}

Write-Host "==> 電話機を起動します(初回はイメージを作るので数分かかります)"
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { exit 1 }

$ErrorActionPreference = "Continue"
Write-Host "==> 電話機の中を待っています"
for ($i = 0; $i -lt 60; $i++) {
    $state = (docker exec kazokuai-pi systemctl is-system-running 2>$null)
    if ($state -match "running|degraded") { break }
    Start-Sleep -Seconds 2
}

$wifi = (docker exec kazokuai-pi systemctl is-active pisim-wifi-module 2>$null)
if ($wifi -ne "active") {
    Write-Host "==> 電話機の無線(wlan0)のモジュールを作っています。初回だけ 10 分ほどかかります。"
    Write-Host "    様子:  docker exec kazokuai-pi journalctl -fu pisim-wifi-module"
}

Write-Host @"

起動しました。電話機の画面が開きます。
  電話機のシェル: .\pi.ps1
  ファイルを置く: このフォルダーの share(電話機では ~/share)
  止める:         docker compose down

kazokuai-device は、secret\.env に値を書くと動き出します(空のあいだは止まっています)。
  書いたら:       docker exec kazokuai-pi systemctl restart kazokuai-device
  様子を見る:     docker exec kazokuai-pi journalctl -fu kazokuai-device
"@
