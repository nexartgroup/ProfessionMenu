-- tests/test_locale.lua
-- ---------------------------------------------------------------------------
-- Texte (Locales.lua): Auswahl der Sprache, Rueckfall auf Englisch, Platzhalter, Vollstaendigkeit der Pflichttexte,
-- Schluessel im Code (jeder benutzte Schluessel existiert in enUS, jeder enUS-Schluessel wird benutzt).
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local F = require("fixtures")

   local ALL_LOCALES = { "enUS", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "zhCN", "zhTW" }

   local function readFile(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local s = f:read("*a")
      f:close()
      return s
   end

   -- Platzhalterfolge eines Textes: "%s", "%d", "%.2f" ... ohne "%%"
   local function placeholders(text)
      local out = {}
      for spec in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*(%a)") do out[#out + 1] = spec end
      return table.concat(out, ",")
   end

   local function boot(locale)
      return F.boot(H, { learned = {}, locale = locale })
   end

   -- ======================================================================
   H.section("Locale selection")
   -- ======================================================================

   H.test("enUS and deDE clients get their own language", function()
      local PM = boot("enUS")
      H.eq(PM.locale, "enUS")
      H.eq(PM.L.title, "Professions")
      PM = boot("deDE")
      H.eq(PM.locale, "deDE")
      H.eq(PM.L.title, "Berufe")
   end)

   H.test("frFR, esES, ruRU, koKR, zhCN, zhTW titles", function()
      local want = { frFR = "M\195\169tiers", esES = "Profesiones", ruRU = "\208\159\209\128\208\190\209\132\208\181\209\129\209\129\208\184\208\184" }
      for locale, title in pairs(want) do
         local PM = boot(locale)
         H.eq(PM.locale, locale)
         H.eq(PM.L.title, title, locale)
      end
      for _, locale in ipairs({ "koKR", "zhCN", "zhTW" }) do
         local PM = boot(locale)
         H.eq(PM.locale, locale)
         H.neq(PM.L.title, "Professions", locale)
      end
   end)

   H.test("esMX shares the Spanish texts", function()
      local PM = boot("esMX")
      H.eq(PM.L.title, "Profesiones")
      H.eq(PM.texts.esMX, PM.texts.esES)
   end)

   H.test("an unknown locale (enGB, itIT, ptBR) falls back to English completely", function()
      for _, locale in ipairs({ "enGB", "itIT", "ptBR", "" }) do
         local PM = boot(locale)
         H.eq(PM.locale, "enUS", "'" .. locale .. "'")
         H.eq(PM.L.title, "Professions")
         H.eq(PM.L.help, PM.texts.enUS.help)
      end
   end)

   H.test("a key missing in a language falls back to English; an unknown key returns itself", function()
      local PM = boot("frFR")
      H.eq(PM.texts.frFR.opt_title, nil, "frFR has no options title")
      H.eq(PM.L.opt_title, "Professions menu")
      H.eq(PM.L.title, "M\195\169tiers")
      H.eq(PM.L.no_such_key_at_all, "no_such_key_at_all")
   end)

   H.test("SetLocale switches at runtime and re-binds the table the code already holds", function()
      local PM = boot("enUS")
      local L = PM.L
      PM.SetLocale("deDE")
      H.eq(L.title, "Berufe")
      PM.SetLocale("xx")
      H.eq(L.title, "Professions")
      H.eq(PM.locale, "enUS")
   end)

   -- ======================================================================
   H.section("Completeness and placeholders")
   -- ======================================================================

   H.test("every locale only uses keys that exist in enUS (no stray keys)", function()
      local PM = boot("enUS")
      for _, locale in ipairs(ALL_LOCALES) do
         for key in pairs(PM.texts[locale]) do
            H.truthy(PM.texts.enUS[key] ~= nil, locale .. ": key '" .. key .. "' does not exist in enUS")
         end
      end
   end)

   H.test("every value is a non-empty string", function()
      local PM = boot("enUS")
      for _, locale in ipairs(ALL_LOCALES) do
         for key, text in pairs(PM.texts[locale]) do
            H.eq(type(text), "string", locale .. "." .. key)
            H.neq(text, "", locale .. "." .. key)
         end
      end
   end)

   H.test("the texts a normal user sees (title, categories, hints, skill, none, combat) exist in every language", function()
      local PM = boot("enUS")
      local needed = { "title", "cat_craft", "cat_refine", "cat_gather", "cat_secondary", "hint_open", "hint_track",
                       "hint_use", "hint_passive", "hint_skills", "skill", "none", "combat", "cat_abilities", "hint_target",
                       "hint_moved" }
      for _, locale in ipairs(ALL_LOCALES) do
         for _, key in ipairs(needed) do
            H.eq(type(PM.texts[locale][key]), "string", locale .. "." .. key)
         end
      end
   end)

   H.test("German and English are complete: all keys translated", function()
      local PM = boot("enUS")
      for key in pairs(PM.texts.enUS) do
         H.eq(type(PM.texts.deDE[key]), "string", "deDE." .. key)
      end
   end)

   H.test("placeholders agree with English in every language (a wrong %d/%s would crash string.format)", function()
      local PM = boot("enUS")
      for _, locale in ipairs(ALL_LOCALES) do
         for key, text in pairs(PM.texts[locale]) do
            H.eq(placeholders(text), placeholders(PM.texts.enUS[key] or ""), locale .. "." .. key)
         end
      end
   end)

   H.test("every format string works with realistic arguments in every language", function()
      for _, locale in ipairs(ALL_LOCALES) do
         local PM = boot(locale)
         local L = PM.L
         H.truthy(pcall(string.format, L.skill, 300, 450), locale .. " skill")
         H.truthy(pcall(string.format, L.listMatched, "Mining", "mining / x", 300, 450), locale .. " listMatched")
         H.truthy(pcall(string.format, L.listUnmatched, "Riding", 150, 150), locale .. " listUnmatched")
         H.truthy(pcall(string.format, L.setSort, "x"), locale .. " setSort")
         H.truthy(pcall(string.format, L.setHeaders, "x"), locale .. " setHeaders")
         H.truthy(pcall(string.format, L.setRanks, "x"), locale .. " setRanks")
         H.truthy(pcall(string.format, L.setDirection, "x"), locale .. " setDirection")
         H.truthy(pcall(string.format, L.setScale, 1.25), locale .. " setScale")
         H.truthy(pcall(string.format, L.error, "Command", "boom"), locale .. " error")
      end
   end)

   H.test("UTF-8 text is valid in every language (no broken sequences)", function()
      local PM = boot("enUS")
      for _, locale in ipairs(ALL_LOCALES) do
         for key, text in pairs(PM.texts[locale]) do
            local ok = pcall(function()
               local i = 1
               while i <= #text do
                  local b = text:byte(i)
                  local n = (b < 0x80 and 1) or (b >= 0xC2 and b < 0xE0 and 2) or (b >= 0xE0 and b < 0xF0 and 3)
                     or (b >= 0xF0 and b < 0xF5 and 4) or error("bad lead byte")
                  for k = 1, n - 1 do
                     local c = text:byte(i + k)
                     if not c or c < 0x80 or c > 0xBF then error("bad continuation") end
                  end
                  i = i + n
               end
            end)
            H.truthy(ok, locale .. "." .. key .. " is valid UTF-8")
         end
      end
   end)

   H.test("localized headings fit the list: the longest category heading is not wider than the button", function()
      -- 10 px outline font, 0.55 em average width in the mock; the heading has the list's width minus 2 * headerPad
      for _, locale in ipairs(ALL_LOCALES) do
         local PM = F.boot(H, { learned = F.ORDER, locale = locale })
         PM.UI.Open()
         for _, h in ipairs(PM.UI.headers) do
            if h.text:IsShown() then
               H.truthy(h.text:GetStringWidth() <= PM.UI.GetMenu():GetWidth() - 2 * PM.UI.sizes.headerPad,
                  locale .. ": heading '" .. tostring(h.text:GetText()) .. "' is too wide")
            end
         end
      end
   end)

   -- ======================================================================
   H.section("Keys used in the code")
   -- ======================================================================

   local FILES = { "Core.lua", "Skin.lua", "UI.lua", "Main.lua", "Options.lua" }

   local function usedKeys()
      local used, dynamic = {}, {}
      for _, file in ipairs(FILES) do
         local src = readFile(M.root .. "/" .. file)
         H.truthy(src, file .. " readable")
         -- Kommentare entfernen
         src = src:gsub("%-%-[^\n]*", "")
         for key in src:gmatch("%f[%w_]L%.([%a_][%w_]*)") do used[key] = file end
         for key in src:gmatch("%f[%w_]PM%.L%.([%a_][%w_]*)") do used[key] = file end
         for key in src:gmatch('%f[%w_]L%["([%w_]+)"%]') do used[key] = file end
         for prefix in src:gmatch('L%["([%w_]+)"%s*%.%.') do dynamic[prefix] = file end
         for table_ in src:gmatch("L%[([%a_][%w_]*)%[") do dynamic["@" .. table_] = file end
      end
      return used, dynamic
   end

   H.test("every L.key used in the code exists in enUS", function()
      local PM = boot("enUS")
      local used = usedKeys()
      local n = 0
      for key, file in pairs(used) do
         n = n + 1
         H.truthy(PM.texts.enUS[key] ~= nil, file .. ": L." .. key .. " is not defined in enUS")
      end
      H.truthy(n > 20, "found the usages (" .. n .. ")")
   end)

   H.test("dynamic keys: cat_<category> exists for every category, the sort/direction labels exist", function()
      local PM = boot("enUS")
      local _, dynamic = usedKeys()
      H.truthy(dynamic.cat_, "L[\"cat_\" .. x] is used")
      for _, cat in ipairs(PM.CATEGORIES) do H.truthy(PM.texts.enUS["cat_" .. cat], cat) end
      for _, key in ipairs({ "sortcat", "sortalpha", "sortrank", "dirauto", "dirup", "dirdown" }) do
         H.truthy(PM.texts.enUS[key], key)
      end
   end)

   H.test("every enUS key is used somewhere in the code (no dead texts)", function()
      local PM = boot("enUS")
      local used = usedKeys()
      -- keys reached through tables / prefixes
      local viaTable = { sortcat = true, sortalpha = true, sortrank = true, dirauto = true, dirup = true, dirdown = true,
                         cat_craft = true, cat_refine = true, cat_gather = true, cat_secondary = true, cat_abilities = true,
                         compactoff = true, compactbutton = true, compactall = true }
      for key in pairs(PM.texts.enUS) do
         H.truthy(used[key] or viaTable[key], "enUS." .. key .. " is never used")
      end
   end)

   H.test("the texts that mention a command name the commands that exist", function()
      local PM = boot("enUS")
      H.contains(PM.texts.enUS.unlocked, "/berufe lock")
      H.contains(PM.texts.deDE.unlocked, "/berufe lock")
      H.contains(PM.texts.enUS.lockedElvUI, "/moveui")
      H.contains(PM.texts.deDE.lockedElvUI, "/moveui")
      H.contains(PM.texts.enUS.opt_move, "/moveui")
   end)

   H.test("no text contains a stray single '|' except the colour codes of the print prefix", function()
      local PM = boot("enUS")
      for _, locale in ipairs(ALL_LOCALES) do
         for key, text in pairs(PM.texts[locale]) do
            if key ~= "help" then
               H.falsy(text:gsub("||", ""):find("|"), locale .. "." .. key .. " has a bare '|'")
            end
         end
      end
   end)
end
