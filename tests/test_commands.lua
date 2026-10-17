-- tests/test_commands.lua
-- ---------------------------------------------------------------------------
-- Chatbefehle (/berufe, /profmenu) und Einstellungen (ProfessionMenuDB): Voreinstellungen, jeder Befehl mit
-- Meldung und Wirkung, ungueltige Eingaben, Gross-/Kleinschreibung, /berufe list, Debug-Modus, Guard.
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   -- "||" ist im Chat das maskierte "|" (ein einzelnes "|r" waere die Farb-Rueckstellung)
   local HELP = "/berufe [toggle] || list || sort cat||alpha||rank || headers on||off || ranks on||off || direction auto||up||down || compact off||button||all || abilities on||off || scale <0.5-2> || unlock || lock || reset || debug"

   local function boot(opts)
      local PM, M = F.boot(H, opts)
      F.clearChat(M)
      return PM, M
   end

   local function lastChat(M)
      return M.messages[#M.messages]
   end

   local PREFIX = "|cffff7b2cProfessionMenu|r "

   -- ======================================================================
   H.section("Database defaults")
   -- ======================================================================

   H.test("first start: ProfessionMenuDB gets exactly the defaults", function()
      local PM = boot({ learned = { "alchemy" } })
      H.deepEq(ProfessionMenuDB, { sort = "cat", headers = true, ranks = true, direction = "auto", compact = "off", abilities = false, scale = 1, locked = true })
      H.eq(PM.db, ProfessionMenuDB)
      H.deepEq(PM.DEFAULTS, ProfessionMenuDB)
   end)

   H.test("existing values are kept, missing ones are filled in, unknown keys survive", function()
      local PM = boot({ learned = { "alchemy" }, db = { sort = "rank", ranks = false, legacyKey = 42 } })
      H.eq(ProfessionMenuDB.sort, "rank")
      H.eq(ProfessionMenuDB.ranks, false, "false is not replaced by the default true")
      H.eq(ProfessionMenuDB.headers, true)
      H.eq(ProfessionMenuDB.direction, "auto")
      H.eq(ProfessionMenuDB.scale, 1)
      H.eq(ProfessionMenuDB.locked, true)
      H.eq(ProfessionMenuDB.legacyKey, 42)
   end)

   H.test("a saved 'false' for headers/locked stays false (nil-check, not truthiness)", function()
      local PM = boot({ learned = { "alchemy" }, db = { headers = false, locked = false } })
      H.eq(ProfessionMenuDB.headers, false)
      H.eq(ProfessionMenuDB.locked, false)
   end)

   H.test("a ProfessionMenuDB that is not a table is replaced", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, saved = { ProfessionMenuDB = "oops" } })
      H.eq(type(ProfessionMenuDB), "table")
      H.eq(ProfessionMenuDB.sort, "cat")
   end)

   H.test("ADDON_LOADED of other addons is ignored; the own one is handled once", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, login = false })
      M.Fire("ADDON_LOADED", "SomethingElse")
      H.eq(PM.db.sort, "cat")
      PM.db.sort = "alpha"
      M.Fire("ADDON_LOADED", "ProfessionMenu")       -- unregistered after the first time
      H.eq(PM.db.sort, "alpha", "defaults are not applied twice")
      H.falsy(PM.frame:IsEventRegistered("ADDON_LOADED"))
   end)

   H.test("before ADDON_LOADED the defaults apply through the metatable (no nil indexing)", function()
      local PM = F.boot(H, { login = false, before = nil })
      H.eq(PM.db.sort, "cat")
      H.eq(PM.db.headers, true)
   end)

   H.test("the slash commands are registered: /berufe, /profmenu", function()
      F.boot(H, { learned = { "alchemy" } })
      H.eq(SLASH_PROFESSIONMENU1, "/berufe")
      H.eq(SLASH_PROFESSIONMENU2, "/profmenu")
      H.eq(type(SlashCmdList.PROFESSIONMENU), "function")
   end)

   -- ======================================================================
   H.section("sort / headers / ranks / direction")
   -- ======================================================================

   H.test("sort cat|alpha|rank: message, database, list", function()
      local PM, M = boot({ learned = { "alchemy", "fishing" } })
      M.Slash("/berufe sort alpha")
      H.eq(lastChat(M), PREFIX .. "Sorting: alphabetical")
      H.eq(PM.db.sort, "alpha")
      M.Slash("/berufe sort rank")
      H.eq(lastChat(M), PREFIX .. "Sorting: by skill level")
      H.eq(PM.db.sort, "rank")
      M.Slash("/berufe sort cat")
      H.eq(lastChat(M), PREFIX .. "Sorting: by category")
      H.eq(PM.db.sort, "cat")
   end)

   H.test("sort messages in German", function()
      local PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe sort alpha")
      H.eq(lastChat(M), PREFIX .. "Sortierung: alphabetisch")
      M.Slash("/berufe sort rank")
      H.eq(lastChat(M), PREFIX .. "Sortierung: nach Fertigkeitsstufe")
      M.Slash("/berufe sort cat")
      H.eq(lastChat(M), PREFIX .. "Sortierung: nach Kategorie")
   end)

   H.test("sort with a bad or missing argument prints the help and changes nothing", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe sort")
      H.eq(lastChat(M), PREFIX .. HELP)
      M.Slash("/berufe sort sideways")
      H.eq(lastChat(M), PREFIX .. HELP)
      M.Slash("/berufe sort alpha beta")
      H.eq(lastChat(M), PREFIX .. HELP)
      H.eq(PM.db.sort, "cat")
   end)

   H.test("headers on|off and the aliases an|aus|1|0|true|false (case-insensitive)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      for _, off in ipairs({ "off", "aus", "0", "false", "OFF", "Aus" }) do
         PM.db.headers = true
         M.Slash("/berufe headers " .. off)
         H.eq(PM.db.headers, false, off)
         H.eq(lastChat(M), PREFIX .. "Category headings: off")
      end
      for _, on in ipairs({ "on", "an", "1", "true", "ON", "An" }) do
         PM.db.headers = false
         M.Slash("/berufe headers " .. on)
         H.eq(PM.db.headers, true, on)
         H.eq(lastChat(M), PREFIX .. "Category headings: on")
      end
   end)

   H.test("headers / ranks with a bad argument print the help and change nothing", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe headers maybe")
      H.eq(lastChat(M), PREFIX .. HELP)
      M.Slash("/berufe ranks")
      H.eq(lastChat(M), PREFIX .. HELP)
      H.eq(PM.db.headers, true)
      H.eq(PM.db.ranks, true)
   end)

   H.test("ranks messages (enUS / deDE)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe ranks off")
      H.eq(lastChat(M), PREFIX .. "Skill levels: off")
      PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe ranks off")
      H.eq(lastChat(M), PREFIX .. "Fertigkeitsstufen: aus")
      M.Slash("/berufe headers on")
      H.eq(lastChat(M), PREFIX .. "Kategorie-\195\156berschriften: an")
   end)

   H.test("direction auto|up|down: message and database; case-insensitive", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe direction up")
      H.eq(lastChat(M), PREFIX .. "Opening direction: up")
      H.eq(PM.db.direction, "up")
      M.Slash("/berufe direction DOWN")
      H.eq(lastChat(M), PREFIX .. "Opening direction: down")
      H.eq(PM.db.direction, "down")
      M.Slash("/berufe direction auto")
      H.eq(lastChat(M), PREFIX .. "Opening direction: automatic")
      M.Slash("/berufe direction left")
      H.eq(lastChat(M), PREFIX .. HELP)
      H.eq(PM.db.direction, "auto")
   end)

   H.test("direction messages in German", function()
      local PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe direction up")
      H.eq(lastChat(M), PREFIX .. "\195\150ffnungsrichtung: nach oben")
      M.Slash("/berufe direction down")
      H.eq(lastChat(M), PREFIX .. "\195\150ffnungsrichtung: nach unten")
      M.Slash("/berufe direction auto")
      H.eq(lastChat(M), PREFIX .. "\195\150ffnungsrichtung: automatisch")
   end)

   -- ======================================================================
   H.section("scale")
   -- ======================================================================

   H.test("scale accepts 0.5 .. 2 including the borders and a decimal comma", function()
      local PM, M = boot({ learned = { "alchemy" } })
      for _, case in ipairs({ { "0.5", 0.5 }, { "2", 2 }, { "1.25", 1.25 }, { "1,5", 1.5 }, { "  1.1  ", 1.1 } }) do
         M.Slash("/berufe scale " .. case[1])
         H.eq(PM.db.scale, case[2], case[1])
         H.eq(PM.UI.GetButton():GetScale(), case[2], case[1])
         H.eq(PM.UI.GetMenu():GetScale(), case[2], case[1])
      end
      H.eq(lastChat(M), PREFIX .. "Scale: 1.10")
   end)

   H.test("scale outside the range or not a number: message, nothing changed", function()
      local PM, M = boot({ learned = { "alchemy" } })
      for _, bad in ipairs({ "0.49", "2.01", "0", "-1", "abc", "", "1..5", "5", "1e9" }) do
         M.Slash("/berufe scale " .. bad)
         H.eq(lastChat(M), PREFIX .. "Scale must be between 0.5 and 2.", "'" .. bad .. "'")
         H.eq(PM.db.scale, 1, "'" .. bad .. "' left the scale alone")
      end
      H.eq(PM.UI.GetButton():GetScale(), 1)
   end)

   H.test("the range message is German in deDE", function()
      local PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe scale 9")
      H.eq(lastChat(M), PREFIX .. "Die Skalierung muss zwischen 0.5 und 2 liegen.")
   end)

   -- ======================================================================
   H.section("unlock / lock / reset / debug / help")
   -- ======================================================================

   H.test("unlock and lock: messages (enUS / deDE) and database", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe unlock")
      H.eq(lastChat(M), PREFIX .. "Button unlocked: drag it with the left mouse button, /berufe lock when done.")
      H.eq(PM.db.locked, false)
      M.Slash("/berufe lock")
      H.eq(lastChat(M), PREFIX .. "Button locked.")
      H.eq(PM.db.locked, true)
      PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe unlock")
      H.eq(lastChat(M), PREFIX .. "Knopf entsperrt: mit der linken Maustaste ziehen, danach /berufe lock.")
      M.Slash("/berufe lock")
      H.eq(lastChat(M), PREFIX .. "Knopf gesperrt.")
   end)

   H.test("reset: message (enUS / deDE)", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe reset")
      H.eq(lastChat(M), PREFIX .. "Position reset.")
      PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe reset")
      H.eq(lastChat(M), PREFIX .. "Position zur\195\188ckgesetzt.")
   end)

   H.test("debug toggles PM.debug and says so", function()
      local PM, M = boot({ learned = { "alchemy" } })
      M.Slash("/berufe debug")
      H.eq(PM.debug, true)
      H.eq(lastChat(M), PREFIX .. "Debug messages on.")
      M.Slash("/berufe debug")
      H.eq(PM.debug, false)
      H.eq(lastChat(M), PREFIX .. "Debug messages off.")
      PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      M.Slash("/berufe debug")
      H.eq(lastChat(M), PREFIX .. "Debug-Meldungen an.")
   end)

   H.test("unknown commands and a lone junk word print the help", function()
      local PM, M = boot({ learned = { "alchemy" } })
      for _, cmd in ipairs({ "/berufe help", "/berufe ?", "/berufe foo bar", "/berufe sorty" }) do
         F.clearChat(M)
         M.Slash(cmd)
         H.eq(lastChat(M), PREFIX .. HELP, cmd)
      end
   end)

   H.test("commands are case-insensitive and tolerate extra blanks", function()
      local PM, M = boot({ learned = { "alchemy", "fishing" } })
      M.Slash("/berufe   SORT    Alpha   ")
      H.eq(PM.db.sort, "alpha")
      M.Slash("/BERUFE Direction UP")
      H.eq(PM.db.direction, "up")
      M.Slash("/Profmenu Headers OFF")
      H.eq(PM.db.headers, false)
   end)

   H.test("the help text lists every command that exists", function()
      local PM = boot({ learned = { "alchemy" } })
      for _, word in ipairs({ "toggle", "list", "sort cat||alpha||rank", "headers on||off", "ranks on||off",
                              "direction auto||up||down", "scale <0.5-2>", "unlock", "lock", "reset", "debug" }) do
         H.contains(PM.L.help, word)
      end
   end)

   H.test("the help text has no bare '|' that the client would read as an escape sequence ('|r' resets the colour)", function()
      -- "sort cat|alpha|rank": "|r" is the colour reset code, "|a", "|u", "|o" are invalid escapes; literal pipes are '||'.
      local PM = boot({ learned = { "alchemy" } })
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local text = PM.texts[locale].help
         local stripped = text:gsub("||", "")
         H.falsy(stripped:find("|"), locale .. " help contains a single '|': " .. text)
      end
   end)

   -- ======================================================================
   H.section("/berufe list")
   -- ======================================================================

   H.test("list shows the recognised skills: matched ones with key and action, unmatched ones flagged", function()
      local PM, M = boot({ learned = { "alchemy", "mining", "skinning" }, noSpell = { "skinning" },
                           extraSkills = { { "Riding", 150, 150 } } })
      M.Slash("/berufe list")
      local out = {}
      for _, line in ipairs(M.messages) do out[#out + 1] = (line:gsub("^|cffff7b2cProfessionMenu|r ", "")) end
      H.eq(out[1], "Detected skills:")
      local joined = table.concat(out, "\n")
      H.contains(joined, "  Alchemy -> alchemy / Alchemy (300/450)")
      H.contains(joined, "  Mining -> mining / Find Minerals (300/450)")
      H.contains(joined, "  Skinning -> skinning / no action (300/450)")
      H.contains(joined, "  Riding (150/150) - not a known profession")
      H.contains(joined, "  Defense (400/400) - not a known profession")
      H.contains(joined, "  Smelting -> smelting / Smelting (300/450)")
   end)

   H.test("list in German", function()
      local PM, M = boot({ learned = { "mining" }, locale = "deDE", noWeapons = true })
      M.Slash("/berufe list")
      H.eq(M.messages[1], PREFIX .. "Erkannte Fertigkeiten:")
      H.contains(M.messages[2], "Bergbau -> mining / Mineraliensuche (300/450)")
      H.contains(M.messages[3], "Verh\195\188ttung -> smelting / Verh\195\188ttung (300/450)")
   end)

   H.test("list without any skill line says so", function()
      local PM, M = boot({ skills = {}, spells = {} })
      M.Slash("/berufe list")
      H.eq(M.messages[1], PREFIX .. "Detected skills:")
      H.eq(M.messages[2], PREFIX .. "  (no skills read)")
      H.len(M.messages, 2)
   end)

   H.test("list restores collapsed headers and does not loop on the events it causes", function()
      local PM, M = boot({ learned = { "mining" }, collapsed = { Professions = true, ["Weapon Skills"] = true } })
      local before = M.SkillStates()
      M.Slash("/berufe list")
      H.deepEq(M.SkillStates(), before)
      M.Advance(1)
      H.eq(F.chatCount(M, "Detected skills:"), 1)
   end)

   -- ======================================================================
   H.section("Errors in handlers (PM.Guard)")
   -- ======================================================================

   H.test("a failing command is reported once (not repeated), and the addon keeps running", function()
      local PM, M = boot({ learned = { "alchemy" } })
      local orig = PM.UI.Toggle
      PM.UI.Toggle = function() error("boom") end
      M.Slash("/berufe")
      M.Slash("/berufe")
      M.Slash("/berufe")
      H.eq(F.chatCount(M, "Error in Command: "), 1, "reported once")
      PM.UI.Toggle = orig
      M.Slash("/berufe")
      H.truthy(F.isOpen(PM))
      H.allowGuardErrors()
   end)

   H.test("with debug on, every failure is reported", function()
      local PM, M = boot({ learned = { "alchemy" } })
      PM.UI.Toggle = function() error("boom") end
      M.Slash("/berufe debug")
      F.clearChat(M)
      M.Slash("/berufe")
      M.Slash("/berufe")
      H.eq(F.chatCount(M, "Error in Command: "), 2)
      H.allowGuardErrors()
   end)

   H.test("the error text is localized (German)", function()
      local PM, M = boot({ learned = { "alchemy" }, locale = "deDE" })
      PM.UI.Toggle = function() error("boom") end
      M.Slash("/berufe")
      H.eq(F.chatCount(M, "Fehler in Command: "), 1)
      H.allowGuardErrors()
   end)

   H.test("PM.Trace prints only in debug mode", function()
      local PM, M = boot({ learned = { "alchemy" } })
      PM.Trace("hello", 1, nil)
      H.len(M.messages, 0)
      PM.debug = true
      PM.Trace("hello", 1, nil)
      H.len(M.messages, 1)
      H.contains(M.messages[1], "hello 1 nil")
   end)
end
