@echo off
set COOKIE=supersecreta123

REM Detectar la IP local automáticamente (toma la primera IPv4 no loopback)
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    for /f "tokens=* delims= " %%b in ("%%a") do (
        set MIIP=%%b
        goto continuar
    )
)
:continuar

REM Quitar espacios iniciales
set MIIP=%MIIP: =%

iex --name servidor@%MIIP% --cookie %COOKIE% -r util.ex -r chat_logger.exs chat_server.exs
pause