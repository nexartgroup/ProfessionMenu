-- tests/fixtures.lua
-- ---------------------------------------------------------------------------
-- Gemeinsame Testdaten und Hilfen fuer die ProfessionMenu-Tests.
--
--    local F = require("fixtures")
--    local PM = F.boot(H, { locale = "deDE", learned = { "mining", "herbalism" } })
--
-- F.boot baut aus einer Liste erlernter Berufe konsistente Fertigkeitszeilen (Skills-Fenster mit den
-- ueblichen Ueberschriften) und ein Zauberbuch (Berufszauber, Ortung, Verhuettung) und startet das Addon
-- ueber H.boot (echte TOC). Optionen (alle optional):
--   locale        "enUS" (Standard) | "deDE" | andere (Zaubernamen dann englisch, siehe mock.spellNames)
--   learned       Liste von Schluesseln (F.ORDER) oder Tabelle { mining = { rank, max } }
--   ranks         { mining = { 375, 450 } } -- ueberschreibt Stufe/Maximum
--   collapsed     { Professions = true }    -- Ueberschriften des Skills-Fensters, die zugeklappt starten
--                 (Schluessel sind die ENGLISCHEN Ueberschriften: Professions, Secondary Skills, ...)
--   noSpell       Liste von Schluesseln, deren Berufszauber NICHT im Zauberbuch steht
--   noSmelting    Bergbau ohne Zauber "Verhuettung"
--   noTracking    Bergbau/Kraeuterkunde ohne Ortungszauber
--   extraSkills   { { "Riding", 150, 150, group = "Secondary Skills" } }
--   extraSpells   zusaetzliche Zauber (IDs/Namen) im Zauberbuch
--   spellTabs     Aufteilung des Zauberbuchs auf Reiter: { { name = ..., spells = { ... } } } (statt nur "General")
--   noWeapons     keine Waffen-/Ruestungs-/Sprachzeilen
--   skills, spells  fertige Tabellen (ueberschreiben alles oben)
--   elvui         true | false | "pending" (E.initialized noch nicht wahr) | Tabelle fuer mock.InstallElvUI
--   combat        true: PLAYER_LOGIN im Kampf
--   db            Vorgaben fuer ProfessionMenuDB (SavedVariables vor dem Laden)
--   saved         komplette SavedVariables ({ ProfessionMenuDB = {...} }), z.B. von M.SavedVariables()
--   world         weitere Welt-Angaben fuer mock.world
--   login         false: nur ADDON_LOADED
-- ---------------------------------------------------------------------------

local F = {}

-- Schluessel in der Reihenfolge der Daten (Data.lua)
F.ORDER = {
   "blacksmithing", "leatherworking", "tailoring", "engineering", "alchemy", "inscription",
   "jewelcrafting", "enchanting", "mining", "herbalism", "skinning", "cooking", "firstaid", "fishing",
}

-- Fertigkeitsname (Skills-Fenster) und Berufszauber je Sprache
F.PROFS = {
   blacksmithing = { en = "Blacksmithing", de = "Schmiedekunst", spell = 2018, group = "Professions" },
   leatherworking = { en = "Leatherworking", de = "Lederverarbeitung", spell = 2108, group = "Professions" },
   tailoring = { en = "Tailoring", de = "Schneiderei", spell = 3908, group = "Professions" },
   engineering = { en = "Engineering", de = "Ingenieurskunst", spell = 4036, group = "Professions" },
   alchemy = { en = "Alchemy", de = "Alchemie", spell = 2259, group = "Professions" },
   inscription = { en = "Inscription", de = "Inschriftenkunde", spell = 45357, group = "Professions" },
   jewelcrafting = { en = "Jewelcrafting", de = "Juwelenschleifen", spell = 25229, group = "Professions" },
   enchanting = { en = "Enchanting", de = "Verzauberkunst", spell = 7411, group = "Professions" },
   mining = { en = "Mining", de = "Bergbau", spell = 2575, group = "Professions", extra = { 2656, 2580 },
              smelting = 2656, tracking = 2580 },
   -- Fertigkeit "Herbalism"/"Kraeuterkunde", Zauber "Herb Gathering"/"Kraeutersammeln"
   herbalism = { en = "Herbalism", de = "Kr\195\164uterkunde", spell = 2366, group = "Professions",
                 extra = { 2383 }, tracking = 2383 },
   skinning = { en = "Skinning", de = "K\195\188rschnerei", spell = 8613, group = "Professions" },
   cooking = { en = "Cooking", de = "Kochkunst", spell = 2550, group = "Secondary Skills" },
   firstaid = { en = "First Aid", de = "Erste Hilfe", spell = 3273, group = "Secondary Skills" },
   fishing = { en = "Fishing", de = "Angeln", spell = 7620, group = "Secondary Skills" },
}

