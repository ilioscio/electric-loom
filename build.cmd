@echo off
REM Regenerate the committed single-file index.html on Windows.
REM Prefers build.sh (the same script the Nix derivation runs) when a POSIX
REM shell is on PATH, so there is only one real build. Falls back to
REM PowerShell doing the same two steps: concatenate, then substitute.
REM
REM The fallback reads and writes UTF-8 explicitly. Get-Content without an
REM encoding uses the ANSI codepage on Windows PowerShell 5.1, which silently
REM mangles every multi-byte character in the source.

setlocal
cd /d "%~dp0"

where sh >nul 2>nul
if %errorlevel%==0 (
  sh -c "OUT=. SINGLE_FILE=1 ./build.sh"
  goto :tests
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$enc = New-Object System.Text.UTF8Encoding $false;" ^
  "$parts = 'p01_head','p02_body','p03_util','p04_shaders','p05_flame','p06_engine','p07_ui','p08_gif','p09_export','p09b_theatre','p10_boot';" ^
  "$text = ($parts | ForEach-Object { [IO.File]::ReadAllText((Join-Path $PWD ('build\' + $_ + '.txt')), $enc) }) -join '';" ^
  "$text = $text -replace '<!--EL_HEAD-->\r?\n', '' -replace '<!--EL_AD_RAIL-->\r?\n', '' -replace '<!--EL_BODY_END-->\r?\n', '';" ^
  "$text = $text -replace '__SITE_URL__', '';" ^
  "[IO.File]::WriteAllText((Join-Path $PWD 'index.html'), $text, $enc);" ^
  "Write-Host ('built index.html  (' + $text.Length + ' chars)')"

:tests
where node >nul 2>nul
if %errorlevel%==0 node build\test_gif.js
