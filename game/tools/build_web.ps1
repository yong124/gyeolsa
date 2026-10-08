# 결사(광복 IF) 웹 빌드 (itch.io용)
# 사용법 (프로젝트 루트 G:\Git\결사 에서):
#   powershell -ExecutionPolicy Bypass -File game\tools\build_web.ps1
# 준비: Godot 4.7.1 익스포트 템플릿 설치 (에디터 > 내보내기 템플릿 관리 > 다운로드 및 설치)
# 결과: build\web\ (index.html이 맨 위) 과 build\GwangbokIF_web_v<버전>.zip

param(
    [string]$Godot = "E:\Godot\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Version = "2.0.0",
    [switch]$SkipTests
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8   # Godot 출력(한글)을 UTF-8로 읽는다
$ErrorActionPreference = "Continue"   # Godot가 stderr로 내는 정상 경고(시험이 일부러 내는 오류 포함)에 멈추지 않게. 실패는 아래에서 직접 throw
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # G:\Git\결사
$game = Join-Path $root "game"
$out = Join-Path $root "build\web"
$zip = Join-Path $root "build\GwangbokIF_web_v${Version}.zip"

if (-not $SkipTests) {
    Write-Host "1/4 v2 시험"
    foreach ($t in @("v2_data_test", "v2_engine_test", "v2_mechanics_test", "v2_ai_test")) {
        $log = & $Godot --headless --path $game --script "res://tests/$t.gd" 2>&1
        if ($LASTEXITCODE -ne 0 -or ($log -match "실패 [1-9]")) { throw "시험 실패: $t`n$log" }
        Write-Host "   통과: $t"
    }
    $log = & $Godot --headless --path $game -- v2uitest 1 2>&1
    if (-not ($log -match "v2 화면 시험: 통과")) { throw "화면 시험 실패`n$log" }
    Write-Host "   통과: v2 화면 시험"
}

Write-Host "2/4 웹 내보내기 (스레드 없음: itch.io에서 별도 헤더 없이 돔)"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $game --export-release "Web" (Join-Path $out "index.html")
if (-not (Test-Path (Join-Path $out "index.html"))) { throw "내보내기 실패 (웹 익스포트 템플릿이 설치되어 있는지 확인)" }

Write-Host "3/4 크기"
$total = 0
Get-ChildItem $out | ForEach-Object {
    $total += $_.Length
    Write-Host ("   {0,-28} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB))
}
Write-Host ("   합계 {0:N1} MB (목표 30 MB 안)" -f ($total / 1MB))

Write-Host "4/4 압축 (index.html이 zip 맨 위)"
Copy-Item (Join-Path $game "CREDITS.md") (Join-Path $out "CREDITS.txt")
Copy-Item (Join-Path $game "assets\fonts\OFL.txt") (Join-Path $out "OFL.txt")
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Write-Host "완료: $zip"
Write-Host "로컬에서 열어 보기: python -m http.server 8060 --directory build\web  → http://localhost:8060"
