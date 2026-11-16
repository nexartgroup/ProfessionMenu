-- Diag.lua
-- ---------------------------------------------------------------------------
-- /berufe diag: sammelt, was das Addon vom Spiel sieht (Version, vorhandene Funktionen, die gelesenen
-- Berufe samt Zaubern, die gebauten Eintraege, die Klick-Einstellungen), schreibt es in die SavedVariables
-- (ProfessionMenuDB.diag) und fasst das Wichtigste im Chat zusammen. Damit laesst sich auf dem echten
-- Client pruefen, was ohne Spiel nicht zu pruefen ist.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local tostring, type, pcall, ipairs, select = tostring, type, pcall, ipairs, select

local Diag = {}
PM.Diag = Diag

-- Funktionen und Tabellen, auf die das Addon baut ("Pfad" in _G)
local APIS = {
   "GetProfessions", "GetProfessionInfo", "GetBuildInfo", "GetPhysicalScreenSize", "IsMouseButtonDown",
   "InCombatLockdown", "RegisterStateDriver", "hooksecurefunc", "CreateFrame", "ToggleProfessionsBook",
   "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.IsSpellKnown", "C_SpellBook.CastSpellBookItem",
   "C_Spell.GetSpellName", "C_Spell.GetSpellTexture",
   "C_TradeSkillUI.CanTradeSkillShowCraftingUI", "C_TradeSkillUI.GetBaseProfessionInfo",
   "C_TradeSkillUI.OpenTradeSkill", "C_TradeSkillUI.CloseTradeSkill",
   "Enum.SpellBookSpellBank", "Enum.SpellBookItemType", "BackdropTemplateMixin", "PixelUtil",
   "Settings.RegisterVerticalLayoutCategory", "Settings.RegisterAddOnSetting", "Settings.CreateCheckbox",
   "Settings.CreateDropdown", "Settings.CreateSlider", "Settings.OpenToCategory",
   "SecureActionButton_OnClick", "SecureActionButton_ShouldUseOnKeyDown", "UISpecialFrames",
   "GameTooltip", "UIErrorsFrame", "ProfessionsFrame", "TRADE_SKILLS",
   -- Lager: Taschen, Gegenstaende, Herstellen
   "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo", "C_Container.GetItemCooldown",
   "C_Item.GetItemNameByID", "C_Item.GetItemIconByID", "C_Item.IsUsableItem", "C_Item.RequestLoadItemDataByID",
   "C_TradeSkillUI.CraftRecipe", "C_TradeSkillUI.OpenRecipe", "C_TradeSkillUI.IsTradeSkillReady",
   "C_TradeSkillUI.GetRecipeInfo", "C_Timer.After", "UnitFactionGroup", "UnitCastingInfo", "GetTime",
   -- Funktionen der alten Technik: sollten hier fehlen (zeigt, dass es wirklich der Retail-Unterbau ist)
   "GetSkillLineInfo", "GetSpellInfo", "GetNumSpellTabs", "CloseTradeSkill",
}

local function Lookup(path)
   local value = _G
   for part in path:gmatch("[^%.]+") do
      if type(value) ~= "table" then return nil end
      value = value[part]
   end
   return value
end

local function Safe(fn, ...)
   local ok, a, b, c, d = pcall(fn, ...)
   if ok then return a, b, c, d end
   return nil
end

