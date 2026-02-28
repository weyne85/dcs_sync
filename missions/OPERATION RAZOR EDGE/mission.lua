-- ==========================================================
-- OPERATION RAZOR EDGE - IMMERSIVE C2 & SOUND EDITION (FIXED V11)
-- ==========================================================

-- 0. DEFINITION DER HILFSFUNKTION (MUSS GANZ OBEN STEHEN)
local function SafeCall(name, func)
    local status, err = pcall(func)
    if not status then
        env.error("AUDIT ERROR in " .. name .. ": " .. tostring(err))
    else
        env.info("AUDIT: " .. name .. " loaded successfully.")
    end
end

env.info('AUDIT: V11 STARTING - ALL SYSTEMS GO.')


-- 1. AIRBOSS
-- No MOOSE settings menu. Comment out this line if required.
_SETTINGS:SetPlayerMenuOff()

-- S-3B Recovery Tanker spawning in air.
local tanker=RECOVERYTANKER:New("Carrier_Stennis", "Texaco Group")
tanker:SetTakeoffAir()
tanker:SetRadio(250)
tanker:SetModex(511)
tanker:SetTACAN(1, "TKR")
tanker:__Start(1)

-- E-2D AWACS spawning on Stennis.
local awacs=RECOVERYTANKER:New("Carrier_Stennis", "E-2D Wizard Group")
awacs:SetAWACS()
awacs:SetRadio(260)
awacs:SetAltitude(20000)
awacs:SetCallsign(CALLSIGN.AWACS.Wizard)
awacs:SetRacetrackDistances(30, 15)
awacs:SetModex(611)
awacs:SetTACAN(2, "WIZ")
awacs:__Start(1)

-- Rescue Helo with home base Lake Erie. Has to be a global object!
local rescuehelo=RESCUEHELO:New("Carrier_Stennis", "Rescue Helo")
rescuehelo:SetHomeBase(AIRBASE:FindByName("Lake Erie"))
rescuehelo:SetModex(42)
rescuehelo:__Start(1)

-- Create AIRBOSS object.
local AirbossStennis=AIRBOSS:New("Carrier_Stennis")

-- Add recovery windows:
-- Case I from 9 to 10 am.
local window1=AirbossStennis:AddRecoveryWindow( "9:00", "10:00", 1, nil, false, 25)
-- Case III from 11:00 to 23:00
local window3=AirbossStennis:AddRecoveryWindow("11:00", "22:00", 3,  nil, false, 21)

-- Set folder of airboss sound files within miz file.
AirbossStennis:SetSoundfilesFolder("Airboss Soundfiles/")

-- Single carrier menu optimization.
AirbossStennis:SetMenuSingleCarrier()

-- Skipper menu.
AirbossStennis:SetMenuRecovery(30, 20, false)

-- Remove landed AI planes from flight deck.
AirbossStennis:SetDespawnOnEngineShutdown()

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


-- 2. RANGE, LOFT & JTAC
local RangeZoneME = ZONE:FindByName("Range_Zone")
if RangeZoneME then
    local RazorRange = RANGE:New("Razor Training Range")
    RazorRange:SetRangeZone(RangeZoneME)
    -- FIX: Fehlende Anführungszeichen korrigiert
    RazorRange:AddBombingTargets({"Bomb_Target_1", "Bomb_Target_2", "Target_LOFT_1", "Target_LOFT_2", "Target_LOFT_3"})
    RazorRange:AddStrafePit("Strafe_Pit_1", 3000, 300, nil, true, nil, 0) 
    RazorRange:AddStrafePit("Strafe_Pit_2", 3000, 300, nil, true, nil, 0)
    RazorRange:SetInstructorRadio(305)
    RazorRange:SetSoundfilesPath("Range Soundfiles/")
    RazorRange:Start()
else
    env.warning("AUDIT: Range_Zone not found in ME!")
end

local ZoneLOFT = ZONE:FindByName("Zone_LOFT_IP")
if ZoneLOFT then
    ZoneLOFT:DrawZone(1, {1, 0, 0}, 1, {1, 0, 0}, 0.2)
    MARKER:New(ZoneLOFT:GetCoordinate(), "IP: START LOFT ATTACK"):ToAll()
end

-- 3. RAT (Stabil)
SafeCall("RAT", function()
    RAT:New("RAT_Transport_1"):SetDeparture({"Kobuleti", "Batumi"}):Spawn(3)
    RAT:New("RAT_Carrier_Hornet"):SetTakeoff("Air"):Spawn(2)
end)

-- 4. JTAC (100% NATIVE DCS API - PARAMETER FIXED)
SafeCall("NATIVE_JTAC", function()
    -- Roter Konvoi Spawn
    if GROUP:FindByName("Convoy_Red_Template") then
        SPAWN:New("Convoy_Red_Template"):InitLimit(1, 20):SpawnScheduled(60, 0.2)
    end
    
    -- Native DCS Einheiten-Abfrage
    local jtacUnit = Unit.getByName("JTAC_Unit")
    local targetUnit = Unit.getByName("Bomb_Target_1")
    
    if jtacUnit and targetUnit then
        if jtacUnit:isExist() and targetUnit:isExist() then
            local targetPos = targetUnit:getPoint()
            
            -- FIX: 4. Parameter (1688) direkt in createLaser hinzugefügt
            -- Signatur: createLaser(source, offset, target, laserCode)
            local laser = Spot.createLaser(jtacUnit, {x = 0, y = 2, z = 0}, targetPos, 1688)
            
            if laser then
                env.info("AUDIT: Native DCS Laser (1688) successfully placed on Bomb_Target_1.")
            end
        else
            env.info("AUDIT: JTAC or Target units exist in ME but are not yet spawned/active.")
        end
    else
        env.info("AUDIT: JTAC_Unit or Bomb_Target_1 not found in Mission Editor.")
    end
end)

-- 5. SUPPORT (CTLD & CSAR)
SafeCall("SUPPORT_CORE", function()
    -- Tasker/Chief bleibt deaktiviert wegen internem Moose 2.8.1 Bug.
    if _G["CTLD"] then
        CTLD:New(coalition.side.BLUE, {"Helo_1", "Helo_2"}, "Blue_CTLD"):Start()
    elseif _G["ctld"] then
        ctld:new(coalition.side.BLUE, {"Helo_1", "Helo_2"}, "Blue_CTLD"):start()
    end
    
    if _G["CSAR"] then
        CSAR:New(coalition.side.BLUE, "CSAR Support"):Start()
    end
end)

env.info('AUDIT: MISSION LOADED - V18 FINAL.')