-- Ueberschriften des Skills-Fensters je Sprache (nur die Namen aendern sich, nicht die Reihenfolge)
F.GROUPS = {
   { en = "Class Skills", de = "Klassenfertigkeiten" },
   { en = "Professions", de = "Berufe" },
   { en = "Secondary Skills", de = "Nebenberufe" },
   { en = "Weapon Skills", de = "Waffenfertigkeiten" },
   { en = "Armor Proficiencies", de = "R\195\188stungsfertigkeiten" },
   { en = "Languages", de = "Sprachen" },
}

function F.skillName(key, locale)
   local p = F.PROFS[key]
   if locale == "deDE" then return p.de end
   return p.en
end

local function groupName(en, locale)
   for _, g in ipairs(F.GROUPS) do
      if g.en == en then return locale == "deDE" and g.de or g.en end
   end
   return en
end
F.groupName = groupName

local function toSet(list)
   local s = {}
   for _, v in ipairs(list or {}) do s[v] = true end
   return s
end

-- Baut { skills =, spells = } fuer H.boot
function F.build(opts)
   opts = opts or {}
   local locale = opts.locale or "enUS"
   local learned, ranks = {}, {}
   if opts.learned then
      for k, v in pairs(opts.learned) do
         if type(k) == "number" then
            learned[#learned + 1] = v
         else
            learned[#learned + 1] = k
            ranks[k] = v
         end
      end
   end
   for k, v in pairs(opts.ranks or {}) do ranks[k] = v end
   -- in Datenreihenfolge
   local have, list = toSet(learned), {}
   for _, key in ipairs(F.ORDER) do
      if have[key] then list[#list + 1] = key end
   end
   for key in pairs(have) do
      if not F.PROFS[key] then error("fixtures: unknown profession key '" .. tostring(key) .. "'", 2) end
   end

   local lines = {}                       -- group (englisch) -> Zeilen
   local function add(group, line)
      lines[group] = lines[group] or {}
      lines[group][#lines[group] + 1] = line
   end

   if not opts.noWeapons then
      add("Class Skills", { "Defense", 400, 400 })
      add("Weapon Skills", { "Swords", 400, 400 })
      add("Weapon Skills", { "Unarmed", 400, 400 })
      add("Armor Proficiencies", { "Plate Mail", 1, 1 })
      add("Languages", { "Common", 300, 300 })
   end
   for _, key in ipairs(list) do
      local p = F.PROFS[key]
      local r = ranks[key] or { 300, 450 }
      add(p.group, { F.skillName(key, locale), r[1], r[2] })
   end
   for _, extra in ipairs(opts.extraSkills or {}) do
      add(extra.group or "Secondary Skills", { extra[1], extra[2], extra[3] })
   end

   local groups = {}
   for _, g in ipairs(F.GROUPS) do
      local ls = lines[g.en]
      if ls then
         groups[#groups + 1] = { name = groupName(g.en, locale), collapsed = opts.collapsed and opts.collapsed[g.en] or false,
                                 lines = ls }
      end
   end

   -- Zauberbuch
   local noSpell, ids = toSet(opts.noSpell), { "Attack" }
   for _, key in ipairs(list) do
      local p = F.PROFS[key]
      if not noSpell[key] then
         ids[#ids + 1] = p.spell
         for _, extra in ipairs(p.extra or {}) do
            local skip = (extra == p.smelting and opts.noSmelting) or (extra == p.tracking and opts.noTracking)
            if not skip then ids[#ids + 1] = extra end
         end
      end
   end
   for _, x in ipairs(opts.extraSpells or {}) do ids[#ids + 1] = x end

   local spells
   if opts.spellTabs then
      spells = opts.spellTabs
   else
      spells = ids
   end
   return groups, spells
end

-- Startet das Addon. Rueckgabe: PM (Namensraum), M (Attrappe)
function F.boot(H, opts)
   opts = opts or {}
   local skills, spells = F.build(opts)
   if opts.skills then skills = opts.skills end
   if opts.spells then spells = opts.spells end
   local world = { locale = opts.locale or "enUS", combat = opts.combat and true or false }
   for k, v in pairs(opts.world or {}) do world[k] = v end
   local globals = opts.saved
   if opts.db then
      globals = globals or {}
      globals.ProfessionMenuDB = opts.db
   end
   local elvui = opts.elvui
   if elvui == "pending" then elvui = { initialized = false } end
   if elvui == false then elvui = nil end
   local PM = H.boot({
      world = world, skills = skills, spells = spells, elvui = elvui, globals = globals,
      login = opts.login, before = opts.before, beforeLogin = opts.beforeLogin, enterWorld = opts.enterWorld,
   })
   return PM, H.mock
end

-- ---------------------------------------------------------------------------
-- Abfragen
-- ---------------------------------------------------------------------------

-- Sichtbare Zeilen in Anzeigereihenfolge: { row =, entry =, name =, rank =, key = }
function F.rows(PM)
   local out = {}
   for i, row in ipairs(PM.UI.rows) do
      if row:IsShown() and row.entry then
         out[#out + 1] = {
            row = row, entry = row.entry, key = row.entry.key, index = i,
            name = row.text:GetText(), rank = row.rank:GetText(),
         }
      end
   end
   return out
end

function F.rowKeys(PM)
   local out = {}
   for _, r in ipairs(F.rows(PM)) do out[#out + 1] = r.key end
   return out
end

function F.rowNames(PM)
   local out = {}
   for _, r in ipairs(F.rows(PM)) do out[#out + 1] = r.name end
   return out
end

-- Texte der sichtbaren Ueberschriften (in der Reihenfolge der Ueberschrift-Objekte)
function F.headerTexts(PM)
   local out = {}
   for _, h in ipairs(PM.UI.headers) do
      if h.text:IsShown() then out[#out + 1] = h.text:GetText() end
   end
   return out
end

-- Alle sichtbaren Zeilen und Ueberschriften von oben nach unten (nach dem Anker-y)
function F.layoutOrder(PM)
   local items = {}
   for _, r in ipairs(F.rows(PM)) do
      local _, _, _, _, y = r.row:GetPoint(1)
      items[#items + 1] = { kind = "row", key = r.key, y = y, text = r.name }
   end
   for _, h in ipairs(PM.UI.headers) do
      if h.text:IsShown() then
         local _, _, _, _, y = h.text:GetPoint(1)
         -- Der Text sitzt S.gap unter der Oberkante seines Streifens (UI.sizes.gap)
         items[#items + 1] = { kind = "header", y = y + PM.UI.sizes.gap, text = h.text:GetText() }
      end
   end
   table.sort(items, function(a, b) return a.y > b.y end)
   return items
end

function F.open(PM)
   PM.UI.Open()
   return PM.UI.GetMenu():IsShown() and true or false
end

function F.isOpen(PM)
   return PM.UI.GetMenu():IsShown() and true or false
end

-- Chatzeilen, die einen Teilstring enthalten
function F.chatCount(M, text)
   local n = 0
   for _, line in ipairs(M.messages) do
      if string.find(line, text, 1, true) then n = n + 1 end
   end
   return n
end

function F.clearChat(M)
   for i = #M.messages, 1, -1 do M.messages[i] = nil end
end

-- Namen -> true
F.toSet = toSet

-- Stufentext "300/450" in der Zeile
function F.rankOf(rowInfo) return rowInfo.rank end

return F
