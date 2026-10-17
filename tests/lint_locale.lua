-- tests/lint_locale.lua
-- ---------------------------------------------------------------------------
-- Linter fuer die Texte des Addons ProfessionMenu (Locales.lua).
--
--    luajit tests/lint_locale.lua [-v] [--root DIR] [--strict-locales]
--
-- Prueft ohne Attrappe, nur am Quelltext:
--   * Jede Sprachtabelle  texts.<Sprache> = { Schluessel = "Text", ... }  ist lesbar; Schluessel sind
--     [A-Za-z][A-Za-z0-9_]* und nicht doppelt.
--   * Jeder Schluessel einer Sprache gibt es in enUS (kein verwaister Schluessel).
--   * Jeder im Code benutzte Schluessel  L.<name>, PM.L.<name>, L["name"]  steht in enUS (key-undefined).
--   * Jeder enUS-Schluessel wird im Code benutzt (key-unused, Warnung); L["cat_" .. x] und die Beschriftungen aus
--     Tabellen (sort*, dir*) zaehlen als benutzt.
--   * Platzhalter (%s %d %.2f) stimmen mit enUS ueberein (placeholder).
--   * deDE ist vollstaendig (locale-missing); mit --strict-locales muessen es alle Sprachen sein.
--   * Kodierung: gueltiges UTF-8, kein CR, kein Tab, kein Leerraum am Zeilenende.
--   * Warnung (pipe): ein einzelnes '|' im Text wird vom Client als Escape-Folge gelesen ("|r" setzt die Farbe zurueck).
--
-- Exit-Code: 0 = keine Fehler (Warnungen moeglich), 1 = Fehler, 2 = Aufrufproblem.
-- ---------------------------------------------------------------------------

local scriptPath = (arg and arg[0]) or "tests/lint_locale.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."
local verbose, strictLocales = false, false

do
   local i = 1
   while arg and arg[i] do
      local a = arg[i]
      if a == "-v" or a == "--verbose" then
         verbose = true
      elseif a == "--strict-locales" then
         strictLocales = true
      elseif a == "--root" then
         i = i + 1
         ROOT = arg[i] or ROOT
      end
      i = i + 1
   end
end

