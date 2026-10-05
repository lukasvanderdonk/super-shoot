@echo off & goto :batch
r'''
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
  Ein Klick daneben kostet einen Haken (rotes X).

Je naeher der Fang, desto schneller springt der Rahmen. Darum schaut der Bot
voraus: Er misst, wie schnell der Rahmen ist und wie lange sein Klick bis zum
Server braucht. Waere der Rahmen schon weiter, wenn der Klick ankommt, klickt
er entsprechend frueher - wenn noetig schon ein paar Felder vorher.
Aus jedem Treffer und jedem Fehlklick lernt er, wie viel frueher er klicken
muss (den "Vorlauf"), und wie schnell der Rahmen nach dem 1., 2., 3. ...
Treffer normalerweise ist. Das merkt er sich fuer das naechste Mal.

Der Bot schaut sich dafuer den Bildschirm an (nur das Minecraft-Fenster) und
klickt selbst. Er klickt nur, solange Minecraft das aktive Fenster ist und
kein Menue (Inventar, Chat, Pause) offen ist.

Beim Start fragt der Bot, wie viele Minispiele er spielen soll (danach macht er
Pause und piept, F8 = nochmal so viele) und auf welchem Platz die Angel liegt.

Nach jedem Auswerfen schaut er im Inventar nach, wie viel Haltbarkeit die Angel
noch hat (Maus ueber den Angel-Platz, Infokasten lesen). Kann er sie nicht lesen,
rechnet er mit 1 weniger als beim letzten Mal. Ist sie unter 5, hoert er sofort
auf und drueckt einmal die Leertaste - damit die Angel nicht kaputtgeht.

Tasten:  F8 = Start / Pause   F10 = Diagnose-Bild speichern   F12 = Beenden
"""

import json
import re
import sys
import time

import numpy as np

# ---------------------------------------------------------------- Einstellungen

SPIELE_ZIEL = None       # nach so vielen Minispielen anhalten (None = beim Start fragen, 0 = nie)
HALTBARKEIT_MIN = 5      # Angel pruefen: Haltbarkeit darunter -> anhalten und Leertaste (0 = nie pruefen)
ANGEL_PLATZ = None       # Platz der Angel in der untersten Inventar-Reihe, 1 (links) bis 9 (None = beim Start fragen)
ANGEL_MAX = 64           # volle Haltbarkeit einer Angel (zur Kontrolle, dass es wirklich die Angel ist)
HALTBARKEIT_START = None # Haltbarkeit der Angel beim Start (None = beim Start fragen, z. B. 64 = neue Angel)
INVENTAR_TASTE = "I"     # Taste, mit der sich in Minecraft das Inventar oeffnet
WARTEN_MAX = 60.0        # Sekunden ohne Biss, dann einholen und neu auswerfen
NACH_FANG_PAUSE = 1.5    # Sekunden nach dem Fang, bevor neu ausgeworfen wird
SPIEL_VORBEI_NACH = 0.6  # so lange muss die Leiste weg sein, dann ist das Spiel vorbei
VERZOEGERUNG_START = 0.15  # Sekunden, bis ein Klick beim Server ist und man es sieht (wird gelernt)
VERZOEGERUNG_MAX = 1.5   # mehr als das gilt als Ruckler und wird nicht gelernt
ZIEL = 0.5               # wo im Zeitfenster "Rahmen steht auf Rot" der Klick ankommen soll (0.5 = Mitte)
SICHERHEIT = 0.2         # so viel vom Ende des Zeitfensters wird gemieden (Fehlklick kostet einen Haken!)
SICHT_GRENZE = 0.6       # "auf Sicht" nur klicken, wenn der Klick in den ersten 60 % der Zeit auf Rot ankommt
ERFAHRUNG = 30           # aus so vielen der letzten Klicks lernt er den richtigen Vorlauf
LERN_DATEI = "angelbot_gelernt.json"
SERVER_TICK = 0.05       # Minecraft-Server rechnen in Schritten von 50 ms
BILDER_PRO_SEKUNDE = 60  # wie oft der Bildschirm angeschaut wird

# Die Leiste ist ein Minecraft-Titel: knapp ueber der Bildschirmmitte.
# Nur dieser Streifen des Fensters wird angeschaut (Anteil der Fensterhoehe).
STREIFEN_OBEN = 0.20
STREIFEN_UNTEN = 0.65
FELDER = 10              # so viele Felder hat die Leiste
GUI_BREITE = 400         # so breit ist die Leiste in Minecraft-GUI-Einheiten (10 Felder x 40)


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


def erkenne(bild, mitte_x=None):
    """Sucht die Minispiel-Leiste im Bild.

    Rueckgabe: None, wenn keine Leiste zu sehen ist, sonst ein dict mit
      auf_rot   True, wenn der weisse Rahmen gerade auf dem roten Feld steht
      rot_x     Mitte des roten Felds (oder None)
      rahmen_x  Mitte des weissen Rahmens (oder None)
      feld      ungefaehre Breite eines Felds in Pixeln
      abstand   Abstand von Feldmitte zu Feldmitte in Pixeln
      rot_unten rote Pixel unter der Leiste (rote X auf den Haken = Fehlklicks)
      rot_feld, rahmen_feld  Feld-Nummern (nur der Unterschied zaehlt) oder None
      abgeschnitten  True, wenn ein Feld ganz am Rand so gut wie nicht zu sehen ist
      versteckt Pixel der Leiste, die links und rechts aus dem Fenster ragen
      y0, y1    obere / untere Zeile der Leiste

    mitte_x: wo die Fenstermitte im Bild liegt (Standard: Bildmitte). Die Leiste steht
    als Minecraft-Titel immer in der Mitte des Fensters.
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
    # Die Leiste ist fast ganz tuerkis (nur ein Feld ist rot) - eine Reihe Herzen nicht.
    tuerkise_felder = sum(1 for s, e in felder if tuerkis[beste, s:e].mean() > 0.5)
    if tuerkise_felder < 3:
        return None

    # Abstand von Feld zu Feld (Mitte zu Mitte)
    mitten = [(s + e) / 2.0 for (s, e), g in zip(felder, gleich) if g]
    schritte = [b - a for a, b in zip(mitten, mitten[1:]) if feld < b - a < feld * 1.8]
    abstand = float(np.median(schritte)) if schritte else feld * 1.25

    # 3. Hoehe der Leiste: alle Zeilen um die beste herum, die fast genauso voll sind.
    schwelle = zeilen_summe[beste] * 0.5
    y0 = beste
    while y0 > 0 and zeilen_summe[y0 - 1] >= schwelle:
        y0 -= 1
    y1 = beste
    while y1 < hoehe - 1 and zeilen_summe[y1 + 1] >= schwelle:
        y1 += 1
    h = y1 - y0 + 1
    # Die Felder sind etwa doppelt so breit wie hoch und randvoll mit Farbe.
    # Buchstaben (Chat, ein ausblendendes "Yeah!" vor hellem Himmel) oder Herzen nicht.
    if h < 6 or not 1.6 <= feld / h <= 3.2:
        return None
    voll = [farbig[y0:y1 + 1, s:e].mean() for (s, e), g in zip(felder, gleich) if g]
    if sum(1 for v in voll if v > 0.75) < 3:
        return None

    # 4. Rotes Feld: Spalten, die in der Leiste ueberwiegend rot sind.
    rot_spalten = rot[y0:y1 + 1].sum(axis=0) >= h * 0.5
    rot_stuecke = [(s, e) for s, e in laeufe(rot_spalten) if e - s >= feld * 0.15]

    # 5. Weisser Rahmen: er hat weisse Kanten direkt ueber UND unter der Leiste
    #    (das Fadenkreuz liegt nur darunter, der Fortschrittsbalken auch).
    rand = max(2, int(round(h * 0.6)))
    oben = weiss[max(0, y0 - rand):y0].any(axis=0)
    unten = weiss[y1 + 1:min(hoehe, y1 + 1 + rand)].any(axis=0)
    rahmen_roh = oben & unten
    # Der Rahmen umschliesst ein ganzes Feld. Schmalere Stuecke sind Schrift ueber und unter
    # der Leiste (z. B. von der Punkte-Tafel des Servers) - die zaehlen nicht. Nur am
    # Bildrand darf der Rahmen angeschnitten sein.
    rahmen_spalten = np.zeros_like(rahmen_roh)
    rahmen_stuecke = []
    for s, e in laeufe(rahmen_roh):
        if e - s >= feld * 0.6 or ((s == 0 or e == breite) and e - s >= feld * 0.15):
            rahmen_spalten[s:e] = True
            rahmen_stuecke.append((s, e))

    # 6. Steht der Rahmen auf dem roten Feld? (Am Fensterrand kann das Feld halb
    #    abgeschnitten sein, darum reicht schon ein Stueck davon.)
    im_rahmen_rot = int((rot_spalten & rahmen_spalten).sum())
    auf_rot = im_rahmen_rot >= max(2, feld * 0.15)

    # 7. Feld-Raster: Wo liegen die Feldmitten? Aus den ganz sichtbaren Feldern bestimmt -
    #    so wird auch ein am Fensterrand halb abgeschnittenes Feld richtig eingeordnet.
    winkel = 2 * np.pi * np.array(mitten) / abstand
    phase = float(np.angle(np.exp(1j * winkel).mean()) / (2 * np.pi))

    def feld_nr(x):
        return None if x is None else int(round(x / abstand - phase))

    # 8. Ragt die Leiste ueber den Fensterrand? Sie steht als Minecraft-Titel in der Mitte
    #    des Fensters, ragt also links und rechts gleich weit hinaus. Ist vom aeussersten
    #    Feld weniger als ein Fuenftel zu sehen, kann dort ein rotes Feld unbemerkt liegen.
    zeile = farbig[y0:y1 + 1].any(axis=0) | rahmen_spalten
    am_rand = bool(zeile[:2].any() or zeile[-2:].any())
    leiste = FELDER * abstand - (abstand - feld)
    versteckt = max(0.0, (leiste - breite) / 2) if am_rand else 0.0
    abgeschnitten = versteckt > 0.8 * feld

    # 9. Rote Pixel unter der Leiste: Dort erscheint bei einem Fehlklick ein rotes X
    #    auf einem der Haken. Steigt die Zahl, war der Klick daneben. Nur links schauen:
    #    Die Haken stehen links und rechts unter der Leiste (die X erscheinen auf beiden
    #    Seiten), rechts kann aber die Punkte-Tafel des Servers mit roter Schrift stehen.
    mitte = breite / 2.0 if mitte_x is None else mitte_x
    u0 = min(hoehe, y1 + 1 + int(h * 0.8))
    u1 = min(hoehe, y1 + 1 + int(h * 3))
    hx0 = int(max(0, mitte - 5.3 * abstand))
    hx1 = int(min(breite, max(hx0, mitte - 2.0 * abstand)))
    rot_unten = int(rot[u0:u1, hx0:hx1].sum())

    def mitte(stuecke):
        if not stuecke:
            return None
        s, e = max(stuecke, key=lambda t: t[1] - t[0])
        return (s + e) / 2.0

    return {
        "auf_rot": bool(auf_rot),
        "rot_x": mitte(rot_stuecke),
        "rahmen_x": mitte(rahmen_stuecke),
        "rot_feld": feld_nr(mitte(rot_stuecke)),
        "rahmen_feld": feld_nr(mitte(rahmen_stuecke)),
        "feld": feld,
        "abstand": abstand,
        "abgeschnitten": abgeschnitten,
        "versteckt": versteckt,
        "rot_unten": rot_unten,
        "y0": y0,
        "y1": y1,
    }


class Vorausschau:
    """Plant die Klicks im Minispiel.

    Langsamer Rahmen: klicken, sobald er auf dem roten Feld steht.
    Schneller Rahmen: Ein Klick braucht eine Weile, bis der Server ihn hat. Waere
    der Rahmen bis dahin schon weiter, klickt der Bot vorher - um den "Vorlauf" -
    so, dass der Klick in der Mitte der Zeit ankommt, in der der Rahmen auf Rot steht.

    Den Vorlauf lernt er aus Erfahrung: Jeder Klick verraet etwas darueber.
    Bei einem Treffer muss der Vorlauf in einem bestimmten Bereich liegen
    (sonst waere der Klick zu frueh oder zu spaet angekommen), bei einem
    Fehlklick ausserhalb davon. Aus den letzten ERFAHRUNG Klicks nimmt er den
    Vorlauf, der zu den meisten Ergebnissen passt (die Mitte davon). Neuere
    Klicks zaehlen mehr. Das klappt auch dann, wenn der Server Treffer und rote X
    erst verzoegert anzeigt - die angezeigte Antwortzeit ist dann laenger als der
    Weg des Klicks und taugt nur als Startwert.

    Ausserdem merkt er sich, wie schnell der Rahmen nach dem 1., 2., 3. ...
    Treffer normalerweise ist (Tempo-Gedaechtnis). Alles landet in LERN_DATEI.
    """

    def __init__(self, gelernt=None):
        gelernt = gelernt or {}
        start = gelernt.get("verzoegerung")
        # Die Antwortzeit vom letzten Mal ist nur ein Startwert - neue Messungen ersetzen ihn schnell.
        self.hat_startwert = isinstance(start, (int, float)) and 0.02 < start < VERZOEGERUNG_MAX
        self.messungen = [float(start)] if self.hat_startwert else []
        self.erfahrung = []  # (von, bis, getroffen): Bereich des Vorlaufs, in dem dieser Klick getroffen haette
        for e in gelernt.get("erfahrung") or []:
            try:
                von, bis, ok = float(e[0]), float(e[1]), bool(e[2])
                if -1.0 < von < bis < 3.0:
                    self.erfahrung.append((von, bis, ok))
            except (TypeError, ValueError, IndexError):
                pass
        del self.erfahrung[:-ERFAHRUNG]
        self.tempo = {}  # Treffer im Spiel -> gemessene Sekunden pro Feld
        for stufe, werte in (gelernt.get("tempo") or {}).items():
            try:
                self.tempo[int(stufe)] = [float(w) for w in werte if 0.03 < float(w) < 2.0][-7:]
            except (TypeError, ValueError):
                pass
        self.neu_gemessen = 0  # Messungen in dieser Sitzung
        self.meldungen = []
        self._vorlauf = None
        self.bild_abstand = 1.0 / BILDER_PRO_SEKUNDE  # gemessen: so oft schaut der Bot wirklich hin
        self.letztes_bild = None
        self.neues_spiel()

    def gelernt(self):
        return {"verzoegerung": round(self.verzoegerung(), 4),
                "vorlauf": round(self.vorlauf(), 4),
                "erfahrung": [[round(a, 3), round(b, 3), int(ok)] for a, b, ok in self.erfahrung],
                "tempo": {str(k): [round(w, 3) for w in v] for k, v in sorted(self.tempo.items()) if v}}

    def neues_spiel(self):
        self.rahmen_x = None   # letzte gesehene Rahmenposition (Pixel)
        self.richtung = 0      # +1 = nach rechts, -1 = nach links, 0 = unbekannt
        self.ankuenfte = []    # wann der Rahmen auf den letzten Feldern angekommen ist (lueckenlos, seit dem letzten Treffer)
        self.letzte_ankunft = None  # wann er auf seinem jetzigen Feld angekommen ist (auch ueber Treffer hinweg)
        self.gerade_gesprungen = False
        self.takt_alt = None   # Tempo vor dem letzten Treffer
        self.treffer = 0       # Treffer in diesem Spiel
        self.klick = None      # letzter Klick, dessen Ergebnis noch aussteht

    # ---------------------------------------------------------- Schaetzungen

    def verzoegerung(self):
        """Angezeigte Antwortzeit: vom Klick, bis das rote Feld springt oder das X erscheint."""
        if not self.messungen:
            return VERZOEGERUNG_START
        return min(VERZOEGERUNG_MAX, max(0.03, float(np.median(self.messungen[-5:]))))

    def vorlauf(self):
        """Um so viel frueher muss geklickt werden, als man es sieht."""
        if self._vorlauf is None:
            self._vorlauf = self._lerne_vorlauf()
        return self._vorlauf

    def _lerne_vorlauf(self):
        treffer = sum(1 for e in self.erfahrung if e[2])
        if treffer < 1 and len(self.erfahrung) < 2:
            # Noch keine Erfahrung: aus der angezeigten Antwortzeit schaetzen (ohne die
            # Wartezeit auf den naechsten Server-Tick, im Schnitt ein halber Tick).
            return max(0.02, self.verzoegerung() - SERVER_TICK / 2)
        # Der Vorlauf kann nicht laenger sein als die angezeigte Antwortzeit - die enthaelt
        # ja den Weg des Klicks (und vielleicht noch etwas Wartezeit, bis der Server es anzeigt).
        werte = np.arange(0.02, min(VERZOEGERUNG_MAX, self.verzoegerung() + 0.05), 0.005)
        punkte = np.zeros(len(werte))
        n = len(self.erfahrung)
        for alter, (von, bis, ok) in enumerate(reversed(self.erfahrung)):
            gewicht = 0.92 ** alter  # neuere Klicks zaehlen mehr
            drin = (werte > von) & (werte <= bis)
            punkte += gewicht * drin if ok else -gewicht * drin
        beste = werte[punkte >= punkte.max() - 1e-9]
        # Bei mehreren gleich guten Stellen: das zusammenhaengende Stueck, dann dessen Mitte.
        stuecke = np.split(beste, np.flatnonzero(np.diff(beste) > 0.0075) + 1)
        stueck = max(stuecke, key=len)
        return max(0.02, float((stueck[0] + stueck[-1]) / 2)) if n else max(0.02, self.verzoegerung())

    def bestes_tempo(self):
        """Beste Schaetzung fuer die Zeit pro Feld (nicht die vorsichtige)."""
        return self.takt() or self.gemerktes_tempo() or self.takt_alt

    def gemerktes_tempo(self):
        werte = self.tempo.get(self.treffer)
        return float(np.median(werte)) if werte else None

    def takt(self):
        """Sekunden pro Feld, gemessen seit dem letzten Treffer (der Rahmen wird mit
        jedem Treffer schneller). Nach nur einem Schritt hilft das Tempo-Gedaechtnis."""
        if len(self.ankuenfte) == 2:
            einzeln = self.ankuenfte[1] - self.ankuenfte[0]
            gemerkt = self.gemerktes_tempo()
            if gemerkt and abs(einzeln - gemerkt) < 0.2 * gemerkt:
                return gemerkt
            return None
        if len(self.ankuenfte) < 3:
            return None
        # Eine Gerade durch alle Ankunftszeiten seit dem letzten Treffer: Das mittelt
        # das Zittern einzelner Bilder viel besser heraus als einzelne Abstaende.
        T = self._gerade()[1]
        abstaende = np.diff(self.ankuenfte)
        if len(abstaende) >= 3 and max(abstaende[-2:]) < T * 0.85:
            T = float(np.mean(abstaende[-2:]))  # wird gerade schneller
        gerundet = round(T / SERVER_TICK) * SERVER_TICK
        if gerundet > 0 and abs(T - gerundet) < 0.02:
            T = gerundet  # der Server springt nur zu vollen Ticks
        return T

    def _gerade(self):
        """Ausgleichsgerade t = a + i*T durch die Ankunftszeiten -> (a, T)."""
        t = np.array(self.ankuenfte)
        i = np.arange(len(t))
        T, a = np.polyfit(i, t, 1)
        return float(a), float(T)

    def takt_vorsichtig(self):
        """Kuerzeste plausible Zeit pro Feld - fuer die Frage "ist es schon zu spaet?"."""
        if len(self.ankuenfte) >= 2:
            kuerzester = float(np.min(np.diff(self.ankuenfte[-4:])))
            T = self.takt()
            return kuerzester if T is None else min(T, kuerzester)
        gemerkt = self.gemerktes_tempo()
        if gemerkt is not None:
            return gemerkt * 0.9
        if self.takt_alt is not None:
            return self.takt_alt * 0.7  # nach einem Treffer ist er schneller geworden
        return None

    def ankunft(self, T):
        """Wann der Rahmen auf seinem jetzigen Feld angekommen ist - ueber mehrere
        Schritte gemittelt, damit ein einzelnes spaetes Bild nicht stoert."""
        if not self.ankuenfte:
            return None
        if T is None or len(self.ankuenfte) < 3:
            return self.ankuenfte[-1]
        k = len(self.ankuenfte) - 1
        return float(np.median([t + (k - i) * T for i, t in enumerate(self.ankuenfte)]))

    # ------------------------------------------------------------ pro Bild

    def schritt(self, info, jetzt):
        """Fuer jedes Bild aufrufen. Gibt einen Grund zurueck, wenn jetzt geklickt werden soll."""
        if info is None:
            # Leiste weg kurz nach einem Klick: das war der letzte, entscheidende Treffer.
            if self.klick is not None and jetzt - self.klick["zeit"] < VERZOEGERUNG_MAX:
                self._ergebnis(True, jetzt)
            self.klick = None
            return None

        if self.letztes_bild is not None and 0 < jetzt - self.letztes_bild < 0.5:
            self.bild_abstand = 0.9 * self.bild_abstand + 0.1 * (jetzt - self.letztes_bild)
        self.letztes_bild = jetzt
        abstand = info["abstand"]
        self._verfolge_rahmen(info["rahmen_x"], jetzt, abstand)
        if self.klick is not None and self.gerade_gesprungen and info["auf_rot"] and not self.klick["gesehen"]:
            # Nach einem vorausschauenden Klick kommt der Rahmen auf Rot an: Jetzt wissen
            # wir genau, wann - besser als die Vorhersage.
            self.klick["ankunft"], self.klick["gesehen"] = self.ankunft(self.takt()) or jetzt, True
        self._pruefe_klick(info, jetzt, abstand)
        if self.klick is not None:
            return None  # erst abwarten, was der letzte Klick bewirkt hat

        L = self.vorlauf()
        T = self.takt()

        # Plan: Wann kommt der Rahmen auf Rot an (oder kam er an, wenn er schon drauf
        # steht), und wann muss der Klick los, damit er in der Mitte dieser Zeit ankommt?
        # Das gilt fuer "auf Sicht" (0 Felder) und "vorausschauend" (1-4 Felder) gleich.
        if T is not None and self.ankuenfte and info["rot_feld"] is not None and info["rahmen_feld"] is not None:
            d = info["rot_feld"] - info["rahmen_feld"]
            felder = 0 if info["auf_rot"] else abs(d)
            vor_dem_rahmen = felder == 0 or (self.richtung and (d > 0) == (self.richtung > 0))
            if vor_dem_rahmen and felder <= 4:
                if felder > 0 and self.neu_gemessen == 0 and not self.hat_startwert and not self.erfahrung:
                    return None  # erst einmal selbst messen, wie lange ein Klick braucht
                ankunft_rot = self.ankunft(T) + felder * T
                klick_zeit = ankunft_rot + ZIEL * T - L
                if jetzt < klick_zeit - 0.5 * self.bild_abstand:
                    return None  # noch nicht (das naechste Bild ist naeher dran)
                if jetzt + L > ankunft_rot + (1 - SICHERHEIT) * T:
                    return None  # kaeme zu spaet an - beim naechsten Durchgang
                art = "auf Sicht" if felder == 0 else "vorausschauend, %d Feld frueher" % felder
                return self._klicke(info, jetzt, art, ankunft_rot, T, felder == 0)
            return None

        # Tempo noch unbekannt (Spielbeginn, gleich nach einem Treffer): auf Sicht, aber nur,
        # wenn der Klick sicher frueh genug ankommt.
        if info["auf_rot"]:
            vorsichtig = self.takt_vorsichtig()
            ankunft = self.ankuenfte[-1] if self.ankuenfte else self.letzte_ankunft
            if ankunft is not None and vorsichtig is not None:
                if jetzt + L > ankunft + vorsichtig * SICHT_GRENZE:
                    return None  # kaeme zu spaet an - lieber beim naechsten Durchgang
            # Nur wenn klar ist, seit wann der Rahmen auf Rot steht, taugt der Klick zum Lernen.
            nuetzlich = bool(self.ankuenfte) and self.ankuenfte[-1] == self.letzte_ankunft
            return self._klicke(info, jetzt, "auf Sicht", self.ankuenfte[-1] if nuetzlich else None,
                                self.bestes_tempo(), True)
        return None

    # ------------------------------------------------------------ intern

    def _verfolge_rahmen(self, x, jetzt, abstand):
        self.gerade_gesprungen = False
        if x is None:  # Rahmen gerade nicht zu sehen
            self.rahmen_x, self.richtung, self.ankuenfte, self.letzte_ankunft = None, 0, [], None
            return
        if self.rahmen_x is None:
            self.rahmen_x = x  # wann er hier angekommen ist, wissen wir nicht
            return
        dx = x - self.rahmen_x
        if abs(dx) < abstand * 0.5:
            return  # noch auf demselben Feld
        if abs(dx) < abstand * 1.5:
            self.richtung = 1 if dx > 0 else -1
            self.ankuenfte.append(jetzt)
            del self.ankuenfte[:-8]
        else:
            self.richtung, self.ankuenfte = 0, [jetzt]
        self.rahmen_x, self.letzte_ankunft, self.gerade_gesprungen = x, jetzt, True

    def _pruefe_klick(self, info, jetzt, abstand):
        k = self.klick
        if k is None:
            return
        h = info["y1"] - info["y0"] + 1
        dauer = jetzt - k["zeit"]
        if info["rot_x"] is not None and k["rot_x"] is not None and abs(info["rot_x"] - k["rot_x"]) > abstand * 0.5:
            self._ergebnis(True, jetzt)
            self.meldungen.append("    Treffer! (Antwort nach %d ms)" % (dauer * 1000))
            T = self.takt()
            if T is not None:  # fuers Tempo-Gedaechtnis
                self.tempo.setdefault(self.treffer, []).append(T)
                del self.tempo[self.treffer][:-7]
            self.takt_alt = T or self.takt_vorsichtig() or self.takt_alt
            self.ankuenfte = []  # neues Tempo ab jetzt
            self.treffer += 1
        elif info["rot_unten"] > k["rot_unten"] + max(20, h * h * 0.15):
            vorher = self.vorlauf()
            self._ergebnis(False, jetzt)
            nachher = self.vorlauf()
            if abs(nachher - vorher) < 0.005:
                warum = "Vorlauf bleibt bei %d ms" % (nachher * 1000)
            else:
                warum = "%s - Vorlauf jetzt %d ms statt %d ms" % (
                    "war zu frueh" if nachher < vorher else "war zu spaet", nachher * 1000, vorher * 1000)
            self.meldungen.append("    Daneben (Haken weg, Antwort nach %d ms), %s." % (dauer * 1000, warum))
        elif dauer > VERZOEGERUNG_MAX:
            self.klick = None  # kein Ergebnis zu sehen - weitermachen

    def _ergebnis(self, getroffen, jetzt):
        """Ein Klick hat getroffen oder nicht: Antwortzeit und Erfahrung lernen."""
        k = self.klick
        self.klick = None
        self._vorlauf = None  # neu ausrechnen
        dauer = jetzt - k["zeit"]
        if 0.02 < dauer < VERZOEGERUNG_MAX:
            self.messungen.append(dauer)
            del self.messungen[:-9]
            self.neu_gemessen += 1
        if k["ankunft"] is not None and k["T"]:
            # Mit welchem Vorlauf haette dieser Klick getroffen? Mit jedem, bei dem er
            # ankommt, waehrend der Rahmen auf Rot steht.
            von = k["ankunft"] - k["zeit"]
            self.erfahrung.append((von, von + k["T"], getroffen))
            del self.erfahrung[:-ERFAHRUNG]
            self._vorlauf = None

    def _klicke(self, info, jetzt, art, ankunft, T, gesehen):
        self.klick = {"zeit": jetzt, "art": art, "rot_x": info["rot_x"], "rot_unten": info["rot_unten"],
                      "ankunft": ankunft, "T": T, "gesehen": gesehen}
        return art


# ------------------------------------------------------------- Haltbarkeit lesen

# Die Ziffern der Minecraft-Schrift (je 5 x 7 Pixel) und der Schraegstrich.
SCHRIFT = {
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "2": [".###.", "#...#", "....#", "..##.", ".#...", "#...#", "#####"],
    "3": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
    "4": ["...##", "..#.#", ".#..#", "#...#", "#####", "....#", "....#"],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "#...#", "....#", "...#.", "..#..", "..#..", "..#.."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
}
_VORLAGEN = {z: np.array([[c == "#" for c in reihe] for reihe in muster]) for z, muster in SCHRIFT.items()}


def finde_infokasten(bild, p):
    """Sucht den dunkel-lila Infokasten (Tooltip) -> (x0, y0, x1, y1) oder None.
    p = Bild-Pixel pro Minecraft-Pixel."""
    r = bild[:, :, 0].astype(np.int16)
    g = bild[:, :, 1].astype(np.int16)
    b = bild[:, :, 2].astype(np.int16)
    # Dunkles Lila (Hintergrund 16,0,16 und lila Rand): rot und blau deutlich ueber gruen.
    maske = (r - g >= 6) & (b - g >= 6) & (r < 70) & (b < 100)
    # In Kaestchen von 2 Schrift-Pixeln zusammenfassen - so unterbricht die Schrift die Flaeche nicht.
    k = max(2, int(round(2 * p)))
    h2, w2 = maske.shape[0] // k, maske.shape[1] // k
    if h2 < 3 or w2 < 3:
        return None
    feld = maske[:h2 * k, :w2 * k].reshape(h2, k, w2, k).mean(axis=(1, 3)) > 0.25
    # Groesste zusammenhaengende Flaeche suchen
    gesehen = np.zeros_like(feld)
    beste = None
    for sy, sx in zip(*np.nonzero(feld)):
        if gesehen[sy, sx]:
            continue
        stapel, punkte = [(sy, sx)], []
        gesehen[sy, sx] = True
        while stapel:
            y, x = stapel.pop()
            punkte.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h2 and 0 <= nx < w2 and feld[ny, nx] and not gesehen[ny, nx]:
                    gesehen[ny, nx] = True
                    stapel.append((ny, nx))
        if beste is None or len(punkte) > len(beste):
            beste = punkte
    if beste is None or len(beste) < 12:
        return None
    ys = [q[0] for q in beste]
    xs = [q[1] for q in beste]
    return min(xs) * k, min(ys) * k, (max(xs) + 1) * k, (max(ys) + 1) * k


def lies_zeile(helligkeit, p):
    """Liest eine Textzeile (helligkeit = max(R,G,B) je Pixel) bei p Bild-Pixeln pro
    Schrift-Pixel. Gibt die erkannten Zeichen zurueck (Ziffern und /, sonst ?)."""
    bestes = None
    schritt = max(0.2, p / 6)
    for oy in np.arange(0, p, schritt):
        for ox in np.arange(0, p, schritt):
            reihen = int((helligkeit.shape[0] - oy) / p)
            spalten = int((helligkeit.shape[1] - ox) / p)
            if reihen < 7 or spalten < 5:
                continue
            ys = np.minimum((oy + (np.arange(reihen) + 0.5) * p).astype(int), helligkeit.shape[0] - 1)
            xs = np.minimum((ox + (np.arange(spalten) + 0.5) * p).astype(int), helligkeit.shape[1] - 1)
            werte = helligkeit[np.ix_(ys, xs)].astype(float)
            # Scharf getroffen: Messpunkte liegen mitten in Strichen oder mitten im Hintergrund
            klar = np.abs(werte - 140).mean()
            if bestes is None or klar > bestes[0]:
                bestes = (klar, werte > 140)
    if bestes is None:
        return ""
    raster = bestes[1]
    tinte = raster.sum(axis=1)
    start = int(np.argmax([tinte[i:i + 7].sum() for i in range(raster.shape[0] - 6)]))
    g = raster[start:start + 7]
    text, s, leer = "", None, 0
    for i, v in enumerate(list(g.any(axis=0)) + [False]):
        if v and s is None:
            if leer >= 3 and text:
                text += " "
            s, leer = i, 0
        elif not v:
            leer += 1
            if s is not None:
                zeichen = g[:, s:i]
                if zeichen.shape[1] == 5:
                    abst = {z: int((v_ != zeichen).sum()) for z, v_ in _VORLAGEN.items()}
                    z = min(abst, key=abst.get)
                    text += z if abst[z] <= 3 else "?"
                else:
                    text += "?"
                s = None
    return text


def lies_haltbarkeit(bild, p):
    """Liest "Haltbarkeit: 35/64" aus dem Infokasten -> (35, 64) oder None.
    p = Bild-Pixel pro Minecraft-Pixel (die GUI-Groesse)."""
    kasten = finde_infokasten(bild, p)
    if kasten is None:
        return None
    x0, y0, x1, y1 = kasten
    helligkeit = bild[y0:y1, x0:x1].max(axis=2)
    zeilen = (helligkeit > 140).sum(axis=1) > 0
    # Helle Reihen zu Textzeilen zusammenfassen (Umlaut-Punkte gehoeren zur Zeile darunter)
    gruppen = []
    for y in np.flatnonzero(zeilen):
        if gruppen and y - gruppen[-1][1] <= 2 * p:
            gruppen[-1][1] = y
        else:
            gruppen.append([y, y])
    for oben, unten in gruppen:
        if unten - oben < 4 * p:
            continue
        teil = helligkeit[max(0, int(oben - p)):min(len(zeilen), int(unten + 2 * p))]
        treffer = re.search(r"(\d+) ?/ ?(\d+)", lies_zeile(teil, p))
        if treffer:
            return int(treffer.group(1)), int(treffer.group(2))
    return None


def finde_inventar(bild):
    """Sucht das hellgraue Inventar-Fenster -> (links, oben, g) in Bild-Pixeln oder None.
    Das Inventar ist 176 x 166 Minecraft-Pixel gross; g = Bild-Pixel pro Minecraft-Pixel."""
    r = bild[:, :, 0].astype(np.int16)
    g_ = bild[:, :, 1].astype(np.int16)
    b = bild[:, :, 2].astype(np.int16)
    maske = (np.abs(r - 198) < 6) & (np.abs(g_ - 198) < 6) & (np.abs(b - 198) < 6)
    spalten = maske.sum(axis=0)
    zeilen = maske.sum(axis=1)
    if spalten.max() < 10 or zeilen.max() < 10:
        return None
    xs = np.flatnonzero(spalten >= spalten.max() * 0.15)
    ys = np.flatnonzero(zeilen >= zeilen.max() * 0.15)
    breite, hoehe = xs[-1] - xs[0] + 1, ys[-1] - ys[0] + 1
    g = breite / 170.0  # die graue Flaeche ist etwa 170 der 176 Pixel breit
    if g <= 0 or not 0.85 < (hoehe / g) / 160.0 < 1.15:
        return None  # keine Inventar-Form
    mitte_x, mitte_y = (xs[0] + xs[-1] + 1) / 2.0, (ys[0] + ys[-1] + 1) / 2.0
    return mitte_x - 88 * g, mitte_y - 83 * g, g


def platz_mitte(inventar, platz):
    """Mitte von Platz 1-9 der untersten Inventar-Reihe (Schnellleiste) in Bild-Pixeln."""
    links, oben, g = inventar
    return links + (8 + 18 * (platz - 1) + 8) * g, oben + (142 + 8) * g


# ------------------------------------------------------- Windows: Maus, Tasten

if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)

    MOUSEEVENTF_MOVE = 0x0001
    MOUSEEVENTF_RIGHTDOWN = 0x0008
    MOUSEEVENTF_RIGHTUP = 0x0010
    KEYEVENTF_KEYUP = 0x0002
    INPUT_MOUSE = 0
    INPUT_KEYBOARD = 1

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wintypes.LONG),
            ("dy", wintypes.LONG),
            ("mouseData", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
        ]

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
        ]

    class INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("_pad", ctypes.c_byte * 32)]

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
    user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]
    user32.MapVirtualKeyW.restype = wintypes.UINT
    user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]

    def _maus(flag, dx=0, dy=0):
        inp = INPUT(type=INPUT_MOUSE)
        inp.mi = MOUSEINPUT(dx, dy, 0, flag, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def taste(vk):
        """Eine Taste einmal kurz druecken (mit Scancode, den braucht Minecraft)."""
        scan = user32.MapVirtualKeyW(vk, 0)
        for flag in (0, KEYEVENTF_KEYUP):
            inp = INPUT(type=INPUT_KEYBOARD)
            inp.ki = KEYBDINPUT(vk, scan, flag, 0, None)
            user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
            time.sleep(0.05)

    def maus_hin(x, y):
        """Mauszeiger an eine Bildschirmstelle setzen (im Inventar)."""
        user32.SetCursorPos(int(round(x)), int(round(y)))
        time.sleep(0.03)
        _maus(MOUSEEVENTF_MOVE, 1, 0)  # kleiner Ruck, damit Minecraft es sicher bemerkt
        _maus(MOUSEEVENTF_MOVE, -1, 0)

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
VK_ESCAPE, VK_SPACE = 0x1B, 0x20


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


def rand_tipp(info, raster, fensterbreite):
    """Was tun, wenn die Leiste breiter als das Fenster ist? Die Leiste ist GUI_BREITE
    Minecraft-Einheiten breit; die GUI-Groesse sagt, wie viele Pixel eine Einheit hat."""
    gui_jetzt = max(1, round(info["abstand"] * raster * FELDER / GUI_BREITE))
    gui_passt = int(fensterbreite // (GUI_BREITE * 1.02))
    text = ("Achtung: Die Leiste ist breiter als das Minecraft-Fenster - ganz links und rechts"
            " ist je ein Feld nicht zu sehen. Liegt das rote Feld dort, kann ich es nicht"
            " treffen. ")
    if 1 <= gui_passt < gui_jetzt:
        return text + ("Abhilfe: In Minecraft unter Optionen -> Grafikeinstellungen die"
                       " GUI-Groesse auf %d stellen (jetzt %d), oder das Fenster breiter machen."
                       % (gui_passt, gui_jetzt))
    return text + "Abhilfe: Mach das Minecraft-Fenster breiter."


def frage_anzahl():
    """Nach wie vielen Minispielen soll der Bot anhalten? 0 = nie."""
    if SPIELE_ZIEL is not None:
        return max(0, int(SPIELE_ZIEL))
    while True:
        try:
            antwort = input("Wie viele Minispiele soll ich spielen? Zahl eingeben und Enter"
                            " (nur Enter = ohne Ende): ").strip()
        except (EOFError, OSError):
            return 0
        if not antwort:
            return 0
        if antwort.isdigit():
            return int(antwort)
        print("Bitte nur eine Zahl eingeben, zum Beispiel 10.")


def frage_platz(vorschlag):
    """Auf welchem Platz der untersten Inventar-Reihe liegt die Angel? 1-9."""
    if ANGEL_PLATZ is not None:
        return min(9, max(1, int(ANGEL_PLATZ)))
    while True:
        try:
            antwort = input("Auf welchem Platz liegt die Angel? 1 = ganz links ... 9 = ganz rechts"
                            " (nur Enter = %d): " % vorschlag).strip()
        except (EOFError, OSError):
            return vorschlag
        if not antwort:
            return vorschlag
        if antwort.isdigit() and 1 <= int(antwort) <= 9:
            return int(antwort)
        print("Bitte eine Zahl von 1 bis 9 eingeben.")


def frage_haltbarkeit(letzte):
    """Wie viel Haltbarkeit hat die Angel jetzt? Eine ganz neue Angel zeigt Minecraft
    im Infokasten erst nach dem ersten Fang an - bis dahin rechnet der Bot mit dieser Zahl."""
    if HALTBARKEIT_START is not None:
        return min(ANGEL_MAX, max(0, int(HALTBARKEIT_START)))
    zuletzt = " - letztes Mal: %d" % letzte if letzte is not None else ""
    while True:
        try:
            antwort = input("Wie viel Haltbarkeit hat die Angel? (nur Enter = %d = neue Angel%s): "
                            % (ANGEL_MAX, zuletzt)).strip()
        except (EOFError, OSError):
            return ANGEL_MAX
        if not antwort:
            return ANGEL_MAX
        if antwort.isdigit() and int(antwort) <= ANGEL_MAX:
            return int(antwort)
        print("Bitte eine Zahl von 0 bis %d eingeben." % ANGEL_MAX)


def piep():
    try:
        import winsound
        winsound.MessageBeep()
    except Exception:
        pass


def pruefe_angel(kamera, fenster, platz):
    """Oeffnet das Inventar, faehrt mit der Maus ueber den Angel-Platz, liest die
    Haltbarkeit aus dem Infokasten und schliesst das Inventar wieder.
    Gibt (haltbarkeit, maximum) zurueck - oder einen Text, was nicht geklappt hat."""
    import mss.tools
    links, oben, breite, hoehe = fenster
    bereich = {"left": links, "top": oben, "width": breite, "height": hoehe}

    def foto():
        roh = kamera.grab(bereich)
        return roh, np.asarray(roh)[:, :, 2::-1]

    taste(ord(INVENTAR_TASTE.upper()))
    inventar, ende = None, time.monotonic() + 2.0
    while inventar is None and time.monotonic() < ende:
        time.sleep(0.1)
        inventar = finde_inventar(foto()[1])
    if inventar is None:
        return "Das Inventar ist nicht aufgegangen (Inventar-Taste %s?)." % INVENTAR_TASTE
    x, y = platz_mitte(inventar, platz)
    maus_hin(links + x, oben + y)
    g = inventar[2]
    ergebnis, roh = None, None
    for versuch in range(5):
        time.sleep(0.15)
        roh, bild = foto()
        # Der Infokasten steht neben der Maus - nur dort suchen (geht schneller).
        x0, x1 = int(max(0, x - 250 * g)), int(min(breite, x + 250 * g))
        y0 = int(max(0, y - 200 * g))
        ergebnis = lies_haltbarkeit(bild[y0:, x0:x1], g)
        if ergebnis:
            break
    taste(VK_ESCAPE)  # Inventar zu
    for _ in range(30):
        time.sleep(0.05)
        if not mauszeiger_sichtbar():
            break
    if ergebnis is None:
        name = "diagnose_haltbarkeit.png"  # immer dieselbe Datei, damit sich keine Bilder stapeln
        mss.tools.to_png(roh.rgb, roh.size, output=name)
        return ("Im Infokasten von Platz %d habe ich keine Haltbarkeit gefunden (Bild: %s)."
                " Bei einer ganz neuen Angel ist das normal. Sonst: Liegt dort die Angel?"
                " Ist F3+H an (erweiterte Infos)?" % (platz, name))
    if ergebnis[1] != ANGEL_MAX:
        return ("Auf Platz %d liegt wohl nicht die Angel (volle Haltbarkeit %d statt %d)."
                " Leg die Angel dorthin oder gib beim Start den richtigen Platz an." % (platz, ergebnis[1], ANGEL_MAX))
    return ergebnis


def lade_gelerntes():
    try:
        with open(LERN_DATEI, encoding="utf-8") as datei:
            return json.load(datei)
    except (OSError, ValueError):
        return {}


def speichere_gelerntes(daten):
    try:
        with open(LERN_DATEI, "w", encoding="utf-8") as datei:
            json.dump(daten, datei, indent=2)
    except OSError:
        pass


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
    gelernt = lade_gelerntes()
    vorausschau = Vorausschau(gelernt)

    print(HILFE)
    if vorausschau.messungen or vorausschau.erfahrung:
        sag("Vom letzten Mal gelernt: Vorlauf %d ms (aus %d Klicks)" % (
            vorausschau.vorlauf() * 1000, len(vorausschau.erfahrung)))
    ziel = frage_anzahl()
    sag("Ich spiele %s." % ("%d Minispiele und mache dann Pause" % ziel if ziel else "ohne Ende"))
    angel_platz = 1
    if HALTBARKEIT_MIN > 0:
        vorschlag = gelernt.get("angel_platz", 1)
        angel_platz = frage_platz(vorschlag if isinstance(vorschlag, int) and 1 <= vorschlag <= 9 else 1)
        sag("Die Angel liegt auf Platz %d - dort schaue ich nach der Haltbarkeit." % angel_platz)

    # Letzte bekannte Haltbarkeit - zum Weiterrechnen, falls sie einmal nicht zu lesen ist
    # (eine ganz neue Angel zeigt Minecraft erst nach dem ersten Fang an).
    haltbarkeit = gelernt.get("haltbarkeit") if isinstance(gelernt.get("haltbarkeit"), int) else None
    if HALTBARKEIT_MIN > 0:
        haltbarkeit = frage_haltbarkeit(haltbarkeit)
        if haltbarkeit < HALTBARKEIT_MIN:
            sag("Achtung: Haltbarkeit %d/%d ist unter %d - kann ich sie im Inventar nicht lesen,"
                " hoere ich gleich nach dem ersten Auswerfen wieder auf." % (haltbarkeit, ANGEL_MAX, HALTBARKEIT_MIN))
        else:
            sag("Die Angel hat %d/%d Haltbarkeit - damit rechne ich, bis ich sie im Inventar lesen kann."
                % (haltbarkeit, ANGEL_MAX))

    def speichern():
        speichere_gelerntes(dict(vorausschau.gelernt(), angel_platz=angel_platz, haltbarkeit=haltbarkeit))

    speichern()  # damit der Platz beim naechsten Mal schon vorgeschlagen wird
    sag("Bereit. Geh in Minecraft, nimm die Angel in die Hand (nicht auswerfen),"
        " schau aufs Wasser und druecke F8.")

    aktiv = False
    zustand = "auswerfen"   # auswerfen -> warten -> spiel -> nach_fang -> auswerfen
    seit = time.monotonic()
    zuletzt_leiste = 0.0
    treffer = 0
    runden = 0              # Minispiele insgesamt
    gespielt = 0            # Minispiele fuer das Ziel (zaehlt nach "Fertig" neu)
    fortsetzung = False     # Leiste kam nach dem Fang wieder: dasselbe Minispiel, nicht neu zaehlen
    angel_pruefen = True    # nach dem naechsten Auswerfen die Haltbarkeit der Angel pruefen
    rand_gewarnt = None
    warte_grund = None
    # Erst wenn der Mauszeiger einmal im Spiel versteckt war, wissen wir sicher,
    # dass "Zeiger sichtbar" wirklich "Menue offen" bedeutet.
    zeiger_geprueft = False
    leiste_wieder = None  # seit wann die Leiste nach dem Fang wieder zu sehen ist
    bilder_im_spiel = 0
    bild_takt = 1.0 / BILDER_PRO_SEKUNDE

    with mss.mss() as kamera:
        while True:
            start = time.monotonic()

            if tasten.neu(VK_F12):
                sag("Beendet. Minispiele gespielt: %d" % runden)
                return
            if tasten.neu(VK_F8):
                aktiv = not aktiv
                zustand = "auswerfen"
                angel_pruefen = True
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
                bild_zeit = time.monotonic()
            except Exception as fehler:
                sag("Bildschirmfoto ging nicht (%s) - versuche es gleich nochmal." % fehler)
                time.sleep(0.5)
                continue
            # Grosse Fenster: Die Felder sind riesig, da reicht jedes 2. oder 3. Pixel - so
            # schaut der Bot viel oefter hin (wichtig fuer den richtigen Zeitpunkt).
            raster = max(1, breite // 960)
            bild = np.asarray(roh)[::raster, ::raster, 2::-1]  # BGRA -> RGB
            info = erkenne(bild)

            if tasten.neu(VK_F10):
                name = time.strftime("diagnose_%H%M%S.png")
                mss.tools.to_png(roh.rgb, roh.size, output=name)
                sag("Diagnose-Bild gespeichert: %s  Erkennung: %s" % (name, info))

            if not aktiv:
                time.sleep(0.05)
                continue

            jetzt = bild_zeit
            if info is not None:
                zuletzt_leiste = jetzt
                if info["abgeschnitten"] and rand_gewarnt != (breite, hoehe):
                    rand_gewarnt = (breite, hoehe)  # pro Fenstergroesse einmal sagen
                    sag(rand_tipp(info, raster, breite))

            if zustand == "auswerfen":
                if info is not None:
                    zustand, seit, treffer, bilder_im_spiel = "spiel", jetzt, 0, 0  # Minispiel laeuft schon
                    vorausschau.neues_spiel()
                else:
                    rechtsklick()
                    sag("Ausgeworfen, warte auf einen Biss ...")
                    zustand, seit = "warten", jetzt
                    if HALTBARKEIT_MIN > 0 and angel_pruefen:
                        angel_pruefen = False
                        time.sleep(0.6)
                        ergebnis = pruefe_angel(kamera, fenster, angel_platz)
                        if not isinstance(ergebnis, str):
                            haltbarkeit = ergebnis[0]
                            text = "Angel: Haltbarkeit %d/%d" % ergebnis
                        elif haltbarkeit is not None:
                            # Nicht erkannt: so rechnen, als waere es genau 1 weniger als beim letzten Mal.
                            haltbarkeit -= 1
                            sag(ergebnis)
                            text = "Ich rechne mit Haltbarkeit %d/%d (1 weniger als beim letzten Mal)" % (
                                haltbarkeit, ANGEL_MAX)
                        else:
                            text = None
                            sag(ergebnis + " Ich kenne noch keinen alten Wert zum Rechnen -"
                                " zur Sicherheit halte ich an (F8 = weiter).")
                            piep()
                            aktiv = False
                        if text and haltbarkeit < HALTBARKEIT_MIN:
                            sag(text + ". Die Angel ist fast kaputt - ich hoere sofort auf.")
                            taste(VK_SPACE)
                            piep()
                            aktiv = False
                        elif text:
                            sag(text + " - weiter geht's.")
                        speichern()
                        seit = time.monotonic()

            elif zustand == "warten":
                if info is not None:
                    sag("Biss! Minispiel laeuft.")
                    zustand, seit, treffer, bilder_im_spiel = "spiel", jetzt, 0, 0
                    vorausschau.neues_spiel()
                elif jetzt - seit > WARTEN_MAX:
                    sag("Kein Biss nach %d s - ich hole ein und werfe neu aus." % WARTEN_MAX)
                    rechtsklick()
                    time.sleep(1.0)
                    zustand = "auswerfen"

            elif zustand == "spiel":
                bilder_im_spiel += 1
                grund = vorausschau.schritt(info, jetzt)
                for meldung in vorausschau.meldungen:
                    sag(meldung)
                vorausschau.meldungen.clear()
                if grund:
                    rechtsklick()
                    treffer += 1
                    tempo = vorausschau.takt()
                    sag("  Klick %d (%s)  Rahmen: %s, Vorlauf: %d ms" % (
                        treffer, grund, "%.2f s/Feld" % tempo if tempo else "?",
                        vorausschau.vorlauf() * 1000))
                elif jetzt - zuletzt_leiste > SPIEL_VORBEI_NACH:
                    if not fortsetzung:
                        runden += 1
                        gespielt += 1
                    sag("Minispiel %s vorbei (%d Klicks, %d Bilder/s)." % (
                        "%d von %d" % (gespielt, ziel) if ziel else str(runden),
                        treffer, bilder_im_spiel / max(0.1, jetzt - seit)))
                    speichern()
                    zustand, seit, fortsetzung = "nach_fang", jetzt, False
                    angel_pruefen = True
                    if ziel and gespielt >= ziel:
                        sag("Fertig: %d Minispiele gespielt! Ich mache Pause."
                            " F8 = nochmal %d spielen, F12 = beenden." % (gespielt, ziel))
                        piep()
                        aktiv, gespielt = False, 0

            elif zustand == "nach_fang":
                # Nach dem Fang zeigt der Server die Leiste manchmal noch einmal kurz an.
                # Erst wenn sie laenger bleibt, laeuft das Spiel doch noch weiter.
                if info is None:
                    leiste_wieder = None
                elif leiste_wieder is None:
                    leiste_wieder = jetzt
                if leiste_wieder is not None and jetzt - leiste_wieder > 0.3:
                    zustand, leiste_wieder, seit, bilder_im_spiel = "spiel", None, jetzt, 0
                    fortsetzung = True
                    vorausschau.neues_spiel()
                elif leiste_wieder is None and jetzt - seit > NACH_FANG_PAUSE:
                    zustand = "auswerfen"

            rest = bild_takt - (time.monotonic() - start)
            if rest > 0:
                time.sleep(rest)


if __name__ == "__main__":
    main()
