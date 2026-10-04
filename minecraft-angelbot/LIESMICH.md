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
2. In Minecraft: **Fenster groß machen** (maximieren), damit die ganze Leiste zu
   sehen ist. Angel in die Hand nehmen (noch **nicht** auswerfen) und aufs Wasser schauen.
3. **F8 drücken** – los geht's.

| Taste | Was passiert |
|-------|--------------|
| F8    | Start / Pause |
| F10   | Diagnose-Bild speichern (was der Bot gerade sieht) |
| F12   | Bot beenden |

Im schwarzen Fenster steht immer, was der Bot gerade macht.

## Vorausschauen und Dazulernen

Je näher der Fang, desto schneller springt der weiße Rahmen – und ein Klick
daneben kostet einen Haken. Der Bot misst darum bei jedem Schritt, wie schnell
der Rahmen gerade ist, und bei jedem Treffer, wie lange sein Klick bis zum Server
braucht (so lange dauert es, bis das rote Feld springt). Käme ein Klick „auf Sicht“
zu spät an, klickt er vorher – wenn nötig ein oder zwei Felder früher –, sodass
der Klick in der Mitte der Zeit ankommt, in der der Rahmen auf Rot steht.
Wäre es sicher zu spät, lässt er den Durchgang lieber aus, statt einen Haken zu
riskieren. Nach einem Fehlklick korrigiert er sich (zu früh → später klicken,
zu spät → früher klicken).

Was er gelernt hat, merkt er sich in `angelbot_gelernt.json` (neben
`Angel-Bot.bat`). Löschst du die Datei, fängt er wieder bei 150 ms an.

## Wenn etwas nicht klappt

- **„Die Leiste ist am Fensterrand abgeschnitten“**: Das Minecraft-Fenster ist zu
  schmal. Fenster maximieren oder in Minecraft unter *Optionen → Grafikeinstellungen →
  GUI-Größe* einen kleineren Wert nehmen.
- **Der Bot merkt den Biss nicht oder klickt nicht**: Während das Minispiel läuft
  **F10** drücken. Neben `Angel-Bot.bat` liegt dann ein Bild `diagnose_….png` – schick es Claude,
  dann kann der Bot angepasst werden.
- **Kein Biss**: Nach 60 Sekunden ohne Biss holt der Bot die Angel ein und wirft neu aus.

## Einstellungen

`Angel-Bot.bat` mit dem Editor öffnen: Unter „Einstellungen“ im Python-Teil stehen
ein paar Zahlen, die du ändern kannst, z. B.
`WARTEN_MAX` (wie lange er auf einen Biss wartet), `NACH_FANG_PAUSE` oder
`SICHERHEIT` (größer = vorsichtiger, lässt eher einen Durchgang aus).
