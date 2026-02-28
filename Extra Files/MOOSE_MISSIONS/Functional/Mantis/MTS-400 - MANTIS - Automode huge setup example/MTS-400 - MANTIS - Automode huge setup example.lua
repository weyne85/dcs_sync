-------------------------------------------------------------------------
-- MTS-400 - MANTIS - Auto-mode huge set-up example
-------------------------------------------------------------------------
-- Documentation
-- 
-- MANTIS: https://flightcontrol-master.github.io/MOOSE_DOCS_DEVELOP/Documentation/Functional.Mantis.html
-- 
-------------------------------------------------------------------------
-- Observe a set of SAM sites being attacked by F18 SEAD 
-------------------------------------------------------------------------
-- Date: Mar 2025 - Updated July 2025

--- Borders
local israelborder = ZONE_POLYGON:New("Israel",GROUP:FindByName("Israel Border"))
local syriaborder = ZONE_POLYGON:New("Syria",GROUP:FindByName("Syria Border"))
israelborder:DrawZone(-1,{0,1,0},1,{0,1,0},.1,1,true)
syriaborder:DrawZone(-1,{1,0,0},1,{1,0,0},.1,1,true)

--- MANTIS
local RedMantis = MANTIS:New("SyMantis","SAM-SA","EWR",nil,"red")
RedMantis:AddZones({syriaborder},{israelborder}) --accept and reject zones
RedMantis:__Start(5)

function RedMantis:OnAfterSeadSuppressionPlanned(From, Event, To, Group, Name, SuppressionStartTime, SuppressionEndTime)
  MESSAGE:New("SAM Suppression planned! "..Name.. " is planning to shut down.",10):ToAll()
  BASE:I("SAM Suppression planned! "..Name.. " is planning to shut down.")
end

function RedMantis:OnAfterSeadSuppressionStart(From, Event, To, Group, Name)
  MESSAGE:New("SAM Suppressed! "..Name.. " is suppressed.",10):ToAll()
  BASE:I("SAM Suppressed! "..Name.. "is suppressed!" )
end

function RedMantis:OnAfterRedState(From,Event,To,Group)
  local Name = Group:GetName()
  MESSAGE:New("SAM "..Name.. " switched to RED",10):ToAll()
  BASE:I("SAM "..Name.. " switched to RED" )
end

function RedMantis:OnAfterGreenState(From,Event,To,Group)
  local Name = Group:GetName()
  MESSAGE:New("SAM "..Name.. " switched to GREEN",10):ToAll()
  BASE:I("SAM "..Name.. " switched to GREEN" )
end

--- get some SEAD flights
function GetBlueCAS()
  local BlueCAS = SPAWN:New("Aerial-2"):Spawn()
  local BlueCAS2 = SPAWN:New("Aerial-3"):Spawn()
end

local bluetimer = TIMER:New(GetBlueCAS)
bluetimer:Start(20)