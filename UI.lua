-- UI.lua
-- ---------------------------------------------------------------------------
-- Knopf "Berufe" und die Ausklappliste.
--
-- Kampfsperre (das Wichtigste an diesem Aufbau)
--   Die Zeilen sind SecureActionButtons (type=spell, spell=<Zauber-Nummer>). Geschuetzte
--   Rahmen duerfen im Kampf nicht verschoben, ein- oder ausgeblendet oder umbelegt
--   werden, und dasselbe gilt fuer ihre Eltern und die Rahmen, an denen sie
--   verankert sind. Darum:
--     * Die Liste (menu) ist selbst ein SecureHandlerStateTemplate-Rahmen und
--       schliesst sich im Kampf von allein (Zustandstreiber "[combat]").
--     * Die Liste ist NUR an UIParent verankert, mit festen Abstaenden, die beim
--       Oeffnen aus der Lage des Knopfes berechnet werden. Der Knopf haengt deshalb
--       nicht in der geschuetzten Kette.
--     * Zeilen werden einmal angelegt (beim Anmelden, ausserhalb des Kampfes) und
--       danach nur ausserhalb des Kampfes umbelegt.
--     * Im Kampf bleibt der Knopf ruhig (abgedunkelt); Oeffnen wird abgelehnt.
--
-- Untermenues
--   Ein Beruf mit mehreren Taetigkeiten (Verhuetten und Suchen, Angeln und Fischglas ...) zeigt sie in einer
--   zweiten Liste (flyout) neben seiner Zeile, sobald die Maus darauf liegt. Fuer sie gilt dasselbe wie fuer
--   die Liste: eigener Zustandstreiber "[combat]", nur an UIParent verankert, Zeilen einmal angelegt und nur
--   ausserhalb des Kampfes umbelegt.
--
-- Klick-Zeitpunkt (neu gegenueber 3.3.5a)
--   Der Retail-Client feuert sichere Knoepfe standardmaessig beim NIEDERDRUECKEN der Taste
--   (CVar ActionButtonUseKeyDown). Unsere Zeilen reagieren auf das Loslassen, wie ein Menue es
--   erwartet; dafuer setzt jede Zeile das Attribut useOnKeyDown = false.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local Skin, L = PM.Skin, PM.L
local format, tinsert, max, tostring, tonumber, pairs, ipairs, type, pcall =
   string.format, table.insert, math.max, tostring, tonumber, pairs, ipairs, type, pcall

local UI = {}
PM.UI = UI

local MAX_ROWS, MAX_HEADERS, MAX_SUB = 24, 6, 14
local SWITCH_DELAY = 0.15    -- so lange muss die Maus auf einer anderen Zeile liegen, bevor das Untermenue wechselt
local WHITE = "Interface\\Buttons\\WHITE8X8"

local S                      -- Masse (UI-Einheiten, auf Pixel gerundet), siehe ComputeSizes
local button, menu, flyout
local rows, headers, subRows = {}, {}, {}
local hoverRow, hoverAt      -- Zeile der Liste unter der Maus und seit wann
local probeName, probeRank   -- unverankerte Schriftzeilen zum Messen von Texten
local signature
local pendingRebuild = false
local pendingRelayout = false
UI.rows, UI.headers, UI.subRows = rows, headers, subRows

function UI.GetButton() return button end
function UI.GetMenu() return menu end
function UI.GetFlyout() return flyout end

-- Masse nach dem Pixelraster. Wird beim Bauen berechnet, nicht beim Laden der Datei:
-- erst dann stehen UI-Skalierung und Bildschirmgroesse fest.
-- Verhaeltnisse: Knopf 4:1, Liste so breit wie der Knopf, Zeile 24.
local function ComputeSizes()
   local px = Skin.Px
   S = {
      buttonW = px(150), buttonH = px(37), buttonIcon = px(29), buttonPad = px(4), chevron = px(13.4),
      rowH = px(24), icon = px(22), iconPad = px(4.5), textGap = px(8), rankPad = px(6),
      header = px(18), headerPad = px(6), gap = px(4), menuGap = px(6.7),
      pad = Skin.Border(), line = Skin.Mult(),
      -- "nur Symbole": quadratische Zellen fuer Knopf und Zeilen, Luecke zwischen den Kategorien
      -- Symbolfeld: Rand = ein ganzzahliges Vielfaches eines Pixels, damit das Symbol in Knopf und
      -- Zeile mittig auf ganzen Pixeln sitzt (cell - cellIcon ist dann gerade)
      cell = px(32), cellIcon = px(32) - 2 * px(2), catGap = px(5),
      -- Untermenue: Winkel am Zeilenrand, Abstand zur Liste
      subArrow = px(8), subGap = px(3),
      -- Platzhalter (nicht erlernter Beruf): das Symbolfeld ist ringsum um shrink kleiner, damit der
      -- gestrichelte Rahmen (Abstand dashInset vom Zeilenrand) frei steht
      shrink = px(2), dashInset = Skin.Mult(),
   }
   S.fullW = S.buttonW
   S.minW = S.buttonW
   UI.sizes = S
end

-- Darstellung (Einstellung compact): off = mit Text | button = Knopf nur Symbol | all = Knopf und Liste nur Symbole
local function CompactButton() return PM.db.compact == "button" or PM.db.compact == "all" end
local function CompactMenu() return PM.db.compact == "all" end

local function Measure(fontString, text)
   fontString:SetText(text)
   return fontString:GetStringWidth()
end

-- Breite einer Zeile mit gegebener Namensbreite. Fuer die Stufe ("450/450") wird der
-- schlimmste Fall reserviert: die Breite aendert sich dann nicht, wenn eine Stufe waechst
-- (eine Ziffer mehr) oder ein Beruf in die naechste Stufe wechselt.
local function RankReserve()
   if not PM.db.ranks then return 0 end
   return Measure(probeRank, "450/450")
end

local function RowContent(nameWidth, rankReserve)
   return S.iconPad + S.icon + S.textGap + nameWidth + S.textGap + rankReserve + S.rankPad + S.pad * 2 + S.line * 2
end

