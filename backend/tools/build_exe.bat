@echo off
REM Rebuild the standalone ApexBooksMigration.exe (no dependencies for end users).
REM Run from the backend repo root:  tools\build_exe.bat
setlocal
cd /d "%~dp0.."

if not exist ".venv313\Scripts\python.exe" (
    echo ERROR: .venv313 not found. Create it first:  python -m venv .venv313
    exit /b 1
)

echo Installing build tools into the venv...
.venv313\Scripts\python.exe -m pip install -q pyinstaller || exit /b 1

echo Building ApexBooksMigration.exe ...
.venv313\Scripts\python.exe -m PyInstaller --noconfirm --clean --onefile --windowed ^
    --name ApexBooksMigration ^
    --collect-submodules src ^
    --collect-submodules slowapi ^
    --hidden-import email_validator ^
    --hidden-import sqlalchemy.dialects.sqlite ^
    tools\migration_gui.py || exit /b 1

echo.
echo Done: dist\ApexBooksMigration.exe
echo Share that single file - the end user needs nothing installed.
endlocal
