# ProfessionMenu (Berufe-Menü) – ausführliche Beschreibung

Kurzfassung und Installation: [README.md](../README.md).

Ein Knopf **„Berufe“**, der beim Klick eine Liste deiner erlernten Berufe ausklappt. Ein Klick auf einen Beruf
öffnet ihn. Für **WoW 3.3.5a**; sieht mit **ElvUI** aus wie ElvUI (Vorlagen, Schrift, Wertfarbe, Pixelraster,
Mover, Optionen unter `/ec` → „Berufe-Menü“), läuft aber auch ohne ElvUI mit eigenem flachem Design.

*English summary:* a "Professions" button that unrolls a list of the professions you have learned, grouped by
category; click one to open its window (Smelting has its own entry, a tracking search for Mining/Herbalism, the
skills window for Skinning, casting for Fishing). Matches ElvUI, standalone otherwise. Commands: `/berufe`. Two optional settings, both off
by default: smaller icon-only display (`/berufe compact button|all`, button only or button and list) and active
abilities in the list (`/berufe abilities on`: Fishing, Disenchant, Prospecting, Milling, Campfire, tracking searches).

## Benutzung

* **Linksklick** auf den Knopf: Liste auf/zu. Klick daneben oder ESC schließt sie.
* **Linksklick** auf einen Beruf (auch mit Umschalt/Strg/Alt):
  * Herstellung, Weiterverarbeitung, Kochkunst, Erste Hilfe: das Berufsfenster öffnet sich (ein schon offenes
    Berufsfenster wird dabei ersetzt).
  * **Verhüttung** (steht unter Weiterverarbeitung, sobald Bergbau gelernt ist): Schmelzfenster.
  * **Bergbau** / **Kräuterkunde**: Mineraliensuche bzw. Kräutersuche aktivieren (die Berufe selbst haben kein
    Fenster; sie wirken auf Rohstoffvorkommen).
  * **Kürschnerei** (nichts zu öffnen): zeigt das Fertigkeitenfenster.
  * **Angeln**: wirft die Angel aus.
* **Rechtsklick** auf einen Beruf: Fertigkeitenfenster (ist es schon offen, bleibt es offen).
* Im Kampf ruht der Knopf (abgedunkelt), die Liste schließt sich von allein und lässt sich nicht öffnen.
* Rechts steht die Fertigkeitsstufe (grün, wenn sie das Maximum der Stufe erreicht hat).
* Knopf und Liste sind gleich breit: die Breite richtet sich nach dem längsten Berufsnamen deiner
  Sprache und bleibt beim Steigern der Stufen gleich.

## Optionen: kleinere Darstellung und aktive Fähigkeiten

Beides ist standardmäßig **aus** (`/berufe compact …`, `/berufe abilities …`, mit ElvUI auch unter `/ec` → „Berufe-Menü“).

* **`compact button`** – der Knopf „Berufe“ ist nur noch ein quadratisches Symbol (Hammer auf Amboss), ohne Text und
  Pfeil. Die Liste bleibt wie gewohnt mit Namen und Stufen.
* **`compact all`** – Knopf **und** Liste zeigen nur Symbole: eine schmale Spalte quadratischer Felder (so breit wie der
  Knopf), ohne Überschriften, zwischen den Kategorien eine kleine Lücke. Name, Stufe und Hinweise stehen im Tooltip.
* **`compact off`** – mit Text (Standard).
* **`abilities on`** – nimmt die **aktiven Fähigkeiten** in die Liste auf, in einer eigenen letzten Kategorie
  „Fähigkeiten“ (nur, was du kennst): **Angeln**, **Entzaubern**, **Sondieren**, **Mahlen**, **Einfaches Lagerfeuer**,
  **Mineraliensuche**, **Kräutersuche**, **Fischsuche**. Ein Klick wirkt den Zauber; bei Entzaubern, Sondieren und Mahlen
  wählst du danach den Gegenstand aus. Angeln wandert dafür aus den Nebenberufen in die Fähigkeiten (mit seiner
  Stufe), und Bergbau/Kräuterkunde starten die Suche nicht mehr selbst (ein Klick zeigt dort das Fertigkeitenfenster),
  weil die Suchzauber jetzt eigene Zeilen sind.

## Sortierung

