-- Data.lua
-- ---------------------------------------------------------------------------
-- Welche Berufe es gibt und wie sie einsortiert werden (WoW: Forever).
--
-- Die erlernten Berufe liefert das Spiel selbst: GetProfessions() / GetProfessionInfo()
-- nennen Namen, Symbol, Stufe, die Fertigkeitszeile (skillLine) und die Zauber des
-- Berufs im Zauberbuch. Diese Tabelle ergaenzt nur, was das Spiel nicht sagt: die
-- Kategorie, die Reihenfolge und eine Ausweichliste mit Namen (falls eine
-- Fertigkeitszeile hier nicht bekannt ist).
--
-- Felder je Beruf
--   key        Schluessel
--   skillLine  Grund-Fertigkeitszeile (dieselbe Nummer, die GetProfessionInfo liefert)
--   cat        Kategorie: craft | refine | gather | secondary
--   learn      Hauptberuf, den es in Forever zu erlernen gibt (die neun klassischen; fuer genau diese haelt
--              Forever Lager-Objekte bereit): er steht im Untermenue eines freien Hauptberufs
--   slot       Nebenberuf, den in Forever jeder erlernen kann: ist er nicht erlernt, steht dafuer ein
--              Platzhalter in der Liste (Einstellung unlearned)
--   order      Reihenfolge innerhalb der Kategorie
--   names      Berufsnamen je Sprache (nur als Ausweichliste und zum Messen der Knopfbreite)
--   icon       Ausweichsymbol (das Spiel liefert das Symbol selbst)
--   gather     Sammelberuf: seine Zauber ohne Fenster sind Suchzauber ("Ortung")
--   expect     was ein Klick bewirken sollte: window (oeffnet ein Fenster) | use (wirkt)
--   asAbility  Angeln: mit activities = "list" steht es bei den Faehigkeiten statt unter den Nebenberufen
--   abilityOrder  Reihenfolge dort
--
-- Nichts hiervon ist fest verdrahtet: ein Beruf, den die Tabelle nicht kennt, erscheint
-- trotzdem (er kommt aus GetProfessions) und wird nach seiner Art einsortiert.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

-- Kategorien in Anzeigereihenfolge
--   primary    Platzhalter fuer freie Hauptberufe (WoW: Forever: zwei Hauptberufe)
--   camp       Lager (WoW: Forever): Lagerfeuer, Zelt und die anderen Lager-Objekte der Berufe
--   abilities  aktive Faehigkeiten als eigene Kategorie (Einstellung activities = "list") oder solche, deren
--              Beruf nicht in der Liste steht
PM.CATEGORIES = { "craft", "refine", "gather", "primary", "secondary", "camp", "abilities" }

-- So viele Hauptberufe kann ein Charakter in Forever erlernen; die Nebenberufe (Kochkunst, Erste Hilfe,
-- Angeln) tragen unten das Feld slot.
PM.PRIMARY_SLOTS = 2

local ICON = "Interface\\Icons\\"

-- N(en, de, fr, es, ru, ko, cn, tw): Namen je Sprache
local function N(en, de, fr, es, ru, ko, cn, tw)
   return {
      enUS = en, enGB = en, deDE = de, frFR = fr, esES = es, esMX = es,
      ruRU = ru, koKR = ko, zhCN = cn, zhTW = tw,
   }
end

