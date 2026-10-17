-- Data.lua
-- ---------------------------------------------------------------------------
-- Welche Berufe es gibt, wie sie einsortiert werden und was ein Klick tut.
--
-- Berufe erkennt das Addon an den Fertigkeiten (GetSkillLineInfo), deren Namen in
-- der Sprache des Clients dastehen. Die Namen unten stammen aus den Client-Daten
-- (SkillLine.dbc der Sprach-MPQs bzw. dem mehrsprachigen Spell.dbc) und sind fuer
-- enUS, deDE, frFR, esES und ruRU direkt aus dem Client gelesen, fuer koKR, zhCN und
-- zhTW indirekt (Zaubername = Fertigkeitsname, gegen Tooltips und Addon-Dateien
-- geprueft). esMX teilt die spanischen Namen.
--
-- Zusaetzlich zaehlen die Namen der Zauber in "spells" (GetSpellInfo, Sprache des
-- Clients). Das faengt Clients ab, deren Namen hier fehlen. Ausnahme-Beruf ist die
-- Kraeuterkunde: ihr Zauber heisst anders ("Kraeutersammeln"), doch Zauber 9134
-- ("Herbalism", ein Hilfszauber) traegt in allen geprueften Sprachen exakt den
-- Namen der Fertigkeit.
--
-- Felder je Beruf
--   key     Schluessel
--   cat     Kategorie: craft | refine | gather | secondary
--   order   Reihenfolge innerhalb der Kategorie
--   names   Fertigkeitsnamen je Sprache
--   spells  Zauber-IDs, deren Name (in der Sprache des Clients) dem der Fertigkeit entspricht
--   open    Zauber-IDs, die ein Klick wirkt (der erste im Zauberbuch gilt)
--   kind    window (oeffnet ein Fenster) | tracking (Ortung) | use (wirkt) | target (wirkt, danach einen
--           Gegenstand anklicken; nur bei den Faehigkeiten) | none (nichts zu wirken)
--   icon    Symbol (Datei aus SpellIcon.dbc)
--   from    nur bei abgeleiteten Eintraegen (Verhuettung): Beruf, dessen Stufe gilt
--   spell   nur dort: der Zauber des Eintrags selbst
--   asAbility  Angeln: mit "aktive Faehigkeiten" steht es dort statt unter den Nebenberufen
--
-- Welcher Zauber ein Fenster oeffnet, steht in Spell.dbc: nur Zauber mit Effekt 47
-- (TRADE_SKILL). Bergbau, Kraeutersammeln und Kuerschnerei haben keinen (sie wirken
-- auf Weltobjekte bzw. Leichen), deshalb wirkt ein Klick dort die Ortung; das
-- Schmelzfenster oeffnet nur "Verhuettung" (2656).
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

-- Kategorien in Anzeigereihenfolge ("abilities" nur mit der Einstellung "aktive Faehigkeiten")
PM.CATEGORIES = { "craft", "refine", "gather", "secondary", "abilities" }

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
   { key = "blacksmithing", cat = "craft", order = 1, spells = { 2018 },
     names = N("Blacksmithing", "Schmiedekunst", "Forge", "Herrería", "Кузнечное дело", "대장기술", "锻造", "鍛造"),
     open = { 2018 }, kind = "window", icon = ICON .. "Trade_BlackSmithing" },
   { key = "leatherworking", cat = "craft", order = 2, spells = { 2108 },
     names = N("Leatherworking", "Lederverarbeitung", "Travail du cuir", "Peletería", "Кожевничество", "가죽세공", "制皮", "製皮"),
     open = { 2108 }, kind = "window", icon = ICON .. "Trade_LeatherWorking" },
   { key = "tailoring", cat = "craft", order = 3, spells = { 3908 },
     names = N("Tailoring", "Schneiderei", "Couture", "Sastrería", "Портняжное дело", "재봉술", "裁缝", "裁縫"),
     open = { 3908 }, kind = "window", icon = ICON .. "Trade_Tailoring" },
   { key = "engineering", cat = "craft", order = 4, spells = { 4036 },
     names = N("Engineering", "Ingenieurskunst", "Ingénierie", "Ingeniería", "Инженерное дело", "기계공학", "工程学", "工程學"),
     open = { 4036 }, kind = "window", icon = ICON .. "Trade_Engineering" },
   { key = "alchemy", cat = "craft", order = 5, spells = { 2259 },
     names = N("Alchemy", "Alchemie", "Alchimie", "Alquimia", "Алхимия", "연금술", "炼金术", "鍊金術"),
     open = { 2259 }, kind = "window", icon = ICON .. "Trade_Alchemy" },
   { key = "inscription", cat = "craft", order = 6, spells = { 45357 },
     names = N("Inscription", "Inschriftenkunde", "Calligraphie", "Inscripción", "Начертание", "주문각인", "铭文", "銘文學"),
     open = { 45357 }, kind = "window", icon = ICON .. "INV_Inscription_Tradeskill01" },

   -- Weiterverarbeitung: Rohstoffe und Gegenstaende veredeln
   { key = "smelting", cat = "refine", order = 1, from = "mining", spell = 2656,
     open = { 2656 }, kind = "window", icon = ICON .. "Spell_Fire_FlameBlades" },
   { key = "jewelcrafting", cat = "refine", order = 2, spells = { 25229 },
     names = N("Jewelcrafting", "Juwelenschleifen", "Joaillerie", "Joyería", "Ювелирное дело", "보석세공", "珠宝加工", "珠寶設計"),
     open = { 25229 }, kind = "window", icon = ICON .. "INV_Misc_Gem_01" },
   { key = "enchanting", cat = "refine", order = 3, spells = { 7411 },
     names = N("Enchanting", "Verzauberkunst", "Enchantement", "Encantamiento", "Наложение чар", "마법부여", "附魔", "附魔"),
     open = { 7411 }, kind = "window", icon = ICON .. "Trade_Engraving" },

   -- Sammeln: Rohstoffe finden
   { key = "mining", cat = "gather", order = 1, spells = { 2575 },
     names = N("Mining", "Bergbau", "Minage", "Minería", "Горное дело", "채광", "采矿", "採礦"),
     open = { 2580 }, kind = "tracking", icon = ICON .. "Trade_Mining" },
   { key = "herbalism", cat = "gather", order = 2, spells = { 9134, 2366 },
     names = N("Herbalism", "Kräuterkunde", "Herboristerie", "Herboristería", "Травничество", "약초채집", "草药学", "草藥學"),
     open = { 2383 }, kind = "tracking", icon = ICON .. "Trade_Herbalism" },
   { key = "skinning", cat = "gather", order = 3, spells = { 8613 },
     names = N("Skinning", "Kürschnerei", "Dépeçage", "Desollar", "Снятие шкур", "무두질", "剥皮", "剝皮"),
     open = {}, kind = "none", icon = ICON .. "INV_Misc_Pelt_Wolf_01" },

   -- Nebenberufe
   { key = "cooking", cat = "secondary", order = 1, spells = { 2550 },
     names = N("Cooking", "Kochkunst", "Cuisine", "Cocina", "Кулинария", "요리", "烹饪", "烹飪"),
     open = { 2550 }, kind = "window", icon = ICON .. "INV_Misc_Food_15" },
   { key = "firstaid", cat = "secondary", order = 2, spells = { 3273 },
     names = N("First Aid", "Erste Hilfe", "Secourisme", "Primeros auxilios", "Первая помощь", "응급치료", "急救", "急救"),
     open = { 3273 }, kind = "window", icon = ICON .. "Spell_Holy_SealOfSacrifice" },
   { key = "fishing", cat = "secondary", order = 3, spells = { 7620 },
     names = N("Fishing", "Angeln", "Pêche", "Pesca", "Рыбная ловля", "낚시", "钓鱼", "釣魚"),
     open = { 7620 }, kind = "use", icon = ICON .. "Trade_Fishing", asAbility = true },
}

