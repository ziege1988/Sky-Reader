# Changelog

## 1.9.1
- Aufnahmezeit laut Schattenwurf wird nur noch angezeigt, wenn sie auf ±3 Stunden oder genauer bestimmt ist (bei Bildern ohne nennenswerte Licht-Schatten-Grenze war die Angabe zu ungenau).

## 1.9.0
- **Mondrelief (LOLA-Höhenmodell der NASA-Sonde LRO, ca. 950 m Auflösung)**: Sky Reader berechnet, wie der Mond bei der ermittelten Lage und dem Sonnenstand zur Aufnahmezeit aussehen muss – mit Hangbeleuchtung und Schlagschatten – und vergleicht das mit dem Foto.
  - **Aufnahmezeit über den Schattenwurf**: Ist die Licht-Schatten-Grenze im Bild, wird die Uhrzeit auf etwa ±1–2 Stunden bestimmt (vorher ±7 h). Der Vorschlag im Datums-Popup nutzt das bereits; weicht eine eingegebene Uhrzeit deutlich ab, gibt es einen Hinweis.
  - **Qualitätsanzeige** „Übereinstimmung mit dem Mondrelief“ in der Zusammenfassung.
  - **Vergleichsansicht** (Knopf „Mit dem Mondrelief vergleichen“): Foto und berechnete Ansicht überblenden, blinken lassen oder nebeneinander zeigen.
- Das Höhenmodell (88 MB, Vorderseite ±120° Länge) wird beim Build eingebunden; die App wird dadurch entsprechend größer.

## 1.8.1
- Die Feinjustierung an den Kraterwällen gilt jetzt auch für Mondfotos ohne sichtbaren Mondrand (mit Aufnahmedatum); dort werden zusätzlich Maßstab und Bildlage nachgeführt.

## 1.8.0
- **Genauere Kraterbeschriftung bei Mondbildern mit Rand**: Nach der Zuordnung wird die Mondlage direkt am Foto nachjustiert. Für alle Katalogkrater ab 15 km wird geprüft, ob an der vorhergesagten Stelle ein Kraterwall liegt; Mondradius und Drehung werden so eingestellt, dass möglichst viele Wälle übereinstimmen. Besonders weit vom sichtbaren Mondrand entfernte Krater (z. B. Cleomedes, Geminus, Endymion, Hercules) sitzen jetzt deutlich genauer.

## 1.7.0
- **Robbins Lunar Crater Database (2018)** eingebunden: 212.149 vermessene Mondkrater ab 3 km (2,5 MB).
  - Benannte Krater zeigen zusätzlich den genau vermessenen Durchmesser.
  - Bei „Alle Krater“ werden erkannte Krater ohne IAU-Namen mit dem Katalog abgeglichen: Bestätigte Krater erhalten exakten Durchmesser und selenografische Lage, unbestätigte werden als mögliche Fehlerkennung gekennzeichnet (nicht gelöscht).
- Katalog-Build: selbst bereitgestellte Quelldateien werden aus dem Vorab-Release „katalog-quellen“ geladen.

## 1.6.0
- **Geologisches Alter der Krater** aus der USGS-Karte „Unified Geologic Map of the Moon“ (2020, gemeinfrei): Kopernikanisch, Eratosthenisch, Imbrisch, Nektarisch oder Prä-Nektarisch – mit Altersangabe und verständlicher Erklärung in der Beschreibung.
- **Beobachtungsort** (Einstellungen → Analyse): Die Datumsberechnung berücksichtigt nur Zeiten, zu denen der Mond am Ort über dem Horizont stand; die Analyse zeigt die Mondhöhe und warnt bei unmöglichen Zeitpunkten. Der Ortsname wird im Tagebuch vorbelegt.
- **Mondanalyse etwa dreimal schneller** (auf 4 Kernen gemessen, auf Apple-Silicon-Macs mit mehr Kernen entsprechend mehr): Der Kraterabgleich nutzt alle Prozessorkerne. Die Auswertung erfolgt in derselben Reihenfolge wie bisher – die Kraternamen sind unverändert.
- **Reproduzierbare Ergebnisse**: Der Mondrand wurde bisher mit Zufallsstichproben vermessen, wodurch dasselbe Bild leicht unterschiedliche Ergebnisse liefern konnte. Jetzt feste Startwerte und Median aus sieben Durchläufen; gelingt die Zuordnung nicht eindeutig, werden weitere Randkreise geprüft.
- **Fortschrittsbalken mit Restzeit**: lernt aus den letzten Analysen, wie lange Mond- bzw. Himmelsaufnahmen dauern; die Wartezeit im Datums-Popup zählt nicht mit.

## 1.5.0
- **Datum aus dem Bild berechnet**: Ist der Mondrand im Bild, bestimmt Sky Reader zuerst die Lage des Mondes (Libration) und die Lage der Licht-Schatten-Grenze (Colongitude) und sucht daraus den passenden Aufnahmezeitpunkt. Dieser ist im Datums-Popup vorausgewählt und kann korrigiert werden; ähnlich gut passende Alternativen sind anklickbar. Ein Tag im Dateinamen ohne Jahr (z. B. „13.05“) wird berücksichtigt – das Jahr wird dann berechnet.
- **Robbins Lunar Crater Database (2018)** zusätzlich zur IAU-Nomenklatur (sobald der Katalog-Build sie laden kann): genaue Durchmesser benannter Krater, Lage und Größe unbenannter Krater; erkannte Krater ohne Gegenstück im Katalog werden als Fehlerkennung verworfen.

## 1.4.0
- **Beobachtungstagebuch**: Aufnahmen mit Analyse, Ort, Ausrüstung, Bedingungen und Notizen ablegen; übersichtliche Kachelansicht mit Suche und Filter (Himmel/Mond/Kometen). Überschrift automatisch: größter Nebel im Bild bzw. „Mond – größter Krater“.
- **Mond-Datum**: Bei Mondaufnahmen fragt Sky Reader nach Datum/Uhrzeit (Vorschlag aus dem Dateinamen, z. B. „…_13.05.jpg“). Daraus werden Libration, Sonnenstand, Phase und Beleuchtung berechnet.
- **Kraternamen ohne Mondrand**: Mit bekanntem Datum werden Krater auch in Bildern ohne sichtbaren Mondrand benannt (Abgleich über Kraterpaare und Sonnenstand).
- **Offizielle IAU-Nomenklatur vollständig**: 8.679 Krater inkl. 7.064 Nebenkrater („Atlas A“) sowie Maria, Seen, Buchten, Gebirge und Täler als Bezeichnungen.
- **Ringwall-Detektor**: findet Krater über ihre Wälle – ergänzt die Schatten-Erkennung bei hohem Sonnenstand.
- Krater auf der Nachtseite werden bei bekanntem Datum ausgeblendet.

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
