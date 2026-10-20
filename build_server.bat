@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion
title LEGIONFORGE 7.3.5.26124 (2026-10-20) - Сборка сервера
rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20) - сборка из core\.
rem  Все зависимости скачиваются сами в папку tools\: CMake,
rem  Boost, OpenSSL, MySQL. Если компилятора нет, скачается
rem  Visual Studio 2022 Build Tools (нужны права администратора
rem  и интернет; единственный системный шаг).
rem  /auto - тихий режим (вызывается из setup.bat)
rem ============================================================
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "AUTO="
if /I "%~1"=="/auto" set "AUTO=1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\build_server.ps1" -Root "%ROOT%"
if errorlevel 1 (
    echo.
    echo  [ОШИБКА] Сборка не удалась. Подробности: %ROOT%\build_log.txt
    if not defined AUTO pause
    exit /b 1
)
echo.
echo  [OK] Сборка завершена: бинарники скопированы в папку server\.
if not defined AUTO pause
exit /b 0
