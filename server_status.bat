@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20) - Статус
rem  Файл: server_status.bat
rem
rem  Показывает:
rem    - найден ли MySQL
rem    - размер баз auth / characters / world / hotfixes
rem    - слушаются ли порты 1119 (bnet), 8085/8086 (world), 3306
rem    - запущены ли процессы
rem ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "TOOLS_DIR=%ROOT%\tools"
set "MYSQL_CNF=%TOOLS_DIR%\mysql.cnf"

title LEGIONFORGE 7.3.5.26124 - Статус сервера
color 0B

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 (2026-10-20) - статус сервера
echo  =========================================================
echo.

set "MYSQL="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\find_mysql.ps1" -Port 3306`) do set "MYSQL=%%P"

if exist "%MYSQL%" (
    echo  [OK] MySQL найден: !MYSQL!
) else (
    echo  [ОШИБКА] MySQL не найден или не запущен.
)

if exist "%MYSQL_CNF%" (
    echo  [OK] Файл подключения к MySQL: !MYSQL_CNF!
) else (
    echo  [ОШИБКА] Файл подключения не найден, запустите setup.bat.
)

echo.
echo  [*] Порты:
call :SHOWPORT 1119 "bnetserver (вход в игру)"
call :SHOWPORT 8085 "worldserver (игровой)"
call :SHOWPORT 8086 "worldserver (socket)"
call :SHOWPORT 3306 "MySQL"

echo.
echo  [*] Процессы:
tasklist /FI "IMAGENAME eq worldserver.exe" 2>nul | findstr /I "worldserver.exe" >nul && echo  [OK] worldserver.exe запущен. || echo  [-] worldserver.exe не запущен.
tasklist /FI "IMAGENAME eq bnetserver.exe" 2>nul | findstr /I "bnetserver.exe" >nul && echo  [OK] bnetserver.exe запущен.  || echo  [-] bnetserver.exe не запущен.

echo.
if exist "%MYSQL_CNF%" (
    echo  [*] Сводка по базам данных:
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\server_status.ps1" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
)

echo.
pause
exit /b 0

:SHOWPORT
netstat -ano -p tcp | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo  [OK] %~1 слушается - %~2
) else (
    echo  [X]  %~1 не слушается - %~2
)
exit /b 0