-- Der Knopf ist so breit wie die breiteste moegliche Zeile (laengster Berufsname der Sprache
-- des Clients plus Stufe): die Liste ist dann nie breiter als er.
local function ComputeButtonWidth()
   local widest = 0
   local loc = GetLocale and GetLocale() or "enUS"
   local reserve = Measure(probeRank, "450/450")
   for _, def in ipairs(PM.PROFESSIONS) do
      local name = def.names and (def.names[loc] or def.names.enUS)
      if name then
         local w = Measure(probeName, name)
         if w > widest then widest = w end
      end
   end
   local fullW = max(Skin.Px(150), RowContent(widest, reserve))
   -- stehen die Faehigkeiten in der Liste, zaehlen auch deren Namen, sonst ragte die Liste ueber den Knopf hinaus
   if PM.db.activities == "list" then
      for _, def in ipairs(PM.ABILITIES) do
         local name = PM.SpellName(def.spell)
         if name then
            fullW = max(fullW, RowContent(Measure(probeName, name), 0))
         end
      end
   end
   S.fullW = Skin.PxCeil(fullW)
   S.minW = S.fullW
end

-- Knopf im Text- oder im Symbol-Modus (der Knopf ist ungeschuetzt: auch im Kampf erlaubt).
local function ApplyButtonMode()
   if not button then return end
   local b = button
   if CompactButton() then
      S.buttonW = S.cell
      b:SetWidth(S.cell)
      b:SetHeight(S.cell)
      b.box:ClearAllPoints()
      b.box:SetPoint("CENTER", b, "CENTER", 0, 0)
      b.box:SetWidth(S.cellIcon)
      b.box:SetHeight(S.cellIcon)
      b.text:Hide()
      b.arrow:Hide()
   else
      S.buttonW = S.fullW
      b:SetWidth(S.fullW)
      b:SetHeight(S.buttonH)
      b.box:ClearAllPoints()
      b.box:SetPoint("LEFT", b, "LEFT", S.buttonPad, 0)
      b.box:SetWidth(S.buttonIcon)
      b.box:SetHeight(S.buttonIcon)
      b.text:Show()
      b.arrow:Show()
   end
end

-- Text am rechten Rand einer Zeile: ein Kennzeichen (Lager: Anzahl, "herstellen", "fehlt") oder die Stufe.
local function RightText(entry)
   if entry.tag then return entry.tag end
   if PM.db.ranks and entry.maxRank and entry.maxRank > 0 then
      return format("%d/%d", entry.rank or 0, entry.maxRank)
   end
   return ""
end

-- Breite, die die gezeigten Zeilen einer Liste brauchen (Name plus rechter Text; fuer die Stufe gilt der
-- reservierte schlimmste Fall, siehe RankReserve). arrows: am Rand steht ein Winkel fuer Untermenues.
local function ContentWidth(list, arrows)
   local widest, reserve, shown = 0, RankReserve(), 0
   for _, row in ipairs(list) do
      if row.entry and row:IsShown() then
         shown = shown + 1
         local w = Measure(probeName, row.entry.name)
         if row.entry.tag then
            w = w + Measure(probeRank, row.entry.tag)
         elseif PM.db.ranks and row.entry.maxRank > 0 then
            w = w + reserve
         end
         if w > widest then widest = w end
      end
   end
   if arrows then widest = widest + S.subArrow + S.textGap end
   return widest, shown
end

-- Hat eine der gezeigten Zeilen der Liste ein Untermenue?
local function AnyChildren()
   for _, row in ipairs(rows) do
      if row.entry and row.entry.children and row:IsShown() then return true end
   end
   return false
end

-- Passt die Liste an ihre Zeilen an. Nur ausserhalb des Kampfes aufrufen (die Liste ist geschuetzt).
-- Nur Symbole: so breit wie eine Zelle, also wie der (kompakte) Knopf.
local function FitWidth()
   local widest, shown = ContentWidth(rows, AnyChildren())
   if CompactMenu() and shown > 0 then
      menu:SetWidth(S.cell)
      return
   end
   if menu.empty:IsShown() then widest = max(widest, menu.empty:GetStringWidth()) end
   menu:SetWidth(Skin.PxCeil(max(S.minW, RowContent(widest, 0))))
end

-- ---------------------------------------------------------------------------
-- Berufsfenster
-- ---------------------------------------------------------------------------

-- Ist das Fenster dieses Berufs gerade offen? Dann soll ein Klick darauf nichts wirken: der Zauber
-- wuerde das offene Fenster neu auslesen (Blizzards eigene Reiter wirken ihn in dem Fall auch nicht).
local IsProfessionOpen = PM.IsProfessionOpen
UI.IsProfessionOpen = IsProfessionOpen

-- Die Berufsuebersicht (Blizzards Berufsbuch) zeigen. Ist das Fenster schon offen, wechselt es auf die
-- Uebersichtsseite; sonst oeffnet ToggleProfessionsBook es (und laedt das Fenster bei Bedarf).
local function ShowOverview()
   local frame = _G.ProfessionsFrame
   if frame and frame:IsShown() then
      if frame.SelectBookPage then
         frame:SelectBookPage()
         if frame.RightTabSelected and frame.ProfessionsOverviewTab then
            frame:RightTabSelected(frame.ProfessionsOverviewTab)
         end
      end
   elseif _G.ToggleProfessionsBook then
      _G.ToggleProfessionsBook()
   end
end
UI.ShowOverview = ShowOverview

-- ---------------------------------------------------------------------------
-- Zeilen (SecureActionButtons)
-- ---------------------------------------------------------------------------

local FlyoutOnLeft         -- (weiter unten) liegt das Untermenue links von der Liste?

local GREEN, RED = { 0.35, 0.85, 0.45 }, { 0.95, 0.35, 0.35 }

local function Clock(seconds)
   seconds = math.floor(seconds + 0.5)
   return format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Tooltip eines Lager-Objekts: Zustand, Beruf, Material, Hinweis zum Klick.
local function AddCampLines(entry)
   local st = entry.camp
   local def = st.def
   if st.mode == "place" then
      GameTooltip:AddLine(format(L.camp_inbags, st.count), GREEN[1], GREEN[2], GREEN[3])
   elseif st.mode == "craft" then
      GameTooltip:AddLine(L.camp_craftable, GREEN[1], GREEN[2], GREEN[3])
   else
      GameTooltip:AddLine(L.camp_lacking, RED[1], RED[2], RED[3])
   end
   if st.prof and def.skill > 0 then
      GameTooltip:AddLine(format(L.camp_prof, st.prof.name, def.skill), 0.65, 0.65, 0.65)
   end
   if st.mode ~= "place" then
      for _, reagent in ipairs(st.reagents) do
         local c = reagent.ok and GREEN or RED
         GameTooltip:AddLine(format("  %s  %d/%d", PM.ItemName(reagent.id), reagent.have, reagent.need), c[1], c[2], c[3])
      end
      if st.tool then
         local c = st.tool.ok and GREEN or RED
         GameTooltip:AddLine(format(L.camp_tool, PM.ItemName(st.tool.id)), c[1], c[2], c[3])
      end
   else
      if st.cooldown and st.cooldown > 0 then
         GameTooltip:AddLine(format(L.camp_cooldown, Clock(st.cooldown)), RED[1], RED[2], RED[3])
      elseif st.usable == false then
         GameTooltip:AddLine(L.camp_unusable, RED[1], RED[2], RED[3])
      end
   end
