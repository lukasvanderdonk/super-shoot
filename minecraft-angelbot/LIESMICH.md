# Angel-Bot für das Minecraft-Angel-Minispiel

Der Bot angelt für dich: auswerfen, auf den Biss warten, im Minispiel genau dann
rechtsklicken, wenn der weiße Rahmen auf dem roten Feld steht, und danach wieder
auswerfen. Er schaut dafür nur auf das Minecraft-Fenster und klickt nur, solange
Minecraft vorne ist und kein Menü (Inventar, Chat, Pause) offen ist.

## Angeln lassen

1. **`Angel-Bot.bat` doppelklicken.** Das ist alles in einer Datei: Sie findet
   ein vorhandenes Python von selbst. Fehlt Python, installiert sie es (das dauert
   beim ersten Mal ein paar Minuten), dazu die Pakete `mss` und `numpy`.
   Falls Windows „Der Computer wurde geschützt“ zeigt:
   „Weitere Informationen“ → „Trotzdem ausführen“.
2. Zuerst kommt ein kleines Menü: **1 = Angeln** (nur Enter), **2 = Neue Aufnahme
   machen**, **3 = Aufnahme ausprobieren**, **4 = Aufnahme löschen** – mehr dazu unten
   bei „Aufnahmen“.
   Dann fragt der Bot: **Wie viele Minispiele soll ich spielen?** Zahl eintippen und
   Enter – oder nur Enter für „ohne Ende“.
   Hast du eine Zahl eingegeben, fragt er: **Was soll ich machen, wenn die
   Minispiele gespielt sind?**

   | Nummer | Was passiert |
   |--------|--------------|
   | 1 | Pause machen und piepen – mit F8 spielt er nochmal so viele |
   | 2 | Leertaste drücken, dann Pause und piepen |
   | 3 | Bot beenden |
   | 4 | Laptop ausschalten (in 1 Minute, abbrechen: Windows-Taste + R, `shutdown /a`, Enter) |
   | 5 | Eine deiner **Aufnahmen** abspielen, dann Pause und piepen |
   | 6 | Eine deiner **Aufnahmen** abspielen, dann weiter angeln (nochmal so viele) |

   Bei 5 oder 6 fragt er, welche Aufnahme (wenn du mehrere hast).
   Er merkt sich deine Wahl – beim nächsten Mal reicht Enter.
   Dann fragt er: **Soll ich den Laptop ausschalten? Nach wie vielen Stunden?**
   Zum Beispiel `2` (oder `1,5` oder `90 min`) – oder nur Enter, dann bleibt der
   Laptop an. Mehr dazu unten bei „Laptop ausschalten“.
   Dann fragt er: **Auf welchem Platz liegt die Angel?** 1 = ganz links … 9 = ganz
   rechts in der untersten Inventar-Reihe. Er merkt sich die Antwort – beim nächsten
   Mal reicht Enter.
   Zuletzt fragt er: **Wie viel Haltbarkeit hat die Angel?** Bei einer neuen Angel
   nur Enter (= 64), sonst die Zahl eintippen, z. B. `35`.
3. Minecraft-Fenster hinstellen, wo du willst: maximiert, halber Bildschirm links
   oder rechts oder ein Viertel (oben/unten, links/rechts). Angel in die Hand nehmen
   (noch **nicht** auswerfen) und aufs Wasser schauen.
4. **F8 drücken** – los geht's.

| Taste | Was passiert |
|-------|--------------|
| F8    | Start / Pause |
| F9    | Beim Angeln: Aufnahme starten / fertig |
| F7    | Beim Angeln: Aufnahme zum Ausprobieren abspielen (in Minecraft drücken) |
| F10   | Diagnose-Bild speichern (was der Bot gerade sieht) |
| F12   | Bot beenden |

Im schwarzen Fenster steht immer, was der Bot gerade macht.

## Haltbarkeit der Angel

Damit deine Angel nicht kaputtgeht, schaut der Bot beim Start und nach jedem
Minispiel nach: Er wirft ganz normal aus, drückt **I** (Inventar), fährt mit der
Maus über den Angel-Platz und liest im Infokasten „Haltbarkeit: 35/64“. Dann
schließt er das Inventar wieder (Esc) und angelt weiter.
**Ist die Haltbarkeit unter 5**, hört er sofort auf, drückt einmal die
**Leertaste** und piept.

Damit das klappt:
- Beim Start den richtigen **Platz der Angel** angeben (1 = ganz links … 9 = ganz
  rechts in der untersten Inventar-Reihe).
- **F3+H** ist an (erweiterte Infos) – sonst steht „Haltbarkeit“ nicht im Infokasten.
- Das Rezeptbuch im Inventar ist zu.

**Kann er die Haltbarkeit nicht lesen** (Inventar geht nicht auf, kein „Haltbarkeit“
im Infokasten, auf dem Platz liegt etwas anderes als die Angel), rechnet er so, als
wäre sie **genau 1 weniger als beim letzten Mal**, und angelt weiter. Aufgehört wird
nur, wenn das unter 5 ist. Neben `Angel-Bot.bat` liegt dann ein Bild
`diagnose_haltbarkeit.png` – das kannst du Claude schicken, wenn es öfter passiert.

