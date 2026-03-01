-- ==========================================================
-- DCS MISSION ARCHITECT - FINAL COMPATIBILITY REWRITE
-- AUDITED BY: GEMINI SCRIPT FIXING PRIME
-- ==========================================================

env.info("MISSION STARTING: FINAL RANGE & AIRBOSS ALIGNMENT")

-- 1. AIRBOSS SETUP
local airbossStennis = AIRBOSS:New("Carrier_Group_Blue")
airbossStennis:SetSoundfilesFolder("Airboss Soundfiles/")
--airbossStennis:SetVoiceLSO(true)
--airbossStennis:SetVoiceMarshal(true)
airbossStennis:SetMarshalRadio(264)
airbossStennis:SetLSORadio(265)
airbossStennis:SetTACAN(74, "X", "TDR")
airbossStennis:SetICLS(11)
_SETTINGS:SetPlayerMenuOff()

-- S-3B Recovery Tanker spawning in air.
local tanker=RECOVERYTANKER:New("Carrier_Group_Blue", "Template_Tanker")
tanker:SetTakeoffAir()
tanker:SetRadio(250)
tanker:SetModex(511)
tanker:SetTACAN(1, "TKR")
tanker:__Start(1)

-- E-2D AWACS spawning on Stennis.
local awacs=RECOVERYTANKER:New("Carrier_Group_Blue", "Template_AWACS")
awacs:SetAWACS()
awacs:SetRadio(260)
awacs:SetAltitude(20000)
awacs:SetCallsign(CALLSIGN.AWACS.Wizard)
awacs:SetRacetrackDistances(30, 15)
awacs:SetModex(611)
awacs:SetTACAN(2, "WIZ")
awacs:__Start(1)

-- Rescue Helo with home base Lake Erie. Has to be a global object!
local rescuehelo=RESCUEHELO:New("Carrier_Group_Blue", "Template_RescueHelo")
rescuehelo:SetHomeBase(AIRBASE:FindByName("Lake Erie"))
rescuehelo:SetModex(42)
rescuehelo:__Start(1)





airbossStennis:Start()

-- 2. RANGE ALPHA SETUP
RangeAlpha = RANGE:New("Range Alpha")
RangeAlpha:SetSoundfilesPath("Range Soundfiles/")
RangeAlpha:SetRangeControl(266)
RangeAlpha:SetInstructorRadio(267)

local bombtargets={"RANGE_Targets_Red", "RANGE_Targets_Red-1", "RANGE_Targets_Red-2"}

local strafepit={"RANGE_Strafe_Target"}
RangeAlpha:AddStrafePit(strafepit, 3000, 300, nil, true, 30, 500)

RangeAlpha:AddBombingTargets(bombtargets, 50)

--RangeAlpha:SetPlayerSmoke(true)
--RangeAlpha:SetMessageDisplay(true)
RangeAlpha:Start()

-- 3. ASSETS & SPAWNS
-- Note: AddRecoveryTanker and AddAWACS handle the .Spawn() internally.
--local TankerSpawn = SPAWN:New("Template_Tanker")
--airbossStennis:AddRecoveryTanker(TankerSpawn, 6000, 260, 75, "TKR")

--local AwacsSpawn = SPAWN:New("Template_AWACS")
--airbossStennis:AddAWACS(AwacsSpawn, 25000, 350, 76, "AWACS")

-- Fixed Chaining Syntax for Target Spawning
local RangeSpawn = SPAWN:New("RANGE_Targets_Red")
    :InitLimit(10, 0)
    :SpawnScheduled(30, 0.1)

-- 4. RAT & CTLD
local ratCivilian = RAT:New("RAT_Civilian")
ratCivilian:SetDeparture({"Poti", "Batumi", "Senaki-Kolkhi"})
ratCivilian:SetDestination({"Kutaisi", "Kobuleti", "Sukhumi-Babushara"}) -- Corrected Spelling
ratCivilian:SetSpawnQuantity(5)
ratCivilian:ContinueJourney()
ratCivilian:Spawn()

local my_ctld = OPS_CTLD:New(coalition.side.BLUE, {"CTLD_Pickup_Senaki"}, "Logistics")
my_ctld:SetUseParaDroppedTroops(true):Start()

-- 5. EVENT HANDLER
local Handler = EVENTHANDLER:New():HandleEvent(EVENTS.PlayerEnterUnit)
function Handler:OnEventPlayerEnterUnit(EventData)
    if EventData.IniGroup then
        -- Use a small delay to ensure the UI is ready to display the message
        SCHEDULER:New(nil, function()
            MESSAGE:New("Range Alpha is ACTIVE. Check F10 menu for status.", 10):ToGroup(EventData.IniGroup)
        end, {}, 1)
    end
end

env.info("Mission Logic: All systems synchronized for MOOSE 2.8.1.")