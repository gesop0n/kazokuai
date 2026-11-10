param(
    [string]$User = "tana",
    [string]$Name = "kazokuai-pi"
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:WSL_UTF8 = "1"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-Distros {
    (wsl.exe -l -q) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Host "==> WSL を確かめます"
wsl.exe --status | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WSL が入っていません。管理者の PowerShell で 'wsl --install' を実行し、再起動してから、もう一度動かしてください。"
    exit 1
}

if ((Get-Distros) -notcontains $Name) {
    Write-Host "==> Debian を $Name という名前で入れます"
    wsl.exe --install Debian --name $Name --no-launch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "入れられませんでした。'wsl --update' で WSL を新しくしてから、もう一度動かしてください(--name には WSL 2.4.4 以降が要ります)。"
        exit 1
    }
} else {
    Write-Host "==> $Name はもうあります。設定だけやり直します"
}

wsl.exe -d $Name -u root -e true 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> $Name が root で起動できないので、止めてからやり直します"
    wsl.exe --terminate $Name | Out-Null
    Start-Sleep -Seconds 3
    wsl.exe -d $Name -u root -e true
    if ($LASTEXITCODE -ne 0) {
        Write-Host @"
$Name を root で起動できません。中身はまだ空なので、消して入れ直してください:
  wsl --unregister $Name
  powershell -ExecutionPolicy Bypass -File .\install.ps1
"@
        exit 1
    }
}

Write-Host "==> Debian の中を用意します(数分かかります)"
$linuxDir = wsl.exe -d $Name -u root -e wslpath -a ($here -replace '\\', '/')
if (-not $linuxDir) {
    Write-Host "フォルダーの場所を Debian の中のパスに直せませんでした: $here"
    exit 1
}
$linuxDir = "$linuxDir".Trim()
wsl.exe -d $Name -u root -e bash "$linuxDir/setup.sh" $User
if ($LASTEXITCODE -ne 0) {
    Write-Host "setup.sh が失敗しました。上のメッセージを見てください。"
    exit 1
}

Write-Host "==> WSL を止めて、systemd で起動し直します"
wsl.exe --terminate $Name
wsl.exe -d $Name -u root -- systemctl is-active pisim | Out-Null

Write-Host "==> デスクトップにショートカットを作ります"
$wslg = Join-Path $env:ProgramFiles "WSL\wslg.exe"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "かぞくAI 電話機.lnk"))
$lnk.Arguments = "-d $Name --cd ~ -- kazokuai-phone"
if (Test-Path $wslg) {
    $lnk.TargetPath = $wslg
} else {
    $lnk.TargetPath = "wsl.exe"
    $lnk.WindowStyle = 7
}
$lnk.Save()

Write-Host @"

できました。
  電話機の画面:   デスクトップの「かぞくAI 電話機」
  電話機のシェル: Windows Terminal の "$Name"、または  wsl -d $Name
  ファイルを置く: エクスプローラーで  \\wsl.localhost\$Name\home\$User
                  または  scp -P 2222 ファイル $User@localhost:~/
"@