PM.PROFESSIONS = {
   -- Herstellung: Gegenstaende bauen
   { key = "blacksmithing", learn = true, skillLine = 164, cat = "craft", order = 1, expect = "window",
     names = N("Blacksmithing", "Schmiedekunst", "Forge", "Herrería", "Кузнечное дело", "대장기술", "锻造", "鍛造"),
     icon = ICON .. "Trade_BlackSmithing" },
   { key = "leatherworking", learn = true, skillLine = 165, cat = "craft", order = 2, expect = "window",
     names = N("Leatherworking", "Lederverarbeitung", "Travail du cuir", "Peletería", "Кожевничество", "가죽세공", "制皮", "製皮"),
     icon = ICON .. "Trade_LeatherWorking" },
   { key = "tailoring", learn = true, skillLine = 197, cat = "craft", order = 3, expect = "window",
     names = N("Tailoring", "Schneiderei", "Couture", "Sastrería", "Портняжное дело", "재봉술", "裁缝", "裁縫"),
     icon = ICON .. "Trade_Tailoring" },
   { key = "engineering", learn = true, skillLine = 202, cat = "craft", order = 4, expect = "window",
     names = N("Engineering", "Ingenieurskunst", "Ingénierie", "Ingeniería", "Инженерное дело", "기계공학", "工程学", "工程學"),
     icon = ICON .. "Trade_Engineering" },
   { key = "alchemy", learn = true, skillLine = 171, cat = "craft", order = 5, expect = "window",
     names = N("Alchemy", "Alchemie", "Alchimie", "Alquimia", "Алхимия", "연금술", "炼金术", "鍊金術"),
     icon = ICON .. "Trade_Alchemy" },
   { key = "inscription", skillLine = 773, cat = "craft", order = 6, expect = "window",
     names = N("Inscription", "Inschriftenkunde", "Calligraphie", "Inscripción", "Начертание", "주문각인", "铭文", "銘文學"),
     icon = ICON .. "INV_Inscription_Tradeskill01" },

   -- Weiterverarbeitung: Rohstoffe und Gegenstaende veredeln
   { key = "jewelcrafting", skillLine = 755, cat = "refine", order = 1, expect = "window",
     names = N("Jewelcrafting", "Juwelenschleifen", "Joaillerie", "Joyería", "Ювелирное дело", "보석세공", "珠宝加工", "珠寶設計"),
     icon = ICON .. "INV_Misc_Gem_01" },
   { key = "enchanting", learn = true, skillLine = 333, cat = "refine", order = 2, expect = "window",
     names = N("Enchanting", "Verzauberkunst", "Enchantement", "Encantamiento", "Наложение чар", "마법부여", "附魔", "附魔"),
     icon = ICON .. "Trade_Engraving" },

   -- Sammeln: Rohstoffe finden (Bergbau oeffnet das Schmelzfenster, falls das Spiel eines hat)
   { key = "mining", learn = true, skillLine = 186, cat = "gather", order = 1, gather = true,
     names = N("Mining", "Bergbau", "Minage", "Minería", "Горное дело", "채광", "采矿", "採礦"),
     icon = ICON .. "Trade_Mining" },
   { key = "herbalism", learn = true, skillLine = 182, cat = "gather", order = 2, gather = true,
     names = N("Herbalism", "Kräuterkunde", "Herboristerie", "Herboristería", "Травничество", "약초채집", "草药学", "草藥學"),
     icon = ICON .. "Trade_Herbalism" },
   { key = "skinning", learn = true, skillLine = 393, cat = "gather", order = 3, gather = true,
     names = N("Skinning", "Kürschnerei", "Dépeçage", "Desollar", "Снятие шкур", "무두질", "剥皮", "剝皮"),
     icon = ICON .. "INV_Misc_Pelt_Wolf_01" },

   -- Nebenberufe
   { key = "cooking", skillLine = 185, cat = "secondary", order = 1, expect = "window", slot = true,
     names = N("Cooking", "Kochkunst", "Cuisine", "Cocina", "Кулинария", "요리", "烹饪", "烹飪"),
     icon = ICON .. "INV_Misc_Food_15" },
   { key = "firstaid", skillLine = 129, cat = "secondary", order = 2, expect = "window", slot = true,
     names = N("First Aid", "Erste Hilfe", "Secourisme", "Primeros auxilios", "Первая помощь", "응급치료", "急救", "急救"),
     icon = ICON .. "Spell_Holy_SealOfSacrifice" },
   { key = "fishing", skillLine = 356, cat = "secondary", order = 3, expect = "use", slot = true,
     names = N("Fishing", "Angeln", "Pêche", "Pesca", "Рыбная ловля", "낚시", "钓鱼", "釣魚"),
     icon = ICON .. "Trade_Fishing", asAbility = true, abilityOrder = 1 },
   { key = "archaeology", skillLine = 794, cat = "secondary", order = 4,
     names = N("Archaeology", "Archäologie", "Archéologie", "Arqueología", "Археология", "고고학", "考古学", "考古學"),
     icon = ICON .. "Trade_Archaeology" },
}

