@echo off
REM LEGIONFORGE 7.3.5.26124 - UNBLOCK.bat (run FIRST after unpacking)
REM ASCII only, no labels, no GOTO, no ( ) blocks: this file works even
REM when it was saved with Unix LF line endings.
REM 1) removes "Mark of the Web" (Zone.Identifier) from every file;
REM 2) converts every .bat/.cmd to Windows CRLF line endings and every
REM    .ps1 to UTF-8 with BOM. LF-only .bat files are the cause of
REM    "'...' is not recognized as an internal or external command".
cd /d "%~dp0"
echo.
echo  ==========================================================
echo   LEGIONFORGE 7.3.5.26124 - unblock and repair files
echo  ==========================================================
echo   Folder: %CD%
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\repair_files.ps1" -Root "%~dp0."
echo.
echo  [OK] Done. Now run setup.bat (it asks for administrator rights itself).
echo  If SmartScreen appears: "More info" - "Run anyway".
echo.
pause
