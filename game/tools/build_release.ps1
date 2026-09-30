# 광복 IF Windows 출시 빌드
# 사용법 (프로젝트 루트 G:\Git\결사 에서):
#   powershell -ExecutionPolicy Bypass -File game\tools\build_release.ps1
# 준비: Godot 4.7.1 익스포트 템플릿 설치 (에디터 > 내보내기 템플릿 관리 > 다운로드 및 설치)

param(
    [string]$Godot = "E:\Godot\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Version = "1.1.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # G:\Git\결사
$game = Join-Path $root "game"
$out = Join-Path $root "build\GwangbokIF"
$zip = Join-Path $root "build\GwangbokIF_v${Version}_win64.zip"

Write-Host "1/4 테스트 실행"
foreach ($t in @("data_test", "sim_test", "faction_test", "save_test", "path_test", "tutorial_test")) {
    & $Godot --headless --path $game --script "res://tests/$t.gd" -- 100 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "테스트 실패: $t" }
    Write-Host "   통과: $t"
}

Write-Host "2/4 Windows 내보내기"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $game --export-release "Windows Desktop" (Join-Path $out "GwangbokIF.exe")
if (-not (Test-Path (Join-Path $out "GwangbokIF.exe"))) { throw "내보내기 실패 (익스포트 템플릿이 설치되어 있는지 확인)" }

Write-Host "3/4 실행 파일 확인 (AI 자동 진행 한 판)"
$log = & (Join-Path $out "GwangbokIF.exe") --headless --fixed-fps 30 --quit-after 80000 -- autostart autoplay 2>&1
if (-not ($log -match "화면=엔딩")) { throw "실행 파일로 한 판을 끝까지 진행하지 못함`n$log" }

Write-Host "4/4 압축"
Copy-Item (Join-Path $game "CREDITS.md") (Join-Path $out "CREDITS.txt")
Copy-Item (Join-Path $game "assets\fonts\OFL.txt") (Join-Path $out "글꼴_라이선스_OFL.txt")
Copy-Item (Join-Path $root "release\README_플레이어.txt") (Join-Path $out "읽어주세요.txt")
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Write-Host "완료: $zip"
