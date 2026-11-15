#!/usr/bin/env python3
"""Kuratierte deutsche Objekttexte für Sky Reader → Resources/Catalogs/objects_de.json
Felder: ids (Katalognummern), name, distance, size, age, scientific, latest, layman.
Zahlen: gerundete Literaturwerte (Gaia/HST/VLBI, wo verfügbar); Unsicherheiten sind im Text vermerkt."""
import json, os, sys

E = []
def o(ids, name, distance=None, size=None, age=None, scientific="", latest="", layman="", extra=None):
    E.append({k: v for k, v in dict(ids=ids, name=name, distance=distance, size=size, age=age, extra=extra,
                                    scientific=scientific, latest=latest, layman=layman).items() if v is not None})

# ---------------------------------------------------------------- Orion
o(["NGC 1976", "M 42"], "Orionnebel", "ca. 1.350 Lichtjahre", "ca. 25 Lichtjahre", "Sterne meist < 2 Mio. Jahre",
  "Die nächstgelegene große Sternentstehungsregion. Die vier heißen Trapez-Sterne (θ¹ Orionis) ionisieren das Gas mit ihrer UV-Strahlung; im Nebel sind Hunderte junger Sterne und zahlreiche protoplanetare Scheiben („Proplyds“) eingebettet. Die Entfernung ist durch VLBA-Parallaxen auf wenige Prozent genau bestimmt (≈ 414 Parsec).",
  "Das James-Webb-Weltraumteleskop entdeckte 2023 in einer protoplanetaren Scheibe (d203-506) erstmals das Methyl-Kation CH₃⁺, ein Schlüsselmolekül der Kohlenstoffchemie. Die zugleich gemeldeten frei fliegenden Paare jupitergroßer Objekte („JuMBOs“) werden inzwischen kritisch gesehen – Nachanalysen deuten bei vielen auf Hintergrundquellen hin.",
  "Hier werden gerade Sterne geboren – wie in einer kosmischen Kinderstube. Das Leuchten stammt von Wasserstoffgas, das von ein paar sehr heißen, jungen Sternen im Zentrum zum Glühen gebracht wird. Mit bloßem Auge ist der Nebel als „Schwertgehänge“ unter den Gürtelsternen des Orion zu erahnen.")
o(["NGC 1982", "M 43"], "De-Mairans-Nebel", "ca. 1.350 Lichtjahre", "ca. 6 Lichtjahre", None,
  "Ein vom Orionnebel durch eine Staubbahn getrennter Teil derselben H-II-Region, ionisiert vom jungen Stern NU Orionis (Spektraltyp B0.5).",
  "Infrarotaufnahmen zeigen, dass M 43 und M 42 physikalisch zur selben Molekülwolke (OMC-1) gehören; die Trennung ist nur eine vorgelagerte Staubwolke.",
  "Ein kleiner „Ableger“ des Orionnebels – eigentlich gehört er dazu, wird aber von einem dunklen Staubband optisch abgetrennt.")
o(["NGC 1977", "NGC 1973", "NGC 1975"], "Running-Man-Nebel", "ca. 1.500 Lichtjahre", "ca. 15 Lichtjahre", None,
  "Ein Komplex aus Reflexions- und Emissionsnebeln nördlich des Orionnebels. Das bläuliche Licht ist an Staub gestreutes Sternlicht junger B-Sterne (u. a. 42 Orionis).",
  "Am Rand von NGC 1977 wurden zahlreiche Proplyds entdeckt – Sternscheiben, die von der UV-Strahlung heißer Sterne langsam „verdampft“ werden.",
  "Die dunklen Staubstrukturen formen die Silhouette einer laufenden Figur – daher der Name „Running Man“.")
o(["NGC 2024"], "Flammennebel", "ca. 1.350 Lichtjahre", "ca. 12 Lichtjahre", "Haufen ca. 0,2–1,5 Mio. Jahre",
  "Eine helle H-II-Region in der Molekülwolke Orion B. Lange galt der Gürtelstern Alnitak als Energiequelle; heute weiß man, dass ein im Staub verborgener junger O-Stern (IRS 2b) das Gas ionisiert. Im Inneren steckt ein junger Haufen mit mehreren hundert Sternen.",
  "Röntgen- und Infrarotdaten (Chandra, 2MASS) zeigten, dass die Sterne im Zentrum jünger sind als am Rand – die Sternentstehung schreitet hier von außen nach innen fort.",
  "Der Nebel sieht aus wie ein Lagerfeuer, das von dunklen Rauchschwaden durchzogen ist. Hinter dem Staub verbirgt sich ein Nest frisch entstandener Sterne.")
o(["IC 434"], "Emissionsnebel am Pferdekopf", "ca. 1.400 Lichtjahre", "ca. 30 Lichtjahre lang", None,
  "Ein langgestreckter Emissionsnebel, ionisiert vom Mehrfachstern σ Orionis. Vor ihm zeichnet sich der Dunkelnebel Barnard 33 – der Pferdekopf – als Silhouette ab.",
  "Euclid (2023) und das James-Webb-Teleskop (2024) bildeten die Grenzschicht zwischen ionisiertem Gas und Molekülwolke mit bisher unerreichter Schärfe ab.",
  "Ein roter Vorhang aus leuchtendem Wasserstoff – der Hintergrund, vor dem sich der berühmte Pferdekopf abhebt.")
