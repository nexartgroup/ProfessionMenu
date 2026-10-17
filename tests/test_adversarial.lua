-- tests/test_adversarial.lua
-- ---------------------------------------------------------------------------
-- Boese Faelle: kaputte SavedVariables, merkwuerdige Fertigkeitszeilen, Fehler mitten im Lesen, Ereignisfluten,
-- Lesen ohne Daten (nil-Zugriffe), Zeit- und Reihenfolgeprobleme.
-- Tests mit "BUG?" pruefen Robustheit, die im normalen Spiel selten gebraucht wird.
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   -- ======================================================================
   H.section("Saved variables that are not what the addon wrote")
   -- ======================================================================

   H.test("unknown sort / direction values in the saved variables are replaced by the defaults", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining", "fishing" }, db = { sort = "bogus", direction = "sideways" } })
      H.truthy(PM.ready)
      H.eq(PM.db.sort, "cat")
      H.eq(PM.db.direction, "auto")
      F.open(PM)
      H.deepEq(F.rowKeys(PM), { "alchemy", "smelting", "mining", "fishing" }, "category order")
      H.eq(#F.headerTexts(PM), 4, "sort fell back to 'cat': one header per category")
      H.truthy(PM.UI.GetMenu():IsShown())
   end)

   H.test("saved headers/ranks of the wrong type (strings, numbers) do not crash the layout", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, db = { headers = "yes", ranks = 1 } })
      H.truthy(PM.ready)
      F.open(PM)
      H.len(F.rows(PM), 1)
   end)

   H.test("a saved scale of 0, a negative scale or a non-finite scale does not break the start (replaced by 1)", function()
      for _, bad in ipairs({ 0, -1, 1 / 0 }) do
         local PM = F.boot(H, { learned = { "alchemy" }, db = { scale = bad } })
         H.truthy(PM.ready, "scale " .. tostring(bad) .. " aborted the creation of the UI")
         H.eq(PM.db.scale, 1)
      end
   end)

   H.test("a saved position with an invalid anchor point does not break the start (position dropped)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { pos = { point = "MIDDLE", relPoint = "MIDDLE", x = 1, y = 1 } } })
      H.truthy(PM.ready, "an invalid saved anchor point aborted the creation of the UI")
      H.eq(PM.db.pos, nil)
   end)

   H.test("a huge but valid saved scale (2.5) and extreme position values are accepted", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { scale = 2.5, pos = { point = "CENTER", relPoint = "CENTER", x = 99999, y = -99999 } } })
      H.truthy(PM.ready)
      F.open(PM)
      H.truthy(F.isOpen(PM))
   end)

   -- ======================================================================
   H.section("Odd skill data")
   -- ======================================================================

   H.test("very many skill lines (300) are read without trouble", function()
      local lines = {}
      for i = 1, 300 do lines[i] = { "Skill " .. i, i, 300 } end
      lines[#lines + 1] = { "Mining", 100, 300 }
      local PM, M = F.boot(H, { skills = { { name = "Professions", lines = lines } }, spells = { "Mining", "Smelting" } })
      local entries = PM.Collect()
      H.eq(#entries, 2)
   end)

   H.test("duplicate skill names: the later one wins, no crash", function()
      local PM = F.boot(H, { skills = { { name = "Professions", lines = { { "Mining", 10, 75 }, { "Mining", 200, 300 } } } },
                             spells = { "Mining" } })
      local entries = PM.Collect()
      H.eq(entries[1].rank, 200)
   end)

   H.test("a skill line with an empty name is ignored", function()
      local PM = F.boot(H, { skills = { { name = "Professions", lines = { { "", 1, 1 }, { "Fishing", 5, 75 } } } },
                             spells = { "Fishing" } })
      H.deepEq((function() local k = {} for _, e in ipairs((PM.Collect())) do k[#k + 1] = e.key end return k end)(), { "fishing" })
   end)

   H.test("negative or huge ranks are shown as they are (no formatting error)", function()
      local PM = F.boot(H, { skills = { { name = "Professions", lines = { { "Alchemy", -5, 450 }, { "Mining", 99999, 450 } } } },
                             spells = { "Alchemy", "Mining" } })
      F.open(PM)
      local rows = F.rows(PM)
      H.eq(rows[1].rank, "-5/450")
      H.eq(rows[2].rank, "99999/450")
   end)

   H.test("skill lines of a character without any headers (flat list)", function()
      local PM = F.boot(H, { skills = {}, spells = {} })
      F.open(PM)
      H.truthy(PM.UI.GetMenu().empty:IsShown())
   end)

   H.test("only headers, no lines at all", function()
      local PM = F.boot(H, { skills = { { name = "Professions", lines = {} }, { name = "Secondary Skills", lines = {} } }, spells = {} })
      F.open(PM)
      H.truthy(PM.UI.GetMenu().empty:IsShown())
      local before = H.mock.SkillStates()
      PM.Collect()
      H.deepEq(H.mock.SkillStates(), before)
   end)

   H.test("collapsed headers with no profession below them cost nothing and are restored", function()
      local PM, M = F.boot(H, { learned = {}, collapsed = { ["Weapon Skills"] = true, ["Class Skills"] = true, Languages = true } })
      local before = M.SkillStates()
      for i = 1, 5 do PM.Collect() end
      H.deepEq(M.SkillStates(), before)
   end)

   H.test("the skills window is expanded again by the USER between two reads: states are re-read each time", function()
      local PM, M = F.boot(H, { learned = { "mining" }, collapsed = { Professions = true } })
      PM.Collect()
      ExpandSkillHeader(0)                 -- the user pressed 'expand all'
      local after = M.SkillStates()
      PM.Collect()
      H.deepEq(M.SkillStates(), after, "left as the user left it")
      CollapseSkillHeader(0)
      PM.Collect()
      for _, expanded in pairs(M.SkillStates()) do H.eq(expanded, false) end
   end)

   H.test("an error while reading (another addon hooks GetSkillLineInfo) leaves the skills window as found", function()
      local PM, M = F.boot(H, { learned = { "mining" }, collapsed = { Professions = true } })
      local before = M.SkillStates()
      local orig = GetSkillLineInfo
      local failed = false
      rawset(_G, "GetSkillLineInfo", function(i)
         -- fail once, right after the addon expanded a header (the headers are open while it reads)
         if not failed and (M.calls.ExpandSkillHeader or 0) > 0 then
            failed = true
            error("hooked addon failed")
         end
         return orig(i)
      end)
      pcall(PM.Collect)
      rawset(_G, "GetSkillLineInfo", orig)
      H.deepEq(M.SkillStates(), before, "collapse states restored although the read failed")
      H.falsy(PM.scanning, "the scan flag does not stay set")
      H.eq(F.chatCount(M, "Error in ReadSkills"), 1, "the failure is reported once")
      H.allowGuardErrors()
      M.skillIndexErrors = {}
   end)

   -- ======================================================================
   H.section("No data at all")
   -- ======================================================================

   H.test("skill APIs missing entirely (nil): empty list, no error, no stuck scan flag", function()
      local PM = F.boot(H, { learned = { "alchemy" }, login = false })
      rawset(_G, "GetNumSkillLines", nil)
      rawset(_G, "GetSkillLineInfo", nil)
      M = H.mock
      M.Fire("PLAYER_LOGIN")
      F.open(PM)
      H.truthy(PM.UI.GetMenu().empty:IsShown())
      H.falsy(PM.scanning)
   end)

   H.test("spell APIs missing (nil): professions are listed without actions, passive", function()
      local PM = F.boot(H, { learned = { "alchemy" }, login = false })
      rawset(_G, "GetNumSpellTabs", nil)
      rawset(_G, "GetSpellInfo", nil)
      H.mock.Fire("PLAYER_LOGIN")
      F.open(PM)
      H.eq(#F.rows(PM), 1, "the profession is found by its static name")
      H.eq(F.rows(PM)[1].entry.action, nil)
      H.eq(F.rows(PM)[1].row:GetAttribute("type1"), nil)
   end)

   H.test("no ToggleCharacter / CloseTradeSkill / RegisterStateDriver in the client: the addon still starts and works", function()
      local PM, M = F.boot(H, { learned = { "skinning", "alchemy" }, login = false })
      rawset(_G, "ToggleCharacter", nil)
      rawset(_G, "CloseTradeSkill", nil)
      rawset(_G, "RegisterStateDriver", nil)
      M.Fire("PLAYER_LOGIN")
      H.truthy(PM.ready)
      F.open(PM)
      M.Click(PM.UI.rows[2], "RightButton")        -- would call ToggleCharacter
      H.falsy(F.isOpen(PM))
   end)

   -- ======================================================================
   H.section("Event floods and timing")
   -- ======================================================================

   H.test("1000 SPELLS_CHANGED events while the list is closed cost no skill reads", function()
      local PM, M = F.boot(H, { learned = F.ORDER, collapsed = { Professions = true } })
      for i = 1, 1000 do M.Fire("SPELLS_CHANGED") end
      H.eq(M.calls.GetSkillLineInfo, nil)
   end)

   H.test("100 learn/unlearn cycles with the list open keep the list consistent", function()
      local PM, M = F.boot(H, { learned = { "fishing" } })
      F.open(PM)
      for i = 1, 100 do
         M.LearnSkill("Cooking", i, 450, "Secondary Skills")
         M.LearnSpell("Cooking")
         H.eq(#F.rows(PM), 2)
         M.UnlearnSkill("Cooking")
         M.UnlearnSpell("Cooking")
         H.eq(#F.rows(PM), 1)
      end
   end)

   H.test("a real rank-up within 0.5 s after a scan with collapsed headers is not lost for good", function()
      -- The ignore window swallows events for 0.5 s after a scan that had to expand headers. A genuine rank-up inside the
      -- window must still show up at the latest when the list is opened again.
      local PM, M = F.boot(H, { learned = { mining = { 100, 450 } }, collapsed = { Professions = true } })
      F.open(PM)
      M.SetSkillRank("Mining", 101)          -- inside the window: ignored by the event handler
      PM.UI.Close()
      F.open(PM)
      local rows = F.rows(PM)
      H.eq(rows[2].rank, "101/450")
   end)

   H.test("an event inside the ignore window does not leave the list stale while it stays open (rank-up of the shown skill)", function()
      local PM, M = F.boot(H, { learned = { mining = { 100, 450 } }, collapsed = { Professions = true } })
      F.open(PM)
      M.SetSkillRank("Mining", 101)
      M.Advance(0.6)
      M.SetSkillRank("Mining", 102)          -- after the window: handled
      H.eq(F.rows(PM)[2].rank, "102/450")
   end)

   H.test("known limitation: a skill-up inside the ignore window is not shown until the list is opened again", function()
      -- Rechecking after the window would re-run the scan (Expand/CollapseSkillHeader), whose own echo events land in the
      -- next window: a feedback loop. A rank text that is 0.5 s late for a list that was just opened (and only with collapsed
      -- headers) is the cheaper side of that trade; opening the list again shows the new value (see the test above).
      local PM, M = F.boot(H, { learned = { mining = { 100, 450 } }, collapsed = { Professions = true } })
      F.open(PM)
      M.SetSkillRank("Mining", 101)
      M.Advance(1)
      H.eq(F.rows(PM)[2].rank, "100/450")
      PM.UI.Close()
      F.open(PM)
      H.eq(F.rows(PM)[2].rank, "101/450")
   end)

   H.test("time never goes backwards for the addon: no GetTime() misuse (mock throws on a backwards clock)", function()
      local PM, M = F.boot(H, { learned = { "mining" }, collapsed = { Professions = true } })
      F.open(PM)
      M.Advance(3)
      PM.UI.Close()
      F.open(PM)
      H.len(M.errors, 0)
   end)

   -- ======================================================================
   H.section("Reload")
   -- ======================================================================

   H.test("a full relog with the saved variables of the last session works and keeps every setting", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      M.Slash("/berufe sort alpha")
      M.Slash("/berufe headers off")
      M.Slash("/berufe ranks off")
      M.Slash("/berufe direction down")
      M.Slash("/berufe scale 1.3")
      M.Slash("/berufe unlock")
      local saved = M.SavedVariables()
      PM, M = F.boot(H, { learned = { "alchemy", "mining" }, saved = saved })
      H.deepEq({ PM.db.sort, PM.db.headers, PM.db.ranks, PM.db.direction, PM.db.scale, PM.db.locked },
         { "alpha", false, false, "down", 1.3, false })
      F.open(PM)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Mining", "Smelting" })
      H.eq(F.rows(PM)[1].rank, "")
      H.truthy(PM.UI.GetButton():IsMovable())
      H.eq(PM.UI.GetButton():GetScale(), 1.3)
   end)

   H.test("two sessions in a row: switching between standalone and ElvUI keeps the database usable", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe unlock")
      M.Drag(PM.UI.GetButton(), -50, 50)
      local saved = M.SavedVariables()
      PM, M = F.boot(H, { learned = { "alchemy" }, saved = saved, elvui = true })
      H.allowFrames({ "RightChatPanel" })
      H.eq(PM.Skin.elvui, true)
      local _, rel = PM.UI.GetButton():GetPoint(1)
      H.eq(rel, ProfessionMenuMover, "ElvUI mover decides, the old standalone position is ignored")
      saved = M.SavedVariables()
      PM = F.boot(H, { learned = { "alchemy" }, saved = saved })
      H.eq(PM.Skin.elvui, false)
      local p = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
   end)
end
