-- Options.lua
-- ---------------------------------------------------------------------------
-- Optionen in ElvUIs Einstellungsfenster (/ec -> eigener Eintrag "Berufe-Menue"), nur wenn ElvUI da ist.
-- Die Werte liegen weiter in ProfessionMenuDB (PM.db); die Position verwaltet
-- ElvUIs Mover (E.db.movers). LibElvUIPlugin ruft die Funktion ohne Argumente, sobald
-- ElvUI_OptionsUI geladen ist (beim ersten /ec) oder sofort, wenn es das schon ist.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local E = _G.ElvUI and _G.ElvUI[1]
if not (E and E.Libs and E.Libs.EP) then return end

local L = PM.L

local function InsertOptions()
   E.Options.args.professionMenu = {
      order = 100,
      type = "group",
      name = L.opt_title,
      desc = L.opt_desc,
      get = function(info) return PM.db[info[#info]] end,
      set = function(info, value)
         PM.db[info[#info]] = value
         PM.Changed()
      end,
      args = {
         sort = {
            order = 1, type = "select", name = L.opt_sort,
            values = { cat = L.sortcat, alpha = L.sortalpha, rank = L.sortrank },
         },
         headers = { order = 2, type = "toggle", name = L.opt_headers },
         ranks = { order = 3, type = "toggle", name = L.opt_ranks },
         compact = {
            order = 4, type = "select", name = L.opt_compact,
            values = { off = L.compactoff, button = L.compactbutton, all = L.compactall },
         },
         abilities = { order = 5, type = "toggle", name = L.opt_abilities, desc = L.opt_abilities_desc },
         direction = {
            order = 6, type = "select", name = L.opt_direction,
            values = { auto = L.dirauto, up = L.dirup, down = L.dirdown },
         },
         move = {
            order = 7, type = "execute", name = L.opt_move,
            func = function() E:ToggleMoveMode() end,
         },
      },
   }
end

E.Libs.EP:RegisterPlugin(ADDON, InsertOptions)