**Neue Angel:** Minecraft zeigt die Haltbarkeit erst an, wenn die Angel einmal etwas
abbekommen hat. Darum fragt der Bot beim Start, wie viel Haltbarkeit die Angel hat
(nur Enter = 64 = neue Angel). Mit dieser Zahl rechnet er, bis er sie im Inventar
lesen kann – danach zählt immer der gelesene Wert.

## Aufnahmen (Nr. 5 und 6)

Du kannst dem Bot vormachen, was er nach den Minispielen tun soll – zum Beispiel
Fische verkaufen (Chat öffnen, Befehl tippen, Enter) oder in eine Truhe legen.
Er macht es dann genau so nach: dieselben Tasten und Klicks, gleich lang und im
gleichen Takt. Du kannst mehrere Aufnahmen mit Namen speichern.

**Neue Aufnahme machen:**
1. Bot starten, im ersten Menü **2** eintippen, Enter.
2. Einen **Namen** eintippen, z. B. `verkaufen`, Enter.
3. **In Minecraft gehen.** Ist dort das Pause-Menü offen, mach es zu. Sobald du im
   Spiel bist, **piept** es – ab jetzt nimmt er auf.
4. Vormachen, was er später machen soll. Er merkt sich Tasten (auch wie lange du
   sie hältst), Maustasten, Mausrad und Mausbewegungen – im Spiel als Kameradrehung,
   im Inventar oder in einer Truhe als Stelle, an der der Mauszeiger steht.
   Im schwarzen Fenster siehst du nebenbei „bisher: 5 Tasten, 1 Klicks“.
5. **Fertig:** zurück ins schwarze Fenster und **Enter** drücken (oder in Minecraft
   F9). Er zeigt, was drin ist, zum Beispiel
   `T > UMSCHALT > 7 > S > E > L > L > EINGABE > Rechtsklick > Linksklick im Menue`.

Das Zurückwechseln ins schwarze Fenster (Alt+Tab oder Klick) kommt nicht mit in die
Aufnahme, das Pause-Menü am Anfang auch nicht.

**Ausprobieren:** im ersten Menü **3**, Aufnahme wählen, in Minecraft gehen – sobald
du im Spiel bist, spielt er sie ab. Klappt etwas nicht, einfach neu aufnehmen (gleicher
Name ersetzt die alte). **Löschen:** im ersten Menü **4**.

**Beim Angeln** geht es auch mit Tasten: **F9** in Minecraft startet und beendet eine
Aufnahme (sie ersetzt die, die bei Nr. 5/6 abgespielt wird), **F7** spielt sie ab.

Gespeichert wird alles in `angelbot_aufnahmen.json` neben `Angel-Bot.bat`.

Gut zu wissen:
- Aufgenommen wird nur, was in Minecraft passiert. F7 bis F12 und die Windows-Taste
  sind nicht drin.
- Geht beim Abspielen ein Menü langsamer auf als beim Aufnehmen (Truhe, Shop, Server-Menü),
  wartet er mit dem Klicken, bis es offen ist – bis zu 5 Sekunden. Geht es gar nicht auf,
  bricht er ab, statt daneben zu klicken.
- Hältst du im Chat oder in einem Menü eine Taste gedrückt (z. B. Löschen), wiederholt
  sie sich beim Abspielen.
- Lass das Minecraft-Fenster beim Abspielen genauso groß wie beim Aufnehmen –
  sonst treffen Klicks im Inventar nicht dieselbe Stelle.
- Bei **6** angelt er danach gleich weiter. Hör beim Aufnehmen darum so auf, wie
  du angefangen hast: Angel in der Hand, Blick aufs Wasser.
- Abbrechen: **F8** drücken oder ein anderes Fenster anklicken – dann hört er sofort
  auf und lässt keine Taste gedrückt.
- In Minecraft unter *Optionen → Steuerung → Maus* „Rohe Eingabe“ an lassen
  (ist normalerweise an), dann dreht sich die Kamera genau wie beim Aufnehmen.
  Schreibt der Bot „Kamera-Drehen und Mausrad kann ich hier nicht aufnehmen“, gehen
  Tasten, Klicks und Menüs trotzdem.

## Laptop ausschalten

Gibst du beim Start Stunden an, zum Beispiel `2`, sagt der Bot, um wie viel Uhr er
aufhört. 5 Minuten vorher sagt er Bescheid. Ist die Zeit um, spielt er ein
laufendes Minispiel noch fertig, hört dann auf und lässt Windows in **1 Minute**
herunterfahren (offene Programme wie Minecraft werden dabei geschlossen).
Die Zeit läuft auch, wenn der Bot gerade Pause macht.

**Doch nicht ausschalten?** In der Minute davor: Windows-Taste + R drücken,
`shutdown /a` eintippen, Enter. Vorher reicht es, den Bot mit F12 zu beenden.

