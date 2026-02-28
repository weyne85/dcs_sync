-- assert(loadfile("C:\\Users\\post\\Saved Games\\DCS\\Missions\\test28.lua"))()

local zoneset = SET_ZONE:New():FilterPrefixes("Zone"):FilterOnce()
zoneset:ForEach(
  function(zone)
    zone:DrawZone(-1,{0,0,1},1,{0,0,1},0.2,1,true)
  end
)

function RouteToNextZone(Group,Zone)
  
  BASE:I("RouteToNextZone: "..Zone:GetName())
  local grp = Group -- Wrapper.Group#GROUP
  local targetzone = Zone -- Core.Zone#ZONE_RADIUS
  
  local startpoint = grp:GetCoordinate()
  local roadpoint = startpoint:GetClosestPointToRoad()
  local endpoint = targetzone:GetRandomCoordinate(inner,outer,{land.SurfaceType.LAND,land.SurfaceType.ROAD})
  
  local task = grp:TaskFunction("RouteToNextZone",zoneset:GetRandom())
  
  local route = {}
  local startwpt = startpoint:WaypointGround(30,AI.Task.VehicleFormation.OFF_ROAD)
  local roadwpt = roadpoint:WaypointGround(30,AI.Task.VehicleFormation.ON_ROAD)
  local endwpt = endpoint:WaypointGround(30,AI.Task.VehicleFormation.ON_ROAD,{task})
  
  route[#route+1] = startwpt
  route[#route+1] = roadwpt
  route[#route+1] = endwpt
  
  MESSAGE:New(string.format("Routing group %s to zone %s!",grp:GetName(),targetzone:GetName()),15,"Info"):ToAll()
  
  grp:Route(route,1)
  
end

local vehicle = SPAWN:New("Vehicle")
  :InitRandomizeZones(zoneset:GetSet())
  :InitLimit(0,5)
  :OnSpawnGroup(function(grp) RouteToNextZone(grp,zoneset:GetRandom()) end)
  :SpawnScheduled(5,0.5)
  