@echo off
REM Maksab web demo - keep this window OPEN, then open http://localhost:8080
cd /d E:\Development\marketappabdogomla\mobile\build\web
echo Serving app on http://localhost:8080 ...
python -m http.server 8080
pause
