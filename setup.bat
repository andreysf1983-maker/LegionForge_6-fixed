@echo off
rem ====================================================================
rem  LEGIONFORGE 7.3.5.26124 - installer (setup.bat)
rem  NOTE: this file MUST have Windows CRLF line endings. With LF-only
rem  endings cmd.exe mis-parses lines ("'...' is not recognized as an
rem  internal or external command"). .gitattributes forces CRLF and
rem  UNBLOCK.bat repairs line endings of all .bat files automatically.
rem  Everything above "chcp 65001" is plain ASCII on purpose.
rem ====================================================================
if /i "%LF_SETUP_CONSOLE%"=="LF26124" goto :LF_SETUP_MAIN
set "LF_SETUP_CONSOLE=LF26124"
"%ComSpec%" /d /k call "%~f0" %*
exit /b %errorlevel%

:LF_SETUP_MAIN
chcp 65001 >nul 2>&1
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title LEGIONFORGE 7.3.5.26124 - Установка

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SERVER_DIR=%ROOT%\server"
set "SQL_DIR=%ROOT%\sql"
set "TOOLS_DIR=%ROOT%\tools"
set "TMP_DIR=%TOOLS_DIR%\setup_tmp"
set "MYSQL_CNF=%TOOLS_DIR%\mysql.cnf"
set "PS=powershell -NoLogo -NoProfile -ExecutionPolicy Bypass"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 - Установка
echo  =========================================================
echo   Папка сервера: %ROOT%
echo.

rem ---- 0. Путь без спецсимволов ----
echo "%ROOT%" | findstr /r /c:"[!%%^&]" >nul 2>&1
if errorlevel 1 goto :PATH_OK
echo  [ОШИБКА] В пути к серверу есть символы ! %% ^^ ^& - скрипты cmd.exe с ними не работают.
echo      Переместите папку, например, в D:\LegionForge и запустите снова.
goto :FAIL
:PATH_OK

rem ---- 1. Права администратора (нужны только для Visual Studio Build Tools) ----
net session >nul 2>&1
if not errorlevel 1 goto :ADMIN_OK
echo  [*] Нет прав администратора - запрашиваю повышение (UAC)...
%PS% -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Повышение прав отклонено. Щёлкните setup.bat правой кнопкой -
    echo      "Запуск от имени администратора".
    goto :FAIL
)
echo  [OK] Установка продолжается в новом окне администратора. Это окно можно закрыть.
exit /b 0
:ADMIN_OK
echo  [OK] Права администратора есть.

rem ---- 2. Снять блокировку Windows и починить окончания строк ----
%PS% -File "%ROOT%\scripts\repair_files.ps1" -Root "%ROOT%" -Quiet
if errorlevel 1 echo  [!] repair_files.ps1 сообщил о проблеме - продолжаю.

rem ---- 3. Поиск / загрузка MySQL ----
set "MYSQL="
if exist "%TOOLS_DIR%\mysql\server\bin\mysql.exe" set "MYSQL=%TOOLS_DIR%\mysql\server\bin\mysql.exe"
if defined MYSQL goto :MYSQL_FOUND
netstat -ano -p tcp | findstr /r /c:":3306 .*LISTENING" >nul 2>&1
if errorlevel 1 goto :MYSQL_DOWNLOAD
rem Порт 3306 уже занят системным MySQL - используем его клиент, если он есть.
for /f "delims=" %%P in ('where mysql.exe 2^>nul') do if not defined MYSQL set "MYSQL=%%P"
if defined MYSQL goto :MYSQL_FOUND
:MYSQL_DOWNLOAD
echo  [*] Скачиваю портативный MySQL 8.0 в tools\mysql (около 250 МБ)...
%PS% -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -SevenZip -MySQL
if exist "%TOOLS_DIR%\mysql\server\bin\mysql.exe" set "MYSQL=%TOOLS_DIR%\mysql\server\bin\mysql.exe"
if defined MYSQL goto :MYSQL_FOUND
echo  [ОШИБКА] Не удалось получить mysql.exe.
echo      Проверьте интернет или положите mysql-8.0.46-winx64.zip в tools\downloads.
goto :FAIL
:MYSQL_FOUND
echo  [OK] MySQL: %MYSQL%

