-- Core.lua
-- ---------------------------------------------------------------------------
-- Einstellungen, Erkennung der erlernten Berufe, Aufbau der Liste.
-- Nichts hier fasst Oberflaeche an: PM.Collect() liefert reine Daten, die
-- UI.lua zeichnet. So laesst sich die Erkennung ohne Spiel testen.
--
-- WoW: Forever (Retail-Technik): die Berufe liefert GetProfessions() /
-- GetProfessionInfo(), die Zauber eines Berufs stehen im Zauberbuch
-- (C_SpellBook), und ob ein Zauber ein Berufsfenster oeffnet, sagt
-- C_TradeSkillUI.CanTradeSkillShowCraftingUI. So arbeitet auch Blizzards
-- eigenes Berufsbuch.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local strlower, format, tsort = string.lower, string.format, table.sort

PM.version = "1.1-forever"

-- ---------------------------------------------------------------------------
-- Einstellungen (SavedVariables: ProfessionMenuDB)
-- ---------------------------------------------------------------------------

local DEFAULTS = {
   sort = "cat",          -- cat | alpha | rank
   headers = true,        -- Kategorie-Ueberschriften zeigen (nur bei Sortierung nach Kategorie)
   ranks = true,          -- Fertigkeitsstufe rechts in der Zeile
   direction = "auto",    -- auto | up | down
   compact = "off",       -- off | button (Knopf nur Symbol) | all (Knopf und Liste nur Symbole)
   -- Taetigkeiten der Berufe (Entzaubern, Suchen, Angeln, Lager-Objekte ...):
   --   sub   als Untermenue des Berufs | list  als eigene Kategorie "Faehigkeiten" | off  gar nicht
   activities = "sub",
   -- Lager (Lagerfeuer, Zelt ...): auto  was aufstellbar oder herstellbar ist (das Lagerfeuer immer) |
   --   all  auch, wofuer Material fehlt | off  nichts
   camp = "auto",
   unlearned = true,      -- Platzhalter fuer nicht erlernte Berufe (freie Hauptberufe, fehlende Nebenberufe)
   scale = 1,
   locked = true,         -- Knopf verschiebbar?
}

PM.DEFAULTS = DEFAULTS

