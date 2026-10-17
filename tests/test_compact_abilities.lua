-- tests/test_compact_abilities.lua
-- ---------------------------------------------------------------------------
-- Die drei optionalen Einstellungen:
--   compact = button   Knopf nur als Symbol
--   compact = all      Knopf und Liste nur als Symbole
--   abilities          aktive Faehigkeiten (Angeln, Entzaubern, Sondieren, Mahlen, Lagerfeuer, Suchzauber) in der Liste
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function rowFor(PM, key)
      for _, r in ipairs(F.rows(PM)) do
         if r.key == key then return r.row end
      end
   end

   local function elvui(opts)
      local PM, M = F.boot(H, opts)
      H.allowFrames({ "RightChatPanel" })
      return PM, M, ElvUI[1]
   end

   -- Ein Beruf-Satz mit allen Zauberquellen der Faehigkeiten
   local ALL = { learned = { "enchanting", "jewelcrafting", "inscription", "mining", "herbalism", "cooking", "fishing", "alchemy" },
                 extraSpells = { 13262, 31252, 51005, 818, 43308 } }

   local function tipLines()
      local out = {}
      for i = 1, 12 do
         local fs = rawget(_G, "GameTooltipTextLeft" .. i)
         if fs and fs:IsShown() and fs:GetText() then out[#out + 1] = fs:GetText() end
      end
      return out
   end

   -- ======================================================================
   H.section("Aktive Faehigkeiten: Standard aus")
   -- ======================================================================

   H.test("default: no abilities in the list, Angeln stays a secondary profession, Bergbau/Kraeuterkunde start the search", function()
      local PM, M = F.boot(H, ALL)
      F.open(PM)
      local keys = F.rowKeys(PM)
      H.deepEq(keys, { "alchemy", "inscription", "smelting", "jewelcrafting", "enchanting", "mining", "herbalism", "cooking", "fishing" }, "no ability rows")
      H.eq(PM.db.abilities, false)
      H.eq(rowFor(PM, "mining").entry.action, "Find Minerals")
      H.eq(rowFor(PM, "mining").entry.kind, "tracking")
      H.eq(rowFor(PM, "fishing").entry.cat, "secondary")
   end)

   -- ======================================================================
   H.section("Aktive Faehigkeiten: eingeschaltet")
   -- ======================================================================

   H.test("/berufe abilities on: a last category 'Abilities' with the abilities you know, in a fixed order", function()
      local PM, M = F.boot(H, ALL)
      F.open(PM)
      M.Slash("/berufe abilities on")
      H.eq(PM.db.abilities, true)
      H.eq(F.chatCount(M, "Active abilities in the list: on"), 1)
      H.truthy(F.isOpen(PM), "the list stays open and is rebuilt in place")
      local keys = F.rowKeys(PM)
      H.deepEq(keys, { "alchemy", "inscription", "smelting", "jewelcrafting", "enchanting", "mining", "herbalism", "cooking",
                       "fishing", "disenchant", "prospecting", "milling", "campfire", "findminerals", "findherbs", "findfish" })
      local headers = F.headerTexts(PM)
      H.eq(headers[#headers], "Abilities")
      H.eq(rowFor(PM, "fishing").entry.cat, "abilities", "Angeln moved to the abilities")
      H.eq(rowFor(PM, "fishing").entry.rank, 300, "Angeln keeps its skill level")
      H.eq(rowFor(PM, "fishing").entry.maxRank, 450)
      H.eq(rowFor(PM, "disenchant").entry.maxRank, 0, "other abilities show no level")
   end)

   H.test("with abilities on Angeln moves, Bergbau/Kraeuterkunde no longer start the search (the search spells are abilities)", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      F.open(PM)
      local mining = rowFor(PM, "mining")
      H.eq(mining.entry.action, nil)
      H.eq(mining.entry.kind, "none")
      H.falsy(mining.entry.missing, "not flagged as a missing spell")
      H.eq(mining:GetAttribute("type1"), nil)
      H.eq(rowFor(PM, "findminerals").entry.action, "Find Minerals")
      H.eq(rowFor(PM, "findminerals"):GetAttribute("type1"), "spell")
      H.eq(rowFor(PM, "findminerals"):GetAttribute("spell1"), "Find Minerals")
      H.eq(rowFor(PM, "findherbs").entry.action, "Find Herbs")
      -- the profession rows only show the skills window now
      M.Click(mining)
      H.deepEq(M.toggles, { "SkillFrame" })
   end)

   H.test("only abilities whose spell is in the spellbook are listed (Entzaubern comes with Verzauberkunst, the rest is learned separately)", function()
      local PM, M = F.boot(H, { learned = { "enchanting", "jewelcrafting", "fishing" }, extraSpells = { 13262 } })
      M.Slash("/berufe abilities on")
      F.open(PM)
      H.deepEq(F.rowKeys(PM), { "jewelcrafting", "enchanting", "fishing", "disenchant" })
   end)

   H.test("clicking an ability casts the spell by name and closes the list (item targets pick the item afterwards)", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      F.open(PM)
      M.Click(rowFor(PM, "disenchant"))
      H.eq(M.casts[#M.casts], "Disenchant")
      H.falsy(F.isOpen(PM))
      F.open(PM)
      M.Click(rowFor(PM, "fishing"))
      H.eq(M.casts[#M.casts], "Fishing")
      F.open(PM)
      M.Click(rowFor(PM, "campfire"))
      H.eq(M.casts[#M.casts], "Basic Campfire")
      H.deepEq(M.toggles, {}, "an ability never opens the skills window with a left click")
   end)

   H.test("ability tooltips: item targets say 'then pick an item', Angeln shows its skill level, searches say 'start tracking'", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      F.open(PM)
      M.Enter(rowFor(PM, "disenchant"))
      local lines = tipLines()
      H.eq(lines[1], "Disenchant")
      H.contains(lines, "Left-click: use, then pick an item")
      H.falsy(lines[2] and lines[2]:find("Skill:", 1, true), "no skill line for Entzaubern")
      M.Leave(rowFor(PM, "disenchant"))
      M.Enter(rowFor(PM, "fishing"))
      lines = tipLines()
      H.contains(lines, "Left-click: use")
      H.truthy(lines[2] and lines[2]:find("Skill:", 1, true), "Angeln keeps its skill line")
      M.Leave(rowFor(PM, "fishing"))
      M.Enter(rowFor(PM, "findherbs"))
      H.contains(tipLines(), "Left-click: start tracking")
   end)

   H.test("abilities in German: category 'Fähigkeiten', spell names from the client", function()
      local PM, M = F.boot(H, { locale = "deDE", learned = { "enchanting", "fishing" }, extraSpells = { 13262 } })
      M.Slash("/berufe abilities on")
      F.open(PM)
      local headers = F.headerTexts(PM)
      H.eq(headers[#headers], "Fähigkeiten")
      H.contains(F.rowNames(PM), "Entzaubern")
      H.contains(F.rowNames(PM), "Angeln")
      M.Enter(rowFor(PM, "disenchant"))
      H.contains(tipLines(), "Linksklick: benutzen, danach Gegenstand wählen")
   end)

   H.test("sorting: alphabetical and by rank mix the abilities in without headers; abilities sort last by rank", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      M.Slash("/berufe sort alpha")
      F.open(PM)
      local names = F.rowNames(PM)
      for i = 2, #names do H.truthy(names[i - 1]:lower() <= names[i]:lower(), "alphabetical: " .. names[i - 1] .. " <= " .. names[i]) end
      H.eq(#F.headerTexts(PM), 0)
      M.Slash("/berufe sort rank")
      local rows = F.rows(PM)
      H.truthy(rows[#rows].entry.ability, "an ability (no skill level) is last")
   end)

   H.test("turning the abilities off again restores the plain list", function()
      local PM, M = F.boot(H, ALL)
      F.open(PM)
      local before = F.rowKeys(PM)
      M.Slash("/berufe abilities on")
      M.Slash("/berufe abilities off")
      H.deepEq(F.rowKeys(PM), before)
      H.eq(rowFor(PM, "mining").entry.action, "Find Minerals")
   end)

   H.test("/berufe abilities with a bad argument prints the help and changes nothing", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities maybe")
      H.eq(PM.db.abilities, false)
      H.eq(F.chatCount(M, "abilities on||off"), 1)
   end)

   H.test("/berufe list names the known abilities and whether they are in the list", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe list")
      H.truthy(F.chatCount(M, "ability: Disenchant (disenchant, list: off)") == 1)
      M.Slash("/berufe abilities on")
      F.clearChat(M)
      M.Slash("/berufe list")
      H.truthy(F.chatCount(M, "ability: Disenchant (disenchant, list: on)") == 1)
   end)

   H.test("the next Open rebuilds when the setting was changed behind the addon's back (signature includes abilities and compact)", function()
      local PM, M = F.boot(H, ALL)
      F.open(PM)
      PM.UI.Close()
      PM.db.abilities = true                 -- e.g. edited SavedVariables or another addon
      F.open(PM)
      H.truthy(rowFor(PM, "disenchant"), "abilities show up on the next open")
      PM.UI.Close()
      PM.db.compact = "all"
      F.open(PM)
      H.falsy(rowFor(PM, "disenchant").text:IsShown(), "compact applied on the next open")
   end)

   H.test("everything fits the pre-built frames: 22 rows and 5 headers with all professions and all abilities", function()
      local PM, M = F.boot(H, { learned = F.ORDER, extraSpells = { 13262, 31252, 51005, 818, 43308 } })
      M.Slash("/berufe abilities on")
      F.open(PM)
      -- 13 professions (Angeln moved to the abilities) + Verhuettung + 8 abilities
      H.eq(#F.rows(PM), 13 + 1 + 8)
      H.eq(#F.headerTexts(PM), 5)
   end)

   -- ======================================================================
   H.section("Kompakt: nur der Knopf")
   -- ======================================================================

   H.test("compact = button: a square icon-only button, label and arrow hidden, the list keeps its text", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      M.Slash("/berufe compact button")
      H.eq(PM.db.compact, "button")
      H.eq(F.chatCount(M, "Display: icon only: button"), 1)
      local b, S = PM.UI.GetButton(), PM.UI.sizes
      H.eq(b:GetWidth(), S.cell)
      H.eq(b:GetHeight(), S.cell)
      H.falsy(b.text:IsShown())
      H.falsy(b.arrow:IsShown())
      H.truthy(b.box:IsShown())
      H.eq(b.box:GetWidth(), S.cellIcon)
      F.open(PM)
      local row = F.rows(PM)[1].row
      H.truthy(row.text:IsShown(), "the list still shows names")
      H.truthy(PM.UI.GetMenu():GetWidth() > b:GetWidth(), "the list is wider than the icon button")
      H.eq(row:GetHeight(), S.rowH)
   end)

   H.test("compact button: the hover tooltip still names the button, the click toggles the list, the list aligns to the button edge", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe compact button")
      local b = PM.UI.GetButton()
      M.Enter(b)
      H.deepEq(tipLines(), { "Professions", "Click: open list" })
      M.Leave(b)
      M.Click(b)
      H.truthy(F.isOpen(PM))
      local menu = PM.UI.GetMenu()
      -- default position: right half of the screen, right edges flush
      H.near(menu:GetRight(), b:GetRight(), 1e-6)
      M.Click(b)
      H.falsy(F.isOpen(PM))
   end)

   H.test("going back to 'off' restores width, label and arrow", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local b = PM.UI.GetButton()
      local w, h = b:GetWidth(), b:GetHeight()
      M.Slash("/berufe compact button")
      M.Slash("/berufe compact off")
      H.eq(b:GetWidth(), w)
      H.eq(b:GetHeight(), h)
      H.truthy(b.text:IsShown())
      H.truthy(b.arrow:IsShown())
      H.eq(b.box:GetWidth(), PM.UI.sizes.buttonIcon)
   end)

   -- ======================================================================
   H.section("Kompakt: Knopf und Liste nur als Symbole")
   -- ======================================================================

   H.test("compact = all: rows are square icon cells (no text, no rank, no separators), the list is as wide as the button", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining", "cooking" }, ranks = { alchemy = { 300, 375 } } })
      M.Slash("/berufe compact all")
      F.open(PM)
      local S, b, menu = PM.UI.sizes, PM.UI.GetButton(), PM.UI.GetMenu()
      H.eq(b:GetWidth(), S.cell)
      H.eq(menu:GetWidth(), S.cell, "list width = cell = button width")
      for _, r in ipairs(F.rows(PM)) do
         H.falsy(r.row.text:IsShown(), r.key .. " text hidden")
         H.falsy(r.row.rank:IsShown(), r.key .. " rank hidden")
         H.falsy(r.row.sep:IsShown(), r.key .. " separator hidden")
         H.eq(r.row:GetHeight(), S.cell, r.key .. " row height")
         H.eq(r.row.box:GetWidth(), S.cellIcon, r.key .. " icon box")
         local point = r.row.box:GetPoint(1)
         H.eq(point, "CENTER", r.key .. " icon centred in the cell")
         H.eq(r.row:GetAttribute("type1"), "spell", r.key .. " still clickable")
      end
   end)

   H.test("compact = all: no category headings, a gap between categories instead", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "blacksmithing", "mining", "cooking" } })
      M.Slash("/berufe compact all")
      F.open(PM)
      H.eq(#F.headerTexts(PM), 0)
      local ys = {}
      for _, r in ipairs(F.rows(PM)) do
         local _, _, _, _, y = r.row:GetPoint(1)
         ys[#ys + 1] = { key = r.key, y = y, cat = r.entry.cat }
      end
      local S = PM.UI.sizes
      for i = 2, #ys do
         local step = ys[i - 1].y - ys[i].y
         if ys[i].cat == ys[i - 1].cat then
            H.near(step, S.cell, 1e-6, "same category: no gap (" .. ys[i].key .. ")")
         else
            H.near(step, S.cell + S.catGap, 1e-6, "category change: gap (" .. ys[i].key .. ")")
         end
      end
      local lastKey = ys[#ys].key
      local menu = PM.UI.GetMenu()
      H.truthy(menu:GetHeight() >= #ys * S.cell + S.catGap * 2, "the list height covers cells and gaps")
   end)

   H.test("compact = all: the tooltip still names the profession with its skill level, clicks still cast", function()
      local PM, M = F.boot(H, { learned = { alchemy = { 300, 375 } } })
      M.Slash("/berufe compact all")
      F.open(PM)
      local row = rowFor(PM, "alchemy")
      M.Enter(row)
      H.deepEq(tipLines(), { "Alchemy", "Skill: 300 / 375", " ", "Left-click: open", "Right-click: skills window" })
      M.Leave(row)
      M.Click(row)
      H.eq(M.casts[#M.casts], "Alchemy")
      H.falsy(F.isOpen(PM))
   end)

   H.test("compact = all with abilities: icons for the abilities too, the abilities form their own group", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      M.Slash("/berufe compact all")
      F.open(PM)
      H.eq(#F.rows(PM), 16)
      local last = F.rows(PM)[16]
      H.eq(last.key, "findfish")
      H.truthy(PM.UI.GetMenu():IsShown())
   end)

   H.test("switching between the modes while the list is open: the list stays open when the button size is unchanged, closes when it changes", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      F.open(PM)
      M.Slash("/berufe compact button")
      H.falsy(F.isOpen(PM), "the button changed its size: the list closes (its offsets would be wrong)")
      F.open(PM)
      M.Slash("/berufe compact all")
      H.truthy(F.isOpen(PM), "button -> all keeps the button size: rebuilt in place")
      H.eq(PM.UI.GetMenu():GetWidth(), PM.UI.sizes.cell)
      M.Slash("/berufe compact button")
      H.truthy(F.isOpen(PM))
      H.truthy(PM.UI.GetMenu():GetWidth() > PM.UI.sizes.cell, "all -> button: names are back")
      H.truthy(F.rows(PM)[1].row.text:IsShown())
   end)

   H.test("an empty list in compact = all shows the hint at a width that fits it", function()
      local PM, M = F.boot(H, { learned = {} })
      M.Slash("/berufe compact all")
      F.open(PM)
      H.truthy(PM.UI.GetMenu().empty:IsShown())
      H.truthy(PM.UI.GetMenu():GetWidth() > PM.UI.sizes.cell, "the hint needs more than one cell")
   end)

   H.test("/berufe compact with a bad argument prints the help and changes nothing", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe compact tiny")
      H.eq(PM.db.compact, "off")
      H.eq(F.chatCount(M, "compact off||button||all"), 1)
   end)

   H.test("the mode is German in deDE", function()
      local PM, M = F.boot(H, { locale = "deDE", learned = { "alchemy" } })
      M.Slash("/berufe compact all")
      H.eq(F.chatCount(M, "Darstellung: nur Symbol: Knopf und Liste"), 1)
      M.Slash("/berufe abilities on")
      H.eq(F.chatCount(M, "Aktive Fähigkeiten in der Liste: an"), 1)
   end)

   -- ======================================================================
   H.section("Speichern, Kampf, ElvUI")
   -- ======================================================================

   H.test("the settings survive a relog; invalid saved values fall back to the defaults", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe compact all")
      M.Slash("/berufe abilities on")
      local saved = M.SavedVariables()
      PM, M = F.boot(H, { learned = { "alchemy" }, saved = saved })
      H.eq(PM.db.compact, "all")
      H.eq(PM.db.abilities, true)
      H.eq(PM.UI.GetButton():GetWidth(), PM.UI.sizes.cell, "the button starts compact")
      PM = F.boot(H, { learned = { "alchemy" }, db = { compact = "tiny", abilities = "yes" } })
      H.eq(PM.db.compact, "off")
      H.eq(PM.db.abilities, false)
   end)

   H.test("changing the display in combat waits until the combat is over and touches no protected frame", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      M.EnterCombat()
      M.Slash("/berufe compact all")
      M.Slash("/berufe abilities on")
      H.len(M.blocked, 0)
      H.eq(PM.db.compact, "all")
      M.LeaveCombat()
      H.len(M.blocked, 0)
      H.eq(PM.UI.GetButton():GetWidth(), PM.UI.sizes.cell, "applied after the combat")
      F.open(PM)
      H.eq(PM.UI.GetMenu():GetWidth(), PM.UI.sizes.cell)
   end)

   H.test("ElvUI options: Display (select) and Include active abilities (toggle) exist, localized, and change the live list", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true, locale = "deDE" })
      E.LoadOptions()
      local args = E.Options.args.professionMenu.args
      H.eq(args.compact.name, "Darstellung")
      H.eq(args.compact.type, "select")
      H.deepEq(args.compact.values, { off = "mit Text", button = "nur Symbol: Knopf", all = "nur Symbol: Knopf und Liste" })
      H.eq(args.abilities.name, "Aktive Fähigkeiten einbeziehen")
      H.eq(args.abilities.type, "toggle")
      local group = E.Options.args.professionMenu
      group.set({ [1] = "compact" }, "all")
      H.eq(PM.db.compact, "all")
      H.eq(PM.UI.GetButton():GetWidth(), PM.UI.sizes.cell)
      group.set({ [1] = "abilities" }, true)
      H.eq(PM.db.abilities, true)
      H.eq(group.get({ [1] = "compact" }), "all")
   end)

   H.test("ElvUI + compact: the mover follows the smaller button", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local mover = ProfessionMenuMover
      local w0 = mover:GetWidth()
      M.Slash("/berufe compact button")
      H.truthy(mover:GetWidth() < w0, "mover shrank with the button: " .. w0 .. " -> " .. mover:GetWidth())
   end)

   H.test("on a high-DPI pixel grid (3024x1964, UI scale 0.7) the compact sizes are whole pixels", function()
      local mult = (768 / 1964) / 0.7
      local PM, M, E = elvui({ learned = { "alchemy", "mining" }, elvui = { mult = mult } })
      M.Slash("/berufe compact all")
      F.open(PM)
      for _, v in ipairs({ PM.UI.sizes.cell, PM.UI.sizes.cellIcon, PM.UI.sizes.catGap, PM.UI.GetButton():GetWidth(),
                           PM.UI.GetMenu():GetWidth() }) do
         local n = v / mult
         H.near(n, math.floor(n + 0.5), 1e-6)
      end
   end)

   -- ======================================================================
   H.section("Nachbesserungen aus der Pruefung")
   -- ======================================================================

   H.test("leaving compact restores the text layout (names, ranks, row height, icon box, separators, button box)", function()
      for _, back in ipairs({ "off", "button" }) do
         local PM, M = F.boot(H, { learned = { "alchemy", "mining", "cooking" }, ranks = { alchemy = { 300, 375 } } })
         local S, b = PM.UI.sizes, PM.UI.GetButton()
         M.Slash("/berufe compact all")
         F.open(PM)
         M.Slash("/berufe compact " .. back)
         F.open(PM)
         local rows = F.rows(PM)
         for i, r in ipairs(rows) do
            local row = r.row
            H.truthy(row.text:IsShown(), back .. ": " .. r.key .. " name shown")
            H.truthy(row.rank:IsShown(), back .. ": " .. r.key .. " rank shown")
            H.eq(row:GetHeight(), S.rowH, back .. ": row height")
            H.eq(row.box:GetWidth(), S.icon, back .. ": icon box size")
            local point, _, _, x = row.box:GetPoint(1)
            H.eq(point, "LEFT", back .. ": icon box at the left")
            H.near(x, S.iconPad, 1e-6)
            H.eq(row.sep:IsShown() and true or false, i < #rows, back .. ": separator except on the last row")
         end
         H.eq(rowFor(PM, "alchemy").rank:GetText(), "300/375")
         local point = b.box:GetPoint(1)
         if back == "off" then
            H.eq(point, "LEFT", "button icon back at the left")
            H.truthy(b.text:IsShown())
         else
            H.eq(point, "CENTER", "compact button keeps the centred icon")
         end
      end
   end)

   H.test("compact = all: the row highlight lies over the icon (icon box below the row), flat; text mode: gradient over the row", function()
      local PM, M = elvui({ learned = { "alchemy", "mining" }, elvui = true })
      F.open(PM)
      local row = rowFor(PM, "alchemy")
      H.truthy(row.box:GetFrameLevel() < row:GetFrameLevel(), "icon box is below the row's own regions")
      H.eq(row.hl:GetTexture(), (PM.Skin.HighlightTexture()))
      H.truthy(row.hl:GetTexture() ~= "Interface\\Buttons\\WHITE8X8", "with ElvUI the text list uses the gradient")
      M.Slash("/berufe compact all")
      H.eq(row.hl:GetTexture(), "Interface\\Buttons\\WHITE8X8", "flat highlight in the icon list")
      local point, rel = row.hl:GetPoint(1)
      H.eq(point, "TOPLEFT")
      H.eq(rel, row.box, "the highlight follows the icon box")
      M.Slash("/berufe compact off")
      H.eq(row.hl:GetTexture(), (PM.Skin.HighlightTexture()), "gradient again")
      point, rel = row.hl:GetPoint(1)
      H.eq(rel, row, "the highlight covers the row again")
   end)

   H.test("PM.Layout: gaps only between categories, never first or last; none for alpha/rank sort; headers stay for button mode", function()
      local PM = F.boot(H, ALL)
      local entries = PM.BuildEntries(PM.ReadSkills(), PM.ReadSpellbook(), "cat", { abilities = true })
      local function count(rows, field)
         local n = 0
         for _, r in ipairs(rows) do if r[field] then n = n + 1 end end
         return n
      end
      local rows = PM.Layout(entries, { sort = "cat", headers = true, compact = "all" })
      H.eq(count(rows, "header"), 0, "no headings in compact all")
      H.eq(count(rows, "gap"), 4, "5 categories with abilities = 4 gaps")
      H.truthy(not rows[1].gap and not rows[#rows].gap, "no gap at the start or end")
      for i, r in ipairs(rows) do
         if r.gap then H.truthy(rows[i - 1].entry and rows[i + 1].entry, "a gap sits between two entries") end
      end
      rows = PM.Layout(entries, { sort = "cat", headers = true, compact = "button" })
      H.eq(count(rows, "gap"), 0)
      H.eq(count(rows, "header"), 5, "button mode keeps the headings")
      for _, sort in ipairs({ "alpha", "rank" }) do
         rows = PM.Layout(entries, { sort = sort, headers = true, compact = "all" })
         H.eq(count(rows, "gap"), 0, sort .. ": no gaps")
         H.eq(count(rows, "header"), 0, sort .. ": no headings")
      end
      rows = PM.Layout(entries, { sort = "cat", headers = false, compact = "off" })
      H.eq(#rows, #entries)
   end)

   H.test("compact = all: exact list height = 2 * pad + cells * cell + gaps * catGap", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      M.Slash("/berufe compact all")
      F.open(PM)
      local S = PM.UI.sizes
      H.near(PM.UI.GetMenu():GetHeight(), 2 * S.pad + 16 * S.cell + 4 * S.catGap, 1e-6)
   end)

   H.test("the abilities table: ids, kinds, icons, names in two languages, which one carries a level", function()
      local EXPECT = {
         { key = "fishing",       spell = 7620,  kind = "use",      en = "Fishing",        de = "Angeln",               rank = true },
         { key = "disenchant",    spell = 13262, kind = "target",   en = "Disenchant",     de = "Entzaubern" },
         { key = "prospecting",   spell = 31252, kind = "target",   en = "Prospecting",    de = "Sondieren" },
         { key = "milling",       spell = 51005, kind = "target",   en = "Milling",        de = "Mahlen" },
         { key = "campfire",      spell = 818,   kind = "use",      en = "Basic Campfire", de = "Einfaches Lagerfeuer" },
         { key = "findminerals",  spell = 2580,  kind = "tracking", en = "Find Minerals",  de = "Mineraliensuche" },
         { key = "findherbs",     spell = 2383,  kind = "tracking", en = "Find Herbs",     de = "Kräutersuche" },
         { key = "findfish",      spell = 43308, kind = "tracking", en = "Find Fish",      de = "Fischsuche" },
      }
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local PM, M = F.boot(H, { locale = locale, learned = { "enchanting", "jewelcrafting", "inscription", "mining", "herbalism",
                                                                  "cooking", "fishing" },
                                   ranks = { fishing = { 217, 300 } }, extraSpells = { 13262, 31252, 51005, 818, 43308 } })
         M.Slash("/berufe abilities on")
         F.open(PM)
         H.eq(#PM.ABILITIES, #EXPECT, "no ability without a test")
         for i, e in ipairs(EXPECT) do
            H.eq(PM.ABILITIES[i].key, e.key, "order " .. i)
            H.eq(PM.ABILITIES[i].spell, e.spell, e.key .. " spell id")
            H.eq(PM.ABILITIES[i].kind, e.kind, e.key .. " kind")
            H.truthy(PM.ABILITIES[i].icon, e.key .. " has an icon")
            local row = rowFor(PM, e.key)
            H.truthy(row, locale .. ": " .. e.key .. " listed")
            local name = locale == "deDE" and e.de or e.en
            H.eq(row.entry.name, name, locale .. ": " .. e.key .. " name")
            H.eq(row:GetAttribute("spell1"), name, e.key .. " casts by name")
            H.eq(row:GetAttribute("type1"), "spell")
            H.truthy(row.icon:GetTexture(), e.key .. " shows an icon")
            M.Click(row)
            H.eq(M.casts[#M.casts], name, e.key .. " click casts the spell")
            F.open(PM)
            row = rowFor(PM, e.key)
            M.Enter(row)
            local lines = tipLines()
            H.eq(lines[1], name)
            local hint = ({ enUS = { use = "use", target = "then pick", tracking = "tracking" },
                            deDE = { use = "benutzen", target = "Gegenstand", tracking = "Suche" } })[locale][e.kind]
            local found
            for _, l in ipairs(lines) do if l:lower():find(hint:lower(), 1, true) then found = true end end
            H.truthy(found, e.key .. " tooltip names the action: " .. table.concat(lines, " | "))
            M.Leave(row)
         end
         local fishing = rowFor(PM, "fishing")
         H.eq(fishing.entry.rank, 217, "Angeln shows its own level")
         H.eq(fishing.entry.maxRank, 300)
         H.eq(fishing.rank:GetText(), "217/300")
         for _, e in ipairs(EXPECT) do
            if not e.rank then H.eq(rowFor(PM, e.key).entry.maxRank, 0, e.key .. " carries no level") end
         end
      end
   end)

   H.test("shrinking from 22 rows leaves no stale rows (entries nil, hidden, no action)", function()
      local PM, M = F.boot(H, { learned = F.ORDER, extraSpells = { 13262, 31252, 51005, 818, 43308 } })
      M.Slash("/berufe abilities on")
      F.open(PM)
      H.eq(#F.rows(PM), 22)
      M.Slash("/berufe abilities off")
      local n = #F.rows(PM)
      H.eq(n, 15)
      for i = n + 1, #PM.UI.rows do
         local row = PM.UI.rows[i]
         H.falsy(row:IsShown(), "row " .. i .. " hidden")
         H.eq(row.entry, nil, "row " .. i .. " has no entry")
         H.eq(row:GetAttribute("type1"), nil, "row " .. i .. " has no action")
      end
   end)

   H.test("/berufe compact is case-insensitive", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe compact ALL")
      H.eq(PM.db.compact, "all")
      M.Slash("/berufe abilities ON")
      H.eq(PM.db.abilities, true)
   end)

   H.test("a saved 'button' mode survives a relog; wrong types fall back to the defaults", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe compact button")
      local saved = M.SavedVariables()
      PM = F.boot(H, { learned = { "alchemy" }, saved = saved })
      H.eq(PM.db.compact, "button")
      H.eq(PM.UI.GetButton():GetWidth(), PM.UI.sizes.cell)
      PM = F.boot(H, { learned = { "alchemy" }, db = { compact = 5, abilities = 1 } })
      H.eq(PM.db.compact, "off")
      H.eq(PM.db.abilities, false)
   end)

   H.test("signature: with only Angeln learned, switching abilities on changes the list (header Nebenberufe -> Faehigkeiten)", function()
      local PM, M = F.boot(H, { learned = { "fishing" } })
      F.open(PM)
      H.deepEq(F.headerTexts(PM), { "Secondary" })
      PM.UI.Close()
      PM.db.abilities = true
      F.open(PM)
      H.deepEq(F.headerTexts(PM), { "Abilities" })
   end)

   H.test("the 'moved' search rows say where the search went; /berufe list says 'see abilities'", function()
      local PM, M = F.boot(H, ALL)
      M.Slash("/berufe abilities on")
      F.open(PM)
      local mining = rowFor(PM, "mining")
      H.truthy(mining.entry.moved)
      M.Enter(mining)
      local found
      for _, l in ipairs(tipLines()) do if l:find("Abilities list", 1, true) then found = true end end
      H.truthy(found, "tooltip points to the abilities: " .. table.concat(tipLines(), " | "))
      H.falsy(rowFor(PM, "alchemy").entry.moved)
      F.clearChat(M)
      M.Slash("/berufe list")
      H.truthy(F.chatCount(M, "see abilities") >= 2, "Mining, Herbalism (and Fishing) are listed as 'see abilities'")
   end)

   H.test("the Abilities category uses the client's own word (global ABILITIES) when there is one", function()
      local PM, M = F.boot(H, { locale = "frFR", learned = { "enchanting" }, extraSpells = { 13262 },
                                before = function() _G.ABILITIES = "Techniques" end })
      M.Slash("/berufe abilities on")
      F.open(PM)
      local headers = F.headerTexts(PM)
      H.eq(headers[#headers], "Techniques")
      _G.ABILITIES = nil
   end)

   H.test("a long ability name never makes the list wider than the button", function()
      local long = "An extremely long name for Fishing that no profession has"
      local PM, M = F.boot(H, { learned = { "alchemy", "fishing" },
                                before = function(mock) mock.spellNames[7620] = { enUS = long, deDE = long } end })
      M.Slash("/berufe abilities on")
      F.open(PM)
      H.truthy(rowFor(PM, "fishing"), "Angeln is listed")
      H.truthy(PM.UI.GetMenu():GetWidth() <= PM.UI.GetButton():GetWidth() + 1e-6,
         "list " .. PM.UI.GetMenu():GetWidth() .. " <= button " .. PM.UI.GetButton():GetWidth())
   end)

   H.test("compact = all: the mover is as wide as the cell", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      M.Slash("/berufe compact all")
      H.near(ProfessionMenuMover:GetWidth(), PM.UI.sizes.cell, 1e-6)
   end)

   H.test("on a high-DPI pixel grid the icon margin is a whole, even number of pixels (button and rows)", function()
      local mult = (768 / 1964) / 0.7
      local PM, M, E = elvui({ learned = { "alchemy", "mining" }, elvui = { mult = mult } })
      M.Slash("/berufe compact all")
      F.open(PM)
      local S = PM.UI.sizes
      local margin = (S.cell - S.cellIcon) / mult
      H.near(margin, math.floor(margin + 0.5), 1e-6, "margin in whole pixels")
      H.eq(math.floor(margin + 0.5) % 2, 0, "even, so the icon sits centred on whole pixels")
      -- the actual frames: icon box inside the cell on every side
      local row = F.rows(PM)[1].row
      H.near(row.box:GetWidth(), S.cellIcon, 1e-6)
      local b = PM.UI.GetButton()
      H.near(b.box:GetWidth(), S.cellIcon, 1e-6)
   end)
end
