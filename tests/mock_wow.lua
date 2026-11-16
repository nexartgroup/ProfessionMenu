-- tests/mock_wow.lua
-- ---------------------------------------------------------------------------
-- Ein strenger Attrappen-Client fuer WoW: Forever (Retail-Technik, Teilmenge). Streng heisst: was der
-- echte Client ablehnt, lehnt auch die Attrappe ab.
--   * SetBackdrop & Co. gibt es nur an Rahmen mit der Vorlage "BackdropTemplate".
--   * Texture:SetTexture(r, g, b, a) (3.3.5a) ist ein Fehler; es gilt SetColorTexture.
--   * Geschuetzte Rahmen (Secure*-Vorlagen) lassen im Kampf kein Show/Hide/SetPoint/SetAttribute/... zu.
--   * Sichere Knoepfe feuern wie SecureActionButton_OnClick: je nach CVar ActionButtonUseKeyDown beim
--     Niederdruecken oder Loslassen, sofern das Attribut useOnKeyDown sie nicht festlegt.
--   * Unbekannte Methoden eines Rahmens sind ein Fehler ("attempt to call method ... (a nil value)").
-- Gelaufen wird mit LuaJIT (Lua 5.1, wie im Spiel) in einer Sandbox ohne os/io/require.
-- ---------------------------------------------------------------------------

local Mock = {}

local STD = {
   "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset",
   "select", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "string", "table", "math",
   "loadstring", "newproxy", "collectgarbage", "bit",
}

-- ---------------------------------------------------------------------------
-- Flaechen (Texturen, Schriften)
-- ---------------------------------------------------------------------------

local RegionMethods = {}
local RegionMT = {
   __index = function(self, key)
      local m = RegionMethods[key]
      if m then return m end
      return nil
   end,
}

local function noop() end

for _, name in ipairs({
   "ClearAllPoints", "SetAllPoints", "SetTexCoord", "SetVertexColor", "SetAtlas", "SetBlendMode", "SetJustifyH",
   "SetJustifyV", "SetWordWrap", "SetDrawLayer", "SetTextColor", "SetShadowOffset", "SetFontObject",
}) do
   RegionMethods[name] = noop
end

