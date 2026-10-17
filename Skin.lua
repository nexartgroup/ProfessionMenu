-- Skin.lua
-- ---------------------------------------------------------------------------
-- Aussehen. Mit ElvUI sehen Knopf und Liste aus wie ElvUI (Vorlagen "Default" und
-- "Transparent", ElvUI-Schrift, Hervorhebung in der Wertfarbe, Pixelraster wie
-- E:Scale), ohne ElvUI gibt es dasselbe aus Bordmitteln: ElvUIs Standardfarben,
-- schwarze 1-Pixel-Kante, Schrift des Spiels.
--
-- ElvUI wird erst bei seinem PLAYER_LOGIN fertig (E.initialized, gesetzt am Ende
-- von E:Initialize). Skin.Detect() wird deshalb aufgerufen, wenn die Oberflaeche
-- gebaut wird, nicht beim Laden der Datei. E.media-Tabellen und E.db werden dort
-- jedes Mal frisch gelesen und nie zwischengespeichert: ElvUI ersetzt sie beim
-- Profilwechsel.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local type, unpack, tonumber, floor, ipairs, pairs = type, unpack, tonumber, math.floor, ipairs, pairs
local strmatch = string.match
local Skin = {}
PM.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- ElvUIs Standardwerte (ElvUI/Settings/Profile.lua), fuer den Betrieb ohne ElvUI
local FALLBACK = {
   accent = { 0.99, 0.48, 0.17 },       -- Wertfarbe (Orange)
   border = { 0, 0, 0 },                -- schwarze Kante
   solid = { 0.10, 0.10, 0.10 },        -- "Default": backdropcolor
   fade = { 0.06, 0.06, 0.06, 0.8 },    -- "Transparent": backdropfadecolor
}

Skin.E = nil              -- ElvUI-Engine, wenn aktiv
Skin.elvui = false

local function Engine()
   local engine = _G.ElvUI
   return type(engine) == "table" and engine[1] or nil
end

-- Stellt fest, ob ElvUI aktiv und fertig initialisiert ist (true: ElvUI-Aussehen).
function Skin.Detect()
   local E = Engine()
   if E and E.initialized and E.media and E.db then
      Skin.E = E
      Skin.elvui = true
      return true
   end
   Skin.E = nil
   Skin.elvui = false
   return false
end

-- ElvUI ist geladen, aber noch nicht fertig: warten.
function Skin.ElvUIPending()
   local E = Engine()
   return (E ~= nil) and not E.initialized
end

-- ---------------------------------------------------------------------------
-- Pixelraster
-- ---------------------------------------------------------------------------

-- Eine physische Pixelbreite in UI-Einheiten (bei ElvUI E.mult).
function Skin.Mult()
   if Skin.elvui and Skin.E.mult then return Skin.E.mult end
   local height = tonumber(strmatch((GetCVar and GetCVar("gxResolution")) or "", "%d+x(%d+)")) or 768
   local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
   if scale <= 0 then scale = 1 end
   return (768 / height) / scale
end

-- Auf ganze Pixel runden (wie E:Scale), mindestens ein Pixel.
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

-- Abstand zwischen Inhalt und Rand wie bei ElvUI (E.Border: 1 Pixel mit Pixel-Perfect,
-- sonst 2: die Vorlage zeichnet dann noch einen inneren Rand).
function Skin.Border()
   if Skin.elvui and Skin.E.Border then return Skin.E.Border end
   return Skin.Mult()
end

-- ---------------------------------------------------------------------------
-- Farben (immer frisch lesen)
-- ---------------------------------------------------------------------------

function Skin.AccentColor()
   if Skin.elvui and Skin.E.media.rgbvaluecolor then
      local c = Skin.E.media.rgbvaluecolor
      return c[1], c[2], c[3]
   end
   return unpack(FALLBACK.accent)
end

function Skin.BorderColor()
   if Skin.elvui and Skin.E.media.bordercolor then
      local c = Skin.E.media.bordercolor
      return c[1], c[2], c[3]
   end
   return unpack(FALLBACK.border)
end

function Skin.TextColor()
   return 1, 1, 1
end

function Skin.DimColor()
   return 0.65, 0.65, 0.65
end

-- Wird gerufen, wenn der Nutzer in ElvUI die Wertfarbe aendert.
function Skin.OnAccentChanged(fn)
   if Skin.elvui and type(Skin.E.valueColorUpdateFuncs) == "table" then
      Skin.E.valueColorUpdateFuncs[fn] = true
   end
end

-- ---------------------------------------------------------------------------
-- Rahmen
-- ---------------------------------------------------------------------------

