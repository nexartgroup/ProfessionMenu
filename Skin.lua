-- Skin.lua
-- ---------------------------------------------------------------------------
-- Aussehen. Knopf und Liste sehen aus wie die flachen Leisten von ElvUI (dunkle Flaeche,
-- schwarze 1-Pixel-Kante, Hervorhebung in Orange), gebaut aus Bordmitteln des Spiels:
-- BackdropTemplate fuer Rahmen, die Schrift des Spiels, das Pixelraster der Oberflaeche.
-- Eine Anbindung an ElvUI gibt es fuer Forever (noch) nicht.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local type, unpack, floor, ipairs = type, unpack, math.floor, ipairs
local Skin = {}
PM.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"

local COLORS = {
   accent = { 0.99, 0.48, 0.17 },       -- Hervorhebung (Orange)
   border = { 0, 0, 0 },                -- schwarze Kante
   solid = { 0.10, 0.10, 0.10 },        -- Knopf, Symbolfeld
   fade = { 0.06, 0.06, 0.06, 0.8 },    -- Liste (halbtransparent)
}

-- ---------------------------------------------------------------------------
-- Pixelraster
-- ---------------------------------------------------------------------------

-- Eine physische Pixelbreite in UI-Einheiten (Rahmen mit Skalierung 1 unter UIParent).
function Skin.Mult()
   local height = 768
   if _G.GetPhysicalScreenSize then
      local _, h = _G.GetPhysicalScreenSize()
      if type(h) == "number" and h > 0 then height = h end
   end
   local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
   if not scale or scale <= 0 then scale = 1 end
   return (768 / height) / scale
end

-- Auf ganze Pixel runden, mindestens ein Pixel.
function Skin.Px(value)
   local mult = Skin.Mult()
   local px = mult * floor(value / mult + 0.5)
   if px < mult then px = mult end
   return px
end

-- Auf ganze Pixel AUFrunden (fuer Breiten, in die ein Text passen muss).
function Skin.PxCeil(value)
   local mult = Skin.Mult()
   return mult * math.ceil(value / mult - 1e-6)
end

-- Abstand zwischen Inhalt und Rand: ein Pixel.
function Skin.Border()
   return Skin.Mult()
end

-- ---------------------------------------------------------------------------
-- Farben
-- ---------------------------------------------------------------------------

function Skin.AccentColor() return unpack(COLORS.accent) end
function Skin.BorderColor() return unpack(COLORS.border) end
function Skin.TextColor() return 1, 1, 1 end
function Skin.DimColor() return 0.65, 0.65, 0.65 end

-- ---------------------------------------------------------------------------
-- Rahmen
-- ---------------------------------------------------------------------------

-- Ein Rahmen, der SetBackdrop kennt: seit Patch 9.0 braucht jeder Rahmen mit Hintergrund die
-- Vorlage "BackdropTemplate". extra: weitere Vorlagen (etwa "SecureActionButtonTemplate").
function Skin.NewFrame(frameType, name, parent, extra)
   local template = extra and (extra .. ",BackdropTemplate") or "BackdropTemplate"
   return CreateFrame(frameType, name, parent, template)
end

-- kind: "panel" (halbtransparent, Liste), "button" (Knopf), "inset" (Symbolrahmen)
function Skin.Frame(frame, kind)
   frame.pmKind = kind
   local mult = Skin.Mult()
   frame:SetBackdrop({
      bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = mult,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
   })
   local c = (kind == "panel") and COLORS.fade or COLORS.solid
   frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
   frame:SetBackdropBorderColor(unpack(COLORS.border))
end

-- Rahmenfarbe setzen (Hervorhebung) oder zurueck auf die Grundfarbe.
function Skin.SetBorder(frame, highlighted)
   local r, g, b
   if highlighted then
      r, g, b = Skin.AccentColor()
   else
      r, g, b = Skin.BorderColor()
   end
   frame:SetBackdropBorderColor(r, g, b, 1)
end

-- ---------------------------------------------------------------------------
-- Gestrichelter Rahmen (Platzhalter fuer nicht erlernte Berufe)
--
-- Das Spiel kennt keine gestrichelte Linie: jeder Strich ist eine eigene einfarbige Flaeche. Die Striche
-- liegen auf ganzen Pixeln, an jeder Ecke beginnt und endet einer.
-- ---------------------------------------------------------------------------

local DASH, GAP = 4, 3     -- Strich und Luecke in Pixeln

