@echo off & goto :batch
'''
:batch
rem ===================================================================
rem  Angel-Bot - einfach doppelklicken!
rem  Diese Datei ist Start-Skript und Python-Programm in einem:
rem  Der Batch-Teil hier oben installiert bei Bedarf Python und die
rem  Zusatzpakete und startet dann den Python-Teil weiter unten
rem  (python -x ueberspringt dabei die erste Zeile).
rem ===================================================================
setlocal
cd /d "%~dp0"
title Angel-Bot

call :finde_python
if not defined PY (
    echo Python ist noch nicht installiert - das mache ich jetzt.
    echo Das kann ein paar Minuten dauern, bitte warten ...
    echo.
    call :installiere_python
)
if not defined PY (
    echo.
    echo Python konnte nicht automatisch installiert werden.
    echo Bitte installiere es selbst von der Webseite, die sich gleich oeffnet,
    echo setze dabei das Haekchen "Add python.exe to PATH"
    echo und doppelklicke danach Angel-Bot.bat nochmal.
    start "" https://www.python.org/downloads/windows/
    pause
    exit /b 1
)

echo Pruefe die Zusatzpakete ...
"%PY%" -m pip install --user --quiet --disable-pip-version-check mss numpy
if errorlevel 1 (
    echo.
    echo Die Zusatzpakete konnten nicht installiert werden.
    echo Bist du mit dem Internet verbunden?
    pause
    exit /b 1
)

"%PY%" -x "%~f0" %*
pause
exit /b 0


:finde_python
set "PY="
for /f "delims=" %%P in ('py -3 -c "import sys; print(sys.executable)" 2^>nul') do set "PY=%%P"
if defined PY exit /b 0
for /f "delims=" %%P in ('python -c "import sys; print(sys.executable)" 2^>nul') do set "PY=%%P"
if defined PY exit /b 0
call :suche_in "%LOCALAPPDATA%\Programs\Python"
if not defined PY call :suche_in "%ProgramFiles%"
exit /b 0

:suche_in
for /f "delims=" %%D in ('dir /b /ad "%~1\Python3*" 2^>nul') do (
    if exist "%~1\%%D\python.exe" set "PY=%~1\%%D\python.exe"
)
exit /b 0


:installiere_python
where winget >nul 2>&1
if not errorlevel 1 (
    winget install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements
    call :finde_python
    if defined PY exit /b 0
)
echo Lade Python von python.org herunter ...
curl -L --fail -o "%TEMP%\python-installer.exe" https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe
if errorlevel 1 exit /b 1
echo Installiere Python ...
"%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
del "%TEMP%\python-installer.exe" >nul 2>&1
call :finde_python
exit /b 0
'''

# Angel-Bot fuer das Angel-Minispiel auf dem Minecraft-Server (Python-Teil).

HILFE = """Angel-Bot fuer das Angel-Minispiel auf dem Minecraft-Server.

So funktioniert das Minispiel:
  Auswerfen (Rechtsklick) -> ein Fisch beisst -> oben erscheint eine Leiste aus
  tuerkisen Feldern mit einem roten Feld. Ein weisser Rahmen springt Feld fuer
  Feld ueber die Leiste. Steht der Rahmen auf dem roten Feld, Rechtsklick ->
  der gruene Balken waechst, das rote Feld springt woanders hin. Nach ein paar
  Treffern ist der Fisch gefangen ("Yeah!"), dann wieder auswerfen.

Der Bot schaut sich dafuer den Bildschirm an (nur das Minecraft-Fenster) und
klickt selbst. Er klickt nur, solange Minecraft das aktive Fenster ist und
kein Menue (Inventar, Chat, Pause) offen ist.

Tasten:  F8 = Start / Pause   F10 = Diagnose-Bild speichern   F12 = Beenden
"""

import sys
import time

import numpy as np

# ---------------------------------------------------------------- Einstellungen

