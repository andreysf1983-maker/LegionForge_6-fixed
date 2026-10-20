@echo off
rem LEGIONFORGE 7.3.5.26124 - extract game data (dbc/maps/vmaps/mmaps) from the WoW client.
rem Usage: extract_data.bat [/auto] [/nommaps]
chcp 65001 >nul 2>&1
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "AUTO="
set "EXTRA="
for %%A in (%*) do (
    if /i "%%~A"=="/auto" set "AUTO=1"
    if /i "%%~A"=="/nommaps" set "EXTRA=-SkipMMaps"
)
title LEGIONFORGE 7.3.5.26124 - Извлечение игровых данных
echo.
echo  [*] Извлечение игровых данных из клиента WoW 7.3.5 (26124) в server\data
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\extract_data.ps1" -Root "%ROOT%" %EXTRA%
set "RC=%errorlevel%"
if not "%RC%"=="0" echo  [ОШИБКА] Извлечение данных не удалось - см. сообщения выше.
if "%RC%"=="0" echo  [OK] Данные извлечены.
if not defined AUTO pause
exit /b %RC%
