@echo off
chcp 65001 >nul
rem 광복 IF 실행: 이 파일을 더블클릭하면 Godot 4.7.1로 game 폴더의 게임을 켭니다.
rem 에디터로 열려면: 게임_실행.bat editor

set "GODOT=E:\Godot\Godot_v4.7.1-stable_win64.exe"

if not exist "%GODOT%" (
    echo Godot 4.7.1을 찾을 수 없습니다: %GODOT%
    echo 이 파일을 메모장으로 열어 GODOT 경로를 고쳐 주세요.
    pause
    exit /b 1
)

if /i "%~1"=="editor" (
    start "" "%GODOT%" --editor --path "%~dp0game"
) else (
    start "" "%GODOT%" --path "%~dp0game"
)
