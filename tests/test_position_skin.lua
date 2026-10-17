-- tests/test_position_skin.lua
-- ---------------------------------------------------------------------------
-- Position und Aussehen (UI.lua, Skin.lua, Options.lua).
--   Standalone: Standardplatz, entsperren/sperren/ziehen, Speichern in ProfessionMenuDB.pos, Neuanmeldung,
--               Skalierung, Zuruecksetzen, flaches Design in ElvUIs Standardfarben, Pixelraster
--   ElvUI:      Vorlagen (Default/Transparent), Schrift (FontTemplate), Mover "ProfessionMenuMover",
--               Standardplatz ueber RightChatPanel, /berufe unlock|scale -> Hinweis, /berufe reset -> ResetMovers
--               (ueber den TEXT), Wertfarbe folgt dem Nutzer, Optionen als eigener Eintrag unter /ec
--   Start:      ElvUI fertig / noch nicht fertig (Warten per OnUpdate, Aufgeben nach 10 s)
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function near3(r, g, b, want, msg)
      H.near(r, want[1], 1e-6, (msg or "") .. " r")
      H.near(g, want[2], 1e-6, (msg or "") .. " g")
      H.near(b, want[3], 1e-6, (msg or "") .. " b")
   end

   local function elvui(opts)
      local PM, M = F.boot(H, opts)
      H.allowFrames({ "RightChatPanel" })
      return PM, M, ElvUI[1]
   end

   -- ======================================================================
   H.section("Standalone: position")
   -- ======================================================================

   H.test("default position: bottom right, 20 px from the right edge and 210 px up", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      local b = PM.UI.GetButton()
      local p, rel, rp, x, y = b:GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      H.eq(rel, UIParent)
      H.eq(rp, "BOTTOMRIGHT")
      H.eq(x, -20)
      H.eq(y, 210)
      H.eq(b:GetNumPoints(), 1, "exactly one anchor")
   end)

   H.test("a saved position is used at login", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { pos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 33, y = -44 } } })
      local p, rel, rp, x, y = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "TOPLEFT"); H.eq(rel, UIParent); H.eq(rp, "TOPLEFT"); H.eq(x, 33); H.eq(y, -44)
   end)

   H.test("a saved position without relPoint falls back to its own point; a broken one falls back to the default", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { pos = { point = "LEFT", x = 5, y = 6 } } })
      local p, _, rp = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "LEFT")
      H.eq(rp, "LEFT")
      PM = F.boot(H, { learned = { "alchemy" }, db = { pos = "garbage" } })
      p = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      PM = F.boot(H, { learned = { "alchemy" }, db = { pos = {} } })
      p = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
   end)

   H.test("locked by default: not movable, drag does nothing, position not saved", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local b = PM.UI.GetButton()
      H.falsy(b:IsMovable())
      local _, _, _, x0, y0 = b:GetPoint(1)
      M.Drag(b, 50, 50)
      local _, _, _, x1, y1 = b:GetPoint(1)
      H.eq(x1, x0); H.eq(y1, y0)
      H.eq(PM.db.pos, nil)
   end)

   H.test("/berufe unlock makes the button draggable; dragging saves the position; /berufe lock freezes it again", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local b = PM.UI.GetButton()
      M.Slash("/berufe unlock")
      H.eq(PM.db.locked, false)
      H.truthy(b:IsMovable())
      H.truthy(b.__drag.LeftButton)
      M.Drag(b, -30, 40)
      H.truthy(PM.db.pos, "position saved")
      H.eq(PM.db.pos.point, "BOTTOMRIGHT")
      H.eq(PM.db.pos.relPoint, "BOTTOMRIGHT")
      H.near(PM.db.pos.x, -50, 1e-6)
      H.near(PM.db.pos.y, 250, 1e-6)
      H.falsy(PM.UI.GetMenu():IsShown(), "a drag must not open the list")
      M.Slash("/berufe lock")
      H.eq(PM.db.locked, true)
      H.falsy(b:IsMovable())
      H.eq(next(b.__drag), nil, "no drag buttons registered")
      M.Drag(b, 100, 100)
      H.near(PM.db.pos.x, -50, 1e-6)
   end)

   H.test("the position survives a relog (SavedVariables) and the list opens at the new place", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe unlock")
      M.Drag(PM.UI.GetButton(), -100, 200)
      local saved = M.SavedVariables()
      H.truthy(saved.ProfessionMenuDB.pos)
      PM, M = F.boot(H, { learned = { "alchemy" }, saved = saved })
      local p, rel, rp, x, y = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      H.eq(x, -120)
      H.eq(y, 410)
      F.open(PM)
      -- the button now sits in the upper half of the screen: the list opens downwards
      H.near(PM.UI.GetMenu():GetTop(), 410 - PM.UI.sizes.menuGap, 1e-6)
   end)

   H.test("/berufe reset removes the saved position and puts the button back to the default place", function()
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      M.Slash("/berufe unlock")
      M.Drag(PM.UI.GetButton(), -100, 200)
      H.truthy(PM.db.pos)
      M.Slash("/berufe reset")
      H.eq(PM.db.pos, nil)
      local p, rel, rp, x, y = PM.UI.GetButton():GetPoint(1)
      H.eq(p, "BOTTOMRIGHT"); H.eq(x, -20); H.eq(y, 210)
      H.eq(PM.UI.GetButton():GetNumPoints(), 1)
      H.eq(F.chatCount(M, "Position reset."), 1)
   end)

   H.test("the unlocked state is restored at login (the saved 'locked = false' is respected)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { locked = false } })
      local b = PM.UI.GetButton()
      H.truthy(b:IsMovable())
      H.truthy(b.__clamped, "clamped to the screen")
   end)

   H.test("a drag with the menu open does not leave the list behind: it is re-anchored at the next open", function()
      local PM, M = F.boot(H, { learned = { "alchemy" }, db = { locked = false } })
      F.open(PM)
      local before = PM.UI.GetMenu():GetLeft()
      PM.UI.Close()
      M.Drag(PM.UI.GetButton(), -200, 0)
      F.open(PM)
      H.truthy(PM.UI.GetMenu():GetLeft() < before)
   end)

   -- ======================================================================
   H.section("Standalone: scale")
   -- ======================================================================

   H.test("/berufe scale scales the button and the list; the list opens in the right place at scale 1.5", function()
      local PM, M = F.boot(H, { learned = { "alchemy", "mining" } })
      M.Slash("/berufe scale 1.5")
      H.eq(PM.db.scale, 1.5)
      H.eq(PM.UI.GetButton():GetScale(), 1.5)
      H.eq(PM.UI.GetMenu():GetScale(), 1.5)
      F.open(PM)
      local b, m = PM.UI.GetButton(), PM.UI.GetMenu()
      H.near(m:GetBottom() * 1.5, b:GetTop() * 1.5 + PM.UI.sizes.menuGap * 1.5, 1e-6)
      H.near(m:GetRight() * 1.5, b:GetRight() * 1.5, 1e-6)
      H.eq(F.chatCount(M, "Scale: 1.50"), 1)
   end)

   H.test("the saved scale is applied at login", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { scale = 0.75 } })
      H.eq(PM.UI.GetButton():GetScale(), 0.75)
      H.eq(PM.UI.GetMenu():GetScale(), 0.75)
   end)

   H.test("a saved scale that is not a number is ignored (scale 1)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, db = { scale = "huge" } })
      H.eq(PM.UI.GetButton():GetScale(), 1)
   end)

   H.test("changing the scale keeps the button where it is on the screen", function()
      -- SetPoint offsets are in the frame's own (scaled) units: UI.ApplyScale(true) re-anchors by the centre.
      local PM, M = F.boot(H, { learned = { "alchemy" } })
      local b = PM.UI.GetButton()
      local cx0, cy0 = b:GetCenter()
      cx0, cy0 = cx0 * b:GetEffectiveScale(), cy0 * b:GetEffectiveScale()
      M.Slash("/berufe scale 1.5")
      local cx1, cy1 = b:GetCenter()
      cx1, cy1 = cx1 * b:GetEffectiveScale(), cy1 * b:GetEffectiveScale()
      H.near(cx1, cx0, 1, "screen x of the button centre")
      H.near(cy1, cy0, 1, "screen y of the button centre")
   end)

   -- ======================================================================
   H.section("Standalone: flat design in ElvUI's default colours, pixel grid")
   -- ======================================================================

   H.test("colours: black 1px border, dark fill, orange value colour; text white, secondary text grey", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      local r, g, b = PM.Skin.BorderColor()
      near3(r, g, b, { 0, 0, 0 }, "border")
      r, g, b = PM.Skin.AccentColor()
      near3(r, g, b, { 0.99, 0.48, 0.17 }, "accent")
      r, g, b = PM.Skin.TextColor()
      near3(r, g, b, { 1, 1, 1 }, "text")
      r, g, b = PM.Skin.DimColor()
      near3(r, g, b, { 0.65, 0.65, 0.65 }, "dim")
      H.eq(PM.Skin.elvui, false)
      H.eq(PM.Skin.E, nil)
   end)

   H.test("backdrop of button and boxes: solid; of the list: translucent; edge size is one pixel", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      local bd = PM.UI.GetButton():GetBackdrop()
      H.eq(bd.edgeSize, 1)
      H.eq(bd.bgFile, "Interface\\Buttons\\WHITE8X8")
      H.eq(bd.edgeFile, "Interface\\Buttons\\WHITE8X8")
      bd = PM.UI.GetMenu():GetBackdrop()
      H.eq(bd.edgeSize, 1)
      local _, _, _, a = PM.UI.GetMenu():GetBackdropColor()
      H.near(a, 0.8, 1e-6)
      local box = PM.UI.rows[1].box
      local _, _, _, a2 = box:GetBackdropColor()
      H.near(a2, 1, 1e-6)
   end)

   H.test("row highlight uses the accent colour at 0.18 alpha with the white texture", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      local hl = PM.UI.rows[1].hl
      H.eq(hl:GetTexture(), "Interface\\Buttons\\WHITE8X8")
      local vr, vg, vb, va = unpack(hl.__vertex)
      near3(vr, vg, vb, { 0.99, 0.48, 0.17 }, "highlight")
      H.near(va, 0.18, 1e-6)
   end)

   H.test("pixel grid: Px() rounds to whole pixels (multiples of the pixel size) and never below one pixel", function()
      local PM = F.boot(H, { learned = {}, world = { cvars = { gxResolution = "1920x1080" }, uiScale = 0.64 } })
      local mult = PM.Skin.Mult()
      H.near(mult, (768 / 1080) / 0.64, 1e-9)
      for _, v in ipairs({ 1, 4, 12, 22, 24, 36, 150, 0.2 }) do
         local px = PM.Skin.Px(v)
         local n = px / mult
         H.near(n, math.floor(n + 0.5), 1e-6, "Px(" .. v .. ") is a whole number of pixels")
         H.truthy(px >= mult - 1e-9, "at least one pixel")
      end
   end)

   H.test("all measures of the UI are whole pixels at a non-trivial UI scale", function()
      local PM = F.boot(H, { learned = { "alchemy", "mining" }, world = { cvars = { gxResolution = "1680x1050" }, uiScale = 0.8 } })
      local mult = PM.Skin.Mult()
      for name, v in pairs(PM.UI.sizes) do
         local n = v / mult
         H.near(n, math.floor(n + 0.5), 1e-6, "sizes." .. name)
      end
      F.open(PM)
      local n = PM.UI.GetMenu():GetHeight() / mult
      H.near(n, math.floor(n + 0.5), 1e-6, "list height")
      n = PM.UI.GetMenu():GetWidth() / mult
      H.near(n, math.floor(n + 0.5), 1e-6, "list width")
   end)

   H.test("with a pixel perfect scale of 768/height the measures are the plain integers", function()
      local PM = F.boot(H, { learned = {}, world = { cvars = { gxResolution = "1920x1080" }, uiScale = 768 / 1080 } })
      H.near(PM.Skin.Mult(), 1, 1e-9)
      H.near(PM.UI.sizes.rowH, 24, 1e-9)
      H.truthy(PM.UI.sizes.buttonW >= 150, "the button is at least 150 wide (the widest possible row decides)")
      H.near(PM.UI.sizes.buttonW, math.ceil(PM.UI.sizes.buttonW), 1e-9, "a whole number of pixels")
   end)

   H.test("a missing or odd resolution cvar falls back to 768 pixels height", function()
      local PM = F.boot(H, { learned = {}, world = { cvars = { gxResolution = "garbage" } } })
      H.near(PM.Skin.Mult(), 1, 1e-9)
   end)

   -- ======================================================================
   H.section("ElvUI: look")
   -- ======================================================================

   H.test("ElvUI detected: Skin.elvui, engine stored, templates Default (button, boxes) and Transparent (list)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      H.eq(PM.Skin.elvui, true)
      H.eq(PM.Skin.E, E)
      local button, menu = PM.UI.GetButton(), PM.UI.GetMenu()
      H.eq(button.template, "Default")
      H.eq(button.glossTex, true, "buttons get the gloss like S:HandleButton")
      H.eq(menu.template, "Transparent")
      H.eq(PM.UI.rows[1].box.template, "Default")
      H.eq(PM.UI.rows[1].box.glossTex, nil)
   end)

   H.test("ElvUI backdrop colours come from E.media (border, fill, translucent fill)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local r, g, b = PM.UI.GetButton():GetBackdropBorderColor()
      near3(r, g, b, E.media.bordercolor, "button border")
      r, g, b = PM.UI.GetButton():GetBackdropColor()
      near3(r, g, b, E.media.backdropcolor, "button fill")
      local _, _, _, a = PM.UI.GetMenu():GetBackdropColor()
      H.near(a, E.media.backdropfadecolor[4], 1e-6, "list alpha")
   end)

   H.test("ElvUI fonts: FontTemplate with the ElvUI font, the size given and the outline of the user", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local fs = PM.UI.rows[1].text
      local path, size, flags = fs:GetFont()
      H.eq(path, E.media.normFont)
      H.eq(size, 12)
      H.eq(flags, "OUTLINE", "E.db.general.fontStyle")
      path, size = PM.UI.rows[1].rank:GetFont()
      H.eq(size, 11)
      path, size, flags = PM.UI.headers[1].text:GetFont()
      H.eq(size, 10)
      H.eq(flags, "OUTLINE")
      H.truthy(E.texts[fs], "registered for profile changes")
   end)

   H.test("ElvUI font styles NONE and MONOCHROMEOUTLINE (set by the user in ElvUI) work; headings keep their outline", function()
      for _, style in ipairs({ "NONE", "MONOCHROMEOUTLINE", "THICKOUTLINE" }) do
         local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { fontStyle = style } })
         H.truthy(PM.ready, style)
         local _, _, flags = PM.UI.rows[1].text:GetFont()
         H.eq(flags, style, "row text follows the user's style " .. style)
         _, _, flags = PM.UI.headers[1].text:GetFont()
         H.eq(flags, "OUTLINE", "headings are always outlined")
         if style == "NONE" then
            local sx = PM.UI.rows[1].text.__shadowOffset
            H.truthy(sx and sx[1] ~= 0, "ElvUI draws a shadow instead of an outline")
         end
      end
   end)

   H.test("ElvUI icon texcoords: cropped like ElvUI (cropIcon 2 -> 0.08 .. 0.92), uncropped with cropIcon 0", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      F.open(PM)
      local ulx, uly, llx, lly, urx = PM.UI.rows[1].icon:GetTexCoord()
      H.near(ulx, 0.08, 1e-6)
      H.near(urx, 0.92, 1e-6)
      PM = elvui({ learned = { "alchemy" }, elvui = { cropIcon = 0 } })
      F.open(PM)
      ulx, uly, llx, lly, urx = PM.UI.rows[1].icon:GetTexCoord()
      H.near(ulx, 0, 1e-6)
      H.near(urx, 1, 1e-6)
   end)

   H.test("ElvUI icon texcoords come from E.TexCoords", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      E.TexCoords = { 0.1, 0.9, 0.1, 0.9 }
      PM.UI.Close()
      PM.UI.Refresh(true)
      local ulx = PM.UI.rows[1].icon:GetTexCoord()
      H.near(ulx, 0.1, 1e-6)
   end)

   H.test("ElvUI highlight texture is ElvUI's Highlight.tga at 0.25 alpha", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local hl = PM.UI.rows[1].hl
      H.eq(hl:GetTexture(), E.Media.Textures.Highlight)
      local _, _, _, va = unpack(hl.__vertex)
      H.near(va, 0.25, 1e-6)
   end)

   H.test("ElvUI accent: header colour, row highlight and open-state border follow E.media.rgbvaluecolor", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local ar, ag, ab = unpack(E.media.rgbvaluecolor)
      local r, g, b = PM.UI.headers[1].text:GetTextColor()
      near3(r, g, b, { ar, ag, ab }, "header")
      F.open(PM)
      r, g, b = PM.UI.GetButton():GetBackdropBorderColor()
      near3(r, g, b, { ar, ag, ab }, "open border")
   end)

   H.test("ElvUI accent change at runtime: the registered update function recolours headers, highlight and border", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local n = 0
      for _ in pairs(E.valueColorUpdateFuncs) do n = n + 1 end
      H.eq(n, 1, "one update function registered")
      F.open(PM)
      E:SetValueColor(1, 0, 0)
      local r, g, b = PM.UI.headers[1].text:GetTextColor()
      near3(r, g, b, { 1, 0, 0 }, "header")
      r, g, b = unpack(PM.UI.rows[1].hl.__vertex)
      near3(r, g, b, { 1, 0, 0 }, "highlight")
      r, g, b = PM.UI.GetButton():GetBackdropBorderColor()
      near3(r, g, b, { 1, 0, 0 }, "open border")
   end)

   H.test("ElvUI pixel size: measures follow E.mult", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { mult = 0.75 } })
      H.near(PM.Skin.Mult(), 0.75, 1e-9)
      for name, v in pairs(PM.UI.sizes) do
         H.near(v / 0.75, math.floor(v / 0.75 + 0.5), 1e-6, "sizes." .. name)
      end
      H.near(PM.UI.sizes.pad, E.Border, 1e-9, "inner padding = E.Border")
      H.near(PM.UI.sizes.line, 0.75, 1e-9, "separator = one pixel")
   end)

   H.test("ElvUI without pixel perfect: inner padding is E.Border = 2 pixels (the template draws an inner border)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { mult = 0.75, pixelMode = false } })
      H.near(E.Border, 1.5, 1e-9)
      H.near(PM.UI.sizes.pad, 1.5, 1e-9)
      H.near(PM.UI.sizes.line, 0.75, 1e-9, "separator stays one pixel")
   end)

   H.test("with ElvUI the list is not scaled by the addon (ElvUI's UI scale decides)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true, db = { scale = 1.7 } })
      H.eq(PM.UI.GetButton():GetScale(), 1)
      H.eq(PM.UI.GetMenu():GetScale(), 1)
   end)

   -- ======================================================================
   H.section("ElvUI: mover and position")
   -- ======================================================================

   H.test("a mover 'ProfessionMenuMover' is created with the localized label and the config string", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local mover = rawget(_G, "ProfessionMenuMover")
      H.truthy(mover)
      local info = E.CreatedMovers.ProfessionMenuMover
      H.truthy(info)
      H.eq(info.text, "Professions button")
      H.eq(info.parent, PM.UI.GetButton())
      H.truthy(info.type.ALL)
      H.truthy(info.type.GENERAL)
      H.eq(info.configString, "professionMenu")
      PM = elvui({ learned = { "alchemy" }, elvui = true, locale = "deDE" })
      H.eq(ElvUI[1].CreatedMovers.ProfessionMenuMover.text, "Berufe-Knopf")
   end)

   H.test("default place: the button sits above the right chat panel (4 px gap), held by the mover", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local button = PM.UI.GetButton()
      local mover = ProfessionMenuMover
      local _, rel = button:GetPoint(1)
      H.eq(rel, mover, "the button is anchored to the mover")
      H.eq(button:GetNumPoints(), 1)
      local p, relMover, rp, x, y = mover:GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      H.eq(relMover, RightChatPanel)
      H.eq(rp, "TOPRIGHT")
      H.eq(x, 0)
      H.eq(y, 4)
      H.near(button:GetBottom(), RightChatPanel:GetTop() + 4, 1e-6)
      H.near(button:GetRight(), RightChatPanel:GetRight(), 1e-6)
   end)

   H.test("without a RightChatPanel the button goes to ElvUI's UIParent bottom right (250 up)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { rightChatPanel = false } })
      local mover = ProfessionMenuMover
      local p, rel, rp, x, y = mover:GetPoint(1)
      H.eq(p, "BOTTOMRIGHT")
      H.eq(rel, UIParent)
      H.eq(y, 250)
   end)

   H.test("the saved position of an earlier standalone run is ignored with ElvUI (the mover decides)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true,
                               db = { pos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 5, y = -5 } } })
      local _, rel = PM.UI.GetButton():GetPoint(1)
      H.eq(rel, ProfessionMenuMover)
      local p, relMover = ProfessionMenuMover:GetPoint(1)
      H.eq(relMover, RightChatPanel)
   end)

   H.test("moving the mover moves the button and the list follows at the next open", function()
      local PM, M, E = elvui({ learned = { "alchemy", "mining" }, elvui = true, db = { direction = "up" } })
      local button, mover = PM.UI.GetButton(), ProfessionMenuMover
      E:ToggleMoveMode(true)
      H.truthy(mover:IsShown())
      local bottom0 = button:GetBottom()
      M.Drag(mover, -200, 300)
      H.near(button:GetBottom(), bottom0 + 300, 1e-6)
      H.truthy(E.db.movers and E.db.movers.ProfessionMenuMover, "ElvUI saved the mover position")
      E:ToggleMoveMode(false)
      F.open(PM)
      H.near(PM.UI.GetMenu():GetBottom(), button:GetTop() + PM.UI.sizes.menuGap, 1e-6)
   end)

   H.test("/berufe unlock and lock with ElvUI only print the hint; nothing changes", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      M.Slash("/berufe unlock")
      H.eq(F.chatCount(M, "/moveui"), 1)
      H.eq(PM.db.locked, true)
      H.falsy(PM.UI.GetButton():IsMovable())
      M.Slash("/berufe lock")
      H.eq(F.chatCount(M, "/moveui"), 2)
      H.eq(PM.db.locked, true)
   end)

   H.test("the ElvUI hint is German in deDE and names the mover label", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true, locale = "deDE" })
      M.Slash("/berufe unlock")
      H.eq(F.chatCount(M, "ElvUI ist aktiv: Knopf mit /moveui (Ankerpunkte) verschieben, Anker 'Berufe-Knopf'."), 1)
   end)

   H.test("/berufe scale with ElvUI only prints the hint and leaves the scale alone", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      M.Slash("/berufe scale 1.5")
      H.eq(PM.db.scale, 1)
      H.eq(PM.UI.GetButton():GetScale(), 1)
      H.eq(F.chatCount(M, "With ElvUI the size follows ElvUI's UI scale"), 1)
      H.eq(F.chatCount(M, "Scale: "), 0)
   end)

   H.test("/berufe reset with ElvUI puts the mover back to its default place and keeps the button on the mover", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local button, mover = PM.UI.GetButton(), ProfessionMenuMover
      mover:ClearAllPoints()
      mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      E.db.movers = { ProfessionMenuMover = "CENTER,UIParent,CENTER,0,0" }
      M.Slash("/berufe reset")
      local p, rel, rp, x, y = mover:GetPoint(1)
      H.eq(p, "BOTTOMRIGHT", "mover back at its default point")
      H.eq(rel, RightChatPanel)
      H.eq(y, 4)
      local _, brel = button:GetPoint(1)
      H.eq(brel, mover, "the button is still held by the mover")
      H.eq(E.db.movers and E.db.movers.ProfessionMenuMover, nil, "ElvUI forgot the saved position")
      H.eq(F.chatCount(M, "Position reset."), 1)
   end)

   H.test("/berufe reset calls E:ResetMovers with the label text (ElvUI matches by text, not by name)", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      local calls = {}
      local orig = E.ResetMovers
      E.ResetMovers = function(self, arg)
         calls[#calls + 1] = arg
         return orig(self, arg)
      end
      M.Slash("/berufe reset")
      H.deepEq(calls, { "Professions button" })
   end)

   -- ======================================================================
   H.section("ElvUI: options as own top-level entry in /ec")
   -- ======================================================================

   H.test("the options group is registered with LibElvUIPlugin and inserted when ElvUI_OptionsUI loads", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      H.eq(E.Options.args.professionMenu, nil, "not before the options UI is loaded")
      E.LoadOptions()
      local group = E.Options.args.professionMenu
      H.truthy(group)
      H.eq(group.type, "group")
      H.eq(group.name, "Professions menu")
      for _, key in ipairs({ "sort", "headers", "ranks", "direction", "move" }) do
         H.truthy(group.args[key], key)
      end
      H.eq(group.args.sort.type, "select")
      H.deepEq(group.args.sort.values, { cat = "by category", alpha = "alphabetical", rank = "by skill level" })
      H.deepEq(group.args.direction.values, { auto = "automatic", up = "up", down = "down" })
      H.eq(group.args.headers.type, "toggle")
      H.eq(group.args.move.type, "execute")
   end)

   H.test("options registered after ElvUI_OptionsUI is already loaded are inserted at once", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true,
                               before = function() end })
      E.LoadOptions()
      H.truthy(E.Options.args.professionMenu)
   end)

   H.test("option get/set read and write ProfessionMenuDB and rebuild the list", function()
      local PM, M, E = elvui({ learned = { "alchemy", "fishing" }, elvui = true })
      E.LoadOptions()
      local group = E.Options.args.professionMenu
      local function info(key) return { [1] = key } end
      H.eq(group.get(info("sort")), "cat")
      group.set(info("sort"), "alpha")
      H.eq(PM.db.sort, "alpha")
      F.open(PM)
      H.deepEq(F.rowNames(PM), { "Alchemy", "Fishing" })
      group.set(info("ranks"), false)
      H.eq(F.rows(PM)[1].rank, "")
      group.set(info("headers"), false)
      group.set(info("direction"), "down")
      H.eq(PM.db.direction, "down")
      H.eq(group.get(info("headers")), false)
   end)

   H.test("the 'move' button toggles ElvUI's move mode", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      E.LoadOptions()
      E.Options.args.professionMenu.args.move.func()
      H.eq(E.moveModeToggles, 1)
      H.truthy(ProfessionMenuMover:IsShown())
   end)

   H.test("option labels are German in deDE", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true, locale = "deDE" })
      E.LoadOptions()
      local group = E.Options.args.professionMenu
      H.eq(group.name, "Berufe-Men\195\188")
      H.eq(group.args.sort.name, "Sortierung")
   end)

   H.test("without ElvUI's plugin library (or without ElvUI) Options.lua does nothing and does not fail", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { plugins = false } })
      H.eq(E.Options.args.professionMenu, nil)
      PM = F.boot(H, { learned = { "alchemy" } })
      H.truthy(PM.ready)
   end)

   -- ======================================================================
   H.section("Start with ElvUI: waiting for E.initialized")
   -- ======================================================================

   H.test("E.initialized already true at PLAYER_LOGIN: started at once, ElvUI look, nothing waits", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = true })
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, true)
      H.eq(PM.frame:GetScript("OnUpdate"), nil)
      H.len(M.UpdateFrames(), 0)
   end)

   H.test("ElvUI's own PLAYER_LOGIN handler runs before ours: initialized in time, no waiting", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { initialized = false, initOnLogin = true } })
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, true)
      H.eq(PM.frame:GetScript("OnUpdate"), nil)
   end)

   H.test("ElvUI not initialized yet: the addon waits with an OnUpdate and does not build anything", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = "pending" })
      H.falsy(PM.ready)
      H.truthy(PM.frame:GetScript("OnUpdate"))
      H.eq(rawget(_G, "ProfessionMenuButton"), nil)
      M.Slash("/berufe")
      M.Advance(1)
      H.falsy(PM.ready)
      H.eq(F.chatCount(M, "Error in"), 0)
      H.len(M.UpdateFrames(), 1)
   end)

   H.test("ElvUI becomes ready after 3 s: the UI appears right after, with the ElvUI look; the wait loop is gone", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { initialized = false, initAfter = 3 } })
      M.Advance(2.9)
      H.falsy(PM.ready)
      M.Advance(0.2)
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, true)
      H.eq(PM.UI.GetButton().template, "Default")
      H.truthy(rawget(_G, "ProfessionMenuMover"))
      H.eq(PM.frame:GetScript("OnUpdate"), nil)
      H.len(M.UpdateFrames(), 0)
   end)

   H.test("ElvUI never becomes ready: after 10 s the addon starts standalone and stays standalone", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { initialized = false, initAfter = 30 } })
      M.Advance(9.8)
      H.falsy(PM.ready)
      M.Advance(0.4)
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, false)
      H.eq(rawget(_G, "ProfessionMenuMover"), nil)
      H.eq(PM.UI.GetButton():GetPoint(1), "BOTTOMRIGHT")
      local _, rel = PM.UI.GetButton():GetPoint(1)
      H.eq(rel, UIParent, "standalone default place")
      M.Advance(30)
      H.eq(PM.Skin.elvui, false, "a late ElvUI does not change the look afterwards")
      H.len(M.UpdateFrames(), 0)
   end)

   H.test("ElvUI present and waiting, combat starts before it is ready: the UI is built after the fight", function()
      local PM, M, E = elvui({ learned = { "alchemy" }, elvui = { initialized = false, initAfter = 2 } })
      M.EnterCombat()
      M.Advance(2.5)
      H.falsy(PM.ready, "nothing built in combat")
      H.truthy(PM.startAfterCombat)
      M.LeaveCombat()
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, true)
      H.len(M.blocked, 0)
   end)

   H.test("an empty ElvUI table or one without engine/media does not break the start (standalone look)", function()
      local PM = F.boot(H, { learned = { "alchemy" }, before = function() rawset(_G, "ElvUI", {}) end })
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, false)
      PM = F.boot(H, { learned = { "alchemy" }, before = function()
         rawset(_G, "ElvUI", { { initialized = true } })
      end })
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, false, "E without media/db is not usable")
   end)

   H.test("without ElvUI at all: ready at login, standalone", function()
      local PM = F.boot(H, { learned = { "alchemy" } })
      H.truthy(PM.ready)
      H.eq(PM.Skin.elvui, false)
      H.eq(PM.frame:GetScript("OnUpdate"), nil)
   end)
end
