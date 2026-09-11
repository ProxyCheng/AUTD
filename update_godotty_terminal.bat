@echo off
setlocal EnableDelayedExpansion
rem ============================================================
rem  update_godotty_terminal.bat
rem
rem  Rebuild the godotty (embedded Terminal) GDExtension DLL against
rem  the locally compiled Godot engine, then deploy it to the AUTD
rem  project. Run this AFTER recompiling the Godot editor at:
rem      E:\Projects\CPP\godot\bin\godot.windows.editor.dev.x86_64.exe
rem
rem  Why this exists: godotty is compiled against the engine's
rem  extension_api.json. When you rebuild the engine, the API hashes
rem  change, and a stale DLL crashes the editor at startup with
rem  "Failed to load class method ... (hash NNNN)". Rebuilding here
rem  re-dumps the API and recompiles so the hashes match again.
rem
rem  Fingerprint logic (to skip pointless rebuilds):
rem    * The engine .exe MD5 is recorded after each successful run.
rem      If the MD5 is UNCHANGED, the engine binary is byte-identical,
rem      so nothing is rebuilt at all.
rem    * If the engine changed but the dumped CORE/EDITOR API hashes
rem      are identical to the last run, the API is unchanged, so the
rem      existing DLL is still valid and no rebuild happens.
rem    * Pass --force to ignore fingerprints and always rebuild.
rem ============================================================

rem ---- configurable paths (edit if you move things) ----
set "GODOT_EXE=E:\Projects\CPP\godot\bin\godot.windows.editor.dev.x86_64.exe"
set "SRC_DIR=E:\Projects\Rust\godotty"
set "GHOSTTY_DIR=E:\Projects\Rust\ghostty-src"
set "DEPLOY_DLL=E:\Projects\Godot\autd\addons\godotty\bin\libgodotty.windows.x86_64.dll"
set "ZIG_DIR=C:\Users\32242\.local\zig\zig-0.15.2"
set "TARGET=x86_64-pc-windows-gnu"
set "SIDECAR=%SRC_DIR%\extension_api.json.fingerprint"

rem ---- sanity checks ----
if not exist "%GODOT_EXE%" (
    echo [ERROR] Godot engine not found: %GODOT_EXE%
    exit /b 1
)
if not exist "%SRC_DIR%\Cargo.toml" (
    echo [ERROR] godotty source not found: %SRC_DIR%
    exit /b 1
)
if not exist "%GHOSTTY_DIR%\build.zig" (
    echo [ERROR] ghostty source not found: %GHOSTTY_DIR%
    exit /b 1
)

rem ---- optional --force ----
set "FORCE=0"
if /I "%~1"=="--force" set "FORCE=1"

rem ---- read previously recorded engine md5 + api hashes (if any) ----
set "engine_md5="
set "core_hash="
set "editor_hash="
if exist "%SIDECAR%" for /f "usebackq tokens=1,* delims==" %%A in ("%SIDECAR%") do set "%%A=%%B"

rem ============================================
echo.
echo  godotty terminal updater
echo    engine : %GODOT_EXE%
echo ============================================

rem ---- compute current engine MD5 (fast: ~1s for a 200MB exe) ----
for /f "delims=" %%H in ('certutil -hashfile "%GODOT_EXE%" MD5 ^| findstr /R "^[0-9a-f][0-9a-f]*$"') do set "CUR_MD5=%%H"
if not defined CUR_MD5 (
    echo [ERROR] Could not hash the engine executable.
    exit /b 1
)
echo    engine MD5 : %CUR_MD5%  ^(previous: %engine_md5%^)

rem ---- FAST PATH: engine binary unchanged since last successful run ----
if "%FORCE%"=="0" (
    if defined engine_md5 (
        if "%engine_md5%"=="%CUR_MD5%" (
            if exist "%DEPLOY_DLL%" (
                echo.
                echo [SKIP] Engine MD5 unchanged since last build.
                echo        The deployed godotty DLL is already in sync.
                echo        ^(use --force to rebuild anyway^)
                endlocal
                exit /b 0
            )
        )
    )
)

rem ============================================
rem  Engine changed  ->  dump the API and compare hashes
rem ============================================

echo.
echo [1/4] Dumping extension_api.json from the engine...
set "DUMP_DIR=%TEMP%\godotty_api_dump"
if not exist "%DUMP_DIR%" mkdir "%DUMP_DIR%"
set "DUMP_LOG=%DUMP_DIR%\dump.log"
pushd "%DUMP_DIR%"
"%GODOT_EXE%" --headless --editor --verbose --dump-extension-api > "%DUMP_LOG%" 2>&1
set "DUMP_ERR=%ERRORLEVEL%"
popd
if not "%DUMP_ERR%"=="0" (
    echo [ERROR] Engine dump-extension-api failed with code %DUMP_ERR%
    type "%DUMP_LOG%"
    exit /b 1
)
if not exist "%DUMP_DIR%\extension_api.json" (
    echo [ERROR] Engine did not produce extension_api.json
    exit /b 1
)