end

local function ShowRowTooltip(row)
   local entry = row.entry
   if not entry then return end
   if not row.pmSub and flyout and flyout:IsShown() and flyout.owner == row then
      -- die Zeile hat ihr Untermenue neben sich: der Tooltip steht jenseits davon
      GameTooltip:SetOwner(row, "ANCHOR_NONE")
      GameTooltip:ClearAllPoints()
      if FlyoutOnLeft() then
         GameTooltip:SetPoint("TOPRIGHT", flyout, "TOPLEFT", -S.subGap, 0)
      else
         GameTooltip:SetPoint("TOPLEFT", flyout, "TOPRIGHT", S.subGap, 0)
      end
   else
      GameTooltip:SetOwner(row, UI.tooltipAnchor or "ANCHOR_RIGHT")
   end
   -- Lager-Objekt: der Tooltip des Spiels fuer den Gegenstand (er sagt, was das Objekt bewirkt), darunter
   -- unsere Zeilen. Kennt der Client den Gegenstand noch nicht, bleibt es beim Namen.
   local native = false
   if entry.camp and GameTooltip.SetItemByID then
      native = pcall(GameTooltip.SetItemByID, GameTooltip, entry.camp.item)
         and (not GameTooltip.NumLines or GameTooltip:NumLines() > 0)
   end
   if native then
      GameTooltip:AddLine(" ")
   else
      GameTooltip:AddLine(entry.name, 1, 1, 1)
   end
   if entry.maxRank and entry.maxRank > 0 then
      GameTooltip:AddLine(format(L.skill, entry.rank or 0, entry.maxRank), 0.65, 0.65, 0.65)
   end
   if entry.camp then AddCampLines(entry) end
   local overview = _G.TRADE_SKILLS or L.title
   if entry.open or entry.kind == "learn" then
      -- Platzhalter und erlernbare Berufe: sagen, was hier noch erlernt werden kann (und welcher andere
      -- Charakter den Beruf schon hat); jeder Klick zeigt die Berufsuebersicht
      local desc = L.learn_desc
      if entry.open then desc = (entry.open == "primary") and L.open_primary_desc or L.open_secondary_desc end
      GameTooltip:AddLine(desc, 0.65, 0.65, 0.65, true)
      if entry.kind == "learn" then
         if entry.alts then
            GameTooltip:AddLine(L.learn_alts, GREEN[1], GREEN[2], GREEN[3])
            for _, alt in ipairs(entry.alts) do
               GameTooltip:AddLine(format("  %s  %d", alt.label, alt.rank), GREEN[1], GREEN[2], GREEN[3])
            end
         else
            GameTooltip:AddLine(L.learn_noalts, 0.65, 0.65, 0.65, true)
         end
      end
      GameTooltip:AddLine(" ")
      if entry.children then GameTooltip:AddLine(L.hint_learnable, 0.40, 0.75, 1) end
      GameTooltip:AddLine(format(L.hint_overview, overview), 0.40, 0.75, 1)
      GameTooltip:Show()
      return
   end
   local hint
   if entry.kind == "window" then hint = L.hint_open
   elseif entry.kind == "tracking" then hint = L.hint_track
   elseif entry.kind == "use" then hint = L.hint_use
   elseif entry.kind == "target" then hint = L.hint_target
   elseif entry.kind == "place" then hint = L.hint_place
   elseif entry.kind == "craft" then hint = L.hint_craft
   elseif entry.kind == "lack" then hint = L.hint_lack
   elseif entry.moved then hint = format(L.hint_moved, overview)
   elseif entry.missing then hint = format(L.hint_missing, overview)
   else hint = format(L.hint_passive, overview) end
   GameTooltip:AddLine(" ")
   GameTooltip:AddLine(hint, 0.40, 0.75, 1)
   if entry.children then GameTooltip:AddLine(L.hint_sub, 0.40, 0.75, 1) end
   GameTooltip:AddLine(format(L.hint_skills, overview), 0.55, 0.55, 0.55)
   GameTooltip:Show()
end

-- Setzt oder loescht, was ein Linksklick wirkt. Nur ausserhalb des Kampfes.
-- Linksklick (auch mit Umschalt/Strg/Alt: "*") wirkt den Zauber (entry.action) oder benutzt den Gegenstand
-- (entry.item, Lager-Objekt aufstellen); Rechtsklick behandelt RowPostClick.
-- (type/spell ohne Nummer gaelten fuer alle Tasten.)
local function SetRowAction(row, entry)
   local kind, spell, item
   if entry and entry.item then
      kind, item = "item", "item:" .. entry.item
   elseif entry and entry.action then
      kind, spell = "spell", entry.action
   end
   row:SetAttribute("type1", kind)
   row:SetAttribute("*type1", kind)
   row:SetAttribute("spell1", spell)
   row:SetAttribute("*spell1", spell)
   row:SetAttribute("spell", spell)
   row:SetAttribute("item1", item)
   row:SetAttribute("*item1", item)
   row:SetAttribute("item", item)
end

-- Vor dem Zaubern (laeuft ungeschuetzt vor der sicheren Aktion): ist das Fenster dieses Berufs schon offen,
-- wird der Zauber diesmal nicht gewirkt. Das gilt auch fuer "herstellen": dort oeffnet der Zauber nur das
-- Fenster, das Herstellen selbst geschieht in RowPostClick.
local function RowPreClick(self, mouseButton)
   self.pmSkipped = nil
   local entry = self.entry
   if mouseButton == "LeftButton" and entry and (entry.kind == "window" or entry.kind == "craft")
      and not InCombatLockdown() and IsProfessionOpen(entry.skillLine) then
      self.pmSkipped = true
      SetRowAction(self, nil)
   end
end

-- Der Tooltip einer Zeile bleibt sonst stehen, wenn die Liste unter dem Mauszeiger
-- verschwindet (OnLeave kommt dann nicht).
local function HideRowTooltip()
   local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
   if not owner then return end
   for _, list in ipairs({ rows, subRows }) do
      for _, row in ipairs(list) do
         if owner == row then
            GameTooltip:Hide()
            return
         end
      end
   end
end

