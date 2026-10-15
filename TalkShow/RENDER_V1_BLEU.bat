@echo off
setlocal EnableExtensions
title FAMILY V1 BLEUE - RENDER
cd /d "%~dp0"

echo.
python RENDER_V1_BLEU.py
if errorlevel 1 (
  echo.
  echo ERREUR - voir le message ci-dessus.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   TERMINE - fichiers dans EXPORTS\V1
echo ============================================================
echo.
pause
