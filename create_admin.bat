@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 (сборка 2026-10-20)
rem  Файл: create_admin.bat
rem
rem  Создаёт аккаунт администратора сервера:
rem    Логин (Battle.net): admin@legionforge.ru
rem    Пароль:             legionforge
rem    Уровень доступа:    3 (администратор)
rem
rem  Аккаунт сразу готов к входу в клиент: в окне Battle.net
rem  вводится именно e-mail и пароль.
rem ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "TOOLS_DIR=%ROOT%\tools"
set "MYSQL_CNF=%TOOLS_DIR%\mysql.cnf"

title LEGIONFORGE 7.3.5.26124 - Создание админа
color 0B

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 (2026-10-20) - создание админа
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

echo  [*] Проверяю/создаю аккаунт администратора...
echo      Логин:  admin@legionforge.ru
echo      Пароль: legionforge
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\update_local_account.ps1" -Username "admin" -Password "legionforge" -Email "admin@legionforge.ru" -GmLevel 3 -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 (
    echo  [*] Обновить не удалось, попробую создать аккаунт заново...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\create_local_account.ps1" -Username "admin" -Password "legionforge" -Email "admin@legionforge.ru" -GmLevel 3 -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
    if errorlevel 1 (
        echo  [ОШИБКА] Не удалось создать аккаунт администратора.
        pause
        exit /b 1
    )
)

echo.
echo  =========================================================
echo   Готово.
echo  =========================================================
echo.
echo   Вход в клиент:
echo     Логин:  admin@legionforge.ru
echo     Пароль: legionforge
echo.
echo   Сервер должен быть запущен (bnetserver и worldserver).
echo   Запуск сервера: play.bat
echo.
pause
exit /b 0
