-- tests/test_detect.lua
-- ---------------------------------------------------------------------------
-- Erkennung der erlernten Berufe (Core.lua): Fertigkeiten lesen (auch unter zugeklappten Ueberschriften),
-- Zauberbuch lesen, Namenszuordnung in enUS/deDE, Aktionen, Symbole, Sortierung, Layout.
-- Alles ohne Oberflaeche: PM.Collect() liefert reine Daten.
-- ---------------------------------------------------------------------------

return function(H)
   local F = require("fixtures")

   local function collect(opts)
      local PM, M = F.boot(H, opts)
      local entries, skills, known = PM.Collect()
      return PM, M, entries, skills, known
   end

   local function keys(entries)
      local out = {}
      for _, e in ipairs(entries) do out[#out + 1] = e.key end
      return out
   end

   local function names(entries)
      local out = {}
      for _, e in ipairs(entries) do out[#out + 1] = e.name end
      return out
   end

   local function byKey(entries)
      local out = {}
      for _, e in ipairs(entries) do out[e.key] = e end
      return out
   end

   local ALL = F.ORDER

   local CAT_ORDER_KEYS = {
      "blacksmithing", "leatherworking", "tailoring", "engineering", "alchemy", "inscription",
      "smelting", "jewelcrafting", "enchanting",
      "mining", "herbalism", "skinning",
      "cooking", "firstaid", "fishing",
   }

   -- ======================================================================
   H.section("All professions, both languages")
   -- ======================================================================

   H.test("enUS: all 14 professions are found (15 entries with smelting), names from the skill lines", function()
      local PM, M, entries = collect({ learned = ALL })
      H.deepEq(keys(entries), CAT_ORDER_KEYS)
      H.deepEq(names(entries), {
         "Blacksmithing", "Leatherworking", "Tailoring", "Engineering", "Alchemy", "Inscription",
         "Smelting", "Jewelcrafting", "Enchanting",
         "Mining", "Herbalism", "Skinning",
         "Cooking", "First Aid", "Fishing",
      })
   end)

   H.test("deDE: all 14 professions are found, names are the German skill names, smelting is 'Verhuettung'", function()
      local PM, M, entries = collect({ learned = ALL, locale = "deDE" })
      H.deepEq(keys(entries), CAT_ORDER_KEYS)
      H.deepEq(names(entries), {
         "Schmiedekunst", "Lederverarbeitung", "Schneiderei", "Ingenieurskunst", "Alchemie", "Inschriftenkunde",
         "Verh\195\188ttung", "Juwelenschleifen", "Verzauberkunst",
         "Bergbau", "Kr\195\164uterkunde", "K\195\188rschnerei",
         "Kochkunst", "Erste Hilfe", "Angeln",
      })
   end)

   H.test("each profession alone is detected (enUS and deDE)", function()
      for _, locale in ipairs({ "enUS", "deDE" }) do
         for _, key in ipairs(ALL) do
            local _, _, entries = collect({ learned = { key }, locale = locale })
            local want = (key == "mining") and { "smelting", "mining" } or { key }
            if key == "mining" then
               -- smelting sorts before mining (refine before gather)
               H.deepEq(keys(entries), { "smelting", "mining" }, locale .. " " .. key)
            else
               H.deepEq(keys(entries), want, locale .. " " .. key)
            end
         end
      end
   end)

   -- ======================================================================
   H.section("Subsets")
   -- ======================================================================

   H.test("no professions: empty list, no error (only weapon/class skills exist)", function()
      local _, M, entries = collect({ learned = {} })
      H.len(entries, 0)
   end)

   H.test("no skill lines at all and an empty spellbook: empty list", function()
      local _, M, entries = collect({ skills = {}, spells = {} })
      H.len(entries, 0)
   end)

   H.test("only secondary professions", function()
      local _, _, entries = collect({ learned = { "fishing", "cooking", "firstaid" } })
      H.deepEq(keys(entries), { "cooking", "firstaid", "fishing" })
   end)

   H.test("mining without the smelting spell: mining alone, no smelting entry", function()
      local _, _, entries = collect({ learned = { "mining" }, noSmelting = true })
      H.deepEq(keys(entries), { "mining" })
      H.eq(entries[1].action, "Find Minerals")
   end)

   H.test("smelting spell known but mining skill missing: no smelting entry", function()
      local _, _, entries = collect({ learned = { "alchemy" }, extraSpells = { "Smelting", "Find Minerals" } })
      H.deepEq(keys(entries), { "alchemy" })
   end)

   H.test("mining without any spell: still listed, passive (no action), no smelting", function()
      local _, _, entries = collect({ learned = { "mining" }, noSpell = { "mining" } })
      H.deepEq(keys(entries), { "mining" })
      H.eq(entries[1].action, nil)
      H.eq(entries[1].kind, "none")
   end)

   H.test("a profession whose skill line exists but whose spell is missing is listed without action", function()
      local _, _, entries = collect({ learned = { "tailoring", "fishing" }, noSpell = { "tailoring" } })
      local e = byKey(entries)
      H.eq(e.tailoring.action, nil)
      H.eq(e.tailoring.kind, "none")
      H.eq(e.fishing.action, "Fishing")
   end)

   H.test("a spell without a skill line does not create an entry", function()
      local _, _, entries = collect({ learned = {}, extraSpells = { "Alchemy", "Fishing" } })
      H.len(entries, 0)
   end)

   H.test("herbalism: skill 'Herbalism' vs spell 'Herb Gathering' (enUS) and 'Kraeuterkunde' vs 'Kraeutersammeln' (deDE)", function()
      for _, locale in ipairs({ "enUS", "deDE" }) do
         local _, M, entries = collect({ learned = { "herbalism" }, locale = locale })
         H.deepEq(keys(entries), { "herbalism" }, locale)
         H.eq(entries[1].name, F.skillName("herbalism", locale), locale .. " name is the skill line name")
         H.neq(entries[1].name, (GetSpellInfo(2366)), locale .. " (differs from the gathering spell name)")
         H.eq(entries[1].action, (GetSpellInfo(2383)), locale .. " tracking spell")
      end
   end)

   H.test("unknown skill lines are ignored: Riding, weapon skills, languages, class skills", function()
      local _, _, entries = collect({
         learned = { "fishing" }, extraSkills = { { "Riding", 150, 150 }, { "Reiten", 75, 75 }, { "Archaeology", 1, 75 } },
      })
      H.deepEq(keys(entries), { "fishing" })
   end)

   H.test("a skill line is only a profession when it is not a header", function()
      -- a header called like a profession must not produce an entry
      local _, _, entries = collect({
         skills = { { name = "Mining", lines = { { "Defense", 1, 1 } } } }, spells = { "Mining", "Smelting" },
      })
      H.len(entries, 0)
   end)

   H.test("skill lines of the wrong locale are still matched (names of all languages are accepted)", function()
      -- deDE client but the skill line is English (e.g. a partially translated server)
      local _, _, entries = collect({
         locale = "deDE", skills = { { name = "Berufe", lines = { { "Alchemy", 100, 300 } } } },
         spells = { "Alchemie" },
      })
      H.deepEq(keys(entries), { "alchemy" })
      H.eq(entries[1].action, "Alchemie")
   end)

   -- ======================================================================
   H.section("Collapsed headers in the skills window")
   -- ======================================================================

   H.test("professions under a collapsed header are found and the header is collapsed again afterwards", function()
      local PM, M, entries = collect({ learned = { "mining", "fishing", "alchemy" }, collapsed = { Professions = true } })
      H.deepEq(keys(entries), { "alchemy", "smelting", "mining", "fishing" })
      H.eq(M.SkillStates().Professions, false, "Professions collapsed as before")
      H.eq(M.SkillStates()["Secondary Skills"], true, "untouched header stays expanded")
      H.truthy(M.calls.ExpandSkillHeader, "it was expanded for reading")
      H.eq(M.calls.ExpandSkillHeader, M.calls.CollapseSkillHeader, "one collapse per expand")
   end)

   H.test("all headers collapsed: everything is found, all states restored", function()
      local collapsed = {}
      for _, g in ipairs(F.GROUPS) do collapsed[g.en] = true end
      local PM, M, entries = collect({ learned = ALL, collapsed = collapsed })
      H.deepEq(keys(entries), CAT_ORDER_KEYS)
      for name, expanded in pairs(M.SkillStates()) do H.eq(expanded, false, name .. " collapsed again") end
      -- and again: repeated reads keep the state
      PM.Collect()
      PM.Collect()
      for name, expanded in pairs(M.SkillStates()) do H.eq(expanded, false, name .. " still collapsed") end
   end)

   H.test("mixed collapse states are restored exactly (collapsed stay collapsed, expanded stay expanded)", function()
      local PM, M = collect({ learned = ALL, collapsed = { ["Secondary Skills"] = true, ["Weapon Skills"] = true } })
      local before = M.SkillStates()
      PM.Collect()
      H.deepEq(M.SkillStates(), before)
      H.eq(before.Professions, true)
      H.eq(before["Secondary Skills"], false)
   end)

   H.test("nothing collapsed: no Expand/Collapse call at all", function()
      local PM, M = collect({ learned = ALL })
      H.eq(M.calls.ExpandSkillHeader, nil)
      H.eq(M.calls.CollapseSkillHeader, nil)
   end)

   H.test("collapsed headers in deDE (German group names)", function()
      local PM, M, entries = collect({ learned = { "mining", "cooking" }, locale = "deDE",
                                       collapsed = { Professions = true, ["Secondary Skills"] = true } })
      H.deepEq(keys(entries), { "smelting", "mining", "cooking" })
      H.eq(M.SkillStates()["Berufe"], false)
      H.eq(M.SkillStates()["Nebenberufe"], false)
   end)

   H.test("SKILL_LINES_CHANGED fired by Expand/Collapse while reading does not rebuild or loop (sync events)", function()
      local PM, M = collect({ learned = { "mining", "fishing" }, collapsed = { Professions = true } })
      local rebuilds = 0
      local orig = PM.UI.Rebuild
      PM.UI.Rebuild = function(...)
         rebuilds = rebuilds + 1
         return orig(...)
      end
      F.open(PM)
      H.eq(rebuilds, 1, "one rebuild for the first open")
      local scans = M.calls.GetNumSkillLines
      M.Advance(1)
      H.eq(M.calls.GetNumSkillLines, scans, "no rescans while idle with the menu open")
      H.eq(rebuilds, 1)
      H.falsy(PM.scanning, "scan flag reset")
      PM.UI.Close()
      F.open(PM)
      H.eq(rebuilds, 1, "second open: same list -> no rebuild")
      H.eq(M.SkillStates().Professions, false)
   end)

   H.test("with the events switched off (skillEventMode none) the same reads work", function()
      local PM, M, entries = collect({ learned = { "mining" }, collapsed = { Professions = true },
                                       world = { skillEventMode = "none" } })
      H.deepEq(keys(entries), { "smelting", "mining" })
      F.open(PM)
      M.Advance(0.5)
      H.eq(M.SkillStates().Professions, false)
   end)

   H.test("SKILL_LINES_CHANGED that arrives one frame late (client defers it) does not cause a rescan storm", function()
      -- If the client delivers the event asynchronously the PM.scanning flag is already false; the 0.5 s ignore
      -- window (PM.ignoreUntil) has to swallow the late events, otherwise every scan's Expand+Collapse
      -- produces two events that each start another scan (exponential growth).
      local PM, M = collect({ learned = { "mining" }, collapsed = { Professions = true },
                              world = { skillEventMode = "deferred" } })
      F.open(PM)
      local calls0 = M.calls.GetNumSkillLines
      M.Advance(0.25)       -- 5 frames
      local extra = M.calls.GetNumSkillLines - calls0
      H.truthy(extra <= 6, "rescans in 5 idle frames with the menu open: " .. tostring(extra))
   end)

   -- ======================================================================
   H.section("Ranks")
   -- ======================================================================

   H.test("rank and maxRank come from the skill line; smelting takes the ranks of mining", function()
      local _, _, entries = collect({ learned = { mining = { 375, 450 }, alchemy = { 450, 450 }, fishing = { 1, 75 } } })
      local e = byKey(entries)
      H.eq(e.mining.rank, 375); H.eq(e.mining.maxRank, 450)
      H.eq(e.smelting.rank, 375); H.eq(e.smelting.maxRank, 450)
      H.eq(e.alchemy.rank, 450); H.eq(e.alchemy.maxRank, 450)
      H.eq(e.fishing.rank, 1); H.eq(e.fishing.maxRank, 75)
   end)

   H.test("a skill line without maxRank still yields numbers (0), never nil", function()
      local _, _, entries = collect({
         skills = { { name = "Professions", lines = { { "Mining" } } } }, spells = { "Mining" },
      })
      H.eq(entries[1].rank, 0)
      H.eq(entries[1].maxRank, 0)
   end)

   -- ======================================================================
   H.section("Actions and kinds")
   -- ======================================================================

   H.test("action and kind per profession (enUS)", function()
      local _, _, entries = collect({ learned = ALL })
      local e = byKey(entries)
      H.eq(e.blacksmithing.action, "Blacksmithing"); H.eq(e.blacksmithing.kind, "window")
      H.eq(e.leatherworking.action, "Leatherworking")
      H.eq(e.tailoring.action, "Tailoring")
      H.eq(e.engineering.action, "Engineering")
      H.eq(e.alchemy.action, "Alchemy")
      H.eq(e.inscription.action, "Inscription")
      H.eq(e.jewelcrafting.action, "Jewelcrafting")
      H.eq(e.enchanting.action, "Enchanting")
      H.eq(e.smelting.action, "Smelting"); H.eq(e.smelting.kind, "window")
      H.eq(e.mining.action, "Find Minerals"); H.eq(e.mining.kind, "tracking")
      H.eq(e.herbalism.action, "Find Herbs"); H.eq(e.herbalism.kind, "tracking")
      H.eq(e.skinning.action, nil); H.eq(e.skinning.kind, "none")
      H.eq(e.cooking.action, "Cooking"); H.eq(e.cooking.kind, "window")
      H.eq(e.firstaid.action, "First Aid"); H.eq(e.firstaid.kind, "window")
      H.eq(e.fishing.action, "Fishing"); H.eq(e.fishing.kind, "use")
   end)

   H.test("action and kind per profession (deDE spell names)", function()
      local _, _, entries = collect({ learned = ALL, locale = "deDE" })
      local e = byKey(entries)
      H.eq(e.blacksmithing.action, "Schmiedekunst")
      H.eq(e.smelting.action, "Verh\195\188ttung")
      H.eq(e.mining.action, "Mineraliensuche"); H.eq(e.mining.kind, "tracking")
      H.eq(e.herbalism.action, "Kr\195\164utersuche")
      H.eq(e.skinning.action, nil)
      H.eq(e.fishing.action, "Angeln"); H.eq(e.fishing.kind, "use")
      H.eq(e.firstaid.action, "Erste Hilfe")
   end)

   H.test("only the first known spell of 'open' is used; unknown tracking spell gives a passive entry", function()
      local _, _, entries = collect({ learned = { "herbalism" }, noTracking = true })
      H.eq(entries[1].action, nil)
      H.eq(entries[1].kind, "none")
   end)

   H.test("spell tabs: professions in the last tab with many spells before are found (offsets)", function()
      local _, _, entries = collect({
         learned = { "mining", "fishing" },
         spellTabs = {
            { name = "General", spells = { "Attack", "Language Common" } },
            { name = "Warrior", spells = { "Attack", "Attack", "Attack" } },
            { name = "Crafts", spells = { "Mining", "Smelting", "Find Minerals", "Fishing" } },
            { name = "Empty", spells = {} },
         },
      })
      H.deepEq(keys(entries), { "smelting", "mining", "fishing" })
      H.eq(entries[2].action, "Find Minerals")
   end)

   -- ======================================================================
   H.section("Icons")
   -- ======================================================================

   H.test("icon is the static icon of Data.lua for every profession, also when the spells are known", function()
      local PM, _, entries = collect({ learned = ALL })
      for _, e in ipairs(entries) do
         H.eq(e.icon, PM.PROFESSION_BY_KEY[e.key].icon, e.key)
         H.matches(e.icon, "^Interface\\Icons\\", e.key)
      end
   end)

   H.test("icon does not depend on the spellbook (nothing known: still the static icon)", function()
      local PM = F.boot(H, { learned = { "mining", "blacksmithing" }, noSpell = { "mining", "blacksmithing" } })
      local e = byKey((PM.Collect()))
      H.eq(e.mining.icon, PM.PROFESSION_BY_KEY.mining.icon)
      H.eq(e.blacksmithing.icon, PM.PROFESSION_BY_KEY.blacksmithing.icon)
   end)

   -- ======================================================================
   H.section("Sorting")
   -- ======================================================================

   H.test("sort = cat: craft, refine, gather, secondary, within a category by 'order'", function()
      local PM, _, entries = collect({ learned = { "fishing", "alchemy", "mining", "enchanting", "blacksmithing", "skinning" } })
      PM.SortEntries(entries, "cat")
      H.deepEq(keys(entries), { "blacksmithing", "alchemy", "smelting", "enchanting", "mining", "skinning", "fishing" })
   end)

   H.test("sort = alpha (enUS): case-insensitive by displayed name", function()
      local PM, _, entries = collect({ learned = ALL, db = { sort = "alpha" } })
      H.deepEq(names(entries), {
         "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing", "Herbalism",
         "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Skinning", "Smelting", "Tailoring",
      })
   end)

   H.test("sort = alpha (deDE): umlauts keep their position within the words", function()
      local PM, _, entries = collect({ learned = ALL, locale = "deDE", db = { sort = "alpha" } })
      H.deepEq(names(entries), {
         "Alchemie", "Angeln", "Bergbau", "Erste Hilfe", "Ingenieurskunst", "Inschriftenkunde", "Juwelenschleifen",
         "Kochkunst", "Kr\195\164uterkunde", "K\195\188rschnerei", "Lederverarbeitung", "Schmiedekunst", "Schneiderei",
         "Verh\195\188ttung", "Verzauberkunst",
      })
   end)

   H.test("sort = rank: highest first; ties alphabetically; smelting ties with mining", function()
      local PM, _, entries = collect({
         learned = { mining = { 450, 450 }, alchemy = { 375, 450 }, herbalism = { 300, 450 }, skinning = { 300, 450 },
                     fishing = { 5, 75 } },
         db = { sort = "rank" },
      })
      H.deepEq(keys(entries), { "mining", "smelting", "alchemy", "herbalism", "skinning", "fishing" })
   end)

   H.test("sort = rank with equal ranks and names falls back to the key (stable, deterministic)", function()
      local PM = collect({ learned = { "alchemy", "enchanting" } })
      local list = {
         { key = "b", name = "Same", rank = 1, cat = "craft", order = 1 },
         { key = "a", name = "Same", rank = 1, cat = "craft", order = 1 },
      }
      PM.SortEntries(list, "rank")
      H.eq(list[1].key, "a")
      PM.SortEntries(list, "alpha")
      H.eq(list[1].key, "a")
   end)

   H.test("an unknown sort mode behaves like the category order", function()
      local PM, _, entries = collect({ learned = { "fishing", "alchemy" } })
      PM.SortEntries(entries, "bogus")
      H.deepEq(keys(entries), { "alchemy", "fishing" })
   end)

   H.test("BuildEntries takes the sort mode from the database", function()
      local PM = collect({ learned = { "fishing", "alchemy" } })
      PM.db.sort = "alpha"
      local entries = PM.Collect()
      H.deepEq(keys(entries), { "alchemy", "fishing" })
      PM.db.sort = "rank"
      PM.db.sort = "cat"
      H.deepEq(keys(PM.Collect()), { "alchemy", "fishing" })
   end)

   -- ======================================================================
   H.section("Layout (headers)")
   -- ======================================================================

   local function layoutKinds(layout)
      local out = {}
      for _, item in ipairs(layout) do out[#out + 1] = item.header and ("H:" .. item.header) or item.entry.key end
      return out
   end

   H.test("headers appear only for sort = cat and headers = true, one per category change", function()
      local PM, _, entries = collect({ learned = { "alchemy", "mining", "fishing", "cooking" } })
      local db = { sort = "cat", headers = true }
      H.deepEq(layoutKinds(PM.Layout(entries, db)),
         { "H:craft", "alchemy", "H:refine", "smelting", "H:gather", "mining", "H:secondary", "cooking", "fishing" })
      H.deepEq(layoutKinds(PM.Layout(entries, { sort = "cat", headers = false })),
         { "alchemy", "smelting", "mining", "cooking", "fishing" })
      PM.SortEntries(entries, "alpha")
      H.deepEq(layoutKinds(PM.Layout(entries, { sort = "alpha", headers = true })),
         { "alchemy", "cooking", "fishing", "mining", "smelting" })
      H.deepEq(layoutKinds(PM.Layout({}, db)), {})
   end)

   H.test("Layout with a rank-sorted list never emits headers, even with headers = true", function()
      local PM, _, entries = collect({ learned = { "alchemy", "mining" } })
      PM.SortEntries(entries, "rank")
      for _, item in ipairs(PM.Layout(entries, { sort = "rank", headers = true })) do H.falsy(item.header) end
   end)

   -- ======================================================================
   H.section("Signature")
   -- ======================================================================

   H.test("Signature changes with the list, the sort mode and the display options, not with ranks", function()
      local PM, M, entries = collect({ learned = { "alchemy", "fishing" } })
      local sig = PM.Signature(entries)
      M.SetSkillRank("Alchemy", 301)
      H.eq(PM.Signature((PM.Collect())), sig, "rank change alone keeps the signature")
      M.LearnSkill("Cooking", 1, 75, "Secondary Skills")
      H.neq(PM.Signature((PM.Collect())), sig, "a new skill line changes it")
      PM.db.sort = "alpha"
      H.neq(PM.Signature(entries), sig, "sort mode")
      PM.db.sort = "cat"
      PM.db.headers = false
      H.neq(PM.Signature(entries), sig, "headers option")
      PM.db.headers = true
      PM.db.ranks = false
      H.neq(PM.Signature(entries), sig, "ranks option")
   end)

   H.test("Signature changes when only the action changes (spell learned later)", function()
      local PM, M = collect({ learned = { "mining" }, noSmelting = true, noTracking = true })
      local sig = PM.Signature((PM.Collect()))
      M.LearnSpell("Find Minerals")
      H.neq(PM.Signature((PM.Collect())), sig)
   end)

   -- ======================================================================
   H.section("Locales beyond enUS and deDE")
   -- ======================================================================

   H.test("herbalism is detected in frFR although the gathering spell is called differently ('Cueillette')", function()
      -- frFR: skill line "Herboristerie", spell 2366 "Cueillette"; Data.lua carries the French skill name
      local PM, M = F.boot(H, {
         locale = "frFR",
         skills = { { name = "Métiers", lines = { { "Herboristerie", 100, 300 } } } },
         spells = { "Herb Gathering", "Find Herbs" },
         before = function(mock)
            mock.spellNames[2366].frFR = "Cueillette"
            mock.spellNames[2383].frFR = "Dénicher les herbes"
         end,
      })
      local entries = PM.Collect()
      H.deepEq(keys(entries), { "herbalism" })
   end)

   H.test("frFR: professions whose skill name equals the spell name are detected via GetSpellInfo", function()
      local PM, M = F.boot(H, {
         locale = "frFR",
         skills = { { name = "Métiers", lines = { { "Alchimie", 100, 300 }, { "Minage", 50, 300 } } } },
         spells = { "Alchemy", "Mining", "Smelting", "Find Minerals" },
         before = function(mock)
            mock.spellNames[2259].frFR = "Alchimie"
            mock.spellNames[2575].frFR = "Minage"
            mock.spellNames[2656].frFR = "Fonte"
            mock.spellNames[2580].frFR = "Dénicher les minerais"
         end,
      })
      local entries = PM.Collect()
      H.deepEq(keys(entries), { "alchemy", "smelting", "mining" })
      H.eq(byKey(entries).smelting.name, "Fonte")
      H.eq(byKey(entries).mining.action, "Dénicher les minerais")
   end)

   H.test("every profession is found by its Data.lua name in all ten client locales", function()
      local PM0 = F.boot(H, { learned = {} })
      local names = {}
      for _, key in ipairs(ALL) do names[key] = PM0.PROFESSION_BY_KEY[key].names end
      for _, locale in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "zhCN", "zhTW" }) do
         local lines = {}
         for _, key in ipairs(ALL) do lines[#lines + 1] = { names[key][locale], 100, 300 } end
         local PM = F.boot(H, {
            locale = locale, skills = { { name = "Professions", lines = lines } },
            spells = { "Alchemy", "Mining", "Smelting", "Find Minerals" },
         })
         local entries = PM.Collect()
         H.len(entries, 15, locale .. ": 14 professions + smelting")
         H.deepEq(keys(entries), CAT_ORDER_KEYS, locale)
      end
   end)

   H.test("the localized names in Data.lua are distinct across professions within each locale", function()
      local PM = F.boot(H, { learned = {} })
      for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }) do
         local seen = {}
         for _, def in ipairs(PM.PROFESSIONS) do
            if def.names then
               local n = def.names[locale]
               H.eq(type(n), "string", def.key .. " " .. locale)
               H.falsy(seen[n], locale .. ": " .. tostring(n) .. " is used by " .. def.key .. " and " .. tostring(seen[n]))
               seen[n] = def.key
            end
         end
      end
   end)

   H.test("Spanish Skinning is found under both names: skill 'Desollar' (client SkillLine.dbc) and spell 'Desuello'", function()
      -- Skill name from the esES client's SkillLine.dbc ("Desollar"), spell name from Spell.dbc / MultiBot ("Desuello").
      local PM = F.boot(H, { learned = {} })
      local def = PM.PROFESSION_BY_KEY.skinning
      H.eq(def.names.esES, "Desollar")
      H.eq(def.names.esMX, "Desollar")
      local set = PM.NameSet(def)
      H.truthy(set["Desollar"])
      H.truthy(set["Desuello"])
   end)

   H.test("a spellbook the API cannot enumerate (custom client) still yields the actions via GetSpellInfo(name)", function()
      local PM, M, entries = collect({ learned = { "mining", "fishing", "herbalism" }, world = { spellbookBroken = true } })
      H.eq(GetNumSpellTabs(), 0, "the mock really hides the book")
      H.deepEq(keys(entries), { "smelting", "mining", "herbalism", "fishing" })
      local e = byKey(entries)
      H.eq(e.mining.action, "Find Minerals")
      H.eq(e.smelting.action, "Smelting")
      H.eq(e.herbalism.action, "Find Herbs")
      H.eq(e.fishing.action, "Fishing")
   end)

   H.test("herbalism is also recognized through the helper spell 9134 whose name equals the skill name", function()
      local PM = F.boot(H, { learned = {} })
      local set = PM.NameSet(PM.PROFESSION_BY_KEY.herbalism)
      H.truthy(set[(GetSpellInfo(9134))])
      H.truthy(set[(GetSpellInfo(2366))])
   end)

   -- ======================================================================
   H.section("IdentifySkill and NameSet")
   -- ======================================================================

   H.test("IdentifySkill maps skill names to definitions (not to the derived smelting entry)", function()
      local PM = collect({ learned = {} })
      H.eq(PM.IdentifySkill("Mining").key, "mining")
      H.eq(PM.IdentifySkill("Bergbau").key, "mining")
      H.eq(PM.IdentifySkill("Kr\195\164uterkunde").key, "herbalism")
      H.eq(PM.IdentifySkill("Smelting"), nil)
      H.eq(PM.IdentifySkill("Riding"), nil)
      H.eq(PM.IdentifySkill(""), nil)
   end)

   H.test("NameSet contains the localized spell name and the static names", function()
      local PM = collect({ learned = {}, locale = "deDE" })
      local set = PM.NameSet(PM.PROFESSION_BY_KEY.herbalism)
      H.truthy(set["Kr\195\164utersammeln"])
      H.truthy(set["Kr\195\164uterkunde"])
      H.truthy(set["Herbalism"])
      local mining = PM.NameSet(PM.PROFESSION_BY_KEY.mining)
      H.truthy(mining["Bergbau"])
      H.truthy(mining["Mining"])
   end)
end
