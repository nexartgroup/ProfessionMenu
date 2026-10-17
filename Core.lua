-- Core.lua
-- ---------------------------------------------------------------------------
-- Einstellungen, Erkennung der erlernten Berufe, Aufbau der Liste.
-- Nichts hier fasst Oberflaeche an: PM.Collect() liefert reine Daten, die
-- UI.lua zeichnet. So laesst sich die Erkennung ohne Spiel testen.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local pairs, ipairs, type, tostring, tonumber, select = pairs, ipairs, type, tostring, tonumber, select
local strlower, format, tsort = string.lower, string.format, table.sort

PM.version = "1.0"

-- ---------------------------------------------------------------------------
-- Einstellungen (SavedVariables: ProfessionMenuDB)
-- ---------------------------------------------------------------------------

local DEFAULTS = {
   sort = "cat",          -- cat | alpha | rank
   headers = true,        -- Kategorie-Ueberschriften zeigen (nur bei Sortierung nach Kategorie)
   ranks = true,          -- Fertigkeitsstufe rechts in der Zeile
   direction = "auto",    -- auto | up | down
   compact = "off",       -- off | button (Knopf nur Symbol) | all (Knopf und Liste nur Symbole)
   abilities = false,     -- aktive Faehigkeiten (Entzaubern, Angeln ...) in die Liste aufnehmen
   scale = 1,             -- nur ohne ElvUI
   locked = true,         -- ohne ElvUI: Knopf verschiebbar?
}

PM.DEFAULTS = DEFAULTS