-- kind: "panel" (halbtransparent, Liste), "button" (Knopf), "inset" (Symbolrahmen)
function Skin.Frame(frame, kind)
   frame.pmKind = kind
   if Skin.elvui and frame.SetTemplate then
      -- wie S:HandleButton: Knoepfe "Default" mit Glanz, Listen "Transparent"
      if kind == "panel" then
         frame:SetTemplate("Transparent")
      else
         frame:SetTemplate("Default", kind == "button")
      end
      return
   end
   local mult = Skin.Mult()
   frame:SetBackdrop({
      bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = mult,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
   })
   local c = (kind == "panel") and FALLBACK.fade or FALLBACK.solid
   frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
   frame:SetBackdropBorderColor(unpack(FALLBACK.border))
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

-- Zeilen-Hervorhebung: Textur und Deckkraft (ElvUI: der weiche Verlauf der Leisten).
function Skin.HighlightTexture()
   if Skin.elvui and Skin.E.Media and Skin.E.Media.Textures and Skin.E.Media.Textures.Highlight then
      return Skin.E.Media.Textures.Highlight, 0.25
   end
   return WHITE, 0.18
end

-- ---------------------------------------------------------------------------
-- Schrift
-- ---------------------------------------------------------------------------

-- ElvUI: FontTemplate() mit Schrift und Kontur des Nutzers (mit Eintrag in E.texts, folgt
-- also Profilwechseln). Die Groesse ist die Groesse der Stelle (10/11/12/13) PLUS die
-- Abweichung der ElvUI-Grundgroesse von 12: wer in ElvUI 14 einstellt, bekommt hier 14
-- statt 12. ElvUI setzt bei einer Aenderung die gespeicherte Groesse wieder ein; unser Haken
-- auf E:UpdateFontTemplates legt danach unsere an und ruft die Rueckrufe (neu vermessen).
-- Ohne ElvUI die Schrift des Spiels (STANDARD_TEXT_FONT, bei ElvUI ohnehin dessen Schrift).
local fontStrings = setmetatable({}, { __mode = "k" })
local fontCallbacks = {}
local fontHooked = false

local function ElvUIFontSize(size)
   local base = Skin.E.db and Skin.E.db.general and tonumber(Skin.E.db.general.fontSize) or 12
   local px = size + base - 12
   if px < 8 then px = 8 end
   return px
end

function Skin.Font(fontString, size, style)
   size = size or 12
   if Skin.elvui and fontString.FontTemplate then
      fontStrings[fontString] = { size, style }
      fontString:FontTemplate(nil, ElvUIFontSize(size), style)
      if not fontHooked and type(Skin.E.UpdateFontTemplates) == "function" then
         fontHooked = true
         hooksecurefunc(Skin.E, "UpdateFontTemplates", function()
            for fs, data in pairs(fontStrings) do
               fs:FontTemplate(nil, ElvUIFontSize(data[1]), data[2])
            end
            for _, fn in ipairs(fontCallbacks) do fn() end
         end)
      end
   else
      fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, style or "OUTLINE")
   end
end

-- Wird gerufen, nachdem ElvUI die Schriften neu gesetzt hat (Groesse, Breite neu rechnen).
function Skin.OnFontsChanged(fn)
   fontCallbacks[#fontCallbacks + 1] = fn
end

-- ---------------------------------------------------------------------------
-- Symbole
-- ---------------------------------------------------------------------------

-- Texturkoordinaten, die den Rand eines Symbols abschneiden (zum Bauzeitpunkt lesen:
-- ElvUI beschneidet erst in E:Initialize).
function Skin.IconCoords()
   if Skin.elvui and Skin.E.TexCoords then
      return unpack(Skin.E.TexCoords)
   end
   return 0.08, 0.92, 0.08, 0.92
end

-- Pfeil (Winkel) fuer den Knopf: eine eigene Textur, damit er mit und ohne ElvUI
-- gleich aussieht. Die Datei zeigt nach unten, nach oben wird sie gespiegelt.
Skin.ARROW = "Interface\\AddOns\\ProfessionMenu\\Media\\chevron.tga"

function Skin.SetArrow(texture, direction)
   texture:SetTexture(Skin.ARROW)
   if direction == "up" then
      texture:SetTexCoord(0, 1, 1, 0)
   else
      texture:SetTexCoord(0, 1, 0, 1)
   end
end

-- ---------------------------------------------------------------------------
-- Verschieben (Mover)
-- ---------------------------------------------------------------------------

-- Mit ElvUI: ElvUIs Mover. Der Knopf darf danach nicht mehr selbst neu verankert
-- werden (der Mover haelt ihn). Ohne ElvUI: false, UI.lua verschiebt selbst.
function Skin.CreateMover(frame, name, label, configString)
   if Skin.elvui and Skin.E.CreateMover then
      Skin.E:CreateMover(frame, name, label, nil, nil, nil, "ALL,GENERAL", nil, configString)
      return true
   end
   return false
end

-- Setzt den Mover zurueck. ElvUI sucht ihn ueber den TEXT, nicht den Namen.
function Skin.ResetMover(label)
   if Skin.elvui and Skin.E.ResetMovers then
      Skin.E:ResetMovers(label)
      return true
   end
   return false
end
