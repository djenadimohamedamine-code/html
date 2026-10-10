@echo off
title Generateur Web - TalkShow
cd /d "%~dp0.."
python render_talkshow.py --serve
pause