o(["B 33"], "Pferdekopfnebel", "ca. 1.400 Lichtjahre", "ca. 3,5 Lichtjahre hoch", None,
  "Eine dichte Staubsäule aus der Molekülwolke Orion B, die sich vor den leuchtenden Emissionsnebel IC 434 schiebt. Die UV-Strahlung von σ Orionis trägt den Kopf langsam ab; in etwa 5 Mio. Jahren wird er verschwunden sein.",
  "Das James-Webb-Teleskop zeigte 2024 die „Mähne“ des Pferdekopfs im Detail: eine Photodissoziationsregion, in der UV-Licht Moleküle aufbricht und Staub erhitzt.",
  "Eine der berühmtesten Formen am Himmel: eine dunkle Staubwolke in Gestalt eines Pferdekopfs, die das rote Leuchten dahinter verdeckt.")
o(["NGC 2023"], "Reflexionsnebel NGC 2023", "ca. 1.350 Lichtjahre", "ca. 4 Lichtjahre", None,
  "Ein heller Reflexionsnebel um den jungen B-Stern HD 37903 nahe dem Pferdekopf. Er zeigt fluoreszierenden molekularen Wasserstoff.",
  "NGC 2023 ist eines der Standardobjekte zur Erforschung von „Extended Red Emission“ und interstellaren PAH-Molekülen.",
  "Ein bläulich schimmernder Staubschleier, beleuchtet von einem einzelnen jungen Stern.")
o(["NGC 2068", "M 78"], "M 78", "ca. 1.350 Lichtjahre", "ca. 4 Lichtjahre", None,
  "Der hellste diffuse Reflexionsnebel am Himmel, beleuchtet von zwei B-Sternen. In seiner Umgebung finden sich rund 45 junge veränderliche T-Tauri-Sterne und Herbig-Haro-Objekte.",
  "2004 tauchte nahe M 78 der veränderliche „McNeil-Nebel“ auf – ausgelöst durch einen Helligkeitsausbruch eines neu entstehenden Sterns (V1647 Ori).",
  "Hier wirft Staub das Licht junger Sterne zurück – wie ein Scheinwerfer im Nebel. Daneben liegen dunkle Wolken, in denen noch weitere Sterne entstehen.")
o(["NGC 2071"], "Reflexionsnebel NGC 2071", "ca. 1.350 Lichtjahre", None, None,
  "Ein Reflexionsnebel nördlich von M 78 in der Molekülwolke Orion B mit einem aktiven Sternentstehungsgebiet und kräftigen molekularen Ausflüssen.",
  "", "Ein kleiner bläulicher Nebel, in dessen Inneren gerade neue Sterne heranwachsen.")
o(["Sh2-276"], "Barnards Loop", "ca. 1.400 Lichtjahre (unsicher)", "Radius ca. 150 Lichtjahre", "ca. 2 Mio. Jahre",
  "Ein riesiger Bogen ionisierten Wasserstoffs um das Orion-Sternbild, Teil der Orion-Eridanus-Superblase. Er entstand vermutlich durch Supernova-Explosionen und Sternwinde massereicher Sterne der Orion-OB1-Assoziation.",
  "Neuere 3D-Staubkarten auf Basis von Gaia-Daten zeigen, dass die Schale räumlich ausgedehnt und nicht exakt kugelförmig ist; die Entfernungsangaben schwanken daher je nach Abschnitt.",
  "Ein gewaltiger roter Halbkreis, der den halben Orion umspannt – die Druckwelle explodierter Sterne, die Gas zum Leuchten bringt. Mit bloßem Auge ist er nicht zu sehen, auf Langzeitbelichtungen aber eindrucksvoll.")
o(["LDN 1622"], "Boogeyman-Nebel", "ca. 500–1.300 Lichtjahre (unsicher)", "ca. 10 Lichtjahre", None,
  "Eine dichte Dunkelwolke am Rand von Barnards Loop. Sie liegt möglicherweise deutlich näher als der Orion-Komplex; in ihr wurden junge Sterne und Ausflüsse gefunden.",
  "Die Entfernung ist umstritten; Gaia-basierte Studien legen eine Lage vor der Orion-B-Wolke nahe.",
  "Eine dunkle, fast gespenstische Wolke – daher der Spitzname „Boogeyman“. Sie verschluckt das Licht der Sterne dahinter.")
o(["NGC 1981"], "NGC 1981", "ca. 1.300 Lichtjahre", None, None,
  "Ein lockerer, junger offener Sternhaufen am Nordende des Schwertgehänges des Orion.",
  "", "Eine kleine Gruppe heller junger Sterne direkt nördlich des Orionnebels.")
o(["NGC 1980"], "NGC 1980", "ca. 1.300 Lichtjahre", None, "ca. 4–5 Mio. Jahre",
  "Ein junger Sternhaufen um ι Orionis am Südende des Schwertgehänges; Gaia-Daten zeigen, dass er eine eigene, etwas ältere Sternpopulation vor dem Orionnebel bildet.",
  "", "Die hellen Sterne unterhalb des Orionnebels sind eine eigene junge Sternfamilie.")