-- Aktive Faehigkeiten: Zauber, die ein Klick wirkt. Ein Eintrag erscheint nur, wenn der Spieler den Zauber
-- kennt; Namen und (falls hier keines steht) Symbole liefert das Spiel. Die Zauber-Nummern sind die des
-- Retail-Clients; kennt Forever einen davon nicht, fehlt die Zeile einfach.
--   kind  use (wirkt sofort) | target (danach einen Gegenstand anklicken) | tracking (Suche) | window (oeffnet ein Fenster)
--   prof  Beruf, zu dem die Faehigkeit gehoert: mit activities = "sub" steht sie in dessen Untermenue
PM.ABILITIES = {
   -- Schmelzen: der Zauber oeffnet das Schmelzfenster. Steht er nicht im Berufsabschnitt des Zauberbuchs
   -- (Forever fuehrt ihn getrennt), bleibt das Verhuetten sonst unsichtbar.
   { key = "smelting", spell = 2656, kind = "window", order = 1, prof = "mining",
     icon = ICON .. "Spell_Fire_FlameBlades" },
   { key = "disenchant", spell = 13262, kind = "target", order = 2, prof = "enchanting",
     icon = ICON .. "INV_Enchant_Disenchant" },
   { key = "prospecting", spell = 31252, kind = "target", order = 3, prof = "jewelcrafting",
     icon = ICON .. "INV_Misc_Gem_BloodGem_01" },
   { key = "milling", spell = 51005, kind = "target", order = 4, prof = "inscription",
     icon = ICON .. "Ability_Miling" },
   { key = "campfire", spell = 818, kind = "use", order = 5, prof = "cooking",
     icon = ICON .. "Spell_Fire_Fire" },
   { key = "findminerals", spell = 2580, kind = "tracking", order = 6, prof = "mining",
     icon = ICON .. "Spell_Nature_Earthquake" },
   { key = "findherbs", spell = 2383, kind = "tracking", order = 7, prof = "herbalism",
     icon = ICON .. "INV_Misc_Flower_02" },
   { key = "findfish", spell = 43308, kind = "tracking", order = 8, prof = "fishing",
     icon = ICON .. "INV_Misc_Fish_02" },
   { key = "survey", spell = 80451, kind = "use", order = 9, prof = "archaeology",
     icon = ICON .. "INV_Misc_Shovel_01" },
}

-- ---------------------------------------------------------------------------
-- Lager (WoW: Forever)
--
-- Forever gibt jedem Beruf Lager-Objekte: das Lagerfeuer (Kochkunst) und Dinge, die man daneben aufstellt
-- (Zelt, Fischglas, Manabrunnen ...). Jedes ist ein Gegenstand, den ein Rezept des Berufs herstellt und den
-- man danach aus der Tasche aufstellt. Je Beruf gibt es drei Stufen (Fertigkeit 20 / 140 / 300), die hoehere
-- schliesst die Wirkung der niedrigeren ein.
--
-- Quelle der Nummern: die Datentabellen der Addons FishFry (GildedVellum) und OneForAll (Smoergi), beide aus
-- dem Forever-Beta-Client abgelesen. Namen und Symbole liefert das Spiel; "name" ist nur der Ausweichtext,
-- bis der Client den Gegenstand geladen hat.
--
-- Felder
--   key        Schluessel
--   chain      Kette: Stufen desselben Objekts (in der Kategorie "Lager" steht je Kette nur die beste Zeile)
--   tier       Stufe innerhalb der Kette
--   prof       Beruf (Schluessel aus PM.PROFESSIONS), dessen Rezept das Objekt herstellt
--   skill      noetige Fertigkeit
--   item       Gegenstand (items: mehrere moegliche, etwa das Banner je Fraktion)
--   recipe     Rezept-Zauber (recipes: je Fraktion)
--   reagents   Material: { Gegenstand, Anzahl }
--   tool       Werkzeug, das im Inventar liegen muss (wird nicht verbraucht)
--   important  Grundfunktion: erscheint auch, wenn Material fehlt (mit Hinweis)
--   bagOnly    kein Rezept: erscheint nur, wenn der Gegenstand im Inventar liegt
-- ---------------------------------------------------------------------------

local function C(key, chain, tier, prof, skill, item, recipe, name, reagents, extra)
   local def = { key = key, chain = chain, tier = tier, prof = prof, skill = skill, item = item, recipe = recipe,
      name = name, reagents = reagents or {} }
   for k, v in pairs(extra or {}) do def[k] = v end
   return def
end