## Fenstergröße und -position

Der Bot funktioniert in jeder Fensterlage. Wichtig ist nur:
- **Minecraft muss das aktive Fenster sein.** Andere Fenster dürfen daneben zu
  sehen sein – klickst du aber hinein, pausiert der Bot, bis Minecraft wieder vorne ist.
- **Die ganze Leiste muss ins Fenster passen.** Die Leiste steht in der Mitte des
  Fensters und ist in hohen, schmalen Fenstern (halber Bildschirm) manchmal breiter
  als das Fenster. Ist ein Feld ganz außen ein bisschen abgeschnitten, ist das egal.
  Fehlt ein ganzes Feld, sagt der Bot Bescheid und nennt die **GUI-Größe**, die du in
  Minecraft unter *Optionen → Grafikeinstellungen* einstellen solltest.
- Die Punkte-Tafel des Servers rechts stört nicht.

## Vorausschauen und Dazulernen

Je näher der Fang, desto schneller springt der weiße Rahmen – und ein Klick
daneben kostet einen Haken. Der Bot misst darum bei jedem Schritt, wie schnell
der Rahmen gerade ist, und bei jedem Treffer, wie lange sein Klick bis zum Server
braucht (so lange dauert es, bis das rote Feld springt). Käme ein Klick „auf Sicht“
zu spät an, klickt er vorher – wenn nötig ein oder zwei Felder früher –, sodass
der Klick in der Mitte der Zeit ankommt, in der der Rahmen auf Rot steht.
Wäre es sicher zu spät, lässt er den Durchgang lieber aus, statt einen Haken zu
riskieren.

Er lernt dabei aus jedem Klick:
- **Vorlauf (wie viel früher klicken):** Bei jedem Treffer weiß er: Der richtige
  Vorlauf liegt in einem bestimmten Bereich – sonst wäre der Klick zu früh oder zu
  spät angekommen. Bei jedem Fehlklick weiß er: Er liegt *nicht* in diesem Bereich.
  Aus den letzten 30 Klicks nimmt er den Vorlauf, der zu den meisten Ergebnissen
  passt (die Mitte davon). Neuere Klicks zählen mehr. Das klappt auch, wenn der
  Server Treffer und rote X erst verzögert anzeigt.
- **Antwortzeit:** Zeit vom Klick, bis das rote Feld springt oder ein rotes X
  erscheint. Sie dient als Startwert und als Obergrenze für den Vorlauf.
- **Tempo-Gedächtnis:** wie schnell der Rahmen nach dem 1., 2., 3. … Treffer
  normalerweise ist – so kann er direkt nach einem Treffer schon vorausschauen.

Was er gelernt hat, merkt er sich in `angelbot_gelernt.json` (neben
`Angel-Bot.bat`). Löschst du die Datei, fängt er wieder von vorne an.

## Wenn etwas nicht klappt

- **„Die Leiste ist breiter als das Minecraft-Fenster“**: Die GUI-Größe einstellen,
  die der Bot nennt (*Optionen → Grafikeinstellungen → GUI-Größe*), oder das Fenster
  breiter machen.
- **Der Bot merkt den Biss nicht oder klickt nicht**: Während das Minispiel läuft
  **F10** drücken. Neben `Angel-Bot.bat` liegt dann ein Bild `diagnose_….png` – schick es Claude,
  dann kann der Bot angepasst werden.
- **Kein Biss**: Nach 60 Sekunden ohne Biss holt der Bot die Angel ein und wirft neu aus.
- **Bilder/s**: Am Ende jedes Minispiels steht, wie oft der Bot pro Sekunde
  hingeschaut hat. Unter etwa 25 wird er ungenauer – dann hilft es, das
  Minecraft-Fenster kleiner zu machen (mittlerer Knopf oben rechts), aber nur so
  weit, dass die ganze Leiste noch zu sehen ist. Andere Programme schließen hilft auch.

## Einstellungen

`Angel-Bot.bat` mit dem Editor öffnen: Unter „Einstellungen“ im Python-Teil stehen
ein paar Zahlen, die du ändern kannst, z. B.
`SPIELE_ZIEL` (z. B. `SPIELE_ZIEL = 10`, dann fragt er beim Start nicht mehr; `0` =
ohne Ende), `NACH_ZIEL` (was danach passiert, `1` bis `6` wie oben, dann fragt er nicht mehr), `AUSSCHALTEN_NACH` (Stunden, z. B. `2`; `0` = nie ausschalten und nicht fragen), `HALTBARKEIT_MIN` (ab wann er aufhört; `0` = nicht prüfen), `ANGEL_PLATZ` (z. B. `7`,
dann fragt er nicht mehr nach dem Platz), `HALTBARKEIT_START` (z. B. `64`, dann fragt er nicht
mehr nach der Haltbarkeit),
`INVENTAR_TASTE`, `WARTEN_MAX` (wie lange er auf einen Biss wartet), `NACH_FANG_PAUSE` oder
`SICHERHEIT` (größer = vorsichtiger, lässt eher einen Durchgang aus).
