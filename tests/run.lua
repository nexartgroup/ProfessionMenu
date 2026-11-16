-- tests/run.lua
-- ---------------------------------------------------------------------------
-- Tests fuer ProfessionMenu (WoW: Forever). Aufruf im Addon-Ordner:
--     luajit tests/run.lua
-- Das Addon laeuft dabei in der strengen Attrappe aus tests/mock_wow.lua, mit den Dateien in der
-- Reihenfolge aus ProfessionMenu.toc.
-- ---------------------------------------------------------------------------

package.path = "tests/?.lua;" .. package.path
local Mock = require("mock_wow")

-- ---------------------------------------------------------------------------
-- Mini-Pruefrahmen
-- ---------------------------------------------------------------------------

local tests, passed, failed = {}, 0, 0

local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function show(v)
   if type(v) == "string" then return string.format("%q", v) end
   return tostring(v)
end

local function eq(actual, expected, msg)
   if actual ~= expected then
      error((msg or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
   end
end

local function ok(value, msg)
   if not value then error(msg or "expected a true value", 2) end
end

local function fails(fn, pattern, msg)
   local good, err = pcall(fn)
   if good then error((msg or "expected an error") .. " (no error raised)", 2) end
   if pattern and not tostring(err):find(pattern, 1, true) then
      error((msg or "wrong error") .. ": " .. tostring(err), 2)
   end
end

-- ---------------------------------------------------------------------------
-- Aufbau einer Welt
-- ---------------------------------------------------------------------------

local function tocFiles()
   local files = {}
   for line in io.lines("ProfessionMenu.toc") do
      if line ~= "" and not line:find("^##") then files[#files + 1] = (line:gsub("%s+$", "")) end
   end
   return files
end

local function boot(opts)
   local w = Mock.new(opts)
   for _, file in ipairs(tocFiles()) do w.load(file) end
   w.PM = w.ns
   return w
end

local function start(w)
   w.fire("ADDON_LOADED", "ProfessionMenu")
   w.fire("PLAYER_LOGIN")
end

local function chatHas(w, text)
   for _, line in ipairs(w.chat) do
      if line:find(text, 1, true) then return true end
   end
   return false
end

-- Beispielberufe (Namen deutsch, Nummern wie im Retail-Client)
local function prof(name, skillLine, pos, rank, max, spells)
   return { name = name, skillLine = skillLine, pos = pos, rank = rank or 1, max = max or 75, spells = spells }
end
local P = {
   alchemy = function(pos) return prof("Alchemie", 171, pos, 300, 300, { { id = 2259, name = "Alchemie", window = true } }) end,
   enchanting = function(pos) return prof("Verzauberkunst", 333, pos, 150, 300, { { id = 7411, name = "Verzauberkunst", window = true } }) end,
   mining = function(pos) return prof("Bergbau", 186, pos, 75, 300, {
      { id = 2656, name = "Verhüttung", window = true }, { id = 2580, name = "Mineralien aufspüren" } }) end,
   herbalism = function(pos) return prof("Kräuterkunde", 182, pos, 40, 300, {
      { id = 9134, name = "Kräuterkunde", passive = true }, { id = 2383, name = "Kräuter aufspüren" } }) end,
   skinning = function(pos) return prof("Kürschnerei", 393, pos, 20, 300, { { id = 8613, name = "Kürschnerei", passive = true } }) end,
   firstaid = function(pos) return prof("Erste Hilfe", 129, pos, 100, 300, { { id = 3273, name = "Erste Hilfe", window = true } }) end,
   fishing = function(pos) return prof("Angeln", 356, pos, 50, 300, { { id = 7620, name = "Angeln" } }) end,
   cooking = function(pos) return prof("Kochkunst", 185, pos, 200, 300, {
      { id = 2550, name = "Kochkunst", window = true }, { id = 818, name = "Lagerfeuer" } }) end,
}

-- ---------------------------------------------------------------------------
-- Gegenprobe: die Attrappe muss ablehnen, was der Client ablehnt
-- ---------------------------------------------------------------------------

test("Attrappe ist streng (sonst bewiesen die anderen Tests nichts)", function()
   local w = Mock.new()
   local CreateFrame = w.G.CreateFrame
   local plain = CreateFrame("Frame", nil, w.UIParent)
   fails(function() plain:SetBackdrop({}) end, "attempt to call method", "SetBackdrop ohne BackdropTemplate")
   CreateFrame("Frame", nil, w.UIParent, "BackdropTemplate"):SetBackdrop({})
   local tex = plain:CreateTexture()
   fails(function() tex:SetTexture(1, 1, 1, 0.5) end, "SetColorTexture", "SetTexture mit Farbe")
   local sec = CreateFrame("Button", "GegenprobeKnopf", w.UIParent, "SecureActionButtonTemplate")
   w.combat = true
   fails(function() sec:SetAttribute("type1", "spell") end, "ADDON_ACTION_BLOCKED", "SetAttribute im Kampf")
   fails(function() sec:Show() end, "ADDON_ACTION_BLOCKED", "Show im Kampf")
   fails(function() sec:SetPoint("CENTER") end, "ADDON_ACTION_BLOCKED", "SetPoint im Kampf")
   plain:SetAlpha(0.5)                        -- ungeschuetzte Rahmen duerfen im Kampf alles
   w.combat = false
   fails(function() plain:GibtEsNicht() end, "attempt to call method", "unbekannte Methode")
   fails(function() w.G.C_SpellBook.CastSpellBookItem(1, 0) end, "ADDON_ACTION_FORBIDDEN")
   fails(function() w.G.C_TradeSkillUI.OpenTradeSkill(171) end, "ADDON_ACTION_FORBIDDEN")
end)

-- ---------------------------------------------------------------------------
-- Dateien
-- ---------------------------------------------------------------------------

test("toc: Interface 16001, alle Dateien vorhanden, keine fehlt", function()
   local f = io.open("ProfessionMenu.toc")
   local toc = f:read("*a")
   f:close()
   ok(toc:find("## Interface: 16001", 1, true), "Interface-Zeile")
   ok(toc:find("## SavedVariables: ProfessionMenuDB", 1, true), "SavedVariables")
   local listed = {}
   for _, file in ipairs(tocFiles()) do
      listed[file] = true
      local h = io.open(file)
      ok(h, "TOC nennt " .. file .. ", aber die Datei fehlt")
      h:close()
   end
   local p = io.popen("ls *.lua")
   for file in p:lines() do ok(listed[file], file .. " liegt im Ordner, steht aber nicht im TOC") end
   p:close()
end)

test("alle Dateien laden ohne Fehler und ohne Zugriff auf alte Funktionen", function()
   local w = boot()
   ok(w.PM.UI and w.PM.Skin and w.PM.Diag, "Module")
   eq(w.G.GetSkillLineInfo, nil, "3.3.5a-Funktion darf es nicht geben")
   eq(w.G.GetSpellInfo, nil, "3.3.5a-Funktion darf es nicht geben")
end)

-- ---------------------------------------------------------------------------
-- Erkennung (Core)
-- ---------------------------------------------------------------------------

local function entriesByKey(entries)
   local by = {}
   for _, e in ipairs(entries) do by[e.key] = e end
   return by
end

test("Erkennung: Haupt- und Nebenberufe, Art des Klicks, Kategorien", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.mining(2), P.firstaid(3), P.fishing(4), P.cooking(5) })
   local PM = w.PM
   PM.InitDB()
   local entries = PM.Collect()
   eq(#entries, 6, "fuenf Berufe und das Lagerfeuer")
   local by = entriesByKey(entries)
   eq(by.camp_fire1.cat, "camp"); eq(by.camp_fire1.kind, "lack", "Kochkunst erlernt, aber kein Holz")
   eq(by.alchemy.cat, "craft"); eq(by.alchemy.kind, "window"); eq(by.alchemy.action, 2259)
   eq(by.alchemy.rank, 300); eq(by.alchemy.maxRank, 300); eq(by.alchemy.skillLine, 171)
   -- Bergbau oeffnet das Schmelzfenster (die Suche steht im Untermenue)
   eq(by.mining.cat, "gather"); eq(by.mining.kind, "window"); eq(by.mining.action, 2656)
   eq(by.firstaid.cat, "secondary"); eq(by.firstaid.kind, "window")
   eq(by.fishing.cat, "secondary"); eq(by.fishing.kind, "use"); eq(by.fishing.action, 7620)
   eq(by.cooking.kind, "window"); eq(by.cooking.action, 2550, "Kochkunst: das Fenster, nicht das Lagerfeuer")
end)

test("Erkennung: Kraeuterkunde sucht, Kuerschnerei hat nichts zu wirken", function()
   local w = boot()
   w.setProfessions({ P.herbalism(1), P.skinning(2) })
   w.PM.InitDB()
   local by = entriesByKey(w.PM.Collect())
   eq(by.herbalism.kind, "tracking"); eq(by.herbalism.action, 2383, "der passive Zauber zaehlt nicht")
   eq(by.skinning.kind, "none"); eq(by.skinning.action, nil)
   eq(by.skinning.missing, nil, "Kuerschnerei soll nichts wirken: kein Fehlerhinweis")
end)

test("Erkennung: nicht belegte Plaetze (nil-Luecken) werden uebersprungen", function()
   local w = boot()
   w.setProfessions({ P.enchanting(2), P.fishing(4) })      -- Platz 1, 3, 5 leer
   w.PM.InitDB()
   w.PM.db.unlearned = false
   local entries = w.PM.Collect()
   eq(#entries, 2)
   eq(entries[1].key, "enchanting"); eq(entries[2].key, "fishing")
   eq(entries[1].cat, "refine")
end)

test("Erkennung: kein Beruf -> leere Liste, kein Fehler", function()
   local w = boot()
   w.setProfessions({})
   w.PM.InitDB()
   w.PM.db.unlearned = false
   eq(#w.PM.Collect(), 0)
   w.PM.db.unlearned = true
   w.G.GetProfessions = nil
   eq(#w.PM.Collect(), 0, "ohne GetProfessions (dann auch keine Platzhalter: nichts gelesen heisst nicht nichts erlernt)")
end)

test("Erkennung: unbekannte Berufe erscheinen trotzdem und werden nach Art einsortiert", function()
   local w = boot()
   w.setProfessions({
      prof("Neuer Handwerksberuf", 90001, 1, 10, 100, { { id = 90010, name = "Neuer Handwerksberuf", window = true } }),
      prof("Neues Sammeln", 90002, 2, 10, 100, { { id = 90020, name = "Neues Sammeln" } }),
      prof("Neuer Nebenberuf", 90003, 3, 10, 100, { { id = 90030, name = "Neuer Nebenberuf", window = true } }),
   })
   w.PM.InitDB()
   local by = entriesByKey(w.PM.Collect())
   eq(by.skill90001.cat, "craft"); eq(by.skill90002.cat, "gather"); eq(by.skill90003.cat, "secondary")
   eq(by.skill90001.kind, "window"); eq(by.skill90002.kind, "use")
end)

test("Erkennung: bekannter Name mit unbekannter Fertigkeitszeile wird ueber den Namen erkannt", function()
   local w = boot()
   w.setProfessions({ prof("Schmiedekunst", 77777, 1, 5, 75, { { id = 2018, name = "Schmiedekunst", window = true } }) })
   w.PM.InitDB()
   local entries = w.PM.Collect()
   eq(entries[1].key, "blacksmithing"); eq(entries[1].cat, "craft")
end)

test("Erkennung: ein Zauber im Zauberbuch, der kein Zauber ist (FutureSpell), zaehlt nicht", function()
   local w = boot()
   w.setProfessions({ prof("Alchemie", 171, 1, 1, 75, { { id = 2259, name = "Alchemie", window = true, itemType = 2 } }) })
   w.PM.InitDB()
   local e = w.PM.Collect()[1]
   eq(e.action, nil); eq(e.kind, "none"); eq(e.missing, true, "Alchemie sollte etwas wirken -> Hinweis")
end)

test("Einstellung activities = list: Suchen und Angeln wandern in die Kategorie Faehigkeiten", function()
   local w = boot()
   w.setProfessions({ P.mining(1), P.herbalism(2), P.fishing(4), P.cooking(5) })
   w.known[13262] = true; w.spellNames[13262] = "Entzaubern"
   w.known[818] = true
   local PM = w.PM
   PM.InitDB()
   PM.db.activities = "list"
   local by = entriesByKey(PM.Collect())
   eq(by.mining.children, nil, "keine Untermenues in dieser Darstellung")
   eq(by.fishing.cat, "abilities"); eq(by.fishing.order, 1); eq(by.fishing.kind, "use")
   eq(by.herbalism.kind, "none"); eq(by.herbalism.moved, true); eq(by.herbalism.missing, nil)
   eq(by.mining.kind, "window", "Bergbau oeffnet weiter das Schmelzfenster")
   ok(by.disenchant and by.disenchant.action == 13262 and by.disenchant.kind == "target", "Entzaubern aus der Liste")
   ok(by.campfire and by.campfire.action == 818, "Lagerfeuer aus der Liste")
   -- die Suchzauber stehen im Zauberbuch bei den Berufen (IsSpellKnown meldet sie hier nicht) -> eigene Zeilen
   ok(by.findminerals and by.findminerals.action == 2580 and by.findminerals.kind == "tracking", "Mineralien aufspueren als eigene Zeile")
   ok(by.findherbs and by.findherbs.action == 2383 and by.findherbs.kind == "tracking", "Kraeuter aufspueren als eigene Zeile")
   ok(by.smelting and by.smelting.action == 2656 and by.smelting.kind == "window", "Verhuetten als eigene Zeile")
   -- ist der Zauber bekannt und steht er in der Liste, gibt es ihn nur einmal
   w.known[2383] = true
   local count = 0
   for _, e in ipairs(PM.Collect()) do if e.action == 2383 then count = count + 1 end end
   eq(count, 1, "Kraeuter aufspueren genau einmal")
end)

test("Sortierung und Layout", function()
   local w = boot()
   w.setProfessions({ P.mining(1), P.alchemy(2), P.fishing(4), P.cooking(5) })
   local PM = w.PM
   PM.InitDB()
   local function keys(entries) local t = {} for i, e in ipairs(entries) do t[i] = e.key end return table.concat(t, ",") end
   eq(keys(PM.Collect()), "alchemy,mining,cooking,open_firstaid,fishing,camp_fire1", "nach Kategorie")
   PM.db.sort = "alpha"
   eq(keys(PM.Collect()), "alchemy,fishing,mining,cooking,open_firstaid,camp_fire1",
      "alphabetisch nach (deutschen) Namen, danach der Platzhalter, danach das Lager")
   PM.db.sort = "rank"
   eq(keys(PM.Collect()), "alchemy,cooking,mining,fishing,open_firstaid,camp_fire1",
      "nach Stufe, danach der Platzhalter, danach das Lager")
   PM.db.sort = "cat"
   local layout = PM.Layout(PM.Collect())
   eq(layout[1].header, "craft"); eq(layout[2].entry.key, "alchemy")
   PM.db.headers = false
   eq(PM.Layout(PM.Collect())[1].entry.key, "alchemy", "ohne Ueberschriften")
   PM.db.headers = true; PM.db.compact = "all"
   local compact = PM.Layout(PM.Collect())
   local gaps = 0
   for _, item in ipairs(compact) do if item.gap then gaps = gaps + 1 end end
   eq(gaps, 3, "eine Luecke zwischen je zwei Kategorien, keine Ueberschriften")
end)

test("Signatur aendert sich, wenn sich die Liste aendert", function()
   local w = boot()
   local PM = w.PM
   PM.InitDB()
   w.setProfessions({ P.alchemy(1) })
   local a = PM.Signature(PM.Collect())
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   local b = PM.Signature(PM.Collect())
   ok(a ~= b)
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   eq(PM.Signature(PM.Collect()), b)
end)

test("SavedVariables: kaputte Werte werden ersetzt", function()
   local w = boot()
   w.G.ProfessionMenuDB = { sort = "bogus", headers = "yes", scale = 0, compact = 5, pos = { point = "NOWHERE", x = 1, y = 1 },
      direction = "sideways", abilities = true, activities = "x", camp = 3, diag = "x" }
   local db = w.PM.InitDB()
   eq(db.sort, "cat"); eq(db.headers, true); eq(db.scale, 1); eq(db.compact, "off"); eq(db.pos, nil)
   eq(db.direction, "auto"); eq(db.diag, nil)
   eq(db.abilities, nil, "die alte Einstellung (bis 1.0) entfaellt")
   eq(db.activities, "sub"); eq(db.camp, "auto")
   w.G.ProfessionMenuDB = { pos = { point = "CENTER", x = 10, y = -20 }, scale = 1.5, sort = "alpha" }
   db = w.PM.InitDB()
   eq(db.pos.x, 10); eq(db.scale, 1.5); eq(db.sort, "alpha")
end)

-- ---------------------------------------------------------------------------
-- Oberflaeche
-- ---------------------------------------------------------------------------

local function openList(w)
   w.PM.UI.Open()
   return w.PM.UI.GetMenu()
end

local function shownRows(w)
   local list = {}
   for _, row in ipairs(w.PM.UI.rows) do if row:IsShown() then list[#list + 1] = row end end
   return list
end

test("UI: Knopf und Liste entstehen beim Anmelden, ausserhalb des Kampfes", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   ok(w.PM.ready)
   local button, menu = w.PM.UI.GetButton(), w.PM.UI.GetMenu()
   ok(button and menu)
   eq(menu:IsShown(), false)
   ok(menu:IsProtected(), "die Liste ist ein geschuetzter Zustandsrahmen")
   eq(w.stateDrivers[1].cond, "[combat] 1; 0"); eq(w.stateDrivers[1].frame, menu)
   ok(menu:GetAttribute("_onstate-combat"):find("self:Hide()", 1, true))
   eq(button:GetPoint(), "BOTTOMRIGHT")
   eq(#w.G.UISpecialFrames, 1); eq(w.G.UISpecialFrames[1], "ProfessionMenuEscProxy")
end)

test("UI: Anmeldung im Kampf baut erst nach dem Kampf", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   w.combat = true
   start(w)
   eq(w.PM.ready, nil)
   eq(w.PM.UI.GetButton(), nil)
   w.combat = false
   w.fire("PLAYER_REGEN_ENABLED")
   ok(w.PM.ready); ok(w.PM.UI.GetButton())
end)

test("UI: Zeilen tragen Zauber-Nummer und useOnKeyDown = false", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.skinning(2), P.fishing(4) })
   start(w)
   local menu = openList(w)
   ok(menu:IsShown())
   local rows = shownRows(w)
   eq(#rows, 5, "drei Berufe und die Platzhalter fuer Kochkunst und Erste Hilfe")
   local alch, skin, fish = rows[1], rows[2], rows[5]
   eq(alch.entry.key, "alchemy"); eq(alch:GetAttribute("type1"), "spell"); eq(alch:GetAttribute("spell1"), 2259)
   eq(alch:GetAttribute("*type1"), "spell"); eq(alch:GetAttribute("spell"), 2259)
   eq(skin.entry.key, "skinning"); eq(skin:GetAttribute("type1"), nil); eq(skin:GetAttribute("spell1"), nil)
   eq(fish.entry.key, "fishing"); eq(fish:GetAttribute("spell1"), 7620)
   for _, row in ipairs(w.PM.UI.rows) do eq(row:GetAttribute("useOnKeyDown"), false, "useOnKeyDown") end
   eq(alch.text:GetText(), "Alchemie"); eq(alch.rank:GetText(), "300/300")
   -- nicht benutzte Zeilen sind leer und versteckt
   local unused = w.PM.UI.rows[10]
   eq(unused:IsShown(), false); eq(unused:GetAttribute("type1"), nil); eq(unused.entry, nil)
   -- zwei Ueberschriften (Herstellung, Sammeln, Nebenberufe) = 3
   local headers = 0
   for _, h in ipairs(w.PM.UI.headers) do if h.text:IsShown() then headers = headers + 1 end end
   eq(headers, 3)
end)

test("UI: Linksklick wirkt den Zauber genau einmal, bei beiden Werten der CVar ActionButtonUseKeyDown", function()
   for _, cvar in ipairs({ "1", "0" }) do
      local w = boot()
      w.cvars.ActionButtonUseKeyDown = cvar
      w.setProfessions({ P.alchemy(1) })
      start(w)
      openList(w)
      local row = shownRows(w)[1]
      w.click(row, "LeftButton")
      eq(#w.casts, 1, "CVar " .. cvar); eq(w.casts[1], 2259)
      eq(w.PM.UI.GetMenu():IsShown(), false, "die Liste schliesst sich nach dem Klick")
   end
end)

test("UI: ohne useOnKeyDown wuerde der Klick bei CVar = 1 verpuffen (Beleg fuer die Notwendigkeit)", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   openList(w)
   local row = shownRows(w)[1]
   row:SetAttribute("useOnKeyDown", nil)
   w.click(row, "LeftButton")
   eq(#w.casts, 0, "Attrappe verhaelt sich wie der Client: Aktion beim Niederdruecken, Zeile hoert nur auf Loslassen")
end)

test("UI: Rechtsklick und Zeile ohne Aktion zeigen die Berufsuebersicht", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.skinning(2) })
   start(w)
   openList(w)
   local rows = shownRows(w)
   w.click(rows[1], "RightButton")
   eq(#w.casts, 0); eq(w.toggled, 1)
   openList(w)
   w.click(shownRows(w)[2], "LeftButton")
   eq(#w.casts, 0); eq(w.toggled, 2)
end)

test("UI: ist das Fenster des Berufs schon offen, wird nicht noch einmal gewirkt (Zeile bleibt danach intakt)", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.enchanting(2) })
   start(w)
   local frame = w.newFrame("Frame", "ProfessionsFrame", w.UIParent, "")
   frame._shown = true
   w.openSkillLine = 171
   openList(w)
   local alch, ench = shownRows(w)[1], shownRows(w)[2]
   w.click(alch, "LeftButton")
   eq(#w.casts, 0, "Alchemie ist offen: kein Zauber")
   eq(alch:GetAttribute("spell1"), 2259, "Attribut nach dem Klick wieder da")
   openList(w)
   w.click(shownRows(w)[2], "LeftButton")
   eq(#w.casts, 1, "ein anderer Beruf wird gewirkt"); eq(w.casts[1], 7411)
   -- Rechtsklick bei offenem Fenster: Uebersichtsseite, ToggleProfessionsBook nicht noetig
   frame.SelectBookPage = function() frame.bookPage = true end
   openList(w)
   w.click(shownRows(w)[1], "RightButton")
   eq(frame.bookPage, true)
end)

test("UI: im Kampf ruehrt nichts die geschuetzten Rahmen an", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   start(w)
   openList(w)
   w.combat = true
   w.fire("PLAYER_REGEN_DISABLED")                  -- schliesst die Liste nicht selbst (das tut der Zustandstreiber)
   w.fire("SPELLS_CHANGED")                          -- Liste neu lesen: im Kampf keine Aenderung der Zeilen
   w.fire("SKILL_LINES_CHANGED")
   w.PM.UI.Toggle()                                  -- geoeffnet im Kampf: Schliessen ist gesperrt, aber kein Fehler
   eq(w.PM.UI.GetMenu():IsShown(), true)
   w.PM.UI.GetMenu()._shown = false                  -- das tut im Spiel der Zustandstreiber "[combat]"
   w.PM.UI.Toggle()                                  -- Oeffnen im Kampf: nur die Meldung
   eq(w.lastError, "Im Kampf nicht verfügbar")
   w.PM.Command("compact all")                       -- Einstellung im Kampf: wartet bis nach dem Kampf
   w.PM.Command("scale 1.5")
   eq(w.PM.db.scale, 1, "Skalierung im Kampf abgelehnt")
   w.setProfessions({ P.alchemy(1) })
   w.combat = false
   w.fire("PLAYER_REGEN_ENABLED")
   eq(w.PM.UI.GetButton():GetAlpha(), 1)
   eq(#shownRows(w), 5, "nach dem Kampf ist die Liste aktuell (Alchemie und vier Platzhalter)")
   eq(shownRows(w)[1].entry.key, "alchemy"); eq(shownRows(w)[2].entry.key, "open2")
end)

test("UI: Darstellung 'nur Symbole' und 'Knopf nur Symbol'", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   start(w)
   local S = w.PM.UI.sizes
   w.PM.Command("compact button")
   eq(w.PM.UI.GetButton():GetWidth(), S.cell); eq(w.PM.UI.GetButton().text:IsShown(), false)
   w.PM.Command("compact all")
   local menu = openList(w)
   eq(menu:GetWidth(), S.cell)
   local rows = shownRows(w)
   eq(rows[1]:GetHeight(), S.cell); eq(rows[1].text:IsShown(), false)
   w.PM.Command("compact off")
   eq(w.PM.UI.GetButton():GetWidth(), S.fullW); eq(w.PM.UI.GetButton().text:IsShown(), true)
   ok(w.PM.UI.GetMenu():GetWidth() >= S.fullW)
end)

test("UI: Liste oeffnet nach oben oder unten, je nach Lage des Knopfes", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local menu = openList(w)
   eq(w.PM.UI.Direction(), "up", "Knopf unten rechts")
   local p = menu._points[1]
   eq(p[1], "BOTTOMRIGHT"); eq(p[2], w.UIParent); eq(p[3], "BOTTOMLEFT", "die Liste haengt nur an UIParent")
   w.PM.Command("direction down")
   w.PM.UI.Close(); openList(w)
   eq(menu._points[1][1], "TOPRIGHT")
   w.PM.Command("unlock")
   eq(w.PM.UI.GetButton():IsMovable(), true)
   w.PM.Command("lock")
   eq(w.PM.UI.GetButton():IsMovable(), false)
end)

test("UI: Klick neben die Liste schliesst sie, Klick auf den Knopf nicht doppelt", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local menu = openList(w)
   local update = menu:GetScript("OnUpdate")
   w.mouseDown.LeftButton = true
   menu._mouseOver = true
   update(menu)
   eq(menu:IsShown(), true, "Klick in der Liste")
   menu._mouseOver = false
   update(menu)
   eq(menu:IsShown(), false, "Klick daneben")
   -- Knopf: Klick oeffnet, zweiter schliesst
   w.mouseDown.LeftButton = false
   w.click(w.PM.UI.GetButton(), "LeftButton")
   eq(menu:IsShown(), true)
   w.click(w.PM.UI.GetButton(), "LeftButton")
   eq(menu:IsShown(), false)
end)

test("UI: ESC-Stellvertreter schliesst die Liste", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local menu = openList(w)
   local proxy = w.G.ProfessionMenuEscProxy
   eq(proxy:IsShown(), true)
   proxy:Hide()                                       -- CloseSpecialWindows() ruft Hide()
   eq(menu:IsShown(), false)
   eq(proxy:IsShown(), false)
end)

test("UI: Tooltip einer Zeile nennt Hinweis und Rechtsklick-Hinweis mit dem Wort des Clients", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.skinning(2) })
   start(w)
   openList(w)
   local rows = shownRows(w)
   rows[1]:GetScript("OnEnter")(rows[1])
   local tip = w.G.GameTooltip
   eq(tip.lines[1], "Alchemie"); eq(tip.lines[2], "Fertigkeit: 300 / 300")
   eq(tip.lines[4], "Linksklick: öffnen"); eq(tip.lines[5], "Rechtsklick: Berufe")
   rows[2]:GetScript("OnEnter")(rows[2])
   eq(tip.lines[3], " ")
   eq(tip.lines[4], "Nichts zu öffnen - Linksklick: Berufe")
end)

test("UI: Skalierung und Position", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   w.PM.Command("scale 1,5")
   eq(w.PM.db.scale, 1.5); eq(w.PM.UI.GetButton():GetScale(), 1.5); eq(w.PM.UI.GetMenu():GetScale(), 1.5)
   ok(w.PM.db.pos, "die Position wird beim Skalieren festgehalten")
   w.PM.Command("scale 7")
   eq(w.PM.db.scale, 1.5)
   w.PM.Command("reset")
   eq(w.PM.db.pos, nil)
   eq(w.PM.UI.GetButton():GetPoint(), "BOTTOMRIGHT")
end)

test("UI: Berufe aendern sich bei geoeffneter Liste -> Liste wird neu gebaut", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   w.PM.Command("unlearned off")
   openList(w)
   eq(#shownRows(w), 1)
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   w.fire("LEARNED_SPELL_IN_SKILL_LINE", 356)
   eq(#shownRows(w), 2)
   w.setProfessions({})
   w.fire("SKILL_LINES_CHANGED")
   eq(#shownRows(w), 0); eq(w.PM.UI.GetMenu().empty:IsShown(), true)
end)

-- ---------------------------------------------------------------------------
-- Untermenues und Lager
-- ---------------------------------------------------------------------------

-- Gegenstaende (Nummern wie in Data.lua)
local I = {
   wood = 4470, flint = 4471, starWood = 11291, kit1 = 279981, kit2 = 279961,
   lightLeather = 2318, tent = 279978, smallfish = 6291, vial = 3371, fishBowl = 279967,
   linen = 2996, thread = 2320, bannerHorde = 279972, bannerAlliance = 279973, sleepingBag = 211527,
}
local R = { kit1 = 1229737, kit2 = 1283400, tent = 1229432, fishBowl = 1229745, bannerHorde = 1229504, bannerAlliance = 1263425 }

local function leatherworking(pos, rank)
   return prof("Lederverarbeitung", 165, pos, rank or 100, 300, { { id = 2108, name = "Lederverarbeitung", window = true } })
end
local function tailoring(pos)
   return prof("Schneiderei", 197, pos, 100, 300, { { id = 3908, name = "Schneiderei", window = true } })
end

local function childKeys(entry)
   local t = {}
   for i, child in ipairs(entry.children or {}) do t[i] = child.key end
   return table.concat(t, ",")
end

local function rowFor(w, key, list)
   for _, row in ipairs(list or w.PM.UI.rows) do
      if row:IsShown() and row.entry and row.entry.key == key then return row end
   end
end

-- Die Maus kommt auf eine Zeile (wie im Spiel: OnEnter)
local function hover(row) row:GetScript("OnEnter")(row) end

local function openProfession(w, skillLine)
   if not w.G.ProfessionsFrame then w.newFrame("Frame", "ProfessionsFrame", w.UIParent, "") end
   w.G.ProfessionsFrame._shown = true
   w.openSkillLine = skillLine
end

test("Verhuetten fehlt nicht, auch wenn das Zauberbuch es nicht beim Beruf fuehrt", function()
   local w = boot()
   -- Bergbau nur mit der Suche im Berufsabschnitt; Verhuetten ist als eigener Zauber bekannt
   w.setProfessions({ prof("Bergbau", 186, 1, 75, 300, { { id = 2580, name = "Mineralien aufspüren" } }), P.enchanting(2) })
   w.known[2656] = true; w.spellNames[2656] = "Verhüttung"
   local PM = w.PM
   PM.InitDB()
   local by = entriesByKey(PM.Collect())
   eq(childKeys(by.mining), "spell2580,smelting", "Suche aus dem Zauberbuch, Verhuetten aus der Tabelle")
   eq(by.mining.children[2].action, 2656); eq(by.mining.children[2].kind, "window")
   PM.db.activities = "list"
   by = entriesByKey(PM.Collect())
   eq(by.smelting and by.smelting.cat, "abilities", "auch als Faehigkeit in der eigenen Kategorie")
   -- fuehrt das Zauberbuch es beim Beruf (Fensterzauber), steht es auch dann als Faehigkeit da
   w.known[2656] = nil
   w.setProfessions({ P.mining(1), P.enchanting(2) })
   by = entriesByKey(PM.Collect())
   eq(by.smelting and by.smelting.action, 2656, "auch ohne IsSpellKnown")
   eq(by.smelting.kind, "window"); eq(by.smelting.cat, "abilities")
   eq(by.spell2656, nil, "und nur einmal")
end)

test("Untermenue: die Taetigkeiten eines Berufs stehen als Kinder an seiner Zeile", function()
   local w = boot()
   w.setProfessions({ P.enchanting(1), P.mining(2), P.fishing(4), P.cooking(5) })
   w.known[13262] = true; w.spellNames[13262] = "Entzaubern"
   local PM = w.PM
   PM.InitDB()
   local by = entriesByKey(PM.Collect())
   eq(childKeys(by.mining), "spell2656,spell2580", "Verhuetten und die Suche")
   eq(by.mining.children[1].kind, "window"); eq(by.mining.children[1].skillLine, 186)
   eq(by.mining.children[2].kind, "tracking")
   eq(by.mining.action, 2656, "der Klick auf den Beruf bleibt, was er war")
   eq(childKeys(by.enchanting), "spell7411,disenchant", "Entzaubern gehoert zur Verzauberkunst")
   eq(by.enchanting.children[2].action, 13262); eq(by.enchanting.children[2].kind, "target")
   eq(by.disenchant, nil, "und steht darum nicht noch einmal in der Liste")
   eq(by.fishing.children, nil, "Angeln bietet nur das Angeln selbst: kein Untermenue")
   eq(by.fishing.action, 7620)
   eq(childKeys(by.cooking), "spell2550,spell818,camp_fire1", "Kochkunst, das Lagerfeuer des Zauberbuchs und das Feuer-Set (Grundfunktion: steht da, auch wenn Holz fehlt)")
   eq(by.cooking.children[3].kind, "lack")
   -- eine bekannte Faehigkeit, deren Beruf nicht erlernt ist, bekommt eine eigene Zeile
   w.setProfessions({ P.fishing(4) })
   by = entriesByKey(PM.Collect())
   eq(by.disenchant.cat, "abilities"); eq(by.disenchant.action, 13262)
   -- activities = off: weder Untermenues noch Faehigkeiten
   PM.db.activities = "off"
   w.setProfessions({ P.enchanting(1), P.mining(2) })
   by = entriesByKey(PM.Collect())
   eq(by.mining.children, nil); eq(by.enchanting.children, nil); eq(by.disenchant, nil)
end)

test("Lager: Daten sind schluessig", function()
   local w = boot()
   local PM = w.PM
   local keys, items, recipes, tiers = {}, {}, {}, {}
   for _, def in ipairs(PM.CAMP) do
      ok(not keys[def.key], "doppelter Schluessel " .. def.key); keys[def.key] = true
      ok(not items[def.item], "doppelter Gegenstand " .. def.item); items[def.item] = true
      ok(type(def.name) == "string" and def.name ~= "", def.key .. ": Name")
      ok((tiers[def.chain] or 0) < def.tier, def.key .. ": Stufen einer Kette steigen an"); tiers[def.chain] = def.tier
      if def.bagOnly then
         eq(def.recipe, nil); eq(def.prof, nil)
      else
         ok(PM.PROFESSION_BY_KEY[def.prof], def.key .. ": Beruf " .. tostring(def.prof))
         ok(not recipes[def.recipe], "doppeltes Rezept " .. def.recipe); recipes[def.recipe] = true
         ok(#def.reagents > 0, def.key .. ": Material")
         for _, reagent in ipairs(def.reagents) do
            ok(type(reagent[1]) == "number" and type(reagent[2]) == "number" and reagent[2] > 0, def.key .. ": Material")
         end
      end
   end
   eq(#PM.CAMP, 39, "38 Lager-Objekte der Berufe und der Schlafsack")
   -- jeder Beruf von Forever hat drei Stufen
   for _, key in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring",
      "mining", "herbalism", "skinning", "firstaid", "fishing" }) do
      eq(tiers[key], 3, key)
   end
   eq(tiers.fire, 3)
end)

test("Lager: Lagerfeuer als Grundfunktion - fehlt, herstellbar, im Inventar", function()
   local w = boot()
   w.setProfessions({ P.cooking(5) })
   local PM = w.PM
   PM.InitDB()
   local fire = entriesByKey(PM.Collect()).camp_fire1
   eq(fire.kind, "lack"); eq(fire.dim, true); eq(fire.tag, "fehlt"); eq(fire.action, nil); eq(fire.item, nil)
   eq(fire.name, "Basic Campfire Kit", "Ausweichname, solange der Client den Gegenstand nicht geladen hat")
   ok(w.requested[I.kit1], "der Gegenstand wurde beim Client angefordert")
   eq(table.concat(PM.Camp.Missing(fire.camp), ", "), "item:4470 0/1, item:4471")
   -- Holz allein genuegt nicht: Feuerstein und Zunder ist das Werkzeug
   w.give(I.wood, 3)
   eq(entriesByKey(PM.Collect()).camp_fire1.kind, "lack")
   w.give(I.flint, 1)
   w.itemNames[I.kit1] = "Einfaches Lagerfeuer-Set"
   fire = entriesByKey(PM.Collect()).camp_fire1
   eq(fire.kind, "craft"); eq(fire.name, "Einfaches Lagerfeuer-Set"); eq(fire.tag, "herstellen"); eq(fire.dim, nil)
   eq(fire.action, 2550, "die Zeile oeffnet zuerst die Kochkunst"); eq(fire.skillLine, 185)
   eq(fire.craft.recipe, R.kit1)
   -- mit Sternholz und Kochkunst 200: die hoehere Stufe hat Vorrang (eine Zeile je Kette)
   w.give(I.starWood, 1)
   local by = entriesByKey(PM.Collect())
   eq(by.camp_fire1, nil); eq(by.camp_fire2.kind, "craft"); eq(by.camp_fire2.craft.recipe, R.kit2)
   -- liegt ein Set im Inventar, wird es aufgestellt (auch wenn ein besseres herstellbar waere)
   w.give(I.kit1, 2)
   by = entriesByKey(PM.Collect())
   eq(by.camp_fire2, nil)
   eq(by.camp_fire1.kind, "place"); eq(by.camp_fire1.item, I.kit1); eq(by.camp_fire1.tag, "x2"); eq(by.camp_fire1.action, nil)
   -- im Untermenue der Kochkunst steht beides
   eq(childKeys(by.cooking), "spell2550,spell818,camp_fire1,camp_fire2")
   -- ohne Kochkunst kein Lagerfeuer (ein Set im Inventar laesst sich trotzdem aufstellen)
   w.setProfessions({ P.alchemy(1) })
   eq(entriesByKey(PM.Collect()).camp_fire1.kind, "place")
   w.take(I.kit1)
   eq(entriesByKey(PM.Collect()).camp_fire1, nil)
end)

test("Lager: anderes erscheint nur, wenn es aufstellbar oder herstellbar ist", function()
   local w = boot()
   w.setProfessions({ leatherworking(1), P.fishing(4) })
   local PM = w.PM
   PM.InitDB()
   local by = entriesByKey(PM.Collect())
   eq(by.camp_leatherworking1, nil, "Zelt: Leder fehlt -> keine Zeile")
   eq(by.leatherworking.children, nil)
   w.give(I.lightLeather, 4)
   eq(entriesByKey(PM.Collect()).camp_leatherworking1, nil, "vier von fuenf Leder")
   w.give(I.lightLeather, 1)
   by = entriesByKey(PM.Collect())
   eq(by.camp_leatherworking1.kind, "craft"); eq(by.camp_leatherworking1.craft.recipe, R.tent)
   eq(by.camp_leatherworking1.action, 2108)
   eq(childKeys(by.leatherworking), "spell2108,camp_leatherworking1")
   -- zu wenig Fertigkeit: nichts
   w.setProfessions({ leatherworking(1, 19) })
   eq(entriesByKey(PM.Collect()).camp_leatherworking1, nil, "Fertigkeit 19 < 20")
   -- das Zelt liegt im Inventar: aufstellen, auch ohne den Beruf
   w.setProfessions({ P.fishing(4) })
   w.give(I.tent, 1)
   by = entriesByKey(PM.Collect())
   eq(by.camp_leatherworking1.kind, "place"); eq(by.camp_leatherworking1.item, I.tent)
   -- Fischglas: ein Sammelberuf ohne Fenster-Zauber -> herstellbar, aber ohne Zauber an der Zeile
   w.give(I.smallfish, 1); w.give(I.vial, 1)
   by = entriesByKey(PM.Collect())
   eq(by.camp_fishing1.kind, "craft"); eq(by.camp_fishing1.action, nil); eq(by.camp_fishing1.craft.recipe, R.fishBowl)
   eq(childKeys(by.fishing), "spell7620,camp_fishing1")
   -- Schlafsack: nur aus der Tasche
   eq(by.camp_sleepingbag, nil)
   w.give(I.sleepingBag, 1)
   eq(entriesByKey(PM.Collect()).camp_sleepingbag.kind, "place")
   -- camp = all: auch was fehlt (abgedunkelt); camp = off: nichts
   w.setProfessions({ leatherworking(1) })
   w.take(I.tent); w.take(I.lightLeather); w.take(I.sleepingBag)
   PM.db.camp = "all"
   by = entriesByKey(PM.Collect())
   eq(by.camp_leatherworking1.kind, "lack"); eq(by.camp_leatherworking1.dim, true)
   eq(childKeys(by.leatherworking), "spell2108,camp_leatherworking1", "Stufe 2 und 3 brauchen mehr Fertigkeit")
   PM.db.camp = "off"
   by = entriesByKey(PM.Collect())
   eq(by.camp_leatherworking1, nil); eq(by.leatherworking.children, nil)
end)

test("Lager: Abklingzeit und 'hier nicht benutzbar' dunkeln die Zeile ab", function()
   local w = boot()
   w.setProfessions({ P.fishing(4) })
   w.give(I.tent, 1)
   local PM = w.PM
   PM.InitDB()
   eq(entriesByKey(PM.Collect()).camp_leatherworking1.dim, nil)
   w.unusable[I.tent] = true
   local tent = entriesByKey(PM.Collect()).camp_leatherworking1
   eq(tent.dim, true); eq(tent.kind, "place"); eq(tent.item, I.tent, "der Klick versucht es trotzdem")
   w.unusable[I.tent] = nil
   w.cooldowns[I.tent] = { start = w.time - 10, duration = 3600 }
   tent = entriesByKey(PM.Collect()).camp_leatherworking1
   eq(tent.dim, true); ok(tent.camp.cooldown > 3500)
   w.cooldowns[I.tent] = { start = w.time - 1, duration = 1.5 }       -- nur die allgemeine Abklingzeit
   eq(entriesByKey(PM.Collect()).camp_leatherworking1.dim, nil)
end)

test("Lager: Banner je Fraktion", function()
   for faction, expect in pairs({ Horde = { R.bannerHorde, I.bannerHorde }, Alliance = { R.bannerAlliance, I.bannerAlliance } }) do
      local w = boot({ faction = faction })
      w.setProfessions({ tailoring(1) })
      w.give(I.linen, 1); w.give(I.thread, 1)
      w.PM.InitDB()
      local banner = entriesByKey(w.PM.Collect()).camp_tailoring1
      eq(banner.kind, "craft"); eq(banner.craft.recipe, expect[1], faction)
      -- meldet das Spiel ein Rezept als erlernt, gilt das
      w.recipes[R.bannerHorde] = { learned = true }
      eq(entriesByKey(w.PM.Collect()).camp_tailoring1.craft.recipe, R.bannerHorde)
      -- welches Banner auch im Inventar liegt: es wird aufgestellt
      w.give(I.bannerHorde, 1)
      banner = entriesByKey(w.PM.Collect()).camp_tailoring1
      eq(banner.kind, "place"); eq(banner.item, I.bannerHorde)
   end
end)

test("UI Untermenue: oeffnet neben der Zeile, Zeilen tragen Zauber oder Gegenstand", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.mining(2), P.cooking(5) })
   w.give(I.kit1, 1)
   start(w)
   local menu = openList(w)
   local flyout = w.PM.UI.GetFlyout()
   ok(flyout:IsProtected(), "auch das Untermenue ist ein geschuetzter Zustandsrahmen")
   eq(w.stateDrivers[2].frame, flyout); eq(w.stateDrivers[2].cond, "[combat] 1; 0")
   eq(flyout:IsShown(), false)
   local mining, cooking, alchemy = rowFor(w, "mining"), rowFor(w, "cooking"), rowFor(w, "alchemy")
   eq(mining.arrow:IsShown(), true, "Winkel: hier gibt es ein Untermenue"); eq(alchemy.arrow:IsShown(), false)
   hover(mining)
   eq(flyout:IsShown(), true); eq(flyout.owner, mining)
   local sub = {}
   for _, row in ipairs(w.PM.UI.subRows) do if row:IsShown() then sub[#sub + 1] = row end end
   eq(#sub, 2)
   eq(sub[1].entry.key, "spell2656"); eq(sub[1]:GetAttribute("type1"), "spell"); eq(sub[1]:GetAttribute("spell1"), 2656)
   eq(sub[2].entry.key, "spell2580"); eq(sub[2]:GetAttribute("spell1"), 2580)
   eq(sub[1]:GetAttribute("useOnKeyDown"), false)
   -- Lage: der Knopf sitzt rechts unten, das Untermenue klappt links der Liste auf, nur an UIParent verankert
   local p = flyout._points[1]
   eq(p[1], "TOPRIGHT"); eq(p[2], w.UIParent); eq(p[3], "BOTTOMLEFT")
   ok(p[4] < menu:GetLeft(), "links der Liste")
   -- der Tooltip der Zeile steht jenseits des Untermenues
   eq(w.G.GameTooltip.anchor, "ANCHOR_NONE"); eq(w.G.GameTooltip._points[1][2], flyout)
   -- eine andere Zeile: erst nach kurzem Verweilen wechselt das Untermenue
   local update = menu:GetScript("OnUpdate")
   hover(cooking); cooking._mouseOver = true
   update(menu)
   eq(flyout.owner, mining, "noch nicht gewechselt")
   w.time = w.time + 0.2
   update(menu)
   eq(flyout.owner, cooking)
   local kit = rowFor(w, "camp_fire1", w.PM.UI.subRows)
   eq(kit:GetAttribute("type1"), "item"); eq(kit:GetAttribute("item1"), "item:279981"); eq(kit:GetAttribute("spell1"), nil)
   eq(kit.rank:GetText(), "x1")
   -- eine Zeile ohne Untermenue schliesst es
   cooking._mouseOver = false
   hover(alchemy); alchemy._mouseOver = true
   w.time = w.time + 0.2
   update(menu)
   eq(flyout:IsShown(), false)
   -- Klick im Untermenue zaehlt nicht als Klick daneben
   hover(mining)
   w.mouseDown.LeftButton = true
   alchemy._mouseOver = false; flyout._mouseOver = true
   update(menu)
   eq(menu:IsShown(), true); eq(flyout:IsShown(), true)
   flyout._mouseOver = false
   update(menu)
   eq(menu:IsShown(), false); eq(flyout:IsShown(), false, "Klick daneben schliesst beide")
end)

test("UI Untermenue: Klick wirkt den Zauber und schliesst alles", function()
   local w = boot()
   w.setProfessions({ P.mining(2) })
   start(w)
   local menu = openList(w)
   hover(rowFor(w, "mining"))
   w.click(rowFor(w, "spell2580", w.PM.UI.subRows), "LeftButton")
   eq(#w.casts, 1); eq(w.casts[1], 2580)
   eq(menu:IsShown(), false); eq(w.PM.UI.GetFlyout():IsShown(), false)
end)

test("UI Lager: aufstellen benutzt den Gegenstand", function()
   local w = boot()
   w.setProfessions({ P.fishing(4) })
   w.give(I.tent, 1)
   w.itemNames[I.tent] = "Campingzelt"
   start(w)
   local menu = openList(w)
   local tent = rowFor(w, "camp_leatherworking1")
   eq(tent.text:GetText(), "Campingzelt"); eq(tent.rank:GetText(), "x1")
   eq(tent:GetAttribute("type1"), "item"); eq(tent:GetAttribute("item1"), "item:279978")
   local headers = {}
   for _, h in ipairs(w.PM.UI.headers) do if h.text:IsShown() then headers[#headers + 1] = h.text:GetText() end end
   eq(table.concat(headers, ","), "Hauptberufe,Nebenberufe,Lager")
   hover(tent)
   local tip = table.concat(w.G.GameTooltip.lines, "\n")
   ok(tip:find("Im Inventar: 1", 1, true)); ok(tip:find("Linksklick: aufstellen", 1, true))
   w.click(tent, "LeftButton")
   eq(#w.uses, 1); eq(w.uses[1], "item:279978"); eq(#w.casts, 0)
   eq(menu:IsShown(), false)
   -- verbraucht: die Zeile verschwindet
   w.take(I.tent)
   w.fire("BAG_UPDATE_DELAYED")
   openList(w)
   eq(rowFor(w, "camp_leatherworking1"), nil)
end)

test("UI Lager: herstellen - Beruf zu: der Klick oeffnet ihn, danach wird hergestellt", function()
   local w = boot()
   w.setProfessions({ leatherworking(1) })
   w.give(I.lightLeather, 5)
   w.craftMakes[R.tent] = { item = I.tent, uses = { { I.lightLeather, 5 } } }
   start(w)
   local menu = openList(w)
   local tent = rowFor(w, "camp_leatherworking1")
   eq(tent.entry.kind, "craft"); eq(tent:GetAttribute("type1"), "spell"); eq(tent:GetAttribute("spell1"), 2108)
   hover(tent)
   local tip = table.concat(w.G.GameTooltip.lines, "\n")
   ok(tip:find("Material ist vorhanden", 1, true)); ok(tip:find("Lederverarbeitung (Fertigkeit 20)", 1, true))
   ok(tip:find("item:2318  5/5", 1, true)); ok(tip:find("Linksklick: herstellen", 1, true))
   w.click(tent, "LeftButton")
   eq(#w.casts, 1); eq(w.casts[1], 2108, "der Klick oeffnet die Lederverarbeitung")
   eq(#w.crafts, 0, "noch nichts hergestellt: das Fenster ist noch nicht bereit")
   eq(menu:IsShown(), true, "die Liste bleibt offen")
   -- das Fenster meldet sich
   openProfession(w, 165)
   w.fire("TRADE_SKILL_SHOW")
   eq(#w.crafts, 1); eq(w.crafts[1], R.tent); eq(w.openedRecipes[1], R.tent)
   -- hergestellt: aus der Zeile ist "aufstellen" geworden
   tent = rowFor(w, "camp_leatherworking1")
   eq(tent.entry.kind, "place"); eq(tent:GetAttribute("type1"), "item"); eq(tent:GetAttribute("item1"), "item:279978")
   w.advance(2)
   ok(not chatHas(w, "noch einmal klicken"), "keine Meldung, es hat geklappt")
   w.fire("TRADE_SKILL_LIST_UPDATE")
   eq(#w.crafts, 1, "ein weiteres Ereignis stellt nicht noch einmal her")
   w.click(tent, "LeftButton")
   eq(w.uses[1], "item:279978")
end)

test("UI Lager: herstellen - verlangt der Client einen Tastendruck, bittet eine Meldung um den zweiten Klick", function()
   local w = boot()
   w.craftNeedsClick = true
   w.setProfessions({ leatherworking(1) })
   w.give(I.lightLeather, 5)
   w.itemNames[I.tent] = "Campingzelt"
   w.craftMakes[R.tent] = { item = I.tent, uses = { { I.lightLeather, 5 } } }
   start(w)
   openList(w)
   w.click(rowFor(w, "camp_leatherworking1"), "LeftButton")
   openProfession(w, 165)
   w.fire("TRADE_SKILL_LIST_UPDATE")
   eq(#w.crafts, 1, "der Versuch aus dem Ereignis")
   eq(rowFor(w, "camp_leatherworking1").entry.kind, "craft", "nichts entstanden")
   w.advance(2)
   ok(chatHas(w, "Campingzelt: Das Berufsfenster ist bereit - zum Herstellen noch einmal klicken."))
   -- zweiter Klick: das Fenster ist offen -> kein Zauber, sofort herstellen
   local tent = rowFor(w, "camp_leatherworking1")
   w.click(tent, "LeftButton")
   eq(#w.casts, 1, "kein zweites Oeffnen"); eq(#w.crafts, 2)
   eq(tent:GetAttribute("type1"), "item", "hergestellt: die Zeile stellt jetzt auf")
   eq(rowFor(w, "camp_leatherworking1").entry.kind, "place")
   w.advance(5)
   ok(not chatHas(w, "hat nicht begonnen"))
end)

test("UI Lager: herstellen scheitert trotz offenem Fenster -> Meldung; wartender Klick verfaellt", function()
   local w = boot()
   w.setProfessions({ leatherworking(1) })
   w.give(I.lightLeather, 5)
   start(w)
   openProfession(w, 165)
   openList(w)
   w.click(rowFor(w, "camp_leatherworking1"), "LeftButton")
   eq(#w.casts, 0); eq(#w.crafts, 1)
   w.advance(2)
   ok(chatHas(w, "Basic Campfire Kit") == false)
   ok(chatHas(w, "Camp Tent: Das Herstellen hat nicht begonnen"), "Rezept nicht erlernt: nichts entstand")
   -- solange gezaubert wird, wartet die Pruefung
   w.click(rowFor(w, "camp_leatherworking1"), "LeftButton")
   w.casting = "Campingzelt"
   local before = #w.chat
   w.advance(1.5)
   eq(#w.chat, before, "noch keine Meldung")
   -- ein Klick bei geschlossenem Fenster, das nie bereit wird, verfaellt nach einer Weile
   w.casting = nil
   w.advance(30)
   w.openSkillLine = 0
   w.click(rowFor(w, "camp_leatherworking1"), "LeftButton")
   w.advance(60)
   openProfession(w, 165)
   local crafts = #w.crafts
   w.fire("TRADE_SKILL_SHOW")
   eq(#w.crafts, crafts, "zu spaet: kein ueberraschendes Herstellen")
end)

test("UI Lager: herstellen - bleibt das Ereignis aus, versucht es ein Zeitgeber", function()
   local w = boot()
   w.setProfessions({ leatherworking(1) })
   w.give(I.lightLeather, 5)
   w.craftMakes[R.tent] = { item = I.tent, uses = { { I.lightLeather, 5 } } }
   start(w)
   openList(w)
   w.click(rowFor(w, "camp_leatherworking1"), "LeftButton")
   -- das Fenster ist offen, aber das Spiel nennt dafuer eine andere Berufsnummer und kein Ereignis kommt an
   openProfession(w, 99165)
   eq(#w.crafts, 0)
   w.advance(1.6)
   eq(#w.crafts, 1); eq(w.crafts[1], R.tent)
   eq(rowFor(w, "camp_leatherworking1").entry.kind, "place")
end)

test("UI Lager: Sammelberuf ohne Fenster-Zauber - Klick zeigt die Berufsuebersicht", function()
   local w = boot()
   w.setProfessions({ P.fishing(4) })
   w.give(I.smallfish, 1); w.give(I.vial, 1)
   w.craftMakes[R.fishBowl] = { item = I.fishBowl }
   start(w)
   openList(w)
   local bowl = rowFor(w, "camp_fishing1")
   eq(bowl:GetAttribute("type1"), nil, "kein Zauber, der das Fenster oeffnet")
   w.click(bowl, "LeftButton")
   eq(w.toggled, 1, "Berufsuebersicht"); eq(#w.crafts, 0)
   ok(chatHas(w, "Wähle im Berufsfenster Angeln"))
   openProfession(w, 356)                    -- der Spieler waehlt dort Angeln
   w.fire("TRADE_SKILL_SHOW")
   eq(w.crafts[1], R.fishBowl)
end)

test("UI Lager: fehlt Material, nennt der Klick es und oeffnet nichts", function()
   local w = boot()
   w.setProfessions({ P.cooking(5) })
   w.itemNames[I.wood] = "Einfaches Holz"; w.itemNames[I.flint] = "Feuerstein und Zunder"
   start(w)
   local menu = openList(w)
   local fire = rowFor(w, "camp_fire1")
   eq(fire.entry.kind, "lack"); eq(fire:GetAttribute("type1"), nil); eq(fire.rank:GetText(), "fehlt")
   hover(fire)
   local tip = table.concat(w.G.GameTooltip.lines, "\n")
   ok(tip:find("Material fehlt", 1, true)); ok(tip:find("Einfaches Holz  0/1", 1, true))
   ok(tip:find("Werkzeug: Feuerstein und Zunder", 1, true)); ok(tip:find("Kochkunst (Fertigkeit 1)", 1, true))
   w.click(fire, "LeftButton")
   eq(w.lastError, "Es fehlt: Einfaches Holz 0/1, Feuerstein und Zunder")
   eq(w.toggled, 0); eq(#w.casts, 0); eq(#w.crafts, 0); eq(menu:IsShown(), true)
   -- das Material kommt ins Inventar: die offene Liste zieht nach
   w.give(I.wood, 1); w.give(I.flint, 1)
   w.fire("BAG_UPDATE_DELAYED")
   eq(rowFor(w, "camp_fire1").entry.kind, "craft"); eq(rowFor(w, "camp_fire1"):GetAttribute("spell1"), 2550)
end)

test("UI Lager: nachgeladene Namen erneuern die offene Liste; fremde Gegenstaende nicht", function()
   local w = boot()
   w.setProfessions({ P.fishing(4) })
   w.give(I.tent, 1)
   start(w)
   ok(w.requested[I.tent] and w.requested[I.wood], "beim Anmelden werden die Gegenstaende angefordert")
   openList(w)
   eq(rowFor(w, "camp_leatherworking1").text:GetText(), "Camp Tent")
   w.itemNames[I.tent] = "Campingzelt"
   w.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
   eq(rowFor(w, "camp_leatherworking1").text:GetText(), "Camp Tent", "ein fremder Gegenstand stoesst nichts an")
   w.fire("GET_ITEM_INFO_RECEIVED", I.tent, true)
   eq(rowFor(w, "camp_leatherworking1").text:GetText(), "Campingzelt")
end)

test("UI Untermenue und Lager: im Kampf ruehrt nichts die geschuetzten Rahmen an", function()
   local w = boot()
   w.setProfessions({ P.mining(2), P.cooking(5) })
   w.give(I.kit1, 1)
   start(w)
   local menu = openList(w)
   hover(rowFor(w, "mining"))
   local flyout = w.PM.UI.GetFlyout()
   w.combat = true
   w.fire("PLAYER_REGEN_DISABLED")
   w.give(I.wood, 1)
   w.fire("BAG_UPDATE_DELAYED")
   w.fire("GET_ITEM_INFO_RECEIVED", I.kit1, true)
   w.fire("TRADE_SKILL_SHOW")
   hover(rowFor(w, "cooking"))
   menu:GetScript("OnUpdate")(menu)
   menu._shown = false; flyout._shown = false          -- das tun im Spiel die Zustandstreiber
   w.combat = false
   w.fire("PLAYER_REGEN_ENABLED")
   openList(w)
   eq(rowFor(w, "camp_fire1").entry.kind, "place")
end)

test("UI Untermenue: nur Symbole - die Liste zeigt Zellen, das Untermenue Text", function()
   local w = boot()
   w.setProfessions({ P.mining(2) })
   start(w)
   w.PM.Command("compact all")
   local menu = openList(w)
   local S = w.PM.UI.sizes
   local mining = rowFor(w, "mining")
   eq(menu:GetWidth(), S.cell); eq(mining.arrow:IsShown(), false)
   hover(mining)
   local flyout = w.PM.UI.GetFlyout()
   eq(flyout:IsShown(), true)
   local sub = rowFor(w, "spell2580", w.PM.UI.subRows)
   eq(sub.text:IsShown(), true); eq(sub:GetHeight(), S.rowH); ok(flyout:GetWidth() > S.cell)
end)

-- ---------------------------------------------------------------------------
-- Befehle, Diagnose, Einstellungsfenster
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Platzhalter fuer nicht erlernte Berufe
-- ---------------------------------------------------------------------------

local function keysOf(entries)
   local t = {}
   for i, e in ipairs(entries) do t[i] = e.key end
   return table.concat(t, ",")
end

test("Platzhalter: nichts erlernt -> zwei Hauptberufe, dann Kochkunst, Erste Hilfe, Angeln", function()
   local w = boot()
   w.setProfessions({})
   local PM = w.PM
   PM.InitDB()
   local entries = PM.Collect()
   eq(keysOf(entries), "open1,open2,open_cooking,open_firstaid,open_fishing")
   local by = entriesByKey(entries)
   eq(by.open1.name, "Hauptberuf"); eq(by.open1.cat, "primary"); eq(by.open1.open, "primary")
   eq(by.open_cooking.name, "Kochkunst"); eq(by.open_firstaid.name, "Erste Hilfe"); eq(by.open_fishing.name, "Angeln")
   eq(by.open_fishing.cat, "secondary"); eq(by.open_fishing.open, "secondary")
   for _, e in ipairs(entries) do
      eq(e.kind, "open"); eq(e.action, nil); eq(e.item, nil); eq(e.dim, true); eq(e.maxRank, 0)
   end
   local layout = PM.Layout(entries)
   eq(layout[1].header, "primary"); eq(layout[4].header, "secondary"); eq(#layout, 7)
   eq(PM.L.cat_primary, "Hauptberufe")
end)

test("Platzhalter: nur was fehlt - ein Hauptberuf frei, erlernte Nebenberufe ohne Platzhalter", function()
   local w = boot()
   local PM = w.PM
   PM.InitDB()
   w.setProfessions({ P.mining(1), P.cooking(5) })
   eq(keysOf(PM.Collect()), "mining,open2,cooking,open_firstaid,open_fishing,camp_fire1",
      "der freie Hauptberuf steht hinter den erlernten, vor den Nebenberufen")
   w.setProfessions({ P.mining(1), P.alchemy(2), P.firstaid(3), P.fishing(4), P.cooking(5) })
   eq(keysOf(PM.Collect()), "alchemy,mining,cooking,firstaid,fishing,camp_fire1", "alles erlernt: kein Platzhalter")
   -- ein Hauptberuf, den die Tabelle nicht kennt, belegt trotzdem einen Platz
   w.setProfessions({ prof("Neuer Beruf", 90001, 2, 10, 100, { { id = 90010, name = "Neuer Beruf", window = true } }),
      P.firstaid(3), P.fishing(4), P.cooking(5) })
   local by = entriesByKey(PM.Collect())
   ok(by.open2 and not by.open1, "genau ein freier Hauptberuf")
   -- ein unbekannter Nebenberuf belegt keinen Hauptberuf-Platz
   w.setProfessions({ prof("Neuer Nebenberuf", 90003, 3, 10, 100, { { id = 90030, name = "Neuer Nebenberuf", window = true } }) })
   by = entriesByKey(PM.Collect())
   ok(by.open1 and by.open2, "beide Hauptberufe frei")
   -- Archaeologie gibt es in Forever nicht zu erlernen: kein Platzhalter
   eq(by.open_archaeology, nil)
end)

test("Platzhalter: Einstellung unlearned schaltet sie ab; die Signatur aendert sich", function()
   local w = boot()
   local PM = w.PM
   PM.InitDB()
   eq(PM.db.unlearned, true, "Voreinstellung")
   w.setProfessions({ P.alchemy(1) })
   local with = PM.Signature(PM.Collect())
   PM.db.unlearned = false
   eq(keysOf(PM.Collect()), "alchemy")
   ok(PM.Signature(PM.Collect()) ~= with)
   w.G.ProfessionMenuDB.unlearned = "kaputt"
   PM.InitDB()
   eq(PM.db.unlearned, true, "kaputter Wert wird ersetzt")
end)

test("Platzhalter: der Text der Sprache des Clients (englisch)", function()
   local w = boot({ locale = "enUS" })
   w.setProfessions({})
   w.PM.InitDB()
   local by = entriesByKey(w.PM.Collect())
   eq(by.open1.name, "Primary profession"); eq(by.open_firstaid.name, "First Aid")
end)

test("Skin.DashPlan: Striche auf ganzen Pixeln, an beiden Enden ein Strich, Luecken dazwischen", function()
   local w = boot()
   local Skin = w.PM.Skin
   local mult = Skin.Mult()
   local function px(v) return v / mult end
   for length = 1, 400 do
      local plan = Skin.DashPlan(length * mult)
      ok(#plan >= 1)
      eq(plan[1][1], 0, "beginnt an der Ecke")
      local last = plan[#plan]
      ok(math.abs(px(last[1] + last[2]) - length) < 1e-6, "endet an der Ecke (Laenge " .. length .. ")")
      for i, dash in ipairs(plan) do
         ok(math.abs(px(dash[1]) - math.floor(px(dash[1]) + 0.5)) < 1e-6, "ganzer Pixel")
         if i > 1 then
            local gap = px(dash[1] - (plan[i - 1][1] + plan[i - 1][2]))
            ok(gap >= 3 - 1e-6 and gap <= 4 + 1e-6, "Luecke 3 oder 4 Pixel, war " .. gap .. " bei Laenge " .. length)
         end
         if #plan > 1 then
            ok(px(dash[2]) >= 4 - 1e-6 and px(dash[2]) <= 7 + 1e-6, "Strich 4 bis 7 Pixel, war " .. px(dash[2]) .. " bei Laenge " .. length)
         end
         if length >= 60 then ok(math.abs(px(dash[2]) - 4) < 1e-6, "lange Kante: alle Striche 4 Pixel") end
      end
      if length >= 11 then ok(#plan >= 2, "ab 11 Pixeln mehr als ein Strich") end
   end
end)

-- sichtbare Striche des gestrichelten Rahmens einer Zeile
local function dashes(row)
   local list = {}
   local holder = row.pmDashes
   if holder then
      for i = 1, #holder.pool do
         if holder.pool[i]:IsShown() then list[#list + 1] = holder.pool[i] end
      end
   end
   return list
end

test("UI Platzhalter: gestrichelter Rahmen um die Zeile, keine Aktion, kleineres Symbolfeld", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   start(w)
   local menu = openList(w)
   local S = w.PM.UI.sizes
   eq(keysOf((function() local t = {} for i, r in ipairs(shownRows(w)) do t[i] = r.entry end return t end)()),
      "alchemy,open2,open_cooking,open_firstaid,fishing")
   local alch, open, cook, fish = rowFor(w, "alchemy"), rowFor(w, "open2"), rowFor(w, "open_cooking"), rowFor(w, "fishing")
   eq(#dashes(alch), 0, "erlernter Beruf: kein Rahmen"); eq(#dashes(fish), 0)
   ok(#dashes(open) > 20, "Platzhalter: viele Striche"); ok(#dashes(cook) > 20)
   eq(open.text:GetText(), "Hauptberuf"); eq(open.rank:GetText(), "")
   eq(cook.text:GetText(), "Kochkunst")
   eq(open:GetAttribute("type1"), nil); eq(open:GetAttribute("spell1"), nil); eq(open:GetAttribute("item1"), nil)
   eq(open.box:GetWidth(), S.icon - 2 * S.shrink); eq(alch.box:GetWidth(), S.icon)
   eq(open.sep:IsShown(), false, "keine Trennlinie unter dem Rahmen")
   eq(alch.sep:IsShown(), false, "und keine darueber")
   -- der Rahmen liegt innerhalb der Zeile und reicht bis an ihre Raender (ein Pixel Abstand)
   local holder = open.pmDashes
   eq(holder.width, menu:GetWidth() - 2 * S.pad - 2 * S.dashInset)
   eq(holder.height, S.rowH - 2 * S.dashInset)
   local horizontal, vertical = 0, 0
   for _, tex in ipairs(dashes(open)) do
      local point, anchor, _, x, y = unpack(tex._points[#tex._points])
      eq(point, "TOPLEFT"); eq(anchor, open)
      ok(x >= S.dashInset - 1e-9 and x + tex:GetWidth() <= S.dashInset + holder.width + 1e-9, "waagerecht in der Zeile")
      ok(-y >= S.dashInset - 1e-9 and -y + tex:GetHeight() <= S.dashInset + holder.height + 1e-9, "senkrecht in der Zeile")
      if tex:GetHeight() == S.line then horizontal = horizontal + 1 else vertical = vertical + 1 end
      ok(tex._color and tex._color[4] < 1, "gedimmt")
   end
   ok(horizontal >= 2 * 10 and vertical >= 2 * 2, "oben und unten viele Striche, links und rechts einige")
end)

test("UI Platzhalter: Tooltip erklaert, Klick zeigt die Berufsuebersicht", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   openList(w)
   local open, aid = rowFor(w, "open2"), rowFor(w, "open_firstaid")
   hover(open)
   local tip = w.G.GameTooltip
   eq(tip.lines[1], "Hauptberuf")
   ok(tip.lines[2]:find("Freier Platz", 1, true)); eq(tip.lines[5], "Klick: Berufe"); eq(#tip.lines, 5)
   hover(aid)
   eq(tip.lines[1], "Erste Hilfe"); ok(tip.lines[2]:find("Noch nicht erlernt", 1, true))
   eq(tip.lines[4], "Klick: Berufe"); eq(#tip.lines, 4)
   w.click(open, "LeftButton")
   eq(#w.casts, 0); eq(#w.uses, 0); eq(w.toggled, 1); eq(w.PM.UI.GetMenu():IsShown(), false)
   openList(w)
   w.click(rowFor(w, "open_firstaid"), "RightButton")
   eq(w.toggled, 2)
end)

test("UI Platzhalter: wird der Beruf erlernt, verschwindet der Rahmen (Zeilen werden wiederverwendet)", function()
   local w = boot()
   w.setProfessions({})
   start(w)
   openList(w)
   local rows = shownRows(w)
   eq(#rows, 5)
   eq(w.PM.UI.GetMenu().empty:IsShown(), false, "Platzhalter statt 'Keine Berufe erlernt'")
   for _, row in ipairs(rows) do ok(#dashes(row) > 0) end
   w.setProfessions({ P.alchemy(1), P.mining(2), P.firstaid(3), P.fishing(4), P.cooking(5) })
   w.fire("SKILL_LINES_CHANGED")
   for _, row in ipairs(shownRows(w)) do
      eq(#dashes(row), 0, row.entry.key)
      eq(row.box:GetWidth(), w.PM.UI.sizes.icon, "Symbolfeld wieder in voller Groesse")
   end
   -- abschalten: Zeilen verschwinden, ihre Striche auch
   w.setProfessions({ P.alchemy(1) })
   w.fire("SKILL_LINES_CHANGED")
   ok(#dashes(rowFor(w, "open2")) > 0)
   w.PM.Command("unlearned off")
   eq(#shownRows(w), 1)
   for _, row in ipairs(w.PM.UI.rows) do eq(#dashes(row), 0) end
end)

test("UI Platzhalter: nur Symbole - der Rahmen umschliesst die Zelle; im Kampf bleibt alles ruhig", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   w.PM.Command("compact all")
   local menu = openList(w)
   local S = w.PM.UI.sizes
   local open = rowFor(w, "open2")
   eq(open:GetHeight(), S.cell); eq(open.box:GetWidth(), S.cellIcon - 2 * S.shrink)
   eq(open.pmDashes.width, menu:GetWidth() - 2 * S.pad - 2 * S.dashInset)
   eq(open.pmDashes.height, S.cell - 2 * S.dashInset)
   ok(#dashes(open) >= 12)
   -- im Kampf aendert sich der Bestand: nichts wird angefasst, danach stimmt die Liste
   w.combat = true
   w.fire("PLAYER_REGEN_DISABLED")
   w.setProfessions({ P.alchemy(1), P.mining(2) })
   w.fire("SKILL_LINES_CHANGED")
   ok(#dashes(open) >= 12, "im Kampf unveraendert")
   menu._shown = false                               -- das tut im Spiel der Zustandstreiber "[combat]"
   w.combat = false
   w.fire("PLAYER_REGEN_ENABLED")
   openList(w)
   eq(rowFor(w, "open2"), nil)
   for _, row in ipairs(shownRows(w)) do
      if not row.entry.open then eq(#dashes(row), 0, row.entry.key) end
   end
end)

-- ---------------------------------------------------------------------------
-- Erlernbare Berufe und die Charaktere des Kontos
-- ---------------------------------------------------------------------------

test("Erlernbar: ein freier Hauptberuf traegt als Untermenue die Hauptberufe, die noch nicht erlernt sind", function()
   local w = boot()
   local PM = w.PM
   PM.InitDB()
   w.setProfessions({})
   local by = entriesByKey(PM.Collect())
   eq(childKeys(by.open1),
      "learn_blacksmithing,learn_leatherworking,learn_tailoring,learn_engineering,learn_alchemy,learn_enchanting,"
      .. "learn_mining,learn_herbalism,learn_skinning", "die neun Hauptberufe von Forever")
   eq(childKeys(by.open2), childKeys(by.open1), "beide freien Plaetze zeigen dieselbe Liste")
   eq(by.open_cooking.children, nil, "ein Nebenberuf hat kein Untermenue")
   local smith = by.open1.children[1]
   eq(smith.name, "Schmiedekunst"); eq(smith.kind, "learn"); eq(smith.action, nil); eq(smith.tag, nil); eq(smith.alts, nil)
   -- was der Charakter schon hat, fehlt in der Liste
   w.setProfessions({ P.alchemy(1) })
   by = entriesByKey(PM.Collect())
   ok(not childKeys(by.open2):find("learn_alchemy", 1, true))
   eq(#by.open2.children, 8)
   -- auch ohne Untermenues fuer Taetigkeiten
   PM.db.activities = "off"
   eq(#entriesByKey(PM.Collect()).open2.children, 8)
end)

test("Konto: die Berufe des Charakters werden gemerkt und aktuell gehalten", function()
   local w = boot({ player = "Dope", realm = "Everlook" })
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   start(w)
   local chars = w.G.ProfessionMenuDB.chars
   local me = chars["Dope-Everlook"]
   ok(me, "beim Anmelden gemerkt")
   eq(me.name, "Dope"); eq(me.realm, "Everlook"); eq(me.profs.alchemy, 300); eq(me.profs.fishing, 50)
   eq(me.profs.mining, nil)
   -- neuer Beruf, bei geschlossener Liste
   w.setProfessions({ P.alchemy(1), P.mining(2), P.fishing(4) })
   w.fire("SKILL_LINES_CHANGED")
   eq(chars["Dope-Everlook"].profs.mining, 75)
   -- verlernt
   w.setProfessions({ P.mining(2) })
   w.fire("SKILL_LINES_CHANGED")
   eq(chars["Dope-Everlook"].profs.alchemy, nil); eq(chars["Dope-Everlook"].profs.mining, 75)
   -- lassen sich die Berufe nicht lesen, bleibt der Stand
   w.G.GetProfessions = nil
   w.fire("SKILL_LINES_CHANGED")
   eq(chars["Dope-Everlook"].profs.mining, 75)
end)

local function accountWithAlts()
   return {
      chars = {
         ["Schneiderlein-Everlook"] = { name = "Schneiderlein", realm = "Everlook", profs = { tailoring = 225, enchanting = 150, cooking = 300 } },
         ["Bergmann-Everlook"] = { name = "Bergmann", realm = "Everlook", profs = { mining = 300, enchanting = 40 } },
         ["Fern-Lakeshire"] = { name = "Fern", realm = "Lakeshire", profs = { enchanting = 275 } },
         ["Dope-Everlook"] = { name = "Dope", realm = "Everlook", profs = { skinning = 300 } },       -- der Charakter selbst (alt)
      },
   }
end

test("Konto: erlernbare Berufe, die ein anderer Charakter schon hat, sind markiert", function()
   local w = boot({ player = "Dope", realm = "Everlook" })
   w.G.ProfessionMenuDB = accountWithAlts()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local by = entriesByKey(w.PM.Collect())
   local learn = entriesByKey(by.open2.children)
   eq(learn.learn_tailoring.tag, "Schneiderlein"); eq(#learn.learn_tailoring.alts, 1); eq(learn.learn_tailoring.alts[1].rank, 225)
   eq(learn.learn_mining.tag, "Bergmann")
   eq(learn.learn_enchanting.tag, "Fern-Lakeshire +2", "hoechste Stufe zuerst; anderer Realm mit Realm")
   eq(learn.learn_enchanting.alts[2].label, "Schneiderlein"); eq(learn.learn_enchanting.alts[3].label, "Bergmann")
   eq(learn.learn_blacksmithing.tag, nil, "niemand hat Schmiedekunst")
   eq(learn.learn_skinning.tag, nil, "der eigene (veraltete) Eintrag zaehlt nicht als anderer Charakter")
   eq(w.G.ProfessionMenuDB.chars["Dope-Everlook"].profs.skinning, nil, "und ist jetzt aktuell")
   eq(w.G.ProfessionMenuDB.chars["Dope-Everlook"].profs.alchemy, 300)
end)

test("Konto: kaputte gemerkte Charaktere werden verworfen", function()
   local w = boot()
   w.G.ProfessionMenuDB = { chars = {
      ["Gut-Everlook"] = { name = "Gut", realm = "Everlook", profs = { mining = 10, alchemy = "viel" } },
      ["Kaputt-Everlook"] = "x", ["Ohne-Everlook"] = { name = "Ohne", realm = "Everlook" }, [5] = {},
   } }
   w.setProfessions({})
   start(w)
   local chars = w.G.ProfessionMenuDB.chars
   ok(chars["Gut-Everlook"]); eq(chars["Gut-Everlook"].profs.mining, 10); eq(chars["Gut-Everlook"].profs.alchemy, nil)
   eq(chars["Kaputt-Everlook"], nil); eq(chars["Ohne-Everlook"], nil); eq(chars[5], nil)
   w.G.ProfessionMenuDB.chars = "kaputt"
   w.PM.InitDB()
   eq(type(w.G.ProfessionMenuDB.chars), "table")
   openList(w)
end)

test("UI Erlernbar: Untermenue am freien Hauptberuf, Markierung rechts, Tooltip nennt die Charaktere", function()
   local w = boot({ player = "Dope", realm = "Everlook" })
   w.G.ProfessionMenuDB = accountWithAlts()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   openList(w)
   local open = rowFor(w, "open2")
   eq(open.arrow:IsShown(), true, "Winkel: hier gibt es ein Untermenue")
   local flyout = w.PM.UI.GetFlyout()
   eq(flyout:IsShown(), false)
   hover(open)
   eq(flyout:IsShown(), true)
   local tip = w.G.GameTooltip
   eq(tip.lines[1], "Hauptberuf"); eq(tip.lines[4], "Erlernbare Berufe stehen im Untermenü neben dieser Zeile")
   eq(tip.lines[5], "Klick: Berufe"); eq(#tip.lines, 5)
   local subs = {}
   for _, row in ipairs(w.PM.UI.subRows) do if row:IsShown() then subs[#subs + 1] = row end end
   eq(#subs, 8)
   local tailor, smith = rowFor(w, "learn_tailoring", w.PM.UI.subRows), rowFor(w, "learn_blacksmithing", w.PM.UI.subRows)
   eq(tailor.text:GetText(), "Schneiderei"); eq(tailor.rank:GetText(), "Schneiderlein")
   eq(smith.rank:GetText(), "")
   eq(tailor:GetAttribute("type1"), nil); eq(tailor:GetAttribute("spell1"), nil)
   eq(tailor.pmDashes, nil, "Zeilen des Untermenues haben keinen gestrichelten Rahmen")
   eq(tailor.box:GetWidth(), w.PM.UI.sizes.icon)
   hover(tailor)
   eq(tip.lines[1], "Schneiderei"); eq(tip.lines[3], "Schon auf diesem Konto:"); eq(tip.lines[4], "  Schneiderlein  225")
   eq(tip.lines[#tip.lines], "Klick: Berufe")
   hover(rowFor(w, "learn_enchanting", w.PM.UI.subRows))
   eq(tip.lines[4], "  Fern-Lakeshire  275"); eq(tip.lines[5], "  Schneiderlein  150"); eq(tip.lines[6], "  Bergmann  40")
   hover(smith)
   eq(tip.lines[3], "Kein anderer bekannter Charakter hat diesen Beruf.")
   -- ein Klick wirkt nichts und zeigt die Berufsuebersicht
   w.click(tailor, "LeftButton")
   eq(#w.casts, 0); eq(#w.uses, 0); eq(w.toggled, 1)
   eq(flyout:IsShown(), false); eq(w.PM.UI.GetMenu():IsShown(), false)
   -- nur Symbole: das Untermenue bleibt eine Textliste
   w.PM.Command("compact all")
   openList(w)
   hover(rowFor(w, "open2"))
   eq(flyout:IsShown(), true)
   eq(rowFor(w, "learn_tailoring", w.PM.UI.subRows).text:IsShown(), true)
end)

test("Befehl alts: nennt die gemerkten Charaktere; alts clear vergisst die anderen", function()
   local w = boot({ player = "Dope", realm = "Everlook" })
   w.G.ProfessionMenuDB = accountWithAlts()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   w.PM.Command("alts")
   ok(chatHas(w, "Bekannte Charaktere und ihre Berufe:"))
   ok(chatHas(w, "Schneiderlein-Everlook: Schneiderei 225, Verzauberkunst 150, Kochkunst 300"))
   ok(chatHas(w, "Dope-Everlook: Alchemie 300"))
   openList(w)
   eq(entriesByKey(rowFor(w, "open2").entry.children).learn_tailoring.tag, "Schneiderlein")
   w.PM.Command("alts clear")
   ok(chatHas(w, "Die anderen Charaktere sind vergessen."))
   local chars = w.G.ProfessionMenuDB.chars
   eq(chars["Schneiderlein-Everlook"], nil); ok(chars["Dope-Everlook"], "der angemeldete Charakter bleibt")
   eq(entriesByKey(rowFor(w, "open2").entry.children).learn_tailoring.tag, nil, "die offene Liste ist aktuell")
end)

test("Knopf: entsperrt nennt der Tooltip das Ziehen", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local button = w.PM.UI.GetButton()
   button:GetScript("OnEnter")(button)
   eq(#w.G.GameTooltip.lines, 2)
   w.PM.Command("unlock")
   button:GetScript("OnEnter")(button)
   eq(w.G.GameTooltip.lines[3], "Entsperrt: mit der linken Maustaste ziehen")
end)

test("Befehle: Eingaben pruefen, Hilfe bei Unsinn", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1) })
   start(w)
   local PM = w.PM
   PM.Command("sort alpha"); eq(PM.db.sort, "alpha")
   PM.Command("sort quatsch"); eq(PM.db.sort, "alpha"); ok(chatHas(w, "/berufe [toggle]"), "Hilfe")
   PM.Command("headers aus"); eq(PM.db.headers, false)
   PM.Command("ranks off"); eq(PM.db.ranks, false)
   PM.Command("activities list"); eq(PM.db.activities, "list")
   PM.Command("activities quatsch"); eq(PM.db.activities, "list")
   PM.Command("camp all"); eq(PM.db.camp, "all")
   PM.Command("camp off"); eq(PM.db.camp, "off")
   PM.Command("unlearned aus"); eq(PM.db.unlearned, false)
   PM.Command("unlearned vielleicht"); eq(PM.db.unlearned, false)
   PM.Command("unlearned on"); eq(PM.db.unlearned, true)
   PM.Command("direction up"); eq(PM.db.direction, "up")
   PM.Command("headers maybe"); eq(PM.db.headers, false)
   PM.Command("nonsense")
   PM.Command("debug"); eq(PM.debug, true); PM.Command("debug"); eq(PM.debug, false)
   PM.Command("toggle"); eq(w.PM.UI.GetMenu():IsShown(), true)
   PM.Command("")
   eq(w.PM.UI.GetMenu():IsShown(), false)
end)

test("Befehl list: nennt Berufe, Zauber und Fenster-Zauber", function()
   local w = boot()
   w.setProfessions({ P.mining(1) })
   start(w)
   w.PM.Command("list")
   ok(chatHas(w, "Erkannte Berufe:"))
   ok(chatHas(w, "Bergbau (Fertigkeitszeile 186, 75/300)"))
   ok(chatHas(w, "Zauber 2656: Verhüttung [window]"))
   ok(chatHas(w, "Zauber 2580: Mineralien aufspüren"))
   w.setProfessions({})
   w.PM.Command("list")
   ok(chatHas(w, "(keine Berufe gelesen)"))
end)

test("Befehl diag: schreibt Zeilen in die SavedVariables und fasst im Chat zusammen", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.mining(2) })
   start(w)
   openList(w)
   w.PM.Command("diag")
   local diag = w.PM.db.diag
   ok(diag and #diag.lines > 40, "Diagnosezeilen")
   local text = table.concat(diag.lines, "\n")
   ok(text:find("build: 1.60.1 (70862", 1, true), "Bauversion")
   ok(text:find("CVar ActionButtonUseKeyDown = 1", 1, true))
   ok(text:find("C_SpellBook.GetSpellBookItemInfo = yes", 1, true))
   ok(text:find("GetSkillLineInfo = NO", 1, true), "alte Funktion fehlt wie erwartet")
   ok(text:find("slot 101: 2259 Alchemie [opens window]", 1, true))
   ok(text:find("useOnKeyDown=false", 1, true))
   ok(text:find("all needed API functions exist", 1, true))
   ok(chatHas(w, "professions read: 2")); ok(chatHas(w, "Diagnose gespeichert"))
   -- fehlt eine noetige Funktion, nennt die Diagnose sie
   w.G.C_SpellBook.IsSpellKnown = nil
   w.PM.Command("diag")
   ok(table.concat(w.PM.db.diag.lines, "\n"):find("MISSING (needed): C_SpellBook.IsSpellKnown", 1, true))
end)

test("Einstellungsfenster: alle Bedienelemente, Aenderungen wirken, Befehl config oeffnet es", function()
   local w = boot()
   w.setProfessions({ P.alchemy(1), P.fishing(4) })
   start(w)
   local S = w.G.Settings
   ok(S.registered, "Kategorie registriert")
   eq(#S.created, 10, "9 Bedienelemente + Schieberegler")
   local byKey = {}
   for _, c in ipairs(S.created) do byKey[c[2].key] = c end
   eq(byKey.sort[1], "dropdown"); eq(#byKey.sort[3], 3); eq(byKey.sort[3][1].value, "cat")
   eq(byKey.activities[1], "dropdown"); eq(#byKey.activities[3], 3); eq(byKey.camp[1], "dropdown")
   eq(byKey.scale[1], "slider"); eq(byKey.unlearned[1], "checkbox")
   eq(byKey.sort[2].tbl, w.PM.db, "die Werte liegen in ProfessionMenuDB")
   -- Wert aendern wirkt auf die Liste
   openList(w)
   eq(#shownRows(w), 5)
   byKey.unlearned[2]:SetValue(false)
   eq(#shownRows(w), 2, "ohne Platzhalter")
   byKey.activities[2]:SetValue("list")
   eq(w.PM.db.activities, "list")
   local keys = {}
   for _, row in ipairs(shownRows(w)) do keys[#keys + 1] = row.entry.key end
   eq(keys[#keys], "fishing"); eq(shownRows(w)[#shownRows(w)].entry.cat, "abilities")
   byKey.scale[2]:SetValue(1.25)
   eq(w.PM.UI.GetButton():GetScale(), 1.25)
   -- Sperre: das Haekchen wirkt sofort (nicht erst nach /reload)
   eq(byKey.locked[1], "checkbox"); eq(w.PM.UI.GetButton():IsMovable(), false)
   byKey.locked[2]:SetValue(false)
   eq(w.PM.UI.GetButton():IsMovable(), true, "entsperrt ueber das Einstellungsfenster")
   byKey.locked[2]:SetValue(true)
   eq(w.PM.UI.GetButton():IsMovable(), false, "wieder gesperrt")
   w.PM.Command("config")
   eq(S.opened, 42)
end)

test("Einstellungsfenster: ohne Settings-Schnittstelle kein Fehler", function()
   local w = boot({ noSettings = true })
   w.setProfessions({ P.alchemy(1) })
   start(w)
   eq(w.PM.RegisterOptions(), false)
   w.PM.Command("config")
   ok(chatHas(w, "Das Einstellungsfenster ist nicht verfügbar."))
   ok(w.PM.ready)
end)

test("Einstellungsfenster: scheitert ein Bedienelement, fehlt nur dieses", function()
   local w = boot()
   w.G.Settings.CreateSlider = function() error("kaputt") end
   w.setProfessions({ P.alchemy(1) })
   start(w)
   eq(#w.G.Settings.created, 9)
   ok(w.G.Settings.registered)
   ok(chatHas(w, "Fehler in Options:Skalierung"))
end)

-- ---------------------------------------------------------------------------
-- Texte
-- ---------------------------------------------------------------------------

test("Texte: jeder Schluessel im Code hat einen englischen Text", function()
   local w = boot()
   local en = w.PM.texts.enUS
   local seen = {}
   for _, file in ipairs(tocFiles()) do
      for line in io.lines(file) do
         for key in line:gmatch("%f[%w_]L%.([%a_][%w_]*)") do seen[key] = file end
      end
   end
   for key, file in pairs(seen) do ok(en[key] ~= nil, "L." .. key .. " (" .. file .. ") fehlt in enUS") end
   for _, cat in ipairs(w.PM.CATEGORIES) do ok(en["cat_" .. cat], "cat_" .. cat) end
end)

test("Texte: alle Sprachen nur mit bekannten Schluesseln, Formate gueltig", function()
   local w = boot()
   local en = w.PM.texts.enUS
   for locale, tbl in pairs(w.PM.texts) do
      for key, value in pairs(tbl) do
         ok(en[key] ~= nil, locale .. "." .. key .. " ist kein bekannter Schluessel")
         if key == "skill" then ok(pcall(string.format, value, 1, 2), locale .. ".skill") end
         if key:find("^hint_") and value:find("%%s") then
            ok(pcall(string.format, value, "Berufe"), locale .. "." .. key)
         end
      end
      ok(not (tbl.hint_skills and not tbl.hint_skills:find("%%s")), locale .. ".hint_skills braucht %s")
   end
   for _, loc in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "zhCN", "zhTW" }) do
      local w2 = boot({ locale = loc })
      local L = w2.PM.L
      ok(L.title ~= "title", loc .. ": title")
      ok(L.hint_open ~= "hint_open", loc .. ": hint_open")
   end
   -- Sprachen ohne Eintrag (enGB) fallen auf Englisch zurueck
   eq(boot({ locale = "enGB" }).PM.L.title, "Professions")
end)

test("Daten: jede Fertigkeitszeile und jeder Schluessel nur einmal", function()
   local w = boot()
   local lines, keys, spells = {}, {}, {}
   for _, def in ipairs(w.PM.PROFESSIONS) do
      ok(not lines[def.skillLine], "doppelte Fertigkeitszeile " .. def.skillLine); lines[def.skillLine] = true
      ok(not keys[def.key], "doppelter Schluessel " .. def.key); keys[def.key] = true
      ok(def.names and def.names.enUS and def.names.deDE, def.key .. ": Namen")
      ok(w.PM.CATEGORIES[1] and (def.cat == "craft" or def.cat == "refine" or def.cat == "gather" or def.cat == "secondary"), def.key .. ": Kategorie")
   end
   for _, def in ipairs(w.PM.ABILITIES) do
      ok(not spells[def.spell], "doppelter Zauber " .. def.spell); spells[def.spell] = true
      ok(def.kind == "use" or def.kind == "target" or def.kind == "tracking" or def.kind == "window", def.key .. ": Art")
   end
end)

-- ---------------------------------------------------------------------------
-- Lauf
-- ---------------------------------------------------------------------------

for _, t in ipairs(tests) do
   local good, err = pcall(t.fn)
   if good then
      passed = passed + 1
      print("  ok    " .. t.name)
   else
      failed = failed + 1
      print("  FAIL  " .. t.name .. "\n        " .. tostring(err))
   end
end

print(string.format("\n%d Tests, %d bestanden, %d fehlgeschlagen", #tests, passed, failed))
os.exit(failed == 0 and 0 or 1)
