-- tests/test_mock_selftest.lua
-- ---------------------------------------------------------------------------
-- Selbsttest der Erweiterungen der Attrappe (tests/mock_wow.lua, Abschnitt "ProfessionMenu-Erweiterungen").
-- Wenn die Attrappe falsch rechnet, sind alle Addon-Tests wertlos: deshalb hier die Semantik von
--   * Fertigkeiten (Aufzaehlung, Auf-/Zuklappen, Ereignisse in den drei Modi)
--   * Zauberbuch (Reiter/Offsets, lokalisierte Namen, GetSpellInfo nur fuer bekannte Zauber)
--   * sicheren Knoepfen (Attribute, Klick, Reihenfolge Pre/On/PostClick, M.casts)
--   * Combat Lockdown (geschuetzte Rahmen, Ankerfamilie, Erstellen im Kampf)
--   * Strenge (SetSize, SetShown, SetColorTexture, Texture:SetRotation, C_Timer, unbekannte Ereignisse)
--   * Hilfen (ElvUI-Attrappe, M.After, M.Hover, UIErrorsFrame, ToggleCharacter)
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local function fresh(opts)
      H.install(opts)
      return M
   end

   local function skillset(collapsedProf)
      return {
         { name = "Class Skills", lines = { { "Defense", 400, 400 } } },
         { name = "Professions", collapsed = collapsedProf, lines = { { "Mining", 300, 450 }, { "Herbalism", 75, 75 } } },
         { name = "Secondary Skills", lines = { { "Fishing", 1, 75 } } },
      }
   end

   -- ======================================================================
   H.section("Skills window")
   -- ======================================================================

   H.test("GetSkillLineInfo: return values of headers and lines", function()
      fresh()
      M.SetSkills(skillset(false))
      H.eq(GetNumSkillLines(), 7)
      local name, header, expanded, rank, temp, mod, max = GetSkillLineInfo(3)
      H.eq(name, "Professions")
      H.eq(header, 1)
      H.eq(expanded, 1)
      H.eq(rank, 0)
      name, header, expanded, rank, temp, mod, max = GetSkillLineInfo(4)
      H.eq(name, "Mining")
      H.eq(header, nil)
      H.eq(rank, 300)
      H.eq(max, 450)
      H.eq(temp, 0)
      H.eq(mod, 0)
      H.eq(GetSkillLineInfo(99), nil)
      H.len(M.skillIndexErrors, 1, "out-of-range access is recorded")
      M.skillIndexErrors = {}
   end)

   H.test("collapsed headers hide their lines from the enumeration", function()
      fresh()
      M.SetSkills(skillset(true))
      H.eq(GetNumSkillLines(), 5)
      H.deepEq(M.SkillNames(), { "Class Skills", "Defense", "Professions", "Secondary Skills", "Fishing" })
      local _, header, expanded = GetSkillLineInfo(3)
      H.eq(header, 1)
      H.eq(expanded, nil, "collapsed header reports isExpanded = nil")
   end)

   H.test("ExpandSkillHeader/CollapseSkillHeader change the enumeration and fire SKILL_LINES_CHANGED (sync)", function()
      fresh()
      M.SetSkills(skillset(true))
      local events = 0
      local f = CreateFrame("Frame")
      f:RegisterEvent("SKILL_LINES_CHANGED")
      f:SetScript("OnEvent", function() events = events + 1 end)
      ExpandSkillHeader(3)
      H.eq(events, 1, "event fired synchronously")
      H.eq(GetNumSkillLines(), 7)
      H.deepEq(M.SkillStates(), { ["Class Skills"] = true, Professions = true, ["Secondary Skills"] = true })
      ExpandSkillHeader(3)
      H.eq(events, 1, "no change -> no event")
      CollapseSkillHeader(3)
      H.eq(events, 2)
      H.eq(GetNumSkillLines(), 5)
      ExpandSkillHeader(0)
      CollapseSkillHeader(0)
      H.deepEq(M.SkillStates(), { ["Class Skills"] = false, Professions = false, ["Secondary Skills"] = false })
      H.eq(GetNumSkillLines(), 3)
      ExpandSkillHeader(0)
      H.eq(GetNumSkillLines(), 7)
   end)

   H.test("Expand on a line that is not a header does nothing", function()
      fresh()
      M.SetSkills(skillset(false))
      local events = 0
      local f = CreateFrame("Frame")
      f:RegisterEvent("SKILL_LINES_CHANGED")
      f:SetScript("OnEvent", function() events = events + 1 end)
      ExpandSkillHeader(4)       -- "Mining" is a line
      CollapseSkillHeader(4)
      H.eq(events, 0)
      H.eq(GetNumSkillLines(), 7)
   end)

   H.test("deferred event mode: the event arrives with the next time step, none mode: never", function()
      fresh({ world = { skillEventMode = "deferred" } })
      M.SetSkills(skillset(true))
      local events = 0
      local f = CreateFrame("Frame")
      f:RegisterEvent("SKILL_LINES_CHANGED")
      f:SetScript("OnEvent", function() events = events + 1 end)
      ExpandSkillHeader(3)
      H.eq(events, 0)
      M.Advance(0.05)
      H.eq(events, 1)
      M.Advance(0.5)
      H.eq(events, 1)
      M.world.skillEventMode = "none"
      CollapseSkillHeader(3)
      M.Advance(0.5)
      H.eq(events, 1)
   end)

   H.test("LearnSkill / SetSkillRank / UnlearnSkill fire the event and change the lines", function()
      fresh()
      M.SetSkills(skillset(false))
      local events = 0
      local f = CreateFrame("Frame")
      f:RegisterEvent("SKILL_LINES_CHANGED")
      f:SetScript("OnEvent", function() events = events + 1 end)
      M.LearnSkill("Cooking", 1, 75, "Secondary Skills")
      H.eq(events, 1)
      H.truthy(M.SkillNames()[#M.SkillNames()] == "Cooking")
      M.SetSkillRank("Cooking", 50)
      local _, _, _, rank = GetSkillLineInfo(GetNumSkillLines())
      H.eq(rank, 50)
      M.UnlearnSkill("Cooking")
      H.eq(events, 3)
      H.eq(GetNumSkillLines(), 7)
   end)

   -- ======================================================================
   H.section("Spell book")
   -- ======================================================================

   H.test("spell tabs: offsets, counts and GetSpellName over all tabs", function()
      fresh()
      M.SetSpellbook({
         { name = "General", spells = { "Attack", "Fishing" } },
         { name = "Arms", spells = {} },
         { name = "Crafts", spells = { 2018, "Mining", "Smelting" } },
      })
      H.eq(GetNumSpellTabs(), 3)
      local n, tex, off, cnt = GetSpellTabInfo(1)
      H.eq(n, "General"); H.eq(off, 0); H.eq(cnt, 2)
      n, tex, off, cnt = GetSpellTabInfo(2)
      H.eq(off, 2); H.eq(cnt, 0)
      n, tex, off, cnt = GetSpellTabInfo(3)
      H.eq(off, 2); H.eq(cnt, 3)
      H.eq(GetSpellTabInfo(4), nil)
      H.eq(GetSpellName(1, "spell"), "Attack")
      H.eq(GetSpellName(3, "spell"), "Blacksmithing")
      H.eq(GetSpellName(5, "spell"), "Smelting")
      H.eq(GetSpellName(6, "spell"), nil)
      H.eq(GetSpellName(1, "pet"), nil)
      H.throws(function() GetSpellName(1) end, "bookType")
      H.eq(BOOKTYPE_SPELL, "spell")
   end)

   H.test("spell names are localized (enUS, deDE) and GetSpellInfo(name) only knows spellbook spells", function()
      fresh({ world = { locale = "deDE" } })
      M.SetSpellbook({ "Mining", "Herb Gathering" })
      H.eq((GetSpellInfo(2575)), "Bergbau")
      H.eq((GetSpellInfo(2366)), "Kr\195\164utersammeln")
      H.eq((GetSpellInfo(2656)), "Verh\195\188ttung", "by id always works")
      H.eq(GetSpellInfo("Bergbau"), "Bergbau", "by name: in the book")
      H.eq(GetSpellInfo("Verh\195\188ttung"), nil, "by name: not in the book -> nil")
      H.eq(GetSpellInfo("Mining"), nil, "english name in a deDE client is unknown")
      H.eq(GetSpellInfo(999999), nil)
      H.eq(GetSpellName(1, "spell"), "Bergbau")
      fresh({ world = { locale = "enUS" } })
      H.eq((GetSpellInfo(2656)), "Smelting")
      M.SetSpellbook({ 2656 })
      H.eq(GetSpellInfo("smelting"), "Smelting", "case-insensitive")
   end)

   H.test("all 17 profession spell ids have enUS and deDE names", function()
      local expectEn = { [2018] = "Blacksmithing", [2108] = "Leatherworking", [3908] = "Tailoring", [4036] = "Engineering",
                         [2259] = "Alchemy", [45357] = "Inscription", [25229] = "Jewelcrafting", [7411] = "Enchanting",
                         [2575] = "Mining", [2366] = "Herb Gathering", [8613] = "Skinning", [2550] = "Cooking",
                         [3273] = "First Aid", [7620] = "Fishing", [2656] = "Smelting", [2383] = "Find Herbs",
                         [2580] = "Find Minerals" }
      local expectDe = { [2018] = "Schmiedekunst", [2108] = "Lederverarbeitung", [3908] = "Schneiderei",
                         [4036] = "Ingenieurskunst", [2259] = "Alchemie", [45357] = "Inschriftenkunde",
                         [25229] = "Juwelenschleifen", [7411] = "Verzauberkunst", [2575] = "Bergbau",
                         [2366] = "Kr\195\164utersammeln", [8613] = "K\195\188rschnerei", [2550] = "Kochkunst",
                         [3273] = "Erste Hilfe", [7620] = "Angeln", [2656] = "Verh\195\188ttung",
                         [2383] = "Kr\195\164utersuche", [2580] = "Mineraliensuche" }
      fresh({ world = { locale = "enUS" } })
      for id, name in pairs(expectEn) do H.eq((GetSpellInfo(id)), name, "enUS " .. id) end
      fresh({ world = { locale = "deDE" } })
      for id, name in pairs(expectDe) do H.eq((GetSpellInfo(id)), name, "deDE " .. id) end
   end)

   H.test("GetSpellTexture: by name only when known, by id always, by index with book type", function()
      fresh()
      M.SetSpellbook({ "Fishing" })
      H.truthy(GetSpellTexture("Fishing"))
      H.eq(GetSpellTexture("Mining"), nil)
      H.truthy(GetSpellTexture(2575), "id")
      H.eq(GetSpellTexture(1, "spell"), GetSpellTexture("Fishing"))
      H.eq(GetSpellTexture(2, "spell"), nil)
      M.spellIcons[7620] = "Interface\\Icons\\Custom"
      H.eq(GetSpellTexture("Fishing"), "Interface\\Icons\\Custom")
   end)

   H.test("LearnSpell fires LEARNED_SPELL_IN_TAB and SPELLS_CHANGED, UnlearnSpell fires SPELLS_CHANGED", function()
      fresh()
      M.SetSpellbook({ "Attack" })
      local log = {}
      local f = CreateFrame("Frame")
      f:RegisterEvent("SPELLS_CHANGED")
      f:RegisterEvent("LEARNED_SPELL_IN_TAB")
      f:SetScript("OnEvent", function(_, event, a1) log[#log + 1] = event .. ":" .. tostring(a1) end)
      M.LearnSpell("Fishing")
      H.deepEq(log, { "LEARNED_SPELL_IN_TAB:1", "SPELLS_CHANGED:nil" })
      H.truthy(M.KnowsSpell("Fishing"))
      M.UnlearnSpell("Fishing")
      H.falsy(M.KnowsSpell("Fishing"))
      H.eq(log[3], "SPELLS_CHANGED:nil")
   end)

   -- ======================================================================
   H.section("Secure buttons")
   -- ======================================================================

   H.test("SecureActionButtonTemplate: type1/spell1 cast on left click only; order Pre/On/Post", function()
      fresh()
      M.SetSpellbook({ "Mining", "Smelting" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Smelting")
      local order = {}
      b:SetScript("PreClick", function() order[#order + 1] = "pre:" .. #M.casts end)
      b:SetScript("PostClick", function(_, btn) order[#order + 1] = "post:" .. #M.casts .. ":" .. btn end)
      M.Click(b)
      H.deepEq(M.casts, { "Smelting" })
      H.deepEq(order, { "pre:0", "post:1:LeftButton" }, "the cast happens between PreClick and PostClick")
      order = {}
      M.Click(b, "RightButton")
      H.deepEq(M.casts, { "Smelting" }, "type2 is unset: right click does not cast")
      H.deepEq(order, { "pre:1", "post:1:RightButton" })
      H.eq(b:GetAttribute("type1"), "spell")
      H.eq(b:GetAttribute("", "type", "1"), "spell")
      H.eq(b:GetAttribute("", "type", "2"), nil)
      H.eq(M.castLog[1].button, "LeftButton")
   end)

   H.test("secure click with modifiers uses prefixed attributes", function()
      fresh()
      M.SetSpellbook({ "Mining", "Smelting" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Mining")
      b:SetAttribute("shift-type1", "spell")
      b:SetAttribute("shift-spell1", "Smelting")
      M.Click(b, "LeftButton", { shift = true })
      M.Click(b)
      H.deepEq(M.casts, { "Smelting", "Mining" })
      -- a plain type1 does NOT match while a modifier is held (that needs "*type1"), like the client
      local c = CreateFrame("Button", "ProfessionMenuTestSecure2", UIParent, "SecureActionButtonTemplate")
      c:SetWidth(50)
      c:SetHeight(20)
      c:SetAttribute("type1", "spell")
      c:SetAttribute("spell1", "Mining")
      M.casts = {}
      M.Click(c, "LeftButton", { ctrl = true })
      H.deepEq(M.casts, {})
      c:SetAttribute("*type1", "spell")
      c:SetAttribute("*spell1", "Mining")
      M.Click(c, "LeftButton", { ctrl = true })
      H.deepEq(M.casts, { "Mining" })
   end)

   H.test("casting a spell that is not in the book is recorded as a failure, not as a cast", function()
      fresh()
      M.SetSpellbook({ "Mining" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Smelting")
      M.Click(b)
      H.deepEq(M.casts, {})
      H.deepEq(M.castFailures, { "Smelting" })
   end)

   H.test("type spell without a spell attribute is an error in the click handler", function()
      fresh()
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      M.Click(b)
      H.len(M.errors, 1)
      M.ClearErrors()
   end)

   H.test("replacing OnClick of a secure button disables the secure action (like the client)", function()
      fresh()
      M.SetSpellbook({ "Mining" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Mining")
      b:SetScript("OnClick", function() end)
      M.Click(b)
      H.deepEq(M.casts, {})
   end)

   -- ======================================================================
   H.section("Combat lockdown")
   -- ======================================================================

   local function secureRow()
      local menu = CreateFrame("Frame", "ProfessionMenuTestMenu", UIParent)
      menu:SetWidth(100)
      menu:SetHeight(100)
      menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      local row = CreateFrame("Button", "ProfessionMenuTestRow", menu, "SecureActionButtonTemplate")
      row:SetWidth(80)
      row:SetHeight(20)
      row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
      return menu, row
   end

   H.test("in combat the protected methods of a secure frame throw ADDON_ACTION_BLOCKED", function()
      fresh()
      local menu, row = secureRow()
      M.world.combat = true
      for _, call in ipairs({
         { "SetPoint", function() row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, 1) end },
         { "ClearAllPoints", function() row:ClearAllPoints() end },
         { "Show", function() row:Show() end },
         { "Hide", function() row:Hide() end },
         { "SetAttribute", function() row:SetAttribute("type1", "spell") end },
         { "SetWidth", function() row:SetWidth(10) end },
         { "SetHeight", function() row:SetHeight(10) end },
         { "SetScale", function() row:SetScale(2) end },
         { "SetParent", function() row:SetParent(UIParent) end },
      }) do
         local msg = H.throws(call[2], "ADDON_ACTION_BLOCKED")
         H.contains(tostring(msg), call[1], "message names " .. call[1])
      end
      -- harmless calls stay allowed
      row:SetAlpha(0.5)
      H.eq(#M.blocked, 9)
      M.blocked = {}
   end)

   H.test("in combat the anchor family of a secure frame is protected for geometry, Show/Hide stay allowed", function()
      fresh()
      local menu, row = secureRow()
      M.world.combat = true
      H.throws(function() menu:SetPoint("CENTER", UIParent, "CENTER", 5, 5) end, "ADDON_ACTION_BLOCKED")
      H.throws(function() menu:SetWidth(50) end, "ADDON_ACTION_BLOCKED")
      H.throws(function() UIParent:SetScale(1.5) end, "ADDON_ACTION_BLOCKED")
      menu:Hide()
      menu:Show()
      H.falsy(row:IsVisible() == nil and false, "hiding the unprotected parent works")
      local protected, explicit = M.IsProtected(menu)
      H.eq(protected, true)
      H.eq(explicit, false)
      M.blocked = {}
   end)

   H.test("regions of a secure frame are protected as well; unrelated frames are not", function()
      fresh()
      local _, row = secureRow()
      local fs = row:CreateFontString(nil, "OVERLAY")
      local other = CreateFrame("Frame", "ProfessionMenuTestOther", UIParent)
      other:SetWidth(10)
      other:SetHeight(10)
      M.world.combat = true
      H.throws(function() fs:SetPoint("LEFT", row, "LEFT") end, "ADDON_ACTION_BLOCKED")
      H.throws(function() fs:Hide() end, "ADDON_ACTION_BLOCKED")
      other:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      other:Hide()
      other:Show()
      M.blocked = {}
   end)

   H.test("outside of combat everything is allowed; the anchor family can be switched off", function()
      fresh()
      local menu, row = secureRow()
      row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, 3)
      row:Hide()
      row:Show()
      M.world.combat = true
      M.world.anchorFamily = false
      menu:SetPoint("CENTER", UIParent, "CENTER", 5, 5)
      H.throws(function() row:Hide() end, "ADDON_ACTION_BLOCKED")
      M.blocked = {}
   end)

   H.test("creating a secure frame in combat is blocked, a plain frame is fine", function()
      fresh()
      M.world.combat = true
      CreateFrame("Frame", "ProfessionMenuTestPlain", UIParent)
      H.throws(function()
         CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      end, "ADDON_ACTION_BLOCKED")
      M.blocked = {}
   end)

   -- ======================================================================
   H.section("State driver and secure handler frames")
   -- ======================================================================

   H.test("SecureCmdOptionParse: combat / nocombat clauses, default clause, unsupported conditions fail loudly", function()
      fresh()
      H.eq(SecureCmdOptionParse("[combat] 1; 0"), "0")
      M.world.combat = true
      H.eq(SecureCmdOptionParse("[combat] 1; 0"), "1")
      H.eq(SecureCmdOptionParse("[nocombat] a; [combat] b"), "b")
      H.eq(SecureCmdOptionParse("[nocombat] a"), nil)
      H.eq(SecureCmdOptionParse("[nocombat,combat] a; z"), "z", "conditions inside one bracket are ANDed")
      H.eq(SecureCmdOptionParse("[nocombat][combat] y; z"), "y", "separate brackets are ORed")
      H.throws(function() SecureCmdOptionParse("[mounted] a; b") end, "not supported")
   end)

   H.test("RegisterStateDriver sets state-<id> at once; the snippet _onstate-<id> runs with newstate and can Hide the frame", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestSH", UIParent, "SecureHandlerStateTemplate")
      f:SetWidth(10)
      f:SetHeight(10)
      f:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
      RegisterStateDriver(f, "combat", "[combat] 1; 0")
      H.eq(f:GetAttribute("state-combat"), "0")
      H.truthy(f:IsShown())
      M.world.combat = true
      M.Advance(0.1)
      H.truthy(f:IsShown(), "the driver polls every 0.2 s")
      M.Advance(0.15)
      H.eq(f:GetAttribute("state-combat"), "1")
      H.falsy(f:IsShown(), "hidden by the snippet in combat (secure code may hide protected frames)")
      H.len(M.blocked, 0)
      H.truthy(select(2, M.IsProtected(f)))
   end)

   H.test("a snippet that calls something outside the restricted environment errors (reported to the error handler)", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestSH", UIParent, "SecureHandlerStateTemplate")
      f:SetAttribute("_onstate-x", [[ self:SetPoint("CENTER") ]])
      f:SetAttribute("state-x", "1")
      H.len(M.errors, 1)
      M.ClearErrors()
   end)

   H.test("FrameXML helpers run in secure context: ShowUIPanel/HideUIPanel/CloseSpecialWindows may touch protected frames in combat", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestSH", UIParent, "SecureHandlerStateTemplate")
      f:Hide()
      tinsert(UISpecialFrames, "ProfessionMenuTestSH")
      M.world.combat = true
      ShowUIPanel(f)
      H.truthy(f:IsShown())
      H.truthy(M.Escape())
      H.falsy(f:IsShown())
      H.throws(function() f:Show() end, "ADDON_ACTION_BLOCKED")
      M.blocked = {}
   end)

   H.test("M.EnterCombat / M.LeaveCombat order the lockdown flag and the events", function()
      fresh()
      local log = {}
      local f = CreateFrame("Frame")
      f:RegisterEvent("PLAYER_REGEN_DISABLED")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
      f:SetScript("OnEvent", function(_, event) log[#log + 1] = event .. ":" .. tostring(InCombatLockdown()) end)
      M.EnterCombat()
      M.LeaveCombat()
      M.EnterCombat({ eventFirst = true })
      M.LeaveCombat()
      H.deepEq(log, { "PLAYER_REGEN_DISABLED:1", "PLAYER_REGEN_ENABLED:nil", "PLAYER_REGEN_DISABLED:nil",
                      "PLAYER_REGEN_ENABLED:nil" })
   end)

   H.test("profession windows: a cast opens, a second cast of the same spell closes, CloseTradeSkill closes; tracking is recorded", function()
      fresh()
      M.SetSpellbook({ "Alchemy", "Smelting", "Find Minerals", "Fishing" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Alchemy")
      M.Click(b)
      H.eq(M.tradeSkill.open, "Alchemy")
      H.truthy(TradeSkillFrame:IsShown())
      M.Click(b)
      H.eq(M.tradeSkill.open, nil)
      H.falsy(TradeSkillFrame:IsShown())
      M.Click(b)
      CloseTradeSkill()
      H.eq(M.tradeSkill.open, nil)
      H.eq(M.tradeSkill.closes, 1)
      b:SetAttribute("spell1", "Find Minerals")
      M.Click(b)
      H.eq(M.tracking, "Find Minerals")
      M.Click(b)
      H.eq(M.tracking, "Find Minerals", "still active (what a second cast does in the client is not modelled)")
   end)

   H.test("a profession window cannot be opened in combat (recorded as a cast failure)", function()
      fresh()
      M.SetSpellbook({ "Alchemy" })
      local b = CreateFrame("Button", "ProfessionMenuTestSecure", UIParent, "SecureActionButtonTemplate")
      b:SetWidth(50)
      b:SetHeight(20)
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell1", "Alchemy")
      M.world.combat = true
      M.Click(b)
      H.deepEq(M.castFailures, { "Alchemy" })
      H.deepEq(M.casts, {})
      M.blocked = {}
   end)

   -- ======================================================================
   H.section("Strict API")
   -- ======================================================================

   H.test("methods that do not exist in 3.3.5a throw 'API not in 3.3.5a'", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      local t = f:CreateTexture(nil, "ARTWORK")
      local fs = f:CreateFontString(nil, "OVERLAY")
      H.throws(function() f:SetSize(1, 1) end, "API not in 3.3.5a: Frame:SetSize")
      H.throws(function() f:SetShown(true) end, "API not in 3.3.5a: Frame:SetShown")
      H.throws(function() t:SetColorTexture(1, 1, 1) end, "API not in 3.3.5a: Texture:SetColorTexture")
      H.throws(function() t:SetRotation(1) end, "API not in 3.3.5a: Texture:SetRotation")
      H.throws(function() fs:SetMaxLines(1) end, "API not in 3.3.5a")
   end)

   H.test("retail globals read through the addon environment are poisoned (C_Timer, Mixin, GetProfessions)", function()
      fresh()
      -- the poison lives in the environment of addon chunks: load a probe file the way the addon is loaded
      local path = os.tmpname()
      local dir, file = path:match("^(.*)/([^/]*)$")
      local f = io.open(path, "w")
      f:write("local _, PM = ...\n"
         .. "PM.a = function() return C_Timer.After(1, print) end\n"
         .. "PM.b = function() return Mixin({}) end\n"
         .. "PM.c = function() return GetProfessions() end\n"
         .. "PM.d = function() return C_Map end\n")
      f:close()
      local old = M.root
      M.root = dir
      local ok, err = pcall(M.LoadFiles, { file })
      M.root = old
      os.remove(path)
      H.truthy(ok, tostring(err))
      local PM = M.addonTable
      H.throws(PM.a, "API not in 3.3.5a: C_Timer.After")
      H.throws(PM.b, "API not in 3.3.5a: Mixin")
      H.throws(PM.c, "API not in 3.3.5a: GetProfessions")
      H.truthy(PM.d(), "merely reading the namespace is possible; using it is not")
      H.eq(rawget(_G, "C_Timer"), nil)
   end)

   H.test("RegisterEvent: unknown or retail event names throw", function()
      fresh()
      local f = CreateFrame("Frame")
      f:RegisterEvent("SKILL_LINES_CHANGED")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
      H.throws(function() f:RegisterEvent("PLAYER_REGEN_ENABLE") end, "unknown event")
      H.throws(function() f:RegisterEvent("GLOBAL_MOUSE_DOWN") end, "API not in 3.3.5a")
      H.throws(function() f:RegisterEvent("GET_ITEM_INFO_RECEIVED") end, "API not in 3.3.5a")
      M.AllowEvent("MY_EVENT")
      f:RegisterEvent("MY_EVENT")
   end)

   H.test("UIErrorsFrame:AddMessage is recorded in M.uiErrors, not in the chat", function()
      fresh()
      UIErrorsFrame:AddMessage("Nope", 1, 0.3, 0.3)
      H.len(M.uiErrors, 1)
      H.eq(M.uiErrors[1].text, "Nope")
      H.eq(M.uiErrors[1].g, 0.3)
      H.len(M.messages, 0)
   end)

   H.test("ToggleCharacter records the tab, validates it and toggles CharacterFrame", function()
      fresh()
      ToggleCharacter("SkillFrame")
      H.deepEq(M.toggles, { "SkillFrame" })
      H.truthy(CharacterFrame:IsShown())
      ToggleCharacter("SkillFrame")
      H.falsy(CharacterFrame:IsShown())
      H.throws(function() ToggleCharacter("SkillsFrame") end, "unknown tab")
   end)

   H.test("M.After and M.Advance: timers run in order with the right game time", function()
      fresh()
      local log = {}
      M.After(0.2, function() log[#log + 1] = "b" end)
      M.After(0.1, function() log[#log + 1] = "a" end)
      M.Advance(0.05)
      H.deepEq(log, {})
      M.Advance(0.1)
      H.deepEq(log, { "a" })
      M.Advance(0.2)
      H.deepEq(log, { "a", "b" })
   end)

   H.test("M.Hover / M.SetMouseDown drive MouseIsOver and IsMouseButtonDown", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      f:EnableMouse(true)
      f:SetWidth(10)
      f:SetHeight(10)
      H.falsy(MouseIsOver(f))
      M.Hover(f)
      H.truthy(MouseIsOver(f))
      M.Hover(nil)
      H.falsy(MouseIsOver(f))
      H.falsy(IsMouseButtonDown("LeftButton"))
      M.SetMouseDown("LeftButton", true)
      H.truthy(IsMouseButtonDown("LeftButton"))
      M.SetMouseDown("LeftButton", false)
      H.falsy(IsMouseButtonDown("LeftButton"))
   end)

   H.test("a drag swallows the click (the client sends no OnClick after OnDragStart)", function()
      fresh()
      local b = CreateFrame("Button", "ProfessionMenuTestB", UIParent)
      b:SetWidth(20)
      b:SetHeight(20)
      b:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      b:SetMovable(true)
      b:RegisterForDrag("LeftButton")
      local clicks = 0
      b:SetScript("OnClick", function() clicks = clicks + 1 end)
      b:SetScript("OnDragStart", function(self) self:StartMoving() end)
      b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
      M.Drag(b, 10, 10)
      H.eq(clicks, 0)
      M.Click(b)
      H.eq(clicks, 1)
   end)

   H.test("asset check: extension-less texture paths resolve to .tga/.blp files inside the addon", function()
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      local t = f:CreateTexture(nil, "ARTWORK")
      t:SetTexture("Interface\\AddOns\\ProfessionMenu\\Media\\chevron")
      H.len(M.missingAssets, 0)
      t:SetTexture("Interface\\AddOns\\ProfessionMenu\\Media\\nothere")
      H.len(M.missingAssets, 1)
      H.allowMissingAssets()
   end)

   -- ======================================================================
   H.section("ElvUI fake")
   -- ======================================================================

   H.test("InstallElvUI: global ElvUI table, media, db, TexCoords, RightChatPanel, frame API", function()
      fresh({ elvui = true })
      local E = ElvUI[1]
      H.truthy(E.initialized)
      H.truthy(E.media.rgbvaluecolor)
      H.truthy(E.db.general)
      H.deepEq(E.TexCoords, { 0.08, 0.92, 0.08, 0.92 })
      H.truthy(RightChatPanel)
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      f:SetWidth(20)
      f:SetHeight(20)
      f:SetTemplate("Transparent")
      H.eq(f.template, "Transparent")
      local r, g, b, a = f:GetBackdropColor()
      H.near(a, 0.8, 1e-6)
      local fs = f:CreateFontString(nil, "OVERLAY")
      fs:FontTemplate(nil, 14, "OUTLINE")
      local path, size, flags = fs:GetFont()
      H.eq(path, E.media.normFont)
      H.eq(size, 14)
      H.eq(flags, "OUTLINE")
      f:Size(30, 10)
      H.eq(f:GetWidth(), 30)
      H.eq(f:GetHeight(), 10)
      H.allowFrames({ "RightChatPanel" })
   end)

   H.test("the ElvUI API is gone again after the next Install (non-ElvUI tests stay strict)", function()
      fresh({ elvui = true })
      fresh()
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      H.throws(function() f:SetTemplate("Default") end, "API not in 3.3.5a")
      H.eq(rawget(_G, "ElvUI"), nil)
      H.eq(rawget(_G, "RightChatPanel"), nil)
   end)

   H.test("ElvUI pending: db is empty, FontTemplate fails until E:Initialize; initAfter initializes by game time", function()
      fresh({ elvui = { initialized = false, initAfter = 3 } })
      local E = ElvUI[1]
      H.falsy(E.initialized)
      local f = CreateFrame("Frame", "ProfessionMenuTestF", UIParent)
      local fs = f:CreateFontString(nil, "OVERLAY")
      H.throws(function() fs:FontTemplate(nil, 12) end, "general")
      M.Advance(2.9)
      H.falsy(E.initialized)
      M.Advance(0.2)
      H.truthy(E.initialized)
      fs:FontTemplate(nil, 12)
      H.allowFrames({ "RightChatPanel" })
   end)

   H.test("CreateMover anchors the owner to the mover; ResetMovers matches by TEXT like the real ElvUI", function()
      fresh({ elvui = true })
      local E = ElvUI[1]
      local owner = CreateFrame("Frame", "ProfessionMenuTestOwner", UIParent)
      owner:SetWidth(40)
      owner:SetHeight(20)
      owner:SetPoint("BOTTOMRIGHT", RightChatPanel, "TOPRIGHT", 0, 4)
      E:CreateMover(owner, "ProfessionMenuTestMover", "Test mover", nil, nil, nil, "ALL,GENERAL")
      local mover = ProfessionMenuTestMover
      H.truthy(mover)
      local _, rel = owner:GetPoint(1)
      H.eq(rel, mover, "owner is anchored to the mover")
      H.truthy(E.movers.ProfessionMenuTestMover)
      -- move the mover
      mover:ClearAllPoints()
      mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      E:ResetMovers("ProfessionMenuTestMover")        -- the NAME matches nothing (ElvUI compares the text)
      local p1 = mover:GetPoint(1)
      H.eq(p1, "CENTER", "reset by name does nothing")
      E:ResetMovers("Test mover")
      p1 = mover:GetPoint(1)
      H.eq(p1, "BOTTOMRIGHT", "reset by text restores the default point")
      H.allowFrames({ "RightChatPanel" })
   end)
end
