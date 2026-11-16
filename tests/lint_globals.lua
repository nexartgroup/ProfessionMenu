-- tests/lint_globals.lua
-- ---------------------------------------------------------------------------
-- Statische Pruefung: welche globalen Namen liest oder schreibt das Addon? Jeder muss auf der Liste stehen.
-- Die Liste enthaelt NUR Namen, die im Quelltext der Forever-Oberflaeche (Gethe/wow-ui-source, Zweig
-- "forever", Version 1.60.1.70862) vorkommen oder zur Lua-Standardbibliothek des Spiels gehoeren.
-- So faellt eine Funktion der alten 3.3.5a-Technik (GetSkillLineInfo, GetSpellInfo ...) oder ein Tippfehler auf,
-- bevor das Spiel sie als nil erlebt.
-- Aufruf im Addon-Ordner:  luajit tests/lint_globals.lua
-- ---------------------------------------------------------------------------

local ALLOWED = {}
local function allow(list) for name in list:gmatch("%S+") do ALLOWED[name] = true end end

-- Lua und die Hilfsfunktionen des Spiels
allow [[
_G assert error getmetatable ipairs next pairs pcall rawget rawset select setmetatable tonumber tostring type unpack
string table math bit format tinsert tremove wipe date strlower strmatch
]]

-- Oberflaeche und Rahmen
allow [[
CreateFrame UIParent GameTooltip UIErrorsFrame DEFAULT_CHAT_FRAME UISpecialFrames SlashCmdList
STANDARD_TEXT_FONT ABILITIES TRADE_SKILLS hooksecurefunc
]]

-- Spielzustand und Berufe
allow [[
GetLocale GetPhysicalScreenSize IsMouseButtonDown InCombatLockdown RegisterStateDriver
GetProfessions GetProfessionInfo GetBuildInfo GetCVar WOW_PROJECT_ID
Enum C_Spell C_SpellBook C_TradeSkillUI C_AddOns Settings PixelUtil BackdropTemplateMixin
MinimalSliderWithSteppersMixin ProfessionsFrame ToggleProfessionsBook
SecureActionButton_OnClick SecureActionButton_ShouldUseOnKeyDown
]]

-- Lager: Taschen, Gegenstaende, Herstellen (dieselben Namen benutzen FishFry und OneForAll auf Forever)
allow [[
GetTime C_Container C_Item C_Timer UnitFactionGroup UnitCastingInfo NUM_TOTAL_EQUIPPED_BAG_SLOTS
]]

-- Charaktere des Kontos (wer hat welchen Beruf)
allow [[
UnitName GetRealmName
]]

-- Globale, die das Addon selbst anlegt (Slash-Befehle, gespeicherte Einstellungen)
allow [[
SLASH_PROFESSIONMENU1 SLASH_PROFESSIONMENU2 ProfessionMenuDB
]]

-- Namen aus der Liste oben, die nur in Diag.lua als Text vorkommen, brauchen keinen Eintrag; hier stehen nur
-- die, die der Code wirklich anfasst.

local files = {}
for line in io.lines("ProfessionMenu.toc") do
   if line ~= "" and not line:find("^##") then files[#files + 1] = (line:gsub("%s+$", "")) end
end

local bad, total = {}, 0
for _, file in ipairs(files) do
   local p = io.popen("luajit -bl " .. file .. " 2>&1")
   for line in p:lines() do
      local op, name = line:match("%s(G[GS]ET)%s.-;%s\"(.-)\"")
      if op then
         total = total + 1
         if not ALLOWED[name] then
            bad[#bad + 1] = file .. ": " .. op .. " " .. name
         end
      end
   end
   p:close()

   -- Zugriffe ueber _G.Name (so greift das Addon auf Funktionen zu, die es ggf. nicht gibt) und rawget(_G, "Name")
   local handle = io.open(file)
   local lineNo = 0
   for text in handle:lines() do
      lineNo = lineNo + 1
      local code = text:gsub("%-%-.*$", "")
      for name in code:gmatch("_G%.([%a_][%w_]*)") do
         total = total + 1
         if not ALLOWED[name] then bad[#bad + 1] = file .. ":" .. lineNo .. ": _G." .. name end
      end
      for name in code:gmatch("rawget%(_G,%s*\"([%w_]+)\"%)") do
         total = total + 1
         if not ALLOWED[name] then bad[#bad + 1] = file .. ":" .. lineNo .. ": rawget(_G, \"" .. name .. "\")" end
      end
   end
   handle:close()
end

if #bad > 0 then
   local seen, unique = {}, {}
   for _, b in ipairs(bad) do if not seen[b] then seen[b] = true unique[#unique + 1] = b end end
   print("Unbekannte globale Namen:")
   for _, b in ipairs(unique) do print("  " .. b) end
   os.exit(1)
end

print(string.format("lint_globals: %d globale Zugriffe in %d Dateien, alle auf der Liste", total, #files))
