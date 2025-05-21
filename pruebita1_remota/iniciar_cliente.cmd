@echo off
cd /d "%~dp0"
REM Genera un nombre de nodo único usando la hora actual
set NODE=cliente_%random%
start "" iex.bat --sname %NODE% -r util.ex chat_user.exs