function RegionMethods:SetPoint(point, rel, relPoint, x, y)
   assert(type(point) == "string", "SetPoint: point must be a string")
   self._points[#self._points + 1] = { point, rel, relPoint, x, y }
end
function RegionMethods:SetWidth(w) assert(type(w) == "number", "SetWidth needs a number") self._w = w end
function RegionMethods:SetHeight(h) assert(type(h) == "number", "SetHeight needs a number") self._h = h end
function RegionMethods:GetWidth() return self._w end
function RegionMethods:GetHeight() return self._h end
function RegionMethods:Show() self._shown = true end
function RegionMethods:Hide() self._shown = false end
function RegionMethods:IsShown() return self._shown end
function RegionMethods:SetTexture(file, ...)
   if type(file) == "number" and select("#", ...) >= 2 then
      error("SetTexture(r, g, b, a) was removed; use SetColorTexture", 2)
   end
   self._texture = file
end
function RegionMethods:SetColorTexture(r, g, b, a)
   assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture needs r, g, b")
   self._color = { r, g, b, a }
end
function RegionMethods:SetFont(path, size, flags)
   assert(type(path) == "string" and path ~= "", "SetFont: font path missing")
   assert(type(size) == "number" and size > 0, "SetFont: size must be a positive number")
   assert(flags == nil or type(flags) == "string", "SetFont: flags must be a string")
   self._font = { path, size, flags }
end
function RegionMethods:SetText(text) self._text = text == nil and "" or tostring(text) end
function RegionMethods:GetText() return self._text end
function RegionMethods:GetStringWidth()
   local size = self._font and self._font[2] or 12
   return #self._text * size * 0.5
end
function RegionMethods:GetStringHeight() return self._font and self._font[2] or 12 end

local function NewRegion(kind, parent)
   return setmetatable({ _kind = kind, _parent = parent, _text = "", _shown = true, _points = {}, _w = 0, _h = 0 }, RegionMT)
end

-- ---------------------------------------------------------------------------
-- Rahmen
-- ---------------------------------------------------------------------------

local FrameMethods = {}
local BackdropMethods = {}

local PROTECTED_METHODS = {
   Show = true, Hide = true, SetShown = true, SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
   SetWidth = true, SetHeight = true, SetSize = true, SetAttribute = true, SetScale = true,
   SetFrameStrata = true, SetFrameLevel = true, EnableMouse = true, SetParent = true,
}

local function NewFrameClass(world)
   local MT = {}
   MT.__index = function(self, key)
      local m = FrameMethods[key]
      if m then
         if PROTECTED_METHODS[key] and self._secure then
            return function(frame, ...)
               if world.combat then
                  error("ADDON_ACTION_BLOCKED: " .. tostring(frame._name or "?") .. ":" .. key .. "() in combat", 2)
               end
               return m(frame, ...)
            end
         end
         return m
      end
      local b = BackdropMethods[key]
      if b and self._backdrop then return b end
      return nil
   end
   return MT
end

function FrameMethods:SetPoint(point, rel, relPoint, x, y)
   assert(type(point) == "string", "SetPoint: point must be a string")
   if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
   self._points[#self._points + 1] = { point, rel, relPoint, x, y }
end
function FrameMethods:ClearAllPoints() self._points = {} end
function FrameMethods:SetAllPoints() self._points = { { "ALL" } } end
function FrameMethods:GetPoint(i)
   local p = self._points[i or 1]
   if not p then return nil end
   return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0
end
function FrameMethods:SetWidth(w) assert(type(w) == "number" and w == w, "SetWidth needs a number") self._w = w end
function FrameMethods:SetHeight(h) assert(type(h) == "number" and h == h, "SetHeight needs a number") self._h = h end
function FrameMethods:SetSize(w, h) self._w, self._h = w, h end
function FrameMethods:GetWidth() return self._w end
function FrameMethods:GetHeight() return self._h end
function FrameMethods:SetScale(s) assert(type(s) == "number" and s > 0, "SetScale must be positive") self._scale = s end
function FrameMethods:GetScale() return self._scale end
function FrameMethods:GetEffectiveScale()
   local parent = self._parent
   return self._scale * ((parent and parent ~= self) and parent:GetEffectiveScale() or 1)
end
function FrameMethods:SetAlpha(a) self._alpha = a end
function FrameMethods:GetAlpha() return self._alpha end
function FrameMethods:SetFrameStrata(s) self._strata = s end
function FrameMethods:GetFrameStrata() return self._strata end
function FrameMethods:SetFrameLevel(l) assert(type(l) == "number" and l >= 0, "SetFrameLevel needs >= 0") self._level = l end
function FrameMethods:GetFrameLevel() return self._level end
function FrameMethods:SetClampedToScreen() end
function FrameMethods:SetMovable(v) self._movable = v and true or false end
function FrameMethods:IsMovable() return self._movable end
function FrameMethods:EnableMouse(v) self._mouse = v end
function FrameMethods:RegisterForDrag(...) self._drag = { ... } end
function FrameMethods:StartMoving() self._moving = true end
function FrameMethods:StopMovingOrSizing() self._moving = false end
function FrameMethods:SetParent(p) self._parent = p end
function FrameMethods:GetParent() return self._parent end
function FrameMethods:GetName() return self._name end
function FrameMethods:IsProtected() return self._secure and true or false end
function FrameMethods:SetAttribute(k, v) self._attrs[k] = v end
function FrameMethods:GetAttribute(k) return self._attrs[k] end
function FrameMethods:RegisterForClicks(...)
   self._clicks = {}
   for _, c in ipairs({ ... }) do self._clicks[c] = true end
end
function FrameMethods:RegisterEvent(e) self._events[e] = true end
function FrameMethods:UnregisterEvent(e) self._events[e] = nil end
function FrameMethods:SetScript(name, fn) self._scripts[name] = fn end
function FrameMethods:GetScript(name) return self._scripts[name] end
function FrameMethods:HookScript() end
function FrameMethods:IsMouseOver() return self._mouseOver and true or false end
function FrameMethods:CreateTexture() local r = NewRegion("Texture", self) self._regions[#self._regions + 1] = r return r end
function FrameMethods:CreateFontString() local r = NewRegion("FontString", self) self._regions[#self._regions + 1] = r return r end

function FrameMethods:Show()
   if self._shown then return end
   self._shown = true
   local fn = self._scripts.OnShow
   if fn then fn(self) end
end
function FrameMethods:Hide()
   if not self._shown then return end
   self._shown = false
   local fn = self._scripts.OnHide
   if fn then fn(self) end
end
function FrameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMethods:IsShown() return self._shown end
function FrameMethods:IsVisible()
   if not self._shown then return false end
   local p = self._parent
   if p and p ~= self and p.IsVisible then return p:IsVisible() end
   return true
end

-- Lage auf dem Bildschirm: nur fuer Anker an UIParent (genug fuer Knopf und Liste)
local function Rect(self, world)
   local p = self._points[1]
   if not p or p[1] == "ALL" then return nil end
   local rel = p[2]
   if rel ~= world.UIParent and rel ~= nil then return nil end
   local relPoint = p[3] or p[1]
   local W, H = world.UIParent._w, world.UIParent._h
   local ax = ({ LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = W / 2, TOP = W / 2, BOTTOM = W / 2, RIGHT = W, TOPRIGHT = W, BOTTOMRIGHT = W })[relPoint]
   local ay = ({ BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = H / 2, LEFT = H / 2, RIGHT = H / 2, TOP = H, TOPLEFT = H, TOPRIGHT = H })[relPoint]
   if not ax or not ay then return nil end
   ax, ay = ax + (p[4] or 0), ay + (p[5] or 0)
   local w, h = self._w, self._h
   local left = ({ LEFT = ax, TOPLEFT = ax, BOTTOMLEFT = ax, CENTER = ax - w / 2, TOP = ax - w / 2, BOTTOM = ax - w / 2,
      RIGHT = ax - w, TOPRIGHT = ax - w, BOTTOMRIGHT = ax - w })[p[1]]
   local bottom = ({ BOTTOM = ay, BOTTOMLEFT = ay, BOTTOMRIGHT = ay, CENTER = ay - h / 2, LEFT = ay - h / 2, RIGHT = ay - h / 2,
      TOP = ay - h, TOPLEFT = ay - h, TOPRIGHT = ay - h })[p[1]]
   return left, bottom
end

function Mock.install(world)
   local MT = NewFrameClass(world)

   function FrameMethods.GetLeft(self) local l = Rect(self, world) return l end
   function FrameMethods.GetBottom(self) local _, b = Rect(self, world) return b end
   function FrameMethods.GetCenter(self)
      local l, b = Rect(self, world)
      if not l then return nil end
      return l + self._w / 2, b + self._h / 2
   end

   -- Zeichnet das Backdrop auf (nur mit der Vorlage "BackdropTemplate")
   function BackdropMethods:SetBackdrop(info)
      assert(type(info) == "table", "SetBackdrop needs a table")
      self._backdropInfo = info
   end
   function BackdropMethods:SetBackdropColor(r, g, b, a) self._bdColor = { r, g, b, a } end
   function BackdropMethods:SetBackdropBorderColor(r, g, b, a)
      assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetBackdropBorderColor needs r, g, b")
      self._bdBorder = { r, g, b, a }
   end

   function world.newFrame(ftype, name, parent, template)
      template = template or ""
      local f = setmetatable({
         _type = ftype, _name = name, _parent = parent, _template = template,
         _attrs = {}, _scripts = {}, _events = {}, _shown = true, _points = {}, _regions = {},
         _w = 0, _h = 0, _scale = 1, _alpha = 1, _level = 0, _strata = "MEDIUM",
         _secure = template:find("Secure") ~= nil,
         _backdrop = template:find("BackdropTemplate") ~= nil,
      }, MT)
      if parent and parent._level then f._level = parent._level + 1 end
      if name then
         assert(rawget(world.G, name) == nil or world.allowRedefine, "frame name already in use: " .. name)
         world.G[name] = f
      end
      world.frames[#world.frames + 1] = f
      return f
   end
   return MT
end

-- ---------------------------------------------------------------------------
-- Welt: Spielzustand und alle Funktionen der Sandbox
-- ---------------------------------------------------------------------------

function Mock.new(opts)
   opts = opts or {}
   local world = {
      combat = false, chat = {}, frames = {}, casts = {}, mouseDown = {}, time = 100,
      locale = opts.locale or "deDE", cvars = { ActionButtonUseKeyDown = "1" },
      professions = {}, known = {}, spellNames = {}, spellIcons = {}, windowSpells = {},
      openSkillLine = 0, spellbook = {}, toggled = 0,
      -- Lager: Taschen, Gegenstaende, Herstellen
      bags = {}, itemNames = {}, unusable = {}, cooldowns = {}, requested = {}, uses = {}, crafts = {}, openedRecipes = {},
      recipes = {}, craftMakes = {}, timers = {}, faction = opts.faction or "Alliance",
      player = opts.player or "Testerin", realm = opts.realm or "Everlook", tradeReady = true,
   }
   local G = {}
   world.G = G
   for _, name in ipairs(STD) do G[name] = _G[name] end
   G._G = G
   G.format = string.format
   G.tinsert, G.tremove, G.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
   G.strlower, G.strmatch = string.lower, string.match
   G.date = os.date

   Mock.install(world)

   -- Oberflaeche
   local UIParent = world.newFrame("Frame", "UIParent", nil, "")
   UIParent._w, UIParent._h = 1920, 1080
   world.UIParent = UIParent
   G.UIParent = UIParent
   G.UISpecialFrames = {}
   G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
   G.TRADE_SKILLS = "Berufe"
   G.SlashCmdList = {}
   G.CreateFrame = function(ftype, name, parent, template)
      assert(type(ftype) == "string", "CreateFrame: type must be a string")
      assert(template == nil or type(template) == "string", "CreateFrame: template must be a string")
      return world.newFrame(ftype, name, parent or UIParent, template)
   end
   G.hooksecurefunc = function() end
   -- Blizzards sichere Klick-Funktionen (die Attrappe bildet sie in world.click nach)
   G.SecureActionButton_OnClick = noop
   G.SecureActionButton_ShouldUseOnKeyDown = noop

   -- Tooltip, Meldungen, Chat
   local tip = world.newFrame("GameTooltip", "GameTooltip", UIParent, "")
   tip.lines = {}
   function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} self._shown = true end
   function tip:AddLine(text) self.lines[#self.lines + 1] = text end
   function tip:GetOwner() return self.owner end
   function tip:Hide() self._shown = false self.owner = nil end
   tip._shown = false
   G.GameTooltip = tip
   G.UIErrorsFrame = { AddMessage = function(_, msg) world.errorsShown = (world.errorsShown or 0) + 1 world.lastError = msg end }
   G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) world.chat[#world.chat + 1] = msg end }

   -- Zustand
   G.InCombatLockdown = function() return world.combat end
   G.GetTime = function() return world.time end
   G.GetLocale = function() return world.locale end
   G.GetBuildInfo = function() return "1.60.1", "70862", "Nov 7 2026", 16001 end
   G.WOW_PROJECT_ID = 18
   G.GetCVar = function(name) return world.cvars[name] end
   G.GetPhysicalScreenSize = function() return 2560, 1440 end
   G.IsMouseButtonDown = function(button) return world.mouseDown[button] and true or false end
   G.RegisterStateDriver = function(frame, state, cond)
      world.stateDrivers = world.stateDrivers or {}
      world.stateDrivers[#world.stateDrivers + 1] = { frame = frame, state = state, cond = cond }
   end
   G.Enum = {
      SpellBookSpellBank = { Player = 0, Pet = 1 },
      SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
   }
   G.BackdropTemplateMixin = {}
   G.PixelUtil = {}
   G.C_AddOns = { GetAddOnMetadata = function() return "1.1-forever" end }
   G.ToggleProfessionsBook = function() world.toggled = world.toggled + 1 end

   -- Berufe: world.professions = { { name, icon, rank, max, skillLine, pos, spells = { { id, name, icon, passive, window } } } }
   -- Die Zauber landen im Zauberbuch ab einem Versatz je Beruf, wie im Spiel.
   function world.setProfessions(list)
      world.professions = list
      world.spellbook = {}
      world.windowSpells = {}
      for i, prof in ipairs(list) do
         prof.index = i
         prof.offset = 100 * i
         prof.pos = prof.pos or i
         for n, spell in ipairs(prof.spells or {}) do
            world.spellbook[prof.offset + n] = {
               spellID = spell.id, actionID = spell.id, itemType = spell.itemType or 1, name = spell.name,
               subName = "", iconID = spell.icon or 1, isPassive = spell.passive and true or false, isOffSpec = false,
            }
            world.spellNames[spell.id] = spell.name
            world.spellIcons[spell.id] = spell.icon or 1
            if spell.window then world.windowSpells[spell.id] = true end
         end
      end
   end
   G.GetProfessions = function()
      local slot = {}
      for _, prof in ipairs(world.professions) do slot[prof.pos] = prof.index end
      return slot[1], slot[2], slot[3], slot[4], slot[5]
   end
   G.GetProfessionInfo = function(index)
      local prof = world.professions[index]
      if not prof then error("GetProfessionInfo: bad index " .. tostring(index), 2) end
      return prof.name, prof.icon or 1, prof.rank or 1, prof.max or 75, #(prof.spells or {}), prof.offset,
         prof.skillLine, 0, 0, 0, prof.name
   end
   G.C_SpellBook = {
      GetSpellBookItemInfo = function(slot, bank)
         assert(bank == 0 or bank == 1, "bank must be an Enum.SpellBookSpellBank value")
         return world.spellbook[slot]
      end,
      IsSpellKnown = function(id) return world.known[id] and true or false end,
      CastSpellBookItem = function() error("ADDON_ACTION_FORBIDDEN: CastSpellBookItem from insecure code", 2) end,
   }
   G.C_Spell = {
      GetSpellName = function(id) return world.spellNames[id] end,
      GetSpellTexture = function(id) return world.spellIcons[id] end,
   }
   G.C_TradeSkillUI = {
      CanTradeSkillShowCraftingUI = function(id) return world.windowSpells[id] and true or false end,
      GetBaseProfessionInfo = function() return { professionID = world.openSkillLine } end,
      CloseTradeSkill = function() world.openSkillLine = 0 end,
      OpenTradeSkill = function() error("ADDON_ACTION_FORBIDDEN: OpenTradeSkill from insecure code", 2) end,
      IsTradeSkillReady = function() return world.tradeReady end,
      GetRecipeInfo = function(id) return world.recipes[id] end,
      OpenRecipe = function(id) world.openedRecipes[#world.openedRecipes + 1] = id end,
      -- Herstellen wirkt nur, wenn ein Berufsfenster offen und bereit ist; world.craftNeedsClick: nur aus einem
      -- Klick heraus (so, als verlange der Client einen Tastendruck). world.craftMakes[Rezept] = { item, uses = { {id, n} } }
      CraftRecipe = function(id, count)
         assert(type(id) == "number" and type(count) == "number", "CraftRecipe(recipeID, count)")
         world.crafts[#world.crafts + 1] = id
         if world.openSkillLine == 0 or not world.tradeReady then return end
         if world.craftNeedsClick and not world.inClick then return end
         local made = world.craftMakes[id]
         if not made then return end
         for _, use in ipairs(made.uses or {}) do world.take(use[1], use[2]) end
         world.give(made.item, 1)
         world.fire("BAG_UPDATE_DELAYED")
      end,
   }

   -- Taschen: world.bags = { { id, count }, ... } (alles im Rucksack, Tasche 0)
   function world.give(id, count)
      for _, stack in ipairs(world.bags) do
         if stack.id == id then stack.count = stack.count + (count or 1) return end
      end
      world.bags[#world.bags + 1] = { id = id, count = count or 1 }
   end
   function world.take(id, count)
      for i, stack in ipairs(world.bags) do
         if stack.id == id then
            stack.count = stack.count - (count or stack.count)
            if stack.count <= 0 then table.remove(world.bags, i) end
            return
         end
      end
   end
   G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
   G.C_Container = {
      GetContainerNumSlots = function(bag)
         assert(type(bag) == "number", "bag index")
         return bag == 0 and 16 or 0
      end,
      GetContainerItemInfo = function(bag, slot)
         local stack = bag == 0 and world.bags[slot]
         if not stack then return nil end
         return { itemID = stack.id, stackCount = stack.count, iconFileID = 1 }
      end,
      GetItemCooldown = function(id)
         local cd = world.cooldowns[id]
         if cd then return cd.start, cd.duration, 1 end
         return 0, 0, 1
      end,
   }
   G.C_Item = {
      GetItemNameByID = function(id) return world.itemNames[id] end,       -- nil: noch nicht geladen
      GetItemIconByID = function(id) return 500000 + id end,
      IsUsableItem = function(id) return not world.unusable[id], false end,
      RequestLoadItemDataByID = function(id) world.requested[id] = true end,
   }
   G.UnitName = function(unit)
      assert(unit == "player", "UnitName(unit)")
      return world.player
   end
   G.GetRealmName = function() return world.realm end
   G.UnitFactionGroup = function(unit)
      assert(unit == "player", "UnitFactionGroup(unit)")
      return world.faction, world.faction
   end
   G.UnitCastingInfo = function() return world.casting end
   G.C_Timer = {
      After = function(seconds, fn)
         assert(type(seconds) == "number" and type(fn) == "function", "C_Timer.After(seconds, fn)")
         world.timers[#world.timers + 1] = { at = world.time + seconds, fn = fn }
      end,
   }
   -- Zeit vergeht: faellige Zeitgeber laufen
   function world.advance(seconds)
      world.time = world.time + seconds
      local due, rest = {}, {}
      for _, timer in ipairs(world.timers) do
         if timer.at <= world.time then due[#due + 1] = timer else rest[#rest + 1] = timer end
      end
      world.timers = rest
      for _, timer in ipairs(due) do timer.fn() end
   end

   -- Einstellungen (Settings.*)
   if not opts.noSettings then
      local S = { VarType = { Boolean = "boolean", String = "string", Number = "number" }, created = {}, categories = {} }
      function S.RegisterVerticalLayoutCategory(name)
         local cat = { name = name }
         function cat:GetID() return 42 end
         S.categories[#S.categories + 1] = cat
         return cat
      end
      function S.RegisterAddOnSetting(cat, variable, key, tbl, vtype, name, default)
         assert(type(tbl) == "table", "variable table missing")
         assert(S.VarType[vtype == "boolean" and "Boolean" or vtype == "string" and "String" or "Number"] == vtype, "bad var type")
         if tbl[key] == nil then tbl[key] = default end
         local setting = { variable = variable, key = key, tbl = tbl, name = name }
         function setting:SetValueChangedCallback(fn) self.callback = fn end
         function setting:SetValue(v) self.tbl[self.key] = v if self.callback then self.callback(self, v) end end
         return setting
      end
      function S.RegisterAddOnCategory(cat) S.registered = cat end
      function S.CreateCheckbox(cat, setting) S.created[#S.created + 1] = { "checkbox", setting } end
      function S.CreateDropdown(cat, setting, options)
         local data = options()
         assert(type(data) == "table" and #data > 0, "dropdown without options")
         S.created[#S.created + 1] = { "dropdown", setting, data }
      end
      function S.CreateControlTextContainer()
         local c = { data = {} }
         function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label, text = label } end
         function c:GetData() return self.data end
         return c
      end
      function S.CreateSliderOptions(lo, hi, step) return { lo = lo, hi = hi, step = step, SetLabelFormatter = noop } end
      function S.CreateSlider(cat, setting, options) S.created[#S.created + 1] = { "slider", setting, options } end
      function S.OpenToCategory(id) S.opened = id end
      G.Settings = S
   end

   -- Hilfen fuer Tests
   function world.fire(event, ...)
      for _, f in ipairs(world.frames) do
         if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
      end
   end

   -- Ein Klick wie im Spiel: Niederdruecken und Loslassen, soweit der Knopf dafuer angemeldet ist;
   -- sichere Knoepfe fuehren ihre Aktion nach den Regeln von SecureActionButton_OnClick aus.
   function world.click(frame, button)
      button = button or "LeftButton"
      local prefix = button == "LeftButton" and "1" or button == "RightButton" and "2" or "3"
      local function dispatch(down)
         local registered = frame._clicks and (frame._clicks[button .. (down and "Down" or "Up")]
            or frame._clicks["AnyDown"] and down or frame._clicks["AnyUp"] and not down)
         if not registered then return end
         if frame._scripts.PreClick then frame._scripts.PreClick(frame, button, down) end
         if frame._template:find("SecureActionButtonTemplate") then
            local useDown = frame._attrs.useOnKeyDown
            if useDown == nil then useDown = world.cvars.ActionButtonUseKeyDown == "1" end
            local fires = (down and useDown) or (not down and not useDown)
            if fires then
               local a = frame._attrs
               local kind = a["type" .. prefix] or a["*type" .. prefix] or a.type
               if kind == "spell" then
                  local spell = a["spell" .. prefix] or a["*spell" .. prefix] or a.spell
                  world.casts[#world.casts + 1] = tonumber(spell) or spell
               elseif kind == "item" then
                  world.uses[#world.uses + 1] = a["item" .. prefix] or a["*item" .. prefix] or a.item
               end
            end
         end
         if frame._scripts.PostClick then frame._scripts.PostClick(frame, button, down) end
         if frame._scripts.OnClick and not frame._template:find("SecureActionButtonTemplate") and not down then
            frame._scripts.OnClick(frame, button, down)
         end
      end
      world.inClick = true
      dispatch(true)
      dispatch(false)
      world.inClick = false
   end

   -- Die Dateien eines Addons in der Sandbox laden: world.load("Core.lua") ...
   world.ns = {}
   function world.load(path)
      local chunk, err = loadfile(path)
      if not chunk then error(err, 0) end
      setfenv(chunk, G)
      return chunk("ProfessionMenu", world.ns)
   end

   return world
end

return Mock
