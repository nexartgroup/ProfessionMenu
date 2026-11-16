# ProfessionMenu (Berufe-Menü) für WoW: Forever – ausführliche Beschreibung

Kurzfassung und Installation: [README.md](../README.md).

Ein Knopf **„Berufe“**, der beim Klick eine Liste deiner erlernten Berufe ausklappt. Ein Klick auf einen Beruf
öffnet ihn; seine Tätigkeiten (Verhütten, Suchen, Entzaubern, Angeln …) stehen in einem Untermenü daneben, und die
Lager-Objekte von WoW: Forever (Lagerfeuer, Zelt, Fischglas …) lassen sich aus der Liste herstellen und aufstellen.
Dieser Zweig (`forever`) ist die Umsetzung für **WoW: Forever** (Retail-Technik, Interface `16001`,
Version 1.60.1). Die Fassung für **WoW 3.3.5a** mit ElvUI-Anbindung steht auf dem Zweig `main`.

## Benutzung

* **Linksklick** auf den Knopf: Liste auf/zu. Klick daneben oder ESC schließt sie.
* **Linksklick** auf einen Beruf (auch mit Umschalt/Strg/Alt):
  * Herstellung, Weiterverarbeitung, Kochkunst, Erste Hilfe: das Berufsfenster öffnet sich. Ist das Fenster dieses
    Berufs schon offen, passiert nichts (Blizzards eigene Reiter wirken den Zauber in dem Fall auch nicht noch einmal).
  * **Bergbau**: öffnet das Schmelzfenster, wenn das Spiel eines für den Beruf vorsieht; sonst startet es die Mineraliensuche.
  * **Kräuterkunde**: Kräutersuche aktivieren.
  * **Kürschnerei** (nichts zu öffnen): zeigt die Berufsübersicht.
  * **Angeln**: wirft die Angel aus.
* **Rechtsklick** auf einen Beruf: Berufsübersicht (Blizzards Berufsbuch).
* Im Kampf ruht der Knopf (abgedunkelt), die Liste schließt sich von allein und lässt sich nicht öffnen.
* Rechts steht die Fertigkeitsstufe (grün, wenn sie das Maximum der Stufe erreicht hat).
* Knopf und Liste sind gleich breit: die Breite richtet sich nach dem längsten Berufsnamen deiner Sprache.

### Platzhalter: was noch erlernt werden kann

WoW: Forever kennt zwei Hauptberufe und die Nebenberufe Kochkunst, Erste Hilfe und Angeln. Was davon noch nicht erlernt
ist, steht als Platzhalter in der Liste: je freiem Hauptberuf eine Zeile **„Hauptberuf“** (Kategorie „Hauptberufe“, vor
den Nebenberufen), je fehlendem Nebenberuf eine Zeile mit dessen Namen an seiner üblichen Stelle. Platzhalter sind
gedimmt und gestrichelt umrandet. Ein Klick (links oder rechts) zeigt die Berufsübersicht; der Tooltip sagt, dass der
Beruf bei einem Lehrer erlernt werden kann. Ohne erlernte Berufe sieht die Liste so aus:

```
Hauptberufe
  [ Hauptberuf ]
  [ Hauptberuf ]
Nebenberufe
  [ Kochkunst ]
  [ Erste Hilfe ]
  [ Angeln ]
```

**Erlernbare Berufe.** Liegt die Maus auf einem freien „Hauptberuf“, klappt daneben die Liste der Hauptberufe auf, die
der Charakter noch erlernen kann (Schmiedekunst, Lederverarbeitung, Schneiderei, Ingenieurskunst, Alchemie,
Verzauberkunst, Bergbau, Kräuterkunde, Kürschnerei – ohne die, die er schon hat).

**Twinks.** Hat ein anderer Charakter des Kontos einen dieser Berufe schon, steht sein Name grün rechts in der Zeile
(bei mehreren der mit der höchsten Stufe und „+1“, „+2“ …); der Tooltip nennt alle mit ihrer Stufe. Dafür merkt sich
das Addon die Berufe jedes Charakters, sobald er einmal angemeldet war (kontoweit in den gespeicherten Einstellungen,
`chars`). Charaktere, die seit dieser Fassung noch nicht angemeldet waren, kennt es nicht. `/berufe alts` zeigt, was
gemerkt ist; `/berufe alts clear` vergisst alle außer dem angemeldeten (etwa nach dem Löschen eines Charakters).

