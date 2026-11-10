. (Join-Path $PSScriptRoot "common.ps1")
$source = Split-Path -Parent $PSScriptRoot

Write-Host "==> $AppName をインストールします"

if (-not (Test-DockerRunning)) {
    Write-Host @"

Docker Desktop が動いていません。
  1. Docker Desktop を入れていなければ、https://www.docker.com/products/docker-desktop/ から入れる
  2. Docker Desktop を起動し、左下が「Engine running」になるまで待つ
  3. もう一度「インストール.cmd」をダブルクリックする
"@
    exit 1
}

Write-Host "==> $InstallDir にコピーします"
New-Item -ItemType Directory -Force $InstallDir | Out-Null
robocopy $source $InstallDir /E /NFL /NDL /NJH /NJS /NP /XD share secret __pycache__ | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Host "コピーに失敗しました(robocopy $LASTEXITCODE)"
    exit 1
}

$current = Read-SecretEnv
$values = Show-SecretDialog $current
if ($values) {
    Write-SecretEnv $values
    Write-Host "==> 設定を保存しました(このパソコンの中だけに置きます): $SecretEnv"
} elseif (-not (Test-Path $SecretEnv)) {
    Write-SecretEnv @{}
    Write-Host "==> 設定はあとで入れられます(デスクトップの「$AppName の設定」)"
}

Write-Host "==> デスクトップにショートカットを作ります"
New-Shortcut $AppName (Join-Path $InstallDir "start.ps1") "電話機を起動する"
New-Shortcut "$AppName の設定" (Join-Path $InstallDir "installer\settings.ps1") "サーバーの URL とシークレットを変える"

Write-Host "==> 電話機を起動します(初回は 25 分ほどかかります)"
& (Join-Path $InstallDir "start.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host @"

インストールできました。
  起動:           デスクトップの「$AppName」
  設定を変える:   デスクトップの「$AppName の設定」
  電話機のシェル: $InstallDir\pi.ps1
  消す:           $InstallDir\アンインストール.cmd
"@
