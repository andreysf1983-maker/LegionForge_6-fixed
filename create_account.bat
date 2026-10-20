@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20)
rem  Файл: create_account.bat
rem
rem  Создание игрового аккаунта: имя логина и пароль
rem  (вход в клиент - по e-mail и паролю, как в Battle.net).
rem
rem  Сценарии:
rem     create_account.bat                       - интерактивно
rem     create_account.bat имя пароль email gm   - без вопросов
rem     create_admin.bat                         - администратор
rem ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "TOOLS_DIR=%ROOT%\tools"
set "MYSQL_CNF=%TOOLS_DIR%\mysql.cnf"

title LEGIONFORGE 7.3.5.26124 - Создание аккаунта
color 0B

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 (2026-10-20) - создание аккаунта
echo  =========================================================
echo.

if not exist "%MYSQL_CNF%" (
    echo  [ОШИБКА] Нет файла подключения к MySQL: !MYSQL_CNF!
    echo      Сначала выполните установку сервера: setup.bat
    pause
    exit /b 1
)

set "MYSQL="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\find_mysql.ps1" -Port 3306`) do set "MYSQL=%%P"
if not exist "%MYSQL%" (
    echo  [ОШИБКА] MySQL не найден. Запустите setup.bat.
    pause
    exit /b 1
)

rem ---- параметры командной строки или интерактив ----
if not "%~1"=="" (
    set "ACCT_USER=%~1"
    set "ACCT_PASS=%~2"
    set "ACCT_EMAIL=%~3"
    set "GM_LEVEL=%~4"
    if "!GM_LEVEL!"=="" set "GM_LEVEL=0"
    goto :CREATE
)

echo  Заполните данные игрового аккаунта.
echo.
set /p "ACCT_USER=  Имя логина (короткое, латиницей): "
set /p "ACCT_PASS=  Пароль: "
set /p "ACCT_EMAIL= E-mail (именно по нему вход в клиент): "
echo.
echo  Уровень доступа:
echo    0 - обычный игрок
echo    1 - гастмастер
echo    2 - главный-гастмастер
echo    3 - администратор
set /p "GM_LEVEL=  Уровень (0-3) [0]: "

if "!GM_LEVEL!"=="" set "GM_LEVEL=0"
if "!ACCT_USER!"=="" (
    echo.
    echo  [ОШИБКА] Пустое имя логина запрещено.
    pause
    exit /b 1
)
if "!ACCT_PASS!"=="" (
    echo.
    echo  [ОШИБКА] Пустой пароль запрещён.
    pause
    exit /b 1
)
:CREATE

echo.
echo  [*] Создаю аккаунт "!ACCT_USER!" (gmlevel !GM_LEVEL!)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\create_local_account.ps1" -Username "!ACCT_USER!" -Password "!ACCT_PASS!" -Email "!ACCT_EMAIL!" -GmLevel !GM_LEVEL! -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 (
    echo.
    echo  [ОШИБКА] Аккаунт не создан. Проверьте, что MySQL запущен.
    pause
    exit /b 1
)

echo.
echo  =========================================================
echo   Готово. Вход в клиент:
echo     Логин:  !ACCT_EMAIL!
echo     Пароль: (тот, что ввели)
echo  =========================================================
echo.
pause
exit /b 0
