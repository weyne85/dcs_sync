-- ==========================================================
-- DCS MISSION ARCHITECT - FINAL COMPATIBILITY REWRITE
-- AUDITED BY: GEMINI SCRIPT FIXING PRIME
-- ==========================================================

env.info("MISSION STARTING: FINAL RANGE & AIRBOSS ALIGNMENT")

-- 1. AIRBOSS SETUP
-- Ensure "Carrier_Group_Blue" is the NAME of the Group in ME
local airbossStennis = AIRBOSS:New("Carrier_Group_Blue")
airbossStennis:SetSoundfilesFolder("Airboss Soundfiles/")
--airbossStennis:SetVoiceLSO(true)      
--airbossStennis:SetVoiceMarshal(true)  
airbossStennis:SetMarshalRadio(264)
airbossStennis:SetLSORadio(265)
airbossStennis:SetTACAN(74, "X", "TDR")
airbossStennis:SetICLS(11)
airbossStennis:Start()

-- 2. RANGE ALPHA SETUP
-- Ensure "Range Alpha" is a ZONE name in ME
RangeAlpha = RANGE:New("Range Alpha")
RangeAlpha:SetSoundfilesPath("Range Soundfiles/")
RangeAlpha:SetRangeControl(266)
RangeAlpha:SetInstructorRadio(267)

-- FIXED: AddTarget() ensures these units are counted for the Range Scoreboard [cite: 5, 16, 77]
RangeAlpha:AddTarget({ "RANGE_Targets_Red", "RANGE_Targets_Red-1", "RANGE_Targets_Red-2" })

-- FIXED: Realigned Strafe Pit parameters for MOOSE 2.9 compatibility
-- Format: AddStrafePit(TargetName, MaxDistance, Heading, PitLength, PitWidth) 
RangeAlpha:AddStrafePit("RANGE_Strafe_Target", 3000, 270, 50, 500)

--RangeAlpha:SetPlayerSmoke(true)
--RangeAlpha:SetMessageDisplay(true)
RangeAlpha:Start()

-- 3. ASSETS & SPAWNS
-- AIRBOSS handles the .Spawn() call automatically for these assets [cite: 70, 77]
local TankerSpawn = SPAWN:New("Template_Tanker")
airbossStennis:AddRecoveryTanker(TankerSpawn, 6000, 260, 75, "TKR")

local AwacsSpawn = SPAWN:New("Template_AWACS")
airbossStennis:AddAWACS(AwacsSpawn, 25000, 350, 76, "AWACS")

-- Fixed Chaining: Spawns targets every 30 seconds, up to 10 alive at once [cite: 32, 42]
local RangeSpawn = SPAWN:New("RANGE_Targets_Red")
    :InitLimit(10, 0)
    :SpawnScheduled(30, 0.1)

-- 4. RAT (Random Air Traffic)
-- Ensure these Airbase names match the map theatre 
local ratCivilian = RAT:New("RAT_Civilian")
ratCivilian:SetDeparture({"Poti", "Batumi", "Senaki-Kolkhi"})
ratCivilian:SetDestination({"Kutaisi", "Kobuleti", "Sukhumi-Babushara"}) 
ratCivilian:SetSpawnQuantity(5)
ratCivilian:ContinueJourney()
ratCivilian:Spawn()

-- 5. CTLD SETUP
-- Requires a "Logistics" group/template to exist for troop visuals [cite: 16, 30]
local my_ctld = OPS_CTLD:New(coalition.side.BLUE, {"CTLD_Pickup_Senaki"}, "Logistics")
my_ctld:SetUseParaDroppedTroops(true)
my_ctld:Start()

-- 6. EVENT HANDLER
local Handler = EVENTHANDLER:New():HandleEvent(EVENTS.PlayerEnterUnit)
function Handler:OnEventPlayerEnterUnit(EventData)
    -- Safety check: Ensure the unit and group exist [cite: 35, 43, 804]
    if EventData.IniUnit and EventData.IniGroup then
        SCHEDULER:New(nil, function()
            MESSAGE:New("Range Alpha is ACTIVE. Check F10 menu for status.", 10):ToGroup(EventData.IniGroup)
        end, {}, 1)
    end
end

env.info("Mission Logic: All systems synchronized for MOOSE 2.9+.")