# ---------------------------------------------------------------- Taurus / Perseus
o(["Mel 22", "M 45"], "Plejaden (Siebengestirn)", "ca. 444 Lichtjahre", "Kern ca. 15 Lichtjahre", "ca. 100–125 Mio. Jahre",
  "Der bekannteste offene Sternhaufen mit über 1.000 Mitgliedern, dominiert von heißen blauen B-Sternen. Der bläuliche Reflexionsnebel gehört nicht zur Entstehungswolke des Haufens: Die Plejaden durchqueren zufällig eine Staubwolke. Der jahrzehntelange Streit um die Entfernung (Hipparcos: 392 Lj) wurde durch VLBI und Gaia zugunsten von ≈ 444 Lj entschieden.",
  "Eine Studie von 2025 (Gaia + TESS-Rotationsdaten) zeigte, dass die Plejaden nur der Kern eines rund 20-mal größeren, über den Himmel verstreuten Sternverbands sind – des „Greater Pleiades Complex“.",
  "Das „Siebengestirn“: Mit bloßem Auge sieht man sechs bis sieben Sterne, tatsächlich sind es über tausend. Der blaue Schimmer ist Staub, durch den die Sterne gerade hindurchziehen und der ihr Licht reflektiert – wie Scheinwerfer im Nebel.")
o(["NGC 1435"], "Merope-Nebel", "ca. 440 Lichtjahre", None, None,
  "Ein Reflexionsnebel um den Plejadenstern Merope (23 Tau). Die Streifenstruktur entsteht, weil Strahlungsdruck den Staub beim Vorbeizug des Haufens sortiert.",
  "Hubble-Aufnahmen zeigen, dass der Staub durch die Strahlung Meropes regelrecht „weggefegt“ wird.",
  "Ein zarter Schleier um einen der hellsten Plejadensterne – Staub, der vom Sternlicht angestrahlt wird.")
o(["IC 349"], "Barnards Merope-Nebel", "ca. 440 Lichtjahre", "ca. 0,06 Lichtjahre vom Stern Merope", None,
  "Ein winziger, sehr heller Reflexionsnebel nur etwa 3.500 AE von Merope entfernt. Hier wird eine Staubwolke vom Strahlungsdruck des Sterns zerlegt.",
  "", "Ein kleiner Lichtfleck dicht neben Merope – eine Staubwolke, die gerade vom Stern zerrissen wird.")
o(["NGC 1499"], "Kaliforniennebel", "ca. 1.000 Lichtjahre", "ca. 100 Lichtjahre lang", None,
  "Eine ausgedehnte H-II-Region, ionisiert vom extrem heißen Stern ξ Persei (Menkib, Spektraltyp O7.5). Ihre Form erinnert an den US-Bundesstaat Kalifornien.",
  "ξ Persei ist ein „Runaway“-Stern, der mit hoher Geschwindigkeit aus seiner Geburtsgruppe flieht.",
  "Ein riesiger roter Nebel, der wie die Landkarte Kaliforniens aussieht. Er ist so lichtschwach, dass man ihn fast nur auf Fotos sieht.")
o(["NGC 869", "NGC 884"], "Doppelsternhaufen h & χ Persei", "ca. 7.500 Lichtjahre", "je ca. 70 Lichtjahre", "ca. 14 Mio. Jahre",
  "Zwei benachbarte, sehr junge offene Sternhaufen mit Hunderten heller blauer Riesen und einigen roten Überriesen. Beide gehören zur Assoziation Perseus OB1 und sind nahezu gleich alt.",
  "Gaia-Messungen bestätigen, dass beide Haufen dieselbe Entfernung haben und von einem ausgedehnten Halo gemeinsam entstandener Sterne umgeben sind.",
  "Zwei glitzernde Sternhaufen direkt nebeneinander – schon mit dem Fernglas ein Juwel. Die wenigen orangen Sterne darin sind gealterte Riesensterne.")
o(["IC 1805"], "Herznebel", "ca. 7.500 Lichtjahre", "ca. 200 Lichtjahre", None,
  "Eine große H-II-Region im Perseusarm, ionisiert vom Sternhaufen Melotte 15 mit mehreren O-Sternen von bis zu 50 Sonnenmassen.",
  "", "Ein rot leuchtender Nebel in Herzform, in dessen Zentrum einige der massereichsten Sterne unserer Galaxie stehen.")
o(["IC 1848"], "Seelennebel", "ca. 7.500 Lichtjahre", "ca. 100 Lichtjahre", None,
  "Eine H-II-Region neben dem Herznebel mit den jungen Haufen IC 1848 und mehreren Sternentstehungsgebieten.",
  "", "Der Nachbar des Herznebels – zusammen nennt man sie auch „Herz und Seele“.")

# ---------------------------------------------------------------- Nordpol / Cepheus / Cygnus
o(["NGC 188"], "NGC 188", "ca. 6.000 Lichtjahre", "ca. 30 Lichtjahre", "ca. 6–7 Mrd. Jahre",
  "Einer der ältesten bekannten offenen Sternhaufen der Milchstraße, nur gut 4° vom Himmelsnordpol entfernt. Seine hohe Lage über der galaktischen Scheibe hat ihn vor der Zerstörung durch Gaswolken bewahrt.",
  "NGC 188 dient als Referenzhaufen für Sternentwicklungsmodelle; dort wurden zahlreiche „Blue Stragglers“ gefunden – Sterne, die durch Massenaustausch in Doppelsystemen jünger wirken.",
  "Ein unscheinbarer Sternhaufen nahe dem Polarstern – aber uralt: Seine Sterne sind älter als unsere Sonne.")
