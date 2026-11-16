-- Camp.lua
-- ---------------------------------------------------------------------------
-- Lager (WoW: Forever): Lagerfeuer, Zelt und die anderen Lager-Objekte der Berufe (Daten: PM.CAMP).
--
-- Jedes Objekt ist ein Gegenstand. Liegt er im Inventar, stellt ein Klick ihn auf (sichere Aktion
-- "item"). Liegt er nicht dort, kennt der Spieler den Beruf mit genug Fertigkeit und ist das Material
-- im Inventar, stellt ein Klick ihn her. Fehlt Material, erscheint nur die Grundfunktion (das
-- Lagerfeuer), abgedunkelt und mit Hinweis, was fehlt; alles andere bleibt weg (Einstellung camp = "all"
-- zeigt auch das).
--
-- Herstellen
--   C_TradeSkillUI.CraftRecipe wirkt nur, wenn das Fenster des Berufs offen und bereit ist. Die Zeile
--   traegt deshalb als sichere Aktion den Zauber, der das Fenster oeffnet. Ist das Fenster schon offen,
--   stellt der Klick sofort her. Sonst oeffnet er es; sobald der Beruf bereit ist (TRADE_SKILL_SHOW,
--   TRADE_SKILL_LIST_UPDATE), wird das Rezept gewaehlt und das Herstellen versucht. Verlangt der Client
--   dafuer einen Tastendruck, geschieht nichts: dann bittet eine Meldung um einen zweiten Klick (das
--   Fenster ist nun offen, der Klick stellt sofort her). So arbeitet auch FishFry.
--
-- Nichts hier fasst Rahmen an: Evaluate/ForProfession/TopLevel liefern reine Daten fuer Core und UI.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local pairs, ipairs, type, tostring, tonumber, pcall, format = pairs, ipairs, type, tostring, tonumber, pcall, string.format
local L = PM.L

local Camp = {}
PM.Camp = Camp

local PENDING_SECONDS = 15     -- so lange wartet ein Klick darauf, dass das Berufsfenster bereit wird
local WATCH_SECONDS = 20       -- so lange wird auf das Ergebnis eines Herstellens gewartet

-- ---------------------------------------------------------------------------
-- Zugriff auf das Spiel (jeder Aufruf geschuetzt)
-- ---------------------------------------------------------------------------

local function Now()
   return _G.GetTime and _G.GetTime() or 0
end

-- Zaehlt alle Gegenstaende in den Taschen (Rucksack, Taschen, Reagenzientasche): { [Gegenstand] = Anzahl }.
-- Gezaehlt wird Platz fuer Platz statt mit GetItemCount: so stimmen die Zahlen auch fuer Gegenstaende, die
-- der Client noch nicht geladen hat.
function Camp.Scan()
   local counts = {}
   local api = _G.C_Container
   if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return counts, false end
   local last = tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 5
   for bag = 0, last do
      local ok, slots = pcall(api.GetContainerNumSlots, bag)
      slots = ok and tonumber(slots) or 0
      for slot = 1, slots do
         local good, info = pcall(api.GetContainerItemInfo, bag, slot)
         if good and type(info) == "table" then
            local id = tonumber(info.itemID)
            if id then counts[id] = (counts[id] or 0) + (tonumber(info.stackCount) or 1) end
         end
      end
   end
   return counts, true
end

local function Faction()
   if not _G.UnitFactionGroup then return nil end
   local ok, faction = pcall(_G.UnitFactionGroup, "player")
   return ok and faction or nil
end

-- Meldet das Spiel den Gegenstand als benutzbar? (false nur bei einem klaren Nein)
local function Usable(id)
   local api = _G.C_Item
   if api and api.IsUsableItem then
      local ok, usable = pcall(api.IsUsableItem, id)
      if ok and usable == false then return false end
   end
   return true
end

-- Verbleibende Abklingzeit des Gegenstands in Sekunden (0: keine).
local function Cooldown(id)
   local api = _G.C_Container
   if api and api.GetItemCooldown then
      local ok, start, duration = pcall(api.GetItemCooldown, id)
      if ok and type(start) == "number" and type(duration) == "number" and start > 0 and duration > 1.5 then
         local left = start + duration - Now()
         if left > 0 then return left end
      end
   end
   return 0
