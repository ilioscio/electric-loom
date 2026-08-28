@echo off
REM Electric Loom - serve this folder so the GIF encoder can use background workers.
REM Chrome blocks blob: workers on file:// pages, so the app falls back to a
REM single-threaded encoder when you double-click index.html. Running this
REM instead gives you every core.

setlocal
set PORT=8777
cd /d "%~dp0"

where py >nul 2>nul && (
  start "" http://localhost:%PORT%/index.html
  py -3 -m http.server %PORT%
  goto :eof
)
where python >nul 2>nul && (
  start "" http://localhost:%PORT%/index.html
  python -m http.server %PORT%
  goto :eof
)
where npx >nul 2>nul && (
  start "" http://localhost:%PORT%/index.html
  npx --yes http-server -p %PORT% -c-1
  goto :eof
)

echo.
echo   No python or npx found on PATH.
echo   Open index.html directly instead - everything still works, the GIF
echo   encoder just runs on one core.
echo.
pause
