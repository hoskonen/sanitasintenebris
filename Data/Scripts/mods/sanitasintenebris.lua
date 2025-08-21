-- Load PollingManager first
Script.ReloadScript("Scripts/SanitasInTenebris/PollingManager.lua")
-- shared logging + helpers
Script.ReloadScript("Scripts/SanitasInTenebris/Utils.lua")
-- state management
Script.ReloadScript("Scripts/SanitasInTenebris/State.lua")
-- config values (e.g. intervals, buffs)
Script.ReloadScript("Scripts/SanitasInTenebris/Config.lua")
-- debug tools
Script.ReloadScript("Scripts/SanitasInTenebris/DebugTools.lua")
-- roof detection
Script.ReloadScript("Scripts/SanitasInTenebris/RoofDetection.lua")

Script.ReloadScript("Scripts/SanitasInTenebris/HeatDetection.lua")

Script.ReloadScript("Scripts/SanitasInTenebris/BuffLogic.lua")       -- ✅ used by InteriorLogic + Indoor + RainTracker
Script.ReloadScript("Scripts/SanitasInTenebris/IndoorDetection.lua") -- 🛖 depends on BuffLogic

Script.ReloadScript("Scripts/SanitasInTenebris/InteriorLogic.lua")   -- 🏠 depends on BuffLogic + IndoorDetection
Script.ReloadScript("Scripts/SanitasInTenebris/DryingSystem.lua")

Script.ReloadScript("Scripts/SanitasInTenebris/RainTracker.lua") -- 🌧️ depends on HeatDetection + BuffLogic
Script.ReloadScript("Scripts/SanitasInTenebris/RainCleans.lua")  -- 🚿 optional, depends only on Utils

-- 3. Entry point — always last
Script.ReloadScript("Scripts/SanitasInTenebris/Main.lua")

-- Bind poll functions globally for CryEngine timer access
_G["SanitasInTenebris.CheckRain"]   = SanitasInTenebris.CheckRain
_G["SanitasInTenebris.OutdoorPoll"] = SanitasInTenebris.OutdoorPoll
_G["SanitasInTenebris.IndoorPoll"]  = SanitasInTenebris.SafeIndoorPoll