local function readFile(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local errors, warnings = {}, {}
local function err(msg) errors[#errors + 1] = msg end
local function warn(msg) warnings[#warnings + 1] = msg end

local src = readFile(ROOT .. "/Locales.lua")
if not src then
   io.write("lint_locale: Locales.lua nicht gefunden (" .. ROOT .. ")\n")
   os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Dateihygiene
-- ---------------------------------------------------------------------------

local function utf8Error(s)
   local i, n = 1, #s
   while i <= n do
      local c = s:byte(i)
      if c < 0x80 then
         i = i + 1
      else
         local need
         if c >= 0xC2 and c <= 0xDF then need = 1
         elseif c >= 0xE0 and c <= 0xEF then need = 2
         elseif c >= 0xF0 and c <= 0xF4 then need = 3
         else return i end
         for k = 1, need do
            local b = s:byte(i + k)
            if not b or b < 0x80 or b > 0xBF then return i end
         end
         i = i + need + 1
      end
   end
   return nil
end

do
   local bad = utf8Error(src)
   if bad then err("Locales.lua: ungueltiges UTF-8 bei Byte " .. bad) end
   if src:find("\r", 1, true) then err("Locales.lua: CR/CRLF-Zeilenende (nur LF)") end
   if src:find("\t", 1, true) then err("Locales.lua: Tabulator") end
   if src:sub(1, 3) == "\239\187\191" then err("Locales.lua: BOM") end
   local n = 0
   for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      n = n + 1
      if line:find("[ \t]+$") then err("Locales.lua:" .. n .. ": Leerraum am Zeilenende") end
   end
end

-- ---------------------------------------------------------------------------
-- Sprachtabellen lesen
-- ---------------------------------------------------------------------------

local function unescape(s)
   s = s:gsub("\\(%d%d?%d?)", function(d) return string.char(tonumber(d)) end)
   s = s:gsub("\\n", "\n"):gsub('\\"', '"'):gsub("\\\\", "\\")
   return s
end

local texts, order = {}, {}
do
   local alias = {}          -- texts.esMX = texts.esES
   for name, body in src:gmatch("texts%.([%a_][%w_]*)%s*=%s*(%b{})") do
      local t = {}
      local seen = {}
      -- Zeile fuer Zeile:  key = "text",
      local lineNo = 0
      for line in body:gmatch("[^\n]+") do
         lineNo = lineNo + 1
         local key, value = line:match('^%s*([%w_]+)%s*=%s*"(.*)",?%s*$')
         if key then
            if not key:match("^[%a][%w_]*$") then err(name .. "." .. key .. ": ungueltiger Schluesselname") end
            if seen[key] then err(name .. "." .. key .. ": doppelt") end
            seen[key] = true
            t[key] = unescape(value)
         elseif line:match("^%s*[%w_]+%s*=") then
            err(name .. ": Zeile nicht lesbar (Wert kein einfacher Text?): " .. line:gsub("^%s+", ""))
         end
      end
      texts[name] = t
      order[#order + 1] = name
   end
   for name, target in src:gmatch("texts%.([%a_][%w_]*)%s*=%s*texts%.([%a_][%w_]*)%s*\n") do
      alias[name] = target
   end
   for name, target in pairs(alias) do
      texts[name] = texts[target]
      order[#order + 1] = name
   end
end

if not texts.enUS then
   err("texts.enUS fehlt")
   io.write("lint_locale: 1 Fehler\n  FEHLER  texts.enUS fehlt\n")
   os.exit(1)
end

local function placeholders(text)
   local out = {}
   for spec in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*(%a)") do out[#out + 1] = spec end
   return table.concat(out, ",")
end

-- ---------------------------------------------------------------------------
-- Schluessel gegen enUS, Platzhalter, Vollstaendigkeit
-- ---------------------------------------------------------------------------

local ESSENTIAL = { "title", "cat_craft", "cat_refine", "cat_gather", "cat_secondary", "hint_open", "hint_track", "hint_use",
                    "hint_passive", "hint_skills", "skill", "none", "combat", "cat_abilities", "hint_target", "hint_moved" }

for _, locale in ipairs(order) do
   local t = texts[locale]
   if locale ~= "enUS" and t ~= texts.enUS then
      for key, text in pairs(t) do
         if texts.enUS[key] == nil then
            err(locale .. "." .. key .. ": Schluessel gibt es in enUS nicht [key-orphan]")
         elseif placeholders(text) ~= placeholders(texts.enUS[key]) then
            err(string.format("%s.%s: Platzhalter (%s) weichen von enUS (%s) ab [placeholder]", locale, key,
               placeholders(text), placeholders(texts.enUS[key])))
         end
      end
      for _, key in ipairs(ESSENTIAL) do
         if t[key] == nil then err(locale .. "." .. key .. " fehlt [locale-missing]") end
      end
      if locale == "deDE" then
         for key in pairs(texts.enUS) do
            if t[key] == nil then err("deDE." .. key .. " fehlt [locale-missing]") end
         end
      elseif strictLocales then
         for key in pairs(texts.enUS) do
            if t[key] == nil then err(locale .. "." .. key .. " fehlt [locale-absent]") end
         end
      end
   end
end

if not texts.deDE then err("texts.deDE fehlt [locale-missing]") end

for _, locale in ipairs(order) do
   for key, text in pairs(texts[locale]) do
      if text == "" then err(locale .. "." .. key .. ": leerer Text") end
      local stripped = text:gsub("||", "")
      if stripped:find("|", 1, true) then
         warn(locale .. "." .. key .. ": einzelnes '|' im Text: der Client liest es als Escape-Folge ('|r' = Farbe zuruecksetzen, "
            .. "'||' = ein senkrechter Strich) [pipe]")
      end
   end
end

-- ---------------------------------------------------------------------------
-- Schluessel im Code
-- ---------------------------------------------------------------------------

local CODE = { "Core.lua", "Skin.lua", "UI.lua", "Main.lua", "Options.lua", "Data.lua" }
local used, dynamicPrefix = {}, {}
for _, file in ipairs(CODE) do
   local code = readFile(ROOT .. "/" .. file)
   if code then
      code = code:gsub("%-%-[^\n]*", "")
      local ln = 0
      for line in (code .. "\n"):gmatch("([^\n]*)\n") do
         ln = ln + 1
         for key in line:gmatch("%f[%w_]PM%.L%.([%a_][%w_]*)") do used[key] = used[key] or (file .. ":" .. ln) end
         for key in line:gsub("PM%.L%.", ""):gmatch("%f[%w_]L%.([%a_][%w_]*)") do used[key] = used[key] or (file .. ":" .. ln) end
         for key in line:gmatch('%f[%w_]L%["([%w_]+)"%]') do used[key] = used[key] or (file .. ":" .. ln) end
         for prefix in line:gmatch('L%["([%w_]+)"%s*%.%.') do dynamicPrefix[prefix] = true end
      end
   end
end

local nUsed = 0
for key, where in pairs(used) do
   nUsed = nUsed + 1
   if texts.enUS[key] == nil then err(where .. ": L." .. key .. " ist in enUS nicht definiert [key-undefined]") end
end

-- Beschriftungen, die ueber Tabellen erreicht werden (Main.lua: SORT_LABELS, DIR_LABELS)
local viaTable = {}
do
   local main = readFile(ROOT .. "/Main.lua") or ""
   for _, tblName in ipairs({ "SORT_LABELS", "DIR_LABELS" }) do
      local body = main:match("local%s+" .. tblName .. "%s*=%s*(%b{})")
      if body then
         for value in body:gmatch('=%s*"([%w_]+)"') do viaTable[value] = true end
      end
   end
end

for key in pairs(texts.enUS) do
   local ok = used[key] or viaTable[key]
   if not ok then
      for prefix in pairs(dynamicPrefix) do
         if key:sub(1, #prefix) == prefix then ok = true end
      end
   end
   if not ok then warn("enUS." .. key .. " wird im Code nirgends benutzt [key-unused]") end
end

-- ---------------------------------------------------------------------------
-- Ausgabe
-- ---------------------------------------------------------------------------

table.sort(errors)
table.sort(warnings)
local nKeys = 0
for _ in pairs(texts.enUS) do nKeys = nKeys + 1 end
io.write(string.format("lint_locale: %d Sprachen, %d Schluessel (enUS), %d im Code benutzt, %d Fehler, %d Warnung(en)\n",
   #order, nKeys, nUsed, #errors, #warnings))
for _, e in ipairs(errors) do io.write("  FEHLER  " .. e .. "\n") end
for _, w in ipairs(warnings) do io.write("  Hinweis " .. w .. "\n") end
os.exit(#errors > 0 and 1 or 0)