local VALID = {
   sort = { cat = true, alpha = true, rank = true },
   direction = { auto = true, up = true, down = true },
   compact = { off = true, button = true, all = true },
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
   for _, key in ipairs({ "headers", "ranks", "locked", "abilities" }) do
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
end

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

-- Einen Fehler einmal melden (im Debug-Modus immer).
function PM.ReportOnce(name, err)
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
-- Fertigkeiten lesen (Skills-Fenster)
-- ---------------------------------------------------------------------------

-- Ignorierfenster nach dem Aufklappen/Zuklappen: Expand/CollapseSkillHeader loesen
-- SKILL_LINES_CHANGED aus (vermutlich sofort, evtl. einen Takt spaeter). Das
-- Fenster verhindert, dass unser eigener Ereignis-Haken daraus eine Schleife macht.
PM.ignoreUntil = 0
local IGNORE_SECONDS = 0.5

function PM.EventsIgnored()
   return PM.scanning or (GetTime and GetTime() < PM.ignoreUntil)
end

-- Ist das die Ueberschrift der Berufe ("Berufe") oder der Nebenberufe ("Sekundaere
-- Fertigkeiten")? Beide Namen liefert der Client als Globals; TRADE_SKILLS ist genau der
-- Text der Ueberschrift, SECONDARY_SKILLS hat zusaetzlich einen Doppelpunkt (bei frFR
-- mit geschuetztem Leerzeichen davor, bei Chinesisch evtl. ein breiter): daher "beginnt
-- damit und ist hoechstens 4 Bytes laenger".
local function IsProfessionHeader(name)
   if type(name) ~= "string" then return false end
   if _G.TRADE_SKILLS and name == _G.TRADE_SKILLS then return true end
   local secondary = _G.SECONDARY_SKILLS
   return type(secondary) == "string" and #secondary >= #name and #secondary - #name <= 4
      and secondary:sub(1, #name) == name
end

-- Liest alle Fertigkeitszeilen, auch die unter eingeklappten Ueberschriften
-- (GetNumSkillLines zaehlt nur sichtbare Zeilen). Eingeklappte Ueberschriften
-- werden fuers Lesen aufgeklappt (von hinten) und danach wieder zugeklappt
-- (nach Nummer der Ueberschrift, von hinten), damit das Skills-Fenster so bleibt,
-- wie es war. Ist nichts eingeklappt (der Normalfall), wird nichts angefasst.
-- Aufgeklappt werden nur die Ueberschriften der Berufe und Nebenberufe (Waffen, Ruestung,
-- Sprachen bleiben unberuehrt: jedes Auf-/Zuklappen loest SKILL_LINES_CHANGED fuer alle
-- Addons aus). Findet das Addon nicht beide Ueberschriften wieder (unbekannte Sprache),
-- klappt es sicherheitshalber alle eingeklappten auf.
-- Ergebnis: Tabelle Name -> { name, rank, maxRank, modifier, section } und
-- die Liste in Anzeigereihenfolge.
function PM.ReadSkills()
   local skills, order = {}, {}
   if not (GetNumSkillLines and GetSkillLineInfo) then return skills, order end

   PM.scanning = true
   local wasCollapsed, headers, expanded = {}, 0, false

   -- Lesen in einem pcall: ein Fehler mittendrin (etwa ein anderes Addon, das
   -- GetSkillLineInfo abfaengt) darf das Skills-Fenster nicht aufgeklappt zuruecklassen
   -- und PM.scanning nicht fuer immer setzen.
   local ok, err = pcall(function()
      -- 1. Ueberschriften zaehlen, eingeklappte merken (und welche Berufe enthalten)
      local collapsedHeaders, professionHeaders = {}, 0
      for i = 1, GetNumSkillLines() do
         local name, isHeader, isExpanded = GetSkillLineInfo(i)
         if isHeader then
            headers = headers + 1
            if IsProfessionHeader(name) then professionHeaders = professionHeaders + 1 end
            if not isExpanded then collapsedHeaders[headers] = name end
         end
      end
      local onlyProfessions = professionHeaders >= 2
      local any = false
      for ordinal, name in pairs(collapsedHeaders) do
         if not onlyProfessions or IsProfessionHeader(name) then
            wasCollapsed[ordinal] = true
            any = true
         end
      end

      -- 2. aufklappen (von hinten: die kleineren Nummern bleiben gueltig)
      if any and ExpandSkillHeader then
         expanded = true
         local ordinal = headers
         for i = GetNumSkillLines(), 1, -1 do
            local _, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader then
               if wasCollapsed[ordinal] and not isExpanded then ExpandSkillHeader(i) end
               ordinal = ordinal - 1
            end
         end
      end

      -- 3. lesen (GetNumSkillLines nach dem Aufklappen neu fragen)
      local section
      for i = 1, GetNumSkillLines() do
         local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(i)
         if name and name ~= "" then
            if isHeader then
               section = name
            else
               local entry = {
                  name = name, rank = rank or 0, maxRank = maxRank or 0,
                  modifier = modifier or 0, section = section,
               }
               skills[name] = entry
               order[#order + 1] = entry
            end
         end
      end
   end)

   -- 4. wieder zuklappen: Ueberschriften von hinten, nach ihrer Nummer erkannt
   if expanded and CollapseSkillHeader then
      pcall(function()
         local ordinal = headers
         for i = GetNumSkillLines(), 1, -1 do
            local _, isHeader = GetSkillLineInfo(i)
            if isHeader then
               if wasCollapsed[ordinal] then CollapseSkillHeader(i) end
               ordinal = ordinal - 1
            end
         end
      end)
      if GetTime then PM.ignoreUntil = GetTime() + IGNORE_SECONDS end
   end

   PM.scanning = false
   if not ok then PM.ReportOnce("ReadSkills", err) end
   return skills, order
end

-- ---------------------------------------------------------------------------
-- Zauberbuch lesen (welche Zauber der Spieler kennt)
-- ---------------------------------------------------------------------------

-- Menge der bekannten Zaubernamen. Ein Zauber, der im Zauberbuch steht, ist
-- bekannt; fuer Berufe genuegt der Name (alle Raenge heissen gleich). Das Buch
-- enthaelt auch niedrigere Raenge, darum eine Menge und kein Zaehlen.
function PM.ReadSpellbook()
   local known = {}
   if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellName) then return known end
   local book = BOOKTYPE_SPELL or "spell"
   -- Ein Fehler mittendrin (angepasster Client, ein Addon, das die Funktionen abfaengt)
   -- darf das Oeffnen nicht verhindern: das bisher Gelesene bleibt, den Rest faengt
   -- PM.IsKnown ueber GetSpellInfo(Name) ab.
   local ok, err = pcall(function()
      for tab = 1, (GetNumSpellTabs() or 0) do
         local _, _, offset, count = GetSpellTabInfo(tab)
         offset, count = tonumber(offset) or 0, tonumber(count) or 0
         for index = offset + 1, offset + count do
            local name = GetSpellName(index, book)
            if name then known[name] = true end
         end
      end
   end)
   if not ok then PM.ReportOnce("ReadSpellbook", err) end
   return known
end

local function SpellName(id)
   if not (id and GetSpellInfo) then return nil end
   return (GetSpellInfo(id))
end

local function SpellTexture(id)
   if not (id and GetSpellInfo) then return nil end
   return (select(3, GetSpellInfo(id)))
end

-- Kennt der Spieler den Zauber? Zauberbuch zuerst; GetSpellInfo(Name) liefert nur
-- fuer Zauber im Zauberbuch etwas und faengt ab, wenn das Auslesen des Buches
-- (angepasster Client) nichts ergibt.
function PM.IsKnown(name, known)
   if not name then return false end
   if known and known[name] then return true end
   return GetSpellInfo ~= nil and GetSpellInfo(name) ~= nil
end

-- ---------------------------------------------------------------------------
-- Berufe zuordnen
-- ---------------------------------------------------------------------------

-- Alle Namen, unter denen ein Beruf in der Fertigkeitenliste stehen kann: die
-- Namen der Zauber aus def.spells (Sprache des Clients) und die festen Namen
-- aller Sprachen (kein Beruf heisst in einer Sprache wie ein anderer in einer anderen).
function PM.NameSet(def)
   local set = {}
   for _, id in ipairs(def.spells or {}) do
      local name = SpellName(id)
      if name then set[name] = true end
   end
   if def.names then
      for _, name in pairs(def.names) do set[name] = true end
   end
   return set
end

-- Die Fertigkeit, die zu einem Beruf gehoert (oder nil).
function PM.FindSkill(def, skills)
   for name in pairs(PM.NameSet(def)) do
      if skills[name] then return skills[name] end
   end
   return nil
end

-- Welcher Beruf gehoert zu einem Fertigkeitsnamen (fuer /berufe list).
function PM.IdentifySkill(skillName)
   for _, def in ipairs(PM.PROFESSIONS) do
      if not def.from and PM.NameSet(def)[skillName] then return def end
   end
   return nil
end

-- Den ersten bekannten Zauber aus def.open waehlen (Name), sonst nil.
local function PickAction(def, known)
   for _, id in ipairs(def.open or {}) do
      local name = SpellName(id)
      if name and PM.IsKnown(name, known) then return name, id end
   end
   return nil
end

-- Baut den Listeneintrag eines Berufs oder nil, wenn er nicht erlernt ist.
-- Mit der Einstellung "abilities": Angeln steht bei den Faehigkeiten (def.asAbility), und
-- Bergbau/Kraeuterkunde wirken nicht mehr selbst als Suche (die Suchzauber stehen dort).
function PM.Resolve(def, skills, known, db)
   db = db or PM.db
   if db.abilities and def.asAbility then return nil end
   local skill
   if def.from then
      local parent = PM.PROFESSION_BY_KEY[def.from]
      skill = parent and PM.FindSkill(parent, skills)
   else
      skill = PM.FindSkill(def, skills)
   end
   if not skill then return nil end

   local name = skill.name
   if def.from then
      -- abgeleiteter Eintrag (Verhuettung): Name des Zaubers, Stufe des Elternberufs
      name = SpellName(def.spell)
      if not name then return nil end
   end

   local action = PickAction(def, known)
   if def.from and not action then
      -- Verhuettung gibt es nur, wenn der Zauber im Zauberbuch steht
      return nil
   end
   local searchMoved = db.abilities and def.kind == "tracking"
   if searchMoved then action = nil end

   return {
      key = def.key,
      cat = def.cat,
      order = def.order,
      name = name,
      rank = skill.rank,
      maxRank = skill.maxRank,
      icon = def.icon or SpellTexture(def.spells and def.spells[1] or def.spell),
      action = action,           -- Zaubername, den ein Klick wirkt (nil: nichts zu wirken)
      kind = action and def.kind or "none",
      -- ein Beruf, der etwas wirken sollte, dessen Zauber aber nicht gefunden wurde
      missing = (not action) and not searchMoved and def.kind ~= "none" or nil,
      -- die Suche dieses Berufs steht (mit "aktive Faehigkeiten") in einer eigenen Zeile
      moved = searchMoved or nil,
   }
end

-- Baut den Eintrag einer aktiven Faehigkeit oder nil, wenn der Zauber nicht im Zauberbuch steht.
function PM.ResolveAbility(def, skills, known)
   local name = SpellName(def.spell)
   if not (name and PM.IsKnown(name, known)) then return nil end
   local rank, maxRank = 0, 0
   if def.rankFrom then
      local parent = PM.PROFESSION_BY_KEY[def.rankFrom]
      local skill = parent and PM.FindSkill(parent, skills)
      if skill then rank, maxRank = skill.rank, skill.maxRank end
   end
   return {
      key = def.key,
      cat = def.cat,
      order = def.order,
      name = name,
      rank = rank,
      maxRank = maxRank,
      icon = def.icon or SpellTexture(def.spell),
      action = name,
      kind = def.kind,
      ability = true,
   }
end

local CAT_ORDER = {}
for i, cat in ipairs(PM.CATEGORIES) do CAT_ORDER[cat] = i end

function PM.SortEntries(entries, mode)
   if mode == "alpha" then
      tsort(entries, function(a, b)
         local an, bn = strlower(a.name), strlower(b.name)
         if an ~= bn then return an < bn end
         return a.key < b.key
      end)
   elseif mode == "rank" then
      tsort(entries, function(a, b)
         if a.rank ~= b.rank then return a.rank > b.rank end
         local an, bn = strlower(a.name), strlower(b.name)
         if an ~= bn then return an < bn end
         return a.key < b.key
      end)
   else
      tsort(entries, function(a, b)
         local ac, bc = CAT_ORDER[a.cat] or 99, CAT_ORDER[b.cat] or 99
         if ac ~= bc then return ac < bc end
         if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
         return a.key < b.key
      end)
   end
   return entries
end

-- Alle erlernten Berufe, sortiert nach db.sort.
function PM.BuildEntries(skills, known, sortMode, db)
   db = db or PM.db
   local entries = {}
   for _, def in ipairs(PM.PROFESSIONS) do
      local entry = PM.Resolve(def, skills, known, db)
      if entry then entries[#entries + 1] = entry end
   end
   if db.abilities then
      for _, def in ipairs(PM.ABILITIES) do
         local entry = PM.ResolveAbility(def, skills, known)
         if entry then entries[#entries + 1] = entry end
      end
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

-- Erkennung in einem Schritt: liest Skills und Zauberbuch, baut die Eintraege.
function PM.Collect()
   local skills = PM.ReadSkills()
   local known = PM.ReadSpellbook()
   return PM.BuildEntries(skills, known), skills, known
end

-- Kurzer Schluessel zum Vergleichen: aendert sich die Liste, muss neu gebaut werden.
-- Die Fertigkeitsstufen gehoeren nur dazu, wenn danach sortiert wird; sonst genuegt
-- UI.UpdateRanks.
function PM.Signature(entries, db)
   db = db or PM.db
   local parts = { db.sort, tostring(db.headers), tostring(db.ranks), tostring(db.compact), tostring(db.abilities) }
   for _, e in ipairs(entries) do
      parts[#parts + 1] = format("%s|%s|%s|%s|%s%s", e.key, e.name, tostring(e.action), tostring(e.icon), tostring(e.kind),
         db.sort == "rank" and ("|" .. tostring(e.rank)) or "")
   end
   return table.concat(parts, ";")
end
