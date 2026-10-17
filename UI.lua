-- UI.lua
-- ---------------------------------------------------------------------------
-- Knopf "Berufe" und die Ausklappliste.
--
-- Kampfsperre (das Wichtigste an diesem Aufbau)
--   Die Zeilen sind SecureActionButtons (type=spell, spell=<Name>). Geschuetzte
--   Rahmen duerfen im Kampf nicht verschoben, ein- oder ausgeblendet oder umbelegt
--   werden, und dasselbe gilt fuer ihre Eltern und die Rahmen, an denen sie
--   verankert sind. Darum:
--     * Die Liste (menu) ist selbst ein SecureHandlerStateTemplate-Rahmen und
--       schliesst sich im Kampf von allein (Zustandstreiber "[combat]").
--     * Die Liste ist NUR an UIParent verankert, mit festen Abstaenden, die beim
--       Oeffnen aus der Lage des Knopfes berechnet werden. Der Knopf und ElvUIs
--       Chatfenster haengen deshalb nicht in der geschuetzten Kette.
--     * Zeilen werden einmal angelegt (beim Anmelden, ausserhalb des Kampfes) und
--       danach nur ausserhalb des Kampfes umbelegt.
--     * Im Kampf bleibt der Knopf ruhig (abgedunkelt); Oeffnen wird abgelehnt.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local Skin, L = PM.Skin, PM.L
local format, tinsert, floor, max, tostring, tonumber, pairs, ipairs, type =
   string.format, table.insert, math.floor, math.max, tostring, tonumber, pairs, ipairs, type

local UI = {}
PM.UI = UI

local MAX_ROWS, MAX_HEADERS = 24, 5
local WHITE = "Interface\\Buttons\\WHITE8X8"

local S                      -- Masse (UI-Einheiten, auf Pixel gerundet), siehe ComputeSizes
local button, menu
local rows, headers = {}, {}
local probeName, probeRank   -- unverankerte Schriftzeilen zum Messen von Texten
local signature
local pendingRebuild = false
local pendingRelayout = false
UI.rows, UI.headers = rows, headers

function UI.GetButton() return button end
function UI.GetMenu() return menu end

-- Masse nach dem Pixelraster. Wird beim Bauen berechnet, nicht beim Laden der Datei:
-- erst dann stehen UI-Skalierung und (bei ElvUI) E.mult fest.
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
      local name
      if def.names then
         name = def.names[loc] or def.names.enUS
      elseif def.spell and GetSpellInfo then
         name = GetSpellInfo(def.spell)
      end
      if name then
         local w = Measure(probeName, name)
         if w > widest then widest = w end
      end
   end
   local fullW = max(Skin.Px(150), RowContent(widest, reserve))
   -- mit "aktive Faehigkeiten" zaehlen auch deren Namen (Angeln traegt die Stufe), sonst ragte die Liste
   -- ueber den Knopf hinaus
   if PM.db.abilities and GetSpellInfo then
      for _, def in ipairs(PM.ABILITIES) do
         local name = GetSpellInfo(def.spell)
         if name then
            fullW = max(fullW, RowContent(Measure(probeName, name), def.rankFrom and reserve or 0))
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

-- Passt die Liste an ihre Zeilen an. Nur ausserhalb des Kampfes (die Liste ist geschuetzt).
-- Nur Symbole: so breit wie eine Zelle, also wie der (kompakte) Knopf.
local function FitWidth()
   local widest, reserve, shown = 0, RankReserve(), 0
   for i = 1, MAX_ROWS do
      local row = rows[i]
      if row and row.entry and row:IsShown() then
         shown = shown + 1
         local w = Measure(probeName, row.entry.name)
         if PM.db.ranks and row.entry.maxRank > 0 then w = w + reserve end
         if w > widest then widest = w end
      end
   end
   if CompactMenu() and shown > 0 then
      menu:SetWidth(S.cell)
      return
   end
   if menu.empty:IsShown() then widest = max(widest, menu.empty:GetStringWidth()) end
   menu:SetWidth(Skin.PxCeil(max(S.minW, RowContent(widest, 0))))
end

-- ---------------------------------------------------------------------------
-- Zeilen (SecureActionButtons)
-- ---------------------------------------------------------------------------

