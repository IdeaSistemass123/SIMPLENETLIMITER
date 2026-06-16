@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\19.0\bin\rsvars.bat"
set LIBREL=%BDS%\lib\win32\release
set OUT=..\bin
set DCU=..\dcu
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%DCU%" mkdir "%DCU%"

echo === [0/3] Copiando runtime WinDivert -^> bin ===
copy /Y ..\lib\WinDivert.dll   "%OUT%\" >nul
copy /Y ..\lib\WinDivert32.sys "%OUT%\" >nul
copy /Y ..\lib\WinDivert64.sys "%OUT%\" >nul

echo === [1/3] Compilando manifest (app.res) ===
brcc32 app.rc -foapp.res
if errorlevel 1 goto :err

echo === [2/3] Compilando SefazThrottle.exe ===
dcc32 -B -E"%OUT%" -NU"%DCU%" -NS"Winapi;System;System.Win;Data;Vcl;Vcl.Imaging" -U"%LIBREL%" -I"%LIBREL%" -R"%LIBREL%" -O"%LIBREL%" SefazThrottle.dpr
if errorlevel 1 goto :err

echo === [3/3] Compilando smoke.exe (teste do binding) ===
dcc32 -B -E"%OUT%" -NU"%DCU%" -NS"Winapi;System;System.Win" -U"%LIBREL%" -I"%LIBREL%" -R"%LIBREL%" -O"%LIBREL%" smoke.dpr
if errorlevel 1 goto :err

echo.
echo === BUILD OK -> %OUT% ===
exit /b 0
:err
echo.
echo === ERRO NA COMPILACAO ===
exit /b 1