local function RowPostClick(self, mouseButton)
   local entry = self.entry
   local skipped = self.pmSkipped
   if skipped then
      self.pmSkipped = nil
      if entry and not InCombatLockdown() then SetRowAction(self, entry) end
   end
   if mouseButton == "LeftButton" and entry and entry.kind == "craft" then
      -- Die Liste bleibt offen: nach dem Herstellen wird aus der Zeile "aufstellen", ein zweiter Klick stellt auf.
      PM.Camp.Click(entry, skipped == true)
      return
   end
   if mouseButton == "LeftButton" and entry and entry.kind == "lack" then
      UIErrorsFrame:AddMessage(format(L.camp_lack_msg, table.concat(PM.Camp.Missing(entry.camp), ", ")), 1, 0.3, 0.3)
      return
   end
   local wantOverview = mouseButton == "RightButton" or not (entry and (entry.action or entry.item))
   UI.Close()            -- zuerst: soll auch geschehen, wenn das Berufsfenster einen Fehler wirft
   if wantOverview then ShowOverview() end
end

local ShowFlyout, HideFlyout   -- (weiter unten)

-- Die Maus kommt auf eine Zeile. Zeile der Liste: ist kein Untermenue offen, oeffnet sich ihres sofort;
-- sonst wechselt es erst nach kurzem Verweilen (MenuOnUpdate), damit der Weg quer ueber andere Zeilen hin
-- zum offenen Untermenue es nicht schliesst.
local function RowEnter(row)
   if not row.pmSub then
      hoverRow, hoverAt = row, GetTime()
      if flyout and not flyout:IsShown() and row.entry and row.entry.children and not InCombatLockdown() then
         ShowFlyout(row)
      end
   end
   ShowRowTooltip(row)
end

-- parent: die Liste oder das Untermenue (sub = true)
local function CreateRow(i, parent, sub)
   local row = CreateFrame("Button", (sub and "ProfessionMenuSubRow" or "ProfessionMenuRow") .. i, parent,
      "SecureActionButtonTemplate")
   row.pmSub = sub and true or nil
   row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   -- Loslassen loest aus, nicht Niederdruecken (siehe Kopf der Datei)
   row:SetAttribute("useOnKeyDown", false)
   row:SetFrameStrata(parent:GetFrameStrata())
   row:SetFrameLevel(parent:GetFrameLevel() + 2)
   row:SetHeight(S.rowH)

   local box = Skin.NewFrame("Frame", nil, row)
   box:SetWidth(S.icon)
   box:SetHeight(S.icon)
   box:SetPoint("LEFT", row, "LEFT", S.iconPad, 0)
   Skin.Frame(box, "inset")
   -- Das Symbolfeld liegt UNTER den Flaechen der Zeile, sonst verdeckt es die Hervorhebung beim
   -- Ueberfahren (in der Symbol-Liste fast die ganze Zeile).
   box:SetFrameLevel(max(0, row:GetFrameLevel() - 1))
   row.box = box

   local icon = box:CreateTexture(nil, "ARTWORK")
   icon:SetPoint("TOPLEFT", box, "TOPLEFT", S.pad, -S.pad)
   icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S.pad, S.pad)
   row.icon = icon

   local rank = row:CreateFontString(nil, "OVERLAY")
   Skin.Font(rank, 11)
   rank:SetPoint("RIGHT", row, "RIGHT", -S.rankPad, 0)
   rank:SetJustifyH("RIGHT")
   row.rank = rank

   -- Winkel am Rand: diese Zeile hat ein Untermenue
   local arrow = row:CreateTexture(nil, "OVERLAY")
   arrow:SetWidth(S.subArrow)
   arrow:SetHeight(S.subArrow)
   arrow:SetPoint("RIGHT", row, "RIGHT", -S.rankPad, 0)
   arrow:SetVertexColor(1, 1, 1)
   arrow:Hide()
   row.arrow = arrow

   local text = row:CreateFontString(nil, "OVERLAY")
   Skin.Font(text, 12)
   text:SetPoint("LEFT", box, "RIGHT", S.textGap, 0)
   text:SetPoint("RIGHT", rank, "LEFT", -S.textGap, 0)
   text:SetJustifyH("LEFT")
   -- eine Zeile, "..." statt eines Umbruchs
   if text.SetWordWrap then text:SetWordWrap(false) end
   text:SetTextColor(Skin.TextColor())
   row.text = text

   local sep = row:CreateTexture(nil, "BACKGROUND")
   sep:SetHeight(S.line)
   sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
   sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
   sep:SetColorTexture(1, 1, 1, 0.07)
   row.sep = sep

   local hl = row:CreateTexture(nil, "HIGHLIGHT")
   hl:SetAllPoints(row)
   local path = Skin.HighlightTexture()
   hl:SetTexture(path)
   row.hl = hl

   row:SetScript("OnEnter", PM.Guard("RowEnter", RowEnter))
   row:SetScript("OnLeave", function() GameTooltip:Hide() end)
   row:SetScript("PreClick", PM.Guard("RowPreClick", RowPreClick))
   row:SetScript("PostClick", PM.Guard("RowPostClick", RowPostClick))
   row:Hide()
   return row
end

local function CreateHeader()
   local text = menu:CreateFontString(nil, "OVERLAY")
   Skin.Font(text, 10, "OUTLINE")
   text:SetJustifyH("LEFT")
   text:Hide()
   return { text = text }
end

-- ---------------------------------------------------------------------------
-- Farben
-- ---------------------------------------------------------------------------

local function RankColor(entry)
   if entry.maxRank and entry.maxRank > 0 and entry.rank >= entry.maxRank then
      return 0.35, 0.85, 0.45
   end
   return Skin.DimColor()
end

-- Farbe des rechten Textes: Stufe (gruen bei voller Stufe) oder Kennzeichen eines Lager-Objekts.
local function RightColor(entry)
   if entry.kind == "place" or entry.kind == "learn" then return GREEN[1], GREEN[2], GREEN[3] end
   if entry.kind == "craft" then return Skin.AccentColor() end
   if entry.kind == "lack" then return RED[1], RED[2], RED[3] end
   return RankColor(entry)
end

local function ApplyColors()
   local ar, ag, ab = Skin.AccentColor()
   local _, alpha = Skin.HighlightTexture()
   for _, list in ipairs({ rows, subRows }) do
      for _, row in ipairs(list) do
         row.hl:SetVertexColor(ar, ag, ab, alpha)
      end
   end
   for _, header in ipairs(headers) do
      header.text:SetTextColor(ar, ag, ab)
   end
   if UI.RefreshBorder then UI.RefreshBorder() end
