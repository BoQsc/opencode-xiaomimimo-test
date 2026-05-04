@echo off
REM Build CrossUI Notepad for Windows
REM Requires: DMD (D compiler) from https://dlang.org/
cd /d "%~dp0"
del /q crossui.exe crossui.obj font_backend_d.obj 2>nul

dmd crossui.d font_backend_d.d ^
    -ofcrossui.exe ^
    -O -release -inline ^
    -L/subsystem:windows ^
    -L/entry:mainCRTStartup ^
    -L/DEFAULTLIB:user32 ^
    -L/DEFAULTLIB:gdi32 ^
    -L/DEFAULTLIB:opengl32 ^
    -L/DEFAULTLIB:comdlg32 ^
    -L/DEFAULTLIB:comctl32

if %ERRORLEVEL% EQU 0 (
    echo Build successful: crossui.exe
) else (
    echo Build failed with errors.
)
