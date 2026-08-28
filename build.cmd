@echo off
REM Rebuild index.html from the numbered source parts in build\
cd /d "%~dp0"
copy /b "build\p01_head.txt"+"build\p02_body.txt"+"build\p03_util.txt"+"build\p04_shaders.txt"+"build\p05_flame.txt"+"build\p06_engine.txt"+"build\p07_ui.txt"+"build\p08_gif.txt"+"build\p09_export.txt"+"build\p10_boot.txt" "index.html" >nul
echo Rebuilt index.html
where node >nul 2>nul && node build\test_gif.js
