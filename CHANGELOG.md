# Changelog

## 1.3.1
- Mondbilder, die (fast) vollständig von der Mondoberfläche ausgefüllt sind, werden zuverlässig als Mond erkannt (vorher teilweise als Himmelsaufnahme behandelt)
- Scheitert bei einer vermeintlichen Himmelsaufnahme das Plate Solving und ähnelt das Bild einer Mondaufnahme, wird automatisch die Mondanalyse verwendet

## 1.3.0
- Mond: Krater werden mit ihren **offiziellen IAU-Namen** beschriftet. Sky Reader bestimmt dazu die Lage des Mondes (Drehung, Spiegelung, Libration) durch Abgleich der erkannten Krater mit dem IAU-Kraterkatalog – wie Plate Solving, nur für den Mond.
- Es werden alle benannten Krater im Bildausschnitt markiert, auch solche, die die Erkennung übersehen hat; Krater auf der Nachtseite werden ausgelassen
- Kraterdetails: offizieller Durchmesser, selenografische Lage, Namensgeber; Bildinfo mit Libration und Nordrichtung
- „Nur die größten“ zeigt bis zu 25 benannte Krater, „Alle“ zusätzlich kleinere und nummerierte Krater ohne Eigennamen
- Mondrand-Vermessung genauer und auch bei weichem Rand bzw. Streulicht zuverlässig
- Ohne sichtbaren Mondrand oder ohne eindeutige Zuordnung werden Krater weiterhin nummeriert

## 1.2.0
- Mond: Krater werden mit einem kleinen blauen Fadenkreuz in der Mitte und ihrer Nummer markiert (keine Kreise)
- Export mit Live-Vorschau: großer Dialog, zoom- und verschiebbar; jede Änderung ist sofort im Bild und in der Beschreibung sichtbar
- Entfernte Markierungen erscheinen in der Vorschau rot gestrichelt, ihre Bezeichnung und ihr Beschreibungsabsatz durchgestrichen („wird nicht exportiert“); abschaltbar für die exakte Endansicht
- Hinweis mit „Rückgängig“ nach jedem Entfernen/Zurückholen; entfernte Objekte in der Liste durchgestrichen

## 1.1.0
- Mond: deutlich genauere Kratererkennung. Die Sonnenrichtung wird aus Licht/Schatten-Paaren und dem beleuchteten Mondrand bestimmt; Krater werden als Paar aus Schatten und beleuchteter Innenwand erkannt.
- Randnahe Krater werden als Ellipsen vermessen (Durchmesser entlang der langen Achse, Angabe des Blickwinkels)
- Große, flache Krater werden über ihre Schattensichel erkannt
- Dunkle Maria gehören jetzt zur Mondfläche (vorher wurden dort keine Krater gesucht)

## 1.0.0
- Erste Version von Sky Reader für macOS 15+ (Apple Silicon)
- Offline-Plate-Solving gegen mitgelieferten Sternkatalog (blind, ohne Vorwissen über das Bildfeld)
- Erkennung von Nebeln, Galaxien, Sternhaufen und Dunkelnebeln (OpenNGC u. a.) mit Kreisen und Beschriftung
- Kometen: Erkennung im Bild und Identifikation über MPC-Bahnelemente – auch ohne Aufnahmedatum
- Mond: Erkennung der Mondoberfläche, Vermessung des Mondrands, nummerierte Krater mit Details
- Analyse-Popup mit Live-Protokoll, Fertig / Abbrechen / Report (TXT)
- Export als JPEG oder TIFF mit Beschreibungsspalte; Markierungen per Rechtsklick abwählbar
- Automatische Updates über GitHub-Releases
- Kataloge: Tycho-2 (1,49 Mio. Sterne bis 11,5 mag), 15.964 Deep-Sky-Objekte, 973 Kometenbahnen, 80 ausführlich beschriebene Objekte