end
UI.ApplyColors = ApplyColors

-- ---------------------------------------------------------------------------
-- Liste aufbauen
-- ---------------------------------------------------------------------------

-- Rahmen des Knopfes: Akzentfarbe, solange die Liste offen ist oder die Maus darauf liegt.
local function RefreshBorder()
   if not button then return end
   local open = (menu and menu:IsShown()) and true or false
   Skin.SetBorder(button, open or button.pmHover == true)
end

-- Pfeil: geschlossen zeigt er dorthin, wo die Liste aufgeht, offen davon weg (liegt die
-- Liste ueber dem Knopf: geschlossen nach oben, offen nach unten).
local function SyncArrow()
   if not button then return false end
   local open = (menu and menu:IsShown()) and true or false
   local up = (UI.Direction() == "up")
   Skin.SetArrow(button.arrow, (up ~= open) and "up" or "down")
   return open
end
UI.SyncArrow = SyncArrow

UI.RefreshBorder = RefreshBorder

local function UpdateArrow()
   if not button then return end
   SyncArrow()
   RefreshBorder()
end

function UI.UpdateRanks(entries)
   local byKey = {}
   for _, e in ipairs(entries) do byKey[e.key] = e end
   for i = 1, MAX_ROWS do
      local row = rows[i]
      if row and row.entry and byKey[row.entry.key] then
         row.entry = byKey[row.entry.key]
         if not row.entry.tag and PM.db.ranks and row.entry.maxRank > 0 then
            row.rank:SetText(format("%d/%d", row.entry.rank, row.entry.maxRank))
            row.rank:SetTextColor(RankColor(row.entry))
         end
      end
   end
end

-- Liegt der Knopf in der rechten Bildschirmhaelfte? Dann haengt die Liste rechtsbuendig an ihm, das
-- Untermenue klappt nach links auf und die Tooltips stehen links.
local function OnRightHalf()
   local left = button and button:GetLeft()
   if not left then return true end
   local width, bs = button:GetWidth(), button:GetEffectiveScale()
   return ((left + width / 2) * bs) > (UIParent:GetWidth() * UIParent:GetEffectiveScale()) / 2
end
FlyoutOnLeft = OnRightHalf

-- Belegt eine Zeile mit einem Eintrag und setzt sie an ihre Stelle. Nur ausserhalb des Kampfes.
--   parent   die Liste oder das Untermenue
--   y        Abstand der Zeilenoberkante von der Oberkante von parent (negativ)
--   compact  nur das Symbol, mittig in einer Zelle
--   arrows   in dieser Liste haben Zeilen einen Winkel fuer ihr Untermenue: rechts Platz dafuer lassen
local function FillRow(row, entry, parent, y, compact, arrows)
   local cl, cr, ct, cb = Skin.IconCoords()
   local rowH = compact and S.cell or S.rowH
   row.entry = entry
   row.pmY = y
   row.icon:SetTexture(entry.icon or PM.BUTTON_ICON)
   row.icon:SetTexCoord(cl, cr, ct, cb)
   row.text:SetText(entry.name)
   row.rank:SetText(RightText(entry))
   row.rank:SetTextColor(RightColor(entry))
   -- abgedunkelt: gerade nicht benutzbar (Material fehlt, Abklingzeit); ein Platzhalter noch staerker
   local shrink = entry.open and S.shrink or 0
   if entry.open then
      row.icon:SetVertexColor(0.35, 0.35, 0.35)
      row.text:SetTextColor(0.5, 0.5, 0.5)
   elseif entry.dim then
      row.icon:SetVertexColor(0.45, 0.45, 0.45)
      row.text:SetTextColor(Skin.DimColor())
   else
      row.icon:SetVertexColor(1, 1, 1)
      row.text:SetTextColor(Skin.TextColor())
   end
   if row.icon.SetDesaturated then row.icon:SetDesaturated(entry.dim and true or false) end

   -- Darstellung: mit Text (Symbol links, Name, Stufe) oder nur das Symbol, mittig in der Zelle
   row:SetHeight(rowH)
   row.box:ClearAllPoints()
   row.rank:ClearAllPoints()
   if compact then
      row.box:SetPoint("CENTER", row, "CENTER", 0, 0)
      row.box:SetWidth(S.cellIcon - 2 * shrink)
      row.box:SetHeight(S.cellIcon - 2 * shrink)
      row.text:Hide()
      row.rank:Hide()
      row.arrow:Hide()
      -- flaches Feld ueber dem Symbol
      row.hl:ClearAllPoints()
      row.hl:SetPoint("TOPLEFT", row.box, "TOPLEFT", S.pad, -S.pad)
      row.hl:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -S.pad, S.pad)
      row.hl:SetTexture(WHITE)
   else
      row.box:SetPoint("LEFT", row, "LEFT", S.iconPad + shrink, 0)
      row.box:SetWidth(S.icon - 2 * shrink)
      row.box:SetHeight(S.icon - 2 * shrink)
      -- der Name beginnt immer an derselben Stelle, auch neben einem kleineren Symbolfeld
      row.text:SetPoint("LEFT", row.box, "RIGHT", S.textGap + shrink, 0)
      row.text:Show()
      row.rank:Show()
      if entry.children then row.arrow:Show() else row.arrow:Hide() end
      row.hl:ClearAllPoints()
      row.hl:SetAllPoints(row)
      row.hl:SetTexture((Skin.HighlightTexture()))
   end
   row.rank:SetPoint("RIGHT", row, "RIGHT", -(S.rankPad + (arrows and (S.subArrow + S.textGap) or 0)), 0)
   SetRowAction(row, entry)
   row:ClearAllPoints()
   row:SetPoint("TOPLEFT", parent, "TOPLEFT", S.pad, y)
   row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -S.pad, y)
   -- ein Platzhalter hat seinen eigenen (gestrichelten) Rahmen: keine Trennlinie darunter
   if compact or entry.open then row.sep:Hide() else row.sep:Show() end
   row:Show()
   return rowH
end

local function ClearRow(row)
   row.entry = nil
   SetRowAction(row, nil)
   Skin.HideDashes(row)
   row:Hide()
end

-- Gestrichelte Rahmen der Platzhalter (nicht erlernte Berufe). Nach FitWidth aufrufen: der Rahmen richtet
-- sich nach der Breite der Liste. Er umschliesst die ganze Zeile (nur Symbole: die Zelle).
local function SyncDashes()
   local inset = S.dashInset
   local width = menu:GetWidth() - 2 * S.pad
   for _, row in ipairs(rows) do
      if row.entry and row.entry.open and row:IsShown() then
         Skin.DrawDashes(row, row, inset, inset, width - 2 * inset, row:GetHeight() - 2 * inset)
      else
         Skin.HideDashes(row)
      end
   end