rem ---- 4. MySQL слушает порт 3306 ----
netstat -ano -p tcp | findstr /r /c:":3306 .*LISTENING" >nul 2>&1
if not errorlevel 1 goto :MYSQL_UP
if not exist "%TOOLS_DIR%\mysql\server\bin\mysqld.exe" (
    echo  [ОШИБКА] Порт 3306 не слушается, а портативного mysqld.exe нет.
    goto :FAIL
)
echo  [*] Запускаю портативный MySQL...
%PS% -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -MySQL -StartMySQL
netstat -ano -p tcp | findstr /r /c:":3306 .*LISTENING" >nul 2>&1
if not errorlevel 1 goto :MYSQL_UP
echo  [ОШИБКА] MySQL не слушает порт 3306. Смотрите tools\mysql\data\*.err
goto :FAIL
:MYSQL_UP
echo  [OK] MySQL слушает порт 3306.
if exist "%TOOLS_DIR%\mysql\server\bin\mysql.exe" %PS% -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -StartMySQL >nul 2>&1

rem ---- 5. Доступ к MySQL ----
echo.
echo  [*] Проверка доступа к MySQL...
call :WRITE_CNF "%TMP_DIR%\mysql_legionforge.cnf" "admin@legionforge.ru" "legionforge"
"%MYSQL%" --defaults-extra-file="%TMP_DIR%\mysql_legionforge.cnf" -e "SELECT 1" >nul 2>&1
if errorlevel 1 goto :TRY_SAVED
copy /Y "%TMP_DIR%\mysql_legionforge.cnf" "%MYSQL_CNF%" >nul
goto :AUTH_OK
:TRY_SAVED
if not exist "%MYSQL_CNF%" goto :TRY_ROOT
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
:TRY_ROOT
call :WRITE_CNF "%MYSQL_CNF%" "root" ""
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
call :WRITE_CNF "%MYSQL_CNF%" "root" "legionforge"
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
echo  [!] Автоматический вход не удался. На порту 3306 работает другой MySQL.
echo      Введите пароль пользователя root этого MySQL (пусто - Enter):
set "MYSQL_PASS="
set /p "MYSQL_PASS=  Пароль root: "
call :WRITE_CNF "%MYSQL_CNF%" "root" "%MYSQL_PASS%"
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
echo  [ОШИБКА] Не удалось подключиться к MySQL с введённым паролем.
goto :FAIL
:AUTH_OK
echo  [OK] Доступ к MySQL есть.

rem ---- 6. Базы и учётная запись admin@legionforge.ru ----
echo.
echo  [*] Создание баз auth, characters, world, hotfixes и учётной записи...
> "%TMP_DIR%\bootstrap.sql" (
    echo CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8mb4;
    echo CREATE DATABASE IF NOT EXISTS characters DEFAULT CHARACTER SET utf8mb4;
    echo CREATE DATABASE IF NOT EXISTS world DEFAULT CHARACTER SET utf8mb4;
    echo CREATE DATABASE IF NOT EXISTS hotfixes DEFAULT CHARACTER SET utf8mb4;
    echo CREATE USER IF NOT EXISTS 'admin@legionforge.ru'@'localhost' IDENTIFIED WITH mysql_native_password BY 'legionforge';
    echo CREATE USER IF NOT EXISTS 'admin@legionforge.ru'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge';
    echo ALTER USER 'admin@legionforge.ru'@'localhost' IDENTIFIED WITH mysql_native_password BY 'legionforge';
    echo ALTER USER 'admin@legionforge.ru'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge';
    echo GRANT ALL PRIVILEGES ON *.* TO 'admin@legionforge.ru'@'localhost' WITH GRANT OPTION;
    echo GRANT ALL PRIVILEGES ON *.* TO 'admin@legionforge.ru'@'127.0.0.1' WITH GRANT OPTION;
    echo GRANT ALL PRIVILEGES ON auth.* TO 'admin@legionforge.ru'@'localhost';
    echo GRANT ALL PRIVILEGES ON characters.* TO 'admin@legionforge.ru'@'localhost';
    echo GRANT ALL PRIVILEGES ON world.* TO 'admin@legionforge.ru'@'localhost';
    echo GRANT ALL PRIVILEGES ON hotfixes.* TO 'admin@legionforge.ru'@'localhost';
    echo GRANT ALL PRIVILEGES ON auth.* TO 'admin@legionforge.ru'@'127.0.0.1';
    echo GRANT ALL PRIVILEGES ON characters.* TO 'admin@legionforge.ru'@'127.0.0.1';
    echo GRANT ALL PRIVILEGES ON world.* TO 'admin@legionforge.ru'@'127.0.0.1';
    echo GRANT ALL PRIVILEGES ON hotfixes.* TO 'admin@legionforge.ru'@'127.0.0.1';
    echo FLUSH PRIVILEGES;
)
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" < "%TMP_DIR%\bootstrap.sql"
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось создать базы / учётную запись admin@legionforge.ru.
    goto :FAIL
)
rem Старое ядро не совместимо со строгим sql_mode MySQL 8 (ONLY_FULL_GROUP_BY и т.п.).
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SET PERSIST sql_mode='NO_ENGINE_SUBSTITUTION'" >nul 2>&1
if errorlevel 1 "%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SET GLOBAL sql_mode='NO_ENGINE_SUBSTITUTION'" >nul 2>&1
call :WRITE_CNF "%MYSQL_CNF%" "admin@legionforge.ru" "legionforge"
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось войти под admin@legionforge.ru.
    goto :FAIL
)
echo  [OK] Базы готовы, учётная запись MySQL: admin@legionforge.ru / legionforge

