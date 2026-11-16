-- Options.lua
-- ---------------------------------------------------------------------------
-- Einstellungsfenster: Spiel-Menue > Optionen > AddOns > "Berufe-Menue". Gebaut mit der
-- Einstellungs-Schnittstelle des Spiels (Settings.*, siehe Blizzard_Settings_Shared). Die Werte liegen
-- weiter in ProfessionMenuDB (PM.db); eine Aenderung stoesst PM.Changed an.
-- Jedes Bedienelement wird einzeln gebaut: scheitert eines, fehlt nur dieses.
-- ---------------------------------------------------------------------------

local ADDON, PM = ...

local L = PM.L
local pcall, type, tostring = pcall, type, tostring

local category

local function Available()
   local s = _G.Settings
   return type(s) == "table" and s.RegisterVerticalLayoutCategory and s.RegisterAddOnSetting and s.RegisterAddOnCategory
      and s.CreateCheckbox and s.CreateDropdown and s.CreateControlTextContainer and s.VarType
end

function PM.RegisterOptions()
   if category or not Available() then return false end
   local Settings = _G.Settings
   local db = PM.db
   local defaults = PM.DEFAULTS
   local cat = Settings.RegisterVerticalLayoutCategory(L.opt_title)

   local function Changed() PM.Changed() end

   local function Add(label, fn)
      local ok, err = pcall(fn)
      if not ok then PM.ReportOnce("Options:" .. tostring(label), err) end
   end

   local function Checkbox(key, label, tooltip)
      Add(label, function()
         local setting = Settings.RegisterAddOnSetting(cat, "PROFESSIONMENU_" .. key, key, db,
            Settings.VarType.Boolean, label, defaults[key])
         if setting.SetValueChangedCallback then setting:SetValueChangedCallback(Changed) end
         Settings.CreateCheckbox(cat, setting, tooltip)
      end)
   end

   local function Dropdown(key, label, choices)
      Add(label, function()
         local setting = Settings.RegisterAddOnSetting(cat, "PROFESSIONMENU_" .. key, key, db,
            Settings.VarType.String, label, defaults[key])
         if setting.SetValueChangedCallback then setting:SetValueChangedCallback(Changed) end
         local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
            return container:GetData()
         end
         Settings.CreateDropdown(cat, setting, GetOptions)
      end)
   end

   Dropdown("sort", L.opt_sort, {
      { "cat", L.sortcat }, { "alpha", L.sortalpha }, { "rank", L.sortrank },
   })
   Checkbox("headers", L.opt_headers)
   Checkbox("ranks", L.opt_ranks)
   Dropdown("compact", L.opt_compact, {
      { "off", L.compactoff }, { "button", L.compactbutton }, { "all", L.compactall },
   })
   Dropdown("activities", L.opt_activities, {
      { "sub", L.actsub }, { "list", L.actlist }, { "off", L.actoff },
   })
   Dropdown("camp", L.opt_camp, {
      { "auto", L.campauto }, { "all", L.campall }, { "off", L.campoff },
   })
   Checkbox("unlearned", L.opt_unlearned, L.opt_unlearned_desc)
   Dropdown("direction", L.opt_direction, {
      { "auto", L.dirauto }, { "up", L.dirup }, { "down", L.dirdown },
   })
   Checkbox("locked", L.opt_locked, L.opt_locked_desc)

   -- Skalierung: ein Schieberegler (UI.ApplyScale ist im Kampf gesperrt und tut dort nichts)
   if Settings.CreateSlider and Settings.CreateSliderOptions then
      Add(L.opt_scale, function()
         local setting = Settings.RegisterAddOnSetting(cat, "PROFESSIONMENU_scale", "scale", db,
            Settings.VarType.Number, L.opt_scale, defaults.scale)
         if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
               if PM.ready and PM.UI and PM.UI.ApplyScale then PM.UI.ApplyScale(true) end
            end)
         end
         local options = Settings.CreateSliderOptions(0.5, 2, 0.05)
         local slider = _G.MinimalSliderWithSteppersMixin
         if options.SetLabelFormatter and slider and slider.Label then
            options:SetLabelFormatter(slider.Label.Right)
         end
         Settings.CreateSlider(cat, setting, options)
      end)
   end

   Settings.RegisterAddOnCategory(cat)
   category = cat
   return true
end

-- Oeffnet das Einstellungsfenster auf der Seite des Addons. Rueckgabe: true, wenn es klappte.
function PM.OpenOptions()
   local Settings = _G.Settings
   if not (category and Settings and Settings.OpenToCategory and category.GetID) then return false end
   local ok = pcall(Settings.OpenToCategory, category:GetID())
   return ok
end