o(["NGC 7000"], "Nordamerikanebel", "ca. 2.600 Lichtjahre", "ca. 90 Lichtjahre", None,
  "Eine große H-II-Region im Schwan, die zusammen mit dem Pelikannebel (IC 5070) eine Wolke bildet; getrennt werden beide nur durch die vorgelagerte Dunkelwolke LDN 935.",
  "Mit Gaia-Daten wurde 2020 der ionisierende Stern identifiziert – ein stark gerötetes O-Stern-System, getauft „Bajamar-Stern“.",
  "Ein roter Nebel in der Form Nordamerikas – samt „Golf von Mexiko“, der in Wahrheit eine dunkle Staubwolke ist.")
o(["IC 5070", "IC 5067"], "Pelikannebel", "ca. 2.600 Lichtjahre", "ca. 30 Lichtjahre", None,
  "Teil derselben Gaswolke wie der Nordamerikanebel. Ionisationsfronten fressen sich hier in die Molekülwolke; dabei entstehen Säulen und Herbig-Haro-Jets.",
  "", "Der „Pelikan“ ist der Nachbar des Nordamerikanebels – beide sind Teile derselben riesigen Gaswolke.")
o(["NGC 6960", "NGC 6992", "NGC 6995", "NGC 6979"], "Cirrusnebel (Schleiernebel)", "ca. 2.400 Lichtjahre", "ca. 110 Lichtjahre", "Supernova vor ca. 10.000–20.000 Jahren",
  "Die Überreste einer Supernova im Schwan. Die Stoßwelle läuft mit Hunderten km/s in das umgebende Gas und erhitzt es; die Filamente leuchten in Wasserstoff (rot) und Sauerstoff (blaugrün).",
  "Gaia-Parallaxen von Sternen in und hinter dem Nebel ergaben 2018 eine Entfernung von ≈ 2.400 Lj – deutlich näher als früher angenommen.",
  "Feine, leuchtende Fäden – die Trümmer eines Sterns, der vor vielen Jahrtausenden explodiert ist.")
o(["NGC 6888"], "Sichelnebel", "ca. 5.000 Lichtjahre", "ca. 25 Lichtjahre", "ca. 200.000 Jahre",
  "Eine vom Wolf-Rayet-Stern WR 136 abgestoßene Gasblase. Sein schneller Sternwind prallt auf früher ausgestoßenes Material und bringt es zum Leuchten.",
  "", "Eine Gasblase, die ein sterbender Riesenstern um sich herum aufgeblasen hat.")
o(["IC 1396"], "Elefantenrüsselnebel (IC 1396)", "ca. 3.000 Lichtjahre", "ca. 100 Lichtjahre", None,
  "Eine große H-II-Region im Kepheus, ionisiert vom Mehrfachstern HD 206267. Der „Elefantenrüssel“ (vdB 142) ist eine dichte Staubsäule, in der durch Kompression neue Sterne entstehen.",
  "", "Ein riesiger roter Nebel mit einer dunklen, gewundenen Staubsäule – sie sieht aus wie der Rüssel eines Elefanten.")
o(["NGC 7023"], "Irisnebel", "ca. 1.300 Lichtjahre", "ca. 6 Lichtjahre", None,
  "Ein heller Reflexionsnebel um den jungen Herbig-Ae/Be-Stern HD 200775. Er ist ein Standardobjekt zur Untersuchung von PAH-Molekülen und Fullerenen im All.",
  "", "Ein blau leuchtender Staubnebel, der wie eine Blüte um einen jungen Stern liegt.")
o(["NGC 7635"], "Blasennebel", "ca. 7.000–11.000 Lichtjahre", "ca. 7 Lichtjahre", None,
  "Eine vom Sternwind des heißen O-Sterns BD+60 2522 aufgeblasene Gasblase in der Kassiopeia.",
  "Hubble zeigte 2016 zum 26. Geburtstag des Teleskops die gesamte Blase in hoher Auflösung.",
  "Eine fast perfekte Seifenblase im All – aufgeblasen vom Wind eines einzigen sehr heißen Sterns.")
o(["NGC 281"], "Pacman-Nebel", "ca. 9.500 Lichtjahre", "ca. 48 Lichtjahre", None,
  "Eine H-II-Region in der Kassiopeia mit dem jungen Haufen IC 1590 und zahlreichen Bok-Globulen.",
  "", "Ein roter Nebel, dessen Form an die Videospielfigur Pac-Man erinnert.")

# ---------------------------------------------------------------- Winter
o(["NGC 2237", "NGC 2244", "NGC 2238", "NGC 2239", "NGC 2246"], "Rosettennebel", "ca. 5.200 Lichtjahre", "ca. 130 Lichtjahre", "Haufen ca. 4 Mio. Jahre",
  "Eine große, rosettenförmige H-II-Region im Einhorn. Der zentrale Haufen NGC 2244 hat mit seinen Sternwinden einen Hohlraum in die Wolke geblasen.",
  "", "Eine riesige rote „Rose“ am Himmel. In ihrer Mitte hat ein junger Sternhaufen das Gas weggeblasen.")