Bei Sortierung nach Namen oder Stufe stehen die Platzhalter hinter den erlernten Berufen. Ließen sich die Berufe nicht
lesen (die Funktion des Spiels fehlt oder wirft einen Fehler), gibt es keine Platzhalter.

### Untermenüs: die Tätigkeiten eines Berufs

Hat ein Beruf mehr zu bieten als den Klick auf seine Zeile, trägt die Zeile einen kleinen Winkel. Liegt die Maus
darauf, klappt daneben ein **Untermenü** auf:

* die aktiven Zauber des Berufs aus dem Zauberbuch (Bergbau: Verhütten **und** Mineraliensuche; Angeln; Kochkunst …),
* bekannte Fähigkeiten, die zu ihm gehören (**Entzaubern** bei Verzauberkunst, Sondieren, Mahlen, Fischsuche …) – ein
  Klick wirkt den Zauber, bei Entzaubern wählst du danach den Gegenstand,
* seine **Lager-Objekte** (siehe unten).

Das Untermenü bleibt offen, bis die Maus eine Weile auf einer anderen Zeile liegt, du daneben klickst oder ESC drückst.
Eine bekannte Fähigkeit, deren Beruf nicht in der Liste steht, bekommt eine Zeile in der Kategorie „Fähigkeiten“.

### Lager (WoW: Forever)

Forever gibt jedem Beruf Lager-Objekte: das **Lagerfeuer** (Kochkunst, drei Stufen) und Dinge, die man daneben
aufstellt – Campingzelt (Lederverarbeitung), Fischglas (Angeln), Manabrunnen (Alchemie), Schleifrad (Schmiedekunst),
Magnetstein (Bergbau), Räucherkerze (Kräuterkunde), Campingstuhl (Kürschnerei), Verzauberte Laute (Verzauberkunst),
Reagenzien-Bot (Ingenieurskunst), Banner (Schneiderei), Erste-Hilfe-Kasten (Erste Hilfe) und je zwei höhere Stufen
(Fertigkeit 140 und 300). Jedes ist ein Gegenstand, den ein Rezept des Berufs herstellt und den man aus der Tasche
aufstellt. Das Addon kennt alle 38 (plus den Gemütlichen Schlafsack) und zeigt sie so (die Namen hier sind frei
übersetzt; in der Liste stehen die Namen, die dein Client liefert):

| Zustand | Zeile | Linksklick |
| --- | --- | --- |
| liegt im Inventar | grün, rechts die Anzahl (`x1`) | **stellt es auf** (benutzt den Gegenstand) |
| nicht im Inventar, Beruf und Fertigkeit reichen, Material liegt im Inventar | rechts „herstellen“ | **stellt es her** |
| Material fehlt | nur das **Lagerfeuer** (Grundfunktion): abgedunkelt, rechts „fehlt“ | nennt, was fehlt |
| Material fehlt, alles andere | keine Zeile | – |

* Die Kategorie **„Lager“** in der Liste zeigt je Objekt-Kette eine Zeile: die höchste Stufe, die im Inventar liegt,
  sonst die höchste herstellbare. Im Untermenü des Berufs stehen alle, die gerade gehen.
* **Herstellen** braucht das offene Berufsfenster. Der Klick öffnet es und stellt her, sobald es bereit ist. Verlangt
  das Spiel dafür einen eigenen Tastendruck, bittet eine Chatmeldung um einen zweiten Klick auf dieselbe Zeile (die
  Liste bleibt dafür offen). Danach wird aus der Zeile „aufstellen“. Sammelberufe und Angeln haben keinen Zauber, der
  ihr Fenster öffnet: dort zeigt der Klick die Berufsübersicht, du wählst den Beruf, dann stellt das Addon her.
* **Aufstellen**: Meldet das Spiel den Gegenstand als gerade nicht benutzbar oder läuft seine Abklingzeit (die
  Lager-Objekte teilen sich eine Stunde), ist die Zeile abgedunkelt und der Tooltip sagt warum; der Klick versucht es
  trotzdem, die Antwort gibt dann das Spiel (etwa „Benötigt Lagerfeuer“). Ob ein Lagerfeuer in der Nähe brennt, kann
  ein Addon vorab nicht sehen.
