------------------------------------------------
-- ATIS for Kandahar
-- Dec 2024
-- Using new soundfiles from FunkyFranky
------------------------------------------------

BASE:TraceOn()
BASE:TraceClass("ATIS")

local atisKandahar=ATIS:New(AIRBASE.Afghanistan.Kandahar, 143.4, radio.modulation.AM)
atisKandahar:SetRadioRelayUnitName("Radio Relay Kandahar" )
atisKandahar:SetImperialUnits()
atisKandahar:SetTACAN(75)
atisKandahar:SetTowerFrequencies({360.200,119.50})
atisKandahar:ReportQNHOnly()
atisKandahar:ReportZuluTimeOnly() 
atisKandahar:MarkRunways(true)
atisKandahar:Start()