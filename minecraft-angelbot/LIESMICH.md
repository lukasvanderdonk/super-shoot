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
2. Der Bot fragt: **Wie viele Minispiele soll ich spielen?** Zahl eintippen und
   Enter – oder nur Enter für „ohne Ende“.
   Hast du eine Zahl eingegeben, fragt er: **Was soll ich machen, wenn die
   Minispiele gespielt sind?**

   | Nummer | Was passiert |
   |--------|--------------|
   | 1 | Pause machen und piepen – mit F8 spielt er nochmal so viele |
   | 2 | Leertaste drücken, dann Pause und piepen |
   | 3 | Bot beenden |
   | 4 | Laptop ausschalten (in 1 Minute, abbrechen: Windows-Taste + R, `shutdown /a`, Enter) |

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
ohne Ende), `NACH_ZIEL` (was danach passiert, `1` bis `4` wie oben, dann fragt er nicht mehr), `AUSSCHALTEN_NACH` (Stunden, z. B. `2`; `0` = nie ausschalten und nicht fragen), `HALTBARKEIT_MIN` (ab wann er aufhört; `0` = nicht prüfen), `ANGEL_PLATZ` (z. B. `7`,
dann fragt er nicht mehr nach dem Platz), `HALTBARKEIT_START` (z. B. `64`, dann fragt er nicht
mehr nach der Haltbarkeit),
`INVENTAR_TASTE`, `WARTEN_MAX` (wie lange er auf einen Biss wartet), `NACH_FANG_PAUSE` oder
`SICHERHEIT` (größer = vorsichtiger, lässt eher einen Durchgang aus).
