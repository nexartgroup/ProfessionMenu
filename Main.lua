-- Main.lua
-- ---------------------------------------------------------------------------
-- Ereignisse, Start und Chatbefehle.
--
-- Start: SavedVariables stehen bei ADDON_LOADED bereit. Die Oberflaeche wird bei PLAYER_LOGIN
-- gebaut. Im Kampf wird nichts gebaut (geschuetzte Rahmen), sondern danach.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local UI, L = PM.UI, PM.L
local format, strmatch, strlower, tonumber, tostring, ipairs =
   string.format, string.match, string.lower, tonumber, tostring, ipairs

local frame = CreateFrame("Frame")
PM.frame = frame

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------

local function StartUI()
   if PM.ready then return true end
   if InCombatLockdown() then
      PM.startAfterCombat = true
      return false
   end
   UI.Create()
   PM.ready = true
   PM.startAfterCombat = nil
   return true
end
PM.StartUI = StartUI

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

local EVENTS = {
   "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
   "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
   -- Lager: Inhalt der Taschen, nachgeladene Gegenstandsnamen, das Berufsfenster meldet sich
   "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
   "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
}
-- einzeln geschuetzt: kennt der Client ein Ereignis nicht, fehlt nur dieses
for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end

local TRADE_SKILL_EVENTS = {
   TRADE_SKILL_SHOW = true, TRADE_SKILL_LIST_UPDATE = true, TRADE_SKILL_DATA_SOURCE_CHANGED = true,
}

-- Gegenstaende, deren Name oder Symbol in der Liste stehen kann (Lager-Objekte und ihr Material)
local campItems
local function IsCampItem(id)
   if not campItems then
      campItems = {}
      for _, def in ipairs(PM.CAMP) do
         for _, item in ipairs(PM.Camp.Items(def)) do campItems[item] = true end
         for _, reagent in ipairs(def.reagents) do campItems[reagent[1]] = true end
         if def.tool then campItems[def.tool] = true end
      end
   end
   return campItems[id] == true
end

frame:SetScript("OnEvent", PM.Guard("OnEvent", function(self, event, arg1)
   if event == "ADDON_LOADED" then
      if arg1 == ADDON then
         PM.InitDB()
         self:UnregisterEvent("ADDON_LOADED")
      end
   elseif event == "PLAYER_LOGIN" then
      StartUI()
      if PM.RegisterOptions then PM.Guard("Options", PM.RegisterOptions)() end
      PM.Camp.Prime()
      PM.RememberCharacter()
   elseif event == "PLAYER_REGEN_DISABLED" then
      if PM.ready then UI.EnterCombat() end
   elseif event == "PLAYER_REGEN_ENABLED" then
      if PM.startAfterCombat then StartUI() end
      if PM.ready then UI.LeaveCombat() end
   elseif TRADE_SKILL_EVENTS[event] then
      -- wartet ein Klick auf "herstellen" darauf, dass das Berufsfenster bereit ist?
      PM.Camp.OnTradeSkill()
   elseif event == "GET_ITEM_INFO_RECEIVED" then
      -- der Client hat einen Gegenstand nachgeladen: nur die eigenen betreffen die Liste
      if PM.ready and IsCampItem(arg1) then UI.MarkStale() end
   else
      -- SKILL_LINES_CHANGED, SPELLS_CHANGED, LEARNED_SPELL_IN_SKILL_LINE: die Berufe haben sich geaendert;
      -- BAG_UPDATE_DELAYED: der Inhalt der Taschen (Lager-Objekte, Material)
      if event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then PM.RememberCharacter() end
      if PM.ready then UI.MarkStale() end
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

-- Nach einer Einstellung: Masse und Liste neu bestimmen (auch fuer das Einstellungsfenster). Im
-- Kampf wartet das bis nach dem Kampf (UI.Relayout).
function PM.Changed()
   if PM.ready then
      UI.ApplyLock()        -- das Haekchen "Knopf sperren" im Einstellungsfenster aendert nur den Wert
      UI.Relayout()
   end
end

-- /berufe list: zeigt, was erkannt wurde (hilft bei Fehlern)
local function List()
   local raws = PM.ReadProfessions()
   PM.Print(L.listHeader)
   if #raws == 0 then
      PM.Print(L.listNone)
      return
   end
   for _, raw in ipairs(raws) do
      PM.Print(format(L.listLine, raw.name, tostring(raw.skillLine), raw.rank, raw.maxRank))
      for _, spell in ipairs(raw.spells) do
         local flags = (spell.passive and " [passive]" or "") .. (spell.window and " [window]" or "")
         PM.Print(format(L.listSpell, tostring(spell.id), tostring(spell.name), flags))
      end
   end
end

-- /berufe alts: die gemerkten Charaktere des Kontos und ihre Berufe; /berufe alts clear vergisst die anderen
local function Alts(rest)
   if strlower(rest) == "clear" then
      PM.ForgetCharacters()
      PM.Print(L.altsCleared)
      PM.Changed()
      return
   end
   PM.Print(L.altsHeader)
   local lines = PM.CharacterLines()
   if #lines == 0 then PM.Print(L.altsNone) end
   for _, line in ipairs(lines) do PM.Print("  " .. line) end
end

local SORT_LABELS = { cat = "sortcat", alpha = "sortalpha", rank = "sortrank" }
local DIR_LABELS = { auto = "dirauto", up = "dirup", down = "dirdown" }
local COMPACT_LABELS = { off = "compactoff", button = "compactbutton", all = "compactall" }
local ACTIVITY_LABELS = { sub = "actsub", list = "actlist", off = "actoff" }
local CAMP_LABELS = { auto = "campauto", all = "campall", off = "campoff" }

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
   elseif cmd == "alts" or cmd == "twinks" then
      Alts(rest)
   elseif cmd == "diag" or cmd == "probe" then
      PM.Diag.Run()
   elseif cmd == "config" or cmd == "options" then
      if not (PM.OpenOptions and PM.OpenOptions()) then PM.Print(L.configMissing) end
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
   elseif cmd == "unlearned" then
      local v = ParseOnOff(rest)
      if v == nil then PM.Print(L.help) return end
      db.unlearned = v
      PM.Print(format(L.setUnlearned, OnOff(v)))
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
   elseif cmd == "activities" then
      rest = strlower(rest)
      if ACTIVITY_LABELS[rest] then
         db.activities = rest
         PM.Print(format(L.setActivities, L[ACTIVITY_LABELS[rest]]))
         PM.Changed()
      else
         PM.Print(L.help)
      end
   elseif cmd == "camp" then
      rest = strlower(rest)
      if CAMP_LABELS[rest] then
         db.camp = rest
         PM.Print(format(L.setCamp, L[CAMP_LABELS[rest]]))
         PM.Changed()
      else
         PM.Print(L.help)
      end
   elseif cmd == "direction" then
      rest = strlower(rest)
      if DIR_LABELS[rest] then
         db.direction = rest
         PM.Print(format(L.setDirection, L[DIR_LABELS[rest]]))
      else
         PM.Print(L.help)
      end
   elseif cmd == "scale" then
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
