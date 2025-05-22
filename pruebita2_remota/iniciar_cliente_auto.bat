@echo off
set SERVERIP=192.168.100.7  REM Cambia esto por la IP real del servidor
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

REM Cambia cliente1 por un nombre único en cada PC
iex --name cliente1@%MIIP% --cookie %COOKIE% -r util.ex chat_user.exs
pause