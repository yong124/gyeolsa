# 결사 온라인 서버 빌드 (리눅스 헤드리스) → build\server\ 에 Dockerfile · fly.toml과 함께 둔다
# 사용법 (프로젝트 루트에서): powershell -ExecutionPolicy Bypass -File game\tools\build_server.ps1
# 배포: build\server 폴더에서 `fly deploy` (v2_구현/서버_배포.md)
param([string]$Godot = "E:\Godot\Godot_v4.7.1-stable_win64_console.exe")
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$game = Join-Path $root "game"
$out = Join-Path $root "build\server"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $game --export-release "Linux Server" (Join-Path $out "gyeolsa_server.x86_64")
if (-not (Test-Path (Join-Path $out "gyeolsa_server.x86_64"))) { throw "서버 내보내기 실패 (리눅스 익스포트 템플릿 확인)" }
Copy-Item (Join-Path $root "deploy\server\Dockerfile") $out
Copy-Item (Join-Path $root "deploy\server\fly.toml") $out
Get-ChildItem $out | ForEach-Object { Write-Host ("   {0,-28} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB)) }
Write-Host "완료: $out  (배포: cd build\server; fly deploy)"
