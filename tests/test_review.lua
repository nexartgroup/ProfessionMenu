-- tests/test_review.lua
-- ---------------------------------------------------------------------------
-- Regressionstests zu Fehlern und Testluecken, die bei der Durchsicht des Addons gefunden wurden (Erkennung der
-- Berufe, Kampfsperre, Pixelraster, Eingaben aus SavedVariables).
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function rowFor(PM, key)
      for _, r in ipairs(F.rows(PM)) do
         if r.key == key then return r.row end
      end
   end

   local function elvui(opts)
      local PM, M = F.boot(H, opts)
      H.allowFrames({ "RightChatPanel" })
      return PM, M, ElvUI[1]
   end

   -- ======================================================================
   H.section("Fertigkeitenfenster: nur zeigen, nie schliessen; Liste zuerst zu")
   -- ======================================================================

   H.test("right click with the Skills page already visible leaves the window open (ToggleCharacter would close it)", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      H.allowFrames({ "SkillFrame" })
      local skills = CreateFrame("Frame", "SkillFrame", UIParent)
      skills:Show()
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"), "RightButton")
      H.deepEq(M.toggles, {}, "no toggle: the Skills page is already visible")
      H.falsy(F.isOpen(PM))
   end)

   H.test("right click with the Skills page hidden (or not loaded) opens it", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      H.allowFrames({ "SkillFrame" })
      local skills = CreateFrame("Frame", "SkillFrame", UIParent)
      skills:Hide()
      F.open(PM)
      M.Click(rowFor(PM, "alchemy"), "RightButton")
      H.deepEq(M.toggles, { "SkillFrame" })
   end)

   H.test("an error in ToggleCharacter cannot leave the list open: the list closes first", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      F.open(PM)
      rawset(_G, "ToggleCharacter", function() error("custom character frame failed") end)
      M.Click(rowFor(PM, "alchemy"), "RightButton")
      H.falsy(F.isOpen(PM), "the list is closed although the skills window code failed")
      H.eq(F.chatCount(M, "Error in RowPostClick"), 1)
      H.allowGuardErrors()
   end)

   -- ======================================================================
   H.section("Die offene Liste folgt dem Knopf nicht: sie schliesst sich, wenn er sich aendert")
   -- ======================================================================

   H.test("scale change, reset and dragging the unlocked button close an open list", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      F.open(PM)
      M.Slash("/berufe scale 1.5")
      H.falsy(F.isOpen(PM), "scale")
      F.open(PM)
      M.Slash("/berufe reset")
      H.falsy(F.isOpen(PM), "reset")
      M.Slash("/berufe unlock")
      F.open(PM)
      M.Drag(PM.UI.GetButton(), -50, 40)
      H.falsy(F.isOpen(PM), "drag")
   end)

   H.test("with ElvUI the reset closes an open list too", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      F.open(PM)
      M.Slash("/berufe reset")
      H.falsy(F.isOpen(PM))
   end)

   -- ======================================================================
   H.section("Knopf: Tooltip und Rahmen nach dem Klick")
   -- ======================================================================

   H.test("the button tooltip is gone once the click has opened the list", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Hover(PM.UI.GetButton())
      M.Click(PM.UI.GetButton())
      H.truthy(F.isOpen(PM))
      H.falsy(GameTooltip:IsShown())
   end)

   H.test("closing the list by click keeps the hover border while the mouse is still on the button", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local button = PM.UI.GetButton()
      M.Hover(button)
      M.Click(button)
      M.Click(button)
      H.falsy(F.isOpen(PM))
      local r = button:GetBackdropBorderColor()
      H.near(r, 0.99, 1e-6, "accent red channel")
   end)

   H.test("closing the list does not hide a tooltip that belongs to another frame", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      F.open(PM)
      GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
      GameTooltip:AddLine("foreign")
      GameTooltip:Show()
      PM.UI.Close()
      H.truthy(GameTooltip:IsShown())
   end)

   -- ======================================================================
   H.section("Breite: aendert sich nicht mit den Stufen, Namen passen immer")
   -- ======================================================================

   H.test("the list width does not change when a rank grows by a digit or a profession reaches the next tier", function()
      local PM, M = F.boot(H, { learned = { leatherworking = { 9, 75 }, alchemy = { 1, 75 } } })
      F.open(PM)
      local menu = PM.UI.GetMenu()
      local w0 = menu:GetWidth()
      for _, step in ipairs({ { 99, 150 }, { 100, 150 }, { 300, 375 }, { 450, 450 } }) do
         M.SetSkillRank("Leatherworking", step[1], step[2])
         H.eq(menu:GetWidth(), w0, "rank " .. step[1] .. "/" .. step[2])
      end
   end)

   H.test("the name fits next to the reserved '450/450': label region >= text width for the widest names", function()
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local PM, M = F.boot(H, { locale = locale, learned = F.ORDER })
         F.open(PM)
         local menu = PM.UI.GetMenu()
         local S = PM.UI.sizes
         for _, r in ipairs(F.rows(PM)) do
            -- region of the name: from after the icon to the left edge of the rank column
            local nameWidth = r.row.text:GetStringWidth()
            local rankReserve = r.row.rank:GetStringWidth()
            local avail = menu:GetWidth() - S.pad * 2 - S.iconPad - S.icon - S.textGap - S.textGap - S.rankPad - rankReserve
            -- with the worst-case reserve the available space must cover the name even at 450/450
            H.truthy(avail >= nameWidth - 1e-6, locale .. " " .. r.key .. ": room " .. avail .. " < name " .. nameWidth)
         end
      end
   end)

   H.test("the button is as wide as the widest possible row, so the list never overhangs it", function()
      for _, learned in ipairs({ { "alchemy" }, { "leatherworking", "jewelcrafting" }, F.ORDER }) do
         local PM = F.boot(H, { locale = "deDE", learned = learned })
         F.open(PM)
         H.truthy(PM.UI.GetMenu():GetWidth() <= PM.UI.GetButton():GetWidth() + 1e-6, "list <= button")
         H.near(PM.UI.GetMenu():GetWidth(), PM.UI.GetButton():GetWidth(), 1e-6, "list == button")
      end
   end)

   H.test("rows show names on one line (SetWordWrap(false)) with the label anchored to the icon and the rank column", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      F.open(PM)
      H.eq(PM.UI.rows[1].text.__wordWrap, false)
   end)

   -- ======================================================================
   H.section("Zeilen: Umschalt/Strg/Alt-Klick wirkt, Attribute werden mit geleert")
   -- ======================================================================

   H.test("wildcard attributes (*type1, *spell1) are set for rows with a spell and cleared for unused rows", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      F.open(PM)
      for _, r in ipairs(F.rows(PM)) do
         H.eq(r.row:GetAttribute("*type1"), "spell", r.key)
         H.eq(r.row:GetAttribute("*spell1"), r.entry.action, r.key)
      end
      M.UnlearnSkill("Mining")
      M.UnlearnSpell("Mining")
      M.UnlearnSpell("Smelting")
      M.UnlearnSpell("Find Minerals")
      PM.UI.Refresh(true)
      for i = 2, 5 do
         H.eq(PM.UI.rows[i]:GetAttribute("*type1"), nil, "unused row " .. i)
         H.eq(PM.UI.rows[i]:GetAttribute("*spell1"), nil, "unused row " .. i)
      end
   end)

   -- ======================================================================
   H.section("Fertigkeitsfenster: nur die Ueberschriften der Berufe werden aufgeklappt")
   -- ======================================================================

   H.test("only the Professions and Secondary Skills headers are expanded and re-collapsed; Weapon/Class/Language headers stay untouched", function()
      local PM, M = F.boot(H, { learned = { "mining", "cooking" },
         collapsed = { Professions = true, ["Secondary Skills"] = true, ["Weapon Skills"] = true, ["Class Skills"] = true, Languages = true } })
      local before = M.SkillStates()
      M.calls.ExpandSkillHeader, M.calls.CollapseSkillHeader = 0, 0
      local entries = PM.Collect()
      H.eq(M.calls.ExpandSkillHeader, 2, "two expands: Professions and Secondary Skills")
      H.eq(M.calls.CollapseSkillHeader, 2, "two collapses")
      H.deepEq(M.SkillStates(), before, "states as before")
      local keys = {}
      for _, e in ipairs(entries) do keys[#keys + 1] = e.key end
      H.deepEq(keys, { "smelting", "mining", "cooking" })
   end)

   H.test("headers the addon does not recognise (unknown locale): all collapsed headers are expanded for the read, nothing is missed", function()
      local PM, M = F.boot(H, { learned = { "mining", "cooking" },
         collapsed = { Professions = true, ["Secondary Skills"] = true, ["Weapon Skills"] = true } })
      rawset(_G, "TRADE_SKILLS", "Unbekannt")
      rawset(_G, "SECONDARY_SKILLS", "Auch unbekannt:")
      local before = M.SkillStates()
      M.calls.ExpandSkillHeader, M.calls.CollapseSkillHeader = 0, 0
      local entries = PM.Collect()
      H.eq(M.calls.ExpandSkillHeader, 3, "all three")
      H.deepEq(M.SkillStates(), before)
      H.len(entries, 3)
   end)

   H.test("a character with only secondary skills has only one recognisable header: conservative path (all collapsed headers expanded)", function()
      local PM, M = F.boot(H, { learned = { "cooking" }, collapsed = { ["Secondary Skills"] = true, ["Weapon Skills"] = true } })
      M.calls.ExpandSkillHeader = 0
      local entries = PM.Collect()
      H.eq(M.calls.ExpandSkillHeader, 2)
      H.len(entries, 1)
   end)

   H.test("one of two headers no longer matches (odd colon): conservative path, nothing is missed", function()
      local PM, M = F.boot(H, { learned = { "mining", "cooking" },
         collapsed = { ["Secondary Skills"] = true, ["Weapon Skills"] = true } })
      rawset(_G, "SECONDARY_SKILLS", "Auch unbekannt:")      -- Professions still matches TRADE_SKILLS, Secondary does not
      M.calls.ExpandSkillHeader = 0
      local entries = PM.Collect()
      H.eq(M.calls.ExpandSkillHeader, 2, "both collapsed headers expanded")
      H.len(entries, 3, "cooking is found although its header was not recognised")
   end)

   H.test("the header test accepts the colon variants of SECONDARY_SKILLS (NBSP + colon, fullwidth colon)", function()
      for _, tail in ipairs({ ":", "\194\160:", "\239\188\154" }) do
         -- both headers must exist (a primary and a secondary skill), otherwise the addon takes the conservative path
         local PM, M = F.boot(H, { learned = { "cooking", "mining" },
            collapsed = { ["Secondary Skills"] = true, ["Weapon Skills"] = true } })
         rawset(_G, "SECONDARY_SKILLS", "Secondary Skills" .. tail)
         M.calls.ExpandSkillHeader = 0
         PM.Collect()
         H.eq(M.calls.ExpandSkillHeader, 1, "tail " .. tail:byte(1, -1))
      end
   end)

   -- ======================================================================
   H.section("Zauberbuch: ein Fehler beim Lesen verhindert das Oeffnen nicht")
   -- ======================================================================

   H.test("ReadSpellbook alone finds every spell of every tab, including the last one of a tab", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining", "fishing" },
         spellTabs = { { name = "General", spells = { "Attack", 2259 } }, { name = "Prof", spells = { 2575, 2656, 7620 } } } })
      local known = PM.ReadSpellbook()
      for _, name in ipairs({ "Attack", "Alchemy", "Mining", "Smelting", "Fishing" }) do
         H.truthy(known[name], "spellbook scan misses '" .. name .. "'")
      end
   end)

   H.test("a throwing spellbook API keeps the partial result, reports once and the list still opens (GetSpellInfo(name) fallback)", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "fishing" } })
      local orig = GetSpellTabInfo
      rawset(_G, "GetSpellTabInfo", function() error("another addon broke the spellbook") end)
      H.truthy(F.open(PM), "the list opens")
      rawset(_G, "GetSpellTabInfo", orig)
      H.deepEq(F.rowKeys(PM), { "alchemy", "fishing" }, "the fallback still finds the professions")
      H.eq(F.chatCount(M, "Error in ReadSpellbook"), 1)
      PM.UI.Close()
      rawset(_G, "GetSpellTabInfo", function() error("again") end)
      F.open(PM)
      H.eq(F.chatCount(M, "Error in ReadSpellbook"), 1, "reported only once")
      rawset(_G, "GetSpellTabInfo", orig)
      H.allowGuardErrors()
   end)

   H.test("a non-numeric offset/count from the spellbook tab (custom client) does not break the scan", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local orig = GetSpellTabInfo
      rawset(_G, "GetSpellTabInfo", function(tab) return "Tab", "tex", "x", "y" end)
      local known = PM.ReadSpellbook()
      rawset(_G, "GetSpellTabInfo", orig)
      H.eq(next(known), nil)
   end)

   H.test("when Rebuild throws, the next Refresh tries again (the signature is not stored too early)", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      F.open(PM)
      PM.UI.Close()
      M.LearnSkill("Mining", 10, 75, "Professions"); M.LearnSpell("Mining"); M.LearnSpell("Smelting")
      local orig = PM.UI.Rebuild
      PM.UI.Rebuild = function() error("boom") end
      pcall(PM.UI.Refresh)
      PM.UI.Rebuild = orig
      PM.UI.Refresh()
      H.deepEq(F.rowKeys(PM), { "alchemy", "smelting", "mining" })
      H.allowErrors()
   end)

   -- ======================================================================
   H.section("Befehle und gespeicherte Werte")
   -- ======================================================================

   H.test("/berufe scale nan and -nan neither store NaN nor raise", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      for _, word in ipairs({ "nan", "-nan", "inf" }) do
         M.Slash("/berufe scale " .. word)
      end
      H.eq(F.chatCount(M, "Error in"), 0)
      H.eq(PM.db.scale, 1)
   end)

   H.test("/berufe in combat before the UI exists tells the player (combat message), out of combat it stays quiet", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, combat = true })
      H.falsy(PM.ready)
      M.Slash("/berufe")
      H.eq(#M.uiErrors, 1)
      H.eq(M.uiErrors[1].text, "Not available in combat")
   end)

   H.test("truthy junk in boolean settings is replaced by real booleans", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { headers = "no", ranks = 0, locked = 1 } })
      H.eq(PM.db.headers, true)
      H.eq(PM.db.ranks, true)
      H.eq(PM.db.locked, true)
   end)

   H.test("with ranks off a rank-up while the list is open does not bring the rank text back", function()
      local PM, M = F.boot(H, { learned = { alchemy = { 100, 450 } } })
      M.Slash("/berufe ranks off")
      F.open(PM)
      M.SetSkillRank("Alchemy", 101)
      H.eq(F.rows(PM)[1].rank, "")
   end)

   H.test("UI.Open in combat returns false and touches nothing even when the list is unchanged", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      F.open(PM)
      PM.UI.Close()
      M.EnterCombat()
      H.eq(PM.UI.Open(), false)
      H.falsy(F.isOpen(PM))
      H.len(M.blocked, 0)
   end)

   H.test("a button whose centre is right of the screen middle but whose left edge is left of it aligns the list to the right", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, db = { direction = "up" } })
      local button, menu = PM.UI.GetButton(), PM.UI.GetMenu()
      local mid = UIParent:GetWidth() / 2
      button:ClearAllPoints()
      button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", mid - 20, 100)
      F.open(PM)
      H.eq((menu:GetPoint(1)), "BOTTOMRIGHT")
   end)

   -- ======================================================================
   H.section("Tooltip: 'Zauber nicht gefunden' statt 'passiv'")
   -- ======================================================================

   H.test("a profession whose spell is not in the spellbook says so in the tooltip (not 'passive')", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "skinning" }, noSpell = { "alchemy" } })
      F.open(PM)
      local alchemy, skinning = rowFor(PM, "alchemy"), rowFor(PM, "skinning")
      H.truthy(alchemy.entry.missing, "alchemy is flagged as missing its spell")
      H.falsy(skinning.entry.missing, "skinning has no spell by design")
      M.Enter(alchemy)
      H.truthy(GameTooltip:IsShown())
      local lines = {}
      for i = 1, GameTooltip:NumLines() do lines[#lines + 1] = _G["GameTooltipTextLeft" .. i]:GetText() end
      H.contains(lines, "Spell not found - left-click shows your skills")
      M.Leave(alchemy)
   end)

   -- ======================================================================
   H.section("ElvUI: Schrift folgt ElvUIs Groesse, Breiten und Farben werden neu gerechnet")
   -- ======================================================================

   H.test("font sizes are the element size plus ElvUI's base size minus 12", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      E.db.general = E.db.general or {}
      E.db.general.fontSize = 14
      E:UpdateFontTemplates()
      local _, size = PM.UI.rows[1].text:GetFont()
      H.eq(size, 14, "row name: 12 + 2")
      _, size = PM.UI.rows[1].rank:GetFont()
      H.eq(size, 13, "rank: 11 + 2")
      _, size = PM.UI.GetButton().text:GetFont()
      H.eq(size, 15, "button label: 13 + 2")
   end)

   H.test("a font change in ElvUI widens the button and the list (names are measured again)", function()
      local PM, M, E = elvui({ learned = { "leatherworking" }, elvui = true })
      F.open(PM)
      local w0 = PM.UI.GetButton():GetWidth()
      E.db.general = E.db.general or {}
      E.db.general.fontSize = 16
      E:UpdateFontTemplates()
      local w1 = PM.UI.GetButton():GetWidth()
      H.truthy(w1 > w0, "button wider: " .. w0 .. " -> " .. w1)
      H.near(PM.UI.GetMenu():GetWidth(), w1, 1e-6, "list as wide as the button")
   end)

   H.test("a profile switch (E:UpdateAll) re-measures and keeps the accent border of an open list", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      F.open(PM)
      E:UpdateAll()
      H.truthy(F.isOpen(PM))
      local r, g, b = PM.UI.GetButton():GetBackdropBorderColor()
      local ar, ag, ab = unpack(E.media.rgbvaluecolor)
      H.near(r, ar, 1e-6)
   end)

   H.test("a relayout request in combat waits for the end of combat (no protected call)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      M.EnterCombat()
      E.db.general = E.db.general or {}
      E.db.general.fontSize = 16
      E:UpdateFontTemplates()
      H.len(M.blocked, 0)
      M.LeaveCombat()
      H.len(M.blocked, 0)
   end)

   H.test("the value colour callback is guarded: an error in it cannot break ElvUI's UpdateMedia", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local fn
      for f in pairs(E.valueColorUpdateFuncs) do fn = f end
      H.truthy(fn)
      PM.UI.rows[1].hl = nil                       -- makes ApplyColors fail
      H.truthy(pcall(fn, "|cff", 1, 0, 0), "the registered function does not raise")
      H.allowGuardErrors()
   end)

   -- ======================================================================
   H.section("Menge der Bildschirmstellen")
   -- ======================================================================

   H.test("the pixel border of the list: sizes are whole pixels on a high-DPI grid (3024x1964, UI scale 0.7, ElvUI mult 0.5586)", function()
      local PM = elvui({ learned = { "leatherworking" }, elvui = { mult = (768 / 1964) / 0.7 } })
      local mult = (768 / 1964) / 0.7
      F.open(PM)
      for name, v in pairs(PM.UI.sizes) do
         local n = v / mult
         H.near(n, math.floor(n + 0.5), 1e-6, "sizes." .. name)
      end
      local w = PM.UI.GetMenu():GetWidth() / mult
      H.near(w, math.floor(w + 0.5), 1e-6, "list width")
      w = PM.UI.GetButton():GetWidth() / mult
      H.near(w, math.floor(w + 0.5), 1e-6, "button width")
   end)
end
