-- No MOOSE settings menu. Comment out this line if required.
_SETTINGS:SetPlayerMenuOff()

-- S-3B Recovery Tanker spawning in air.
local tanker=RECOVERYTANKER:New("USS Stennis", "Texaco Group")
tanker:SetTakeoffAir()
tanker:SetRadio(250)
tanker:SetModex(511)
tanker:SetTACAN(1, "TKR")
tanker:__Start(1)

-- E-2D AWACS spawning on Stennis.
local awacs=RECOVERYTANKER:New("USS Stennis", "E-2D Wizard Group")
awacs:SetAWACS()
awacs:SetRadio(260)
awacs:SetAltitude(20000)
awacs:SetCallsign(CALLSIGN.AWACS.Wizard)
awacs:SetRacetrackDistances(30, 15)
awacs:SetModex(611)
awacs:SetTACAN(2, "WIZ")
awacs:__Start(1)

-- Rescue Helo with home base Lake Erie. Has to be a global object!
local rescuehelo=RESCUEHELO:New("USS Stennis", "Rescue Helo")
rescuehelo:SetHomeBase(AIRBASE:FindByName("Lake Erie"))
rescuehelo:SetModex(42)
rescuehelo:__Start(1)
  
-- Create AIRBOSS object.
local AirbossStennis=AIRBOSS:New("USS Stennis")

-- FunkMan
AirbossStennis:SetFunkManOn(10043)

-- Add recovery windows:
-- Case I from 9 to 10 am.
local window1=AirbossStennis:AddRecoveryWindow( "9:00", "10:00", 1, nil, false, 25)
-- Case II with +15 degrees holding offset from 15:00 for 60 min.
local window2=AirbossStennis:AddRecoveryWindow("15:00", "16:00", 2,  nil, false, 23)
-- Case III with +30 degrees holding offset from 2100 to 2200.
local window3=AirbossStennis:AddRecoveryWindow("21:00", "22:00", 3,  nil, false, 21)

-- Set folder of airboss sound files within miz file.
AirbossStennis:SetSoundfilesFolder("Airboss Soundfiles/")

-- Single carrier menu optimization.
AirbossStennis:SetMenuSingleCarrier()

-- Skipper menu.
AirbossStennis:SetMenuRecovery(30, 20, false)

-- Remove landed AI planes from flight deck.
AirbossStennis:SetDespawnOnEngineShutdown()

-- Load all saved player grades from your "Saved Games\DCS" folder (if lfs was desanitized).
AirbossStennis:Load()

-- Set Illumination
AirbossStennis:SetCarrierIllumination(2)

-- Automatically save player results to your "Saved Games\DCS" folder each time a player get a final grade from the LSO.
AirbossStennis:SetAutoSave()

-- Enable trap sheet.
AirbossStennis:SetTrapSheet()

-- Start airboss class.
AirbossStennis:Start()


--- Function called when recovery tanker is started.
function tanker:OnAfterStart(From,Event,To)

  -- Set recovery tanker.
  AirbossStennis:SetRecoveryTanker(tanker)  


  -- Use tanker as radio relay unit for LSO transmissions.
  AirbossStennis:SetRadioRelayLSO(self:GetUnitName())
  
end

--- Function called when AWACS is started.
function awacs:OnAfterStart(From,Event,To)
  -- Set AWACS.
  AirbossStennis:SetAWACS(awacs)
end


--- Function called when rescue helo is started.
function rescuehelo:OnAfterStart(From,Event,To)
  -- Use rescue helo as radio relay for Marshal.
  AirbossStennis:SetRadioRelayMarshal(self:GetUnitName())
end

--- Function called when a player gets graded by the LSO.
function AirbossStennis:OnAfterLSOGrade(From, Event, To, playerData, grade)
  local PlayerData=playerData --Ops.Airboss#AIRBOSS.PlayerData
  local Grade=grade --Ops.Airboss#AIRBOSS.LSOgrade
end


---------------------------
--- Generate AI Traffic ---
---------------------------