-- Sammelt alle Zeilen; zweiter Rueckgabewert: die Kurzfassung fuer den Chat.
function Diag.Collect()
   local lines, short = {}, {}
   local function add(text, both)
      lines[#lines + 1] = text
      if both then short[#short + 1] = text end
   end

   add("ProfessionMenu " .. tostring(PM.version) .. " diagnostics", true)
   if _G.GetBuildInfo then
      local version, build, date, interface = Safe(_G.GetBuildInfo)
      add("build: " .. tostring(version) .. " (" .. tostring(build) .. ", " .. tostring(date) .. ") interface=" .. tostring(interface), true)
   end
   add("locale: " .. tostring(_G.GetLocale and _G.GetLocale()) .. "  WOW_PROJECT_ID=" .. tostring(_G.WOW_PROJECT_ID))
   add("toc Version: " .. tostring(_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and Safe(_G.C_AddOns.GetAddOnMetadata, ADDON, "Version")))
   if _G.GetCVar then
      add("CVar ActionButtonUseKeyDown = " .. tostring(Safe(_G.GetCVar, "ActionButtonUseKeyDown")))
   end
   if _G.UIParent then
      local pw, ph
      if _G.GetPhysicalScreenSize then pw, ph = Safe(_G.GetPhysicalScreenSize) end
      add("ui: effectiveScale=" .. tostring(_G.UIParent:GetEffectiveScale()) .. " physical=" .. tostring(pw) .. "x" .. tostring(ph)
         .. " pixel=" .. tostring(PM.Skin and PM.Skin.Mult and Safe(PM.Skin.Mult)))
   end
   add("combat: " .. tostring(_G.InCombatLockdown and _G.InCombatLockdown()))

   -- vorhandene Funktionen
   local missing = {}
   add("api:")
   for _, path in ipairs(APIS) do
      local present = Lookup(path) ~= nil
      add("  " .. path .. " = " .. (present and "yes" or "NO"))
      -- die alten Funktionen sollen fehlen, alle anderen sollen da sein
      local old = path == "GetSkillLineInfo" or path == "GetSpellInfo" or path == "GetNumSpellTabs" or path == "CloseTradeSkill"
      if (not old and not present) and path ~= "ProfessionsFrame" and path ~= "ToggleProfessionsBook" then
         missing[#missing + 1] = path
      end
   end
   if #missing > 0 then
      add("MISSING (needed): " .. table.concat(missing, ", "), true)
   else
      add("all needed API functions exist", true)
   end

   -- gelesene Berufe
   local raws = PM.ReadProfessions()
   add("professions read: " .. #raws, true)
   for _, raw in ipairs(raws) do
      add("  [" .. raw.pos .. "] " .. raw.name .. "  rank " .. raw.rank .. "/" .. raw.maxRank .. "  skillLine=" .. tostring(raw.skillLine)
         .. "  index=" .. tostring(raw.index) .. "  spells=" .. raw.numSpells .. " offset=" .. raw.spellOffset
         .. "  known=" .. (PM.Identify(raw) and PM.Identify(raw).key or "NO"), true)
      for _, spell in ipairs(raw.spells) do
         add("      slot " .. spell.slot .. ": " .. tostring(spell.id) .. " " .. tostring(spell.name)
            .. (spell.passive and " [passive]" or "") .. (spell.window and " [opens window]" or "")
            .. (spell.isSpell and "" or " [not a spell]"), true)
      end
   end

   -- gemerkte Charaktere des Kontos
   for _, line in ipairs(PM.CharacterLines()) do add("char: " .. line, true) end

   -- gebaute Eintraege
   local entries = PM.BuildEntries(raws)
   add("entries: " .. #entries, true)
   for _, e in ipairs(entries) do
      add("  " .. e.cat .. "/" .. tostring(e.order) .. "  " .. e.key .. "  \"" .. e.name .. "\"  kind=" .. e.kind
         .. "  spell=" .. tostring(e.action) .. (e.moved and "  [search moved to abilities]" or "")
         .. (e.missing and "  [spell missing]" or "") .. (e.open and ("  [not learned: " .. e.open .. "]") or "")
         .. (e.item and ("  item=" .. e.item) or "")
         .. (e.craft and ("  recipe=" .. tostring(e.craft.recipe)) or ""), true)
      for _, child in ipairs(e.children or {}) do
         add("      > " .. child.key .. "  \"" .. child.name .. "\"  kind=" .. tostring(child.kind) .. "  spell=" .. tostring(child.action)
            .. (child.tag and ("  tag=" .. child.tag) or "") .. (child.item and ("  item=" .. child.item) or "") .. (child.craft and ("  recipe=" .. tostring(child.craft.recipe)) or ""), true)
      end
   end

   -- Lager: jedes Objekt, dessen Beruf erlernt ist oder das im Inventar liegt
   local profs = {}
   for _, raw in ipairs(raws) do
      local def = PM.Identify(raw)
      if def then profs[def.key] = { name = raw.name, rank = raw.rank + raw.modifier, skillLine = raw.skillLine } end
   end
   local camp = PM.Camp.Evaluate(profs)
   local _, scanned = PM.Camp.Scan()
   add("camp: setting=" .. tostring(PM.db.camp) .. " activities=" .. tostring(PM.db.activities) .. " faction=" .. tostring(camp.faction)
      .. " bags scanned=" .. tostring(scanned), true)
   for _, def in ipairs(PM.CAMP) do
      local st = camp.states[def.key]
      if st.prof or st.count > 0 then
         local parts = {}
         for _, reagent in ipairs(st.reagents) do parts[#parts + 1] = reagent.id .. ":" .. reagent.have .. "/" .. reagent.need end
         if st.tool then parts[#parts + 1] = "tool " .. st.tool.id .. ":" .. st.tool.have end
         local learned
         if def.recipe and _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeInfo then
            local info = Safe(_G.C_TradeSkillUI.GetRecipeInfo, PM.Camp.Recipe(def))
            learned = type(info) == "table" and info.learned or nil
         end
         add("  " .. def.key .. "  item=" .. tostring(st.item) .. " \"" .. PM.ItemName(st.item, def.name) .. "\"  mode=" .. tostring(st.mode)
            .. "  bags=" .. st.count .. "  skill " .. (st.prof and st.prof.rank or "-") .. "/" .. def.skill
            .. "  recipe=" .. tostring(PM.Camp.Recipe(def)) .. " learned=" .. tostring(learned)
            .. (st.mode == "place" and ("  usable=" .. tostring(st.usable) .. " cooldown=" .. tostring(st.cooldown)) or "")
            .. "  [" .. table.concat(parts, " ") .. "]", true)
      end
   end

   -- bekannte Faehigkeiten
   local known = {}
   for _, def in ipairs(PM.ABILITIES) do
      if PM.IsSpellKnown(def.spell) then known[#known + 1] = def.key .. "(" .. def.spell .. ")" end
   end
   add("known abilities from list: " .. (#known > 0 and table.concat(known, ", ") or "none"), true)

   -- Zeilen der Oberflaeche
   local UI = PM.UI
   if UI and UI.created then
      local row = UI.rows[1]
      if row and row.entry then
         add("row 1: entry=" .. tostring(row.entry.key) .. " type1=" .. tostring(row:GetAttribute("type1"))
            .. " spell1=" .. tostring(row:GetAttribute("spell1")) .. " useOnKeyDown=" .. tostring(row:GetAttribute("useOnKeyDown")), true)
      end
      local menu = UI.GetMenu()
      add("menu: shown=" .. tostring(menu and menu:IsShown()) .. " width=" .. tostring(menu and menu:GetWidth())
         .. " height=" .. tostring(menu and menu:GetHeight()))
   else
      add("ui: not created yet", true)
   end

   -- Fenster-Zustand
   if _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetBaseProfessionInfo then
      local info = Safe(_G.C_TradeSkillUI.GetBaseProfessionInfo)
      add("open trade skill: professionID=" .. tostring(type(info) == "table" and info.professionID or nil)
         .. " ProfessionsFrame shown=" .. tostring(_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()))
   end

   -- gemeldete Fehler
   if #PM.errors > 0 then
      add("errors:", true)
      for _, err in ipairs(PM.errors) do add("  " .. err, true) end
   else
      add("errors: none")
   end

   return lines, short
end

function Diag.Run()
   local lines, short = Diag.Collect()
   local stamp = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?"
   PM.db.diag = { stamp = stamp, lines = lines }
   for _, text in ipairs(short) do PM.Print(text) end
   PM.Print(string.format(PM.L.diagDone, #lines))
end