o(["NGC 2264"], "Weihnachtsbaumhaufen & Konusnebel", "ca. 2.400 Lichtjahre", "ca. 30 Lichtjahre", "ca. 3 Mio. Jahre",
  "Ein junger Sternhaufen mit Nebel im Einhorn. Am Südende liegt der Konusnebel, eine dunkle Staubsäule; am Nordende der helle Stern S Monocerotis.",
  "", "Die Sterne bilden einen auf dem Kopf stehenden Weihnachtsbaum, an dessen Spitze ein dunkler Kegel aus Staub steht.")
o(["IC 2118"], "Hexenkopfnebel", "ca. 900 Lichtjahre", "ca. 50 Lichtjahre", None,
  "Ein schwacher Reflexionsnebel im Eridanus, beleuchtet vom hellen Orion-Stern Rigel. Wegen der Streuung erscheint er blau.",
  "", "Ein bläulicher Nebel im Profil eines Hexenkopfes – angestrahlt vom hellen Stern Rigel.")
o(["NGC 2632", "M 44"], "Praesepe (Krippe)", "ca. 580 Lichtjahre", "ca. 15 Lichtjahre", "ca. 600–700 Mio. Jahre",
  "Ein naher offener Sternhaufen im Krebs mit rund 1.000 Mitgliedern. Er hat ein ähnliches Alter und eine ähnliche Bewegung wie die Hyaden und stammt wohl aus derselben Region.",
  "In Praesepe wurden mehrere Exoplaneten nachgewiesen (u. a. mit Kepler/K2) – Planeten in Sternhaufen gelten als besonders aufschlussreich.",
  "Ein Sternhaufen, der mit bloßem Auge als nebliger Fleck erscheint – schon in der Antike bekannt.")
o(["NGC 2168", "M 35"], "M 35", "ca. 2.800 Lichtjahre", "ca. 24 Lichtjahre", "ca. 150 Mio. Jahre",
  "Ein reicher offener Sternhaufen in den Zwillingen. Daneben liegt der viel weiter entfernte, ältere Haufen NGC 2158.",
  "", "Ein großer Sternhaufen mit Hunderten Sternen – gut im Fernglas zu sehen.")
o(["NGC 1960", "M 36"], "M 36", "ca. 4.100 Lichtjahre", None, "ca. 25 Mio. Jahre", "Ein junger offener Sternhaufen im Fuhrmann.", "", "Eine junge Sternfamilie im Sternbild Fuhrmann.")
o(["NGC 2099", "M 37"], "M 37", "ca. 4.500 Lichtjahre", None, "ca. 350–500 Mio. Jahre", "Der reichste offene Sternhaufen im Fuhrmann mit über 500 Sternen.", "", "Ein dicht gepackter Sternhaufen mit vielen Sternen.")
o(["NGC 1912", "M 38"], "M 38", "ca. 3.500 Lichtjahre", None, "ca. 250 Mio. Jahre", "Ein offener Sternhaufen im Fuhrmann mit kreuzförmiger Sternanordnung.", "", "Ein Sternhaufen, dessen Sterne ein Kreuz zu bilden scheinen.")
o(["NGC 1952", "M 1"], "Krebsnebel", "ca. 6.500 Lichtjahre", "ca. 11 Lichtjahre", "Supernova im Jahr 1054",
  "Der Überrest der Supernova von 1054, die chinesische Astronomen dokumentierten. Im Zentrum rotiert ein Pulsar 30-mal pro Sekunde und speist den Nebel mit Energie.",
  "Das James-Webb-Teleskop kartierte 2023/24 Staub und Elemente im Nebel; die Zusammensetzung spricht für eine Supernova vom Typ „Elektroneneinfang“ eines relativ massearmen Sterns.",
  "Die Trümmer einer Sternexplosion, die vor fast 1.000 Jahren am Taghimmel sichtbar war. In der Mitte dreht sich ein winziger Neutronenstern wie ein Leuchtturm.")

# ---------------------------------------------------------------- Sommer
o(["NGC 6523", "M 8"], "Lagunennebel", "ca. 4.100 Lichtjahre", "ca. 110 × 50 Lichtjahre", None,
  "Eine große H-II-Region im Schützen mit dem jungen Haufen NGC 6530, Bok-Globulen und dem „Stundenglas“-Gebiet, das vom Stern Herschel 36 ionisiert wird.",
  "", "Ein heller Nebel Richtung Milchstraßenzentrum – schon mit bloßem Auge an dunklen Orten sichtbar.")
o(["NGC 6514", "M 20"], "Trifidnebel", "ca. 5.200 Lichtjahre", "ca. 40 Lichtjahre", None,
  "Eine Kombination aus rotem Emissionsnebel, blauem Reflexionsnebel und dunklen Staubbahnen, die ihn in drei Teile gliedern.",
  "", "Ein Nebel, der von dunklen Bändern in drei Teile geschnitten wird – rot und blau zugleich.")
o(["NGC 6611", "M 16"], "Adlernebel", "ca. 5.700 Lichtjahre", "ca. 70 × 55 Lichtjahre", "Haufen ca. 1–2 Mio. Jahre",
  "Eine H-II-Region mit dem jungen Haufen NGC 6611. Berühmt sind die „Säulen der Schöpfung“, dichte Gas- und Staubsäulen, die von UV-Strahlung abgetragen werden.",
  "Das James-Webb-Teleskop zeigte 2022 die Säulen im Infrarot mit Dutzenden neu entstehender Sterne und Jets.",
  "Hier stehen die berühmten „Säulen der Schöpfung“ – riesige Staubfinger, in denen neue Sterne entstehen.")
