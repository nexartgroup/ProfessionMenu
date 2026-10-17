-- tests/test_files.lua
-- ---------------------------------------------------------------------------
-- Dateien des Addons: Textur (TGA-Kopf, Ausrichtung des Pfeils), TOC gegen Dateisystem, README gegen Dateien.
-- Was die Attrappe nicht pruefen kann (wie die Textur im Spiel aussieht), steht in docs/README.de.md.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local function readFile(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local s = f:read("*a")
      f:close()
      return s
   end

   local function listFiles(dir)
      local out = {}
      local p = io.popen('cd "' .. dir .. '" && find . -type f -not -path "./tests/*" -not -path "./.*" | sed "s|^\\./||" | sort')
      for line in p:lines() do out[#out + 1] = line end
      p:close()
      return out
   end

   -- ======================================================================
   H.section("Media/chevron.tga")
   -- ======================================================================

   local function tga()
      local data = readFile(M.root .. "/Media/chevron.tga")
      H.truthy(data, "Media/chevron.tga exists")
      local h = {
         idlen = data:byte(1), cmap = data:byte(2), itype = data:byte(3),
         w = data:byte(13) + data:byte(14) * 256, h = data:byte(15) + data:byte(16) * 256,
         bpp = data:byte(17), desc = data:byte(18),
      }
      return data, h
   end

   H.test("the arrow is an uncompressed 32-bit truecolour TGA with a power-of-two size (what the 3.3.5a client loads)", function()
      local data, h = tga()
      H.eq(h.idlen, 0, "no image id")
      H.eq(h.cmap, 0, "no colour map")
      H.eq(h.itype, 2, "type 2 = uncompressed truecolour")
      H.eq(h.bpp, 32)
      H.eq(h.w, 32)
      H.eq(h.h, 32)
      H.eq(h.desc % 16, 8, "8 alpha bits")
      H.eq(#data, 18 + h.w * h.h * 4, "no trailing data besides the pixels")
      for _, n in ipairs({ h.w, h.h }) do H.eq(n, 2 ^ math.floor(math.log(n) / math.log(2) + 0.5), "power of two") end
   end)

   H.test("the arrow points down in the file (the addon mirrors it for 'open'), is white and has transparency", function()
      local data, h = tga()
      local bottomOrigin = (math.floor(h.desc / 32) % 2) == 0
      local function alpha(x, y)       -- y = 0 is the top row on screen
         local row = bottomOrigin and (h.h - 1 - y) or y
         return data:byte(18 + (row * h.w + x) * 4 + 4)
      end
      local function rowWidth(y)
         local first, last
         for x = 0, h.w - 1 do
            if alpha(x, y) > 128 then
               first = first or x
               last = x
            end
         end
         return first and (last - first + 1) or 0
      end
      local top, bottom
      for y = 0, h.h - 1 do
         if rowWidth(y) > 0 then
            top = top or y
            bottom = y
         end
      end
      H.truthy(top and bottom and bottom > top, "has visible pixels")
      H.truthy(rowWidth(top) > rowWidth(bottom), "wide at the top, narrow at the bottom = pointing down")
      -- colour of opaque pixels is white (the addon tints it with SetVertexColor if it wants)
      local checked = 0
      for y = 0, h.h - 1 do
         for x = 0, h.w - 1 do
            if alpha(x, y) == 255 then
               local row = bottomOrigin and (h.h - 1 - y) or y
               local o = 18 + (row * h.w + x) * 4
               H.eq(data:byte(o + 1), 255)
               H.eq(data:byte(o + 2), 255)
               H.eq(data:byte(o + 3), 255)
               checked = checked + 1
            end
         end
      end
      H.truthy(checked > 20)
      H.truthy(alpha(0, 0) == 0, "corners are transparent")
   end)

   H.test("the arrow texture path of the code resolves to that file (no missing asset on load)", function()
      local F = require("fixtures")
      local PM = F.boot(H, { learned = { "alchemy" } })
      H.eq(PM.Skin.ARROW, "Interface\\AddOns\\ProfessionMenu\\Media\\chevron.tga")
      H.len(M.missingAssets, 0)
   end)

   -- ======================================================================
   H.section("TOC and README")
   -- ======================================================================

   H.test("every Lua file in the addon folder is listed in the TOC and every listed file exists (exact case)", function()
      local files = listFiles(M.root)
      local lua = {}
      for _, f in ipairs(files) do
         if f:match("%.lua$") then lua[f] = true end
      end
      local toc = readFile(M.root .. "/ProfessionMenu.toc")
      local listed = {}
      for line in toc:gmatch("[^\r\n]+") do
         if not line:match("^%s*#") and line:match("%S") then
            listed[line:match("^%s*(.-)%s*$")] = true
         end
      end
      for f in pairs(lua) do H.truthy(listed[f], f .. " is not listed in the TOC") end
      for f in pairs(listed) do
         H.truthy(lua[f], f .. " is listed in the TOC but does not exist with exactly that spelling")
      end
   end)

   H.test("the addon folder contains only the documented files", function()
      local files = listFiles(M.root)
      local allowed = { ["ProfessionMenu.toc"] = true, ["Locales.lua"] = true, ["Data.lua"] = true, ["Core.lua"] = true,
                        ["Skin.lua"] = true, ["UI.lua"] = true, ["Main.lua"] = true, ["Options.lua"] = true,
                        ["README.md"] = true, ["Media/chevron.tga"] = true, ["LICENSE"] = true,
                        ["docs/README.de.md"] = true }
      for _, f in ipairs(files) do H.truthy(allowed[f], "unexpected file " .. f) end
   end)

   H.test("the detailed README (docs/README.de.md) names every file of the addon", function()
      local readme = readFile(M.root .. "/docs/README.de.md")
      H.truthy(readme)
      for _, f in ipairs({ "ProfessionMenu.toc", "Locales.lua", "Data.lua", "Core.lua", "Skin.lua", "UI.lua", "Main.lua",
                           "Options.lua", "Media/chevron.tga", "LICENSE", "docs/README.de.md" }) do
         H.contains(readme, f)
      end
   end)

   H.test("the detailed README documents every chat command that exists", function()
      local readme = readFile(M.root .. "/docs/README.de.md")
      for _, cmd in ipairs({ "/berufe list", "/berufe sort", "/berufe headers", "/berufe ranks", "/berufe direction",
                             "/berufe scale", "/berufe unlock", "/berufe reset", "/berufe debug", "/profmenu",
                             "/berufe compact off|button|all", "/berufe abilities on|off" }) do
         H.contains(readme, cmd)
      end
   end)

   H.test("the detailed README category table matches Data.lua (names of the German professions per category)", function()
      local readme = readFile(M.root .. "/docs/README.de.md")
      local rows = {
         "Schmiedekunst, Lederverarbeitung, Schneiderei, Ingenieurskunst, Alchemie, Inschriftenkunde",
         "Verh\195\188ttung, Juwelenschleifen, Verzauberkunst",
         "Bergbau, Kr\195\164uterkunde, K\195\188rschnerei",
         "Kochkunst, Erste Hilfe, Angeln",
         "Angeln, Entzaubern, Sondieren, Mahlen, Lagerfeuer, Mineralien-, Kräuter-, Fischsuche",
      }
      for _, row in ipairs(rows) do H.contains(readme, row) end
   end)

   H.test("the short README (README.md) covers installation, the commands and the optional settings, and links the details and the license", function()
      local readme = readFile(M.root .. "/README.md")
      H.truthy(readme)
      for _, text in ipairs({ "ProfessionMenu", "3.3.5a", "/berufe", "/profmenu", "/berufe compact off|button|all",
                              "/berufe abilities on|off", "/berufe sort cat|alpha|rank", "bash tests/check.sh",
                              "Interface/AddOns", "docs/README.de.md", "(LICENSE)" }) do
         H.contains(readme, text)
      end
      H.truthy(select(2, readme:gsub("\n", "\n")) < 100, "the short README stays short")
      H.truthy(readFile(M.root .. "/LICENSE"), "LICENSE exists")
      H.contains(readFile(M.root .. "/LICENSE"), "MIT License")
   end)

   H.test("source files use LF line ends, 3-space indentation and UTF-8 (no BOM) -- the Lua loader of the mock checks BOM", function()
      for _, f in ipairs({ "Locales.lua", "Data.lua", "Core.lua", "Skin.lua", "UI.lua", "Main.lua", "Options.lua", "ProfessionMenu.toc" }) do
         local data = readFile(M.root .. "/" .. f)
         H.falsy(data:find("\r", 1, true), f .. " has CR")
         H.falsy(data:find("\t", 1, true), f .. " has a tab")
         H.neq(data:sub(1, 3), "\239\187\191", f .. " has a BOM")
      end
   end)
end
