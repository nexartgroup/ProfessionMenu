-- tests/test_combat.lua
-- ---------------------------------------------------------------------------
-- Kampfsperre (Combat Lockdown). Geschuetzte Rahmen (die sicheren Zeilen und die Liste als
-- SecureHandlerStateTemplate) duerfen im Kampf nicht verschoben, ein-/ausgeblendet, umbelegt oder skaliert werden;
-- die Attrappe wirft dann "ADDON_ACTION_BLOCKED" (M.blocked) und der Runner laesst den Test durchfallen.
--
-- Zwei Reihenfolgen beim Kampfbeginn: Sperre zuerst, dann PLAYER_REGEN_DISABLED (M.EnterCombat()) oder erst das
-- Ereignis, dann die Sperre (M.EnterCombat{eventFirst = true}). Der Zustandstreiber "[combat]" fragt alle 0,2 s ab.
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function boot(opts)
      local PM, M = F.boot(H, opts)
      return PM, M
   end

   local function dim() return 0.45 end

   -- ======================================================================
   H.section("Entering and leaving combat")
   -- ======================================================================

   H.test("combat start (lockdown first): the button dims, nothing is blocked, the state driver closes the list", function()
      local PM, M = boot({ learned = { "alchemy", "mining" } })
      local button, menu = PM.UI.GetButton(), PM.UI.GetMenu()
      F.open(PM)
      M.EnterCombat()
      H.near(button:GetAlpha(), dim(), 1e-6, "button dimmed")
      -- InCombatLockdown() is already true: the addon must not touch the protected list itself
      H.truthy(menu:IsShown(), "still open until the state driver polls")
      M.Advance(0.25)
      H.falsy(menu:IsShown(), "closed by the [combat] state driver")
      H.len(M.blocked, 0)
   end)

   H.test("combat start (event first): the addon closes the list itself, nothing is blocked", function()
      local PM, M = boot({ learned = { "alchemy" } })
      local menu = PM.UI.GetMenu()
      F.open(PM)
      M.EnterCombat({ eventFirst = true })
      H.falsy(menu:IsShown(), "closed in the event handler (lockdown not yet active)")
      H.near(PM.UI.GetButton():GetAlpha(), dim(), 1e-6)
      H.len(M.blocked, 0)
   end)

   H.test("the state driver alone closes the list (even if the addon's own combat handler did nothing)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      local menu = PM.UI.GetMenu()
      F.open(PM)
      PM.UI.EnterCombat = function() end         -- as if PLAYER_REGEN_DISABLED came too late
      M.EnterCombat()
      M.Advance(0.1)
      H.falsy(menu:IsShown() == nil, "can still be open within the 0.2 s poll interval")
      M.Advance(0.2)
      H.falsy(menu:IsShown(), "closed by the driver")
   end)

   H.test("the state driver is registered at login with '[combat] 1; 0', state 0 out of combat", function()
      local PM, M = boot({ learned = { "alchemy" } })
      local menu = PM.UI.GetMenu()
      H.eq(menu:GetAttribute("state-combat"), "0")
      H.matches(menu:GetAttribute("_onstate-combat"), "Hide")
      H.eq(M.calls.RegisterStateDriver, 1)
      M.EnterCombat()
      M.Advance(0.25)
      H.eq(menu:GetAttribute("state-combat"), "1")
      M.LeaveCombat()
      M.Advance(0.25)
      H.eq(menu:GetAttribute("state-combat"), "0")
   end)

   H.test("combat end: the button is back to full alpha and the list opens again", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.EnterCombat()
      M.Advance(0.25)
      M.LeaveCombat()
      H.eq(PM.UI.GetButton():GetAlpha(), 1)
      M.Click(PM.UI.GetButton())
      H.truthy(F.isOpen(PM))
      H.len(M.blocked, 0)
   end)

   H.test("repeated combat cycles with the list open each time: never a blocked action, always closed in combat", function()
      local PM, M = boot({ learned = { "alchemy", "mining" } })
      for i = 1, 6 do
         F.open(PM)
         M.EnterCombat({ eventFirst = (i % 2 == 0) })
         M.Advance(0.3)
         H.falsy(F.isOpen(PM), "round " .. i)
         M.LeaveCombat()
         M.Advance(0.3)         -- the driver polls every 0.2 s and sees the end of the fight
      end
      H.len(M.blocked, 0)
   end)

   -- ======================================================================
   H.section("Using the button in combat")
   -- ======================================================================

   H.test("clicking the button in combat shows 'Not available in combat' and does not open the list", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.EnterCombat()
      M.Click(PM.UI.GetButton())
      H.falsy(F.isOpen(PM))
      H.len(M.uiErrors, 1)
      H.eq(M.uiErrors[1].text, "Not available in combat")
      H.near(M.uiErrors[1].g, 0.3, 1e-6)
      M.Slash("/berufe")
      H.len(M.uiErrors, 2)
      H.len(M.blocked, 0)
   end)

   H.test("the combat message is German in deDE", function()
      local PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.EnterCombat()
      M.Click(PM.UI.GetButton())
      H.eq(M.uiErrors[1].text, "Im Kampf nicht verf\195\188gbar")
   end)

   H.test("UI.Open returns false in combat and creates nothing", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.EnterCombat()
      H.eq(PM.UI.Open(), false)
      H.falsy(F.isOpen(PM))
   end)

   H.test("ESC while the list is still open at combat start only hides the unprotected ESC proxy; the state driver closes the list", function()
      -- Blizzard's close-all loop reads UISpecialFrames, a table we wrote to (tainted): a Hide() of the PROTECTED list from that
      -- path would be blocked in combat. So the protected list is never in UISpecialFrames; its proxy is.
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.EnterCombat()
      H.truthy(M.Escape())
      H.len(M.blocked, 0, "no protected call blocked")
      M.Advance(0.5)
      H.falsy(F.isOpen(PM), "the state driver closed the list")
      H.len(M.blocked, 0)
   end)

   H.test("ESC out of combat closes the list through the proxy", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      H.truthy(F.isOpen(PM))
      H.truthy(M.Escape())
      H.falsy(F.isOpen(PM))
      H.falsy(ProfessionMenuEscProxy:IsShown(), "the proxy is hidden with the list")
   end)

   H.test("an outside click in the 0.2 s before the driver polls does not touch the protected list", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      M.EnterCombat()
      M.Hover(nil)
      M.SetMouseDown("LeftButton", true)
      M.Advance(0.05)
      H.len(M.blocked, 0)
      M.SetMouseDown("LeftButton", false)
   end)

   H.test("a row click in that window casts nothing that needs out-of-combat (profession windows fail) and breaks nothing", function()
      local PM, M = boot({ learned = { "alchemy", "skinning" } })
      F.open(PM)
      M.EnterCombat()
      local rows = F.rows(PM)
      M.Click(rows[1].row)                    -- Alchemy window cannot open in combat
      H.len(M.casts, 0)
      H.deepEq(M.castFailures, { "Alchemy" })
      H.len(M.blocked, 0)
      M.Click(rows[2].row, "RightButton")     -- the skills window may open
      H.deepEq(M.toggles, { "SkillFrame" })
      H.len(M.blocked, 0)
   end)

   -- ======================================================================
   H.section("Deferred rebuilds")
   -- ======================================================================

   H.test("Refresh in combat does not rebuild; PLAYER_REGEN_ENABLED does it afterwards", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      PM.UI.Close()
      M.LearnSkill("Cooking", 5, 75, "Secondary Skills")
      M.LearnSpell("Cooking")
      M.EnterCombat()
      H.eq(PM.UI.Refresh(), false, "refused in combat")
      H.deepEq(F.rowKeys(PM), { "fishing" }, "rows untouched in combat")
      M.LeaveCombat()
      H.deepEq(F.rowKeys(PM), { "cooking", "fishing" }, "rebuilt after combat")
      H.len(M.blocked, 0)
   end)

   H.test("events in combat only mark the list stale; the first open after combat shows the new state", function()
      local PM, M = boot({ learned = { "fishing" } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      M.LearnSkill("Cooking", 5, 75, "Secondary Skills")
      M.LearnSpell("Cooking")
      M.Fire("SPELLS_CHANGED")
      H.len(M.blocked, 0)
      M.LeaveCombat()
      F.open(PM)
      H.deepEq(F.rowKeys(PM), { "cooking", "fishing" })
   end)

   H.test("settings changed in combat (sort, headers, ranks, direction) neither throw nor block; they apply afterwards", function()
      local PM, M = boot({ learned = { "alchemy", "fishing", "cooking" } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      for _, cmd in ipairs({ "/berufe sort alpha", "/berufe headers off", "/berufe ranks off", "/berufe direction down" }) do
         M.Slash(cmd)
      end
      H.len(M.blocked, 0)
      H.eq(F.chatCount(M, "Error in"), 0)
      M.LeaveCombat()
      F.open(PM)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Cooking", "Fishing" })
      H.eq(#F.headerTexts(PM), 0)
      H.eq(F.rows(PM)[1].rank, "")
   end)

   H.test("/berufe list, debug, lock/unlock, reset in combat do not touch protected frames (standalone)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.EnterCombat()
      for _, cmd in ipairs({ "/berufe list", "/berufe debug", "/berufe debug", "/berufe unlock", "/berufe lock", "/berufe reset" }) do
         M.Slash(cmd)
      end
      H.len(M.blocked, 0)
      H.eq(F.chatCount(M, "Error in"), 0)
   end)

   H.test("/berufe scale in combat must not hit a protected frame (menu:SetScale is blocked), button and list stay consistent", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      M.Slash("/berufe scale 1.5")
      H.len(M.blocked, 0)
      H.eq(F.chatCount(M, "Error in"), 0)
      M.LeaveCombat()
      H.eq(PM.UI.GetButton():GetScale(), PM.UI.GetMenu():GetScale(), "button and list scaled alike")
      M.blocked = {}
      H.allowBlocked()
      H.allowGuardErrors()
   end)

   H.test("dragging the unlocked button in combat is allowed (the button is not in the protected chain)", function()
      local PM, M = boot({ learned = { "alchemy" }, db = { locked = false } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      M.Drag(PM.UI.GetButton(), 40, 40)
      H.len(M.blocked, 0)
      H.truthy(PM.db.pos, "position saved")
   end)

   -- ======================================================================
   H.section("Login in combat")
   -- ======================================================================

   H.test("PLAYER_LOGIN in combat creates nothing; the first PLAYER_REGEN_ENABLED builds the UI once", function()
      local PM, M = boot({ learned = { "alchemy", "mining" }, combat = true })
      H.falsy(PM.ready)
      H.truthy(PM.startAfterCombat)
      H.eq(rawget(_G, "ProfessionMenuButton"), nil)
      H.eq(rawget(_G, "ProfessionMenuList"), nil)
      H.eq(rawget(_G, "ProfessionMenuRow1"), nil)
      H.eq(PM.UI.GetButton(), nil)
      -- everything that can come in the meantime is harmless
      M.Slash("/berufe")
      M.Slash("/berufe sort alpha")
      M.Fire("SKILL_LINES_CHANGED")
      M.Fire("SPELLS_CHANGED")
      M.Fire("PLAYER_REGEN_DISABLED")
      H.eq(F.chatCount(M, "Error in"), 0)
      M.LeaveCombat()
      H.truthy(PM.ready)
      H.eq(PM.startAfterCombat, nil)
      local frames = #M.frames
      H.truthy(PM.UI.GetButton())
      H.eq(PM.UI.GetButton():GetAlpha(), 1)
      for i = 1, 24 do H.truthy(rawget(_G, "ProfessionMenuRow" .. i)) end
      M.LeaveCombat()
      H.eq(#M.frames, frames, "a second PLAYER_REGEN_ENABLED creates nothing")
      M.Slash("/berufe")
      H.truthy(F.isOpen(PM))
      H.deepEq(F.rowKeys(PM), { "alchemy", "mining", "smelting" }, "sorted alphabetically as commanded before login finished")
   end)

   H.test("the settings given before the UI existed (sort alpha) are used when it appears", function()
      local PM, M = boot({ learned = { "alchemy", "fishing" }, combat = true })
      M.Slash("/berufe sort alpha")
      M.Slash("/berufe ranks off")
      M.LeaveCombat()
      F.open(PM)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Fishing" })
      H.eq(F.rows(PM)[1].rank, "")
   end)

   H.test("/berufe reset before the UI exists (login in combat) also clears the saved position", function()
      local PM, M = boot({ learned = { "alchemy" }, combat = true,
                           db = { pos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -10 } } })
      M.Slash("/berufe reset")
      H.eq(PM.db.pos, nil, "saved position cleared")
   end)

   H.test("no handler errors and no blocked actions during a whole login in combat and the first fight", function()
      local PM, M = boot({ learned = F.ORDER, combat = true })
      M.LeaveCombat()
      F.open(PM)
      M.EnterCombat()
      M.Advance(0.3)
      M.LeaveCombat()
      H.len(M.blocked, 0)
      H.len(M.errors, 0)
   end)

   -- ======================================================================
   H.section("What is protected")
   -- ======================================================================

   H.test("in combat any direct call that moves, shows, hides, scales or re-attributes a row throws (guards the mock itself)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      local row = PM.UI.rows[1]
      H.throws(function() row:SetAttribute("type1", "spell") end, "ADDON_ACTION_BLOCKED")
      H.throws(function() row:SetPoint("TOPLEFT", PM.UI.GetMenu(), "TOPLEFT", 0, 0) end, "ADDON_ACTION_BLOCKED")
      H.throws(function() PM.UI.GetMenu():SetScale(2) end, "ADDON_ACTION_BLOCKED")
      H.throws(function() PM.UI.GetMenu():SetWidth(10) end, "ADDON_ACTION_BLOCKED")
      H.throws(function() PM.UI.GetMenu():Show() end, "ADDON_ACTION_BLOCKED")
      PM.UI.GetButton():SetScale(1.2)         -- the button is free
      PM.UI.GetButton():SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      PM.UI.GetButton():SetAlpha(0.5)
      M.blocked = {}
   end)
end