rem ---- 7. Импорт баз (только в пустые - данные не затираются) ----
echo.
echo  [*] Импорт баз данных (только пустые)...
call :IMPORT_IF_EMPTY auth "%SQL_DIR%\base\legion_auth.sql"
if errorlevel 1 goto :FAIL
call :IMPORT_IF_EMPTY characters "%SQL_DIR%\base\legion_characters.sql"
if errorlevel 1 goto :FAIL
call :IMPORT_WORLD_IF_EMPTY
if errorlevel 1 goto :FAIL

rem ---- 8. Обновления sql\updates и патчи LegionForge ----
echo.
echo  [*] Обновления из sql\updates (каждое - один раз)...
%PS% -File "%SQL_DIR%\apply_updates.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 goto :FAIL
echo.
echo  [*] Патчи LegionForge: имя мира, союзные расы, мини-боссы, предметы...
%PS% -File "%SQL_DIR%\apply_custom.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 (
    echo  [ОШИБКА] Патчи применились не полностью - см. сообщения выше.
    goto :FAIL
)
%PS% -File "%ROOT%\scripts\ensure_auth_schema.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 echo  [!] ensure_auth_schema.ps1: см. сообщения выше (не критично).

rem ---- 9. Программы сервера (сборка из core\ при отсутствии) ----
echo.
echo  [*] Проверка программ: worldserver.exe, bnetserver.exe
if exist "%SERVER_DIR%\worldserver.exe" if exist "%SERVER_DIR%\bnetserver.exe" goto :BINARIES_OK
echo  [*] Программ нет - автоматическая сборка из core\ (первый раз 30-90 минут).
echo      CMake, Boost, OpenSSL, Visual Studio Build Tools скачаются сами.
call "%ROOT%\build_server.bat" /auto
if errorlevel 1 goto :FAIL
if not exist "%SERVER_DIR%\worldserver.exe" goto :FAIL
if not exist "%SERVER_DIR%\bnetserver.exe" goto :FAIL
:BINARIES_OK
echo  [OK] Программы сервера на месте.

rem ---- 10. Игровые данные (dbc, maps, vmaps, mmaps) ----
echo.
echo  [*] Проверка игровых данных в server\data...
call :HAS_DATA "%SERVER_DIR%\data"
if not errorlevel 1 goto :DATA_OK
for %%D in ("%ROOT%\data" "%ROOT%\client_data" "%ROOT%\..\LegionForge\server\data" "D:\LegionForge\server\data") do (
    call :HAS_DATA "%%~D"
    if not errorlevel 1 (
        echo      Найдены данные: %%~D - копирую...
        xcopy "%%~D\*" "%SERVER_DIR%\data\" /E /I /Y /Q >nul
        goto :DATA_RECHECK
    )
)
echo      Данных нет - извлекаю их из клиента WoW 7.3.5 (extract_data.bat)...
call "%ROOT%\extract_data.bat" /auto
:DATA_RECHECK
call :HAS_DATA "%SERVER_DIR%\data"
if not errorlevel 1 goto :DATA_OK
echo  [ОШИБКА] Игровые данные не найдены и не извлечены.
echo      Запустите extract_data.bat и укажите папку клиента WoW 7.3.5 (26124).
goto :FAIL
:DATA_OK
echo  [OK] Игровые данные на месте.

echo.
echo  =========================================================
echo   Установка завершена. Запуск сервера и клиента: play.bat
echo   Вход в игру: admin@legionforge.ru / legionforge
echo  =========================================================
echo.
pause
exit /b 0

rem ================= подпрограммы =================

