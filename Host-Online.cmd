@echo off
rem Serve Relic Diver online from this PC without Docker. See docs\ONLINE.md.
cd /d "%~dp0"
where node >nul 2>nul || (echo Node.js 20 or newer is required: https://nodejs.org/ & pause & exit /b 1)
echo Unpacking the web build...
powershell -NoProfile -Command "Expand-Archive -Force build\RelicDiver-Web.zip build\web" || (pause & exit /b 1)
if not exist server\node_modules (pushd server & call npm ci --omit=dev & popd)
echo Relic Diver is running at http://localhost:8080  (Ctrl+C to stop)
node server\server.js
pause
