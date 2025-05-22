@echo off
cd /d "%~dp0"
start "" iex.bat --sname servidor -r util.ex chat_server.exs