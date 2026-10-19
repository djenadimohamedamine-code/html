@echo off
setlocal EnableExtensions
title TalkShow - Bug emission V2 10 MIN
cd /d "%~dp0"

echo.
echo ============================================================
echo   BUG EMISSION V2 - UN SEUL NOM - MASTER DSK 10 MIN
echo ============================================================
echo.
set /p "SHOW=Nom de l'emission [TALK SHOW] : "
if not defined SHOW set "SHOW=TALK SHOW"

echo.
python RENDER_BUG_10MIN.py "%SHOW%"
if errorlevel 1 (
    echo.
    echo ERREUR - regarde le message ci-dessus.
    pause
    exit /b 1
)

echo.
echo Le MOV final 10 minutes est dans EXPORTS
echo.
pause