* Der Tooltip zeigt den Gegenstand (was er bewirkt), den Beruf mit der nötigen Fertigkeit und das Material mit
  „vorhanden/nötig“.
* Das einfache Lagerfeuer-Set braucht Einfaches Holz und als Werkzeug **Feuerstein und Zunder**.

## Optionen

Per Befehl (`/berufe compact …`, `/berufe activities …`, `/berufe camp …`) oder im Einstellungsfenster.

* **`compact button`** – der Knopf „Berufe“ ist nur noch ein quadratisches Symbol, ohne Text und Pfeil.
* **`compact all`** – Knopf **und** Liste zeigen nur Symbole; Name, Stufe und Hinweise stehen im Tooltip.
* **`activities sub|list|off`** – wo die Tätigkeiten stehen: `sub` (Voreinstellung) als Untermenü des Berufs; `list`
  wie bis Version 1.0 als eigene letzte Kategorie „Fähigkeiten“ (Angeln wandert dann dorthin, Kräuterkunde wirkt nicht
  mehr selbst); `off` gar nicht.
* **`camp auto|all|off`** – das Lager: `auto` (Voreinstellung) zeigt, was aufstellbar oder herstellbar ist, das
  Lagerfeuer immer; `all` zeigt auch, wofür Material fehlt (abgedunkelt, je Kette die unterste Stufe; im Untermenü alle
  Stufen, für die die Fertigkeit reicht); `off` blendet das Lager aus.
* **`unlearned on|off`** – Platzhalter für nicht erlernte Berufe (Voreinstellung: an).

## Befehle

```
/berufe                      Liste auf/zu
/berufe sort cat|alpha|rank  Sortierung
/berufe headers on|off       Kategorie-Überschriften
/berufe ranks on|off         Fertigkeitsstufen anzeigen
/berufe direction auto|up|down   Öffnungsrichtung (auto: unten am Bildschirm nach oben)
/berufe compact off|button|all   Darstellung: mit Text | Knopf nur Symbol | Knopf und Liste nur Symbole
/berufe activities sub|list|off  Tätigkeiten: Untermenü | eigene Kategorie | aus
/berufe camp auto|all|off    Lager: was geht | alles | aus
/berufe unlearned on|off     Platzhalter für nicht erlernte Berufe
/berufe alts [clear]         gemerkte Charaktere und ihre Berufe | die anderen vergessen
/berufe scale 0.5-2          Skalierung (nicht im Kampf)
/berufe unlock | lock        Knopf mit der linken Maustaste verschieben / festsetzen
/berufe reset                Position zurücksetzen
/berufe config               Einstellungsfenster öffnen
/berufe list                 zeigt, welche Berufe und Zauber erkannt wurden
/berufe diag                 schreibt einen Diagnosebericht (siehe unten)
/berufe debug                Meldungen bei Fehlern
```

`/profmenu` ist dasselbe. Das Einstellungsfenster steht unter Spielmenü › Optionen › AddOns › **Berufe-Menü**.

## Wenn etwas nicht geht: `/berufe diag`

Der Befehl sammelt, was das Addon vom Spiel sieht: Version, vorhandene Funktionen, die gelesenen Berufe samt Zaubern
(mit Nummer und „öffnet Fenster“), die gebauten Einträge samt Untermenüs, die Lager-Objekte (Gegenstand, Rezept,
Zustand, Material „vorhanden/nötig“, was das Spiel zu „erlernt“, „benutzbar“ und Abklingzeit sagt) und die
Klick-Einstellungen der ersten Zeile. Das Wichtigste
steht im Chat; der ganze Bericht wird mit `/reload` (oder beim Abmelden) nach
`WTF/Account/<Konto>/SavedVariables/ProfessionMenu.lua` geschrieben (Eintrag `ProfessionMenuDB.diag`). Diese Datei und
eine Fehlermeldung (am besten von BugSack/Swatter, falls vorhanden; sonst der Text des Fehlerfensters) reichen, um den Fehler
einzugrenzen.

## So wird gebaut (für Fehlersuche)

