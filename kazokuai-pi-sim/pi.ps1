Set-Location $PSScriptRoot
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$shellArgs = @("-l")
if ($args.Count -gt 0) {
    $shellArgs += @("-c", "$args")
}
docker exec -it -u tana -w /home/tana kazokuai-pi /usr/local/bin/pisim-shell @shellArgs
