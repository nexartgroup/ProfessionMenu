# ProfessionMenu (WoW: Forever)

A small addon for **World of Warcraft: Forever**: a **Professions** button that unrolls a list of the professions you
have learned. Click an entry to open that profession; its activities (smelting, tracking, disenchanting, fishing ...)
sit in a submenu next to it, and the camp objects of WoW: Forever (campfire, tent, fish bowl ...) can be crafted and
placed straight from the list.

> This is the **`forever` branch**: the port to the WoW: Forever client (retail-based engine, interface `16001`).
> The original for WoW **3.3.5a** (with ElvUI integration) lives on the [`main` branch](https://github.com/nexartgroup/ProfessionMenu).

## Features

* Professions grouped by category: Crafting, Processing, Gathering, Secondary (or sorted alphabetically / by skill level).
* **Left-click** opens the profession window (Mining opens Smelting if the game offers it; Herbalism starts the
  tracking search; Fishing casts). **Right-click** opens the professions overview. Skill levels are shown next to the names.
* **Submenus**: a profession with more than one activity shows them in a flyout next to its row - its active spells
  from the spellbook (Mining: Smelting *and* Find Minerals), known abilities that belong to it (Disenchant under
  Enchanting, Prospecting, Milling, Find Fish ...) and its camp objects.
* **Camp** (new in WoW: Forever): all 38 camp objects of the professions (three campfire kits, Camp Tent, Fish Bowl,
  Mana Well, Sharpening Wheel, Lodestone ... and their higher tiers) plus the Cozy Sleeping Bag.
  * In your bags: a click **places** it.
  * Not in your bags, but profession, skill and materials are there: a click **crafts** it (it opens the profession
    first; if the game wants a key press of its own for the craft, a chat message asks for a second click).
  * Materials missing: only the **campfire** (the basic function) stays, dimmed, and tells you what is missing; anything
    else is hidden until it becomes possible.
* **Not learned yet**: free primary profession slots (two in WoW: Forever) and the secondary professions you have
  not learned (Cooking, First Aid, Fishing) show as placeholders - dimmed, with a dashed outline. A click opens the
  professions overview. A free primary slot lists the professions you can still learn in a submenu; a profession that
  another character on your account already has is marked with that character's name (the addon remembers each
  character's professions once it has logged in; `/berufe alts` lists them, `/berufe alts clear` forgets the others).
* Reads the professions from the game itself (`GetProfessions`, the spellbook, `C_TradeSkillUI`), so a profession
  this addon has never heard of still shows up.
* Built for combat lockdown: the entries are secure buttons, the list closes when combat starts and cannot be opened
  during combat.
* Settings panel under *Game Menu > Options > AddOns > Professions menu*, plus chat commands.
* Texts (button title, categories, tooltips) in enUS/enGB, deDE, frFR, esES/esMX, ruRU, koKR, zhCN, zhTW;
  chat messages and the settings panel are English or German only.
* Options:
  * `compact button` - the button is a small icon only;
  * `compact all` - button and list are icon-only (names and skill levels are in the tooltips; submenus keep their text);
  * `activities sub|list|off` - activities as a submenu of the profession (default), as a category of their own (as in
    version 1.0), or not at all;
  * `camp auto|all|off` - camp objects: what can be placed or crafted, campfire always (default); everything, even with
    materials missing; or nothing;
  * `unlearned on|off` - placeholders for professions not learned yet (default: on).

## Installation

1. Copy this folder to `World of Warcraft/_forever_/Interface/AddOns/` so that it is named exactly **`ProfessionMenu`**
   (when you download the ZIP from GitHub, rename `ProfessionMenu-forever` accordingly).
2. Start the game and make sure **Profession Menu** is enabled in the AddOns list. If it shows as "out of date",
   tick *Load out of date AddOns*.

## Commands

`/berufe` (or `/profmenu`) toggles the list.

```
/berufe sort cat|alpha|rank          sorting
/berufe headers on|off               category headings
/berufe ranks on|off                 skill levels
/berufe compact off|button|all       icon-only display
/berufe activities sub|list|off      activities: submenu | own category | off
/berufe camp auto|all|off            camp objects: what works | everything | off
/berufe unlearned on|off             placeholders for professions not learned yet
/berufe alts [clear]                 known characters and their professions | forget the others
/berufe direction auto|up|down       opening direction
/berufe unlock | lock                drag the button with the left mouse button
/berufe scale 0.5-2                  size
/berufe config                       open the settings panel
/berufe list                         show what was detected (professions and their spells)
/berufe diag                         write a diagnostics report (see below)
/berufe reset | debug                reset the position, show error messages
```

## Status - please read

Written against the real source of the Forever interface (the `forever` branch of
[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), version 1.60.1.70862), **not yet run in the game**.
The automated tests run against a strict mock of that API, so they prove that the code is consistent with what the
source says, not that the real client agrees. The camp data (item, recipe and reagent ids) comes from the data tables
of the addons FishFry and OneForAll, which were read from the Forever beta client. The points that only the game can confirm are listed in
[docs/README.de.md](docs/README.de.md) (German). If something does not work, run `/berufe diag`, then `/reload`, and
send the file `WTF/Account/<account>/SavedVariables/ProfessionMenu.lua` (it contains the report) together with any
error message. Written with the help of Claude (Anthropic's AI assistant).

## Tests

Needs [LuaJIT](https://luajit.org/) (a stand-in for the game's Lua 5.1), e.g. `brew install luajit`:

```
sh tests/check.sh
```

Runs the syntax check, a check that the addon uses only global names that exist in the Forever source, and the test suite.

## Deutsch (Kurzfassung)

Ein Knopf **„Berufe“**, der beim Klick eine Liste der erlernten Berufe ausklappt; ein Klick auf einen Beruf öffnet ihn.
Tätigkeiten (Verhütten, Suchen, Entzaubern, Angeln …) stehen in einem Untermenü neben dem Beruf; die Lager-Objekte von
Forever (Lagerfeuer, Zelt, Fischglas …) lassen sich aus der Liste herstellen und aufstellen.
Dieser Zweig (`forever`) ist die Umsetzung für **WoW: Forever**; die Fassung für 3.3.5a steht auf `main`.
Installation: Ordner nach `_forever_/Interface/AddOns/ProfessionMenu` kopieren. Befehl: `/berufe`, Einstellungen unter
Spielmenü › Optionen › AddOns. Ausführliche Beschreibung und die Liste dessen, was nur im Spiel zu prüfen ist:
[docs/README.de.md](docs/README.de.md).

## License

[MIT](LICENSE)