* **Berufe erkennen**: `GetProfessions()` und `GetProfessionInfo(Nummer)` nennen Name, Symbol, Stufe, Fertigkeitszeile
  und die Plätze der Berufszauber im Zauberbuch; die Zauber selbst liefert `C_SpellBook.GetSpellBookItemInfo`. Ob ein
  Zauber ein Berufsfenster öffnet, sagt `C_TradeSkillUI.CanTradeSkillShowCraftingUI` – so arbeitet auch Blizzards
  Berufsbuch. `Data.lua` ergänzt nur Kategorie, Reihenfolge und Namen (Ausweichliste). Einen Beruf, den die Daten nicht
  kennen, zeigt das Addon trotzdem und sortiert ihn nach Art ein (Fenster = Herstellung, Nebenberuf-Platz = Nebenberufe,
  sonst Sammeln).
* **Klick wirkt einen Zauber**: Die Zeilen sind `SecureActionButtons` (`type1=spell`, `spell1=<Zauber-Nummer>`), wie bei
  Aktionsleisten. `C_SpellBook.CastSpellBookItem` und `C_TradeSkillUI.OpenTradeSkill` aus ungeschütztem Code zu rufen wäre
  riskant (nicht belegt, ob sie gesperrt sind); der sichere Knopf braucht das nicht.
* **Klick-Zeitpunkt**: Der Retail-Client löst sichere Knöpfe standardmäßig beim *Niederdrücken* aus (CVar
  `ActionButtonUseKeyDown`). Die Zeilen setzen `useOnKeyDown = false` und reagieren auf das Loslassen, wie ein Menü es
  erwartet. (Quelle: `SecureActionButton_OnClick` in `Blizzard_FrameXML/SecureTemplates.lua`.)
* **Kampfsperre**: Geschützte Rahmen lassen sich im Kampf nicht verschieben, ein-/ausblenden oder umbelegen, ebenso
  ihre Eltern und die Rahmen, an denen sie hängen. Darum ist die Liste ein `SecureHandlerStateTemplate`-Rahmen, der sich
  im Kampf selbst schließt (`[combat]`), nur an `UIParent` verankert (feste Abstände aus der Lage des Knopfes) und nur
  außerhalb des Kampfes umgebaut wird. ESC schließt über einen ungeschützten Stellvertreter (`ProfessionMenuEscProxy` in
  `UISpecialFrames`), nicht über die geschützte Liste.
* **Untermenü**: ein zweiter `SecureHandlerStateTemplate`-Rahmen mit eigenen Zeilen und eigenem `[combat]`-Treiber,
  ebenfalls nur an `UIParent` verankert (Abstände aus der Lage der Liste).
* **Lager**: `Camp.lua` zählt die Taschen Platz für Platz (`C_Container`), bewertet jedes Objekt aus `Data.lua`
  (`PM.CAMP`: Gegenstand, Rezept, Beruf, Fertigkeit, Material) und liefert Einträge. Aufstellen ist die sichere Aktion
  `type1=item`, `item1="item:<Nummer>"`. Herstellen ruft `C_TradeSkillUI.CraftRecipe(Rezept, 1)`; die Zeile trägt dafür
  den Zauber, der das Berufsfenster öffnet. Die Nummern stammen aus den Datentabellen der Addons **FishFry**
  (GildedVellum) und **OneForAll** (Smoergi), beide aus dem Forever-Beta-Client abgelesen.
* **Aussehen**: flache Rahmen im Stil von ElvUI (dunkle Fläche, schwarzer 1-Pixel-Rand, orange Hervorhebung), gebaut
  mit `BackdropTemplate`; alle Maße liegen auf ganzen Bildschirmpixeln. Eine Anbindung an ElvUI gibt es für Forever
  (noch) nicht; die 3.3.5a-Fassung hat sie.

## Nicht im Spiel geprüft

Die Fassung entstand gegen den echten Quelltext der Forever-Oberfläche, **ist aber noch nie im Spiel gelaufen**. Die Tests
laufen gegen eine strenge Attrappe (siehe `tests/`) und beweisen nur, dass der Code zum Quelltext passt. Nur das Spiel
kann bestätigen:

* ob der Interface-Stand `16001` in der TOC stimmt (sonst erscheint das Addon als „veraltet“: *Veraltete Addons laden*
  anhaken und mir den Wert von `/dump (select(4, GetBuildInfo()))` nennen);