-- Aktive Faehigkeiten (Einstellung "abilities"): Zauber, die ein Klick wirkt, kein Fenster oeffnen
-- und bei denen es keine Fertigkeitszeile gibt. Ein Eintrag erscheint nur, wenn der Zauber im
-- Zauberbuch steht (Entzaubern lernt man mit der Verzauberkunst, Sondieren beim Lehrer
-- (Juwelenschleifen 20), Mahlen mit der Inschriftenkunde, das Lagerfeuer mit der Kochkunst,
-- Fischsuche durch den Gegenstand "Verwittertes Tagebuch" (Item 34109, Angeln 100, Beute beim Angeln)).
-- Namen kommen vom Spiel (GetSpellInfo), Symbole aus SpellIcon.dbc.
--   kind  use (wirkt sofort) | target (danach einen Gegenstand anklicken) | tracking (Suche)
--   rankFrom  nur Angeln: zeigt die Stufe dieser Fertigkeit
-- Mit der Einstellung wirken Bergbau und Kraeuterkunde nicht mehr selbst als Suche (die
-- Suchzauber stehen dann hier), und Angeln steht hier statt bei den Nebenberufen.
PM.ABILITIES = {
   { key = "fishing", cat = "abilities", order = 1, spell = 7620, kind = "use",
     icon = ICON .. "Trade_Fishing", rankFrom = "fishing" },
   { key = "disenchant", cat = "abilities", order = 2, spell = 13262, kind = "target",
     icon = ICON .. "INV_Enchant_Disenchant" },
   { key = "prospecting", cat = "abilities", order = 3, spell = 31252, kind = "target",
     icon = ICON .. "INV_Misc_Gem_BloodGem_01" },
   { key = "milling", cat = "abilities", order = 4, spell = 51005, kind = "target",
     icon = ICON .. "Ability_Miling" },                      -- so steht es in SpellIcon.dbc
   { key = "campfire", cat = "abilities", order = 5, spell = 818, kind = "use",
     icon = ICON .. "Spell_Fire_Fire" },
   { key = "findminerals", cat = "abilities", order = 6, spell = 2580, kind = "tracking",
     icon = ICON .. "Spell_Nature_Earthquake" },
   { key = "findherbs", cat = "abilities", order = 7, spell = 2383, kind = "tracking",
     icon = ICON .. "INV_Misc_Flower_02" },
   { key = "findfish", cat = "abilities", order = 8, spell = 43308, kind = "tracking",
     icon = ICON .. "INV_Misc_Fish_02" },
}

-- Spanisch: die Fertigkeit heisst "Desollar", der Zauber "Desuello" (der Zaubername
-- gilt ueber "spells" ohnehin; so steht auch der feste Name beider Formen da)
for _, def in ipairs(PM.PROFESSIONS) do
   if def.key == "skinning" then def.names.esESalt = "Desuello" end
end

-- Symbol des Knopfes: der Hammer auf dem Amboss (Schmiedekunst)
PM.BUTTON_ICON = ICON .. "Trade_BlackSmithing"

PM.PROFESSION_BY_KEY = {}
for _, def in ipairs(PM.PROFESSIONS) do
   PM.PROFESSION_BY_KEY[def.key] = def
end
