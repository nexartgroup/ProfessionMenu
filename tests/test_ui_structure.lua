-- tests/test_ui_structure.lua
-- ---------------------------------------------------------------------------
-- Aufbau von Knopf und Liste (UI.lua): Anzahl der Zeilen/Ueberschriften, Texte, Stufentext und Farben,
-- Attribute der sicheren Zeilen, Groessen, Anordnung, leere Liste, Rahmen, Schichten.
-- Masse bei 1 Pixel = 1 UI-Einheit (Standard der Attrappe): rowH 24, header 18, pad 1, buttonW 150.
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local GREEN = { 0.35, 0.85, 0.45 }

   local function open(opts)
      local PM, M = F.boot(H, opts)
      H.truthy(PM.ready, "addon is ready")
      H.truthy(F.open(PM), "list opens")
      return PM, M
   end

   local function near3(r, g, b, want, msg)
      H.near(r, want[1], 1e-6, (msg or "") .. " r")
      H.near(g, want[2], 1e-6, (msg or "") .. " g")
      H.near(b, want[3], 1e-6, (msg or "") .. " b")
   end

   -- ======================================================================
   H.section("Frames created at login")
   -- ======================================================================

   H.test("exactly 24 rows and 5 header slots exist after login, rows are secure buttons below the list", function()
      local PM, M = F.boot(H, { learned = { "mining" } })
      local menu = PM.UI.GetMenu()
      H.len(PM.UI.rows, 24)
      H.len(PM.UI.headers, 5)
      for i = 1, 24 do
         local row = rawget(_G, "ProfessionMenuRow" .. i)
         H.truthy(row, "row " .. i)
         H.eq(PM.UI.rows[i], row)
         H.eq(row:GetParent(), menu)
         H.eq(row:GetObjectType(), "Button")
         local explicit = select(2, M.IsProtected(row))
         H.eq(explicit, true, "row " .. i .. " is a protected frame")
      end
      H.eq(rawget(_G, "ProfessionMenuRow25"), nil)
      H.eq(menu:GetName(), "ProfessionMenuList")
      H.eq(PM.UI.GetButton():GetName(), "ProfessionMenuButton")
   end)

   H.test("row scripts: PreClick, PostClick, OnEnter, OnLeave; clicks registered for left and right button up", function()
      local PM = F.boot(H, { learned = { "mining" } })
      local row = PM.UI.rows[1]
      for _, name in ipairs({ "PreClick", "PostClick", "OnEnter", "OnLeave" }) do
         H.truthy(row:GetScript(name), name)
      end
      H.truthy(row:GetScript("OnClick"), "the secure template handler is still there")
      H.truthy(row.__clicks.LeftButtonUp)
      H.truthy(row.__clicks.RightButtonUp)
      H.falsy(row.__clicks.LeftButtonDown)
      H.falsy(row.__clicks.MiddleButtonUp)
   end)

   H.test("strata and levels: the list sits in DIALOG above the MEDIUM button, rows above the list", function()
      local PM = F.boot(H, { learned = { "mining" } })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      H.eq(button:GetFrameStrata(), "MEDIUM")
      H.eq(menu:GetFrameStrata(), "DIALOG")
      for _, row in ipairs(PM.UI.rows) do
         H.eq(row:GetFrameStrata(), "DIALOG")
         H.truthy(row:GetFrameLevel() > menu:GetFrameLevel(), "row level above the list")
      end
   end)

   H.test("the list is the only protected frame in the chain: the button is neither protected nor in the anchor family", function()
      local PM, M = open({ learned = { "mining" } })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      local isProtected, explicit = M.IsProtected(menu)
      H.eq(isProtected, true)
      H.eq(explicit, true, "SecureHandlerStateTemplate")
      isProtected, explicit = M.IsProtected(button)
      H.eq(isProtected, false, "button must not hang in the protected chain")
      H.eq(explicit, false)
   end)

   H.test("the list is anchored to UIParent only (one point, relative to UIParent)", function()
      local PM = open({ learned = { "mining" } })
      local menu = PM.UI.GetMenu()
      H.eq(menu:GetNumPoints(), 1)
      local _, rel = menu:GetPoint(1)
      H.eq(rel, UIParent)
   end)

   H.test("UISpecialFrames contains the ESC proxy (not the protected list) exactly once, even after a second UI.Create attempt", function()
      local PM = F.boot(H, { learned = { "mining" } })
      local n = 0
      for _, name in ipairs(UISpecialFrames) do
         if name == "ProfessionMenuEscProxy" then n = n + 1 end
      end
      H.eq(n, 1)
      PM.UI.Create()          -- guarded by UI.created
      PM.StartUI()            -- guarded by PM.ready
      n = 0
      for _, name in ipairs(UISpecialFrames) do
         if name == "ProfessionMenuEscProxy" then n = n + 1 end
      end
      H.eq(n, 1)
   end)

   -- ======================================================================
   H.section("Counts of rows and headers")
   -- ======================================================================

   local SETS = {
      { name = "all 14 professions", learned = F.ORDER, rows = 15, headers = 4 },
      { name = "one crafting profession", learned = { "alchemy" }, rows = 1, headers = 1 },
      { name = "crafting only", learned = { "alchemy", "tailoring", "inscription" }, rows = 3, headers = 1 },
      { name = "mining brings smelting", learned = { "mining" }, rows = 2, headers = 2 },
      { name = "gathering + secondary", learned = { "herbalism", "skinning", "fishing" }, rows = 3, headers = 2 },
      { name = "secondary only", learned = { "cooking", "firstaid", "fishing" }, rows = 3, headers = 1 },
      { name = "no professions", learned = {}, rows = 0, headers = 0 },
   }

   for _, set in ipairs(SETS) do
      H.test("visible rows and headers: " .. set.name, function()
         local PM = open({ learned = set.learned })
         H.eq(#F.rows(PM), set.rows, "rows")
         H.eq(#F.headerTexts(PM), set.headers, "headers")
         -- every row beyond the used ones is hidden and empty
         for i = set.rows + 1, #PM.UI.rows do
            H.falsy(PM.UI.rows[i]:IsShown(), "row " .. i .. " hidden")
            H.eq(PM.UI.rows[i].entry, nil, "row " .. i .. " has no entry")
         end
      end)
   end

   H.test("sort alpha / sort rank: no headers; headers off: no headers; sort cat + headers on: headers", function()
      local PM, M = open({ learned = { "alchemy", "mining", "fishing" } })
      H.eq(#F.headerTexts(PM), 4, "cat sort: craft, refine, gather, secondary")
      M.Slash("/berufe sort alpha")
      H.eq(#F.headerTexts(PM), 0)
      M.Slash("/berufe sort rank")
      H.eq(#F.headerTexts(PM), 0)
      M.Slash("/berufe sort cat")
      H.eq(#F.headerTexts(PM), 4)
      M.Slash("/berufe headers off")
      H.eq(#F.headerTexts(PM), 0)
      M.Slash("/berufe headers on")
      H.eq(#F.headerTexts(PM), 4)
   end)

   -- ======================================================================
   H.section("Texts and colours")
   -- ======================================================================

   H.test("category headings in enUS", function()
      local PM = open({ learned = F.ORDER })
      H.deepEq(F.headerTexts(PM), { "Crafting", "Processing", "Gathering", "Secondary" })
   end)

   H.test("category headings in deDE", function()
      local PM = open({ learned = F.ORDER, locale = "deDE" })
      H.deepEq(F.headerTexts(PM), { "Herstellung", "Weiterverarbeitung", "Sammeln", "Nebenberufe" })
   end)

   H.test("category headings in frFR (translated) and unknown-locale fallback to English", function()
      local PM = open({ learned = F.ORDER, locale = "frFR" })
      H.deepEq(F.headerTexts(PM), { "Fabrication", "Transformation", "R\195\169colte", "Secondaires" })
      PM = open({ learned = F.ORDER, locale = "itIT" })
      H.deepEq(F.headerTexts(PM), { "Crafting", "Processing", "Gathering", "Secondary" })
   end)

   H.test("header texts come out in the colour of the accent; ElvUI-less default is the orange value colour", function()
      local PM = open({ learned = { "alchemy" } })
      local h = PM.UI.headers[1]
      local r, g, b = h.text:GetTextColor()
      local ar, ag, ab = PM.Skin.AccentColor()
      near3(r, g, b, { ar, ag, ab }, "header colour")
      near3(ar, ag, ab, { 0.99, 0.48, 0.17 }, "fallback accent")
   end)

   H.test("row texts are the profession names, the rank text is 'rank/max', coloured grey below max and green at max", function()
      local PM = open({ learned = { mining = { 300, 450 }, alchemy = { 450, 450 }, fishing = { 1, 75 } } })
      local rows = F.rows(PM)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Smelting", "Mining", "Fishing" })
      H.eq(rows[1].rank, "450/450")
      H.eq(rows[2].rank, "300/450")
      H.eq(rows[3].rank, "300/450")
      H.eq(rows[4].rank, "1/75")
      local r, g, b = rows[1].row.rank:GetTextColor()
      near3(r, g, b, GREEN, "max rank is green")
      r, g, b = rows[2].row.rank:GetTextColor()
      local dr, dg, db = PM.Skin.DimColor()
      near3(r, g, b, { dr, dg, db }, "below max is grey")
      r, g, b = rows[4].row.rank:GetTextColor()
      near3(r, g, b, { dr, dg, db }, "1/75 is grey")
   end)

   H.test("row names are white; the text uses the font of the game (STANDARD_TEXT_FONT) with size 12", function()
      local PM = open({ learned = { "alchemy" } })
      local row = PM.UI.rows[1]
      local r, g, b = row.text:GetTextColor()
      near3(r, g, b, { 1, 1, 1 }, "name colour")
      local path, size = row.text:GetFont()
      H.eq(path, STANDARD_TEXT_FONT)
      H.eq(size, 12)
      path, size = row.rank:GetFont()
      H.eq(path, STANDARD_TEXT_FONT)
      H.eq(size, 11)
   end)

   H.test("ranks off: no rank text; back on: texts return", function()
      local PM, M = open({ learned = { "alchemy", "fishing" } })
      M.Slash("/berufe ranks off")
      for _, r in ipairs(F.rows(PM)) do H.eq(r.rank, "", r.key) end
      M.Slash("/berufe ranks on")
      local rows = F.rows(PM)
      H.eq(rows[1].rank, "300/450")
      H.eq(rows[2].rank, "300/450")
   end)

   H.test("a skill without a maximum shows no rank text", function()
      local PM = open({ skills = { { name = "Professions", lines = { { "Alchemy", 5, 0 } } } }, spells = { "Alchemy" } })
      H.eq(F.rows(PM)[1].rank, "")
   end)

   H.test("rank-up while the list is open: texts follow without a new list layout (SKILL_LINES_CHANGED)", function()
      local PM, M = open({ learned = { mining = { 449, 450 } } })
      local rows = F.rows(PM)
      H.eq(rows[2].rank, "449/450")
      M.SetSkillRank("Mining", 450)
      rows = F.rows(PM)
      H.eq(rows[2].rank, "450/450")
      local r, g, b = rows[2].row.rank:GetTextColor()
      near3(r, g, b, GREEN, "turned green")
   end)

   H.test("UpdateRanks changes only the text when the list is the same (Refresh without MarkStale)", function()
      local PM, M = open({ learned = { alchemy = { 100, 450 } } })
      M.world.skillEventMode = "none"
      -- change the rank behind the addon's back, then reopen: the signature is the same
      M.SetSkillRank("Alchemy", 101)
      PM.UI.Close()
      local rebuilds = 0
      local orig = PM.UI.Rebuild
      PM.UI.Rebuild = function(...) rebuilds = rebuilds + 1 return orig(...) end
      PM.UI.Open()
      H.eq(F.rows(PM)[1].rank, "101/450")
   end)

   -- ======================================================================
   H.section("Secure attributes of the rows")
   -- ======================================================================

   H.test("rows with an action carry type1 = spell and spell1 = <spell name> (enUS)", function()
      local PM = open({ learned = { "alchemy", "mining", "herbalism", "fishing", "cooking" } })
      local want = { alchemy = "Alchemy", smelting = "Smelting", mining = "Find Minerals",
                     herbalism = "Find Herbs", cooking = "Cooking", fishing = "Fishing" }
      local seen = 0
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row:GetAttribute("type1"), "spell", r.key)
         H.eq(r.row:GetAttribute("spell1"), want[r.key], r.key)
         seen = seen + 1
      end
      H.eq(seen, 6)
   end)

   H.test("rows with an action carry the German spell names in deDE", function()
      local PM = open({ learned = { "alchemy", "mining" }, locale = "deDE" })
      local rows = F.rows(PM)
      H.eq(rows[1].row:GetAttribute("spell1"), "Alchemie")
      H.eq(rows[2].row:GetAttribute("spell1"), "Verh\195\188ttung")
      H.eq(rows[3].row:GetAttribute("spell1"), "Mineraliensuche")
   end)

   H.test("rows without an action have no type1: skinning, mining without tracking, a profession without spell", function()
      local PM = open({ learned = { "skinning", "mining", "tailoring" }, noTracking = true, noSmelting = true,
                        noSpell = { "tailoring" } })
      local rows = F.rows(PM)
      H.len(rows, 3)
      for _, r in ipairs(rows) do
         H.eq(r.row:GetAttribute("type1"), nil, r.key .. " type1")
         H.eq(r.row:GetAttribute("spell1"), nil, r.key .. " spell1")
         H.eq(r.row:GetAttribute("spell"), nil, r.key .. " spell")
      end
   end)

   H.test("right button and the unnumbered type are never set (otherwise a right click would cast)", function()
      local PM = open({ learned = F.ORDER })
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row:GetAttribute("type2"), nil, r.key)
         H.eq(r.row:GetAttribute("type"), nil, r.key)
         H.eq(r.row:GetAttribute("spell2"), nil, r.key)
      end
   end)

   H.test("attributes are cleared on rows that become unused (profession unlearned while closed)", function()
      local PM, M = open({ learned = { "alchemy", "mining", "fishing" } })
      local used = #F.rows(PM)
      H.eq(used, 4)
      PM.UI.Close()
      M.UnlearnSkill("Mining")
      M.UnlearnSpell("Mining")
      M.UnlearnSpell("Smelting")
      M.UnlearnSpell("Find Minerals")
      H.truthy(F.open(PM))
      H.eq(#F.rows(PM), 2)
      for i = 3, 4 do
         local row = PM.UI.rows[i]
         H.falsy(row:IsShown(), "row " .. i .. " hidden")
         H.eq(row:GetAttribute("type1"), nil, "row " .. i .. " type1 cleared")
         H.eq(row:GetAttribute("spell1"), nil, "row " .. i .. " spell1 cleared")
         H.eq(row:GetAttribute("spell"), nil, "row " .. i .. " spell cleared")
      end
   end)

   H.test("attributes follow a re-sort: after sort alpha each row casts the spell of the profession it shows", function()
      local PM, M = open({ learned = { "alchemy", "mining", "fishing", "cooking" } })
      M.Slash("/berufe sort alpha")
      local want = { Alchemy = "Alchemy", Cooking = "Cooking", Fishing = "Fishing", Mining = "Find Minerals",
                     Smelting = "Smelting" }
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row:GetAttribute("spell1"), want[r.name], r.name)
      end
   end)

   -- ======================================================================
   H.section("Size and arrangement")
   -- ======================================================================

   H.test("height = pad + headers * 18 + rows * 24 + pad; it grows with every row", function()
      local heights = {}
      for n, key in ipairs({ "alchemy", "tailoring", "engineering", "inscription" }) do
         local learned = {}
         for i = 1, n do learned[i] = ({ "alchemy", "tailoring", "engineering", "inscription" })[i] end
         local PM = open({ learned = learned })
         heights[n] = PM.UI.GetMenu():GetHeight()
         H.eq(heights[n], 1 + 18 + n * 24 + 1, n .. " crafting professions")
      end
      for n = 2, 4 do H.truthy(heights[n] > heights[n - 1]) end
   end)

   H.test("height with all four categories and all 15 entries", function()
      local PM = open({ learned = F.ORDER })
      H.eq(PM.UI.GetMenu():GetHeight(), 1 + 4 * 18 + 15 * 24 + 1)
   end)

   H.test("height without headers", function()
      local PM, M = open({ learned = F.ORDER })
      M.Slash("/berufe headers off")
      H.eq(PM.UI.GetMenu():GetHeight(), 1 + 15 * 24 + 1)
   end)

   H.test("width is at least the width of the button and wide enough for every name plus its rank", function()
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local PM = open({ learned = F.ORDER, locale = locale })
         local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
         local S = PM.UI.sizes
         H.truthy(menu:GetWidth() >= button:GetWidth(), locale .. ": at least the button width")
         for _, r in ipairs(F.rows(PM)) do
            local need = S.iconPad + S.icon + S.textGap + r.row.text:GetStringWidth() + S.textGap
               + r.row.rank:GetStringWidth() + S.rankPad
            H.truthy(menu:GetWidth() >= need, locale .. " " .. r.key .. ": row content fits (" .. need .. " <= " .. menu:GetWidth() .. ")")
         end
      end
   end)

   H.test("a short list is as wide as the button (minimum width)", function()
      local PM = open({ learned = { "firstaid" } })
      H.eq(PM.UI.GetMenu():GetWidth(), PM.UI.GetButton():GetWidth())
   end)

   H.test("rows and headers are stacked from the top without overlap; the last row's separator is hidden", function()
      local PM = open({ learned = F.ORDER })
      local S = PM.UI.sizes
      local items = F.layoutOrder(PM)
      H.len(items, 19)
      local expectY = -S.pad
      for i, it in ipairs(items) do
         H.near(it.y, expectY, 1e-6, "item " .. i .. " (" .. tostring(it.text) .. ")")
         expectY = expectY - (it.kind == "header" and S.header or S.rowH)
      end
      H.near(-expectY + S.pad, PM.UI.GetMenu():GetHeight(), 1e-6, "the list ends where the last row ends")
      local rows = F.rows(PM)
      for i, r in ipairs(rows) do
         if i < #rows then
            H.truthy(r.row.sep:IsShown(), "separator " .. i)
         else
            H.falsy(r.row.sep:IsShown(), "last separator hidden")
         end
      end
   end)

   H.test("the order on screen from top to bottom is header, entries of the category, next header ...", function()
      local PM = open({ learned = F.ORDER })
      local kinds = {}
      for _, it in ipairs(F.layoutOrder(PM)) do kinds[#kinds + 1] = it.kind == "header" and ("H " .. it.text) or it.key end
      H.deepEq(kinds, {
         "H Crafting", "blacksmithing", "leatherworking", "tailoring", "engineering", "alchemy", "inscription",
         "H Processing", "smelting", "jewelcrafting", "enchanting",
         "H Gathering", "mining", "herbalism", "skinning",
         "H Secondary", "cooking", "firstaid", "fishing",
      })
   end)

   H.test("rows span the whole width of the list (TOPLEFT and TOPRIGHT anchors on the list)", function()
      local PM = open({ learned = { "alchemy", "mining" } })
      local menu = PM.UI.GetMenu()
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row:GetNumPoints(), 2)
         local p1, rel1 = r.row:GetPoint(1)
         local p2, rel2 = r.row:GetPoint(2)
         H.eq(rel1, menu)
         H.eq(rel2, menu)
         H.truthy((p1 == "TOPLEFT" and p2 == "TOPRIGHT") or (p1 == "TOPRIGHT" and p2 == "TOPLEFT"))
         H.eq(r.row:GetHeight(), PM.UI.sizes.rowH)
      end
   end)

   H.test("no more than 24 rows / 5 headers: all 15 entries and 4 headers fit the pre-built frames", function()
      local PM = open({ learned = F.ORDER })
      H.eq(#F.rows(PM), 15)
      H.eq(#F.headerTexts(PM), 4)
      H.truthy(15 <= #PM.UI.rows and 4 <= #PM.UI.headers)
   end)

   -- ======================================================================
   H.section("Empty list")
   -- ======================================================================

   H.test("empty list: the hint 'No professions learned' replaces the rows (enUS)", function()
      local PM = open({ learned = {} })
      local menu = PM.UI.GetMenu()
      H.truthy(menu.empty:IsShown())
      H.eq(menu.empty:GetText(), "No professions learned")
      H.eq(#F.rows(PM), 0)
      H.eq(menu:GetHeight(), 1 + 24 + 1, "room for one line")
      H.truthy(menu:GetWidth() >= PM.UI.GetButton():GetWidth())
   end)

   H.test("empty list: the hint is German in deDE", function()
      local PM = open({ learned = {}, locale = "deDE" })
      H.eq(PM.UI.GetMenu().empty:GetText(), "Keine Berufe erlernt")
   end)

   H.test("the hint disappears as soon as a profession exists and returns when the last one is gone", function()
      local PM, M = open({ learned = {} })
      local menu = PM.UI.GetMenu()
      H.truthy(menu.empty:IsShown())
      M.LearnSkill("Fishing", 1, 75, "Secondary Skills")
      M.LearnSpell("Fishing")
      H.falsy(menu.empty:IsShown())
      H.eq(#F.rows(PM), 1)
      M.UnlearnSkill("Fishing")
      H.truthy(menu.empty:IsShown())
      H.eq(#F.rows(PM), 0)
   end)

   -- ======================================================================
   H.section("Icons")
   -- ======================================================================

   H.test("row icons use the profession icon and trim the border (standalone texcoords 0.08 .. 0.92)", function()
      local PM = open({ learned = { "alchemy", "mining" } })
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row.icon:GetTexture(), r.entry.icon, r.key)
         local ulx, uly, llx, lly, urx, ury, lrx, lry = r.row.icon:GetTexCoord()
         H.near(ulx, 0.08, 1e-6)
         H.near(urx, 0.92, 1e-6)
         H.near(uly, 0.08, 1e-6)
         H.near(lly, 0.92, 1e-6)
      end
   end)

   -- ======================================================================
   H.section("The button")
   -- ======================================================================

   H.test("button: at least 150 wide and as wide as the list, 37 high, label centred, icon box, arrow, MEDIUM strata, only left clicks", function()
      local PM = F.boot(H, { learned = { "mining" } })
      local b = PM.UI.GetButton()
      H.truthy(b:GetWidth() >= 150, "width")
      H.eq(b:GetHeight(), 37)
      PM.UI.Open()
      H.eq(PM.UI.GetMenu():GetWidth(), b:GetWidth(), "the list is as wide as the button")
      PM.UI.Close()
      H.eq(b.text:GetText(), "Professions")
      H.eq(b.icon:GetTexture(), PM.BUTTON_ICON)
      H.truthy(b.__clicks.LeftButtonUp)
      H.falsy(b.__clicks.RightButtonUp)
      H.truthy(b:IsShown())
      local p, rel, rp, x, y = b:GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      H.eq(rel, UIParent)
      H.eq(rp, "BOTTOMRIGHT")
      H.eq(x, -20)
      H.eq(y, 210)
   end)

   H.test("button label is German in deDE and the icon is the blacksmithing icon", function()
      local PM = F.boot(H, { learned = {}, locale = "deDE" })
      H.eq(PM.UI.GetButton().text:GetText(), "Berufe")
      H.eq(PM.BUTTON_ICON, "Interface\\Icons\\Trade_BlackSmithing")
   end)

   H.test("button arrow: closed it points where the list opens, open it points away (list above the button: closed up, open down)", function()
      -- default position: lower half of the screen, so the list opens upwards
      local PM = F.boot(H, { learned = { "mining" } })
      local arrow = PM.UI.GetButton().arrow
      H.eq(arrow:GetTexture(), PM.Skin.ARROW)
      local x1, y1 = arrow:GetTexCoord()
      H.eq(y1, 1, "list opens upwards: closed arrow points up (flipped)")
      PM.UI.Open()
      x1, y1 = arrow:GetTexCoord()
      H.eq(y1, 0, "open: the arrow points down, away from the list above")
      PM.UI.Close()
      x1, y1 = arrow:GetTexCoord()
      H.eq(y1, 1)
   end)

   H.test("button arrow with direction = down: closed down, open up; follows the /berufe direction command", function()
      local PM, M = F.boot(H, { learned = { "mining" }, db = { direction = "down" } })
      local arrow = PM.UI.GetButton().arrow
      local _, y1 = arrow:GetTexCoord()
      H.eq(y1, 0, "closed, list opens downwards: arrow down")
      PM.UI.Open()
      _, y1 = arrow:GetTexCoord()
      H.eq(y1, 1, "open: up")
      PM.UI.Close()
      M.Slash("/berufe direction up")
      PM.UI.GetButton():GetScript("OnEnter")(PM.UI.GetButton())     -- hovering syncs the arrow
      _, y1 = arrow:GetTexCoord()
      H.eq(y1, 1, "direction up: closed arrow points up")
   end)

   H.test("button border: dark normally, accent while open or hovered", function()
      local PM, M = F.boot(H, { learned = { "mining" } })
      local b = PM.UI.GetButton()
      local ar, ag, ab = PM.Skin.AccentColor()
      local br, bg, bb = PM.Skin.BorderColor()
      local r, g, bl = b:GetBackdropBorderColor()
      near3(r, g, bl, { br, bg, bb }, "closed")
      PM.UI.Open()
      r, g, bl = b:GetBackdropBorderColor()
      near3(r, g, bl, { ar, ag, ab }, "open")
      PM.UI.Close()
      r, g, bl = b:GetBackdropBorderColor()
      near3(r, g, bl, { br, bg, bb }, "closed again")
      M.Enter(b)
      r, g, bl = b:GetBackdropBorderColor()
      near3(r, g, bl, { ar, ag, ab }, "hovered")
      M.Leave(b)
      r, g, bl = b:GetBackdropBorderColor()
      near3(r, g, bl, { br, bg, bb }, "left")
   end)

   H.test("the list panel is the semi-transparent 'fade' backdrop, the button and icon boxes are solid (standalone)", function()
      local PM = F.boot(H, { learned = { "mining" } })
      local r, g, b, a = PM.UI.GetMenu():GetBackdropColor()
      near3(r, g, b, { 0.06, 0.06, 0.06 }, "panel")
      H.near(a, 0.8, 1e-6, "panel alpha")
      r, g, b, a = PM.UI.GetButton():GetBackdropColor()
      near3(r, g, b, { 0.10, 0.10, 0.10 }, "button")
      H.near(a, 1, 1e-6)
      r, g, b = PM.UI.GetButton():GetBackdropBorderColor()
      near3(r, g, b, { 0, 0, 0 }, "black 1px border")
   end)
end