end

local function RecipeLearned(recipe)
   local api = _G.C_TradeSkillUI
   if not (recipe and api and api.GetRecipeInfo) then return nil end
   local ok, info = pcall(api.GetRecipeInfo, recipe)
   if ok and type(info) == "table" then return info.learned end
   return nil
end

local function After(seconds, fn)
   local timer = _G.C_Timer
   if timer and timer.After then
      timer.After(seconds, PM.Guard("CampTimer", fn))
      return true
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Zustand der Lager-Objekte
-- ---------------------------------------------------------------------------

-- Alle Gegenstaende, die dieses Objekt sein kann (das Banner gibt es je Fraktion).
function Camp.Items(def)
   if def.items then return { def.items.Horde, def.items.Alliance } end
   return { def.item }
end

-- Das Rezept, das ein Klick herstellt. Banner: das Rezept, das das Spiel als erlernt meldet, sonst das der
-- eigenen Fraktion. Schlug ein Versuch fehl, merkt Camp.prefer das andere vor.
Camp.prefer = {}

function Camp.Recipe(def)
   if not def.recipes then return def.recipe end
   if Camp.prefer[def.key] then return Camp.prefer[def.key] end
   for _, recipe in pairs(def.recipes) do
      if RecipeLearned(recipe) == true then return recipe end
   end
   return def.recipes[Faction() or ""] or def.recipe
end