end

-- Die Winkel der Zeilen mit Untermenue zeigen dorthin, wo es aufklappt.
local function SyncSubArrows()
   local direction = OnRightHalf() and "left" or "right"
   for _, row in ipairs(rows) do Skin.SetArrow(row.arrow, direction) end
end

-- ---------------------------------------------------------------------------
-- Untermenue
-- ---------------------------------------------------------------------------

function HideFlyout()
   if not flyout then return end
   if flyout:IsShown() and not InCombatLockdown() then flyout:Hide() end
   flyout.owner, flyout.ownerKey = nil, nil
end
UI.HideFlyout = HideFlyout

-- Zeigt das Untermenue der Zeile neben ihr (immer mit Text, auch wenn die Liste nur Symbole zeigt).
-- Nur ausserhalb des Kampfes: das Untermenue ist ein geschuetzter Rahmen.
function ShowFlyout(row)
   local entry = row and row.entry
   if not flyout or InCombatLockdown() then return false end
   if not (entry and entry.children) then
      HideFlyout()
      return false
   end
   flyout.owner, flyout.ownerKey = row, entry.key

   local y, count, last = -S.pad, 0, nil
   for i, child in ipairs(entry.children) do
      local sub = subRows[i]
      if not sub then break end
      y = y - FillRow(sub, child, flyout, y, false, false)
      count, last = i, sub
   end
   if last then last.sep:Hide() end
   for i = count + 1, MAX_SUB do
      if subRows[i] then ClearRow(subRows[i]) end
   end
   flyout:SetWidth(Skin.PxCeil(RowContent((ContentWidth(subRows, false)), 0)))
   flyout:SetHeight(-y + S.pad)

   -- Lage: neben der Liste, die erste Zeile auf Hoehe der Zeile des Berufs. Wie die Liste nur an UIParent
   -- verankert; Liste und Untermenue haben dieselbe Skalierung, die Abstaende gelten also unveraendert.
   flyout:ClearAllPoints()
   local left, bottom = menu:GetLeft(), menu:GetBottom()
   if left and bottom then
      local top = bottom + menu:GetHeight() + (row.pmY or 0) + S.pad
      if OnRightHalf() then
         flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - S.subGap, top)
      else
         flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + menu:GetWidth() + S.subGap, top)
      end
   else
      flyout:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
   end
   flyout:Show()
   return true
end
UI.ShowFlyout = ShowFlyout

-- Belegt Zeilen und Ueberschriften neu. Nur ausserhalb des Kampfes aufrufen.
function UI.Rebuild(entries)
   local layout = PM.Layout(entries)
   local y = -S.pad
   local ri, hi = 0, 0
   local lastRow
   local compact = CompactMenu()
   local arrows = false
   for _, entry in ipairs(entries) do
      if entry.children then arrows = true end
   end

   for _, item in ipairs(layout) do
      if item.gap then
         y = y - S.catGap
      elseif item.header then
         hi = hi + 1
         local header = headers[hi]
         if header then
            header.text:ClearAllPoints()
            header.text:SetPoint("TOPLEFT", menu, "TOPLEFT", S.headerPad, y - S.gap)
            header.text:SetText(L["cat_" .. item.header])
            header.text:Show()
            y = y - S.header
         end
      else
         ri = ri + 1
         local row = rows[ri]
         if row then
            y = y - FillRow(row, item.entry, menu, y, compact, arrows)
            lastRow = row
         end
      end
   end
   if lastRow and not compact then lastRow.sep:Hide() end
   -- ueber einem Platzhalter keine Trennlinie: sie laege dicht an seinem gestrichelten Rahmen
   for i = 1, ri - 1 do
      if rows[i] and rows[i + 1] and rows[i + 1].entry and rows[i + 1].entry.open then rows[i].sep:Hide() end
   end

   -- nicht benutzte Zeilen und Ueberschriften verstecken und leeren
   for i = ri + 1, MAX_ROWS do
      if rows[i] then ClearRow(rows[i]) end
   end
   for i = hi + 1, MAX_HEADERS do
      if headers[i] then headers[i].text:Hide() end
   end

   -- Leere Liste: ein Hinweis statt Zeilen
   if ri == 0 then
      menu.empty:ClearAllPoints()
      menu.empty:SetPoint("TOPLEFT", menu, "TOPLEFT", S.headerPad + S.gap, y - S.gap)
      menu.empty:SetText(L.none)
      menu.empty:Show()
      y = y - S.rowH
   else
      menu.empty:Hide()
   end

   FitWidth()
   menu:SetHeight(-y + S.pad)
   SyncDashes()
   SyncSubArrows()
   ApplyColors()

   -- ein offenes Untermenue folgt seinem Beruf (er kann die Zeile gewechselt haben) oder schliesst sich
   if flyout and flyout:IsShown() then
      local owner
      for i = 1, ri do
         local row = rows[i]
         if row and row.entry and row.entry.key == flyout.ownerKey and row.entry.children then owner = row end
      end
      if owner then ShowFlyout(owner) else HideFlyout() end
   end
end

-- Liest die Berufe neu und baut die Liste bei Aenderungen neu auf.
-- force: auch ohne Aenderung neu bauen.
function UI.Refresh(force)
   if not menu then return false end
   local entries = PM.Collect()
   local sig = PM.Signature(entries)
   UI.entries = entries
   if force or sig ~= signature then
      if InCombatLockdown() then
         pendingRebuild = true
         return false
      end
      UI.Rebuild(entries)
      signature = sig
      pendingRebuild = false
   else
      UI.UpdateRanks(entries)
   end
   return true
end

-- ---------------------------------------------------------------------------
-- Oeffnen, Schliessen, Platzieren
-- ---------------------------------------------------------------------------

-- Unten auf dem Bildschirm klappt die Liste nach oben auf, oben nach unten.
function UI.Direction()
   local dir = PM.db.direction
   if dir == "up" or dir == "down" then return dir end
   local _, cy = button:GetCenter()
   if not cy then return "up" end
   local half = (UIParent:GetHeight() * UIParent:GetEffectiveScale()) / 2
   return (cy * button:GetEffectiveScale() < half) and "up" or "down"
end

