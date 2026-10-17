-- tests/test_boot.lua
-- ---------------------------------------------------------------------------
-- Start des Addons: TOC (Reihenfolge, Metadaten), ADDON_LOADED / PLAYER_LOGIN, keine Handler-Fehler, keine fremden
-- Globals oder Rahmennamen, Ereignisse, Zeilen genau einmal und nur ausserhalb des Kampfes, Ruhe im Leerlauf.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local F = require("fixtures")

   local EXPECTED_FILES = { "Locales.lua", "Data.lua", "Core.lua", "Skin.lua", "UI.lua", "Main.lua", "Options.lua" }

   -- ======================================================================
   H.section("TOC")
   -- ======================================================================

   H.test("the TOC loads the Lua files in dependency order and every file exists", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      H.deepEq(H.loaded, EXPECTED_FILES)
      H.deepEq(H.loadInfo.missing, {})
      H.deepEq(M.toc.files, EXPECTED_FILES)
   end)

   H.test("TOC metadata: Interface 30300, one SavedVariable, ElvUI optional, titles in both languages", function()
      F.boot(H, { learned = {} })
      local meta = M.toc.meta
      H.eq(meta.Interface, "30300")
      H.eq(meta.SavedVariables, "ProfessionMenuDB")
      H.eq(meta.OptionalDeps, "ElvUI")
      H.eq(meta.Title, "Profession Menu")
      H.eq(meta["Title-deDE"], "Berufe-Men\195\188")
      H.truthy(meta.Notes)
      H.truthy(meta["Notes-deDE"])
      H.eq(meta.Version, "1.0")
      H.eq(meta.SavedVariablesPerCharacter, nil)
      H.eq(meta.Dependencies, nil)
      H.eq(meta.Dependencies or meta.RequiredDeps, nil, "ElvUI must stay optional")
   end)

   H.test("GetAddOnMetadata (title in the client's language)", function()
      F.boot(H, { learned = {} })
      H.eq(GetAddOnMetadata("ProfessionMenu", "Title"), "Profession Menu")
      F.boot(H, { learned = {}, locale = "deDE" })
      H.eq(GetAddOnMetadata("ProfessionMenu", "Title"), "Berufe-Men\195\188")
   end)

   H.test("the addon table carries the version", function()
      local PM = F.boot(H, { learned = {} })
      H.eq(PM.version, "1.0")
      H.eq(PM.version, GetAddOnMetadata("ProfessionMenu", "Version"))
   end)

   -- ======================================================================
   H.section("Loading")
   -- ======================================================================

   H.test("loading the files builds data and code but no frames except the event frame", function()
      local PM = F.boot(H, { learned = { "alchemy" }, login = false })
      H.truthy(PM.frame)
      H.eq(PM.UI.GetButton(), nil)
      H.eq(PM.UI.GetMenu(), nil)
      H.eq(rawget(_G, "ProfessionMenuButton"), nil)
      H.falsy(PM.ready)
      H.eq(#PM.UI.rows, 0)
      H.truthy(PM.frame:IsEventRegistered("PLAYER_LOGIN"))
   end)

   H.test("the event frame registers exactly the seven events the addon uses (ADDON_LOADED is dropped after the first own load)", function()
      local logged = {}
      local methods = M.methods.Frame
      local orig = methods.RegisterEvent
      methods.RegisterEvent = function(self, ev)
         logged[#logged + 1] = ev
         return orig(self, ev)
      end
      local ok, err = pcall(F.boot, H, { learned = { "alchemy" }, login = false })
      methods.RegisterEvent = orig
      H.truthy(ok, tostring(err))
      table.sort(logged)
      H.deepEq(logged, { "ADDON_LOADED", "LEARNED_SPELL_IN_TAB", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED", "SPELLS_CHANGED" })
      local PM = M.addonTable
      H.falsy(PM.frame:IsEventRegistered("ADDON_LOADED"), "dropped after the first own load")
   end)

   H.test("no other frame listens to events (button, list and rows are event-free)", function()
      local PM = F.boot(H, { learned = { "alchemy", "mining" } })
      for _, f in ipairs(M.frames) do
         local n = f.__name
         local foreign = n and not n:match("^ProfessionMenu")
         if f ~= PM.frame and not foreign and f.__events and next(f.__events) then
            H.fail("frame " .. tostring(f.__name) .. " registered events")
         end
      end
   end)

   -- ======================================================================
   H.section("Login")
   -- ======================================================================

   H.test("ADDON_LOADED then PLAYER_LOGIN: ready, silent, no handler errors, no swallowed errors", function()
      local PM = F.boot(H, { learned = F.ORDER })
      H.truthy(PM.ready)
      H.len(M.errors, 0)
      H.len(M.messages, 0)
      H.eq(PM.startAfterCombat, nil)
      H.falsy(PM.scanning)
   end)

   H.test("login builds button, list and 24 rows exactly once", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      local rows, buttons, lists = 0, 0, 0
      for _, f in ipairs(M.frames) do
         local n = f.__name
         if n then
            if n:match("^ProfessionMenuRow%d+$") then rows = rows + 1 end
            if n == "ProfessionMenuButton" then buttons = buttons + 1 end
            if n == "ProfessionMenuList" then lists = lists + 1 end
         end
      end
      H.eq(rows, 24)
      H.eq(buttons, 1)
      H.eq(lists, 1)
      -- a repeated PLAYER_LOGIN builds nothing new
      local count = #M.frames
      M.Fire("PLAYER_LOGIN")
      H.eq(#M.frames, count)
   end)

   H.test("the list is created hidden; the button is shown", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      H.falsy(PM.UI.GetMenu():IsShown())
      H.truthy(PM.UI.GetButton():IsShown())
      H.truthy(PM.UI.GetButton():IsVisible())
      for _, row in ipairs(PM.UI.rows) do H.falsy(row:IsShown()) end
      for _, h in ipairs(PM.UI.headers) do H.falsy(h.text:IsShown()) end
   end)

   H.test("the first rebuild happens at the first open, not at login (no work for players who never click)", function()
      local PM, M2 = F.boot(H, { learned = { "alchemy" }, login = false })
      local n = 0
      local orig = PM.UI.Rebuild
      PM.UI.Rebuild = function(...) n = n + 1 return orig(...) end
      M.Fire("PLAYER_LOGIN")
      H.eq(n, 0)
      PM.UI.Open()
      H.eq(n, 1)
   end)

   H.test("skills are not read at login at all (no GetSkillLineInfo call before the first open)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, collapsed = { Professions = true } })
      H.eq(M.calls.GetSkillLineInfo, nil)
      H.eq(M.calls.ExpandSkillHeader, nil)
   end)

   H.test("idle: nothing runs every frame (no OnUpdate on any visible frame)", function()
      local PM = F.boot(H, { learned = F.ORDER })
      H.len(M.UpdateFrames(), 0)
      M.Advance(5)
      H.len(M.UpdateFrames(), 0)
   end)

   H.test("a long idle time with SPELLS_CHANGED / SKILL_LINES_CHANGED spam does not scan while the list is closed", function()
      local PM = F.boot(H, { learned = F.ORDER, collapsed = { Professions = true } })
      for i = 1, 50 do
         M.Fire("SPELLS_CHANGED")
         M.Fire("SKILL_LINES_CHANGED")
         M.Fire("LEARNED_SPELL_IN_TAB", 1)
      end
      M.Advance(2)
      H.eq(M.calls.GetSkillLineInfo, nil, "no reads at all")
   end)

   -- ======================================================================
   H.section("Names and globals")
   -- ======================================================================

   H.test("no stray globals: only ProfessionMenuDB and SLASH_PROFESSIONMENU1/2 are created", function()
      F.boot(H, { learned = F.ORDER })
      H.deepEq(M.StrayGlobals(), {})
      local names = {}
      for name in pairs(M.globalWrites) do names[#names + 1] = name end
      table.sort(names)
      H.deepEq(names, { "SLASH_PROFESSIONMENU1", "SLASH_PROFESSIONMENU2" })
      H.eq(type(rawget(_G, "ProfessionMenuDB")), "table")
   end)

   H.test("the only SavedVariable is ProfessionMenuDB and it survives M.SavedVariables()", function()
      F.boot(H, { learned = { "alchemy" } })
      local saved = M.SavedVariables()
      local keys = {}
      for k in pairs(saved) do keys[#keys + 1] = k end
      H.deepEq(keys, { "ProfessionMenuDB" })
   end)

   H.test("all named frames start with 'ProfessionMenu'", function()
      F.boot(H, { learned = F.ORDER })
      H.deepEq(M.StrayFrameNames(), {})
   end)

   H.test("the addon never reads an undefined global (no API missing in the client)", function()
      local PM = F.boot(H, { learned = F.ORDER })
      PM.UI.Open()
      PM.UI.Close()
      M.Slash("/berufe list")
      M.Slash("/berufe sort alpha")
      M.Slash("/berufe bogus")
      local misses = {}
      for _, m in ipairs(M.GlobalMisses()) do misses[#misses + 1] = m.name .. " @ " .. tostring(m.where) end
      H.deepEq(misses, {})
   end)

   H.test("no implicit handler globals (this, event, arg1) are read", function()
      F.boot(H, { learned = F.ORDER })
      H.deepEq(M.ImplicitGlobalReads(), {})
   end)

   H.test("the addon never touches the shared Blizzard tables beyond UISpecialFrames and SlashCmdList", function()
      F.boot(H, { learned = { "alchemy" } })
      local keys = {}
      for k in pairs(SlashCmdList) do keys[#keys + 1] = k end
      H.deepEq(keys, { "PROFESSIONMENU" })
      H.deepEq(UISpecialFrames, { "ProfessionMenuEscProxy" })
   end)

   H.test("the addon works when GetNumSkillLines / GetSpellInfo style APIs are partly missing (nil-safe Core)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, login = false })
      local saved = { GetNumSkillLines = GetNumSkillLines, GetSkillLineInfo = GetSkillLineInfo }
      rawset(_G, "GetNumSkillLines", nil)
      local skills, order = PM.ReadSkills()
      H.deepEq(order, {})
      rawset(_G, "GetNumSkillLines", saved.GetNumSkillLines)
      rawset(_G, "GetNumSpellTabs", nil)
      H.deepEq(PM.ReadSpellbook(), {})
   end)
end
