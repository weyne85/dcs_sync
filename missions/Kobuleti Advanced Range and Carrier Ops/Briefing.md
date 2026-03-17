# MISSION OVERVIEW

- **Szenario**: "Kaukasus Combined Training" – Hochmoderne Trainingsumgebung für Trägerdeck-Qualifikation, Bodenangriffe (speziell F-4E LOFT) und Helikopter-Logistik.

- **Ziele**: Zertifizierung Case I-III, Punktgenaues Bombardement auf der Kobuleti-Range, Heli-Slingload-Training.

- **Siegbedingungen**: Keine (Sandbox-Training), Feedback erfolgt durch Range Control und Airboss.

- **Spieler-Slots**: 4x F-4E Phantom II, 2x F/A-18C, 2x CH-47F/UH-1H.

# MISSION EDITOR SETUP (Statische Elemente)

- **Karte**: Kaukasus | Zeit: 08:00 Uhr | Wetter: Klar (Standard).

- **Trägergruppe (CSG**):

    - Einheit: CVN-73 George Washington – UNIT NAME zwingend: CVN_Carrier.

    - Frequenz: 127.500 AM, TACAN: 73X, ICLS: 1.

- **Functional Range (Kobuleti)**:

    - **Trigger-Zone**: Erstelle eine Zone namens Range_Zone über dem Runway-Kreuz (Radius ca. 1000m).

    - **Ziele**: Platziere zwei statische Objekte (LKWs/Panzer) auf dem Kreuz. UNIT NAMEN: Target_1 und Target_2.

    - **Range Control**: Platziere einen Humvee abseits der Runway. UNIT NAME: Range_Control_Unit.

- **F-4E LOFT Setup**:

    - **Trigger-Zone**: Erstelle eine Zone namens IP_Loft ca. 10 NM südwestlich der Range (Anflugvektor 045°).

- **RAT (Ziviler Verkehr)**:

    - Erstelle eine Gruppe (z.B. Yak-40) an einem beliebigen Airport.

    - Setze den Haken bei "Late Activation" (Späte Aktivierung).

    - **GROUP NAME**: RAT_Template.

- **Helikopter (CTLD)**:

    - Platziere Slots für UH-1H, Mi-8 oder CH-47F. Sorge für Crates/Container in der Nähe der Startposition.

- **C-130J Training**:
    - **CARP_Zone**: Radius 0.27 NM nördlich von Kobuleti. Zentrum: Statisches Object **CARP_Target**
    - **LZ_C130**: Zone über der Landezone (Piste oder Freifläche)

# REQUIRED DOWNLOADS & SCRIPTS FOLDER

- **Frameworks**: Lade die aktuellsten Versionen von MOOSE.lua und MIST.lua herunter.

- **Sounds**: Deine .miz Datei muss die Soundordner Airboss Soundfiles/ und Range Soundfiles/ im internen Dateisystem (Zip-Struktur der .miz) enthalten.

# LOADING TRIGGERS (Im ME hinzufügen)

## MISSION START -> NO CONDITION -> DO SCRIPT FILE (mist.lua)

## MISSION START -> NO CONDITION -> DO SCRIPT FILE (Moose.lua)

## ONCE -> TIME MORE (5) -> DO SCRIPT FILE (mission.lua)

# MAIN MISSION SCRIPT (mission.lua)
~~~lua
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
~~~

# MISSION BRIEFING & DESCRIPTION
## Kobuleti Range Ops
- Range Control Frequenz: **251.000 AM**
- Die Range bietet voller Trefferauswertung für Bombing & Strafing
- Nutzen sie das F10-Funkmenü, um Berichte abzurufen oder Rauchmarkierungen anzufordern

## F-4E LOFT Training
- Anflug auf Kobuleti aus Südwest. Bei Erreichen des **IP Loft** erhalten sie eine Bestätigung
- Standart-Profil: 4nm vor dem Ziel hochziehen

## C-130J Spezial:
- **CARP**: Abwurf innerhalb der **0.27 NM** CARP-Zone
- **LZ**: Landung in der LZ-Zone. Wertung basiert auf der Distanz zum Zentrum (Exzellent < 0.027 NM)

## Carrier Ops (CVN-73)
- Frequenz: **127.500 AM** (LSO)
- **Manuelle Wahl**: Über das F10-Menü ("Träger-Operationen") können sie Case I, II oder III für den Rest des Trägers erzwingen.

## Heli Logistics:
- Nutzen sie das CTLD-Menü für Truppentransport und Slingload-Operationen


# Testing & Deployments
- **Wichtig**: Wenn die F4-Meldung nicht erscheint, stelle sicher, dass die Pilot-Slots im ME tatsächlich mit "F-4E" beginnen
- **Fehlersuche**: Sollte die Range stumm bleiben, prüfe, ob die **Range_Control_Unit** wirklich existiert und nicht zerstört wurde.
- Überprüfe die Zonenradien im Mission Editor: **Range_Zone** (1000m ~ 0.54 NM), **CARP_Zone** (500m ~ 0.27 NM)
- **Log**: Überprüfe die **dcs.log** nach dem Start. Dort muss am Ende stehen: **Mission Script Fix: Audited and battle-ready!**