o(["NGC 6618", "M 17"], "Omeganebel", "ca. 5.500 Lichtjahre", "ca. 15 Lichtjahre (heller Kern)", None,
  "Eine der hellsten und massereichsten Sternentstehungsregionen der Milchstraße, angeregt von einem eingebetteten jungen Haufen.",
  "", "Ein sehr heller Gasnebel, der an einen Schwan oder den griechischen Buchstaben Omega erinnert.")
o(["NGC 6705", "M 11"], "Wildentenhaufen", "ca. 6.200 Lichtjahre", "ca. 20 Lichtjahre", "ca. 250–300 Mio. Jahre",
  "Einer der reichsten und dichtesten offenen Sternhaufen mit fast 3.000 Sternen.", "",
  "Die hellsten Sterne bilden ein V wie ein Schwarm fliegender Wildenten.")
o(["NGC 6853", "M 27"], "Hantelnebel", "ca. 1.360 Lichtjahre", "ca. 3 Lichtjahre", "ca. 10.000 Jahre",
  "Der erste entdeckte planetarische Nebel (Messier 1764). Der Zentralstern ist ein heißer Weißer Zwerg (≈ 85.000 K).", "",
  "Die abgestoßene Hülle eines sterbenden Sterns – so ähnlich wird auch unsere Sonne einmal enden.")
o(["NGC 6720", "M 57"], "Ringnebel", "ca. 2.500 Lichtjahre", "ca. 1,3 Lichtjahre", "ca. 4.000 Jahre",
  "Ein planetarischer Nebel in der Leier: eine etwa tonnenförmige Gashülle, die wir zufällig entlang ihrer Achse sehen und die deshalb wie ein Ring wirkt.",
  "JWST-Aufnahmen von 2023 zeigen rund 20.000 dichte Gasklumpen im Ring sowie konzentrische Bögen in der äußeren Hülle – ein Hinweis auf einen bislang unbekannten Begleitstern.",
  "Ein leuchtender Rauchring im All – die Hülle eines sterbenden Sterns, die wir genau von oben sehen.")
o(["NGC 6205", "M 13"], "Herkules-Kugelsternhaufen", "ca. 22.000–25.000 Lichtjahre", "ca. 145 Lichtjahre", "ca. 11–12 Mrd. Jahre",
  "Der hellste Kugelsternhaufen des Nordhimmels mit mehreren hunderttausend Sternen.",
  "1974 wurde vom Arecibo-Radioteleskop eine Botschaft in Richtung M 13 gesendet – sie wird in rund 25.000 Jahren ankommen.",
  "Eine riesige Kugel aus Hunderttausenden uralter Sterne – fast so alt wie das Universum.")
o(["NGC 6341", "M 92"], "M 92", "ca. 27.000 Lichtjahre", "ca. 110 Lichtjahre", "ca. 13 Mrd. Jahre",
  "Einer der ältesten Kugelsternhaufen der Milchstraße und Referenzobjekt für die Altersbestimmung.", "", "Ein uralter Kugelsternhaufen im Herkules.")
o(["NGC 5272", "M 3"], "M 3", "ca. 34.000 Lichtjahre", "ca. 180 Lichtjahre", "ca. 11 Mrd. Jahre",
  "Ein großer Kugelsternhaufen mit über 500.000 Sternen und einer Rekordzahl an RR-Lyrae-Veränderlichen.", "", "Eine gewaltige, sehr alte Sternkugel.")
o(["NGC 7293"], "Helixnebel", "ca. 650 Lichtjahre", "ca. 2,5 Lichtjahre", "ca. 10.000 Jahre",
  "Einer der nächstgelegenen planetarischen Nebel. Er enthält Tausende kometenartige Gasknoten („cometary knots“).", "",
  "Wegen seines Aussehens auch „Auge Gottes“ genannt: die abgestoßene Hülle eines sterbenden Sterns ganz in unserer Nähe.")

# ---------------------------------------------------------------- Galaxien
o(["NGC 224", "M 31"], "Andromedagalaxie", "ca. 2,5 Mio. Lichtjahre", "ca. 150.000–220.000 Lichtjahre", None,
  "Die nächste große Spiralgalaxie und größtes Mitglied der Lokalen Gruppe, mit rund einer Billion Sternen. Begleiter sind u. a. M 32 und M 110.",
  "Eine Studie von 2025 auf Basis von Gaia- und Hubble-Daten kam zu dem Schluss, dass eine Verschmelzung mit der Milchstraße in den nächsten 10 Mrd. Jahren nur mit etwa 50 % Wahrscheinlichkeit eintritt – früher galt sie als sicher.",
  "Das am weitesten entfernte Objekt, das man mit bloßem Auge sehen kann: eine Nachbargalaxie mit rund einer Billion Sonnen. Ihr Licht ist 2,5 Millionen Jahre alt.")
o(["NGC 221", "M 32"], "M 32", "ca. 2,5 Mio. Lichtjahre", "ca. 6.500 Lichtjahre", None,
  "Eine kompakte elliptische Zwerggalaxie, Begleiter der Andromedagalaxie.", "", "Eine kleine Begleitgalaxie von Andromeda.")
