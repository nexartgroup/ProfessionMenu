-- tests/coverage.lua
-- ---------------------------------------------------------------------------
-- Zeilenabdeckung des Addon-Codes durch die Tests:
--
--    luajit tests/coverage.lua [Filter fuer run.lua]
--
-- Startet tests/run.lua mit einem Zeilen-Hook (nur die Dateien aus der TOC), zaehlt, welche Zeilen ausgefuehrt
-- wurden, und listet je Datei die nicht erreichten Zeilen. Als "ausfuehrbar" gilt eine Zeile, die ausser Kommentar,
-- Leerraum und reinen Schlusswoertern (end, else, }, ), until) etwas enthaelt -- eine Naeherung, kein Messgeraet.
-- ---------------------------------------------------------------------------

local realDebug, realIo, realOs = debug, io, os
local scriptPath = (arg and arg[0]) or "tests/coverage.lua"
local testsDir = scriptPath:match("^(.*)[/\\]coverage%.lua$") or "tests"
local root = testsDir:gsub("[/\\]tests$", "")
if root == testsDir then root = "." end

local files = {}
do
   local f = realIo.open(root .. "/ProfessionMenu.toc", "rb")
   for line in f:lines() do
      line = line:gsub("\r", "")
      if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
   end
   f:close()
end

local wanted = {}
for _, name in ipairs(files) do wanted["@" .. name] = name end

local hits = {}
for _, name in ipairs(files) do hits[name] = {} end

local getinfo = realDebug.getinfo
realDebug.sethook(function(_, line)
   local info = getinfo(2, "S")
   local name = wanted[info.source]
   if name then hits[name][line] = true end
end, "l")

local realExit = realOs.exit
local function report()
   realDebug.sethook()
   print("\n" .. string.rep("-", 70))
   print("Line coverage of the addon files (approximation)")
   local totalExec, totalHit = 0, 0
   for _, name in ipairs(files) do
      local f = realIo.open(root .. "/" .. name, "rb")
      local src = f:read("*a")
      f:close()
      local executable = {}
      local n = 0
      local inLong = false
      for line in (src .. "\n"):gmatch("([^\n]*)\n") do
         n = n + 1
         local code = line
         if inLong then
            if code:find("%]%]") then inLong = false end
            code = ""
         end
         code = code:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-.*$", "")
         if code:find("%[%[") and not code:find("%]%]") then inLong = true end
         code = code:gsub("\"[^\"]*\"", '""'):gsub("'[^']*'", "''")
         local stripped = code:gsub("%s+", "")
         if stripped ~= "" and stripped ~= "end" and stripped ~= "else" and stripped ~= "}" and stripped ~= ")"
            and stripped ~= "end)" and stripped ~= "until" and stripped ~= "}," and stripped ~= "end," and stripped ~= "end}"
            and stripped ~= "end)," and stripped ~= "})" and stripped ~= "do" and stripped ~= "then" and stripped ~= "{" then
            executable[n] = true
         end
      end
      local count, hit, missing = 0, 0, {}
      for line in pairs(executable) do
         count = count + 1
         if hits[name][line] then hit = hit + 1 else missing[#missing + 1] = line end
      end
      table.sort(missing)
      totalExec, totalHit = totalExec + count, totalHit + hit
      -- zusammenhaengende Bereiche
      local ranges = {}
      local i = 1
      while i <= #missing do
         local j = i
         while missing[j + 1] and missing[j + 1] <= missing[j] + 1 do j = j + 1 end
         ranges[#ranges + 1] = (missing[i] == missing[j]) and tostring(missing[i]) or (missing[i] .. "-" .. missing[j])
         i = j + 1
      end
      print(string.format("%-12s %4d/%-4d  %5.1f%%   not reached: %s", name, hit, count, count > 0 and hit * 100 / count or 100,
         #ranges > 0 and table.concat(ranges, ", ") or "-"))
   end
   print(string.format("%-12s %4d/%-4d  %5.1f%%", "TOTAL", totalHit, totalExec, totalExec > 0 and totalHit * 100 / totalExec or 100))
end

os.exit = function(code)
   report()
   realExit(code)
end

arg = { [0] = testsDir .. "/run.lua", "--known-bugs-ok", unpack(arg or {}) }
dofile(testsDir .. "/run.lua")
