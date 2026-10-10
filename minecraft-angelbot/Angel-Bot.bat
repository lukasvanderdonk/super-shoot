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

Beim Start fragt der Bot, wie viele Minispiele er spielen soll und was danach
passiert (Pause, Leertaste, Bot beenden, Laptop ausschalten oder eine Aufnahme
abspielen), ob er den Laptop nach ein paar Stunden ausschalten soll und auf
welchem Platz die Angel liegt.

Aufnahmen: Im ersten Menue "2" waehlen, Namen eingeben (z. B. verkaufen), in
Minecraft vormachen, was der Bot spaeter machen soll (Tasten, Klicks, Mausrad,
Maus), dann zurueck in dieses Fenster und Enter (oder F9 in Minecraft). Der Bot
merkt sich, was du wann und wie lange gemacht hast, und spielt es nach den
Minispielen genau so ab (Nr. 5/6). Geht dabei ein Menue (Truhe, Server-Menue)
langsamer auf, wartet er darauf. Ausprobieren: Menue "3" oder F7 in Minecraft.

Nach jedem Auswerfen schaut er im Inventar nach, wie viel Haltbarkeit die Angel
noch hat (Maus ueber den Angel-Platz, Infokasten lesen). Kann er sie nicht lesen,
rechnet er mit 1 weniger als beim letzten Mal. Ist sie unter 5, hoert er sofort
auf und drueckt einmal die Leertaste - damit die Angel nicht kaputtgeht. Wenn du
willst (Frage beim Start), schaltet er dann auch gleich den Laptop aus.

Tasten:  F8 = Start / Pause   F9 = Aufnahme an/aus   F7 = Aufnahme ausprobieren
         F10 = Diagnose-Bild   F12 = Beenden
