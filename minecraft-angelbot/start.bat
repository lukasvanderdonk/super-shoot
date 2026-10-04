@echo off
rem Startet den Angel-Bot. Installiert beim ersten Mal die noetigen Python-Pakete.
cd /d "%~dp0"
title Angel-Bot

set "PY="
py -3 --version >/dev/null 2>&1 && set "PY=py -3"
if not defined PY (python --version >/dev/null 2>&1 && set "PY=python")
if not defined PY goto keinpython

echo Pruefe, ob alles installiert ist ...
%PY% -m pip install --user --quiet --disable-pip-version-check mss numpy
if errorlevel 1 (
    echo.
    echo Die Installation hat nicht geklappt. Bist du mit dem Internet verbunden?
    pause
    exit /b 1
)

%PY% angelbot.py
pause
exit /b 0

:keinpython
echo Python ist noch nicht installiert.
echo Ich oeffne jetzt die Python-Webseite: Python herunterladen und installieren.
echo WICHTIG: Beim Installieren unten das Haekchen "Add python.exe to PATH" setzen!
echo Danach start.bat nochmal doppelklicken.
start "" https://www.python.org/downloads/windows/
pause