Standard sind **Kategorien**, innerhalb davon in sinnvoller Reihenfolge:

| Kategorie | Berufe |
|---|---|
| Herstellung | Schmiedekunst, Lederverarbeitung, Schneiderei, Ingenieurskunst, Alchemie, Inschriftenkunde |
| Weiterverarbeitung | Verhüttung, Juwelenschleifen, Verzauberkunst |
| Sammeln | Bergbau, Kräuterkunde, Kürschnerei |
| Nebenberufe | Kochkunst, Erste Hilfe, Angeln |
| Fähigkeiten (nur mit `abilities on`) | Angeln, Entzaubern, Sondieren, Mahlen, Lagerfeuer, Mineralien-, Kräuter-, Fischsuche |

Alternativ `alpha` (alphabetisch) oder `rank` (nach Fertigkeitsstufe, ohne Überschriften).

## Befehle

```
/berufe                      Liste auf/zu
/berufe list                 zeigt, welche Fertigkeiten erkannt wurden (hilft bei Fehlern)
/berufe sort cat|alpha|rank  Sortierung
/berufe headers on|off       Kategorie-Überschriften
/berufe ranks on|off         Fertigkeitsstufen anzeigen
/berufe direction auto|up|down   Öffnungsrichtung (auto: unten am Bildschirm nach oben)
/berufe compact off|button|all   Darstellung: mit Text | Knopf nur Symbol | Knopf und Liste nur Symbole
/berufe abilities on|off     aktive Fähigkeiten (Angeln, Entzaubern ...) in die Liste aufnehmen
/berufe scale 0.5-2          Skalierung (nur ohne ElvUI, nicht im Kampf)
/berufe unlock | lock        Knopf verschieben (nur ohne ElvUI)
/berufe reset                Position zurücksetzen
/berufe debug                Meldungen bei Fehlern
```

`/profmenu` ist dasselbe. Mit ElvUI gibt es dieselben Einstellungen (außer Skalierung) unter `/ec` → **Berufe-Menü**
(ein eigener Eintrag in der linken Liste; unter „Plugins“ steht nur die Liste der geladenen Plugins).

## Position

* **Mit ElvUI**: Standardplatz über dem rechten Chatfenster. Verschieben mit `/moveui` (Anker „Berufe-Knopf“); die
  Größe folgt ElvUIs UI-Skalierung und Schriftgröße. An diesem Platz öffnet ElvUI auch sein Taschenfenster (bei vielen
  Taschenplätzen kann es den Knopf verdecken): `/berufe` (oder ein Makro mit `/berufe`) öffnet die Liste trotzdem, oder verschiebe
  den Knopf.
* **Ohne ElvUI**: `/berufe unlock`, mit der linken Maustaste ziehen, `/berufe lock`.

## So wird gebaut (für Fehlersuche)

* **Berufe erkennen**: Das Addon liest die Fertigkeiten (`GetSkillLineInfo`) und das Zauberbuch. Eingeklappte
  Überschriften im Fertigkeitenfenster (nur die der Berufe und Nebenberufe) werden zum Lesen aufgeklappt und danach
  wieder zugeklappt. Die Namen der Berufe stehen in `Data.lua`: für enUS, deDE, frFR, esES und ruRU direkt aus den
  Client-Dateien gelesen, für koKR, zhCN und zhTW indirekt (Zaubername aus dem mehrsprachigen Spell.dbc, gegen
  Tooltips und Addon-Dateien verglichen), esMX übernimmt die spanischen Namen. Zusätzlich zählen die Namen der
  Berufszauber (`GetSpellInfo`). Die Kräuterkunde heißt als Zauber anders (deDE „Kräutersammeln“); sie wird über den
  Hilfszauber 9134 erkannt, der genau den Fertigkeitsnamen trägt. Taucht ein Beruf nicht auf, zeigt `/berufe list`,
  was erkannt wurde.
* **Klick wirkt einen Zauber**: Die Zeilen sind `SecureActionButtons` (`type1=spell`, `spell1=<Zaubername>`). Nur
  Zauber mit dem Effekt „Handwerk“ öffnen ein Fenster (Schmiedekunst … Erste Hilfe, Verhüttung); Bergbau, Kräutersammeln
  und Kürschnerei wirken auf Weltobjekte und öffnen deshalb nichts.
