# ProfessionMenu

A small **World of Warcraft 3.3.5a** addon: a **Professions** button that unrolls a list of the professions you have
learned. Click an entry to open that profession. With [ElvUI for 3.3.5a](https://github.com/ElvUI-WotLK/ElvUI) loaded it
matches ElvUI's look (templates, font, value colour, pixel grid, mover); without it, it uses its own flat design.

## Features

* Professions grouped by category: Crafting, Processing, Gathering, Secondary (or sorted alphabetically / by skill level).
* **Left-click** opens the profession window (Smelting has its own entry; Mining and Herbalism start the tracking
  search); **right-click** opens the skills window. Skill levels are shown next to the names.
* Built for combat lockdown: the entries are secure buttons, the list closes when combat starts and cannot be opened
  during combat (the closing mechanism is not verified in game yet).
* Profession names, button title, categories and tooltips in enUS/enGB, deDE, frFR, esES/esMX, ruRU, koKR, zhCN, zhTW;
  chat messages and ElvUI options are English or German only.
* Optional settings, all **off** by default:
  * `compact button` - the button is a small icon only;
  * `compact all` - button and list are icon-only (names and skill levels are in the tooltips);
  * `abilities on` - adds a category with your active abilities: Fishing, Disenchant, Prospecting, Milling, Basic
    Campfire and the Find Minerals / Herbs / Fish searches.

## Installation

1. Copy this folder to `World of Warcraft/Interface/AddOns/` so that the folder is named exactly **`ProfessionMenu`**
   (when you download the ZIP from GitHub, rename `ProfessionMenu-main` accordingly).
2. Start the game (a `/reload` does not pick up a newly copied addon) and check that **Profession Menu** is enabled in
   the AddOns list on the character screen.

## Commands

`/berufe` (or `/profmenu`) toggles the list. Settings:

```
/berufe sort cat|alpha|rank          sorting
/berufe headers on|off               category headings
/berufe ranks on|off                 skill levels
/berufe compact off|button|all       icon-only display
/berufe abilities on|off             include active abilities
/berufe direction auto|up|down       opening direction
/berufe list | debug | reset         diagnostics, reset the position
```

Without ElvUI: `/berufe unlock` to drag the button, `/berufe lock`, `/berufe scale 0.5-2`. With ElvUI: move it with
`/moveui` (mover "Professions button", German client: "Berufe-Knopf"); the same settings are under `/ec` in the left
list as "Professions menu" (German: "Berufe-Menü").

## Status

A basic manual check in game (open the list, click professions, change settings) on a German 3.3.5a client with ElvUI
6.09, no systematic in-game testing. The automated tests run against a strict mock of the 3.3.5a client API, not
against a real client. Details, build notes and the points not verified individually in game:
[docs/README.de.md](docs/README.de.md) (German). Written with the help of Claude (Anthropic's AI assistant).

## Tests

Needs [LuaJIT](https://luajit.org/) (a stand-in for the game's Lua 5.1), e.g. `brew install luajit`:

```
bash tests/check.sh
```

Runs syntax, global-variable, locale, style and API-usage checks, then the test suite.

## Deutsch (Kurzfassung)

Ein Knopf **„Berufe“**, der beim Klick eine Liste der erlernten Berufe ausklappt; ein Klick auf einen Beruf öffnet ihn.
Für WoW **3.3.5a**, im Design von ElvUI (läuft auch ohne). Installation: Ordner nach `Interface/AddOns/ProfessionMenu`
kopieren. Befehl: `/berufe`. Optional (standardmäßig aus): kleinere Darstellung nur mit Symbolen
(`/berufe compact button|all`) und aktive Fähigkeiten wie Angeln und Entzaubern in der Liste (`/berufe abilities on`).
Ausführliche Beschreibung: [docs/README.de.md](docs/README.de.md).

## License

[MIT](LICENSE)