WARTEN_MAX = 60.0        # Sekunden ohne Biss, dann einholen und neu auswerfen
NACH_FANG_PAUSE = 1.5    # Sekunden nach dem Fang, bevor neu ausgeworfen wird
SPIEL_VORBEI_NACH = 0.6  # so lange muss die Leiste weg sein, dann ist das Spiel vorbei
KLICK_SPERRE = 0.8       # nicht zweimal auf dasselbe rote Feld klicken (Sekunden)
BILDER_PRO_SEKUNDE = 60  # wie oft der Bildschirm angeschaut wird

# Die Leiste ist ein Minecraft-Titel: knapp ueber der Bildschirmmitte.
# Nur dieser Streifen des Fensters wird angeschaut (Anteil der Fensterhoehe).
STREIFEN_OBEN = 0.20
STREIFEN_UNTEN = 0.65


# ------------------------------------------------------------------ Erkennung

def farb_masken(bild):
    """Teilt die Pixel in tuerkis / rot / weiss ein (bild: H x B x 3, RGB)."""
    r = bild[:, :, 0].astype(np.int16)
    g = bild[:, :, 1].astype(np.int16)
    b = bild[:, :, 2].astype(np.int16)
    tuerkis = (g > 185) & (b > 185) & (r < 170) & (np.abs(g - b) < 40)
    rot = (r > 170) & (g < 170) & (b < 170) & (r - g > 90) & (r - b > 90)
    weiss = (r > 215) & (g > 215) & (b > 215)
    return tuerkis, rot, weiss


def laeufe(zeile):
    """Zusammenhaengende True-Stuecke einer Zeile als Liste von (start, ende)."""
    z = np.concatenate(([False], zeile, [False])).astype(np.int8)
    d = np.diff(z)
    starts = np.flatnonzero(d == 1)
    enden = np.flatnonzero(d == -1)
    return list(zip(starts, enden))