local function ShowRowTooltip(row)
   local entry = row.entry
   if not entry then return end
   GameTooltip:SetOwner(row, UI.tooltipAnchor or "ANCHOR_RIGHT")
   GameTooltip:AddLine(entry.name, 1, 1, 1)
   if entry.maxRank and entry.maxRank > 0 then
      GameTooltip:AddLine(format(L.skill, entry.rank or 0, entry.maxRank), 0.65, 0.65, 0.65)
   end
   local hint
   if entry.kind == "window" then hint = L.hint_open
   elseif entry.kind == "tracking" then hint = L.hint_track
   elseif entry.kind == "use" then hint = L.hint_use
   elseif entry.kind == "target" then hint = L.hint_target
   elseif entry.moved then hint = L.hint_moved
   elseif entry.missing then hint = L.hint_missing
   else hint = L.hint_passive end
   GameTooltip:AddLine(" ")
   GameTooltip:AddLine(hint, 0.40, 0.75, 1)
   GameTooltip:AddLine(L.hint_skills, 0.55, 0.55, 0.55)
   GameTooltip:Show()
end

-- Vor dem Zaubern: ein offenes Berufsfenster schliessen, damit der Klick den
-- gewaehlten Beruf oeffnet statt das offene umzuschalten (so macht es auch das
-- Addon Panda). Laeuft unsicher vor der sicheren Aktion.
local function RowPreClick(self, mouseButton)
   local entry = self.entry
   if mouseButton == "LeftButton" and entry and entry.kind == "window" and entry.action
      and CloseTradeSkill and _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() then
      CloseTradeSkill()
   end
end

-- Der Tooltip einer Zeile bleibt sonst stehen, wenn die Liste unter dem Mauszeiger
-- verschwindet (OnLeave kommt dann nicht).
local function HideRowTooltip()
   local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
   if not owner then return end
   for _, row in ipairs(rows) do
      if owner == row then
         GameTooltip:Hide()
         return
      end
   end
end

-- Das Fertigkeitenfenster zeigen. ToggleCharacter hat hier kein "nur zeigen" und schliesst
-- das Fenster, wenn die Seite schon sichtbar ist: dann bleibt es einfach offen (IsVisible,
-- nicht IsShown: die Seite behaelt ihr eigenes Flag, auch wenn das Charakterfenster zu ist).
local function ShowSkills()
   local page = _G.SkillFrame
   if ToggleCharacter and not (page and page:IsVisible()) then
      ToggleCharacter("SkillFrame")
   end
end

local function RowPostClick(self, mouseButton)
   local entry = self.entry
   local wantSkills = mouseButton == "RightButton" or not (entry and entry.action)
   UI.Close()            -- zuerst: soll auch geschehen, wenn das Fertigkeitenfenster einen Fehler wirft
   if wantSkills then ShowSkills() end
end

local function CreateRow(i)
   local row = CreateFrame("Button", "ProfessionMenuRow" .. i, menu, "SecureActionButtonTemplate")
   row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   row:SetFrameStrata(menu:GetFrameStrata())
   row:SetFrameLevel(menu:GetFrameLevel() + 2)
   row:SetHeight(S.rowH)

   local box = CreateFrame("Frame", nil, row)
   box:SetWidth(S.icon)
   box:SetHeight(S.icon)
   box:SetPoint("LEFT", row, "LEFT", S.iconPad, 0)
   Skin.Frame(box, "inset")
   -- Das Symbolfeld liegt UNTER den Flaechen der Zeile (wie bei ElvUIs CreateBackdrop), sonst verdeckt es
   -- die Hervorhebung beim Ueberfahren (in der Symbol-Liste fast die ganze Zeile).
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

   local text = row:CreateFontString(nil, "OVERLAY")
   Skin.Font(text, 12)
   text:SetPoint("LEFT", box, "RIGHT", S.textGap, 0)
   text:SetPoint("RIGHT", rank, "LEFT", -S.textGap, 0)
   text:SetJustifyH("LEFT")
   -- eine Zeile, "..." statt eines Umbruchs (der Client kennt SetWordWrap, ElvUI ruft es auch auf)
   if text.SetWordWrap then text:SetWordWrap(false) end
   text:SetTextColor(Skin.TextColor())
   row.text = text

   local sep = row:CreateTexture(nil, "BACKGROUND")
   sep:SetHeight(S.line)
   sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
   sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
   sep:SetTexture(1, 1, 1, 0.07)
   row.sep = sep

   local hl = row:CreateTexture(nil, "HIGHLIGHT")
   hl:SetAllPoints(row)
   local path = Skin.HighlightTexture()
   hl:SetTexture(path)
   row.hl = hl

   row:SetScript("OnEnter", PM.Guard("RowEnter", ShowRowTooltip))
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
-- Farben (folgen der Wertfarbe von ElvUI)
-- ---------------------------------------------------------------------------