"""

import json
import re
import subprocess
import sys
import threading
import time

import numpy as np

# ---------------------------------------------------------------- Einstellungen

SPIELE_ZIEL = None       # nach so vielen Minispielen anhalten (None = beim Start fragen, 0 = nie)
NACH_ZIEL = None         # wenn alle Minispiele gespielt sind: 1 = Pause, 2 = Leertaste + Pause,
                         # 3 = Bot beenden, 4 = Laptop ausschalten, 5 = Aufnahme abspielen + Pause,
                         # 6 = Aufnahme abspielen + weiter angeln (None = beim Start fragen)
AUSSCHALTEN_NACH = None  # Laptop nach so vielen Stunden ausschalten (None = beim Start fragen, 0 = nie)
HALTBARKEIT_MIN = 5      # Angel pruefen: Haltbarkeit darunter -> anhalten und Leertaste (0 = nie pruefen)
ANGEL_PLATZ = None       # Platz der Angel in der untersten Inventar-Reihe, 1 (links) bis 9 (None = beim Start fragen)
ANGEL_MAX = 64           # volle Haltbarkeit einer Angel (zur Kontrolle, dass es wirklich die Angel ist)
HALTBARKEIT_START = None # Haltbarkeit der Angel beim Start (None = beim Start fragen, z. B. 64 = neue Angel)
KAPUTT_AUSSCHALTEN = None  # Angel fast kaputt -> auch den Laptop ausschalten (None = beim Start fragen,
                           # True = ja, False = nein)
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
AUFNAHMEN_DATEI = "angelbot_aufnahmen.json"
ALTE_AUFNAHME_DATEI = "angelbot_aufnahme.json"   # von frueher (nur eine Aufnahme)
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

def tasten_name(scan, e0):
    return "Taste %s%02X" % ("E0 " if e0 else "", scan)


def konsole_enter():
    return False


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

    # Fuer das Abspielen einer Aufnahme
    KEYEVENTF_EXTENDEDKEY, KEYEVENTF_SCANCODE = 0x0001, 0x0008
    MOUSEEVENTF_WHEEL = 0x0800
    # Maustaste 1-5 (links, rechts, Mitte, Seite 1, Seite 2): (runter, hoch, mouseData)
    _KNOPF = {1: (0x0002, 0x0004, 0), 2: (0x0008, 0x0010, 0), 3: (0x0020, 0x0040, 0),
              4: (0x0080, 0x0100, 1), 5: (0x0080, 0x0100, 2)}

    def taste_roh(scan, e0, runter):
        """Eine Taste nach ihrem Scancode druecken oder loslassen (so wie aufgenommen)."""
        flag = KEYEVENTF_SCANCODE | (KEYEVENTF_EXTENDEDKEY if e0 else 0) | (0 if runter else KEYEVENTF_KEYUP)
        vk = user32.MapVirtualKeyW(scan | (0xE000 if e0 else 0), 3)   # MAPVK_VSC_TO_VK_EX
        inp = INPUT(type=INPUT_KEYBOARD)
        inp.ki = KEYBDINPUT(vk, scan, flag, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def maus_knopf(nummer, runter):
        an, aus, daten = _KNOPF[nummer]
        inp = INPUT(type=INPUT_MOUSE)
        inp.mi = MOUSEINPUT(0, 0, daten, an if runter else aus, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def maus_rad(schritte):
        inp = INPUT(type=INPUT_MOUSE)
        inp.mi = MOUSEINPUT(0, 0, schritte & 0xFFFFFFFF, MOUSEEVENTF_WHEEL, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def maus_relativ(dx, dy):
        """Maus bewegen wie eine echte Maus - im Spiel dreht das die Kamera. In kleinen
        Schritten, damit die Mausbeschleunigung von Windows grosse Spruenge nicht vergroessert."""
        schritte = max(1, -(-max(abs(dx), abs(dy)) // 6))
        for i in range(schritte):
            _maus(MOUSEEVENTF_MOVE, dx * (i + 1) // schritte - dx * i // schritte,
                  dy * (i + 1) // schritte - dy * i // schritte)

    def zeiger_hin(x, y):
        user32.SetCursorPos(int(round(x)), int(round(y)))

    def zeiger_position():
        punkt = wintypes.POINT()
        user32.GetCursorPos(ctypes.byref(punkt))
        return punkt.x, punkt.y

    user32.GetKeyNameTextW.argtypes = [wintypes.LONG, wintypes.LPWSTR, ctypes.c_int]

    def tasten_name(scan, e0):
        """Name der Taste so, wie sie auf der Tastatur steht (z. B. "Z", "EINGABE")."""
        puffer = ctypes.create_unicode_buffer(64)
        if user32.GetKeyNameTextW((scan << 16) | (1 << 24 if e0 else 0), puffer, 64) > 0:
            return puffer.value
        return "Taste %s%02X" % ("E0 " if e0 else "", scan)

    # Fuer die Aufnahme: "Raw Input" bekommt Tasten, Klicks, Mausrad und Mausbewegungen
    # auch dann, wenn Minecraft die Maus einfaengt (im Spiel) - in einem eigenen Thread.
    WM_DESTROY, WM_CLOSE, WM_INPUT = 0x0002, 0x0010, 0x00FF
    RID_INPUT, RIM_TYPEMOUSE, RIM_TYPEKEYBOARD = 0x10000003, 0, 1
    RIDEV_REMOVE, RIDEV_INPUTSINK = 0x0001, 0x0100
    RI_MOUSE_WHEEL, MOUSE_MOVE_ABSOLUTE = 0x0400, 1
    HWND_MESSAGE = (1 << (8 * ctypes.sizeof(ctypes.c_void_p))) - 3
    LRESULT = ctypes.c_ssize_t
    WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)

    class WNDCLASSW(ctypes.Structure):
        _fields_ = [
            ("style", wintypes.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
            ("cbWndExtra", ctypes.c_int), ("hInstance", wintypes.HINSTANCE), ("hIcon", wintypes.HICON),
            ("hCursor", wintypes.HANDLE), ("hbrBackground", wintypes.HBRUSH),
            ("lpszMenuName", wintypes.LPCWSTR), ("lpszClassName", wintypes.LPCWSTR),
        ]

    class RAWINPUTDEVICE(ctypes.Structure):
        _fields_ = [("usUsagePage", wintypes.USHORT), ("usUsage", wintypes.USHORT),
                    ("dwFlags", wintypes.DWORD), ("hwndTarget", wintypes.HWND)]

    class RAWINPUTHEADER(ctypes.Structure):
        _fields_ = [("dwType", wintypes.DWORD), ("dwSize", wintypes.DWORD),
                    ("hDevice", wintypes.HANDLE), ("wParam", wintypes.WPARAM)]

    class RAWMOUSE(ctypes.Structure):
        _fields_ = [("usFlags", wintypes.USHORT), ("_luecke", wintypes.USHORT),
                    ("usButtonFlags", wintypes.USHORT), ("usButtonData", wintypes.USHORT),
                    ("ulRawButtons", wintypes.ULONG), ("lLastX", wintypes.LONG), ("lLastY", wintypes.LONG),
                    ("ulExtraInformation", wintypes.ULONG)]

    class RAWKEYBOARD(ctypes.Structure):
        _fields_ = [("MakeCode", wintypes.USHORT), ("Flags", wintypes.USHORT), ("Reserved", wintypes.USHORT),
                    ("VKey", wintypes.USHORT), ("Message", wintypes.UINT), ("ExtraInformation", wintypes.ULONG)]

    class RAWINPUT(ctypes.Structure):
        class _D(ctypes.Union):
            _fields_ = [("mouse", RAWMOUSE), ("keyboard", RAWKEYBOARD)]

        _fields_ = [("header", RAWINPUTHEADER), ("data", _D)]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
    kernel32.GetModuleHandleW.restype = wintypes.HMODULE
    user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASSW)]
    user32.RegisterClassW.restype = wintypes.ATOM
    user32.CreateWindowExW.argtypes = [
        wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_int, ctypes.c_int,
        ctypes.c_int, ctypes.c_int, wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID]
    user32.CreateWindowExW.restype = wintypes.HWND
    user32.DefWindowProcW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.DefWindowProcW.restype = LRESULT
    user32.DestroyWindow.argtypes = [wintypes.HWND]
    user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.PostQuitMessage.argtypes = [ctypes.c_int]
    user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
    user32.GetMessageW.restype = wintypes.BOOL
    user32.TranslateMessage.argtypes = [ctypes.POINTER(wintypes.MSG)]
    user32.DispatchMessageW.argtypes = [ctypes.POINTER(wintypes.MSG)]
    user32.DispatchMessageW.restype = LRESULT
    user32.RegisterRawInputDevices.argtypes = [ctypes.POINTER(RAWINPUTDEVICE), wintypes.UINT, wintypes.UINT]
    user32.RegisterRawInputDevices.restype = wintypes.BOOL
    user32.GetRawInputData.argtypes = [wintypes.HANDLE, wintypes.UINT, wintypes.LPVOID,
                                       ctypes.POINTER(wintypes.UINT), wintypes.UINT]
    user32.GetRawInputData.restype = wintypes.UINT
    user32.GetCursorPos.argtypes = [ctypes.POINTER(wintypes.POINT)]

    _lauschen = {"ziel": None, "klasse": False, "fenster": None, "roh": None, "abfrage": None, "stopp": None}

    def _fensterfunktion(hwnd, nachricht, wparam, lparam):
        try:
            ziel = _lauschen["ziel"]
            if nachricht == WM_INPUT and ziel is not None:
                daten, groesse = RAWINPUT(), wintypes.UINT(ctypes.sizeof(RAWINPUT))
                if user32.GetRawInputData(lparam, RID_INPUT, ctypes.byref(daten), ctypes.byref(groesse),
                                          ctypes.sizeof(RAWINPUTHEADER)) not in (0, 0xFFFFFFFF):
                    if daten.header.dwType == RIM_TYPEMOUSE:
                        m = daten.data.mouse
                        if m.usButtonFlags & RI_MOUSE_WHEEL:
                            ziel.rad(ctypes.c_short(m.usButtonData).value)
                        if not m.usFlags & MOUSE_MOVE_ABSOLUTE and (m.lLastX or m.lLastY):
                            ziel.kamera(m.lLastX, m.lLastY)
            elif nachricht == WM_CLOSE:
                user32.DestroyWindow(hwnd)
                return 0
            elif nachricht == WM_DESTROY:
                user32.PostQuitMessage(0)
                return 0
        except Exception as fehler:
            print("Fehler bei der Aufnahme:", fehler)
        return user32.DefWindowProcW(hwnd, nachricht, wparam, lparam)

    _fensterfunktion_c = WNDPROC(_fensterfunktion)

    def _maus_lauscher(bereit):
        """Raw Input fuer die Maus: Kamera-Drehen im Spiel und Mausrad."""
        hinst = kernel32.GetModuleHandleW(None)
        if not _lauschen["klasse"]:
            klasse = WNDCLASSW(lpfnWndProc=_fensterfunktion_c, hInstance=hinst, lpszClassName="AngelBotAufnahme")
            _lauschen["klasse"] = bool(user32.RegisterClassW(ctypes.byref(klasse)))
        hwnd = user32.CreateWindowExW(0, "AngelBotAufnahme", "Angel-Bot", 0, 0, 0, 0, 0,
                                      HWND_MESSAGE, None, hinst, None)
        geraet = RAWINPUTDEVICE(1, 2, RIDEV_INPUTSINK, hwnd)
        if not hwnd or not user32.RegisterRawInputDevices(ctypes.byref(geraet), 1, ctypes.sizeof(RAWINPUTDEVICE)):
            if hwnd:
                user32.DestroyWindow(hwnd)
            bereit.set()
            return
        _lauschen["fenster"] = hwnd
        bereit.set()
        nachricht = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(nachricht), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(nachricht))
            user32.DispatchMessageW(ctypes.byref(nachricht))
        geraet = RAWINPUTDEVICE(1, 2, RIDEV_REMOVE, None)
        user32.RegisterRawInputDevices(ctypes.byref(geraet), 1, ctypes.sizeof(RAWINPUTDEVICE))

    MAPVK_VK_TO_VSC_EX = 4
    _MAUS_VK = {0x01: 1, 0x02: 2, 0x04: 3, 0x05: 4, 0x06: 5}   # links, rechts, Mitte, Seite 1, Seite 2
    _ZUSATZ_VK = set(range(0xA0, 0xA6))                          # Shift, Strg, Alt (links/rechts)
    # Nicht aufnehmen: Shift/Strg/Alt ohne Seite (kommen links/rechts einzeln), Strg+Pause, F7-F12
    # (Bot-Tasten, F11 = Vollbild), Windows-Tasten, Browser-/Medien-/Lautstaerke-Tasten, Sondercodes.
    _NICHT_AUFNEHMEN = {0x03, 0x10, 0x11, 0x12, 0x5B, 0x5C, 0x5D, 0xE7, 0xFF} | set(range(0x76, 0x7C)) \
        | set(range(0xA6, 0xB8))

    def _tasten_abfrage(ziel, stopp):
        """Fragt Tasten und Maustasten ab - genauso wie F8 (das klappt ueberall) - und im Menue,
        wo der Mauszeiger steht."""
        scancodes = {}
        for vk in range(0x07, 0xFF):
            if vk in _NICHT_AUFNEHMEN:
                continue
            code = user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC_EX)
            if code & 0xFF and code >> 8 in (0, 0xE0):
                scancodes[vk] = (code & 0xFF, int(code >> 8 == 0xE0))
        alle = list(_MAUS_VK) + list(scancodes)
        unten = {vk: taste_gedrueckt(vk) for vk in alle}
        zeiger_vorher = None
        while not stopp.is_set():
            fenster, sichtbar = minecraft_fenster(), mauszeiger_sichtbar()
            ziel.zustand(fenster, sichtbar)
            wechsel = []
            for vk in alle:
                jetzt = bool(user32.GetAsyncKeyState(vk) & 0x8000)
                if jetzt != unten[vk]:
                    unten[vk] = jetzt
                    wechsel.append((vk, jetzt))
            # Kam mehreres zugleich: Shift/Strg/Alt zuerst druecken und zuletzt loslassen,
            # sonst wird aus Shift+7 ("/") eine 7.
            wechsel.sort(key=lambda w: (0 if w[1] else 2) if w[0] in _ZUSATZ_VK else 1)
            for vk, jetzt in wechsel:
                if vk in _MAUS_VK:
                    ziel.knopf(_MAUS_VK[vk], jetzt)
                else:
                    ziel.taste(scancodes[vk][0], scancodes[vk][1], jetzt)
            if fenster is not None and sichtbar:
                position = zeiger_position()
                if position != zeiger_vorher:
                    zeiger_vorher = position
                    ziel.zeiger(*position)
            else:
                zeiger_vorher = None
            time.sleep(0.005)

    def starte_lauscher(ziel):
        """Startet die Aufnahme. Liefert True, wenn auch Kamera-Drehen und Mausrad gehen."""
        _lauschen["ziel"], _lauschen["fenster"] = ziel, None
        _lauschen["stopp"] = threading.Event()
        _lauschen["abfrage"] = threading.Thread(target=_tasten_abfrage, args=(ziel, _lauschen["stopp"]), daemon=True)
        _lauschen["abfrage"].start()
        bereit = threading.Event()
        _lauschen["roh"] = threading.Thread(target=_maus_lauscher, args=(bereit,), daemon=True)
        _lauschen["roh"].start()
        bereit.wait(3.0)
        return _lauschen["fenster"] is not None

    def stoppe_lauscher():
        _lauschen["ziel"] = None
        if _lauschen["stopp"] is not None:
            _lauschen["stopp"].set()
            _lauschen["abfrage"].join(3.0)
            _lauschen["stopp"] = None
        if _lauschen["fenster"]:
            user32.PostMessageW(_lauschen["fenster"], WM_CLOSE, 0, 0)
            _lauschen["roh"].join(3.0)
        _lauschen["fenster"] = None

    def konsole_enter():
        """Wurde in diesem (schwarzen) Fenster Enter gedrueckt?"""
        import msvcrt
        gedrueckt = False
        while msvcrt.kbhit():
            gedrueckt = msvcrt.getwch() in "\r\n" or gedrueckt
        return gedrueckt

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

VK_F7, VK_F8, VK_F9, VK_F10, VK_F12 = 0x76, 0x77, 0x78, 0x79, 0x7B
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


class Aufnahme:
    """Nimmt auf, was man in Minecraft macht und wann: Tasten, Maustasten, Mausrad und
    Mausbewegungen. Ereignisse (Zeit in Sekunden ab der ersten Aktion; menue = 1, wenn
    dabei ein Menue offen war - Inventar, Truhe, Chat):
      ["t", zeit, scancode, e0, runter, menue]     Taste
      ["k", zeit, knopf, runter, menue]            Maustaste 1-5
      ["r", zeit, schritte, menue]                 Mausrad
      ["b", zeit, dx, dy, x, y, menue]             Maus: im Spiel dx/dy (Kamera drehen),
                                                   im Menue x/y = Zeiger ab Fenstermitte
    Mit sofort=False faengt sie erst an, sobald man in Minecraft im Spiel ist (kein Menue
    offen) - so kommt das Pause-Menue nach dem Fensterwechsel nicht mit hinein.
    """
    BEWEGUNG_TAKT = 0.01   # Kamera-Bewegungen werden alle 10 ms zusammengefasst

    def __init__(self, sofort=True):
        self.ereignisse = []
        self.tasten_unten, self.knoepfe_unten = set(), set()
        self.bewegung = None             # [zeit, dx, dy] - angefangene Kamera-Bewegung
        self.fenster, self.sichtbar = None, False
        self.laeuft, self.vorne_seit = sofort, None
        self.sperre = threading.Lock()

    def _aktiv(self):
        return self.laeuft and self.fenster is not None

    def zustand(self, fenster, sichtbar):
        """Ist Minecraft vorne, ist ein Menue offen? (vom Abfrage-Thread, alle 5 ms)"""
        with self.sperre:
            jetzt = time.monotonic()
            war_vorne = self.fenster is not None
            self.fenster, self.sichtbar = fenster, sichtbar
            if fenster is None:
                self.vorne_seit = None
                if war_vorne:
                    self._fokus_weg()
                return
            if self.vorne_seit is None:
                self.vorne_seit = jetzt
            if not self.laeuft and (not sichtbar or jetzt - self.vorne_seit > 5.0):
                self.laeuft = True

    def _fokus_weg(self):
        """Minecraft ist nicht mehr vorne (Alt+Tab, Klick ins Bot-Fenster ...): was dabei
        gerade gedrueckt war, gehoert nicht zur Aufnahme."""
        self._bewegung_fertig()
        for art, unten in (("t", self.tasten_unten), ("k", self.knoepfe_unten)):
            for schluessel in unten:
                for i in range(len(self.ereignisse) - 1, -1, -1):
                    e = self.ereignisse[i]
                    if e[0] == art and _schluessel(e) == schluessel and _runter(e):
                        del self.ereignisse[i]
                        break
            unten.clear()

    def _bewegung_fertig(self):
        if self.bewegung is not None:
            zeit, dx, dy = self.bewegung
            self.bewegung = None
            self.ereignisse.append(["b", zeit, dx, dy, None, None, 0])

    def _druck(self, art, schluessel, runter):
        unten = self.tasten_unten if art == "t" else self.knoepfe_unten
        if runter:
            if not self._aktiv() or schluessel in unten:
                return
            unten.add(schluessel)
        else:
            if schluessel not in unten:     # Loslassen nur, wenn das Druecken mit drin ist
                return
            unten.discard(schluessel)
        self._bewegung_fertig()
        jetzt, menue = time.monotonic(), int(self.sichtbar)
        if art == "t":
            self.ereignisse.append(["t", jetzt, schluessel[0], schluessel[1], int(runter), menue])
        else:
            self.ereignisse.append(["k", jetzt, schluessel, int(runter), menue])

    def taste(self, scan, e0, runter):
        with self.sperre:
            self._druck("t", (scan, int(e0)), runter)

    def knopf(self, nummer, runter):
        with self.sperre:
            self._druck("k", nummer, runter)

    def rad(self, schritte):
        with self.sperre:
            if self._aktiv():
                self._bewegung_fertig()
                self.ereignisse.append(["r", time.monotonic(), schritte, int(self.sichtbar)])

    def kamera(self, dx, dy):
        """Mausbewegung im Spiel (Raw Input) - dreht die Kamera."""
        with self.sperre:
            if not self._aktiv() or self.sichtbar:
                return
            jetzt = time.monotonic()
            if self.bewegung is not None and jetzt - self.bewegung[0] >= self.BEWEGUNG_TAKT:
                self._bewegung_fertig()
            if self.bewegung is None:
                self.bewegung = [jetzt, 0, 0]
            self.bewegung[1] += dx
            self.bewegung[2] += dy

    def zeiger(self, x, y):
        """Mauszeiger im Menue (Bildschirm-Koordinaten)."""
        with self.sperre:
            if not self._aktiv() or not self.sichtbar:
                return
            self._bewegung_fertig()
            links, oben, breite, hoehe = self.fenster
            self.ereignisse.append(["b", time.monotonic(), 0, 0, int(round(x - links - breite / 2)),
                                    int(round(y - oben - hoehe / 2)), 1])

    def stand(self):
        """Was bisher drin ist (zum Anzeigen waehrend der Aufnahme)."""
        with self.sperre:
            ereignisse = ohne_alt_tab(self.ereignisse)
            maus = self.bewegung is not None
        tasten = sum(1 for e in ereignisse if e[0] == "t" and e[4])
        klicks = sum(1 for e in ereignisse if e[0] == "k" and e[3])
        rad = sum(1 for e in ereignisse if e[0] == "r")
        maus = maus or any(e[0] == "b" for e in ereignisse)
        return "%d Tasten, %d Klicks%s%s" % (tasten, klicks, ", %d x Mausrad" % rad if rad else "",
                                             ", Maus bewegt" if maus else "")

    def stopp(self):
        """Aufnahme beenden: liefert die Ereignisse, Zeiten ab der ersten Aktion."""
        with self.sperre:
            jetzt = time.monotonic()
            self._bewegung_fertig()
            menue = int(self.sichtbar)
            for scan, e0 in sorted(self.tasten_unten):   # noch gedrueckt? Am Ende loslassen.
                self.ereignisse.append(["t", jetzt, scan, e0, 0, menue])
            for knopf in sorted(self.knoepfe_unten):
                self.ereignisse.append(["k", jetzt, knopf, 0, menue])
            self.tasten_unten.clear()
            self.knoepfe_unten.clear()
            ereignisse = ohne_alt_tab(self.ereignisse)
            if not ereignisse:
                return []
            null = ereignisse[0][1]
            return [[e[0], round(e[1] - null, 3)] + e[2:] for e in ereignisse]


def _schluessel(e):
    return (e[2], e[3]) if e[0] == "t" else e[2]


def _runter(e):
    return bool(e[4] if e[0] == "t" else e[3])


def ohne_alt_tab(ereignisse):
    """Alt+Tab (Fensterwechsel) gehoert nicht in die Aufnahme - sonst wuerde das Abspielen
    Minecraft verlassen."""
    weg, alt_runter, tab_runter = set(), {}, None
    markiert = set()
    for i, e in enumerate(ereignisse):
        if e[0] != "t":
            continue
        if e[2] == 0x38:                       # Alt (links) oder AltGr
            if e[4]:
                alt_runter[(e[2], e[3])] = i
            else:
                anfang = alt_runter.pop((e[2], e[3]), None)
                if anfang in markiert:
                    weg.update((anfang, i))
        elif e[2] == 0x0F and not e[3]:          # Tab
            if e[4] and alt_runter:
                weg.add(i)
                markiert.update(alt_runter.values())
                tab_runter = i
            elif not e[4] and tab_runter is not None:
                weg.add(i)
                tab_runter = None
    weg.update(markiert)                         # Alt gedrueckt, aber Loslassen fehlt
    return [e for i, e in enumerate(ereignisse) if i not in weg]


_MENUE_FELD = {"t": 5, "k": 4, "r": 3, "b": 6}


def menue_von(ereignis):
    """War bei diesem Ereignis ein Menue offen? None bei alten Aufnahmen (ohne diese Angabe)."""
    feld = _MENUE_FELD[ereignis[0]]
    return bool(ereignis[feld]) if len(ereignis) > feld else None


def aufnahme_text(ereignisse):
    """Kurzbeschreibung: wie lang, wie viele Tasten und Klicks."""
    tasten = sum(1 for e in ereignisse if e[0] == "t" and e[4]) - wiederholungen(ereignisse)
    klicks = sum(1 for e in ereignisse if e[0] == "k" and e[3])
    rad = sum(1 for e in ereignisse if e[0] == "r")
    maus = any(e[0] == "b" for e in ereignisse)
    teile = ["%d Tasten" % tasten, "%d Klicks" % klicks]
    if rad:
        teile.append("%d x Mausrad" % rad)
    if maus:
        teile.append("Maus bewegt")
    return "%.1f s: %s" % (ereignisse[-1][1] if ereignisse else 0.0, ", ".join(teile))


def wiederholungen(ereignisse):
    """Wie viele 'Taste runter' nur Wiederholungen einer gehaltenen Taste sind."""
    unten, anzahl = set(), 0
    for e in ereignisse:
        if e[0] == "t":
            if e[4]:
                anzahl += (e[2], e[3]) in unten
                unten.add((e[2], e[3]))
            else:
                unten.discard((e[2], e[3]))
    return anzahl


def aufnahme_ablauf(ereignisse, hoechstens=40):
    """Lesbar, was in der Aufnahme passiert - in der richtigen Reihenfolge."""
    teile, unten = [], {}
    knoepfe = ("Linksklick", "Rechtsklick", "Mittelklick", "Maustaste 4", "Maustaste 5")
    for e in ereignisse:
        menue = menue_von(e)
        if e[0] == "t":
            schluessel = (e[2], e[3])
            if e[4] and schluessel not in unten:
                unten[schluessel] = (len(teile), e[1])
                teile.append(tasten_name(e[2], e[3]))
            elif not e[4] and schluessel in unten:
                stelle, seit = unten.pop(schluessel)
                if e[1] - seit >= 0.5:
                    teile[stelle] += " (%.1f s gehalten)" % (e[1] - seit)
        elif e[0] == "k" and e[3]:
            teile.append(knoepfe[e[2] - 1] + (" im Menue" if menue else ""))
        elif e[0] == "r":
            teile.append("Mausrad " + ("hoch" if e[2] > 0 else "runter"))
        elif e[0] == "b":
            teile.append("Zeiger bewegt" if menue else "Kamera gedreht")
    zusammen = []                      # gleiche Eintraege hintereinander zusammenfassen
    for teil in teile:
        if zusammen and zusammen[-1][0] == teil and teil in ("Zeiger bewegt", "Kamera gedreht"):
            continue
        if zusammen and zusammen[-1][0] == teil:
            zusammen[-1][1] += 1
        else:
            zusammen.append([teil, 1])
    texte = [t if n == 1 else "%s x%d" % (t, n) for t, n in zusammen]
    if len(texte) > hoechstens:
        texte = texte[:hoechstens] + ["... (%d weitere)" % (len(texte) - hoechstens)]
    return " > ".join(texte)


def _gueltig(ereignisse):
    return isinstance(ereignisse, list) and bool(ereignisse) and all(
        isinstance(e, list) and len(e) >= 3 and e[0] in _MENUE_FELD for e in ereignisse)


def lade_aufnahmen():
    """Alle gespeicherten Aufnahmen: {name: ereignisse}."""
    try:
        with open(AUFNAHMEN_DATEI, encoding="utf-8") as datei:
            daten = json.load(datei).get("aufnahmen", {})
        return {name: e for name, e in daten.items() if isinstance(name, str) and _gueltig(e)}
    except FileNotFoundError:
        pass
    except Exception:
        return {}
    try:                                   # die eine Aufnahme von frueher uebernehmen
        with open(ALTE_AUFNAHME_DATEI, encoding="utf-8") as datei:
            alt = json.load(datei).get("ereignisse", [])
        return {"aufnahme": alt} if _gueltig(alt) else {}
    except Exception:
        return {}


def speichere_aufnahmen(aufnahmen):
    with open(AUFNAHMEN_DATEI, "w", encoding="utf-8") as datei:
        json.dump({"aufnahmen": aufnahmen}, datei)


MENUE_WARTEN = 5.0   # so lange wartet das Abspielen hoechstens, bis ein Menue auf- oder zugeht


def spiele_ab(ereignisse, tasten):
    """Spielt eine Aufnahme so ab, wie sie aufgenommen wurde. Geht ein Menue (Truhe, Chat ...)
    langsamer auf als bei der Aufnahme, wartet es darauf, statt daneben zu klicken.
    Liefert None, wenn alles abgespielt ist, "F12" bei F12, sonst den Grund fuer den Abbruch."""
    tasten_unten, knoepfe_unten = set(), set()
    start, verschoben = time.monotonic(), 0.0
    zeiger = None                      # wohin der Zeiger im Menue zuletzt gesetzt wurde
    fehlt = None                       # (menue, seit) - darauf wird schon gewartet
    gehalten = {}                      # gehaltene Taste -> wann sie sich wieder wiederholt

    def wiederholen():
        """Eine gehaltene Taste wiederholt sich (wie beim Loeschen im Chat) - nur in Menues,
        im Spiel braucht man das nicht."""
        if gehalten and mauszeiger_sichtbar():
            jetzt = time.monotonic()
            for taste_, wann in list(gehalten.items()):
                if jetzt >= wann:
                    taste_roh(taste_[0], taste_[1], 1)
                    gehalten[taste_] = jetzt + 1 / 30

    def abbruch():
        if tasten.neu(VK_F12):
            return "F12"
        if tasten.neu(VK_F8):
            return "Aufnahme abgebrochen (F8)."
        if minecraft_fenster() is None:
            return "Minecraft ist nicht mehr vorne - ich habe die Aufnahme abgebrochen."
        return None

    try:
        for e in ereignisse:
            while True:
                grund = abbruch()
                if grund:
                    return grund
                wiederholen()
                rest = start + verschoben + e[1] - time.monotonic()
                if rest <= 0:
                    break
                time.sleep(min(rest, 0.01))
            menue = menue_von(e)
            # Klicks und Zeiger-Bewegungen in Menues brauchen dasselbe Menue wie bei der Aufnahme.
            # Geht eine Truhe oder ein Server-Menue langsamer auf (oder zu), wird darauf gewartet,
            # statt daneben zu klicken. Tasten laufen einfach nach der Uhr.
            klick = e[0] == "k" and e[3]
            if menue is not None and (klick or (e[0] == "b" and menue)) and mauszeiger_sichtbar() != menue:
                # insgesamt hoechstens MENUE_WARTEN auf dasselbe Menue warten
                seit = fehlt[1] if fehlt and fehlt[0] == menue else time.monotonic()
                while mauszeiger_sichtbar() != menue and time.monotonic() - seit <= MENUE_WARTEN:
                    grund = abbruch()
                    if grund:
                        return grund
                    time.sleep(0.02)
                if mauszeiger_sichtbar() != menue:
                    if klick:
                        return ("Das Menue ist nicht %s wie bei der Aufnahme - ich habe abgebrochen,"
                                " damit ich nicht daneben klicke." % ("aufgegangen" if menue else "zugegangen"))
                    fehlt = (menue, seit)
                    verschoben += time.monotonic() - seit   # im Takt bleiben, nicht alles auf einmal
                    continue           # nur eine Zeiger-Bewegung: auslassen
                fehlt = None
                time.sleep(0.15)       # kurz warten, bis das Menue fertig aufgebaut ist
                verschoben += time.monotonic() - seit
            fenster = minecraft_fenster()
            if fenster is None:
                return "Minecraft ist nicht mehr vorne - ich habe die Aufnahme abgebrochen."
            im_menue = mauszeiger_sichtbar()
            if e[0] == "t":
                taste_roh(e[2], e[3], e[4])
                (tasten_unten.add if e[4] else tasten_unten.discard)((e[2], e[3]))
                if e[4]:
                    gehalten.setdefault((e[2], e[3]), time.monotonic() + 0.5)
                else:
                    gehalten.pop((e[2], e[3]), None)
            elif e[0] == "k":
                if e[3] and im_menue and zeiger is not None:
                    zeiger_hin(*zeiger)        # Zeiger sicher an der Stelle, kleiner Ruck,
                    maus_relativ(1, 0)         # damit Minecraft ihn dort bemerkt
                    maus_relativ(-1, 0)
                maus_knopf(e[2], e[3])
                (knoepfe_unten.add if e[3] else knoepfe_unten.discard)(e[2])
            elif e[0] == "r":
                maus_rad(e[2])
            elif e[0] == "b":
                war_menue = im_menue if menue is None else menue
                if war_menue and im_menue and e[4] is not None:   # Menue: Zeiger an dieselbe Stelle
                    links, oben, breite, hoehe = fenster
                    zeiger = (links + breite / 2 + e[4], oben + hoehe / 2 + e[5])
                    zeiger_hin(*zeiger)
                elif not war_menue and not im_menue:              # im Spiel: Kamera drehen
                    maus_relativ(e[2], e[3])
        return None
    finally:
        for scan, e0 in tasten_unten:    # nichts gedrueckt lassen
            taste_roh(scan, e0, 0)
        for knopf in knoepfe_unten:
            maus_knopf(knopf, 0)


def eingabe(text):
    """Eine Zeile eintippen lassen (None, wenn das nicht geht)."""
    try:
        return input(text).strip()
    except (EOFError, OSError):
        return None


def nimm_auf(tasten, sofort):
    """Nimmt auf, bis man in Minecraft F9 oder in diesem Fenster Enter drueckt."""
    aufnahme = Aufnahme(sofort=sofort)
    tasten.neu(VK_F9)                      # einen alten F9-Druck vergessen
    kamera_geht = starte_lauscher(aufnahme)
    if sofort:
        sag("AUFNAHME laeuft. Mach jetzt in Minecraft vor, was ich machen soll.")
    else:
        sag("Geh jetzt in Minecraft. Sobald du dort im Spiel bist (kein Menue offen), piept es"
            " und die Aufnahme laeuft.")
    sag("Fertig? In Minecraft F9 druecken - oder zurueck in dieses Fenster und Enter druecken.")
    if not kamera_geht:
        sag("(Kamera-Drehen und Mausrad kann ich hier leider nicht aufnehmen - Tasten, Klicks und"
            " Menues schon.)")
    gemeldet, stand_vorher, gezeigt = sofort, None, 0.0
    try:
        while not (tasten.neu(VK_F9) or konsole_enter()):
            if not gemeldet and aufnahme.laeuft:
                gemeldet = True
                piep()
                sag("AUFNAHME laeuft - mach jetzt vor, was ich machen soll.")
            stand = aufnahme.stand()
            if gemeldet and stand != stand_vorher and time.monotonic() - gezeigt >= 1.0:
                sag("  bisher: " + stand)
                stand_vorher, gezeigt = stand, time.monotonic()
            time.sleep(0.02)
    finally:
        stoppe_lauscher()
    return aufnahme.stopp()


def speichere_neue(aufnahmen, name, ereignisse):
    """Aufnahme unter diesem Namen speichern und zeigen, was drin ist."""
    if not ereignisse:
        sag("In der Aufnahme ist nichts drin - ich nehme nur auf, was in Minecraft passiert."
            " Nichts gespeichert.")
        return False
    aufnahmen[name] = ereignisse
    speichere_aufnahmen(aufnahmen)
    sag("Gespeichert als '%s' (%s):" % (name, aufnahme_text(ereignisse)))
    sag("  " + aufnahme_ablauf(ereignisse))
    return True


def waehle_aufnahme(aufnahmen, frage, vorschlag=None):
    """Eine der gespeicherten Aufnahmen auswaehlen lassen (Nummer oder Name)."""
    namen = list(aufnahmen)
    if not namen:
        return None
    standard = vorschlag if vorschlag in aufnahmen else namen[0]
    if len(namen) == 1:
        return namen[0]
    for nummer, name in enumerate(namen, 1):
        print("  %d = %s (%s)" % (nummer, name, aufnahme_text(aufnahmen[name])))
    while True:
        antwort = eingabe("%s Nummer eingeben (nur Enter = %s): " % (frage, standard))
        if not antwort:
            return standard
        if antwort.isdigit() and 1 <= int(antwort) <= len(namen):
            return namen[int(antwort) - 1]
        if antwort in aufnahmen:
            return antwort
        print("Bitte eine Zahl von 1 bis %d eingeben." % len(namen))


def warte_auf_spiel(tasten, hoechstens=60.0):
    """Warten, bis Minecraft vorne ist und kein Menue offen ist. False = abgebrochen."""
    bis, seit = time.monotonic() + hoechstens, None
    while time.monotonic() < bis:
        if tasten.neu(VK_F8) or konsole_enter():
            return False
        if minecraft_fenster() is not None:
            seit = seit or time.monotonic()
            if not mauszeiger_sichtbar() or time.monotonic() - seit > 5.0:
                time.sleep(1.0)
                return minecraft_fenster() is not None
        else:
            seit = None
        time.sleep(0.05)
    return False


def hauptmenue(tasten):
    """Vor dem Angeln: Aufnahmen machen, ausprobieren oder loeschen."""
    while True:
        aufnahmen = lade_aufnahmen()
        print()
        print("Was moechtest du machen?")
        print("  1 = Angeln")
        print("  2 = Neue Aufnahme machen und speichern")
        if aufnahmen:
            print("  3 = Aufnahme ausprobieren")
            print("  4 = Aufnahme loeschen")
            print("  Gespeicherte Aufnahmen: " + ", ".join(
                "%s (%.1f s)" % (name, e[-1][1]) for name, e in aufnahmen.items()))
        antwort = eingabe("Nummer eingeben (nur Enter = 1 = Angeln): ")
        if antwort is None or antwort in ("", "1"):
            return
        if antwort == "2":
            vorschlag, nummer = "aufnahme", 2
            while vorschlag in aufnahmen:
                vorschlag, nummer = "aufnahme%d" % nummer, nummer + 1
            name = eingabe("Wie soll die Aufnahme heissen? z. B. verkaufen (nur Enter = %s): " % vorschlag)
            if name is None:
                return
            name = name or vorschlag
            if name in aufnahmen:
                ja = eingabe("'%s' gibt es schon - ersetzen? (j/n): " % name)
                if not ja or ja.lower()[0] not in "jy":
                    continue
            speichere_neue(aufnahmen, name, nimm_auf(tasten, sofort=False))
        elif antwort == "3" and aufnahmen:
            name = waehle_aufnahme(aufnahmen, "Welche Aufnahme soll ich abspielen?")
            sag("Geh in Minecraft. Sobald du dort im Spiel bist (kein Menue offen), spiele ich '%s'"
                " ab (%s). F8 = abbrechen." % (name, aufnahme_text(aufnahmen[name])))
            if not warte_auf_spiel(tasten):
                sag("Abgebrochen.")
                continue
            abbruch = spiele_ab(aufnahmen[name], tasten)
            sag("Abgebrochen." if abbruch == "F12" else abbruch or "Fertig abgespielt.")
        elif antwort == "4" and aufnahmen:
            name = waehle_aufnahme(aufnahmen, "Welche Aufnahme soll ich loeschen?")
            ja = eingabe("'%s' wirklich loeschen? (j/n): " % name)
            if ja and ja.lower()[0] in "jy":
                del aufnahmen[name]
                speichere_aufnahmen(aufnahmen)
                sag("'%s' geloescht." % name)
        else:
            print("Bitte eine der Nummern eingeben.")


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


ZIEL_AKTIONEN = ("Pause machen und piepen (F8 = nochmal)", "Leertaste druecken, dann Pause",
                 "Bot beenden", "Laptop ausschalten", "Aufnahme abspielen, dann Pause",
                 "Aufnahme abspielen, dann weiter angeln (nochmal so viele)")


def frage_nach_ziel(ziel, vorschlag):
    """Was passiert, wenn alle Minispiele gespielt sind? 1-4, siehe ZIEL_AKTIONEN."""
    if NACH_ZIEL is not None:
        return min(len(ZIEL_AKTIONEN), max(1, int(NACH_ZIEL)))
    print("Was soll ich machen, wenn die %d Minispiele gespielt sind?" % ziel)
    for nummer, text in enumerate(ZIEL_AKTIONEN, 1):
        print("  %d = %s" % (nummer, text))
    while True:
        try:
            antwort = input("Nummer eingeben (nur Enter = %d): " % vorschlag).strip()
        except (EOFError, OSError):
            return vorschlag
        if not antwort:
            return vorschlag
        if antwort.isdigit() and 1 <= int(antwort) <= len(ZIEL_AKTIONEN):
            return int(antwort)
        print("Bitte eine Zahl von 1 bis %d eingeben." % len(ZIEL_AKTIONEN))


def frage_ausschalten():
    """Nach wie vielen Stunden soll der Laptop ausgehen? 0 = nie."""
    if AUSSCHALTEN_NACH is not None:
        return max(0.0, float(AUSSCHALTEN_NACH))
    while True:
        try:
            antwort = input("Soll ich den Laptop ausschalten? Nach wie vielen Stunden? z. B. 2 oder 1,5"
                            " (nur Enter = nicht ausschalten): ").strip().lower()
        except (EOFError, OSError):
            return 0.0
        if not antwort or antwort in ("n", "nein"):
            return 0.0
        zahl = re.sub(r"[^0-9,.]", "", antwort).replace(",", ".")
        try:
            stunden = float(zahl)
        except ValueError:
            stunden = -1.0
        if "min" in antwort:
            stunden /= 60
        if 0 <= stunden <= 24:
            return stunden
        print("Bitte die Stunden als Zahl eingeben, zum Beispiel 2 oder 1,5 (oder 90 min).")


def laptop_ausschalten():
    """Windows in 1 Minute herunterfahren. Abbrechen geht mit: shutdown /a"""
    try:
        geklappt = subprocess.run(["shutdown", "/s", "/t", "60", "/c",
                                   "Angel-Bot: Der Laptop geht in 1 Minute aus."
                                   " Abbrechen: Windows-Taste + R, shutdown /a eintippen, Enter."]).returncode == 0
    except OSError:
        geklappt = False
    if geklappt:
        sag("Der Laptop geht in 1 Minute aus. Abbrechen: Windows-Taste + R, shutdown /a eintippen, Enter.")
    else:
        sag("Ausschalten hat nicht geklappt - bitte selbst ausschalten.")
    piep()


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


def frage_kaputt_ausschalten(vorschlag):
    """Soll der Laptop ausgehen, wenn die Angel fast kaputt ist?"""
    if KAPUTT_AUSSCHALTEN is not None:
        return bool(KAPUTT_AUSSCHALTEN)
    while True:
        antwort = eingabe("Wenn die Angel fast kaputt ist: Laptop ausschalten? j/n (nur Enter = %s): "
                          % ("j" if vorschlag else "n"))
        if not antwort:
            return vorschlag
        if antwort.lower()[0] in "jy":
            return True
        if antwort.lower()[0] == "n":
            return False
        print("Bitte j (ja) oder n (nein) eingeben.")


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
    hauptmenue(tasten)
    ziel = frage_anzahl()
    sag("Ich spiele %s." % ("%d Minispiele" % ziel if ziel else "ohne Ende"))
    nach_ziel = gelernt.get("nach_ziel", 1)
    if not (isinstance(nach_ziel, int) and 1 <= nach_ziel <= len(ZIEL_AKTIONEN)):
        nach_ziel = 1
    if ziel:
        nach_ziel = frage_nach_ziel(ziel, nach_ziel)
        sag("Wenn die %d Minispiele gespielt sind: %s." % (ziel, ZIEL_AKTIONEN[nach_ziel - 1]))
    aufnahme_name = gelernt.get("aufnahme_name")
    if ziel and nach_ziel >= 5:
        aufnahmen = lade_aufnahmen()
        if aufnahmen:
            aufnahme_name = waehle_aufnahme(aufnahmen, "Welche Aufnahme soll ich dann abspielen?", aufnahme_name)
            sag("Ich spiele dann '%s' ab (%s)." % (aufnahme_name, aufnahme_text(aufnahmen[aufnahme_name])))
        else:
            sag("Es gibt noch keine Aufnahme. Mach eine mit F9 (in Minecraft) - oder starte mich neu"
                " und waehle im ersten Menue 2.")
    stunden = frage_ausschalten()
    ausschalten_um, ausschalten_gewarnt = None, True
    if stunden > 0:
        ausschalten_um = time.monotonic() + stunden * 3600
        ausschalten_gewarnt = stunden * 60 <= 10  # bei weniger als 10 Minuten nicht extra vorwarnen
        minuten = round(stunden * 60)
        sag("In %d:%02d Stunden (um %s Uhr) hoere ich auf und schalte den Laptop aus." % (
            minuten // 60, minuten % 60, time.strftime("%H:%M", time.localtime(time.time() + stunden * 3600))))
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
    kaputt_aus = gelernt.get("kaputt_ausschalten", True) is not False
    if HALTBARKEIT_MIN > 0:
        kaputt_aus = frage_kaputt_ausschalten(kaputt_aus)
        sag("Ist die Angel fast kaputt (unter %d), hoere ich auf, druecke die Leertaste%s." % (
            HALTBARKEIT_MIN, " und schalte den Laptop aus" if kaputt_aus else ""))

    def speichern():
        speichere_gelerntes(dict(vorausschau.gelernt(), angel_platz=angel_platz, haltbarkeit=haltbarkeit,
                                 nach_ziel=nach_ziel, aufnahme_name=aufnahme_name,
                                 kaputt_ausschalten=kaputt_aus))

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
            if tasten.neu(VK_F9):
                # Aufnahme mitten beim Angeln: speichert unter dem Namen, der bei Nr. 5/6 abgespielt wird
                aktiv, zustand = False, "auswerfen"
                aufnahme_name = aufnahme_name or "aufnahme"
                sag("Aufnahme '%s' (ersetzt die alte mit diesem Namen):" % aufnahme_name)
                if speichere_neue(lade_aufnahmen(), aufnahme_name, nimm_auf(tasten, sofort=True)):
                    speichern()
                    sag("F7 (in Minecraft) = zum Ausprobieren abspielen, F8 = weiter angeln.")
                seit = time.monotonic()
            if tasten.neu(VK_F7):
                aufnahmen = lade_aufnahmen()
                name = aufnahme_name if aufnahme_name in aufnahmen else next(iter(aufnahmen), None)
                if name is None:
                    sag("Es gibt noch keine Aufnahme - mit F9 aufnehmen.")
                elif minecraft_fenster() is None:
                    sag("Zum Ausprobieren in Minecraft gehen und dort F7 druecken.")
                else:
                    aktiv, zustand = False, "auswerfen"
                    sag("Ich spiele '%s' zum Ausprobieren ab (%s). F8 = abbrechen."
                        % (name, aufnahme_text(aufnahmen[name])))
                    abbruch = spiele_ab(aufnahmen[name], tasten)
                    if abbruch == "F12":
                        sag("Beendet. Minispiele gespielt: %d" % runden)
                        return
                    sag(abbruch or "Aufnahme fertig abgespielt. F8 = angeln.")
                    seit = time.monotonic()
            if tasten.neu(VK_F8):
                aktiv = not aktiv
                zustand = "auswerfen"
                angel_pruefen = True
                seit = time.monotonic()
                warte_grund = None
                sag("LAEUFT" if aktiv else "PAUSE (F8 = weiter)")

            # Laptop ausschalten, wenn die Zeit um ist (auch in der Pause).
            if ausschalten_um is not None:
                nun = time.monotonic()
                if not ausschalten_gewarnt and nun >= ausschalten_um - 300:
                    ausschalten_gewarnt = True
                    sag("In 5 Minuten schalte ich den Laptop aus.")
                # Ein laufendes Minispiel noch fertig spielen (hoechstens 1 Minute laenger).
                if nun >= ausschalten_um and (zustand != "spiel" or not aktiv or nun >= ausschalten_um + 60):
                    speichern()
                    sag("Die Zeit ist um - ich hoere auf. Minispiele gespielt: %d" % runden)
                    laptop_ausschalten()
                    return

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
                            if kaputt_aus:
                                speichern()
                                sag("Ich schalte den Laptop aus. Minispiele gespielt: %d" % runden)
                                laptop_ausschalten()
                                return
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
                        sag("Fertig: %d Minispiele gespielt!" % gespielt)
                        if nach_ziel == 3:
                            sag("Ich beende mich. Minispiele insgesamt: %d" % runden)
                            piep()
                            return
                        if nach_ziel == 4:
                            sag("Ich schalte den Laptop aus.")
                            laptop_ausschalten()
                            return
                        if nach_ziel == 2:
                            taste(VK_SPACE)
                            sag("Leertaste gedrueckt.")
                        weiter = False
                        if nach_ziel >= 5:
                            ereignisse = lade_aufnahmen().get(aufnahme_name)
                            if not ereignisse:
                                sag("Es gibt keine Aufnahme '%s' (F9 = aufnehmen)." % aufnahme_name)
                            else:
                                time.sleep(NACH_FANG_PAUSE)   # Fang erst ganz fertig werden lassen
                                sag("Ich spiele '%s' ab (%s). F8 = abbrechen." % (
                                    aufnahme_name, aufnahme_text(ereignisse)))
                                abbruch = spiele_ab(ereignisse, tasten)
                                if abbruch == "F12":
                                    sag("Beendet. Minispiele gespielt: %d" % runden)
                                    return
                                if abbruch:
                                    sag(abbruch)
                                else:
                                    sag("Aufnahme fertig abgespielt.")
                                    weiter = nach_ziel == 6
                        if weiter:
                            sag("Ich angle weiter: nochmal %d Minispiele." % ziel)
                            gespielt, seit = 0, time.monotonic()
                        else:
                            sag("Ich mache Pause. F8 = nochmal %d spielen, F12 = beenden." % ziel)
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