PM.CAMP = {
   -- Kochkunst: das Lagerfeuer (Grundlage des Lagers) und was darauf gekocht wird
   C("fire1", "fire", 1, "cooking", 1, 279981, 1229737, "Basic Campfire Kit", { { 4470, 1 } },
      { tool = 4471, important = true }),
   C("fire2", "fire", 2, "cooking", 90, 279961, 1283400, "Journeyman Campfire Kit", { { 11291, 1 } }),
   C("fire3", "fire", 3, "cooking", 200, 279974, 1291341, "Expert Campfire Kit", { { 272941, 1 } }),
   C("feast", "feast", 1, "cooking", 140, 279957, 1262978, "Cookie's Feast", { { 12037, 2 }, { 12204, 1 }, { 3713, 1 } }),
   C("oven", "oven", 1, "cooking", 300, 279982, 1263067, "Iron Oven", { { 10284, 10 }, { 159, 5 }, { 3713, 4 } }),

   C("alchemy1", "alchemy", 1, "alchemy", 20, 279956, 1230564, "Mana Well", { { 2447, 1 }, { 3371, 1 } }),
   C("alchemy2", "alchemy", 2, "alchemy", 140, 279970, 1263005, "Fermenter", { { 3372, 1 }, { 3356, 1 }, { 2452, 1 } }),
   C("alchemy3", "alchemy", 3, "alchemy", 300, 279990, 1263078, "Alchemy Laboratory", { { 273125, 1 }, { 8925, 1 }, { 13463, 2 } }),

   C("blacksmithing1", "blacksmithing", 1, "blacksmithing", 20, 279944, 1230171, "Sharpening Wheel", { { 2835, 1 }, { 2840, 1 } }),
   C("blacksmithing2", "blacksmithing", 2, "blacksmithing", 140, 279988, 1263041, "Anvil", { { 2841, 5 }, { 3478, 2 }, { 2319, 2 } }),
   C("blacksmithing3", "blacksmithing", 3, "blacksmithing", 300, 279955, 1263073, "Master Forge", { { 273127, 1 }, { 12359, 5 }, { 8170, 2 } }),

   C("enchanting1", "enchanting", 1, "enchanting", 20, 279976, 1230643, "Enchanted Lute", { { 4470, 1 }, { 10940, 1 } }),
   C("enchanting2", "enchanting", 2, "enchanting", 140, 279985, 1263056, "Arcane Salvager", { { 11137, 2 }, { 11174, 1 } }),
   C("enchanting3", "enchanting", 3, "enchanting", 300, 279987, 1263082, "Arcane Forge", { { 273128, 1 }, { 14344, 2 }, { 16203, 4 } }),

   C("engineering1", "engineering", 1, "engineering", 20, 279950, 1230656, "Reagent Bot", { { 4359, 1 }, { 4361, 1 } }),
   C("engineering2", "engineering", 2, "engineering", 140, 279949, 1263034, "Repair Bot", { { 4375, 2 }, { 4371, 1 }, { 4234, 1 } }),
   C("engineering3", "engineering", 3, "engineering", 300, 279989, 1263083, "Anarchist's Workbench", { { 273129, 1 }, { 15994, 2 } }),

   C("leatherworking1", "leatherworking", 1, "leatherworking", 20, 279978, 1229432, "Camp Tent", { { 2318, 5 } }),
   C("leatherworking2", "leatherworking", 2, "leatherworking", 140, 279941, 1263031, "Tanning Rack", { { 2319, 5 }, { 2321, 3 }, { 4470, 2 } }),
   C("leatherworking3", "leatherworking", 3, "leatherworking", 300, 279945, 1263079, "Sewing Machine", { { 273130, 1 }, { 8170, 5 }, { 14341, 1 } }),

   -- Banner: je Fraktion ein Gegenstand und ein Rezept (Horde 279972 / 1229504, Allianz 279973 / 1263425)
   C("tailoring1", "tailoring", 1, "tailoring", 20, 279972, 1229504, "Faction Banner", { { 2996, 1 }, { 2320, 1 } },
      { items = { Horde = 279972, Alliance = 279973 }, recipes = { Horde = 1229504, Alliance = 1263425 } }),
   C("tailoring2", "tailoring", 2, "tailoring", 140, 279943, 1263032, "Spinning Wheel", { { 4470, 2 }, { 4305, 5 }, { 2321, 3 } }),
   C("tailoring3", "tailoring", 3, "tailoring", 300, 279959, 1263080, "Loom", { { 273131, 1 }, { 14048, 4 }, { 4470, 4 } }),

   -- Sammelberufe (Material aus FishFry: dort stehen nur Namen, die Nummern sind die der Classic-Gegenstaende)
   C("mining1", "mining", 1, "mining", 20, 279960, 1230161, "Lodestone", { { 2835, 1 }, { 2840, 1 } }),
   C("mining2", "mining", 2, "mining", 140, 279948, 1262975, "Rock Garden", { { 2838, 2 }, { 2772, 1 }, { 2842, 1 } }),
   C("mining3", "mining", 3, "mining", 300, 279952, 1263071, "Molten Foundry", { { 12359, 5 }, { 12365, 2 }, { 6037, 1 } }),

   C("herbalism1", "herbalism", 1, "herbalism", 20, 279962, 1229705, "Incense Candle", { { 2447, 1 }, { 765, 1 } }),
   C("herbalism2", "herbalism", 2, "herbalism", 140, 279964, 1262980, "Greenhouse", { { 4470, 2 }, { 8836, 1 }, { 8831, 1 } }),
   C("herbalism3", "herbalism", 3, "herbalism", 300, 279947, 1263070, "Seed Hybridizer", { { 13465, 4 }, { 8925, 1 }, { 14047, 2 } }),

   C("skinning1", "skinning", 1, "skinning", 20, 279979, 1229517, "Camp Chair", { { 2318, 3 }, { 4470, 2 } }),
   C("skinning2", "skinning", 2, "skinning", 140, 279969, 1262985, "Field Guide", { { 2319, 3 }, { 5784, 2 }, { 2321, 1 } }),
   C("skinning3", "skinning", 3, "skinning", 300, 279938, 1262982, "Trapper's Workbench", { { 4470, 2 }, { 4234, 4 }, { 2575, 1 } }),

   C("firstaid1", "firstaid", 1, "firstaid", 20, 279968, 1230117, "First Aid Kit", { { 1251, 3 }, { 159, 1 } }),
   C("firstaid2", "firstaid", 2, "firstaid", 140, 279940, 1262996, "Toxin Study", { { 6452, 1 }, { 8544, 2 }, { 4470, 2 } }),
   C("firstaid3", "firstaid", 3, "firstaid", 300, 279951, 1263001, "Plague Doctor's Laboratory", { { 4470, 2 }, { 6453, 2 }, { 14530, 5 } }),

   C("fishing1", "fishing", 1, "fishing", 20, 279967, 1229745, "Fish Bowl", { { 6291, 1 }, { 3371, 1 } }),
   C("fishing2", "fishing", 2, "fishing", 140, 279965, 1262990, "Fishing Rack", { { 4470, 2 }, { 8925, 1 }, { 8365, 2 } }),
   C("fishing3", "fishing", 3, "fishing", 300, 279966, 1262998, "Fishing Hut", { { 4470, 5 }, { 14048, 2 }, { 273295, 1 } }),

   -- Gemuetlicher Schlafsack: kein Rezept, nur aus der Tasche
   C("sleepingbag", "sleepingbag", 1, nil, 0, 211527, nil, "Cozy Sleeping Bag", nil, { bagOnly = true }),
}