o(["NGC 205", "M 110"], "M 110", "ca. 2,7 Mio. Lichtjahre", "ca. 17.000 Lichtjahre", None,
  "Eine elliptische Zwerggalaxie, Begleiter der Andromedagalaxie.", "", "Ein weiterer kleiner Begleiter der Andromedagalaxie.")
o(["NGC 598", "M 33"], "Dreiecksgalaxie", "ca. 2,7 Mio. Lichtjahre", "ca. 60.000 Lichtjahre", None,
  "Die drittgrößte Galaxie der Lokalen Gruppe, eine Spirale ohne ausgeprägten Zentralbulge. Sie enthält die riesige H-II-Region NGC 604.",
  "", "Unsere zweitnächste große Nachbargalaxie – eine lockere Spirale, sehr lichtschwach, aber groß.")
o(["NGC 3031", "M 81"], "Bodes Galaxie", "ca. 12 Mio. Lichtjahre", "ca. 90.000 Lichtjahre", None,
  "Eine große Spiralgalaxie im Großen Bären, im Zentrum ein Schwarzes Loch von ≈ 70 Mio. Sonnenmassen. Wechselwirkt mit M 82 und NGC 3077.", "",
  "Eine prächtige Spiralgalaxie – zusammen mit der Zigarrengalaxie ein beliebtes Fotomotiv.")
o(["NGC 3034", "M 82"], "Zigarrengalaxie", "ca. 12 Mio. Lichtjahre", "ca. 37.000 Lichtjahre", None,
  "Eine Starburst-Galaxie: Durch die Gezeitenwirkung von M 81 entstehen Sterne zehnmal schneller als in der Milchstraße; ein „superwind“ treibt Gas aus der Scheibe.",
  "2014 explodierte in M 82 die Supernova SN 2014J – eine der nächsten Typ-Ia-Supernovae seit Jahrzehnten.",
  "Eine Galaxie im „Baby-Boom“: Hier entstehen extrem viele neue Sterne.")
o(["NGC 5194", "M 51"], "Whirlpool-Galaxie", "ca. 27 Mio. Lichtjahre", "ca. 76.000 Lichtjahre", None,
  "Eine Grand-Design-Spiralgalaxie, deren Arme durch die Begleitgalaxie NGC 5195 verstärkt werden.",
  "2021 wurde mit Chandra ein möglicher Planet in M 51 gemeldet (M51-ULS-1b) – der erste Kandidat außerhalb der Milchstraße, entdeckt per Röntgen-Transit.",
  "Eine Spiralgalaxie wie aus dem Lehrbuch, die gerade eine kleinere Nachbargalaxie „anzieht“.")
o(["NGC 5195"], "NGC 5195", "ca. 27 Mio. Lichtjahre", None, None, "Die Begleitgalaxie von M 51.", "", "Die kleine Nachbargalaxie der Whirlpool-Galaxie.")
o(["NGC 5457", "M 101"], "Feuerradgalaxie", "ca. 21 Mio. Lichtjahre", "ca. 170.000 Lichtjahre", None,
  "Eine große, asymmetrische Spiralgalaxie im Großen Bären.",
  "Im Mai 2023 explodierte in M 101 die Supernova SN 2023ixf – eine der nächsten Kernkollaps-Supernovae des Jahrzehnts, intensiv beobachtet.",
  "Eine riesige, offene Spirale – fast doppelt so groß wie die Milchstraße.")
o(["NGC 4594", "M 104"], "Sombrerogalaxie", "ca. 31 Mio. Lichtjahre", "ca. 50.000 Lichtjahre", None,
  "Eine nahezu von der Kante gesehene Galaxie mit großem Bulge und markantem Staubband.", "",
  "Sieht aus wie ein mexikanischer Hut – eine Galaxie, die wir fast genau von der Seite sehen.")
o(["NGC 5055", "M 63"], "Sonnenblumengalaxie", "ca. 29 Mio. Lichtjahre", None, None, "Eine flockige Spiralgalaxie mit vielen kurzen Armsegmenten.", "", "Eine Galaxie, deren Arme an die Kerne einer Sonnenblume erinnern.")
o(["NGC 4826", "M 64"], "Galaxie mit dem schwarzen Auge", "ca. 17 Mio. Lichtjahre", None, None,
  "Spiralgalaxie mit auffälligem Staubband vor dem Kern; Gas in den äußeren Bereichen rotiert entgegengesetzt zu den inneren – Spur einer früheren Verschmelzung.", "",
  "Ein dunkles Staubband lässt den Kern wie ein „blaues Auge“ aussehen.")
o(["NGC 4258", "M 106"], "M 106", "ca. 24 Mio. Lichtjahre", None, None,
  "Seyfert-Galaxie mit zwei „anomalen“ Armen, die von Jets aus dem Zentrum erzeugt werden. Ihr Wasser-Maser lieferte eine der genauesten geometrischen Galaxienentfernungen.", "",
  "Eine Spiralgalaxie mit zwei zusätzlichen, geisterhaften Armen.")
o(["NGC 3627", "M 66"], "M 66", "ca. 36 Mio. Lichtjahre", None, None, "Teil des Leo-Tripletts; durch Gezeitenwechselwirkung verzerrte Spirale.", "", "Eines von drei Galaxien-Geschwistern im Löwen.")
o(["NGC 3623", "M 65"], "M 65", "ca. 35 Mio. Lichtjahre", None, None, "Teil des Leo-Tripletts; schräg gesehene Spiralgalaxie.", "", "Eine Galaxie im Leo-Triplett.")
o(["NGC 628", "M 74"], "Phantomgalaxie", "ca. 32 Mio. Lichtjahre", None, None,
  "Eine Grand-Design-Spirale, von oben gesehen. JWST zeigte 2022 im PHANGS-Projekt ihre staubigen Filamente.", "", "Eine perfekt von oben gesehene Spiralgalaxie, sehr lichtschwach.")