rem ---- extract CORE / EDITOR API hashes from the dump log ----
for /f "tokens=2 delims=:" %%A in ('findstr /C:"CORE API HASH:" "%DUMP_LOG%"') do set "NEW_CORE=%%A"
for /f "tokens=2 delims=:" %%A in ('findstr /C:"EDITOR API HASH:" "%DUMP_LOG%"') do set "NEW_EDITOR=%%A"
rem trim surrounding whitespace
if defined NEW_CORE for /f "tokens=*" %%A in ("%NEW_CORE%") do set "NEW_CORE=%%A"
if defined NEW_EDITOR for /f "tokens=*" %%A in ("%NEW_EDITOR%") do set "NEW_EDITOR=%%A"

echo        CORE API HASH   : %NEW_CORE%  ^(previous: %core_hash%^)
echo        EDITOR API HASH : %NEW_EDITOR%  ^(previous: %editor_hash%^)

rem ---- SECOND FAST PATH: engine changed but API hashes identical ----
if "%FORCE%"=="0" (
    if defined core_hash (
        if defined NEW_CORE (
            if "%core_hash%"=="%NEW_CORE%" (
                if "%editor_hash%"=="%NEW_EDITOR%" (
                    if exist "%DEPLOY_DLL%" (
                        rem API unchanged -> existing DLL still valid; just refresh fingerprint
                        > "%SIDECAR%" echo engine_md5=%CUR_MD5%
                        >> "%SIDECAR%" echo core_hash=%NEW_CORE%
                        >> "%SIDECAR%" echo editor_hash=%NEW_EDITOR%
                        echo.
                        echo [SKIP] Engine was rebuilt but the API is unchanged.
                        echo        Existing godotty DLL is still compatible.
                        echo        ^(fingerprint refreshed, use --force to rebuild anyway^)
                        endlocal
                        exit /b 0
                    )
                )
            )
        )
    )
)

rem ---- fresh API json -> copy into source tree ----
copy /y "%DUMP_DIR%\extension_api.json" "%SRC_DIR%\extension_api.json" >nul
echo        - copied to %SRC_DIR%\extension_api.json

rem ============================================
rem  Full rebuild path
rem ============================================

rem ---- warn if the editor is currently running (DLL locked) ----
tasklist /FI "IMAGENAME eq godot.windows.editor.dev.x86_64.exe" 2>nul | find /I "godot.windows.editor.dev.x86_64.exe" >nul
if not errorlevel 1 (
    echo.
    echo [WARN] A Godot editor instance is RUNNING.
    echo        Close it first, otherwise the DLL copy below will fail.
    echo.
    set /p "ans=Close it now and press Enter to continue, or Ctrl+C to abort... "
)

rem ---- force godot codegen to re-run with the new API ----
rem godot-ffi's build script does NOT watch extension_api.json, so cargo
rem reuses cached bindings unless we delete the build dirs. Without this
rem the new hashes never reach the DLL and the editor crashes again.
echo.
echo [2/4] Forcing godot-rust codegen to re-run with the new API...
for /d %%d in ("%SRC_DIR%\target\%TARGET%\release\build\godot-core-*") do rmdir /s /q "%%d"
for /d %%d in ("%SRC_DIR%\target\%TARGET%\release\build\godot-ffi-*") do rmdir /s /q "%%d"
for /d %%d in ("%SRC_DIR%\target\%TARGET%\release\build\godot-bindings-*") do rmdir /s /q "%%d"
for /d %%d in ("%SRC_DIR%\target\%TARGET%\release\.fingerprint\godot-core-*") do rmdir /s /q "%%d"
for /d %%d in ("%SRC_DIR%\target\%TARGET%\release\.fingerprint\godot-ffi-*") do rmdir /s /q "%%d"
echo        - cleared godot-core/godot-ffi build caches

rem ---- cargo build (windows-gnu, custom api json) ----
echo.
echo [3/4] cargo build --release --target %TARGET% (this takes a few minutes)...
set "PATH=D:\ghcup\msys64\mingw64\bin;%USERPROFILE%\.cargo\bin;%ZIG_DIR%;%PATH%"
set "GDRUST_GODOT_API_JSON=%SRC_DIR%\extension_api.json"
set "GHOSTTY_SOURCE_DIR=%GHOSTTY_DIR%"
set "LIBGHOSTTY_VT_SYS_OPTIMIZE=ReleaseFast"
pushd "%SRC_DIR%"
call cargo build --release --target %TARGET%
set "BUILD_ERR=%ERRORLEVEL%"
popd
if not "%BUILD_ERR%"=="0" (
    echo [ERROR] cargo build failed with code %BUILD_ERR%
    exit /b 1
)

set "DLL=%SRC_DIR%\target\%TARGET%\release\godotty.dll"
if not exist "%DLL%" (
    echo [ERROR] build output missing: %DLL%
    exit /b 1
)

rem ---- deploy ----
echo.
echo [4/4] Deploying to %DEPLOY_DLL% ...
copy /y "%DLL%" "%DEPLOY_DLL%" >nul
if errorlevel 1 (
    echo [ERROR] deploy failed - is the editor still running?
    exit /b 1
)

rem ---- record fingerprint + api hashes for next run ----
> "%SIDECAR%" echo engine_md5=%CUR_MD5%
>> "%SIDECAR%" echo core_hash=%NEW_CORE%
>> "%SIDECAR%" echo editor_hash=%NEW_EDITOR%

echo.
echo ============================================
echo  DONE. godotty terminal rebuilt and deployed.
echo  Restart the Godot editor (from Explorer) to use it.
echo ============================================
endlocal