-- Ausweichsymbole, bis das Spiel das Symbol des Gegenstands liefert
PM.CAMP_ICON = ICON .. "INV_Misc_Bag_10"
PM.CAMP_FIRE_ICON = ICON .. "Spell_Fire_Fire"

-- Symbol eines freien Hauptberufs (die Schriftrolle, die auch Blizzards Berufsbuch dafuer zeigt)
PM.OPEN_ICON = ICON .. "INV_Scroll_04"

-- Symbol des Knopfes: der Hammer auf dem Amboss (Schmiedekunst)
PM.BUTTON_ICON = ICON .. "Trade_BlackSmithing"

PM.PROFESSION_BY_KEY = {}
PM.PROFESSION_BY_SKILLLINE = {}
for _, def in ipairs(PM.PROFESSIONS) do
   PM.PROFESSION_BY_KEY[def.key] = def
   PM.PROFESSION_BY_SKILLLINE[def.skillLine] = def
end

PM.ABILITY_BY_SPELL = {}
for _, def in ipairs(PM.ABILITIES) do
   PM.ABILITY_BY_SPELL[def.spell] = def
end

PM.CAMP_BY_KEY = {}
for _, def in ipairs(PM.CAMP) do
   PM.CAMP_BY_KEY[def.key] = def
end
