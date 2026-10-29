# Online-Bestenliste

Diese Dateien (`<spiel>.json`) werden automatisch von der GitHub-Action `Bestenliste` geschrieben
(`.github/workflows/scores.yml`, Skript `.github/scripts/process-scores.js`). Nicht von Hand ändern.

Die Spiele-App legt für jeden neuen persönlichen Bestwert ein Issue mit dem Titel `score: <spiel>/<liste>` an.
Die Action prüft es, trägt es ein und schließt das Issue wieder. Die Website liefert die fertigen Dateien aus:
`https://lukasvanderdonk.github.io/super-shoot/scores/<spiel>.json`