local VALID = {
   sort = { cat = true, alpha = true, rank = true },
   direction = { auto = true, up = true, down = true },
   compact = { off = true, button = true, all = true },
   activities = { sub = true, list = true, off = true },
   camp = { auto = true, all = true, off = true },
}
local POINTS = {
   TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
   RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Gespeicherte Werte pruefen: kaputte oder von Hand geaenderte SavedVariables duerfen
-- den Start nicht verhindern (ein ungueltiger Anker oder eine Skalierung 0 wuerde
-- beim Bauen der Oberflaeche einen Fehler werfen).
local function Sanitize(db)
   for key, allowed in pairs(VALID) do
      if not allowed[db[key]] then db[key] = DEFAULTS[key] end
   end
   db.abilities = nil     -- bis 1.0: an/aus; ersetzt durch activities
   for _, key in ipairs({ "headers", "ranks", "locked", "unlearned" }) do
      if type(db[key]) ~= "boolean" then db[key] = DEFAULTS[key] end
   end
   local scale = tonumber(db.scale)
   if not scale or scale ~= scale or scale < 0.5 or scale > 2 then scale = DEFAULTS.scale end
   db.scale = scale
   local pos = db.pos
   if pos ~= nil then
      local good = type(pos) == "table" and POINTS[pos.point] and (pos.relPoint == nil or POINTS[pos.relPoint])
         and type(pos.x) == "number" and type(pos.y) == "number"
         and pos.x == pos.x and pos.y == pos.y and pos.x > -1e5 and pos.x < 1e5 and pos.y > -1e5 and pos.y < 1e5
      if not good then db.pos = nil end
   end
   if db.diag ~= nil and type(db.diag) ~= "table" then db.diag = nil end
   -- gemerkte Charaktere: nur vollstaendige Eintraege behalten
   if type(db.chars) ~= "table" then db.chars = {} end
   for id, char in pairs(db.chars) do
      local good = type(id) == "string" and type(char) == "table" and type(char.name) == "string"
         and type(char.realm) == "string" and type(char.profs) == "table"
      if good then
         for key, rank in pairs(char.profs) do
            if type(key) ~= "string" or type(rank) ~= "number" then char.profs[key] = nil end
         end
      else
         db.chars[id] = nil
      end
   end
end

-- Stehen aktive Faehigkeiten als eigene Kategorie in der Liste (activities = "list")?
local function ListMode(db) return db.activities == "list" end
-- ... oder als Untermenue des Berufs (activities = "sub")?
local function SubMode(db) return db.activities == "sub" end

function PM.InitDB()
   if type(_G.ProfessionMenuDB) ~= "table" then
      _G.ProfessionMenuDB = {}
   end
   local db = _G.ProfessionMenuDB
   for key, value in pairs(DEFAULTS) do
      if db[key] == nil then db[key] = value end
   end
   Sanitize(db)
   PM.db = db
   return db
end

-- Vor ADDON_LOADED (und in Tests ohne Init) gelten die Voreinstellungen.
PM.db = setmetatable({}, { __index = DEFAULTS })

-- ---------------------------------------------------------------------------
-- Meldungen und Fehler
-- ---------------------------------------------------------------------------

local reported = {}
PM.errors = {}

function PM.Print(msg)
   if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff7b2cProfessionMenu|r " .. tostring(msg))
   end
end

function PM.Trace(...)
   if PM.debug then
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      PM.Print("|cff888888" .. table.concat(parts, " ") .. "|r")
   end
end

-- Einen Fehler einmal melden (im Debug-Modus immer) und fuer /berufe diag merken.
function PM.ReportOnce(name, err)
   local errors = PM.errors
   errors[#errors + 1] = tostring(name) .. ": " .. tostring(err)
   if #errors > 20 then table.remove(errors, 1) end
   if PM.debug or not reported[name] then
      reported[name] = true
      PM.Print(format(PM.L.error, name, tostring(err)))
   end
end

-- Fehler in Haken und Ereignissen: einmal melden, weiterlaufen.
function PM.Guard(name, fn)
   return function(...)
      local ok, err = pcall(fn, ...)
      if not ok then PM.ReportOnce(name, err) end
   end
end

-- ---------------------------------------------------------------------------
-- Zugriff auf das Spiel (jeder Aufruf geschuetzt: ein Fehler darf die Liste nie verhindern)
-- ---------------------------------------------------------------------------

local function PlayerBank()
   local enum = _G.Enum
   return enum and enum.SpellBookSpellBank and enum.SpellBookSpellBank.Player or 0
end

local function SpellType()
   local enum = _G.Enum
   return enum and enum.SpellBookItemType and enum.SpellBookItemType.Spell or 1
end

function PM.SpellName(id)
   local api = _G.C_Spell
   if not (id and api and api.GetSpellName) then return nil end
   local ok, name = pcall(api.GetSpellName, id)
   if ok and type(name) == "string" and name ~= "" then return name end
   return nil
end

function PM.SpellIcon(id)
   local api = _G.C_Spell
   if not (id and api and api.GetSpellTexture) then return nil end
   local ok, icon = pcall(api.GetSpellTexture, id)
   if ok and icon then return icon end
   return nil
end

function PM.IsSpellKnown(id)
   local api = _G.C_SpellBook
   if not (id and api and api.IsSpellKnown) then return false end
   local ok, known = pcall(api.IsSpellKnown, id)
   return (ok and known) and true or false
end

-- Oeffnet dieser Zauber ein Berufsfenster? (Blizzards Berufsbuch fragt genauso.)
function PM.OpensWindow(spellID)
   local api = _G.C_TradeSkillUI
   if not (spellID and api and api.CanTradeSkillShowCraftingUI) then return false end
   local ok, can = pcall(api.CanTradeSkillShowCraftingUI, spellID)
   return (ok and can) and true or false
end

-- Ist das Fenster dieses Berufs gerade offen (und zeigt es diesen Beruf)?
function PM.IsProfessionOpen(skillLine)
   local api = _G.C_TradeSkillUI
   local frame = _G.ProfessionsFrame
   if not (skillLine and api and api.GetBaseProfessionInfo and frame and frame:IsShown()) then return false end
   local ok, info = pcall(api.GetBaseProfessionInfo)
   return (ok and type(info) == "table" and info.professionID == skillLine) and true or false
end

-- Name und Symbol eines Gegenstands. Kennt der Client den Gegenstand noch nicht, wird er angefordert
-- (GET_ITEM_INFO_RECEIVED baut die Liste dann neu) und solange gilt der Ausweichtext.
function PM.ItemName(id, fallback)
   local api = _G.C_Item
   if id and api then
      if api.GetItemNameByID then
         local ok, name = pcall(api.GetItemNameByID, id)
         if ok and type(name) == "string" and name ~= "" then return name end
      end
      if api.RequestLoadItemDataByID then pcall(api.RequestLoadItemDataByID, id) end
   end
   return fallback or ("item:" .. tostring(id))
end

function PM.ItemIcon(id)
   local api = _G.C_Item
   if not (id and api and api.GetItemIconByID) then return nil end
   local ok, icon = pcall(api.GetItemIconByID, id)
   if ok and icon then return icon end
   return nil
end

local function Pack(...)
   return { n = select("#", ...), ... }
end

-- ---------------------------------------------------------------------------
-- Berufe lesen
-- ---------------------------------------------------------------------------

local MAX_SPELLS = 8      -- mehr Zauber je Beruf gibt es nicht (Blizzards Buch rechnet mit hoechstens 2)

-- Die Zauber eines Berufs aus dem Zauberbuch: Plaetze spellOffset+1 .. spellOffset+numSpells.
local function ReadSpells(raw)
   local api = _G.C_SpellBook
   if not (api and api.GetSpellBookItemInfo) then return end
   local bank, spellType = PlayerBank(), SpellType()
   for i = 1, math.min(raw.numSpells, MAX_SPELLS) do
      local slot = raw.spellOffset + i
      local ok, info = pcall(api.GetSpellBookItemInfo, slot, bank)
      if ok and type(info) == "table" then
         local id = tonumber(info.spellID) or tonumber(info.actionID)
         local spell = {
            slot = slot,
            id = id,
            name = type(info.name) == "string" and info.name or nil,
            icon = info.iconID,
            passive = info.isPassive and true or false,
            isSpell = (info.itemType == nil) or (info.itemType == spellType),
         }
         spell.window = (id and spell.isSpell and not spell.passive) and PM.OpensWindow(id) or false
         raw.spells[#raw.spells + 1] = spell
      end
   end
end

-- Alle erlernten Berufe in der Reihenfolge des Spiels. GetProfessions() liefert feste Plaetze
-- (1, 2: Hauptberufe; danach die Nebenberufe), nicht belegte Plaetze sind nil: darum mit
-- select("#") zaehlen und Luecken ueberspringen.
-- list.unknown: die Berufe liessen sich nicht lesen (dann gibt es auch keine Platzhalter: eine leere Liste
-- hiesse sonst "nichts erlernt").
function PM.ReadProfessions()
   local list = {}
   if not (_G.GetProfessions and _G.GetProfessionInfo) then
      list.unknown = true
      return list
   end
   local ok, err = pcall(function()
      local indexes = Pack(_G.GetProfessions())
      for pos = 1, indexes.n do
         local index = indexes[pos]
         if index then
            local name, icon, rank, maxRank, numSpells, spellOffset, skillLine, modifier, _, _, skillLineName =
               _G.GetProfessionInfo(index)
            if type(name) == "string" and name ~= "" then
               local raw = {
                  pos = pos, index = index, name = name, icon = icon,
                  rank = tonumber(rank) or 0, maxRank = tonumber(maxRank) or 0,
                  numSpells = tonumber(numSpells) or 0, spellOffset = tonumber(spellOffset) or 0,
                  skillLine = tonumber(skillLine), modifier = tonumber(modifier) or 0,
                  skillLineName = skillLineName, spells = {},
               }
               ReadSpells(raw)
               list[#list + 1] = raw
            end
         end
      end
   end)
   if not ok then
      list.unknown = true
      PM.ReportOnce("ReadProfessions", err)
   end
   return list
end

-- ---------------------------------------------------------------------------
-- Berufe zuordnen
-- ---------------------------------------------------------------------------

local byName
local function NameIndex()
   if byName then return byName end
   byName = {}
   for _, def in ipairs(PM.PROFESSIONS) do
      for _, name in pairs(def.names or {}) do byName[strlower(name)] = def end
   end
   return byName
end

-- Der Dateneintrag zu einem gelesenen Beruf: zuerst ueber die Fertigkeitszeile, sonst ueber den Namen
-- (alle Sprachen). nil bei einem Beruf, den die Daten nicht kennen.
function PM.Identify(raw)
   if raw.skillLine and PM.PROFESSION_BY_SKILLLINE[raw.skillLine] then
      return PM.PROFESSION_BY_SKILLLINE[raw.skillLine]
   end
   local index = NameIndex()
   if type(raw.name) == "string" and index[strlower(raw.name)] then return index[strlower(raw.name)] end
   if type(raw.skillLineName) == "string" and index[strlower(raw.skillLineName)] then
      return index[strlower(raw.skillLineName)]
   end
   return nil
end

-- Ist das ein Suchzauber ("Ortung")? Bekannt aus der Tabelle oder: ein Zauber ohne Fenster bei einem Sammelberuf.
local function IsTracking(spell, def)
   local ability = PM.ABILITY_BY_SPELL[spell.id]
   if ability then return ability.kind == "tracking" end
   return def ~= nil and def.gather == true
end

-- Baut den Listeneintrag eines gelesenen Berufs.
--   Ein Klick wirkt: den Zauber, der ein Fenster oeffnet (Schmiedekunst, Kochkunst, Bergbau/Schmelzen ...);
--   sonst die Suche (Bergbau, Kraeuterkunde) oder den ersten aktiven Zauber (Angeln). Mit activities = "list"
--   stehen die Suchen in einer eigenen Kategorie, dann wirkt der Beruf selbst nichts.
function PM.Resolve(raw, db)
   db = db or PM.db
   local def = PM.Identify(raw)
   local window, tracking, active
   for _, spell in ipairs(raw.spells) do
      if spell.id and spell.isSpell and not spell.passive then
         if spell.window then
            window = window or spell
         elseif IsTracking(spell, def) then
            tracking = tracking or spell
         else
            active = active or spell
         end
      end
   end

   local action, kind
   if window then
      action, kind = window, "window"
   elseif tracking and not ListMode(db) then
      action, kind = tracking, "tracking"
   elseif active then
      action, kind = active, "use"
   end
   local moved = (tracking ~= nil and ListMode(db) and action == nil) or nil

   local cat = def and def.cat
   if not cat then
      if raw.pos > 2 then cat = "secondary" elseif window then cat = "craft" else cat = "gather" end
   end
   local order = def and def.order or (100 + raw.pos)
   if ListMode(db) and def and def.asAbility then
      cat, order = "abilities", def.abilityOrder or 1
   end

   return {
      key = def and def.key or ("skill" .. tostring(raw.skillLine or raw.index)),
      cat = cat,
      order = order,
      name = raw.name,
      rank = raw.rank,
      maxRank = raw.maxRank,
      icon = raw.icon or (def and def.icon),
      action = action and action.id or nil,       -- Zauber-Nummer, die ein Klick wirkt (nil: nichts zu wirken)
      actionName = action and action.name or nil,
      kind = action and kind or "none",
      skillLine = raw.skillLine,
      -- der Zauber, der das Fenster dieses Berufs oeffnet (zum Herstellen der Lager-Objekte)
      windowSpell = window and window.id or nil,
      -- ein Beruf, der etwas wirken sollte, dessen Zauber aber nicht gefunden wurde
      missing = (not action) and not moved and def ~= nil and def.expect ~= nil or nil,
      -- die Suche dieses Berufs steht (mit "aktive Faehigkeiten") in einer eigenen Zeile
      moved = moved,
   }
end

-- Einträge der aktiven Faehigkeiten (activities = "list"): die bekannten Zauber aus
-- PM.ABILITIES plus die Suchzauber, die in den Berufen stehen, aber nicht in der Tabelle.
function PM.BuildAbilities(raws, db)
   db = db or PM.db
   local entries, seen = {}, {}
   -- Zauber, die das Zauberbuch bei einem Beruf fuehrt: gelten als bekannt, auch wenn IsSpellKnown sie nicht
   -- meldet (so steht Verhuetten in der Liste, wie es im Untermenue steht)
   local listed = {}
   for _, raw in ipairs(raws) do
      for _, spell in ipairs(raw.spells) do
         if spell.id and spell.isSpell and not spell.passive then listed[spell.id] = spell end
      end
   end
   for _, def in ipairs(PM.ABILITIES) do
      if listed[def.spell] or PM.IsSpellKnown(def.spell) then
         local name = PM.SpellName(def.spell) or (listed[def.spell] and listed[def.spell].name)
         if name then
            seen[def.spell] = true
            entries[#entries + 1] = {
               key = def.key, cat = "abilities", order = def.order, name = name,
               rank = 0, maxRank = 0, icon = def.icon or PM.SpellIcon(def.spell),
               action = def.spell, actionName = name, kind = def.kind, ability = true,
            }
         end
      end
   end
   local extra = 0
   for _, raw in ipairs(raws) do
      local def = PM.Identify(raw)
      for _, spell in ipairs(raw.spells) do
         if spell.id and spell.isSpell and not spell.passive and not spell.window and not seen[spell.id]
            and IsTracking(spell, def) then
            seen[spell.id] = true
            extra = extra + 1
            entries[#entries + 1] = {
               key = "spell" .. spell.id, cat = "abilities", order = 20 + extra,
               name = spell.name or PM.SpellName(spell.id) or tostring(spell.id),
               rank = 0, maxRank = 0, icon = spell.icon or PM.SpellIcon(spell.id),
               action = spell.id, actionName = spell.name, kind = "tracking", ability = true,
            }
         end
      end
   end
   return entries
end

local CAT_ORDER = {}
for i, cat in ipairs(PM.CATEGORIES) do CAT_ORDER[cat] = i end

-- Berufe zuerst, danach die Platzhalter, danach Lager und Faehigkeiten (bei Sortierung nach Namen oder
-- Stufe gibt es keine Ueberschriften: dann sollen die Zusatzzeilen nicht zwischen den Berufen stehen)
local function Extra(e)
   if e.cat == "camp" or e.cat == "abilities" then return 2 end
   return e.open and 1 or 0
end

local function ByCategory(a, b)
   local ac, bc = CAT_ORDER[a.cat] or 99, CAT_ORDER[b.cat] or 99
   if ac ~= bc then return ac < bc end
   if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
   return a.key < b.key
end

function PM.SortEntries(entries, mode)
   if mode == "alpha" then
      tsort(entries, function(a, b)
         local ax, bx = Extra(a), Extra(b)
         if ax ~= bx then return ax < bx end
         if ax > 0 then return ByCategory(a, b) end
         local an, bn = strlower(a.name), strlower(b.name)
         if an ~= bn then return an < bn end
         return a.key < b.key
      end)
   elseif mode == "rank" then
      tsort(entries, function(a, b)
         local ax, bx = Extra(a), Extra(b)
         if ax ~= bx then return ax < bx end
         if ax > 0 then return ByCategory(a, b) end
         if a.rank ~= b.rank then return a.rank > b.rank end
         local an, bn = strlower(a.name), strlower(b.name)
         if an ~= bn then return an < bn end
         return a.key < b.key
      end)
   else
      tsort(entries, ByCategory)
   end
   return entries
end

-- ---------------------------------------------------------------------------
-- Untermenues (activities = "sub")
-- ---------------------------------------------------------------------------

-- Zeile eines Untermenues aus einem Zauber des Berufs.
local function SpellChild(spell, def, raw, order)
   local ability = PM.ABILITY_BY_SPELL[spell.id]
   local kind
   if spell.window then kind = "window"
   elseif IsTracking(spell, def) then kind = "tracking"
   else kind = ability and ability.kind or "use" end
   return {
      key = "spell" .. spell.id, order = order, sub = true,
      name = spell.name or PM.SpellName(spell.id) or tostring(spell.id),
      rank = 0, maxRank = 0, icon = spell.icon or (ability and ability.icon) or PM.SpellIcon(spell.id),
      action = spell.id, actionName = spell.name, kind = kind,
      skillLine = spell.window and raw.skillLine or nil,
   }
end

-- Die Zeilen im Untermenue eines Berufs: seine aktiven Zauber (in der Reihenfolge des Zauberbuchs), die
-- bekannten Faehigkeiten aus PM.ABILITIES, die zu ihm gehoeren, und seine Lager-Objekte. used: Zauber, die
-- schon in einem Untermenue stehen (damit keiner doppelt erscheint).
local function Children(raw, def, entry, camp, used)
   local list, seen = {}, {}
   for _, spell in ipairs(raw.spells) do
      if spell.id and spell.isSpell and not spell.passive and not seen[spell.id] then
         seen[spell.id] = true
         used[spell.id] = true
         list[#list + 1] = SpellChild(spell, def, raw, #list + 1)
      end
   end
   if def then
      for _, ability in ipairs(PM.ABILITIES) do
         if ability.prof == def.key and not seen[ability.spell] and PM.IsSpellKnown(ability.spell) then
            local name = PM.SpellName(ability.spell)
            if name then
               seen[ability.spell] = true
               used[ability.spell] = true
               list[#list + 1] = {
                  key = ability.key, order = #list + 1, sub = true, name = name, rank = 0, maxRank = 0,
                  icon = ability.icon or PM.SpellIcon(ability.spell),
                  action = ability.spell, actionName = name, kind = ability.kind, ability = true,
               }
            end
         end
      end
      if camp then
         for _, child in ipairs(PM.Camp.ForProfession(camp, def.key)) do
            child.order = #list + 1
            child.sub = true
            list[#list + 1] = child
         end
      end
   end
   -- Ein Untermenue lohnt nur, wenn es mehr bietet als der Klick auf den Beruf selbst.
   local main = entry.action and ("spell" .. entry.action) or nil
   for _, child in ipairs(list) do
      if child.key ~= main then return list end
   end
   return nil
end

-- ---------------------------------------------------------------------------
-- Charaktere des Kontos
--
-- Die Einstellungen gelten kontoweit (SavedVariables). Darin merkt sich das Addon je Charakter, welche Berufe
-- er hat: db.chars["Name-Realm"] = { name, realm, profs = { Schluessel = Stufe } }. So laesst sich bei einem
-- freien Hauptberuf zeigen, welche Berufe ein anderer Charakter schon abdeckt. Bekannt sind nur Charaktere,
-- die mit dem Addon angemeldet waren.
-- ---------------------------------------------------------------------------

local function Character()
   local name = _G.UnitName and _G.UnitName("player")
   local realm = _G.GetRealmName and _G.GetRealmName()
   if type(name) ~= "string" or name == "" then return nil end
   if type(realm) ~= "string" then realm = "" end
   return name, realm, name .. "-" .. realm
end

-- Merkt sich die Berufe des angemeldeten Charakters. raws: gelesene Berufe (sonst wird gelesen).
function PM.RememberCharacter(raws)
   raws = raws or PM.ReadProfessions()
   local name, realm, id = Character()
   if raws.unknown or not name then return false end
   local db = PM.db
   if type(db.chars) ~= "table" then db.chars = {} end
   local profs = {}
   for _, raw in ipairs(raws) do
      local def = PM.Identify(raw)
      if def then profs[def.key] = raw.rank end
   end
   db.chars[id] = { name = name, realm = realm, profs = profs }
   return true
end

-- Die anderen Charaktere des Kontos, die den Beruf key haben: Liste aus { label, rank }, hoechste Stufe zuerst.
-- label: der Name; liegt der Charakter auf einem anderen Realm, mit Realm.
function PM.AltsWith(key)
   local list = {}
   local chars = PM.db.chars
   if type(chars) ~= "table" then return list end
   local _, realm, me = Character()
   for id, char in pairs(chars) do
      local rank = id ~= me and char.profs[key]
      if rank then
         list[#list + 1] = { label = (char.realm == realm) and char.name or (char.name .. "-" .. char.realm), rank = rank }
      end
   end
   tsort(list, function(a, b)
      if a.rank ~= b.rank then return a.rank > b.rank end
      return a.label < b.label
   end)
   return list
end

-- Vergisst alle Charaktere ausser dem angemeldeten.
function PM.ForgetCharacters()
   PM.db.chars = {}
   PM.RememberCharacter()
end

-- Fuer /berufe alts: je gemerktem Charakter eine Zeile "Name-Realm: Beruf Stufe, ...".
function PM.CharacterLines()
   local lines = {}
   local chars = PM.db.chars
   if type(chars) ~= "table" then return lines end
   local ids = {}
   for id in pairs(chars) do ids[#ids + 1] = id end
   tsort(ids)
   for _, id in ipairs(ids) do
      local parts = {}
      for _, def in ipairs(PM.PROFESSIONS) do
         local rank = chars[id].profs[def.key]
         if rank then parts[#parts + 1] = PM.DefName(def) .. " " .. rank end
      end
      lines[#lines + 1] = id .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "-")
   end
   return lines
end

-- ---------------------------------------------------------------------------
-- Platzhalter fuer nicht erlernte Berufe
-- ---------------------------------------------------------------------------

-- Name eines Berufs aus der Tabelle, in der Sprache des Clients.
local function DefName(def)
   local loc = _G.GetLocale and _G.GetLocale() or "enUS"
   return def.names[loc] or def.names.enUS
end
PM.DefName = DefName

-- Untermenue eines freien Hauptberufs: die Hauptberufe, die es zu erlernen gibt und die der Charakter noch
-- nicht hat. Hat ein anderer Charakter des Kontos den Beruf schon, steht dessen Name rechts in der Zeile
-- (tag; bei mehreren "Name +1"), alle stehen im Tooltip (alts).
local function Learnable(have)
   local list = {}
   for _, def in ipairs(PM.PROFESSIONS) do
      if def.learn and not have[def.key] then
         local alts = PM.AltsWith(def.key)
         local tag
         if #alts > 0 then
            tag = alts[1].label .. ((#alts > 1) and (" +" .. (#alts - 1)) or "")
         end
         list[#list + 1] = {
            key = "learn_" .. def.key, order = #list + 1, sub = true, name = DefName(def), rank = 0, maxRank = 0,
            icon = def.icon, kind = "learn", tag = tag, alts = (#alts > 0) and alts or nil,
         }
      end
   end
   return (#list > 0) and list or nil
end

-- WoW: Forever: zwei Hauptberufe, dazu die Nebenberufe Kochkunst, Erste Hilfe und Angeln. Was davon noch
-- nicht erlernt ist, steht als Platzhalter in der Liste: je freiem Hauptberuf eine Zeile "Hauptberuf", je
-- fehlendem Nebenberuf eine Zeile mit dessen Namen. Ein Klick wirkt nichts (er zeigt die Berufsuebersicht).
--   open = "primary" | "secondary" kennzeichnet die Zeile; die Oberflaeche zeichnet sie gedimmt und
--   gestrichelt umrandet. Ein freier Hauptberuf traegt als Untermenue die erlernbaren Berufe (children).
function PM.Placeholders(raws)
   local list, primary, have = {}, 0, {}
   for _, raw in ipairs(raws) do
      local def = PM.Identify(raw)
      if def then
         have[def.key] = true
         if def.cat ~= "secondary" then primary = primary + 1 end
      elseif (raw.pos or 99) <= PM.PRIMARY_SLOTS then
         primary = primary + 1
      end
   end
   local learnable = (primary < PM.PRIMARY_SLOTS) and Learnable(have) or nil
   for i = primary + 1, PM.PRIMARY_SLOTS do
      list[#list + 1] = {
         key = "open" .. i, cat = "primary", order = i, name = PM.L.open_primary, rank = 0, maxRank = 0,
         icon = PM.OPEN_ICON, kind = "open", open = "primary", dim = true, children = learnable,
      }
   end
   for _, def in ipairs(PM.PROFESSIONS) do
      if def.slot and not have[def.key] then
         list[#list + 1] = {
            key = "open_" .. def.key, cat = def.cat, order = def.order, name = DefName(def), rank = 0, maxRank = 0,
            icon = def.icon, kind = "open", open = "secondary", dim = true,
         }
      end
   end
   return list
end

-- Alle erlernten Berufe (und, je nach Einstellung, ihre Taetigkeiten, das Lager und Platzhalter fuer nicht
-- erlernte Berufe), sortiert nach db.sort.
function PM.BuildEntries(raws, sortMode, db)
   db = db or PM.db
   local entries, profs = {}, {}
   for _, raw in ipairs(raws) do
      local entry = PM.Resolve(raw, db)
      entries[#entries + 1] = entry
      local def = PM.Identify(raw)
      if def then
         profs[def.key] = { name = raw.name, rank = raw.rank + raw.modifier, skillLine = raw.skillLine,
            openSpell = entry.windowSpell }
      end
   end

   local camp = (db.camp ~= "off" and PM.Camp) and PM.Camp.Evaluate(profs, db) or nil

   if SubMode(db) then
      local used = {}
      for i, raw in ipairs(raws) do
         entries[i].children = Children(raw, PM.Identify(raw), entries[i], camp, used)
      end
      -- bekannte Faehigkeiten, deren Beruf nicht in der Liste steht: eigene Kategorie
      for _, ability in ipairs(PM.ABILITIES) do
         if not used[ability.spell] and PM.IsSpellKnown(ability.spell) then
            local name = PM.SpellName(ability.spell)
            if name then
               entries[#entries + 1] = {
                  key = ability.key, cat = "abilities", order = ability.order, name = name,
                  rank = 0, maxRank = 0, icon = ability.icon or PM.SpellIcon(ability.spell),
                  action = ability.spell, actionName = name, kind = ability.kind, ability = true,
               }
            end
         end
      end
   elseif ListMode(db) then
      for _, entry in ipairs(PM.BuildAbilities(raws, db)) do entries[#entries + 1] = entry end
   end

   if camp then
      for _, entry in ipairs(PM.Camp.TopLevel(camp)) do entries[#entries + 1] = entry end
   end

   if db.unlearned and not raws.unknown then
      for _, entry in ipairs(PM.Placeholders(raws)) do entries[#entries + 1] = entry end
   end

   PM.SortEntries(entries, sortMode or db.sort)
   return entries
end

-- Zeilenfolge fuer die Liste: Ueberschriften nur bei Sortierung nach Kategorie. In der
-- Darstellung "nur Symbole" (compact = all) gibt es keine Ueberschriften, stattdessen eine
-- Luecke zwischen den Kategorien.
-- Ergebnis: Liste aus { header = "craft" }, { gap = true } und { entry = eintrag }.
function PM.Layout(entries, db)
   db = db or PM.db
   local rows = {}
   local lastCat
   for _, entry in ipairs(entries) do
      if db.sort == "cat" and entry.cat ~= lastCat then
         if db.compact == "all" then
            if lastCat then rows[#rows + 1] = { gap = true } end
         elseif db.headers then
            rows[#rows + 1] = { header = entry.cat }
         end
      end
      lastCat = entry.cat
      rows[#rows + 1] = { entry = entry }
   end
   return rows
end

-- Erkennung in einem Schritt: liest die Berufe und baut die Eintraege (nur die Liste, damit der Aufruf
-- bedenkenlos als letztes Argument einer anderen Funktion stehen kann).
function PM.Collect()
   local raws = PM.ReadProfessions()
   PM.RememberCharacter(raws)
   return PM.BuildEntries(raws)
end

-- Kurzer Schluessel zum Vergleichen: aendert sich die Liste, muss neu gebaut werden.
-- Die Fertigkeitsstufen gehoeren nur dazu, wenn danach sortiert wird; sonst genuegt
-- UI.UpdateRanks.
local function EntrySignature(parts, e, withRank)
   parts[#parts + 1] = format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s%s", e.key, e.name, tostring(e.action), tostring(e.item),
      tostring(e.icon), tostring(e.kind), tostring(e.cat), tostring(e.tag), tostring(e.dim),
      e.craft and tostring(e.craft.recipe) or "", withRank and ("|" .. tostring(e.rank)) or "")
   if e.children then
      parts[#parts + 1] = "{"
      for _, child in ipairs(e.children) do EntrySignature(parts, child, false) end
      parts[#parts + 1] = "}"
   end
end

function PM.Signature(entries, db)
   db = db or PM.db
   local parts = { db.sort, tostring(db.headers), tostring(db.ranks), tostring(db.compact), tostring(db.activities),
      tostring(db.camp), tostring(db.unlearned) }
   for _, e in ipairs(entries) do EntrySignature(parts, e, db.sort == "rank") end
   return table.concat(parts, ";")
end
