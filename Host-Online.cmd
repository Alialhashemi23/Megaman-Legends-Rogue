@echo off
rem Serve Relic Diver online from this PC without Docker. See docs\ONLINE.md.
rem Public address: https://megaman.galosengen.dev (through the Cloudflare Tunnel).
cd /d "%~dp0"
where node >nul 2>nul || (echo Node.js 20 or newer is required: https://nodejs.org/ & pause & exit /b 1)
echo Unpacking the web build...
powershell -NoProfile -Command "Expand-Archive -Force build\RelicDiver-Web.zip build\web" || (pause & exit /b 1)
if not exist server\node_modules (pushd server & call npm ci --omit=dev & popd)
:serve
echo Relic Diver is running at http://localhost:8080 - close this window to stop.
node server\server.js
rem If the server ever stops unexpectedly, bring it back.
echo The server stopped. Restarting in 5 seconds...
timeout /t 5 /nobreak >nul
goto serve