local function RankColor(entry)
   if entry.maxRank and entry.maxRank > 0 and entry.rank >= entry.maxRank then
      return 0.35, 0.85, 0.45
   end
   return Skin.DimColor()
end

local function ApplyColors()
   local ar, ag, ab = Skin.AccentColor()
   local _, alpha = Skin.HighlightTexture()
   for _, row in ipairs(rows) do
      row.hl:SetVertexColor(ar, ag, ab, alpha)
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
         if PM.db.ranks and row.entry.maxRank > 0 then
            row.rank:SetText(format("%d/%d", row.entry.rank, row.entry.maxRank))
            row.rank:SetTextColor(RankColor(row.entry))
         end
      end
   end
end

-- Belegt Zeilen und Ueberschriften neu. Nur ausserhalb des Kampfes aufrufen.
function UI.Rebuild(entries)
   local layout = PM.Layout(entries)
   local y = -S.pad
   local ri, hi = 0, 0
   local cl, cr, ct, cb = Skin.IconCoords()
   local lastRow
   local compact = CompactMenu()
   local rowH = compact and S.cell or S.rowH

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
            local entry = item.entry
            row.entry = entry
            row.icon:SetTexture(entry.icon or PM.BUTTON_ICON)
            row.icon:SetTexCoord(cl, cr, ct, cb)
            row.text:SetText(entry.name)
            if PM.db.ranks and entry.maxRank > 0 then
               row.rank:SetText(format("%d/%d", entry.rank, entry.maxRank))
               row.rank:SetTextColor(RankColor(entry))
            else
               row.rank:SetText("")
            end
            -- Darstellung: mit Text (Symbol links, Name, Stufe) oder nur das Symbol, mittig in der Zelle
            row:SetHeight(rowH)
            row.box:ClearAllPoints()
            if compact then
               row.box:SetPoint("CENTER", row, "CENTER", 0, 0)
               row.box:SetWidth(S.cellIcon)
               row.box:SetHeight(S.cellIcon)
               row.text:Hide()
               row.rank:Hide()
               -- flaches Feld ueber dem Symbol (der Verlauf blendet an den schmalen Raendern aus)
               row.hl:ClearAllPoints()
               row.hl:SetPoint("TOPLEFT", row.box, "TOPLEFT", S.pad, -S.pad)
               row.hl:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -S.pad, S.pad)
               row.hl:SetTexture(WHITE)
            else
               row.box:SetPoint("LEFT", row, "LEFT", S.iconPad, 0)
               row.box:SetWidth(S.icon)
               row.box:SetHeight(S.icon)
               row.text:Show()
               row.rank:Show()
               row.hl:ClearAllPoints()
               row.hl:SetAllPoints(row)
               row.hl:SetTexture((Skin.HighlightTexture()))
            end
            -- Linksklick (auch mit Umschalt/Strg/Alt: "*") wirkt den Zauber; Rechtsklick
            -- behandelt RowPostClick. (type/spell ohne Nummer gaelten fuer alle Tasten.)
            local kind = entry.action and "spell" or nil
            row:SetAttribute("type1", kind)
            row:SetAttribute("*type1", kind)
            row:SetAttribute("spell1", entry.action)
            row:SetAttribute("*spell1", entry.action)
            row:SetAttribute("spell", entry.action)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", S.pad, y)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -S.pad, y)
            if compact then row.sep:Hide() else row.sep:Show() end
            row:Show()
            lastRow = row
            y = y - rowH
         end
      end
   end
   if lastRow and not compact then lastRow.sep:Hide() end

   -- nicht benutzte Zeilen und Ueberschriften verstecken und leeren
   for i = ri + 1, MAX_ROWS do
      local row = rows[i]
      if row then
         row.entry = nil
         row:SetAttribute("type1", nil)
         row:SetAttribute("*type1", nil)
         row:SetAttribute("spell1", nil)
         row:SetAttribute("*spell1", nil)
         row:SetAttribute("spell", nil)
         row:Hide()
      end
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
   ApplyColors()
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
   local right = ((left + width / 2) * bs) > (UIParent:GetWidth() * UIParent:GetEffectiveScale()) / 2
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
   menu:Show()
   UpdateArrow()
   return true
end

function UI.Close()
   if not menu then return end
   HideRowTooltip()
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

-- Klick neben die Liste schliesst sie (3.3.5 kennt kein GLOBAL_MOUSE_DOWN). Der Knopf
-- ist ausgenommen, sonst oeffnete sein eigener Klick die Liste gleich wieder.
local function MenuOnUpdate(self)
   if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
      and not MouseIsOver(self) and not MouseIsOver(button) then
      UI.Close()
   end