:WRITE_CNF
rem %1 = файл, %2 = пользователь, %3 = пароль (спецсимволы безопасны: отложенное раскрытие)
set "LF_CNF_FILE=%~1"
set "LF_CNF_USER=%~2"
set "LF_CNF_PASS=%~3"
setlocal EnableDelayedExpansion
> "!LF_CNF_FILE!" echo [client]
>> "!LF_CNF_FILE!" echo user="!LF_CNF_USER!"
>> "!LF_CNF_FILE!" echo password="!LF_CNF_PASS!"
>> "!LF_CNF_FILE!" echo host=127.0.0.1
>> "!LF_CNF_FILE!" echo port=3306
>> "!LF_CNF_FILE!" echo protocol=tcp
>> "!LF_CNF_FILE!" echo default-character-set=utf8mb4
endlocal
set "LF_CNF_PASS="
exit /b 0

:HAS_DATA
rem errorlevel 0 - если в %1 есть dbc\<локаль>\ChrRaces.db2 и maps
if not exist "%~1\maps" exit /b 1
for /d %%L in ("%~1\dbc\*") do if exist "%%~L\ChrRaces.db2" exit /b 0
exit /b 1

:COUNT_TABLES
rem %1 = база; результат в LF_TABLES
set "LF_TABLES="
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='%~1'" > "%TMP_DIR%\lf_count.txt" 2>nul
set /p LF_TABLES=<"%TMP_DIR%\lf_count.txt"
if not defined LF_TABLES set "LF_TABLES=0"
exit /b 0

:IMPORT_IF_EMPTY
call :COUNT_TABLES %1
if not "%LF_TABLES%"=="0" (
    echo      - база %~1 уже содержит таблиц: %LF_TABLES% - пропуск, данные сохранены.
    exit /b 0
)
if not exist "%~2" (
    echo  [ОШИБКА] Нет файла %~2
    exit /b 1
)
echo      - импорт %~nx2 в базу %~1...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M --default-character-set=utf8mb4 %~1 < "%~2"
if errorlevel 1 (
    echo  [ОШИБКА] Импорт %~nx2 не удался.
    exit /b 1
)
exit /b 0

:IMPORT_WORLD_IF_EMPTY
call :COUNT_TABLES world
set "WC=%LF_TABLES%"
call :COUNT_TABLES hotfixes
set "HC=%LF_TABLES%"
if not "%WC%"=="0" if not "%HC%"=="0" (
    echo      - world и hotfixes уже содержат таблицы - импорт пропущен, данные сохранены.
    exit /b 0
)
echo      - нужна база world/hotfixes: загрузка LegionForge-DB.7z (около 100 МБ)...
%PS% -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -SevenZip -WorldDB
set "DBARC=%TOOLS_DIR%\downloads\LegionForge-DB.7z"
if not exist "%DBARC%" (
    echo  [ОШИБКА] Не удалось получить LegionForge-DB.7z.
    echo      Положите архив вручную в tools\downloads\LegionForge-DB.7z и повторите.
    exit /b 1
)
set "SZ="
if exist "%TOOLS_DIR%\7zip\7zr.exe" set "SZ=%TOOLS_DIR%\7zip\7zr.exe"
if not defined SZ if exist "%ProgramFiles%\7-Zip\7z.exe" set "SZ=%ProgramFiles%\7-Zip\7z.exe"
if not defined SZ (
    echo  [ОШИБКА] Нет 7-Zip для распаковки.
    exit /b 1
)
echo      - распаковка (около 800 МБ SQL) в tools\setup_tmp...
"%SZ%" e -y -bso0 -bsp0 -o"%TMP_DIR%" "%DBARC%" legion_world.sql legion_hotfixes.sql
if errorlevel 1 (
    echo  [ОШИБКА] Распаковка LegionForge-DB.7z не удалась.
    exit /b 1
)
if "%WC%"=="0" (
    echo      - импорт legion_world.sql в world - 5-20 минут, ждите...
    "%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M --default-character-set=utf8mb4 world < "%TMP_DIR%\legion_world.sql"
    if errorlevel 1 (
        echo  [ОШИБКА] Импорт legion_world.sql не удался.
        exit /b 1
    )
)
if "%HC%"=="0" (
    echo      - импорт legion_hotfixes.sql в hotfixes...
    "%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M --default-character-set=utf8mb4 hotfixes < "%TMP_DIR%\legion_hotfixes.sql"
    if errorlevel 1 (
        echo  [ОШИБКА] Импорт legion_hotfixes.sql не удался.
        exit /b 1
    )
)
del /q "%TMP_DIR%\legion_world.sql" "%TMP_DIR%\legion_hotfixes.sql" >nul 2>&1
echo      - world и hotfixes импортированы.
exit /b 0

:FAIL
echo.
echo  [ОШИБКА] Установка не завершена. Исправьте причину выше и запустите setup.bat снова.
echo      Уже сделанные шаги повторно не выполняются.
echo.
pause
exit /b 1