-- Striche einer Kante der Laenge length (UI-Einheiten): Liste aus { Abstand vom Anfang, Laenge }.
-- Der Rest, der nicht in das Raster passt, verteilt sich pixelweise: zuerst je ein Pixel auf die Luecken,
-- was dann noch bleibt (nur bei kurzen Kanten) auf die Striche.
function Skin.DashPlan(length)
   local mult = Skin.Mult()
   local px = floor(length / mult + 0.5)
   local plan = {}
   local count = floor((px + GAP) / (DASH + GAP))
   if count < 2 then
      plan[1] = { 0, px * mult }
      return plan
   end
   local rest = px - (count * DASH + (count - 1) * GAP)
   local wider = (rest < count - 1) and rest or (count - 1)      -- so viele Luecken sind ein Pixel breiter
   rest = rest - wider
   local each, more = floor(rest / count), rest % count          -- so viel laenger sind die Striche
   local at = 0
   for i = 1, count do
      local len = DASH + each + ((i <= more) and 1 or 0)
      plan[i] = { at * mult, len * mult }
      at = at + len + GAP + ((i <= wider) and 1 or 0)
   end
   return plan
end

-- Zeichnet ein gestricheltes Rechteck in frame. holder (frame.pmDashes) haelt die Flaechen; sie werden
-- wiederverwendet. anchor: Region, an deren linker oberer Ecke das Rechteck haengt; x, y: Abstand der Ecke
-- nach rechts und unten; width, height: Masse des Rechtecks.
function Skin.DrawDashes(frame, anchor, x, y, width, height)
   local holder = frame.pmDashes
   if not holder then
      holder = { pool = {}, used = 0 }
      frame.pmDashes = holder
   end
   local mult = Skin.Mult()
   local r, g, b = Skin.DimColor()
   local used = 0
   local function Dash(dx, dy, w, h)
      used = used + 1
      local tex = holder.pool[used]
      if not tex then
         tex = frame:CreateTexture(nil, "BORDER")
         holder.pool[used] = tex
      end
      tex:SetColorTexture(r, g, b, 0.75)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + dx, -(y + dy))
      tex:SetWidth(w)
      tex:SetHeight(h)
      tex:Show()
   end
   for _, dash in ipairs(Skin.DashPlan(width)) do
      Dash(dash[1], 0, dash[2], mult)                    -- oben
      Dash(dash[1], height - mult, dash[2], mult)        -- unten
   end
   for _, dash in ipairs(Skin.DashPlan(height)) do
      Dash(0, dash[1], mult, dash[2])                    -- links
      Dash(width - mult, dash[1], mult, dash[2])         -- rechts
   end
   for i = used + 1, holder.used do holder.pool[i]:Hide() end
   holder.used = used
   holder.width, holder.height = width, height
end

function Skin.HideDashes(frame)
   local holder = frame.pmDashes
   if not holder then return end
   for i = 1, holder.used do holder.pool[i]:Hide() end
   holder.used = 0
end

-- Zeilen-Hervorhebung: Textur und Deckkraft.
function Skin.HighlightTexture()
   return WHITE, 0.18
end

-- ---------------------------------------------------------------------------
-- Schrift
-- ---------------------------------------------------------------------------

function Skin.Font(fontString, size, style)
   fontString:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, style or "OUTLINE")
end

-- ---------------------------------------------------------------------------
-- Symbole
-- ---------------------------------------------------------------------------

-- Texturkoordinaten, die den Rand eines Symbols abschneiden.
function Skin.IconCoords()
   return 0.08, 0.92, 0.08, 0.92
end

-- Pfeil (Winkel) fuer den Knopf und die Zeilen mit Untermenue. Die Datei zeigt nach unten; nach oben wird
-- sie gespiegelt, nach links und rechts gedreht (acht Werte: die Ecken oben links, unten links, oben rechts,
-- unten rechts der Flaeche, jeweils als Punkt in der Datei).
Skin.ARROW = "Interface\\AddOns\\ProfessionMenu\\Media\\chevron.tga"

function Skin.SetArrow(texture, direction)
   texture:SetTexture(Skin.ARROW)
   if direction == "up" then
      texture:SetTexCoord(0, 1, 1, 0)
   elseif direction == "right" then
      texture:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
   elseif direction == "left" then
      texture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
   else
      texture:SetTexCoord(0, 1, 0, 1)
   end
end
