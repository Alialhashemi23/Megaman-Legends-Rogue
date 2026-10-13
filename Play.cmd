@echo off
cd /d "%~dp0"
if not exist "tools\Godot_v4.7.1-stable_win64.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup-runtime.ps1"
if not exist "tools\Godot_v4.7.1-stable_win64.exe" exit /b 1
start "Relic Diver" "tools\Godot_v4.7.1-stable_win64.exe" --path "%~dp0."
