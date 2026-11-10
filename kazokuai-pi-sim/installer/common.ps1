$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AppName = "かぞくAI 電話機"
$InstallDir = Join-Path $env:LOCALAPPDATA "KazokuAI"
$SecretEnv = Join-Path $InstallDir "secret\.env"

$SecretFields = @(
    @{ Name = "KAZOKUAI_BACKEND"; Label = "サーバーの URL(Cloud Run)"; Masked = $false },
    @{ Name = "PHONE_SECRET"; Label = "合言葉(シークレット)"; Masked = $true }
)

function Test-DockerRunning {
    $ErrorActionPreference = "Continue"
    docker info 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Read-SecretEnv {
    $values = @{}
    if (Test-Path $SecretEnv) {
        foreach ($line in [System.IO.File]::ReadAllLines($SecretEnv)) {
            $i = $line.IndexOf("=")
            if ($i -gt 0) {
                $values[$line.Substring(0, $i)] = $line.Substring($i + 1)
            }
        }
    }
    return $values
}

function Write-SecretEnv($values) {
    New-Item -ItemType Directory -Force (Split-Path $SecretEnv) | Out-Null
    $lines = @()
    foreach ($key in $values.Keys) {
        if ($values[$key]) {
            $lines += "$key=$($values[$key])"
        }
    }
    $text = ($lines -join "`n")
    if ($text) { $text += "`n" }
    [System.IO.File]::WriteAllText($SecretEnv, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Show-SecretDialog($current) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$AppName の設定"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10)
    $form.ClientSize = New-Object System.Drawing.Size(520, (150 + 60 * $SecretFields.Count))

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "本番の動き(サーバーにつないで電話を受ける)に使います。`n空欄のままでも、電話機の部品の確認はできます。"
    $note.Location = New-Object System.Drawing.Point(16, 12)
    $note.Size = New-Object System.Drawing.Size(490, 44)
    $form.Controls.Add($note)

    $boxes = @{}
    $y = 66
    foreach ($field in $SecretFields) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $field.Label
        $label.Location = New-Object System.Drawing.Point(16, $y)
        $label.AutoSize = $true
        $form.Controls.Add($label)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(16, ($y + 22))
        $box.Size = New-Object System.Drawing.Size(488, 26)
        $box.UseSystemPasswordChar = $field.Masked
        if ($current.ContainsKey($field.Name)) { $box.Text = $current[$field.Name] }
        $form.Controls.Add($box)
        $boxes[$field.Name] = $box
        $y += 60
    }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "保存"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(318, ($y + 14))
    $ok.Size = New-Object System.Drawing.Size(90, 32)
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $skip = New-Object System.Windows.Forms.Button
    $skip.Text = "あとで"
    $skip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $skip.Location = New-Object System.Drawing.Point(414, ($y + 14))
    $skip.Size = New-Object System.Drawing.Size(90, 32)
    $form.Controls.Add($skip)
    $form.CancelButton = $skip

    $form.Topmost = $true
    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $values = @{}
    foreach ($key in $current.Keys) { $values[$key] = $current[$key] }
    foreach ($field in $SecretFields) { $values[$field.Name] = $boxes[$field.Name].Text.Trim() }
    return $values
}

function Restart-Device {
    $ErrorActionPreference = "Continue"
    docker exec kazokuai-pi systemctl restart kazokuai-device 2>$null | Out-Null
}

function New-Shortcut($name, $script, $description) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "$name.lnk"))
    $lnk.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $lnk.WorkingDirectory = $InstallDir
    $lnk.Description = $description
    $lnk.IconLocation = Join-Path $env:SystemRoot "System32\shell32.dll,197"
    $lnk.Save()
}
