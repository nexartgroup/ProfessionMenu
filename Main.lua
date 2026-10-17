-- Main.lua
-- ---------------------------------------------------------------------------
-- Ereignisse, Start und Chatbefehle.
--
-- Start: SavedVariables stehen bei ADDON_LOADED bereit. Die Oberflaeche wird erst
-- bei PLAYER_LOGIN gebaut, und mit ElvUI erst, wenn dieses fertig ist
-- (E.initialized, am Ende von E:Initialize gesetzt). Ob unser PLAYER_LOGIN vor oder
-- nach dem von ElvUI laeuft, ist nicht festgelegt: ist ElvUI noch nicht fertig,
-- warten wir per OnUpdate (hoechstens ELVUI_WAIT Sekunden) und starten sonst ohne.
-- Im Kampf wird nichts gebaut (geschuetzte Rahmen), sondern danach.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local Skin, UI, L = PM.Skin, PM.UI, PM.L
local format, strmatch, strlower, tonumber, tostring, ipairs =
   string.format, string.match, string.lower, tonumber, tostring, ipairs

local ELVUI_WAIT = 10        -- Sekunden, die wir auf ElvUI warten, bevor wir ohne es starten

local frame = CreateFrame("Frame")
PM.frame = frame
local waiting, waited = false, 0

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------

local function StartUI()
   if PM.ready then return true end
   if InCombatLockdown() then
      PM.startAfterCombat = true
      return false
   end
   Skin.Detect()
   UI.Create()
   PM.ready = true
   PM.startAfterCombat = nil
   return true
end
PM.StartUI = StartUI

local function WaitForElvUI(_, elapsed)
   waited = waited + elapsed
   if not Skin.ElvUIPending() or waited >= ELVUI_WAIT then
      frame:SetScript("OnUpdate", nil)
      waiting = false
      StartUI()
   end
end

local function TryStart()
   if PM.ready then return end
   if Skin.ElvUIPending() then
      if not waiting then
         waiting, waited = true, 0
         frame:SetScript("OnUpdate", WaitForElvUI)
      end
      return
   end
   StartUI()
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

local EVENTS = {
   "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
   "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
}
for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end

frame:SetScript("OnEvent", PM.Guard("OnEvent", function(self, event, arg1)
   if event == "ADDON_LOADED" then
      if arg1 == ADDON then
         PM.InitDB()
         self:UnregisterEvent("ADDON_LOADED")
      end
   elseif event == "PLAYER_LOGIN" then
      TryStart()
   elseif event == "PLAYER_REGEN_DISABLED" then
      if PM.ready then UI.EnterCombat() end
   elseif event == "PLAYER_REGEN_ENABLED" then
      if PM.startAfterCombat then StartUI() end
      if PM.ready then UI.LeaveCombat() end
   else
      -- SKILL_LINES_CHANGED, SPELLS_CHANGED, LEARNED_SPELL_IN_TAB: unser eigenes Lesen der
      -- Fertigkeiten (Aufklappen/Zuklappen) loest SKILL_LINES_CHANGED aus; das ignorieren wir.
      if PM.ready and not PM.EventsIgnored() then UI.MarkStale() end
   end
end))

-- ---------------------------------------------------------------------------
-- Chatbefehle
-- ---------------------------------------------------------------------------

local function OnOff(value)
   return value and L.on or L.off
end

local function ParseOnOff(text)
   text = strlower(text or "")
   if text == "on" or text == "an" or text == "1" or text == "true" then return true end
   if text == "off" or text == "aus" or text == "0" or text == "false" then return false end
   return nil
end

-- Nach einer Einstellung: Masse und Liste neu bestimmen (auch fuer die ElvUI-Optionen). Im
-- Kampf wartet das bis nach dem Kampf (UI.Relayout).
function PM.Changed()
   if PM.ready then UI.Relayout() end
end