o(["NGC 1068", "M 77"], "M 77", "ca. 47 Mio. Lichtjahre", None, None, "Prototyp einer Seyfert-2-Galaxie mit aktivem, staubverhülltem Kern.", "", "Eine Galaxie mit einem sehr aktiven Schwarzen Loch im Zentrum.")
o(["NGC 253"], "Sculptor-Galaxie", "ca. 11 Mio. Lichtjahre", "ca. 90.000 Lichtjahre", None, "Eine staubreiche Starburst-Galaxie, Mitglied der Sculptor-Gruppe.", "", "Eine helle, schräg gesehene Galaxie mit vielen neuen Sternen.")
o(["NGC 891"], "NGC 891", "ca. 30 Mio. Lichtjahre", "ca. 100.000 Lichtjahre", None, "Eine exakt von der Kante gesehene Spiralgalaxie mit markanter Staubbahn – ähnlich der Milchstraße.", "", "So würde unsere Milchstraße von der Seite aussehen.")
o(["NGC 4565"], "Nadelgalaxie", "ca. 40 Mio. Lichtjahre", "ca. 100.000 Lichtjahre", None, "Eine von der Kante gesehene Spiralgalaxie mit Staubband.", "", "Eine Galaxie, schmal wie eine Nadel.")
o(["NGC 3587", "M 97"], "Eulennebel", "ca. 2.000 Lichtjahre", "ca. 2 Lichtjahre", "ca. 8.000 Jahre", "Ein planetarischer Nebel mit zwei dunklen „Augen“.", "", "Ein runder Nebel mit zwei dunklen Flecken – wie das Gesicht einer Eule.")
o(["NGC 3556", "M 108"], "M 108", "ca. 28 Mio. Lichtjahre", None, None, "Eine fast von der Kante gesehene Balkenspirale nahe M 97.", "", "Eine schmale Galaxie neben dem Eulennebel.")

# ---------------------------------------------------------------- Kometen (Schlüssel COMET:<Name>)
o(["COMET:Tsuchinshan-ATLAS", "COMET:C/2023 A3"], "C/2023 A3 (Tsuchinshan-ATLAS)", None, None, None,
  "Entdeckt im Januar 2023 vom Purple-Mountain-Observatorium (Tsuchinshan) und im Februar 2023 vom ATLAS-Survey. Perihel am 27. September 2024 in 0,39 AE Sonnenabstand, größte Erdnähe am 12. Oktober 2024 (≈ 0,47 AE). Die Bahn ist leicht hyperbolisch – der Komet stammt aus der Oortschen Wolke und kehrt wahrscheinlich nicht zurück.",
  "Um den 9. Oktober 2024 erreichte er durch Vorwärtsstreuung des Sonnenlichts am Staub kurzzeitig etwa −4,9 mag (SOHO). Mitte Oktober zeigte er einen spektakulären Gegenschweif, da die Erde nahezu die Bahnebene querte.",
  "Der „Komet des Jahres 2024“: Im Oktober 2024 war er am Abendhimmel mit bloßem Auge sichtbar und hatte einen über 20° langen Schweif.")
o(["COMET:NEOWISE", "COMET:C/2020 F3"], "C/2020 F3 (NEOWISE)", None, None, None,
  "Entdeckt am 27. März 2020 vom Infrarot-Satelliten NEOWISE. Perihel am 3. Juli 2020 in 0,29 AE; durch die Sonnennähe verlängerte sich seine Umlaufzeit auf rund 6.700 Jahre.",
  "", "Der hellste Komet am Nordhimmel seit Hale-Bopp – im Juli 2020 mit bloßem Auge in der Morgen- und Abenddämmerung zu sehen.")
o(["COMET:12P", "COMET:Pons-Brooks"], "12P/Pons-Brooks", None, None, None,
  "Ein Halley-Typ-Komet mit rund 71 Jahren Umlaufzeit. Perihel am 21. April 2024 (0,78 AE). Bekannt für wiederholte Helligkeitsausbrüche, bei denen die Koma vorübergehend „Hörner“ zeigte.",
  "", "Ein „Teufelskomet“: Bei Ausbrüchen sah seine Koma aus, als hätte sie Hörner.")
o(["COMET:C/2022 E3"], "C/2022 E3 (ZTF)", None, None, None,
  "Entdeckt im März 2022 von der Zwicky Transient Facility. Perihel am 12. Januar 2023, Erdnähe am 1. Februar 2023 (0,28 AE). Die grüne Farbe der Koma stammt von zweiatomigem Kohlenstoff (C₂).",
  "", "Der „grüne Komet“ von Anfang 2023 – das Grün kommt von Kohlenstoffmolekülen, die vom Sonnenlicht zum Leuchten angeregt werden.")

out = sys.argv[1] if len(sys.argv) > 1 else "Resources/Catalogs/objects_de.json"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    json.dump(E, f, ensure_ascii=False, indent=1)
print(f"{len(E)} Einträge → {out}")
