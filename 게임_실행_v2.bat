@echo off
chcp 65001 >nul
rem 광복 IF 새 규칙 v2 (시험판): 메뉴를 건너뛰고 v2 요원 고르기 화면으로 바로 들어갑니다.

set "GODOT=E:\Godot\Godot_v4.7.1-stable_win64.exe"

if not exist "%GODOT%" (
    echo Godot 4.7.1을 찾을 수 없습니다: %GODOT%
    echo 이 파일을 메모장으로 열어 GODOT 경로를 고쳐 주세요.
    pause
    exit /b 1
)

start "" "%GODOT%" --path "%~dp0game" -- v2
