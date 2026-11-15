# Sky Reader

**Sky Reader** ist eine macOS-App (ab macOS 15, Apple Silicon), die Astroaufnahmen analysiert und beschriftet – **vollständig offline**.

Ziehe ein JPEG- oder TIFF-Bild in das Fenster: Sky Reader bestimmt anhand der Sterne, welcher Himmelsausschnitt zu sehen ist (Plate Solving), markiert alle bekannten **Nebel, Galaxien, Sternhaufen, Dunkelnebel und Kometen** und liefert zu jedem Objekt Entfernung, wissenschaftliche Daten, neueste Erkenntnisse und eine verständliche Beschreibung. Mondaufnahmen werden erkannt; die **Krater** werden nummeriert und beschrieben.

## Installation

1. Unter [Releases](https://github.com/ziege1988/Sky-Reader/releases/latest) die Datei `SkyReader-<Version>.dmg` laden.
2. „Sky Reader“ in den Ordner *Programme* ziehen.
3. Beim **ersten Start**: Rechtsklick auf die App → **Öffnen** → **Öffnen** bestätigen. Die App ist nicht von Apple notarisiert (kein kostenpflichtiger Developer-Account); dieser Schritt ist nur einmal nötig.
   Falls macOS den Start trotzdem blockiert: *Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“*.

Updates sucht Sky Reader automatisch (abschaltbar in den Einstellungen). Bei einem Update schließt sich die App, die neue Version wird installiert und startet von selbst.

## Bedienung

| Bereich | Funktion |
|---|---|
| Linke 2/3 | Drag & Drop-Fläche (JPEG/TIFF); nach der Analyse Bild mit Markierungen. Zoom per Trackpad, Doppelklick setzt zurück, Klick auf eine Markierung zeigt das Objekt rechts. |
| Rechtes 1/3 | Ergebnisse: Bildfeld, Objekte mit Fakten, Laienbeschreibung, Wissenschaft, neueste Erkenntnisse |
| Analyse-Popup | Live-Protokoll der Rechenschritte. **Fertig** übernimmt das Ergebnis, **Abbrechen** stoppt, **Report** speichert ein TXT-Protokoll (für Fehlermeldungen). |
| Exportieren | JPEG/TIFF mit Beschreibungsspalte rechts; Optionen *Markierungen/Bezeichnungen*, *Beschreibung*, *Ausführliche Beschreibung*. **Rechtsklick** auf eine Markierung in der Vorschau blendet sie aus. |
| ⚙︎ (unten rechts) | Einstellungen: Krater (nur die größten / alle), Objektdichte, Objektarten, Analyseauflösung, Darstellung, Updates |

## Wie die Analyse funktioniert

- **Plate Solving**: Sterne werden im Bild gefunden, zu Vierergruppen („Quads“) kombiniert und deren geometrischer Fingerabdruck mit einem aus dem Sternkatalog (Tycho-2/HYG) berechneten Index verglichen. Die beste Hypothese wird mit allen Sternen verifiziert und zu einer Lösung mit Verzeichnungskorrektur verfeinert. Funktioniert ohne EXIF-Daten für Bildfelder ab ca. 1–2° (Teleobjektiv/kleine Refraktoren); sehr kleine Felder (lange Brennweiten) werden noch nicht unterstützt.
- **Objekte**: Abgleich mit OpenNGC (NGC/IC/Messier), sowie – sofern im Katalog-Build verfügbar – LDN, Barnard, Sharpless, LBN, vdB, Cederblad.
- **Kometen**: Morphologische Erkennung (Koma + Schweif) und Abgleich mit den Bahnelementen des Minor Planet Center. Ohne Aufnahmedatum werden die Bahnen nach einem passenden Durchgang durchsucht (das Datum wird dabei rekonstruiert).
- **Mond**: Erkennung der Mondfläche, Kreisanpassung an den Mondrand (→ Maßstab in km), Kratererkennung über das Licht-Schatten-Muster. Krater werden nach Größe nummeriert. Offline erfolgt **keine** Zuordnung zu IAU-Kraternamen.

## Entwicklung

```bash
swift test                         # Engine-Tests (läuft auch unter Linux)
swift run -c release skyreader-cli bild.pgm --json out.json   # Engine per Kommandozeile
Scripts/build_app.sh               # baut dist/Sky Reader.app, ZIP und DMG (macOS)
python3 Tools/build_catalogs.py    # erzeugt Resources/Catalogs neu (lädt Kataloge aus dem Netz)
```

- `Sources/SkyReaderCore` – plattformunabhängige Analyse-Engine
- `Sources/SkyReader` – macOS-App (SwiftUI/AppKit)
- `Resources/Catalogs` – mitgelieferte Kataloge (vom Workflow *Kataloge erzeugen* gepflegt, wöchentlich aktualisierte Kometenbahnen)
- **Release**: Version in `VERSION` erhöhen und `CHANGELOG.md` ergänzen → jeder Push auf den Standard-Branch baut und veröffentlicht `v<VERSION>`.

## Datenquellen & Lizenzen

OpenNGC (Mattia Verga, CC BY-SA 4.0) · HYG-Datenbank v4.1 (CC BY-SA 4.0) · Tycho-2 (Høg et al. 2000) · LDN, Barnard, Sharpless, LBN, vdB, Cederblad über CDS/VizieR · Minor Planet Center · IAU/USGS Gazetteer of Planetary Nomenclature
