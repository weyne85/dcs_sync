-------------------------------------------------------------------------
-- SET-SCENERY-100 - Scenery Set From Zone
-------------------------------------------------------------------------
-- Documentation
-- 
-- SET_SCENERY: https://flightcontrol-master.github.io/MOOSE_DOCS_DEVELOP/Documentation/Core.Set.html##(SET_SCENERY)
-- 
-------------------------------------------------------------------------
-- Join the game master slot initially, and then the Tank in
-- Combined Arms after a few seconds. Shoot and destroy on of the tanks
-- ahead.
-------------------------------------------------------------------------
-- Date: November 2022
-------------------------------------------------------------------------

-- Get our ZONE object and draw it
local zone = ZONE:FindByName("OilTankZone")
zone:DrawZone(-1,{0,0,1},nil,nil,nil,1)
-- Create a SET_SCENERY from the map objects in the zone
local oilstation = SET_SCENERY:NewFromZone(zone)
-- we'll use this SET for further filtering
local oiltanks = SET_SCENERY:New()

-- An Airbase has a lot of map objects, but we only want to have tanks
oilstation:ForEachScenery(
  function(object)
    local scenery = object --Wrapper.Scenery#SCENERY
    local name = scenery:GetName()
    local desc = scenery:GetDesc()
    BASE:I({desc.typeName})
    if string.find(string.lower(desc.typeName),"tank") then
      oiltanks:AddObject(scenery)
    end
  end
)

-- Count how many we have
local NumberTanks0 = oiltanks:CountAlive()
-- user flag OilTanks will be zero initially
local flag = USERFLAG:New("OilTanks")
flag:Set(0)

-- Function to check number of alive tanks regularly   
function CheckOnOilTanks(TankSet,InitialNo,Threshold)
  local NumberTanks = TankSet:CountAlive()
  MESSAGE:New("Oil Tanks alive: "..NumberTanks,15,"OilTanks"):ToAll()
  if NumberTanks <= InitialNo*Threshold then
    -- Success!
    MESSAGE:New("Success! Oil Tanks have been diminished!",15,"OilTanks"):ToAll()
    -- Set a Flag in Mission Editor
    flag:Set(999)
  end
end

-- Create a timer to run the check function
local TankTimer = TIMER:New(CheckOnOilTanks,oiltanks,NumberTanks0,0.2)
-- check every minute
TankTimer:Start(10,30,3600)
