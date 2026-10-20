@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20) - Остановка
rem  Файл: stop_server.bat
rem
rem  Останавливает корректно все процессы сервера:
rem    worldserver.exe, bnetserver.exe и ПОРТАТИВНЫЙ MySQL
rem    (mysqld.exe из tools\mysql). Системный MySQL Windows
rem    НЕ трогается никогда.
rem
rem  Порядок:
rem    1) мирный shutdown (WM_CLOSE / mysqladmin shutdown),
rem       чтобы InnoDB корректно сбросил данные;
rem    2) если не помогло - taskkill /F /T;
rem    3) если не помогло - убийство по PID.
rem
rem  ВАЖНО: перед остановкой в консоли worldserver выполните
rem  .saveall, если есть незавершённые изменения.
rem ============================================================

title LEGIONFORGE 7.3.5.26124 (2026-10-20) - Остановка
color 0C

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "TOOLS_DIR=%ROOT%\tools"
set "TMP_DIR=%TOOLS_DIR%\setup_tmp"
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%" >nul 2>&1
set "LOG=%TMP_DIR%\stop_server.log"

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 (2026-10-20) - Остановка
echo  =========================================================
echo.

set "FOUND=0"
set "STUCK=0"

:: ------------------------------------------------------------- Игры
call :StopProcess "worldserver.exe" "worldserver (мир)"
call :StopProcess "bnetserver.exe"  "bnetserver (вход)"

:: ------------------------------------------------------------- MySQL
:: Сначала "красивый" shutdown через mysqladmin - это безопасно
:: для InnoDB. Убиваем только портативный MySQL из tools\mysql.
call :ShutdownMySqlGracefully
call :StopPortableMySql

echo.
if "!FOUND!"=="0" (
    echo  [OK] Процессы сервера и так не запущены.
) else if "!STUCK!"=="0" (
    echo  [OK] Все процессы LEGIONFORGE остановлены.
) else (
    echo  [ОШИБКА] Не удалось остановить !STUCK! процесс^(ов^).
    echo           Завершите их вручную в диспетчере задач.
    echo           Лог: %LOG%
)

echo.
pause
exit /b 0


:: ============================================================
::  :StopProcess <имя.exe> <описание>
::  Останавливает процесс: сначала мирно (WM_CLOSE), затем /F /T,
::  в последнюю очередь по PID (покрывает чужие пути/пробелы).
:: ============================================================
:StopProcess
set "PROC=%~1"
set "DESC=%~2"

tasklist /FI "IMAGENAME eq %PROC%" /NH 2>nul | findstr /I /C:"%PROC%" >nul
if errorlevel 1 exit /b 0

set "FOUND=1"
echo  [*] Останавливаю %DESC%...
>>"%LOG%" echo [%DATE% %TIME%] stopping %PROC%

:: 1) мирное закрытие - сервер сам сохранит персонажей
taskkill /IM "%PROC%" /T >nul 2>&1
call :WaitGone "%PROC%" 15
if "!GONE!"=="1" (
    echo  [OK] %DESC% остановлен мирно.
    >>"%LOG%" echo [%DATE% %TIME%] %PROC% stopped gracefully
    exit /b 0
)

:: 2) принудительное завершение вместе с дочерними
echo  [*] %DESC% не закрылся - принудительное завершение...
taskkill /IM "%PROC%" /F /T >nul 2>&1
call :WaitGone "%PROC%" 10
if "!GONE!"=="1" (
    echo  [OK] %DESC% завершён принудительно.
    >>"%LOG%" echo [%DATE% %TIME%] %PROC% killed
    exit /b 0
)

:: 3) в последнюю очередь - по PID (покрывает запуск с путём/пробелами)
for /f "tokens=2 delims=," %%P in ('tasklist /FI "IMAGENAME eq %PROC%" /NH /FO CSV 2^>nul') do (
    set "PID=%%~P"
    taskkill /PID !PID! /F /T >nul 2>&1
)
call :WaitGone "%PROC%" 10
if "!GONE!"=="1" (
    echo  [OK] %DESC% остановлен ^(по PID^).
    >>"%LOG%" echo [%DATE% %TIME%] %PROC% killed by pid
    exit /b 0
)