end

-- ---------------------------------------------------------------------------
-- Knopf: Position, Verschieben, Skalierung
-- ---------------------------------------------------------------------------

local function SavePosition()
   local point, _, relPoint, x, y = button:GetPoint()
   PM.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Setzt die Ausgangsposition (genau EIN Anker). Mit ElvUI nur einmal VOR dem Mover:
-- danach haelt ElvUIs Mover den Knopf, ein erneutes Verankern loest ihn davon.
function UI.ApplyPosition()
   button:ClearAllPoints()
   local pos = PM.db.pos
   if not Skin.elvui and type(pos) == "table" and pos.point then
      button:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
   elseif Skin.elvui and _G.RightChatPanel then
      button:SetPoint("BOTTOMRIGHT", _G.RightChatPanel, "TOPRIGHT", 0, S.gap)
   elseif Skin.elvui and Skin.E.UIParent then
      button:SetPoint("BOTTOMRIGHT", Skin.E.UIParent, "BOTTOMRIGHT", -S.gap, 250)
   else
      button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 210)
   end
end

function UI.ApplyLock()
   if Skin.elvui or PM.db.locked then
      button:SetMovable(false)
      button:RegisterForDrag()
   else
      button:SetMovable(true)
      button:SetClampedToScreen(true)
      button:RegisterForDrag("LeftButton")
   end
end

-- Skalierung nur ohne ElvUI: dort bestimmt ElvUIs UI-Skalierung das Pixelraster, und
-- eine zusaetzliche Skalierung machte alle Ein-Pixel-Kanten unscharf.
-- keepPosition: die Mitte des Knopfes bleibt an derselben Stelle des Bildschirms (die Abstaende
-- eines Rahmens gelten in seiner eigenen Skalierung). Im Kampf nicht moeglich: die Liste
-- ist ein geschuetzter Rahmen (liefert false).
function UI.ApplyScale(keepPosition)
   if Skin.elvui then return true end
   if InCombatLockdown() then return false end
   UI.Close()            -- die Abstaende einer offenen Liste gelten in der alten Skalierung
   local scale = tonumber(PM.db.scale) or 1
   local oldScale = button:GetEffectiveScale()
   local cx, cy = button:GetCenter()
   button:SetScale(scale)
   menu:SetScale(scale)
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
   if Skin.elvui then
      Skin.ResetMover(L.mover)
   else
      UI.ApplyPosition()
   end
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

local function CreateToggle()
   local b = CreateFrame("Button", "ProfessionMenuButton", UIParent)
   b:SetWidth(S.buttonW)
   b:SetHeight(S.buttonH)
   b:SetFrameStrata("MEDIUM")
   b:SetFrameLevel(10)
   b:RegisterForClicks("LeftButtonUp")
   Skin.Frame(b, "button")

   local box = CreateFrame("Frame", nil, b)
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
   menu = CreateFrame("Frame", "ProfessionMenuList", UIParent, "SecureHandlerStateTemplate")
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
   for i = 1, MAX_ROWS do rows[i] = CreateRow(i) end

   -- ESC: ein ungeschuetzter Stellvertreter in UISpecialFrames. Die geschuetzte Liste selbst
   -- steht dort nicht: Blizzards Schliessen-Schleife liest den Eintrag aus einer von uns
   -- beschriebenen Tabelle, und ein Hide() der Liste aus diesem Pfad waere im Kampf gesperrt.
   -- Der Stellvertreter wird mit der Liste ein- und ausgeblendet; sein OnHide schliesst sie
   -- (UI.Close tut im Kampf nichts, dort schliesst sie der Zustandstreiber).
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
   Skin.OnAccentChanged(PM.Guard("ApplyColors", ApplyColors))
   -- ElvUI: nach einer Aenderung der Schrift oder beim Profilwechsel neu messen und faerben
   Skin.OnFontsChanged(PM.Guard("Relayout", function() UI.Relayout() end))
   if Skin.elvui and type(Skin.E.UpdateAll) == "function" then
      hooksecurefunc(Skin.E, "UpdateAll", PM.Guard("Relayout", function() UI.Relayout() end))
   end
   Skin.CreateMover(button, "ProfessionMenuMover", L.mover, "professionMenu")
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

-- Schrift, Profil oder Wertfarbe haben sich geaendert (ElvUI): Breiten neu messen, Liste neu
-- bauen, Farben neu setzen. Im Kampf wird es auf danach verschoben (geschuetzte Rahmen).
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
