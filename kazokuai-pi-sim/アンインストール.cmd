@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0installer\uninstall.ps1'; Read-Host 'Enter'" & exit /b
