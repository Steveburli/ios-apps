@echo off
cd /d "%~dp0web"
start "" http://localhost:8000
where python >nul 2>nul && (python -m http.server 8000 & goto :eof)
where npx >nul 2>nul && (npx --yes http-server -p 8000 -c-1 & goto :eof)
echo Install Python from python.org or Node from nodejs.org, then run this again.
pause