def erkenne(bild):
    """Sucht die Minispiel-Leiste im Bild.

    Rueckgabe: None, wenn keine Leiste zu sehen ist, sonst ein dict mit
      auf_rot   True, wenn der weisse Rahmen gerade auf dem roten Feld steht
      rot_x     Mitte des roten Felds (oder None)
      rahmen_x  Mitte des weissen Rahmens (oder None)
      feld      ungefaehre Breite eines Felds in Pixeln
      abgeschnitten  True, wenn die Leiste an den Fensterrand stoesst
      y0, y1    obere / untere Zeile der Leiste
    """
    hoehe, breite = bild.shape[:2]
    tuerkis, rot, weiss = farb_masken(bild)
    farbig = tuerkis | rot

    # 1. Die Zeile mit den meisten tuerkisen/roten Pixeln finden.
    zeilen_summe = farbig.sum(axis=1)
    beste = int(np.argmax(zeilen_summe))
    if zeilen_summe[beste] < max(12, breite * 0.08):
        return None

    # 2. In dieser Zeile muessen mehrere gleich breite Felder nebeneinander liegen.
    min_feld = max(4, breite // 100)
    felder = [(s, e) for s, e in laeufe(farbig[beste]) if e - s >= min_feld]
    if len(felder) < 3:
        return None
    breiten = np.array([e - s for s, e in felder])
    feld = float(np.median(breiten))
    gleich = np.abs(breiten - feld) <= feld * 0.35
    if gleich.sum() < 3:
        return None

    # 3. Hoehe der Leiste: alle Zeilen um die beste herum, die fast genauso voll sind.
    schwelle = zeilen_summe[beste] * 0.5
    y0 = beste
    while y0 > 0 and zeilen_summe[y0 - 1] >= schwelle:
        y0 -= 1
    y1 = beste
    while y1 < hoehe - 1 and zeilen_summe[y1 + 1] >= schwelle:
        y1 += 1
    h = y1 - y0 + 1
    if h < 3 or h > feld * 2:
        return None

    # 4. Rotes Feld: Spalten, die in der Leiste ueberwiegend rot sind.
    rot_spalten = rot[y0:y1 + 1].sum(axis=0) >= h * 0.5
    rot_stuecke = [(s, e) for s, e in laeufe(rot_spalten) if e - s >= feld * 0.15]

    # 5. Weisser Rahmen: er hat weisse Kanten direkt ueber UND unter der Leiste
    #    (das Fadenkreuz liegt nur darunter, der Fortschrittsbalken auch).
    rand = max(2, int(round(h * 0.6)))
    oben = weiss[max(0, y0 - rand):y0].any(axis=0)
    unten = weiss[y1 + 1:min(hoehe, y1 + 1 + rand)].any(axis=0)
    rahmen_spalten = oben & unten
    rahmen_stuecke = [(s, e) for s, e in laeufe(rahmen_spalten) if e - s >= feld * 0.15]

    # 6. Steht der Rahmen auf dem roten Feld? (Am Fensterrand kann das Feld halb
    #    abgeschnitten sein, darum reicht schon ein Stueck davon.)
    im_rahmen_rot = int((rot_spalten & rahmen_spalten).sum())
    auf_rot = im_rahmen_rot >= max(2, feld * 0.15)

    # 7. Reicht die Leiste bis an den Fensterrand? Dann ist sie vermutlich abgeschnitten.
    zeile = farbig[y0:y1 + 1].any(axis=0) | rahmen_spalten
    abgeschnitten = bool(zeile[:2].any() or zeile[-2:].any())

    def mitte(stuecke):
        if not stuecke:
            return None
        s, e = max(stuecke, key=lambda t: t[1] - t[0])
        return (s + e) / 2.0

    return {
        "auf_rot": bool(auf_rot),
        "rot_x": mitte(rot_stuecke),
        "rahmen_x": mitte(rahmen_stuecke),
        "feld": feld,
        "abgeschnitten": abgeschnitten,
        "y0": y0,
        "y1": y1,
    }


class Klicker:
    """Entscheidet, wann im Minispiel geklickt wird (ohne Doppelklicks)."""

    def __init__(self):
        self.letzter_klick = -1e9
        self.letztes_ziel = None

    def soll_klicken(self, info, jetzt):
        if not info or not info["auf_rot"]:
            return False
        feld = info["feld"] or 1.0
        ziel = (
            None if info["rahmen_x"] is None else round(info["rahmen_x"] / feld),
            None if info["rot_x"] is None else round(info["rot_x"] / feld),
        )
        if ziel == self.letztes_ziel and jetzt - self.letzter_klick < KLICK_SPERRE:
            return False
        self.letztes_ziel = ziel
        self.letzter_klick = jetzt
        return True


# ------------------------------------------------------- Windows: Maus, Tasten

if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)

    MOUSEEVENTF_RIGHTDOWN = 0x0008
    MOUSEEVENTF_RIGHTUP = 0x0010
    INPUT_MOUSE = 0

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wintypes.LONG),
            ("dy", wintypes.LONG),
            ("mouseData", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
        ]

    class INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [("mi", MOUSEINPUT), ("_pad", ctypes.c_byte * 32)]

        _anonymous_ = ("u",)
        _fields_ = [("type", wintypes.DWORD), ("u", _U)]

    class CURSORINFO(ctypes.Structure):
        _fields_ = [
            ("cbSize", wintypes.DWORD),
            ("flags", wintypes.DWORD),
            ("hCursor", wintypes.HANDLE),
            ("ptScreenPos", wintypes.POINT),
        ]

    user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
    user32.SendInput.restype = wintypes.UINT
    user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
    user32.GetAsyncKeyState.restype = ctypes.c_short
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    user32.GetCursorInfo.argtypes = [ctypes.POINTER(CURSORINFO)]

    def _maus(flag):
        inp = INPUT(type=INPUT_MOUSE)
        inp.mi = MOUSEINPUT(0, 0, 0, flag, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def rechtsklick():
        _maus(MOUSEEVENTF_RIGHTDOWN)
        time.sleep(0.04)
        _maus(MOUSEEVENTF_RIGHTUP)

    def taste_gedrueckt(vk):
        return bool(user32.GetAsyncKeyState(vk) & 0x8000)

    def mauszeiger_sichtbar():
        """Im Spiel versteckt Minecraft den Mauszeiger. Ist er sichtbar, ist ein
        Menue offen (Inventar, Truhe, Chat, Pause) - dann wird nicht geklickt."""
        info = CURSORINFO(cbSize=ctypes.sizeof(CURSORINFO))
        if not user32.GetCursorInfo(ctypes.byref(info)):
            return False
        return bool(info.flags & 1) and bool(info.hCursor)

    def minecraft_fenster():
        """Liefert (links, oben, breite, hoehe) der Spielflaeche, wenn Minecraft aktiv ist."""
        hwnd = user32.GetForegroundWindow()
        if not hwnd:
            return None
        laenge = user32.GetWindowTextLengthW(hwnd)
        titel = ctypes.create_unicode_buffer(laenge + 1)
        user32.GetWindowTextW(hwnd, titel, laenge + 1)
        if "minecraft" not in titel.value.lower():
            return None
        rect = wintypes.RECT()
        user32.GetClientRect(hwnd, ctypes.byref(rect))
        punkt = wintypes.POINT(0, 0)
        user32.ClientToScreen(hwnd, ctypes.byref(punkt))
        if rect.right < 100 or rect.bottom < 100:
            return None
        return punkt.x, punkt.y, rect.right, rect.bottom

    def dpi_scharf():
        try:
            ctypes.WinDLL("shcore").SetProcessDpiAwareness(2)
        except Exception:
            try:
                user32.SetProcessDPIAware()
            except Exception:
                pass

VK_F8, VK_F10, VK_F12 = 0x77, 0x79, 0x7B


# ------------------------------------------------------------------ Hauptteil

class Tastenwaechter:
    """Meldet jeden Tastendruck genau einmal (nicht, solange sie gehalten wird)."""

    def __init__(self):
        self.vorher = {}

    def neu(self, vk):
        jetzt = taste_gedrueckt(vk)
        war = self.vorher.get(vk, False)
        self.vorher[vk] = jetzt
        return jetzt and not war


def sag(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


def main():
    if sys.platform != "win32":
        print("Der Angel-Bot laeuft nur unter Windows.")
        return
    try:
        import mss
        import mss.tools
    except ImportError:
        print("Es fehlt 'mss'. Bitte Angel-Bot.bat per Doppelklick starten (installiert alles).")
        return

    dpi_scharf()
    tasten = Tastenwaechter()
    klicker = Klicker()

    print(HILFE)
    sag("Bereit. Geh in Minecraft, nimm die Angel in die Hand (nicht auswerfen),"
        " schau aufs Wasser und druecke F8.")

    aktiv = False
    zustand = "auswerfen"   # auswerfen -> warten -> spiel -> nach_fang -> auswerfen
    seit = time.monotonic()
    zuletzt_leiste = 0.0
    treffer = 0
    runden = 0
    rand_gewarnt = False
    warte_grund = None
    # Erst wenn der Mauszeiger einmal im Spiel versteckt war, wissen wir sicher,
    # dass "Zeiger sichtbar" wirklich "Menue offen" bedeutet.
    zeiger_geprueft = False
    takt = 1.0 / BILDER_PRO_SEKUNDE

    with mss.mss() as kamera:
        while True:
            start = time.monotonic()

            if tasten.neu(VK_F12):
                sag("Beendet. Minispiele gespielt: %d" % runden)
                return
            if tasten.neu(VK_F8):
                aktiv = not aktiv
                zustand = "auswerfen"
                seit = time.monotonic()
                warte_grund = None
                sag("LAEUFT" if aktiv else "PAUSE (F8 = weiter)")

            # Nur arbeiten, wenn Minecraft vorne ist und kein Menue offen ist.
            fenster = minecraft_fenster()
            if fenster is not None:
                sichtbar = mauszeiger_sichtbar()
                if not sichtbar:
                    zeiger_geprueft = True
            grund = None
            if fenster is None:
                grund = "Minecraft ist nicht im Vordergrund - ich warte."
            elif zeiger_geprueft and sichtbar:
                grund = "Ein Menue ist offen (Inventar, Chat, Pause ...) - ich warte."
            if grund:
                if aktiv and grund != warte_grund:
                    sag(grund)
                warte_grund = grund
                time.sleep(0.1)
                continue
            if warte_grund and aktiv:
                sag("Weiter geht's.")
            warte_grund = None

            links, oben, breite, hoehe = fenster
            y_von = int(hoehe * STREIFEN_OBEN)
            y_bis = int(hoehe * STREIFEN_UNTEN)
            bereich = {"left": links, "top": oben + y_von, "width": breite, "height": y_bis - y_von}
            try:
                roh = kamera.grab(bereich)
            except Exception as fehler:
                sag("Bildschirmfoto ging nicht (%s) - versuche es gleich nochmal." % fehler)
                time.sleep(0.5)
                continue
            bild = np.asarray(roh)[:, :, 2::-1]  # BGRA -> RGB
            info = erkenne(bild)

            if tasten.neu(VK_F10):
                name = time.strftime("diagnose_%H%M%S.png")
                mss.tools.to_png(roh.rgb, roh.size, output=name)
                sag("Diagnose-Bild gespeichert: %s  Erkennung: %s" % (name, info))

            if not aktiv:
                time.sleep(0.05)
                continue

            jetzt = time.monotonic()
            if info is not None:
                zuletzt_leiste = jetzt
                if info["abgeschnitten"] and not rand_gewarnt:
                    rand_gewarnt = True
                    sag("Achtung: Die Leiste ist am Fensterrand abgeschnitten! Liegt das rote Feld"
                        " ausserhalb, kann ich es nicht sehen. Mach das Minecraft-Fenster gross"
                        " (maximieren) oder stell in den Optionen die GUI-Groesse kleiner.")

            if zustand == "auswerfen":
                if info is not None:
                    zustand, seit, treffer = "spiel", jetzt, 0  # Minispiel laeuft schon
                else:
                    rechtsklick()
                    sag("Ausgeworfen, warte auf einen Biss ...")
                    zustand, seit = "warten", jetzt

            elif zustand == "warten":
                if info is not None:
                    sag("Biss! Minispiel laeuft.")
                    zustand, seit, treffer = "spiel", jetzt, 0
                elif jetzt - seit > WARTEN_MAX:
                    sag("Kein Biss nach %d s - ich hole ein und werfe neu aus." % WARTEN_MAX)
                    rechtsklick()
                    time.sleep(1.0)
                    zustand = "auswerfen"

            elif zustand == "spiel":
                if info is not None and klicker.soll_klicken(info, jetzt):
                    rechtsklick()
                    treffer += 1
                    sag("  Treffer %d" % treffer)
                elif jetzt - zuletzt_leiste > SPIEL_VORBEI_NACH:
                    runden += 1
                    sag("Minispiel vorbei (%d Treffer). Schon %d Minispiele gespielt." % (treffer, runden))
                    zustand, seit = "nach_fang", jetzt

            elif zustand == "nach_fang":
                if info is not None:
                    zustand = "spiel"  # Leiste war nur kurz weg, das Spiel laeuft noch
                elif jetzt - seit > NACH_FANG_PAUSE:
                    zustand = "auswerfen"

            rest = takt - (time.monotonic() - start)
            if rest > 0:
                time.sleep(rest)


if __name__ == "__main__":
    main()
