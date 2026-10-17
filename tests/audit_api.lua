-- tests/audit_api.lua
-- ---------------------------------------------------------------------------
-- Statische Pruefung der Schnittstellen des Addons ProfessionMenu gegen das, was WoW 3.3.5a bietet.
--
--    luajit tests/audit_api.lua [-v] [--root DIR]            (im Hauptverzeichnis des Addons)
--
-- Liest die Lua-Dateien der TOC und prueft (Kommentare und Zeichenketten sind ausgeblendet, wo es um Code geht):
--
--   1. Modulzugriffe    PM.Name / UI.Name / Skin.Name (auch ueber lokale Aliase wie  local Skin = PM.Skin  und
--                       local Skin, L = PM.Skin, PM.L): jeder Name muss irgendwo definiert sein, und Aufrufe mit MEHR
--                       Argumenten als die Definition Parameter hat sind Fehler (die Zusatzargumente verpuffen).
--   2. Rahmenmethoden   jeder Methodenaufruf  obj:Name(...)  muss eine 3.3.5a-Methode eines Rahmens, einer Textur,
--                       eines FontStrings (Modell der Attrappe tests/mock_wow.lua), eine Zeichenkettenmethode, eine
--                       Methode der ElvUI-Erweiterungen oder eine vom Addon selbst definierte Methode sein.
--   3. Ereignisse       jedes registrierte Ereignis steht in tests/wow_events.txt (echte 3.3.5a-Ereignisse).
--   4. CreateFrame      Rahmentyp und Vorlage (Literale) sind in 3.3.5a erzeugbar bzw. bekannt.
--   5. Aufzaehlungen    Ankerpunkte, Strata, Zeichenebenen, Ausrichtungen, Klickarten (Literale) sind gueltig.
--   6. Dateien          "Interface\AddOns\ProfessionMenu\..." zeigt auf eine vorhandene Datei (.tga/.blp ergaenzt).
--   7. Slash-Befehle    SLASH_<NAME>n und SlashCmdList["<NAME>"] gehoeren zusammen.
--
-- Exit-Code 0 = keine Fehler, 1 = mindestens ein Fehler, 2 = Aufrufproblem.
-- ---------------------------------------------------------------------------

local scriptPath = (arg and arg[0]) or "tests/audit_api.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."
local SCRIPT_DIR = scriptPath:match("^(.*)[/\\][^/\\]*$") or "."      -- Mock und Ereignisliste liegen neben diesem Skript

local verbose = false
local args = arg or {}
local ai = 1
while ai <= #args do
   local a = args[ai]
   if a == "-v" or a == "--verbose" then
      verbose = true
   elseif a == "--root" then
      ai = ai + 1
      ROOT = args[ai] or ROOT
   end
   ai = ai + 1
end