-- Verankert die Liste NUR an UIParent (siehe Kopf: geschuetzte Kette), mit festen
-- Abstaenden aus der Lage des Knopfes. Nur ausserhalb des Kampfes aufrufen.
function UI.PositionMenu()
   local dir = UI.Direction()
   menu:ClearAllPoints()
   local left, bottom = button:GetLeft(), button:GetBottom()
   if not (left and bottom) then
      menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      UI.tooltipAnchor = "ANCHOR_RIGHT"
      return
   end
   local width, height = button:GetWidth(), button:GetHeight()
   local bs, ms = button:GetEffectiveScale(), menu:GetEffectiveScale()
   local right = OnRightHalf()
   local x = (right and (left + width) or left) * bs / ms
   if dir == "up" then
      local y = (bottom + height) * bs / ms + S.menuGap
      menu:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
   else
      local y = bottom * bs / ms - S.menuGap
      menu:SetPoint(right and "TOPRIGHT" or "TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
   end
   UI.tooltipAnchor = right and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

function UI.Open()
   if not menu or InCombatLockdown() then return false end
   if not UI.Refresh() then return false end
   UI.PositionMenu()
   SyncSubArrows()       -- der Knopf kann verschoben worden sein
   hoverRow = nil
   menu:Show()
   UpdateArrow()
   return true
end

function UI.Close()
   if not menu then return end
   HideRowTooltip()
   HideFlyout()
   if menu:IsShown() and not InCombatLockdown() then menu:Hide() end
   UpdateArrow()
end

function UI.Toggle()
   if not menu then return end
   if menu:IsShown() then
      UI.Close()
   elseif InCombatLockdown() then
      UIErrorsFrame:AddMessage(L.combat, 1, 0.3, 0.3)
   else
      UI.Open()
   end
end

-- Klick neben die Liste (und ihr Untermenue) schliesst sie. Der Knopf ist ausgenommen, sonst oeffnete sein
-- eigener Klick die Liste gleich wieder. Ausserdem: liegt die Maus eine Weile auf einer anderen Zeile der
-- Liste, wechselt das Untermenue dorthin (oder schliesst sich, wenn die Zeile keines hat).
local function MenuOnUpdate(self)
   if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
      and not self:IsMouseOver() and not button:IsMouseOver()
      and not (flyout:IsShown() and flyout:IsMouseOver()) then
      UI.Close()
      return
   end
   if flyout:IsShown() and hoverRow and hoverRow ~= flyout.owner and hoverRow:IsMouseOver()
      and GetTime() - (hoverAt or 0) >= SWITCH_DELAY and not InCombatLockdown() then
      ShowFlyout(hoverRow)
      ShowRowTooltip(hoverRow)       -- der Tooltip steht jetzt neben dem Untermenue (oder wieder neben der Zeile)
   end
end

-- ---------------------------------------------------------------------------
-- Knopf: Position, Verschieben, Skalierung
-- ---------------------------------------------------------------------------

local function SavePosition()
   local point, _, relPoint, x, y = button:GetPoint()
   PM.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Setzt die Ausgangsposition (genau EIN Anker).
function UI.ApplyPosition()
   button:ClearAllPoints()
   local pos = PM.db.pos
   if type(pos) == "table" and pos.point then
      button:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
   else
      button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 210)
   end
end

function UI.ApplyLock()
   if PM.db.locked then
      button:SetMovable(false)
      button:RegisterForDrag()
   else
      button:SetMovable(true)
      button:SetClampedToScreen(true)
      button:RegisterForDrag("LeftButton")
   end
end

-- keepPosition: die Mitte des Knopfes bleibt an derselben Stelle des Bildschirms (die Abstaende
-- eines Rahmens gelten in seiner eigenen Skalierung). Im Kampf nicht moeglich: die Liste
-- ist ein geschuetzter Rahmen (liefert false).
function UI.ApplyScale(keepPosition)
   if InCombatLockdown() then return false end
   UI.Close()            -- die Abstaende einer offenen Liste gelten in der alten Skalierung
   local scale = tonumber(PM.db.scale) or 1
   local oldScale = button:GetEffectiveScale()
   local cx, cy = button:GetCenter()
   button:SetScale(scale)
   menu:SetScale(scale)
   flyout:SetScale(scale)
   if keepPosition and cx and cy then
      local newScale = button:GetEffectiveScale()
      button:ClearAllPoints()
      button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * oldScale / newScale, cy * oldScale / newScale)
      SavePosition()
   end
   return true
end

function UI.ResetPosition()
   UI.Close()
   PM.db.pos = nil
   UI.ApplyPosition()
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

local function CreateToggle()
   local b = Skin.NewFrame("Button", "ProfessionMenuButton", UIParent)
   b:SetWidth(S.buttonW)
   b:SetHeight(S.buttonH)
   b:SetFrameStrata("MEDIUM")
   b:SetFrameLevel(10)
   b:RegisterForClicks("LeftButtonUp")
   Skin.Frame(b, "button")

   local box = Skin.NewFrame("Frame", nil, b)
   box:SetWidth(S.buttonIcon)
   box:SetHeight(S.buttonIcon)
   box:SetPoint("LEFT", b, "LEFT", S.buttonPad, 0)
   Skin.Frame(box, "inset")
   b.box = box

   local icon = box:CreateTexture(nil, "ARTWORK")
   icon:SetPoint("TOPLEFT", box, "TOPLEFT", S.pad, -S.pad)
   icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S.pad, S.pad)
   icon:SetTexture(PM.BUTTON_ICON)
   icon:SetTexCoord(Skin.IconCoords())
   b.icon = icon

   -- Beschriftung in der Mitte des ganzen Knopfes
   local text = b:CreateFontString(nil, "OVERLAY")
   Skin.Font(text, 13)
   text:SetPoint("CENTER", b, "CENTER", 0, 0)
   text:SetText(L.title)
   text:SetTextColor(Skin.TextColor())
   b.text = text

   local arrow = b:CreateTexture(nil, "OVERLAY")
   arrow:SetWidth(S.chevron)
   arrow:SetHeight(S.chevron)
   arrow:SetPoint("RIGHT", b, "RIGHT", -S.buttonPad * 2, 0)
   Skin.SetArrow(arrow, "down")
   arrow:SetVertexColor(1, 1, 1)
   b.arrow = arrow

   b:SetScript("OnEnter", PM.Guard("ButtonEnter", function(self)
      self.pmHover = true
      SyncArrow()                 -- der Knopf kann verschoben worden sein: Richtung neu bestimmen
      RefreshBorder()
      if menu and menu:IsShown() then return end     -- die offene Liste ersetzt den Hinweis
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(L.title, 1, 1, 1)
      GameTooltip:AddLine(L.menuHint, 0.55, 0.55, 0.55)
      if not PM.db.locked then GameTooltip:AddLine(L.dragHint, 0.40, 0.75, 1) end
      GameTooltip:Show()
   end))
   b:SetScript("OnLeave", function(self)
      self.pmHover = nil
      if GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
      UpdateArrow()
   end)
   b:SetScript("OnClick", PM.Guard("ButtonClick", function(self)
      -- der Hinweis "Klick: Liste oeffnen" soll nicht ueber der geoeffneten Liste stehen bleiben
      if GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
      UI.Toggle()
   end))
   b:SetScript("OnDragStart", function(self)
      if self:IsMovable() then
         UI.Close()               -- die Liste folgt dem Knopf nicht (sie haengt nur an UIParent)
         self:StartMoving()
      end
   end)
   b:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      SavePosition()
   end)
   return b