* **Kampfsperre**: Geschützte Rahmen lassen sich im Kampf nicht verschieben, ein-/ausblenden oder umbelegen, ebenso
  ihre Eltern und die Rahmen, an denen sie hängen. Darum ist die Liste ein `SecureHandlerStateTemplate`-Rahmen, der sich
  im Kampf selbst schließt (`[combat]`), nur an `UIParent` verankert (feste Abstände aus der Lage des Knopfes, damit
  weder der Knopf noch ElvUIs Chatfenster in der geschützten Kette hängen), und nur außerhalb des Kampfes umgebaut wird.
  ESC schließt über einen ungeschützten Stellvertreter (`ProfessionMenuEscProxy`), nicht über die geschützte Liste.
* **ElvUI-Look**: Vorlagen „Default“ (Knopf, mit Glanz) und „Transparent“ (Liste), Wertfarbe und Rahmenfarbe werden
  jedes Mal frisch gelesen, alle Maße liegen auf ganzen Pixeln (`E.mult`), Schriftgröße = Größe der Stelle + (ElvUI-
  Grundgröße − 12). Nach Änderung von Schrift oder Profil in ElvUI misst das Addon neu, nach Änderung der Wertfarbe färbt es neu.

## Nicht im Spiel geprüft

Die Tests laufen gegen eine strenge Attrappe des 3.3.5a-Clients (siehe `tests/`), das Aussehen wurde mit einer
Pixelvorschau (nicht Teil dieses Repos) gegen Mockups verglichen. Im Spiel hat der Autor die normale Bedienung über die Oberfläche
ausprobiert (Liste, Klick auf Berufe, Einstellungen); dabei schien alles zu funktionieren. Die folgenden Punkte
wurden nicht einzeln geprüft:

* ob der Zustandstreiber `[combat]` die Liste im Kampf zuverlässig schließt (zusätzlich schließt sie das Ereignis
  `PLAYER_REGEN_DISABLED`);
* ob die Berufszauber per Name (`type1=spell`) so das Fenster öffnen wie über das Zauberbuch (so tun es andere Addons);
* das Erkennen der Berufe auf Clients mit angepasstem Zauberbuch (z. B. einer eigenen `NewSpellBook`-Umsetzung) und das Auf-/Zuklappen
  der Fertigkeitsüberschriften (löst vermutlich `SKILL_LINES_CHANGED` aus; das Addon ignoriert es dann 0,5 s lang, ein
  Skill-Up genau in diesem Fenster erscheint erst beim nächsten Öffnen);
* Aussehen und Pixelraster mit deinem ElvUI-Profil, auch die Symbol-Darstellung (`compact`): Rand um das Symbol,
  Hervorhebung beim Überfahren, Lücken zwischen den Kategorien;
* Fähigkeiten, die einen Gegenstand brauchen (Entzaubern, Sondieren, Mahlen): ob der Mauszeiger nach dem Klick
  auf den Zauber wie üblich zum Auswahl-Zeiger wird, und ob die Suchzauber (Mineralien-/Kräuter-/Fischsuche) bei
  erneutem Klick die Ortung wieder abschalten;
* ob das Symbol `Ability_Miling` (Mahlen) in deinem Client vorhanden ist (sonst zeigt die Zeile das Fragezeichen).

## Dateien

```
ProfessionMenu.toc
Locales.lua    Texte (vollständig: de, en; Titel, Kategorien und Tooltips auch fr, es, ru, ko, zh; der Rest fällt
               auf Englisch zurück)
Data.lua       Berufe, Kategorien, Namen je Sprache, Zauber-IDs
Core.lua       Erkennung und Aufbau der Liste (ohne Oberfläche, testbar)
Skin.lua       ElvUI-Aussehen oder flaches Eigendesign, Pixelraster, Schrift
UI.lua         Knopf, Liste, Zeilen (SecureActionButtons), Kampfsperre
Main.lua       Ereignisse, Start, Chatbefehle
Options.lua    ElvUI-Optionen (nur mit ElvUI)
Media/chevron.tga   Pfeil am Knopf
README.md      Kurzfassung, Installation
LICENSE        MIT-Lizenz
docs/README.de.md   diese Beschreibung
tests/         strenge Attrappe, Prüfungen und Tests:  bash tests/check.sh
```
