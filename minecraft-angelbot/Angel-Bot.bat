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

Tasten:  F8 = Start / Pause   F10 = Diagnose-Bild speichern   F12 = Beenden
"""

import json
import sys
import time

import numpy as np

# ---------------------------------------------------------------- Einstellungen

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
      abstand   Abstand von Feldmitte zu Feldmitte in Pixeln
      rot_unten rote Pixel unter der Leiste (rote X auf den Haken = Fehlklicks)
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
    rahmen_spalten = oben & unten
    rahmen_stuecke = [(s, e) for s, e in laeufe(rahmen_spalten) if e - s >= feld * 0.15]

    # 6. Steht der Rahmen auf dem roten Feld? (Am Fensterrand kann das Feld halb
    #    abgeschnitten sein, darum reicht schon ein Stueck davon.)
    im_rahmen_rot = int((rot_spalten & rahmen_spalten).sum())
    auf_rot = im_rahmen_rot >= max(2, feld * 0.15)

    # 7. Reicht die Leiste bis an den Fensterrand? Dann ist sie vermutlich abgeschnitten.
    zeile = farbig[y0:y1 + 1].any(axis=0) | rahmen_spalten
    abgeschnitten = bool(zeile[:2].any() or zeile[-2:].any())

    # 8. Rote Pixel unter der Leiste: Dort erscheint bei einem Fehlklick ein rotes X
    #    auf einem der Haken. Steigt die Zahl, war der Klick daneben.
    u0 = min(hoehe, y1 + 1 + int(h * 0.8))
    u1 = min(hoehe, y1 + 1 + int(h * 3))
    rot_unten = int(rot[u0:u1].sum())

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
        "abstand": abstand,
        "abgeschnitten": abgeschnitten,
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

        abstand = info["abstand"]
        self._verfolge_rahmen(info["rahmen_x"], jetzt, abstand)
        if self.klick is not None and self.gerade_gesprungen and info["auf_rot"] and not self.klick["gesehen"]:
            # Nach einem vorausschauenden Klick kommt der Rahmen auf Rot an: Jetzt wissen
            # wir genau, wann - besser als die Vorhersage.
            self.klick["ankunft"], self.klick["gesehen"] = jetzt, True
        self._pruefe_klick(info, jetzt, abstand)
        if self.klick is not None:
            return None  # erst abwarten, was der letzte Klick bewirkt hat

        L = self.vorlauf()
        T = self.takt()

        # Regel 1: Der Rahmen steht auf Rot -> klicken, wenn der Klick noch rechtzeitig ankommt.
        if info["auf_rot"]:
            vorsichtig = self.takt_vorsichtig()
            ankunft = self.letzte_ankunft
            if self.ankuenfte:
                ankunft = min(self.ankunft(T), self.ankuenfte[-1])
            if ankunft is not None and vorsichtig is not None:
                if jetzt + L > ankunft + vorsichtig * SICHT_GRENZE:
                    return None  # kaeme zu spaet an - lieber vorausschauend beim naechsten Durchgang
            # Nur wenn klar ist, seit wann der Rahmen auf Rot steht, taugt der Klick zum Lernen.
            nuetzlich = bool(self.ankuenfte) and self.ankuenfte[-1] == self.letzte_ankunft
            return self._klicke(info, jetzt, "auf Sicht", self.ankuenfte[-1] if nuetzlich else None,
                                self.bestes_tempo(), True)

        # Regel 2: Der Rahmen ist so schnell, dass der Klick vorher losgeschickt werden muss.
        if self.neu_gemessen == 0 and not self.hat_startwert and not self.erfahrung:
            return None  # erst einmal selbst messen, wie lange ein Klick braucht
        x, rot = info["rahmen_x"], info["rot_x"]
        if T is None or x is None or rot is None or not self.richtung or not self.ankuenfte:
            return None
        d = (rot - x) / abstand
        felder = int(round(abs(d)))
        if not 1 <= felder <= 4 or (d > 0) != (self.richtung > 0):
            return None  # rotes Feld liegt nicht direkt vor dem Rahmen
        ankunft_rot = self.ankunft(T) + felder * T
        klick_zeit = ankunft_rot + ZIEL * T - L
        if klick_zeit >= ankunft_rot:
            return None  # nicht noetig: auf Sicht klicken reicht
        if jetzt < klick_zeit - 0.5 / BILDER_PRO_SEKUNDE:
            return None  # noch nicht (das naechste Bild ist naeher dran)
        if jetzt + L > ankunft_rot + (1 - SICHERHEIT) * T:
            return None  # Moment verpasst
        return self._klicke(info, jetzt, "vorausschauend, %d Feld frueher" % felder, ankunft_rot, T, False)

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
    vorausschau = Vorausschau(lade_gelerntes())

    print(HILFE)
    if vorausschau.messungen or vorausschau.erfahrung:
        sag("Vom letzten Mal gelernt: Vorlauf %d ms (aus %d Klicks)" % (
            vorausschau.vorlauf() * 1000, len(vorausschau.erfahrung)))
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
    leiste_wieder = None  # seit wann die Leiste nach dem Fang wieder zu sehen ist
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
            bild = np.asarray(roh)[:, :, 2::-1]  # BGRA -> RGB
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
                if info["abgeschnitten"] and not rand_gewarnt:
                    rand_gewarnt = True
                    sag("Achtung: Die Leiste ist am Fensterrand abgeschnitten! Liegt das rote Feld"
                        " ausserhalb, kann ich es nicht sehen. Mach das Minecraft-Fenster gross"
                        " (maximieren) oder stell in den Optionen die GUI-Groesse kleiner.")

            if zustand == "auswerfen":
                if info is not None:
                    zustand, seit, treffer = "spiel", jetzt, 0  # Minispiel laeuft schon
                    vorausschau.neues_spiel()
                else:
                    rechtsklick()
                    sag("Ausgeworfen, warte auf einen Biss ...")
                    zustand, seit = "warten", jetzt

            elif zustand == "warten":
                if info is not None:
                    sag("Biss! Minispiel laeuft.")
                    zustand, seit, treffer = "spiel", jetzt, 0
                    vorausschau.neues_spiel()
                elif jetzt - seit > WARTEN_MAX:
                    sag("Kein Biss nach %d s - ich hole ein und werfe neu aus." % WARTEN_MAX)
                    rechtsklick()
                    time.sleep(1.0)
                    zustand = "auswerfen"

            elif zustand == "spiel":
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
                    runden += 1
                    sag("Minispiel vorbei (%d Klicks). Schon %d Minispiele gespielt." % (treffer, runden))
                    speichere_gelerntes(vorausschau.gelernt())
                    zustand, seit = "nach_fang", jetzt

            elif zustand == "nach_fang":
                # Nach dem Fang zeigt der Server die Leiste manchmal noch einmal kurz an.
                # Erst wenn sie laenger bleibt, laeuft das Spiel doch noch weiter.
                if info is None:
                    leiste_wieder = None
                elif leiste_wieder is None:
                    leiste_wieder = jetzt
                if leiste_wieder is not None and jetzt - leiste_wieder > 0.3:
                    zustand, leiste_wieder = "spiel", None
                    vorausschau.neues_spiel()
                elif leiste_wieder is None and jetzt - seit > NACH_FANG_PAUSE:
                    zustand = "auswerfen"

            rest = bild_takt - (time.monotonic() - start)
            if rest > 0:
                time.sleep(rest)


if __name__ == "__main__":
    main()
