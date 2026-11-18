# สร้างไฟล์ embedded_assets.res สำหรับคอมไพล์ transmission_laz.exe แบบ Single-EXE (พกพาไฟล์เดียวจบ)
$ErrorActionPreference = "Stop"
$LazDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $LazDir
$EmbDir = Join-Path $LazDir "embedded"

$DaemonExe = Join-Path $RepoDir "build-static\daemon\transmission-daemon.exe"
if (-not (Test-Path $DaemonExe)) { $DaemonExe = Join-Path $RepoDir "build\daemon\transmission-daemon.exe" }
$CreateExe = Join-Path $RepoDir "build-static\utils\transmission-create.exe"
if (-not (Test-Path $CreateExe)) { $CreateExe = Join-Path $RepoDir "build\utils\transmission-create.exe" }
$WebUiHtml = Join-Path $LazDir "web_ui\index.html"

New-Item -ItemType Directory -Path $EmbDir -Force | Out-Null

python -c @"
import zlib, os
pairs = [
    (r'$DaemonExe', r'$(Join-Path $EmbDir "daemon.z")'),
    (r'$CreateExe', r'$(Join-Path $EmbDir "create.z")'),
    (r'$WebUiHtml', r'$(Join-Path $EmbDir "webui.z")'),
]
for src, dst in pairs:
    raw = open(src, 'rb').read()
    comp = zlib.compress(raw, 9)
    open(dst, 'wb').write(comp)
    print(f'{os.path.basename(dst)}: {len(raw):,} -> {len(comp):,} bytes')
"@

@"
TR_DAEMON_Z RCDATA "embedded/daemon.z"
TR_CREATE_Z RCDATA "embedded/create.z"
TR_WEBUI_Z  RCDATA "embedded/webui.z"
"@ | Set-Content -Path (Join-Path $LazDir "embedded_assets.rc") -Encoding ASCII

$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
Push-Location $LazDir
try {
    & "C:\msys64\ucrt64\bin\windres.exe" -i "embedded_assets.rc" -o "embedded_assets.res" -O coff
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
Write-Host "Built embedded_assets.res cleanly!"
