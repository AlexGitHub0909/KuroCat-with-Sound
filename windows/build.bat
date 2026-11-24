@echo off
setlocal
cd /d "%~dp0"

echo ==> Building KuroCat.exe (Windows native C++17 / Win32 + GDI+ + Raw Input + WASAPI)...

where cl >nul 2>nul
if %ERRORLEVEL%==0 (
    cl /nologo /std:c++17 /O2 /MT /EHsc /utf-8 /DUNICODE /D_UNICODE ^
       /W3 src\main.cpp /Fe:KuroCat.exe ^
       /link /SUBSYSTEM:WINDOWS /MANIFEST:EMBED /MANIFESTINPUT:app.manifest ^
       user32.lib gdi32.lib gdiplus.lib shell32.lib advapi32.lib ole32.lib uuid.lib avrt.lib
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
    del /q main.obj 2>nul
    goto :bundle
)

where g++ >nul 2>nul
if %ERRORLEVEL%==0 (
    g++ -std=c++17 -O2 -mwindows -municode -pthread -DUNICODE -D_UNICODE -static ^
        -finput-charset=UTF-8 -fexec-charset=UTF-8 ^
        src\main.cpp -o KuroCat.exe ^
        -Wl,--subsystem,windows ^
        -luser32 -lgdi32 -lgdiplus -lshell32 -ladvapi32 -lole32 -luuid -lavrt
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
    echo ==> Built successfully with MinGW: %~dp0KuroCat.exe
    goto :bundle
)

echo [ERROR] Neither MSVC (cl.exe) nor MinGW (g++.exe) found in PATH.
echo Please run from "x64 Native Tools Command Prompt for VS" or install Visual Studio Build Tools.
exit /b 1

:bundle
echo ==> Bundling SoundThemes...
if exist "..\Resources\SoundThemes" (
    xcopy "..\Resources\SoundThemes\*" "SoundThemes\" /E /I /Y >nul
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
) else (
    echo [WARNING] ..\Resources\SoundThemes not found — keyboard sounds will be unavailable.
)
echo ==> Built successfully: %~dp0KuroCat.exe
exit /b 0
