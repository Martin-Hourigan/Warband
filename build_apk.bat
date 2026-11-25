@echo off
rem Builds build\Warband.apk (signed with the Android Studio debug key).
rem With a phone plugged in (USB debugging on), "build_apk.bat install" also installs it.
set GODOT=C:\Users\Martin\Programming\Projects\Games\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set GODOT_ANDROID_KEYSTORE_DEBUG_PATH=%USERPROFILE%\.android\debug.keystore
set GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
set GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
cd /d "%~dp0"
if not exist build mkdir build
"%GODOT%" --headless --path . --export-debug "Android" build\Warband.apk
if "%1"=="install" "%ADB%" install -r build\Warband.apk
