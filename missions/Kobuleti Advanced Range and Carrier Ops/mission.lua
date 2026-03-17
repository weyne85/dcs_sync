-- ==========================================================
-- MISSION: ADVANCED TRAINING (AIRBOSS, RANGE, LOFT, CARP, LZ)
-- ==========================================================

-- 1. AIRBOSS & CARRIER OPS
local AirbossCVN73 = AIRBOSS:New("CVN_Carrier")
AirbossCVN73:SetTACAN(73, "X", "GWA")
AirbossCVN73:SetICLS(1, "GWA")
AirbossCVN73:SetLSORadio(127.5)
AirbossCVN73:SetMarshalRadio(305.0)
AirbossCVN73:SetSoundfilesFolder("Airboss Soundfiles/")
AirbossCVN73:SetMenuRecovery(true)
AirbossCVN73:Start()

local MenuCarrier = MENU_COALITION:New(coalition.side.BLUE, "Träger-Operationen")

local function SetManualCase(caseNum)
    -- Startet ein Recovery Fenster für den Rest des Tages
    AirbossCVN73:AddRecoveryWindow("00:01", "23:59", caseNum, 0, true)
    MESSAGE:New("AIRBOSS: Case " .. caseNum .. " aktiv!", 10):ToBlue()
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Case I setzen", MenuCarrier, SetManualCase, 1)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Case II setzen", MenuCarrier, SetManualCase, 2)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Case III setzen", MenuCarrier, SetManualCase, 3)

-- 2. FUNCTIONAL RANGE (KOBULETI)
local KobuletiRange = RANGE:New("Kobuleti Range")
KobuletiRange:SetRangeZone(ZONE:New("Range_Zone"))
KobuletiRange:SetRangeControl("Range_Control_Unit")
KobuletiRange:SetMenuRange(true)
KobuletiRange:SetDefaultPlayerMessages(true)
KobuletiRange:SetSoundfilesFolder("Range Soundfiles/")
KobuletiRange:SetRangeControlRadio(251.0)
-- RANGE verlangt Meter. 15.24m = 50ft.
KobuletiRange:AddBombingTargets({"Target_1", "Target_2"}, 15.24) 
KobuletiRange:Start()

-- 3. F-4E LOFT TRAINING
local IP_Zone = ZONE:New("IP_Loft")
local F4Units = SET_UNIT:New():FilterPrefixes("F-4E"):FilterActive():FilterStart()

SCHEDULER:New(nil, function()
    F4Units:ForEachUnit(function(Unit)
        if Unit:IsAlive() and Unit:IsInZone(IP_Zone) then
            -- Variable-Check um Spam zu vermeiden
            if not Unit:GetVariable("IP_Reached") then
                MESSAGE:New("IP LOFT ERREICHT. Kurs 045, 10.0 NM bis Target. Ready for Pull-up!", 10):ToUnit(Unit)
                Unit:SetVariable("IP_Reached", true)
            end
        else
            Unit:SetVariable("IP_Reached", nil) -- Reset wenn Zone verlassen
        end
    end)
end, {}, 1, 2)

-- 4. C-130J CARP & LZ EVALUATION
local CarpRange = RANGE:New("CARP Training")
CarpRange:SetRangeZone(ZONE:New("CARP_Zone"))
CarpRange:AddBombingTargets({"CARP_Target"}, 30.48) -- 100ft
CarpRange:Start()

local LZ_Zone = ZONE:New("LZ_C130")
local C130Units = SET_UNIT:New():FilterPrefixes("C-130J"):FilterActive():FilterStart()

SCHEDULER:New(nil, function()
    C130Units:ForEachUnit(function(Unit)
        -- Bedingung: Am Boden, in der Zone, Geschwindigkeit unter 20kt
        if Unit:IsAlive() and not Unit:InAir() and Unit:IsInZone(LZ_Zone) then
            if not Unit:GetVariable("Landed_LZ") and Unit:GetVelocityKNOTS() < 20 then
                
                -- Distanz zum Zentrum der LZ Zone berechnen
                local Dist_m = Unit:GetCoordinate():Get2DDistance(LZ_Zone:GetCoordinate())
                local Dist_NM = Dist_m / 1852
                
                local Rating = "AUSREICHEND"
                if Dist_NM < 0.027 then -- unter 50m
                    Rating = "EXZELLENT" 
                elseif Dist_NM < 0.081 then -- unter 150m
                    Rating = "GUT" 
                end
                
                MESSAGE:New(string.format("C-130 LZ LANDUNG!\nPilot: %s\nPräzision: %.3f NM (%.0f m)\nBewertung: %s", 
                            Unit:GetPlayerName() or "AI", Dist_NM, Dist_m, Rating), 15):ToAll()
                
                Unit:SetVariable("Landed_LZ", true)
            end
        elseif Unit:InAir() then
            -- Reset sobald das Flugzeug wieder abhebt
            Unit:SetVariable("Landed_LZ", nil)
        end
    end)
end, {}, 1, 3) -- Etwas schnellerer Check (3s) für Landungen

-- 5. RAT & CTLD
local ZivilerVerkehr = RAT:New("RAT_Template"):SetSpawnInterval(600):Spawn(3)
local BlueCTLD = CTLD:New(coalition.side.BLUE, {"UH-1H", "Mi-8", "CH-47F"}, "CTLD_Blue")
BlueCTLD:SetInternalCargo(true)
BlueCTLD:SetSlingLoad(true)

env.info('Mission Script: Audited and battle-ready!')