set /a STUCK+=1
echo  [ОШИБКА] %DESC% ^(%PROC%^) не удалось остановить.
>>"%LOG%" echo [%DATE% %TIME%] FAILED to stop %PROC%
exit /b 0


:: ============================================================
::  :WaitGone <имя.exe> <секунд> -> GONE=0|1
:: ============================================================
:WaitGone
set "GONE=0"
set "WP=%~1"
set /a WN=%~2
for /l %%I in (1,1,!WN!) do (
    if "!GONE!"=="0" (
        tasklist /FI "IMAGENAME eq !WP!" /NH 2>nul | findstr /I /C:"!WP!" >nul
        if errorlevel 1 (
            set "GONE=1"
        ) else (
            >nul ping -n 2 127.0.0.1
        )
    )
)
exit /b 0


:: ============================================================
::  :ShutdownMySqlGracefully
::  Красивая остановка портативного MySQL через mysqladmin,
::  чтобы не было проблем с InnoDB. Только портативный сервер:
::  mysqladmin берётся из tools\mysql, креды - legionforge.
:: ============================================================
:ShutdownMySqlGracefully
set "MYSQLADMIN="
if exist "%TOOLS_DIR%\mysql\server\bin\mysqladmin.exe" set "MYSQLADMIN=%TOOLS_DIR%\mysql\server\bin\mysqladmin.exe"
if not defined MYSQLADMIN exit /b 0

tasklist /FI "IMAGENAME eq mysqld.exe" /NH 2>nul | findstr /I /C:"mysqld.exe" >nul
if errorlevel 1 (
    tasklist /FI "IMAGENAME eq mscld.exe" /NH 2>nul | findstr /I /C:"mscld.exe" >nul
    if errorlevel 1 exit /b 0
)

echo  [*] Красивый shutdown MySQL ^(mysqladmin shutdown^)...
"%MYSQLADMIN%" --protocol=TCP -h 127.0.0.1 -P 3306 -u admin@legionforge.ru --password=legionforge shutdown >>"%LOG%" 2>&1
if errorlevel 1 (
    "%MYSQLADMIN%" --protocol=TCP -h 127.0.0.1 -P 3306 -u root --password=legionforge shutdown >>"%LOG%" 2>&1
)
>nul ping -n 5 127.0.0.1
exit /b 0


:: ============================================================
::  :StopPortableMySql
::  Если после mysqladmin живой остался только ПОРТАТИВНЫЙ
::  mysqld из tools\mysql - завершаем его. Системные MySQL
::  (другие пути) не трогаем.
:: ============================================================
:StopPortableMySql
set "PORTABLE_PID="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "Get-Process -Name mysqld,mscld -ErrorAction SilentlyContinue ^| Where-Object { try { $_.Path -and $_.Path -like '%\tools\mysql\*' } catch { $false } } ^| Select-Object -ExpandProperty Id"`) do set "PORTABLE_PID=%%P"

if not defined PORTABLE_PID (
    tasklist /FI "IMAGENAME eq mysqld.exe" /NH 2>nul | findstr /I /C:"mysqld.exe" >nul
    if errorlevel 1 (
        tasklist /FI "IMAGENAME eq mscld.exe" /NH 2>nul | findstr /I /C:"mscld.exe" >nul
        if errorlevel 1 exit /b 0
    )
)

if defined PORTABLE_PID (
    echo  [*] Останавливаю портативный MySQL ^(PID !PORTABLE_PID!^)...
    set "FOUND=1"
    taskkill /PID !PORTABLE_PID! /F >nul 2>&1
    >>"%LOG%" echo [%DATE% %TIME%] portable mysqld killed PID !PORTABLE_PID!
    echo  [OK] Портативный MySQL остановлен.
) else (
    :: mysqld живёт, но не наш (системный) - не трогаем
    tasklist /FI "IMAGENAME eq mysqld.exe" /NH 2>nul | findstr /I /C:"mysqld.exe" >nul
    if not errorlevel 1 echo  [i] Найден НЕ портативный MySQL (системный) - оставлен работать.
)
exit /b 0
