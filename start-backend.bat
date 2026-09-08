@echo off
REM Maksab backend API - keep this window OPEN while testing the app
cd /d E:\Development\marketappabdogomla\backend
echo Starting Maksab backend on http://localhost:3100 ...
node src/index.js --seed
pause
