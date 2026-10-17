-- tests/test_behaviour.lua
-- ---------------------------------------------------------------------------
-- Verhalten der Liste (UI.lua, Main.lua): Auf-/Zuklappen, Klick ausserhalb, ESC, Klick auf Zeilen (sicherer
-- Zauber), Rechtsklick/Passiv -> Fertigkeitenfenster, Berufsfenster ersetzen, Aktualisierung bei Ereignissen,
-- Signatur (kein Neuaufbau ohne Aenderung), Richtung/Ankerung, Tooltips, Speicher.
-- Der Kampf hat eine eigene Datei (test_combat.lua).
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function boot(opts)
      local PM, M = F.boot(H, opts)
      H.truthy(PM.ready, "addon ready")
      return PM, M
   end

   local function infoFor(PM, key)
      for _, r in ipairs(F.rows(PM)) do
         if r.key == key then return r end
      end
      return nil
   end

   local function rowFor(PM, key)
      local info = infoFor(PM, key)
      return info and info.row or nil
   end

   local function countRebuilds(PM)
      local n = { count = 0 }
      local orig = PM.UI.Rebuild
      PM.UI.Rebuild = function(...)
         n.count = n.count + 1
         return orig(...)
      end
      return n
   end

   local function tip()
      local out = {}
      for i = 1, 12 do
         local fs = rawget(_G, "GameTooltipTextLeft" .. i)
         if fs and fs:IsShown() and fs:GetText() then out[#out + 1] = fs:GetText() end
      end
      return out
   end

   -- ======================================================================
   H.section("Open and close")
   -- ======================================================================

   H.test("a click on the button opens the list, the next click closes it", function()
      local PM, M = boot({ learned = { "mining", "alchemy" } })
      local button, menu = PM.UI.GetButton(), PM.UI.GetMenu()
      H.falsy(menu:IsShown())
      M.Click(button)
      H.truthy(menu:IsShown())
      M.Click(button)
      H.falsy(menu:IsShown())
      M.Click(button)
      H.truthy(menu:IsShown())
   end)

   H.test("a right click on the button does nothing (only left clicks are registered)", function()
      local PM, M = boot({ learned = { "mining" } })
      M.Click(PM.UI.GetButton(), "RightButton")
      H.falsy(PM.UI.GetMenu():IsShown())
   end)

   H.test("/berufe and /berufe toggle and /profmenu toggle the list", function()
      local PM, M = boot({ learned = { "mining" } })
      local menu = PM.UI.GetMenu()
      H.truthy(M.Slash("/berufe"))
      H.truthy(menu:IsShown())
      M.Slash("/berufe toggle")
      H.falsy(menu:IsShown())
      M.Slash("/profmenu")
      H.truthy(menu:IsShown())
      M.Slash("/BERUFE")
      H.falsy(menu:IsShown())
   end)

   H.test("ESC closes the list (UISpecialFrames)", function()
      local PM, M = boot({ learned = { "mining" } })
      F.open(PM)
      H.truthy(M.Escape())
      H.falsy(F.isOpen(PM))
      H.falsy(M.Escape(), "nothing left to close")
   end)

   H.test("a click outside closes the list; a click on the list or on the button does not", function()
      local PM, M = boot({ learned = { "mining", "alchemy" } })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      F.open(PM)
      -- no mouse button down: nothing happens
      M.Advance(0.2)
      H.truthy(menu:IsShown())
      -- mouse down over a row (counts as over the list)
      M.Hover(PM.UI.rows[1])
      M.SetMouseDown("LeftButton", true)
      M.Advance(0.1)
      H.truthy(menu:IsShown(), "inside the list")
      -- mouse down over the toggle button
      M.Hover(button)
      M.Advance(0.1)
      H.truthy(menu:IsShown(), "on the button (its own click toggles)")
      -- mouse down over nothing
      M.Hover(nil)
      M.Advance(0.1)
      H.falsy(menu:IsShown(), "outside")
      M.SetMouseDown("LeftButton", false)
   end)

   H.test("a right-button press outside closes the list as well", function()
      local PM, M = boot({ learned = { "mining" } })
      F.open(PM)
      M.Hover(nil)
      M.SetMouseDown("RightButton", true)
      M.Advance(0.1)
      H.falsy(F.isOpen(PM))
      M.SetMouseDown("RightButton", false)
   end)

   H.test("a middle-button press outside does not close the list (only left and right are watched)", function()
      local PM, M = boot({ learned = { "mining" } })
      F.open(PM)
      M.Hover(nil)
      M.SetMouseDown("MiddleButton", true)
      M.Advance(0.1)
      H.truthy(F.isOpen(PM))
      M.SetMouseDown("MiddleButton", false)
   end)

   H.test("while closed there is no OnUpdate work: no visible frame has an OnUpdate script", function()
      local PM, M = boot({ learned = { "mining" } })
      H.len(M.UpdateFrames(), 0)
      F.open(PM)
      local frames = M.UpdateFrames()
      H.len(frames, 1)
      H.eq(frames[1], PM.UI.GetMenu())
      PM.UI.Close()
      H.len(M.UpdateFrames(), 0)
   end)

   -- ======================================================================
   H.section("Clicking a row")
   -- ======================================================================

   local CAST_CASES = {
      { key = "alchemy", spell = "Alchemy" },
      { key = "blacksmithing", spell = "Blacksmithing" },
      { key = "smelting", spell = "Smelting" },
      { key = "mining", spell = "Find Minerals" },
      { key = "herbalism", spell = "Find Herbs" },
      { key = "cooking", spell = "Cooking" },
      { key = "firstaid", spell = "First Aid" },
      { key = "fishing", spell = "Fishing" },
   }

   for _, case in ipairs(CAST_CASES) do
      H.test("a left click on '" .. case.key .. "' casts '" .. case.spell .. "' and closes the list", function()
         local PM, M = boot({ learned = F.ORDER })
         F.open(PM)
         local row = rowFor(PM, case.key)
         H.truthy(row, "row exists")
         M.Click(row)
         H.deepEq(M.casts, { case.spell })
         H.deepEq(M.toggles, {}, "the skills window stays closed")
         H.falsy(F.isOpen(PM), "list closed")
         H.len(M.castFailures, 0)
      end)
   end

   H.test("German client: a click casts the German spell name", function()
      local PM, M = boot({ learned = { "alchemy", "mining" }, locale = "deDE" })
      F.open(PM)
      M.Click(rowFor(PM, "smelting"))
      M.Click(F.open(PM) and rowFor(PM, "mining"))
      M.Click(F.open(PM) and rowFor(PM, "alchemy"))
      H.deepEq(M.casts, { "Verh\195\188ttung", "Mineraliensuche", "Alchemie" })
   end)

   H.test("a left click on a passive profession (skinning) opens the skills window, no cast, list closed", function()
      local PM, M = boot({ learned = { "skinning" } })
      F.open(PM)
      M.Click(rowFor(PM, "skinning"))
      H.deepEq(M.casts, {})
      H.deepEq(M.toggles, { "SkillFrame" })
      H.falsy(F.isOpen(PM))
   end)

   H.test("a left click on a profession whose spell is not known opens the skills window as well", function()
      local PM, M = boot({ learned = { "tailoring" }, noSpell = { "tailoring" } })
      F.open(PM)
      M.Click(rowFor(PM, "tailoring"))
      H.deepEq(M.casts, {})
      H.deepEq(M.toggles, { "SkillFrame" })
   end)

   H.test("a right click on any row opens the skills window instead of casting", function()
      local PM, M = boot({ learned = { "alchemy", "mining", "skinning" } })
      for _, key in ipairs({ "alchemy", "smelting", "mining", "skinning" }) do
         F.open(PM)
         M.toggles = {}
         M.Click(rowFor(PM, key), "RightButton")
         H.deepEq(M.casts, {}, key .. ": no cast")
         H.deepEq(M.toggles, { "SkillFrame" }, key)
         H.falsy(F.isOpen(PM), key .. ": closed")
      end
   end)

   H.test("a middle click is ignored (not registered): nothing happens, the list stays open", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"), "MiddleButton")
      H.deepEq(M.casts, {})
      H.deepEq(M.toggles, {})
      H.truthy(F.isOpen(PM))
   end)

   H.test("the skills window toggles: the second open row click closes it again", function()
      local PM, M = boot({ learned = { "skinning" } })
      F.open(PM)
      M.Click(rowFor(PM, "skinning"))
      H.truthy(CharacterFrame:IsShown())
      F.open(PM)
      M.Click(rowFor(PM, "skinning"))
      H.falsy(CharacterFrame:IsShown())
   end)

   H.test("Shift/Ctrl/Alt + left click on a row casts like a plain click (type1 is not a wildcard attribute)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      for _, mods in ipairs({ { shift = true }, { ctrl = true }, { alt = true } }) do
         F.open(PM)
         M.casts = {}
         M.Click(rowFor(PM, "alchemy"), "LeftButton", mods)
         H.deepEq(M.casts, { "Alchemy" }, "modifier click")
         PM.UI.Close()
      end
   end)

   H.test("clicking a row that was just rebuilt for another profession casts the new spell, never the old one", function()
      local PM, M = boot({ learned = { "alchemy", "fishing" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      M.casts = {}
      M.Slash("/berufe sort alpha")            -- Alchemy, Fishing -> same order; use rank sort to swap them
      M.SetSkillRank("Fishing", 450, 450)
      M.Slash("/berufe sort rank")
      F.open(PM)
      local rows = F.rows(PM)
      H.eq(rows[1].key, "fishing")
      M.Click(rows[1].row)
      H.deepEq(M.casts, { "Fishing" })
   end)

   -- ======================================================================
   H.section("Replacing an open profession window")
   -- ======================================================================

   H.test("with a profession window open, a click on another profession closes it first (PreClick) and opens the new one", function()
      local PM, M = boot({ learned = { "alchemy", "blacksmithing" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      H.eq(M.tradeSkill.open, "Alchemy")
      H.eq(M.tradeSkill.closes, 0, "nothing to close the first time")
      F.open(PM)
      M.Click(rowFor(PM, "blacksmithing"))
      H.eq(M.tradeSkill.closes, 1, "CloseTradeSkill was called in PreClick")
      H.eq(M.tradeSkill.open, "Blacksmithing")
      H.deepEq(M.casts, { "Alchemy", "Blacksmithing" })
   end)

   H.test("a click on the profession whose window is already open reopens it instead of toggling it shut", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      H.eq(M.tradeSkill.open, "Alchemy", "the window is open at the end")
      H.truthy(TradeSkillFrame:IsShown())
   end)

   H.test("tracking and fishing clicks do not touch an open profession window", function()
      local PM, M = boot({ learned = { "alchemy", "mining", "fishing" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      F.open(PM)
      M.Click(rowFor(PM, "mining"))
      F.open(PM)
      M.Click(rowFor(PM, "fishing"))
      H.eq(M.tradeSkill.closes, 0)
      H.eq(M.tradeSkill.open, "Alchemy")
      H.eq(M.tracking, "Find Minerals")
   end)

   H.test("a right click with a profession window open does not close it", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"))
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"), "RightButton")
      H.eq(M.tradeSkill.closes, 0)
   end)

   -- ======================================================================
   H.section("Refreshing")
   -- ======================================================================

   H.test("learning a profession while the list is open adds it (skill line first, spell second)", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      H.deepEq(F.rowKeys(PM), { "fishing" })
      M.LearnSkill("Alchemy", 1, 75, "Professions")
      H.deepEq(F.rowKeys(PM), { "alchemy", "fishing" }, "listed as soon as the skill line exists")
      H.eq(rowFor(PM, "alchemy"):GetAttribute("type1"), nil, "no spell yet: passive")
      M.LearnSpell("Alchemy")
      H.eq(rowFor(PM, "alchemy"):GetAttribute("type1"), "spell")
      H.eq(rowFor(PM, "alchemy"):GetAttribute("spell1"), "Alchemy")
      F.open(PM)
      H.truthy(F.isOpen(PM))
   end)

   H.test("learning a profession while the list is open adds it (spell first, skill line second)", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      M.LearnSpell("Alchemy")
      H.deepEq(F.rowKeys(PM), { "fishing" }, "a spell without a skill line is not a profession")
      M.LearnSkill("Alchemy", 1, 75, "Professions")
      H.deepEq(F.rowKeys(PM), { "alchemy", "fishing" })
      H.eq(rowFor(PM, "alchemy"):GetAttribute("spell1"), "Alchemy")
      H.eq(#F.headerTexts(PM), 2)
   end)

   H.test("unlearning a profession while the list is open removes the row and closes the gap", function()
      local PM, M = boot({ learned = { "alchemy", "fishing", "cooking" } })
      F.open(PM)
      local h = PM.UI.GetMenu():GetHeight()
      M.UnlearnSkill("Alchemy")
      M.UnlearnSpell("Alchemy")
      H.deepEq(F.rowKeys(PM), { "cooking", "fishing" })
      H.eq(#F.headerTexts(PM), 1)
      H.eq(PM.UI.GetMenu():GetHeight(), h - 18 - 24)
   end)

   H.test("learning mining adds mining and smelting; mining without the smelting spell adds only mining", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      M.LearnSkill("Mining", 1, 75, "Professions")
      M.LearnSpell("Mining")
      M.LearnSpell("Find Minerals")
      H.deepEq(F.rowKeys(PM), { "mining", "fishing" })
      M.LearnSpell("Smelting")
      H.deepEq(F.rowKeys(PM), { "smelting", "mining", "fishing" })
   end)

   H.test("events while the list is closed only invalidate: the next open shows the new state", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      PM.UI.Close()
      M.LearnSkill("Cooking", 5, 75, "Secondary Skills")
      M.LearnSpell("Cooking")
      H.deepEq(F.rowKeys(PM), { "fishing" }, "not rebuilt while closed")
      F.open(PM)
      H.deepEq(F.rowKeys(PM), { "cooking", "fishing" })
   end)

   H.test("opening twice without changes rebuilds once; a second open is a cheap rank update", function()
      local PM, M = boot({ learned = { "alchemy", "mining" } })
      local n = countRebuilds(PM)
      F.open(PM)
      H.eq(n.count, 1)
      PM.UI.Close()
      F.open(PM)
      PM.UI.Close()
      F.open(PM)
      H.eq(n.count, 1, "same list: no new rebuild")
   end)

   H.test("changing the sort order rebuilds; the signature differs per sort mode", function()
      local PM, M = boot({ learned = { "alchemy", "mining" } })
      local n = countRebuilds(PM)
      F.open(PM)
      M.Slash("/berufe sort alpha")
      H.truthy(n.count >= 2)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Mining", "Smelting" })
   end)

   H.test("SPELLS_CHANGED with unchanged data while the list is open must not rebuild it (signature unchanged)", function()
      local PM, M = boot({ learned = { "alchemy", "mining" } })
      F.open(PM)
      local n = countRebuilds(PM)
      M.Fire("SPELLS_CHANGED")
      M.Fire("SPELLS_CHANGED")
      M.Fire("LEARNED_SPELL_IN_TAB", 1)
      M.Fire("SKILL_LINES_CHANGED")
      M.Advance(1)       -- past the ignore window, if any
      M.Fire("SKILL_LINES_CHANGED")
      H.eq(n.count, 0, "rebuilds caused by events that changed nothing")
   end)

   H.test("repeated open/close and rebuild cycles do not leak frames or regions", function()
      local PM, M = boot({ learned = F.ORDER })
      F.open(PM)
      PM.UI.Close()
      local frames = #M.frames
      local regions = 0
      M.Walk(PM.UI.GetMenu(), function() regions = regions + 1 end)
      for i = 1, 40 do
         F.open(PM)
         M.Slash(i % 2 == 0 and "/berufe sort alpha" or "/berufe sort cat")
         M.Fire("SPELLS_CHANGED")
         PM.UI.Close()
      end
      local after = 0
      M.Walk(PM.UI.GetMenu(), function() after = after + 1 end)
      H.eq(#M.frames, frames, "frame count")
      H.eq(after, regions, "objects below the list")
   end)

   H.test("a second PLAYER_LOGIN or ADDON_LOADED does not create anything twice", function()
      local PM, M = boot({ learned = { "alchemy" } })
      local frames = #M.frames
      M.Fire("PLAYER_LOGIN")
      M.Fire("ADDON_LOADED", "ProfessionMenu")
      M.Fire("PLAYER_LOGIN")
      H.eq(#M.frames, frames)
      H.eq(M.errors[1], nil)
   end)

   -- ======================================================================
   H.section("Direction and placement")
   -- ======================================================================

   local function place(pos, direction, extra)
      local db = { pos = pos, direction = direction or "auto" }
      for k, v in pairs(extra or {}) do db[k] = v end
      local PM, M = boot({ learned = { "alchemy", "mining" }, db = db })
      F.open(PM)
      return PM, M
   end

   local function points(menu)
      local p, rel, rp, x, y = menu:GetPoint(1)
      return p, rp, x, y
   end

   H.test("auto: a button in the lower half opens upwards, a button in the upper half downwards", function()
      local PM = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 100, y = 100 })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      H.truthy(menu:GetBottom() > button:GetTop(), "menu above the button")
      H.near(menu:GetBottom(), button:GetTop() + PM.UI.sizes.menuGap, 1e-6, "gap between button and list")
      PM = place({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 100, y = -100 })
      menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      H.truthy(menu:GetTop() < button:GetBottom(), "menu below the button")
      H.near(menu:GetTop(), button:GetBottom() - PM.UI.sizes.menuGap, 1e-6)
   end)

   H.test("auto: left half aligns the left edges, right half aligns the right edges", function()
      local PM = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 50, y = 100 })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      H.near(menu:GetLeft(), button:GetLeft(), 1e-6)
      H.eq((points(menu)), "BOTTOMLEFT")
      PM = place({ point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -50, y = 100 })
      menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      H.near(menu:GetRight(), button:GetRight(), 1e-6)
      H.eq((points(menu)), "BOTTOMRIGHT")
   end)

   H.test("auto: all four corners of the screen pick the matching anchor pair", function()
      local cases = {
         { { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 20, y = 20 }, "BOTTOMLEFT" },
         { { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 20 }, "BOTTOMRIGHT" },
         { { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -20 }, "TOPLEFT" },
         { { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -20, y = -20 }, "TOPRIGHT" },
      }
      for _, c in ipairs(cases) do
         local PM = place(c[1])
         H.eq((points(PM.UI.GetMenu())), c[2], c[2])
      end
   end)

   H.test("direction up / down override the screen half", function()
      local PM = place({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 100, y = -50 }, "up")
      H.truthy(PM.UI.GetMenu():GetBottom() > PM.UI.GetButton():GetTop(), "forced up at the top of the screen")
      PM = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 100, y = 50 }, "down")
      H.truthy(PM.UI.GetMenu():GetTop() < PM.UI.GetButton():GetBottom(), "forced down at the bottom of the screen")
   end)

   H.test("/berufe direction changes take effect at the next open", function()
      local PM, M = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 100, y = 50 })
      H.truthy(PM.UI.GetMenu():GetBottom() > PM.UI.GetButton():GetTop())
      PM.UI.Close()
      M.Slash("/berufe direction down")
      F.open(PM)
      H.truthy(PM.UI.GetMenu():GetTop() < PM.UI.GetButton():GetBottom())
   end)

   H.test("placement is exact with a scaled button (/berufe scale 1.5) and a small UI scale", function()
      local PM, M = boot({ learned = { "alchemy", "mining" }, world = { uiScale = 0.7 },
                           db = { scale = 1.5, pos = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 200, y = 150 } } })
      F.open(PM)
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      local bs, ms = button:GetEffectiveScale(), menu:GetEffectiveScale()
      H.near(bs, ms, 1e-9, "same effective scale")
      H.near(menu:GetBottom() * ms, button:GetTop() * bs + PM.UI.sizes.menuGap * ms, 1e-6)
      H.near(menu:GetLeft() * ms, button:GetLeft() * bs, 1e-6)
   end)

   H.test("the list follows the button to a new place on the next open", function()
      local PM, M = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 100, y = 100 })
      local menu, button = PM.UI.GetMenu(), PM.UI.GetButton()
      local left = menu:GetLeft()
      PM.UI.Close()
      button:ClearAllPoints()
      button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 400, 300)
      F.open(PM)
      H.near(menu:GetLeft(), 400, 1e-6)
      H.near(menu:GetBottom(), 300 + button:GetHeight() + PM.UI.sizes.menuGap, 1e-6)
      H.neq(menu:GetLeft(), left)
   end)

   H.test("a button without a resolvable position (no anchor yet): the list opens in the screen centre, nothing fails", function()
      local PM, M = boot({ learned = { "alchemy" } })
      PM.UI.GetButton():ClearAllPoints()
      H.truthy(PM.UI.Open())
      local menu = PM.UI.GetMenu()
      local p, rel, rp, x, y = menu:GetPoint(1)
      H.eq(p, "CENTER")
      H.eq(rel, UIParent)
      H.eq(x, 0)
      H.eq(y, 0)
      M.Enter(PM.UI.rows[1])
      H.eq(GameTooltip.__anchorType, "ANCHOR_RIGHT")
   end)

   H.test("row tooltips open to the right in the left half and to the left in the right half", function()
      local PM, M = place({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 50, y = 100 })
      M.Enter(PM.UI.rows[1])
      H.eq(GameTooltip.__anchorType, "ANCHOR_RIGHT")
      M.Leave(PM.UI.rows[1])
      PM = place({ point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -50, y = 100 })
      M.Enter(PM.UI.rows[1])
      H.eq(GameTooltip.__anchorType, "ANCHOR_LEFT")
   end)

   -- ======================================================================
   H.section("Tooltips")
   -- ======================================================================

   H.test("button tooltip: title and hint; hidden again when the mouse leaves", function()
      local PM, M = boot({ learned = { "mining" } })
      local b = PM.UI.GetButton()
      M.Enter(b)
      H.truthy(GameTooltip:IsShown())
      H.eq(GameTooltip:GetOwner(), b)
      H.deepEq(tip(), { "Professions", "Click: open list" })
      M.Leave(b)
      H.falsy(GameTooltip:IsShown())
   end)

   H.test("button tooltip in German", function()
      local PM, M = boot({ learned = { "mining" }, locale = "deDE" })
      M.Enter(PM.UI.GetButton())
      H.deepEq(tip(), { "Berufe", "Klick: Liste \195\182ffnen" })
   end)

   local TIP_CASES = {
      { key = "alchemy", hint = "Left-click: open" },
      { key = "smelting", hint = "Left-click: open" },
      { key = "mining", hint = "Left-click: start tracking" },
      { key = "herbalism", hint = "Left-click: start tracking" },
      { key = "fishing", hint = "Left-click: use" },
      { key = "skinning", hint = "Nothing to open - left-click shows your skills" },
   }
   for _, case in ipairs(TIP_CASES) do
      H.test("row tooltip for " .. case.key .. ": name, skill level, '" .. case.hint .. "', right-click hint", function()
         local PM, M = boot({ learned = { "alchemy", "mining", "herbalism", "fishing", "skinning" } })
         F.open(PM)
         local info = infoFor(PM, case.key)
         local row = info.row
         M.Enter(row)
         H.eq(GameTooltip:GetOwner(), row)
         H.deepEq(tip(), { info.name, "Skill: 300 / 450", " ", case.hint, "Right-click: skills window" }, case.key)
         M.Leave(row)
         H.falsy(GameTooltip:IsShown())
      end)
   end

   H.test("row tooltip: no skill line when the maximum is unknown (0)", function()
      local PM, M = boot({ skills = { { name = "Professions", lines = { { "Alchemy", 5, 0 } } } }, spells = { "Alchemy" } })
      F.open(PM)
      M.Enter(PM.UI.rows[1])
      H.deepEq(tip(), { "Alchemy", " ", "Left-click: open", "Right-click: skills window" })
   end)

   H.test("row tooltip in German", function()
      local PM, M = boot({ learned = { "mining" }, locale = "deDE" })
      F.open(PM)
      M.Enter(PM.UI.rows[1])
      H.deepEq(tip(), { "Verh\195\188ttung", "Fertigkeit: 300 / 450", " ", "Linksklick: \195\182ffnen", "Rechtsklick: Fertigkeitenfenster" })
   end)

   H.test("tooltip shows the data of the row's current entry after a rebuild", function()
      local PM, M = boot({ learned = { "alchemy", "fishing" } })
      F.open(PM)
      M.Slash("/berufe sort alpha")
      M.SetSkillRank("Fishing", 77, 450)
      local row = PM.UI.rows[2]
      M.Enter(row)
      H.eq(tip()[1], "Fishing")
      H.eq(tip()[2], "Skill: 77 / 450")
   end)

   H.test("the tooltip of a row must not stay on screen after the click closed the list", function()
      local PM, M = boot({ learned = { "skinning" } })
      F.open(PM)
      local row = rowFor(PM, "skinning")
      M.Enter(row)
      H.truthy(GameTooltip:IsShown())
      M.Click(row)
      H.falsy(F.isOpen(PM))
      -- the hidden row never gets an OnLeave; its tooltip would hang around (owner invisible)
      H.falsy(GameTooltip:IsShown() and GameTooltip:GetOwner() and not GameTooltip:GetOwner():IsVisible(),
         "tooltip owned by a hidden row is still shown")
   end)

   H.test("the tooltip of a row must not stay on screen after ESC/outside click closed the list", function()
      local PM, M = boot({ learned = { "skinning" } })
      F.open(PM)
      M.Enter(PM.UI.rows[1])
      M.Escape()
      H.falsy(GameTooltip:IsShown() and GameTooltip:GetOwner() and not GameTooltip:GetOwner():IsVisible(),
         "tooltip owned by a hidden row is still shown")
   end)
end