end

-- Baut Knopf, Liste und Zeilen. Einmal, beim Anmelden und ausserhalb des Kampfes.
function UI.Create()
   if UI.created then return end
   ComputeSizes()

   -- Messzeilen: unverankert, damit ihre Breite die des Textes ist (nicht die einer Verankerung)
   local holder = CreateFrame("Frame", nil, UIParent)
   holder:Hide()
   probeName = holder:CreateFontString(nil, "OVERLAY")
   Skin.Font(probeName, 12)
   probeRank = holder:CreateFontString(nil, "OVERLAY")
   Skin.Font(probeRank, 11)
   ComputeButtonWidth()

   button = CreateToggle()
   ApplyButtonMode()

   -- Die Liste ist ein sicherer Zustandsrahmen: der Treiber "[combat]" schliesst sie im
   -- Kampf, auch wenn PLAYER_REGEN_DISABLED zu spaet kaeme.
   menu = Skin.NewFrame("Frame", "ProfessionMenuList", UIParent, "SecureHandlerStateTemplate")
   menu:SetFrameStrata("DIALOG")
   menu:SetFrameLevel(10)
   menu:SetClampedToScreen(true)
   menu:EnableMouse(true)
   menu:Hide()
   Skin.Frame(menu, "panel")
   if RegisterStateDriver then
      menu:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
      RegisterStateDriver(menu, "combat", "[combat] 1; 0")
   end
   menu:SetScript("OnUpdate", MenuOnUpdate)

   local empty = menu:CreateFontString(nil, "OVERLAY")
   Skin.Font(empty, 12)
   empty:SetTextColor(Skin.DimColor())
   empty:Hide()
   menu.empty = empty

   for i = 1, MAX_HEADERS do headers[i] = CreateHeader() end
   for i = 1, MAX_ROWS do rows[i] = CreateRow(i, menu) end

   -- Untermenue: wie die Liste ein sicherer Zustandsrahmen, der sich im Kampf selbst schliesst
   flyout = Skin.NewFrame("Frame", "ProfessionMenuFlyout", UIParent, "SecureHandlerStateTemplate")
   flyout:SetFrameStrata("DIALOG")
   flyout:SetFrameLevel(20)
   flyout:SetClampedToScreen(true)
   flyout:EnableMouse(true)
   flyout:Hide()
   Skin.Frame(flyout, "panel")
   if RegisterStateDriver then
      flyout:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
      RegisterStateDriver(flyout, "combat", "[combat] 1; 0")
   end
   flyout:SetScript("OnHide", HideRowTooltip)
   for i = 1, MAX_SUB do subRows[i] = CreateRow(i, flyout, true) end

   -- ESC: ein ungeschuetzter Stellvertreter in UISpecialFrames. Die geschuetzte Liste selbst
   -- steht dort nicht: Blizzards Schliessen-Schleife (CloseSpecialWindows) ruft Hide() auf dem
   -- Eintrag, und das waere fuer die Liste im Kampf gesperrt. Der Stellvertreter wird mit der
   -- Liste ein- und ausgeblendet; sein OnHide schliesst sie (UI.Close tut im Kampf nichts, dort
   -- schliesst sie der Zustandstreiber).
   local esc = CreateFrame("Frame", "ProfessionMenuEscProxy", UIParent)
   esc:Hide()
   esc:SetScript("OnHide", function()
      if menu:IsShown() then UI.Close() end
   end)
   menu.escProxy = esc
   menu:SetScript("OnShow", function()
      esc:Show()
      UpdateArrow()
   end)
   menu:SetScript("OnHide", function()
      esc:Hide()
      HideRowTooltip()
      UpdateArrow()
   end)
   local registered = false
   for _, name in ipairs(UISpecialFrames) do
      if name == "ProfessionMenuEscProxy" then registered = true end
   end
   if not registered then tinsert(UISpecialFrames, "ProfessionMenuEscProxy") end

   UI.ApplyScale()       -- zuerst: gespeicherte Abstaende gelten in der Skalierung des Knopfes
   UI.ApplyPosition()
   UI.ApplyLock()
   ApplyColors()
   UpdateArrow()
   UI.created = true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

function UI.EnterCombat()
   UI.Close()
   if button then button:SetAlpha(0.45) end
end

function UI.LeaveCombat()
   if button then button:SetAlpha(1) end
   if pendingRelayout then UI.Relayout() end
   if pendingRebuild then UI.Refresh(true) end
end

-- Einstellung geaendert: Breiten neu messen, Liste neu bauen, Farben neu setzen. Im Kampf wird es
-- auf danach verschoben (geschuetzte Rahmen).
function UI.Relayout()
   if not (menu and button) then return end
   if InCombatLockdown() then
      pendingRelayout = true
      return
   end
   pendingRelayout = false
   local oldW, oldH = button:GetWidth(), button:GetHeight()
   ComputeButtonWidth()
   ApplyButtonMode()
   -- Aendert sich die Masse des Knopfes, stimmen die Abstaende einer offenen Liste nicht mehr (sie haengt nur
   -- an UIParent): dann schliesst sie sich. Sonst (Sortierung, Ueberschriften ...) wird sie an Ort und Stelle neu gebaut.
   if button:GetWidth() ~= oldW or button:GetHeight() ~= oldH then UI.Close() end
   UI.Refresh(true)
   ApplyColors()
   UpdateArrow()
end

-- Wird durch Kern-Ereignisse angestossen: gelernte Berufe/Zauber haben sich geaendert.
function UI.MarkStale()
   if menu and menu:IsShown() and not InCombatLockdown() then
      UI.Refresh()      -- die Signatur entscheidet, ob wirklich neu gebaut wird
   end
end