local function readFile(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

-- ---------------------------------------------------------------------------
-- Dateien der TOC
-- ---------------------------------------------------------------------------

local toc = readFile(ROOT .. "/ProfessionMenu.toc")
if not toc then
   io.write("audit_api: ProfessionMenu.toc nicht gefunden (" .. ROOT .. ")\n")
   os.exit(2)
end

local files = {}
for line in (toc .. "\n"):gmatch("(.-)\r?\n") do
   line = line:match("^%s*(.-)%s*$")
   if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():match("%.lua$") then
      files[#files + 1] = (line:gsub("\\", "/"))
   end
end

-- Entfernt Kommentare (und, mit blank, den Inhalt von Zeichenketten); Zeilenumbrueche bleiben erhalten.
local function strip(src, blankStrings)
   local out, n, i = {}, #src, 1
   while i <= n do
      local c = src:sub(i, i)
      if c == "-" and src:sub(i + 1, i + 1) == "-" then
         local eq = src:match("^%[(=*)%[", i + 2)
         if eq then
            local close = "]" .. eq .. "]"
            local _, e = src:find(close, i + 4 + #eq, true)
            e = e or n
            out[#out + 1] = (src:sub(i, e):gsub("[^\n]", ""))
            i = e + 1
         else
            local e = src:find("\n", i, true)
            i = e or (n + 1)
         end
      elseif c == '"' or c == "'" then
         local j = i + 1
         local nl = 0
         while j <= n do
            local d = src:sub(j, j)
            if d == "\\" then
               if src:sub(j + 1, j + 1) == "\n" then nl = nl + 1 end
               j = j + 2
            elseif d == c or d == "\n" then
               break
            else
               j = j + 1
            end
         end
         if blankStrings then
            out[#out + 1] = c .. c .. string.rep("\n", nl)
         else
            out[#out + 1] = src:sub(i, j)
         end
         i = j + 1
      elseif c == "[" and src:match("^%[=*%[", i) then
         local eq = src:match("^%[(=*)%[", i)
         local close = "]" .. eq .. "]"
         local _, e = src:find(close, i + #eq + 2, true)
         e = e or n
         if blankStrings then
            out[#out + 1] = '""' .. (src:sub(i, e):gsub("[^\n]", ""))
         else
            out[#out + 1] = src:sub(i, e)
         end
         i = e + 1
      else
         out[#out + 1] = c
         i = i + 1
      end
   end
   return table.concat(out)
end

local function lineMapper(text)
   local starts = { 1 }
   for p in text:gmatch("()\n") do starts[#starts + 1] = p + 1 end
   return function(pos)
      local lo, hi = 1, #starts
      while lo < hi do
         local mid = math.ceil((lo + hi) / 2)
         if starts[mid] <= pos then lo = mid else hi = mid - 1 end
      end
      return lo
   end
end

local sources = {}
for _, rel in ipairs(files) do
   local text = readFile(ROOT .. "/" .. rel)
   if text then
      sources[#sources + 1] = {
         file = rel, raw = text, code = strip(text, true), kept = strip(text, false),
         line = lineMapper(text), alias = {},
      }
   end
end

local errors, warnings = {}, {}
local function err(file, line, msg) errors[#errors + 1] = string.format("%s:%d: %s", file, line, msg) end

-- ---------------------------------------------------------------------------
-- 1. Modulzugriffe und Argumentzahl
-- ---------------------------------------------------------------------------

local defs = {}       -- [pfad] = { params, vararg, method, file, line }
local isParent = {}   -- [pfad] = true, wenn Eintraege darunter definiert sind

local function split(path)
   local out = {}
   for seg in path:gmatch("[^%.]+") do out[#out + 1] = seg end
   return out
end

local function join(a, b)
   if a == "" then return b end
   if b == "" then return a end
   return a .. "." .. b
end

local function paramInfo(list)
   list = list or ""
   local n, vararg = 0, false
   for item in list:gmatch("[^,]+") do
      local p = item:match("^%s*(.-)%s*$")
      if p == "..." then vararg = true elseif p ~= "" then n = n + 1 end
   end
   return n, vararg
end

local function addDef(path, info)
   if path == "" then return end
   local cur = defs[path]
   if not cur then
      defs[path] = info
   elseif info.params and cur.params and info.params > cur.params then
      cur.params = info.params
   end
   local segs = split(path)
   local acc = ""
   for i = 1, #segs - 1 do
      acc = join(acc, segs[i])
      isParent[acc] = true
   end
end

-- Der Namensraum ist das zweite Argument jeder Datei:  local ADDON, PM = ...
local function resolveRoot(src, name)
   if name == "PM" then return "" end
   return src.alias[name]
end

for _, src in ipairs(sources) do
   for pass = 1, 3 do
      for rawLine in (src.code .. "\n"):gmatch("(.-)\n") do
         -- local A, B = PM.X, PM.Y   /   local A = PM.X.Y   (nur Pfade, sonst nichts)
         local names, rhs = rawLine:match("^%s*local%s+([%a_][%w_,%s]*)=%s*(.-)%s*$")
         if names and rhs and not rhs:find("[%(%){}\"']") then
            local nameList, rhsList = {}, {}
            for n in names:gmatch("[%a_][%w_]*") do nameList[#nameList + 1] = n end
            for r in (rhs .. ","):gmatch("%s*([^,]-)%s*,") do rhsList[#rhsList + 1] = r end
            for k, n in ipairs(nameList) do
               local r = rhsList[k]
               if r and r:match("^[%a_][%w_%.]*$") then
                  local segs = split(r)
                  local base = resolveRoot(src, segs[1])
                  if base ~= nil and #segs >= 2 then
                     src.alias[n] = join(base, table.concat(segs, ".", 2))
                  end
               end
            end
         end
         -- PM.A = X  mit  local X = {}
         local lhs, name2 = rawLine:match("^%s*([%a_][%w_%.]*)%s*=%s*([%a_][%w_]*)%s*$")
         if lhs and name2 and not src.alias[name2] then
            local segs = split(lhs)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 and src.code:find("local%s+" .. name2 .. "%s*=%s*{") then
               src.alias[name2] = join(base, table.concat(segs, ".", 2))
            end
         end
      end
   end
end

for _, src in ipairs(sources) do
   local ln = 0
   for rawLine in (src.code .. "\n"):gmatch("(.-)\n") do
      ln = ln + 1
      local fbase, frest, plist = rawLine:match("^%s*function%s+([%a_][%w_]*)([%.:][%w_%.:]+)%s*%(([^)]*)%)")
      if fbase then
         local base = resolveRoot(src, fbase)
         if base ~= nil then
            local method = frest:find(":", 1, true) ~= nil
            local rest = frest:gsub("^[%.:]", ""):gsub(":", ".")
            local n, vararg = paramInfo(plist)
            addDef(join(base, rest), { params = n, vararg = vararg, method = method, file = src.file, line = ln })
         end
      elseif rawLine:match("^%s*[%a_][%w_%.]*%s*,%s*[%a_][%w_%.,%s]*=[^=]") then
         -- Mehrfachzuweisung  UI.rows, UI.headers = rows, headers
         local list = rawLine:match("^%s*([%a_][%w_%.,%s]*)=[^=]")
         for dotted in list:gmatch("[%a_][%w_%.]*") do
            local segs = split(dotted)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 then
               addDef(join(base, table.concat(segs, ".", 2)), { file = src.file, line = ln })
            end
         end
      else
         local lhs, rhs = rawLine:match("^%s*([%a_][%w_%.]*)%s*=%s*([^=].*)$")
         if lhs and not lhs:find("%.$") then
            local segs = split(lhs)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 then
               local rest = table.concat(segs, ".", 2)
               local plist2 = rhs:match("^%s*function%s*%(([^)]*)%)")
               local info = { file = src.file, line = ln }
               if plist2 then info.params, info.vararg = paramInfo(plist2) end
               if rhs:match("^%s*{%s*}%s*$") or rhs:match("or%s*{%s*}%s*$") then info.module = true end
               local ident = rhs:match("^%s*([%a_][%w_]*)%s*$")
               if ident and src.code:find("local%s+" .. ident .. "%s*=%s*{%s*}") then info.module = true end
               addDef(join(base, rest), info)
            end
         end
      end
   end
end

-- Felder, die bewusst zur Laufzeit entstehen oder von aussen kommen
local DYNAMIC = {
   ["L.__index"] = true,
}
-- Nur diese Tabellen sind Module, deren Felder vollstaendig im Code stehen; PM.L, PM.texts, PM.PROFESSIONS ... sind
-- Datentabellen (Zugriff auf deren Unterfelder wird nicht geprueft, das tun die Tests).
local MODULES = { [""] = true, UI = true, Skin = true }
local function isModule(path)
   return MODULES[path] == true
end

local function firstUndefined(segs)
   local cur = ""
   for i = 1, #segs do
      local nxt = join(cur, segs[i])
      if defs[nxt] or isParent[nxt] or DYNAMIC[nxt] then
         cur = nxt
      else
         if isModule(cur) then return nxt end
         return nil
      end
   end
   return nil
end

local OPEN_WORDS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSE_WORDS = { ["end"] = true, ["until"] = true }

local function countArgs(code, pos)
   local depth, block = 1, 0
   local commas, any = 0, false
   local i, n = pos + 1, #code
   while i <= n do
      local c = code:sub(i, i)
      if c == "(" or c == "{" or c == "[" then
         depth = depth + 1
         any = true
         i = i + 1
      elseif c == ")" or c == "}" or c == "]" then
         depth = depth - 1
         if depth == 0 then return any and (commas + 1) or 0 end
         i = i + 1
      elseif c == "," then
         if depth == 1 and block == 0 then commas = commas + 1 end
         any = true
         i = i + 1
      elseif c:match("[%a_]") then
         local word = code:match("^[%w_]+", i)
         if OPEN_WORDS[word] then block = block + 1 end
         if CLOSE_WORDS[word] then block = block - 1 end
         any = true
         i = i + #word
      else
         if not c:match("%s") then any = true end
         i = i + 1
      end
   end
   return nil
end

for _, src in ipairs(sources) do
   local code = src.code
   local pos = 1
   while true do
      local s, e = code:find("[%a_][%w_]*", pos)
      if not s then break end
      local prev = s > 1 and code:sub(s - 1, s - 1) or ""
      local segs = { code:sub(s, e) }
      local cur = e
      while true do
         local s2, e2 = code:find("^%.([%a_][%w_]*)", cur + 1)
         if not s2 then break end
         segs[#segs + 1] = code:sub(s2 + 1, e2)
         cur = e2
      end
      pos = cur + 1
      if prev ~= "." and prev ~= ":" and #segs >= 2 then
         local base = resolveRoot(src, segs[1])
         if base ~= nil then
            local full = {}
            for _, seg in ipairs(split(base)) do full[#full + 1] = seg end
            for i = 2, #segs do full[#full + 1] = segs[i] end
            local path = table.concat(full, ".")
            local lineNo = src.line(s)
            local bad = firstUndefined(full)
            if bad then
               err(src.file, lineNo, "PM." .. bad .. " ist nirgends definiert")
            else
               local d = defs[path]
               if d and d.params and not d.vararg and not d.method then
                  local after = code:match("^%s*%(", cur + 1)
                  if after then
                     local open = code:find("(", cur + 1, true)
                     local argc = countArgs(code, open)
                     if argc and argc > d.params then
                        err(src.file, lineNo, string.format(
                           "PM.%s mit %d Argument(en) gerufen, Definition (%s:%d) hat %d Parameter",
                           path, argc, d.file, d.line, d.params))
                     end
                  end
               end
            end
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- Modell der Attrappe laden (Rahmenmethoden, erzeugbare Typen, Vorlagen)
-- ---------------------------------------------------------------------------

local okMock, mock = pcall(dofile, SCRIPT_DIR .. "/mock_wow.lua")
if not okMock or type(mock) ~= "table" or not mock.methods then
   io.write("audit_api: tests/mock_wow.lua konnte nicht geladen werden: " .. tostring(mock) .. "\n")
   os.exit(2)
end

local widgetMethods = {}
for _, tbl in pairs(mock.methods) do
   for name in pairs(tbl) do widgetMethods[name] = true end
end

-- Methoden von Zeichenketten, die in 3.3.5a (Lua 5.1) vorhanden sind
local STRING_METHODS = {}
for name in ("byte find format gmatch gsub len lower match rep reverse sub upper"):gmatch("%S+") do
   STRING_METHODS[name] = true
end

-- Methoden, die das Addon auf ElvUI-Objekten (E, Rahmen mit ElvUI-API, LibElvUIPlugin) aufrufen darf
local ELVUI_METHODS = {}
for name in ([[CreateMover ResetMovers ToggleMoveMode ToggleMovers RegisterPlugin SetTemplate FontTemplate Size Point
   Width Height SetOutside SetInside CreateBackdrop Kill StripTextures StyleButton]]):gmatch("%S+") do
   ELVUI_METHODS[name] = true
end

local ownMethods = {}
for _, src in ipairs(sources) do
   for name in src.code:gmatch("function%s+[%a_][%w_%.]*:([%a_][%w_]*)") do ownMethods[name] = true end
end

-- ---------------------------------------------------------------------------
-- 2. Rahmenmethoden
-- ---------------------------------------------------------------------------

local methodUses = 0
for _, src in ipairs(sources) do
   local code = src.code
   for pos, name in code:gmatch("()[%w_%)%]]:([%a_][%w_]*)%s*[%(\"'{]") do
      methodUses = methodUses + 1
      if not (widgetMethods[name] or STRING_METHODS[name] or ELVUI_METHODS[name] or ownMethods[name]) then
         err(src.file, src.line(pos), "Methode :" .. name .. "() gibt es in 3.3.5a weder fuer Rahmen/Texturen/FontStrings "
            .. "noch fuer Zeichenketten (oder sie fehlt in der ElvUI-Liste von audit_api.lua)")
      end
   end
end

-- ---------------------------------------------------------------------------
-- 3. Ereignisse
-- ---------------------------------------------------------------------------

local validEvents = {}
do
   local text = readFile(SCRIPT_DIR .. "/wow_events.txt") or ""
   for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      line = line:gsub("#.*$", "")
      for name in line:gmatch("[%w_]+") do validEvents[name] = true end
   end
end

local registered = {}
for _, src in ipairs(sources) do
   local kept = src.kept
   -- RegisterEvent("NAME")
   for pos, name in kept:gmatch('()RegisterEvent%(%s*"([%w_]+)"') do
      registered[name] = true
      if not validEvents[name] then err(src.file, src.line(pos), "Ereignis " .. name .. " gibt es in 3.3.5a nicht (tests/wow_events.txt)") end
   end
   -- Liste  local EVENTS = { "A", "B" }  gefolgt von RegisterEvent(event)
   for body in kept:gmatch("local%s+EVENTS%s*=%s*(%b{})") do
      for name in body:gmatch('"([%w_]+)"') do
         registered[name] = true
         if not validEvents[name] then err(src.file, 1, "Ereignis " .. name .. " (EVENTS) gibt es in 3.3.5a nicht (tests/wow_events.txt)") end
      end
   end
   -- Vergleiche event == "NAME"
   for pos, name in kept:gmatch('()event%s*==%s*"([%w_]+)"') do
      if not validEvents[name] then err(src.file, src.line(pos), "Ereignis " .. name .. " (Vergleich) gibt es in 3.3.5a nicht") end
   end
end

-- ---------------------------------------------------------------------------
-- 4. CreateFrame
-- ---------------------------------------------------------------------------

for _, src in ipairs(sources) do
   local kept = src.kept
   for pos, typ in kept:gmatch('()CreateFrame%(%s*"([%w_]+)"') do
      if not mock.CREATABLE[typ] then err(src.file, src.line(pos), "CreateFrame: Rahmentyp " .. typ .. " gibt es nicht") end
   end
   for pos, tpl in kept:gmatch('()CreateFrame%([^%)]-,%s*"([%w_]+)"%s*%)') do
      if not mock.TEMPLATES[tpl] then err(src.file, src.line(pos), "CreateFrame: Vorlage " .. tpl .. " ist der Attrappe unbekannt (3.3.5a?)") end
   end
end

-- ---------------------------------------------------------------------------
-- 5. Aufzaehlungen
-- ---------------------------------------------------------------------------

local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local STRATA = { WORLD = 1, BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, FULLSCREEN_DIALOG = 1, TOOLTIP = 1 }
local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }
local JUSTIFY_H = { LEFT = 1, CENTER = 1, RIGHT = 1 }
local JUSTIFY_V = { TOP = 1, MIDDLE = 1, BOTTOM = 1 }
local CLICKS = { LeftButtonUp = 1, LeftButtonDown = 1, RightButtonUp = 1, RightButtonDown = 1, MiddleButtonUp = 1,
                 MiddleButtonDown = 1, Button4Up = 1, Button4Down = 1, Button5Up = 1, Button5Down = 1, AnyUp = 1, AnyDown = 1 }
local DRAG = { LeftButton = 1, RightButton = 1, MiddleButton = 1, Button4 = 1, Button5 = 1 }
local TOOLTIP_ANCHORS = { ANCHOR_NONE = 1, ANCHOR_RIGHT = 1, ANCHOR_LEFT = 1, ANCHOR_TOP = 1, ANCHOR_BOTTOM = 1,
                          ANCHOR_TOPRIGHT = 1, ANCHOR_TOPLEFT = 1, ANCHOR_BOTTOMRIGHT = 1, ANCHOR_BOTTOMLEFT = 1,
                          ANCHOR_CURSOR = 1, ANCHOR_PRESERVE = 1 }
local FONT_FLAGS = { OUTLINE = 1, THICKOUTLINE = 1, MONOCHROME = 1 }

for _, src in ipairs(sources) do
   local kept = src.kept
   for pos, v in kept:gmatch('()SetPoint%(%s*"([%w_]+)"') do
      if not POINTS[v] then err(src.file, src.line(pos), "SetPoint: Ankerpunkt " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()SetPoint%([^"%)]-,[^"%)]-,%s*"([%w_]+)"') do
      if not POINTS[v] then err(src.file, src.line(pos), "SetPoint: Bezugspunkt " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()SetFrameStrata%(%s*"([%w_]+)"') do
      if not STRATA[v] then err(src.file, src.line(pos), "SetFrameStrata: " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()Create[TF][eo][xn][tt][%a]*%(%s*[^,%)]*,%s*"([%w_]+)"') do
      if not LAYERS[v] then err(src.file, src.line(pos), "Zeichenebene " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()SetJustifyH%(%s*"([%w_]+)"') do
      if not JUSTIFY_H[v] then err(src.file, src.line(pos), "SetJustifyH: " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()SetJustifyV%(%s*"([%w_]+)"') do
      if not JUSTIFY_V[v] then err(src.file, src.line(pos), "SetJustifyV: " .. v .. " ist ungueltig") end
   end
   for pos, list in kept:gmatch("()RegisterForClicks(%b())") do
      for v in list:gmatch('"([%w_]+)"') do
         if not CLICKS[v] then err(src.file, src.line(pos), "RegisterForClicks: " .. v .. " ist ungueltig") end
      end
   end
   for pos, list in kept:gmatch("()RegisterForDrag(%b())") do
      for v in list:gmatch('"([%w_]+)"') do
         if not DRAG[v] then err(src.file, src.line(pos), "RegisterForDrag: " .. v .. " ist ungueltig") end
      end
   end
   for pos, v in kept:gmatch('()SetOwner%([^"%)]-,%s*"([%w_]+)"') do
      if not TOOLTIP_ANCHORS[v] then err(src.file, src.line(pos), "SetOwner: Anker " .. v .. " ist ungueltig") end
   end
   for pos, v in kept:gmatch('()tooltipAnchor%s*=%s*[^"\n]-"(ANCHOR_[%w_]+)"') do
      if not TOOLTIP_ANCHORS[v] then err(src.file, src.line(pos), "tooltipAnchor " .. v .. " ist ungueltig") end
   end
   for pos, flags in kept:gmatch('()SetFont%([^%)]-,[^%)]-,%s*"([%w_,]+)"') do
      for f in flags:gmatch("[^,]+") do
         if not FONT_FLAGS[f] then err(src.file, src.line(pos), "SetFont: Schriftmerkmal " .. f .. " ist ungueltig") end
      end
   end
end

-- ---------------------------------------------------------------------------
-- 6. Dateien des Addons
-- ---------------------------------------------------------------------------

local function exists(rel)
   local base = ROOT .. "/" .. rel:gsub("\\", "/")
   for _, candidate in ipairs({ base, base .. ".tga", base .. ".blp", base .. ".TGA", base .. ".BLP" }) do
      local f = io.open(candidate, "rb")
      if f then f:close() return true end
   end
   return false
end

local assetCount = 0
for _, src in ipairs(sources) do
   for pos, rel in src.kept:gmatch('()"[Ii]nterface\\\\[Aa]dd[Oo]ns\\\\ProfessionMenu\\\\([^"]+)"') do
      assetCount = assetCount + 1
      if not exists(rel:gsub("\\\\", "/")) then err(src.file, src.line(pos), "Datei fehlt: " .. rel:gsub("\\\\", "\\")) end
   end
end

-- ---------------------------------------------------------------------------
-- 7. Slash-Befehle
-- ---------------------------------------------------------------------------

do
   local slashNames, listNames = {}, {}
   for _, src in ipairs(sources) do
      for name in src.kept:gmatch("SLASH_([%u%d_]-)%d+%s*=") do slashNames[name] = true end
      for name in src.kept:gmatch('SlashCmdList%["([%u%d_]+)"%]') do listNames[name] = true end
   end
   for name in pairs(slashNames) do
      if not listNames[name] then err("Main.lua", 1, "SLASH_" .. name .. "n ohne SlashCmdList[\"" .. name .. "\"]") end
   end
   for name in pairs(listNames) do
      if not slashNames[name] then err("Main.lua", 1, "SlashCmdList[\"" .. name .. "\"] ohne SLASH_" .. name .. "1") end
   end
end

-- ---------------------------------------------------------------------------
-- Ausgabe
-- ---------------------------------------------------------------------------

table.sort(errors)
local defCount = 0
for _ in pairs(defs) do defCount = defCount + 1 end
local eventCount = 0
for _ in pairs(registered) do eventCount = eventCount + 1 end
io.write(string.format(
   "audit_api: %d Dateien, %d Definitionen, %d Methodenaufrufe, %d Ereignisse, %d Dateiverweise, %d Fehler\n",
   #sources, defCount, methodUses, eventCount, assetCount, #errors))
for _, e in ipairs(errors) do io.write("  FEHLER  " .. e .. "\n") end
os.exit(#errors > 0 and 1 or 0)