* ob die Berufe in den Plätzen und mit den Zaubern ankommen, die `/berufe list` zeigen soll (Spielwert statt Annahme);
* ob ein Klick auf eine Zeile das Berufsfenster öffnet (`type1=spell` mit der Zauber-Nummer) und der Rechtsklick die
  Berufsübersicht zeigt;
* ob das Attribut `useOnKeyDown = false` das Auslösen beim Loslassen so erzwingt, wie der Quelltext es nahelegt;
* ob der Zustandstreiber `[combat]` die Liste im Kampf zuverlässig schließt;
* die Zauber-Nummern der aktiven Fähigkeiten (`Data.lua`, `PM.ABILITIES`): sie stammen aus dem Retail-Client; kennt
  Forever einen Zauber unter anderer Nummer, fehlt die Zeile (die Suchzauber, die im Beruf selbst stehen, erscheinen
  trotzdem);
* **Lager – herstellen**: ob `C_TradeSkillUI.CraftRecipe` direkt nach dem Öffnen des Berufsfensters wirkt (ein Klick)
  oder einen eigenen Tastendruck verlangt (dann zwei Klicks, die Meldung sagt es); ob das Spiel für das offene Fenster
  dieselbe Berufsnummer nennt wie `GetProfessionInfo`; wie sich Sammelberufe und Angeln öffnen lassen;
* **Lager – Daten**: Gegenstands-, Rezept- und Materialnummern stammen aus zwei anderen Addons (Beta-Stand) und können
  sich mit einem Patch ändern. Ob das Rezept **erlernt** ist, prüft das Addon nicht (der Beta-Client beantwortet das
  unzuverlässig): mit Beruf, Fertigkeit und Material erscheint „herstellen“ auch ohne erlerntes Rezept, der Klick
  meldet dann, dass nichts entstand. `/berufe diag` zeigt, was das Spiel zu jedem Objekt sagt;
* **Lager – aufstellen**: ob `item:<Nummer>` als sichere Aktion den Gegenstand benutzt und was `C_Item.IsUsableItem`
  und die Abklingzeit für Lager-Objekte melden;
* **Platzhalter**: ob Forever wirklich zwei Hauptberufe und genau die Nebenberufe Kochkunst, Erste Hilfe und Angeln
  vorsieht (`Data.lua`: `PM.PRIMARY_SLOTS` und das Feld `slot`), ob die neun Hauptberufe mit dem Feld `learn` die sind,
  die es in Forever zu erlernen gibt, und wie der gestrichelte Rahmen aussieht (jeder Strich
  ist eine eigene Fläche auf dem Pixelraster);
* das Untermenü: Lage neben der Liste, Wechsel beim Überfahren, Tooltip daneben;
* das Einstellungsfenster (jedes Bedienelement wird einzeln gebaut; scheitert eines, fehlt nur dieses und der Fehler
  steht im Chat);
* Aussehen und Pixelraster auf deiner Bildschirmgröße und UI-Skalierung, auch die Symbol-Darstellung (`compact`).

## Dateien

```
ProfessionMenu.toc   Interface 16001
Locales.lua    Texte (vollständig: de, en; Titel, Kategorien und Tooltips auch fr, es, ru, ko, zh)
Data.lua       Berufe (Fertigkeitszeile, Kategorie, Namen je Sprache), aktive Fähigkeiten, Lager-Objekte
Core.lua       Einstellungen, Erkennung der Berufe, Aufbau der Liste und der Untermenüs (ohne Oberfläche, testbar)
Camp.lua       Lager: Taschen zählen, Zustand der Objekte, herstellen
Skin.lua       Aussehen: Rahmen, Farben, Schrift, Pixelraster
UI.lua         Knopf, Liste, Untermenü, Zeilen (SecureActionButtons), Kampfsperre
Diag.lua       /berufe diag
Main.lua       Ereignisse, Start, Chatbefehle
Options.lua    Einstellungsfenster (Settings-Schnittstelle des Spiels)
Media/chevron.tga   Pfeil am Knopf und an Zeilen mit Untermenü
README.md      Kurzfassung, Installation
LICENSE        MIT-Lizenz
docs/README.de.md   diese Beschreibung
tests/         strenge Attrappe, Namenskontrolle und Tests:  sh tests/check.sh
```