-- Spawn some AI flights as additional traffic.
local F181=SPAWN:New("FA-18C Group 1"):InitModex(111) -- Coming in from NW after ~ 6 min
local F182=SPAWN:New("FA-18C Group 2"):InitModex(112) -- Coming in from NW after ~20 min
local F183=SPAWN:New("FA-18C Group 3"):InitModex(113) -- Coming in from W  after ~18 min
local F14=SPAWN:New("F-14B 2ship"):InitModex(211)     -- Coming in from SW after ~ 4 min
local E2D=SPAWN:New("E-2D Group"):InitModex(311)      -- Coming in from NE after ~10 min
local S3B=SPAWN:New("S-3B Group"):InitModex(411)      -- Coming in from S  after ~16 min
  
-- Spawn always 9 min before the recovery window opens.
local spawntimes={"8:51", "14:51", "20:51"}
for _,spawntime in pairs(spawntimes) do
  local _time=UTILS.ClockToSeconds(spawntime)-timer.getAbsTime()
  if _time>0 then
    SCHEDULER:New(nil, F181.Spawn, {F181}, _time)
    SCHEDULER:New(nil, F182.Spawn, {F182}, _time)
    SCHEDULER:New(nil, F183.Spawn, {F183}, _time)
    SCHEDULER:New(nil, F14.Spawn,  {F14},  _time)
    SCHEDULER:New(nil, E2D.Spawn,  {E2D},  _time)
    SCHEDULER:New(nil, S3B.Spawn,  {S3B},  _time)
  end
end


-----------
-- Range --
-----------

-- These are names of the corresponding units defined in the ME
local strafepit_left={"GWR Strafe Pit Left 1", "GWR Strafe Pit Left 2"}
local strafepit_right={"GWR Strafe Pit Right 1", "GWR Strafe Pit Right 2"}

-- Bombing Targets
local bombtargets={"GWR Bomb Target Circle Middle", "GWR Bomb Target Circle Left", "GWR Bomb Target Circle Right"}

-- Create Range Object
GoldwaterRange=RANGE:New("Goldwater Range")

-- Ceiling altitude
GoldwaterRange:SetRangeCeiling(25000)
GoldwaterRange:EnableRangeCeiling(true)

-- Distance between THT and foul line
GoldwaterRange:GetFoullineDistance("GWR Strafe Pit Left 1", "GWR Foul Line Left")

-- Add strafe pits
GoldwaterRange:AddStrafePit(strafepit_left, 3000, 300, nil, true, 30, 500)
GoldwaterRange:AddStrafePit(strafepit_right, nil, nil, nil, true, nil, 500)

-- Add bomb targets
GoldwaterRange:AddBombingTargets(bombtargets, 50)

-- Voice over
-- Instructor
GoldwaterRange:SetInstructorRadio(123)

-- Control
GoldwaterRange:SetRangeControl(124)

-- Range Soundfiles
GoldwaterRange:SetSoundfilesPath("Range Soundfiles/")

-- FunkMan
GoldwaterRange:SetFunkManOn(10043)

-- Start Range
GoldwaterRange:Start()




-- Create RAT object from Su-33 template.
--local fa18=RAT:New("RAT_fa18")

-- Huey departing from FARP Berlin.
--fa18:SetDeparture({"Batumi"})

-- Flying to Normandy.
--fa18:SetDestination({"USS Stennis"})

-- Take-off with engines on.
--fa18:SetTakeoff("hot")

-- Spawn two aircraft.
--fa18:Spawn(2)

-- Create RAT object from Su-33 template.
local f14=RAT:New("RAT_f14")

-- Huey departing from FARP Berlin.
f14:SetDeparture({"USS Stennis"})

-- Flying to Normandy.
f14:SetDestination({"Batumi"})

-- Take-off with engines on.
f14:SetTakeoff("hot")

-- Spawn two aircraft.
--f14:Spawn(2)

f14:SetDeparture({"Batumi"})
f14:SetDestination({"USS Stennis"})
f14:SetTakeoff("cold")
f14:Spawn(6)


-- Create RAT object. The only required parameter is the name of the template group in the mission editor.
local yak=RAT:New("RAT_Yak")

-- Set Gudauta as departure airport for all spawned aircraft. (Not required for ContinueJourney() to work.)
yak:SetDeparture("Senaki-Kolkhi")

-- This makes aircraft respawn at their destination airport instead of another random airport.
yak:ContinueJourney()

-- Spawn five aircraft.
yak:Spawn(5)