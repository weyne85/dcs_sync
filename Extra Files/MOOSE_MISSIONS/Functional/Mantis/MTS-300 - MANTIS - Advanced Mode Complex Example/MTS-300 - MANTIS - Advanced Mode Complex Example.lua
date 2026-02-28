-------------------------------------------------------------------------
-- MTS-300 - MANTIS - Advanced Mode Complex Example
-------------------------------------------------------------------------
-- Documentation
-- 
-- MANTIS: https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Functional.Mantis.html
-- 
-------------------------------------------------------------------------
-- Observe a set of SAM sites being attacked by F18 SEAD and A10Cs. 
-- HQ will be destroyed after 10 mins.
-- Watch the long an short range MANTIS in action, with the SA10 also using SHORAD for defense.
-------------------------------------------------------------------------
-- Date: 14 July 2021 - Updated July 2025

-- Long-range SAM site, also linked to SHORAD
local myredsa10 = MANTIS:New("Red Defenses","Red SAM","Red EWR","Red HQ","red",true,"Red AWACS")
myredsa10:SetDetectInterval(20)
myredsa10:SetAutoRelocate(true,false)
myredsa10:SetAdvancedMode(true)
--myredsa10:Debug(true)
myredsa10:Start()

-- Using some "OnAfter..." events to shape the mission
function myredsa10:OnAfterShoradActivated(From, Event, To, Name, Radius, Ontime)
  -- show some info
  local m = MESSAGE:New(string.format("Mantis switched on Shorad for %s | Radius %d | OnTime %d", Name, Radius, Ontime),10,"Info"):ToAll()
end

function myredsa10:OnAfterAdvStateChange(From, Event, To, Oldstate, Newstate, Interval)
    -- show some info
  local state = { [1] = "GREEN", [2] = "AMBER", [3] = "RED" }
  local oldstate = state[Oldstate+1]
  local newstate = state[Newstate+1]
  local m = MESSAGE:New(string.format("Mantis switched Advanced from from %s to %s interval %dsec", oldstate, newstate, Interval),10,"Info"):ToAll()
end

function myredsa10:OnAfterRedState(From, Event, To, Group)
   -- show some info
  local SamName = Group:GetName()
  local m = MESSAGE:New(string.format("Mantis switched %s to RED state!", SamName),10,"Info"):ToAll()
end

function myredsa10:OnAfterGreenState(From, Event, To, Group)
   -- show some info
  local SamName = Group:GetName()
  local m = MESSAGE:New(string.format("Mantis switched %s to GREEN state!", SamName),10,"Info"):ToAll()
end

-- Destroy HQ after 5 mins
function TerminateHQ()
  local group = GROUP:FindByName("Red HQ")
  group:Destroy()
end

local desthqtimer = TIMER:New(TerminateHQ)
desthqtimer:Start(600)
