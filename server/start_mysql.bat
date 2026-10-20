@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20) - Запуск MySQL
rem  Запуск ПОРТАТИВНОГО MySQL из tools\mysql. Системный MySQL
rem  не затрагивается. Файл подключения: tools\mysql.cnf.
rem ============================================================

title LEGIONFORGE - Запуск MySQL
echo.
echo  [*] Проверка MySQL на порту 3306...

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MYSQL_CNF=%ROOT%\tools\mysql.cnf"
set "MYSQL="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\find_mysql.ps1" -Port 3306 -EnsureRunning 2^>nul`) do set "MYSQL=%%P"

if not defined MYSQL (
    echo  [ОШИБКА] MySQL не найден и не удалось запустить.
    echo      Выполните сначала setup.bat (он скачает и поднимет
    echo      портативный MySQL в tools\mysql^).
    pause
    exit /b 1
)
if not exist "%MYSQL%" (
    echo  [ОШИБКА] mysql.exe не найден: !MYSQL!
    pause
    exit /b 1
)

if exist "%MYSQL_CNF%" (
    "%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -Nse "SELECT 1" >nul 2>&1
    if errorlevel 1 (
        echo  [ОШИБКА] MySQL запущен, но учётная запись root/legionforge не подошла.
        echo      Выполните setup.bat - он спросит пароль и обновит tools\mysql.cnf.
        pause
        exit /b 1
    )
)

echo  [OK] MySQL работает на 127.0.0.1:3306.
echo      Клиент: %MYSQL%
echo.
pause
exit /b 0
