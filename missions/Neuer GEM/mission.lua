-- ==========================================================
-- OPERATION: GOLDEN SANDS - ENHANCED AIRBOSS & CTLD
-- ==========================================================

-- No MOOSE settings menu. Comment out this line if required.
_SETTINGS:SetPlayerMenuOff()

-- S-3B Recovery Tanker spawning in air.
local tanker=RECOVERYTANKER:New("USS Theodore Roosevelt", "Texaco Group")
tanker:SetTakeoffAir()
tanker:SetRadio(250)
tanker:SetModex(511)
tanker:SetTACAN(1, "TKR")
tanker:__Start(1)

-- E-2D AWACS spawning on Stennis.
local awacs=RECOVERYTANKER:New("USS Theodore Roosevelt", "E-2D Wizard Group")
awacs:SetAWACS()
awacs:SetRadio(260)
awacs:SetAltitude(20000)
awacs:SetCallsign(CALLSIGN.AWACS.Wizard)
awacs:SetRacetrackDistances(30, 15)
awacs:SetModex(611)
awacs:SetTACAN(2, "WIZ")
awacs:__Start(1)

-- Rescue Helo with home base Lake Erie. Has to be a global object!
local rescuehelo=RESCUEHELO:New("USS Theodore Roosevelt", "Rescue Helo")
rescuehelo:SetHomeBase(AIRBASE:FindByName("Lake Erie"))
rescuehelo:SetModex(42)
rescuehelo:__Start(1)
  
-- Create AIRBOSS object.
local AirbossStennis=AIRBOSS:New("USS Theodore Roosevelt")

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


-------------------------------------------------------------------------------------------------
--------------------------------CTLD-SETUP-------------------------------------------------------
-------------------------------------------------------------------------------------------------
-- 2. CTLD SETUP (Helicopter Logistics)
-- Initialisierung für Blau
CTLD_Blue = CTLD:New(coalition.side.BLUE, {"PL_APACHE", "PL_HIND", "PL_CHINOOK"}, "CTLD_Manager")

-- Pickup Zonen für Truppen & Kisten
CTLD_Blue:AddExtractionZone( "PickupZoneAlpha", CTLD.PickupZoneType.Troops, smoke, true )

-- Truppen-Konfiguration
CTLD_Blue:SetUnitCapabilities({
    ["AH-64D BLK.II"] = { troops = 2, crates = 1 },
    ["CH-47F"] = { troops = 24, crates = 4 },
    ["Mi-24P"] = { troops = 8, crates = 2 }
})

-- Aktiviere Standard-Truppen-Menüs (Infantry, AT, AA)
CTLD_Blue:SetDefaultTroops()

-- Kisten-Logistik (Ermöglicht Aufbau von FOBs oder SAMs)
CTLD_Blue:AddCrateStock("Zone_Pickup_Blue", "Crate Stock", 100, 20)

-- 3. DYNAMISCHE FRONT (Bodenkonvois)
BlueConvoySpawner = SPAWN:New("BLUE_CONVOY"):InitLimit(4, 10):SpawnScheduled(300, 0.4)
RedConvoySpawner = SPAWN:New("RED_CONVOY"):InitLimit(4, 10):SpawnScheduled(300, 0.4)

-- 4. HELI QRF (Reaktion auf Blau)
DetectionZone = ZONE:New("Zone_Front")
RedHeliSpawner = SPAWN:New("RED_HELI_QRF")

SCHEDULER:New(nil, function()
    local BlueUnits = SET_UNIT:New():FilterCoalitions("blue"):FilterZones({DetectionZone}):FilterStart()
    if BlueUnits:Count() > 0 then
        RedHeliSpawner:Spawn()
        MESSAGE:New("WARNUNG: Feindliche QRF Helikopter detektiert!", 10):ToBlue()
    end
end, {}, 30, 600)

env.info("Mission Golden Sands (Airboss & CTLD) geladen!")