local function State(def, ctx)
   local counts = ctx.counts
   local st = { def = def, count = 0, reagents = {} }
   for _, id in ipairs(Camp.Items(def)) do
      local n = counts[id] or 0
      if n > 0 and not st.useItem then st.useItem = id end
      st.count = st.count + n
   end
   st.item = st.useItem or (def.items and def.items[ctx.faction or ""]) or def.item

   local prof = def.prof and ctx.profs[def.prof] or nil
   st.prof = prof
   st.rankOK = (prof ~= nil and prof.rank >= def.skill) and true or false

   local ready = true
   for _, reagent in ipairs(def.reagents) do
      local have = counts[reagent[1]] or 0
      local good = have >= reagent[2]
      st.reagents[#st.reagents + 1] = { id = reagent[1], need = reagent[2], have = have, ok = good }
      ready = ready and good
   end
   if def.tool then
      local have = counts[def.tool] or 0
      st.tool = { id = def.tool, need = 1, have = have, ok = have > 0 }
      ready = ready and have > 0
   end

   if st.count > 0 then
      st.mode = "place"
      st.usable = Usable(st.item)
      st.cooldown = Cooldown(st.item)
   elseif def.bagOnly then
      st.mode = nil
   elseif st.rankOK then
      st.mode = ready and "craft" or "lack"
   end
   return st
end

-- Bewertet alle Lager-Objekte. profs: { [Berufsschluessel] = { name, rank, skillLine, openSpell } }.
function Camp.Evaluate(profs, db)
   db = db or PM.db
   local ctx = { profs = profs or {}, counts = Camp.Scan(), faction = Faction(), all = db.camp == "all", states = {} }
   for _, def in ipairs(PM.CAMP) do
      ctx.states[def.key] = State(def, ctx)
   end
   return ctx
end

local function Entry(st, cat, order)
   local def = st.def
   local entry = {
      key = "camp_" .. def.key, cat = cat, order = order,
      name = PM.ItemName(st.item, def.name),
      icon = PM.ItemIcon(st.item) or (def.chain == "fire" and PM.CAMP_FIRE_ICON or PM.CAMP_ICON),
      rank = 0, maxRank = 0, kind = st.mode, camp = st,
   }
   if st.mode == "place" then
      entry.item = st.item
      entry.tag = "x" .. st.count
      entry.dim = ((not st.usable) or st.cooldown > 0) or nil
   elseif st.mode == "craft" then
      entry.action = st.prof.openSpell            -- oeffnet das Berufsfenster (nil: der Beruf hat keinen solchen Zauber)
      entry.skillLine = st.prof.skillLine
      entry.craft = { recipe = Camp.Recipe(def), def = def, name = entry.name, prof = st.prof.name }
      entry.tag = L.tag_craft
   else
      entry.tag = L.tag_missing
      entry.dim = true
   end
   return entry
end

-- Ist in dieser Kette irgendetwas aufstellbar oder herstellbar?
local function ChainActionable(ctx, chain)
   for _, def in ipairs(PM.CAMP) do
      if def.chain == chain then
         local mode = ctx.states[def.key].mode
         if mode == "place" or mode == "craft" then return true end
      end
   end
   return false
end

-- Die Lager-Objekte eines Berufs (fuer sein Untermenue): alles, was aufstellbar oder herstellbar ist;
-- fehlt Material, nur die Grundfunktion (wenn sonst nichts aus ihrer Kette geht) oder mit camp = "all" alles.
function Camp.ForProfession(ctx, profKey)
   local list = {}
   for _, def in ipairs(PM.CAMP) do
      if def.prof == profKey then
         local st = ctx.states[def.key]
         local show = st.mode == "place" or st.mode == "craft"
         if st.mode == "lack" then
            show = ctx.all or (def.important and not ChainActionable(ctx, def.chain))
         end
         if show then list[#list + 1] = Entry(st, nil, #list + 1) end
      end
   end
   return list
end

-- Die Zeilen der Kategorie "Lager": je Kette die beste. Aufstellbar geht vor herstellbar, hoehere Stufe vor
-- niedriger; fehlt Material, die niedrigste Stufe (nur Grundfunktionen oder camp = "all").
function Camp.TopLevel(ctx)
   local chains, order = {}, {}
   for _, def in ipairs(PM.CAMP) do
      local chain = chains[def.chain]
      if not chain then
         chain = { defs = {} }
         chains[def.chain] = chain
         order[#order + 1] = chain
      end
      chain.defs[#chain.defs + 1] = def
      if def.important then chain.important = true end
   end

   local list = {}
   for index, chain in ipairs(order) do
      local place, craft, lack
      for _, def in ipairs(chain.defs) do
         local st = ctx.states[def.key]
         if st.mode == "place" then place = st
         elseif st.mode == "craft" then craft = st
         elseif st.mode == "lack" and not lack then lack = st end
      end
      local best = place or craft
      if not best and lack and (ctx.all or chain.important) then best = lack end
      if best then list[#list + 1] = Entry(best, "camp", index) end
   end
   return list
end

-- Was fehlt? Liste aus "Name 0/1" (fuer Tooltip und Meldung).
function Camp.Missing(st)
   local parts = {}
   for _, reagent in ipairs(st.reagents) do
      if not reagent.ok then
         parts[#parts + 1] = format("%s %d/%d", PM.ItemName(reagent.id), reagent.have, reagent.need)
      end
   end
   if st.tool and not st.tool.ok then parts[#parts + 1] = PM.ItemName(st.tool.id) end
   return parts
end

-- Alle Gegenstaende der Daten beim Client anfordern, damit Namen und Symbole bereitliegen.
function Camp.Prime()
   local api = _G.C_Item
   if not (api and api.RequestLoadItemDataByID) then return end
   local seen = {}
   local function request(id)
      if id and not seen[id] then
         seen[id] = true
         pcall(api.RequestLoadItemDataByID, id)
      end
   end
   for _, def in ipairs(PM.CAMP) do
      for _, id in ipairs(Camp.Items(def)) do request(id) end
      for _, reagent in ipairs(def.reagents) do request(reagent[1]) end
      request(def.tool)
   end
end

-- ---------------------------------------------------------------------------
-- Herstellen
-- ---------------------------------------------------------------------------

local function Ready()
   local api = _G.C_TradeSkillUI
   if api and api.IsTradeSkillReady then
      local ok, ready = pcall(api.IsTradeSkillReady)
      return ok and ready == true
   end
   return true
end

local function CountOf(def)
   local counts = Camp.Scan()
   local total = 0
   for _, id in ipairs(Camp.Items(def)) do total = total + (counts[id] or 0) end
   return total
end

local function Casting()
   if not _G.UnitCastingInfo then return false end
   local ok, name = pcall(_G.UnitCastingInfo, "player")
   return (ok and name ~= nil) and true or false
end

-- Prueft, ob ein Versuch etwas bewirkt hat; sonst die passende Meldung.
function Camp.Check()
   local watch = Camp.watch
   if not watch then return end
   if CountOf(watch.craft.def) > watch.before then
      Camp.watch = nil
      return
   end
   if Casting() and Now() - watch.t < WATCH_SECONDS then
      After(1, Camp.Check)
      return
   end
   Camp.watch = nil
   local def = watch.craft.def
   if watch.byClick then
      -- Der Klick kam bei offenem Fenster und es geschah trotzdem nichts. Banner: beim naechsten Mal das andere Rezept.
      if def.recipes then
         for _, recipe in pairs(def.recipes) do
            if recipe ~= watch.craft.recipe then Camp.prefer[def.key] = recipe end
         end
      end
      PM.Print(format(L.camp_failed, watch.craft.name))
   else
      PM.Print(format(L.camp_again, watch.craft.name))
   end
end

-- Stellt her (das Fenster des Berufs ist offen und bereit). byClick: direkt aus einem Klick.
function Camp.Craft(craft, byClick)
   local api = _G.C_TradeSkillUI
   if not (api and api.CraftRecipe) then
      PM.Print(L.camp_nocraft)
      return false
   end
   local before = CountOf(craft.def)
   if not byClick and api.OpenRecipe then pcall(api.OpenRecipe, craft.recipe) end
   local ok, err = pcall(api.CraftRecipe, craft.recipe, 1)
   PM.Trace("CraftRecipe", craft.recipe, ok, err)
   Camp.watch = { craft = craft, before = before, t = Now(), byClick = byClick }
   if not After(1.2, Camp.Check) then Camp.watch = nil end
   return ok
end

-- Klick auf eine Zeile "herstellen" (aus PostClick, also mit Tastendruck). wasOpen: das Fenster des Berufs
-- war vor dem Klick schon offen (dann hat die Zeile den oeffnenden Zauber diesmal nicht gewirkt).
function Camp.Click(entry, wasOpen)
   local craft = entry.craft
   Camp.pending = nil
   if wasOpen and Ready() then
      Camp.Craft(craft, true)
      return
   end
   Camp.pending = { craft = craft, skillLine = entry.skillLine, t = Now(), spell = entry.action ~= nil }
   if entry.action then
      After(1.5, Camp.Poll)
   else
      -- kein Zauber, der das Fenster oeffnet (Sammelberufe): die Berufsuebersicht zeigen, der Spieler waehlt dort den Beruf
      if PM.UI and PM.UI.ShowOverview then PM.UI.ShowOverview() end
      PM.Print(format(L.camp_openprof, craft.prof, craft.name))
   end
end

-- Netz unter dem Ereignisweg: der Klick hat den Beruf mit seinem Zauber geoeffnet, aber kein Ereignis hat das
-- Herstellen ausgeloest (oder das Spiel nennt fuer das offene Fenster eine andere Berufsnummer als
-- GetProfessionInfo). Steht ein Berufsfenster bereit, wird es jetzt versucht.
function Camp.Poll()
   local pending = Camp.pending
   if not (pending and pending.spell) then return end
   local frame = _G.ProfessionsFrame
   if frame and frame:IsShown() and Ready() then
      Camp.pending = nil
      Camp.Craft(pending.craft, false)
   end
end

-- Das Berufsfenster meldet sich: wartet ein Klick darauf, jetzt das Rezept waehlen und herstellen.
function Camp.OnTradeSkill()
   local pending = Camp.pending
   if not pending then return end
   if Now() - pending.t > PENDING_SECONDS then
      Camp.pending = nil
      return
   end
   if not (PM.IsProfessionOpen(pending.skillLine) and Ready()) then return end
   Camp.pending = nil
   Camp.Craft(pending.craft, false)
end
