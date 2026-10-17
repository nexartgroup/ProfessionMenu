-- tests/test_data.lua
-- ---------------------------------------------------------------------------
-- Datenpruefung zu Data.lua: jede Berufsdefinition ist in sich stimmig, Kategorien gibt es in jeder Sprache,
-- Schluessel/Reihenfolgen/Zauber-IDs sind eindeutig, und die festen Namen passen zu den Zaubernamen des
-- Spiels (hier: die Namen der Attrappe fuer enUS und deDE).
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local F = require("fixtures")

   local function boot(locale)
      local PM = F.boot(H, { locale = locale or "enUS", learned = {} })
      return PM
   end

   local KINDS = { window = true, tracking = true, use = true, none = true }
   local CATS = { craft = true, refine = true, gather = true, secondary = true }

   H.test("14 professions plus the derived smelting entry, keys unique", function()
      local PM = boot()
      H.len(PM.PROFESSIONS, 15)
      local seen = {}
      for _, def in ipairs(PM.PROFESSIONS) do
         H.falsy(seen[def.key], "duplicate key " .. tostring(def.key))
         seen[def.key] = true
         H.eq(PM.PROFESSION_BY_KEY[def.key], def, "PROFESSION_BY_KEY[" .. def.key .. "]")
      end
      for _, key in ipairs(F.ORDER) do H.truthy(seen[key], "missing profession " .. key) end
      H.truthy(seen.smelting)
   end)

   H.test("every definition has key, category, order, spells, open and kind that agree with each other", function()
      local PM = boot()
      for _, def in ipairs(PM.PROFESSIONS) do
         local k = def.key
         H.eq(type(k), "string")
         H.truthy(CATS[def.cat], k .. ": category " .. tostring(def.cat))
         H.eq(type(def.order), "number", k .. ": order")
         H.truthy(def.order >= 1 and def.order == math.floor(def.order), k .. ": order is a positive integer")
         if def.from then
            H.eq(type(def.spell), "number", k .. ": a derived entry has the spell of its own")
            H.eq(def.spells, nil, k .. ": a derived entry has no 'spells' list")
            H.deepEq(def.open, { def.spell }, k .. ": it casts its own spell")
         else
            H.eq(type(def.spells), "table", k .. ": spells")
            H.truthy(#def.spells >= 1, k .. ": at least one spell id")
            H.eq(def.spell, nil, k .. ": 'spell' is only for derived entries")
         end
         H.eq(type(def.open), "table", k .. ": open")
         H.truthy(KINDS[def.kind], k .. ": kind " .. tostring(def.kind))
         H.eq(type(def.icon), "string", k .. ": fallback icon")
         H.matches(def.icon, "^Interface\\Icons\\", k .. ": icon path")
         if def.kind == "none" then
            H.len(def.open, 0, k .. ": kind none has nothing to cast")
         else
            H.truthy(#def.open >= 1, k .. ": kind " .. def.kind .. " needs a spell to cast")
         end
         for _, id in ipairs(def.spells or {}) do H.eq(type(id), "number", k .. ": spell id type") end
         for _, id in ipairs(def.open) do H.eq(type(id), "number", k .. ": open id type") end
         if def.from then
            H.truthy(PM.PROFESSION_BY_KEY[def.from], k .. ": 'from' refers to an existing profession")
            H.falsy(PM.PROFESSION_BY_KEY[def.from].from, k .. ": derived from a derived entry")
            H.eq(def.names, nil, k .. ": a derived entry has no skill names of its own")
         else
            H.eq(type(def.names), "table", k .. ": names")
            for _, locale in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "zhCN", "zhTW" }) do
               H.eq(type(def.names[locale]), "string", k .. ": " .. locale .. " name")
               H.neq(def.names[locale], "", k .. ": " .. locale .. " name not empty")
            end
            H.eq(def.names.enGB, def.names.enUS, k .. ": enGB = enUS")
            H.eq(def.names.esMX, def.names.esES, k .. ": esMX = esES")
         end
      end
   end)

   H.test("categories: craft, refine, gather, secondary, abilities, in that order, all with localized headings", function()
      local PM = boot()
      H.deepEq(PM.CATEGORIES, { "craft", "refine", "gather", "secondary", "abilities" })
      for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "zhCN", "zhTW" }) do
         local t = PM.texts[locale]
         H.truthy(t, locale .. " texts exist")
         for _, cat in ipairs(PM.CATEGORIES) do
            H.eq(type(t["cat_" .. cat]), "string", locale .. " cat_" .. cat)
            H.neq(t["cat_" .. cat], "", locale .. " cat_" .. cat .. " not empty")
         end
      end
   end)

   H.test("order is unique and gap-free within each category", function()
      local PM = boot()
      for _, cat in ipairs(PM.CATEGORIES) do
         local orders, n = {}, 0
         for _, def in ipairs(PM.PROFESSIONS) do
            if def.cat == cat then
               H.falsy(orders[def.order], cat .. ": duplicate order " .. def.order .. " (" .. def.key .. ")")
               orders[def.order] = def.key
               n = n + 1
            end
         end
         for i = 1, n do H.truthy(orders[i], cat .. ": order " .. i .. " is missing (gap)") end
      end
   end)

   H.test("category sizes follow the README table (craft 6, refine 3, gather 3, secondary 3)", function()
      local PM = boot()
      local size = {}
      for _, def in ipairs(PM.PROFESSIONS) do size[def.cat] = (size[def.cat] or 0) + 1 end
      H.deepEq(size, { craft = 6, refine = 3, gather = 3, secondary = 3 })
   end)

   H.test("spell ids of 'spells' (and the own spell of derived entries) are unique across all definitions", function()
      local PM = boot()
      local seen = {}
      for _, def in ipairs(PM.PROFESSIONS) do
         local ids = {}
         for _, id in ipairs(def.spells or {}) do ids[#ids + 1] = id end
         if def.spell then ids[#ids + 1] = def.spell end
         for _, id in ipairs(ids) do
            H.falsy(seen[id], "spell id " .. id .. " used by " .. def.key .. " and " .. tostring(seen[id]))
            seen[id] = def.key
         end
      end
   end)

   H.test("every spell id in Data.lua exists in the game data of the mock", function()
      local PM = boot()
      for _, def in ipairs(PM.PROFESSIONS) do
         for _, id in ipairs(def.spells or {}) do H.truthy((GetSpellInfo(id)), def.key .. ": spells id " .. id) end
         for _, id in ipairs(def.open) do H.truthy((GetSpellInfo(id)), def.key .. ": open id " .. id) end
      end
   end)

   H.test("every static skill name equals the name of one of the profession's spells (enUS and deDE); herbalism needs its helper spell", function()
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local PM = boot(locale)
         for _, def in ipairs(PM.PROFESSIONS) do
            if def.names then
               local match
               for _, id in ipairs(def.spells) do
                  if (GetSpellInfo(id)) == def.names[locale] then match = id end
               end
               H.truthy(match, def.key .. " " .. locale .. ": no spell is called '" .. tostring(def.names[locale]) .. "'")
            end
         end
         -- herbalism: the gathering spell has another name, only the helper spell 9134 carries the skill name
         local herb = PM.PROFESSION_BY_KEY.herbalism
         H.deepEq(herb.spells, { 9134, 2366 })
         H.eq((GetSpellInfo(9134)), herb.names[locale], locale .. ": helper spell has the skill name")
         H.neq((GetSpellInfo(2366)), herb.names[locale], locale .. ": gathering spell has another name")
         H.eq(herb.names.enUS, "Herbalism")
         H.eq(herb.names.deDE, "Kr\195\164uterkunde")
      end
   end)

   H.test("fixtures and Data.lua agree on the skill names and spells of all 14 professions", function()
      local PM = boot()
      for _, key in ipairs(F.ORDER) do
         local def = PM.PROFESSION_BY_KEY[key]
         H.eq(def.names.enUS, F.PROFS[key].en, key)
         H.eq(def.names.deDE, F.PROFS[key].de, key)
         local has
         for _, id in ipairs(def.spells) do
            if id == F.PROFS[key].spell then has = true end
         end
         H.truthy(has, key .. ": the profession spell " .. F.PROFS[key].spell .. " is listed")
      end
   end)

   H.test("tracking professions cast the tracking spell, smelting is derived from mining", function()
      local PM = boot()
      local by = PM.PROFESSION_BY_KEY
      H.deepEq(by.mining.open, { 2580 })
      H.eq(by.mining.kind, "tracking")
      H.deepEq(by.herbalism.open, { 2383 })
      H.eq(by.herbalism.kind, "tracking")
      H.eq(by.smelting.from, "mining")
      H.eq(by.smelting.spell, 2656)
      H.deepEq(by.smelting.open, { 2656 })
      H.eq(by.smelting.cat, "refine")
      H.eq(by.skinning.kind, "none")
      H.eq(by.fishing.kind, "use")
      for _, key in ipairs({ "blacksmithing", "leatherworking", "tailoring", "engineering", "alchemy", "inscription",
                             "jewelcrafting", "enchanting", "cooking", "firstaid" }) do
         H.eq(by[key].kind, "window", key)
         H.deepEq(by[key].open, by[key].spells, key .. ": opens its own profession spell")
      end
   end)
end