-- /berufe list: zeigt, was erkannt wurde (hilft bei Fehlern in anderen Sprachen)
local function List()
   local skills, order = PM.ReadSkills()
   local known = PM.ReadSpellbook()
   PM.Print(L.listHeader)
   if #order == 0 then
      PM.Print(L.listNone)
      return
   end
   for _, skill in ipairs(order) do
      local def = PM.IdentifySkill(skill.name)
      if def then
         local entry = PM.Resolve(def, skills, known)
         local what = entry and entry.action or L.listNoAction
         if PM.db.abilities and (def.asAbility or def.kind == "tracking") then
            what = L.listAsAbility      -- Angeln / die Suche steht bei den Faehigkeiten
         end
         PM.Print(format(L.listMatched, skill.name, def.key .. " / " .. tostring(what), skill.rank, skill.maxRank))
      else
         PM.Print(format(L.listUnmatched, skill.name, skill.rank, skill.maxRank))
      end
   end
   local smelting = PM.Resolve(PM.PROFESSION_BY_KEY.smelting, skills, known)
   if smelting then
      PM.Print(format(L.listMatched, smelting.name, "smelting / " .. tostring(smelting.action), smelting.rank, smelting.maxRank))
   end
   -- bekannte aktive Faehigkeiten (nur mit der Einstellung "abilities" in der Liste)
   for _, def in ipairs(PM.ABILITIES) do
      local ability = PM.ResolveAbility(def, skills, known)
      if ability then
         PM.Print(format(L.listAbility, ability.name, def.key, PM.db.abilities and L.on or L.off))
      end
   end
end

local SORT_LABELS = { cat = "sortcat", alpha = "sortalpha", rank = "sortrank" }
local DIR_LABELS = { auto = "dirauto", up = "dirup", down = "dirdown" }
local COMPACT_LABELS = { off = "compactoff", button = "compactbutton", all = "compactall" }

local function Command(msg)
   local cmd, rest = strmatch(msg or "", "^%s*(%S*)%s*(.-)%s*$")
   cmd = strlower(cmd or "")
   rest = rest or ""
   local db = PM.db

   if cmd == "" or cmd == "toggle" then
      if PM.ready then
         UI.Toggle()
      elseif InCombatLockdown() then
         -- Anmeldung/Neuladen im Kampf: die Oberflaeche entsteht erst nach dem Kampf
         UIErrorsFrame:AddMessage(L.combat, 1, 0.3, 0.3)
      end
   elseif cmd == "list" then
      List()
   elseif cmd == "sort" then
      rest = strlower(rest)
      if SORT_LABELS[rest] then
         db.sort = rest
         PM.Print(format(L.setSort, L[SORT_LABELS[rest]]))
         PM.Changed()
      else
         PM.Print(L.help)
      end
   elseif cmd == "headers" then
      local v = ParseOnOff(rest)
      if v == nil then PM.Print(L.help) return end
      db.headers = v
      PM.Print(format(L.setHeaders, OnOff(v)))
      PM.Changed()
   elseif cmd == "ranks" then
      local v = ParseOnOff(rest)
      if v == nil then PM.Print(L.help) return end
      db.ranks = v
      PM.Print(format(L.setRanks, OnOff(v)))
      PM.Changed()
   elseif cmd == "compact" then
      rest = strlower(rest)
      if COMPACT_LABELS[rest] then
         db.compact = rest
         PM.Print(format(L.setCompact, L[COMPACT_LABELS[rest]]))
         PM.Changed()
      else
         PM.Print(L.help)
      end
   elseif cmd == "abilities" then
      local v = ParseOnOff(rest)
      if v == nil then PM.Print(L.help) return end
      db.abilities = v
      PM.Print(format(L.setAbilities, OnOff(v)))
      PM.Changed()
   elseif cmd == "direction" then
      rest = strlower(rest)
      if DIR_LABELS[rest] then
         db.direction = rest
         PM.Print(format(L.setDirection, L[DIR_LABELS[rest]]))
      else
         PM.Print(L.help)
      end
   elseif cmd == "scale" then
      if Skin.elvui then
         PM.Print(L.scaleElvUI)
         return
      end
      local n = tonumber((rest:gsub(",", ".")))
      if not n or n ~= n or n < 0.5 or n > 2 then
         PM.Print(L.scaleRange)
         return
      end
      if InCombatLockdown() then
         PM.Print(L.combat)
         return
      end
      db.scale = n
      PM.Print(format(L.setScale, n))
      if PM.ready then UI.ApplyScale(true) end
   elseif cmd == "unlock" or cmd == "lock" then
      if Skin.elvui then
         PM.Print(L.lockedElvUI)
         return
      end
      db.locked = (cmd == "lock")
      PM.Print(db.locked and L.locked or L.unlocked)
      if PM.ready then UI.ApplyLock() end
   elseif cmd == "reset" then
      db.pos = nil
      if PM.ready then UI.ResetPosition() end
      PM.Print(L.resetDone)
   elseif cmd == "debug" then
      PM.debug = not PM.debug
      PM.Print(PM.debug and L.debugOn or L.debugOff)
   else
      PM.Print(L.help)
   end
end
PM.Command = Command

SLASH_PROFESSIONMENU1 = "/berufe"
SLASH_PROFESSIONMENU2 = "/profmenu"
SlashCmdList["PROFESSIONMENU"] = PM.Guard("Command", Command)
