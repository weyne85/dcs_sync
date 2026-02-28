-------------------------------------------------------------------------
-- LoadSave 100 - Basics
-------------------------------------------------------------------------
-- Documentation
-- 
-- https://flightcontrol-master.github.io/MOOSE_DOCS_DEVELOP/Documentation/Utilities.Utils.html##(UTILS).LoadSetOfGroups and below
-- https://flightcontrol-master.github.io/MOOSE_DOCS_DEVELOP/Documentation/Utilities.Utils.html##(UTILS).SaveSetOfGroups and below
-- 
-------------------------------------------------------------------------
-- Join the game master slot. The group and static positions are saved.
-- Some units are destroyed after 30 seconds. Then, re-run the mission to 
-- see the effect of the reload.
-- Adjust the below Filepath to your file path. Mission Scripting 
-- environment must be(!) desanitized!
-------------------------------------------------------------------------
-- Date: December 2022
-------------------------------------------------------------------------

-- We create a SET_GROUP (SAMs) and a SET_STATIC (Bunkers) for saving
local RedSAMSet = SET_GROUP:New():FilterCategoryGround():FilterCoalitions("red"):FilterPrefixes({"Red SAM"}):FilterOnce()
local RedStaticSet = SET_STATIC:New():FilterCoalitions("red"):FilterPrefixes({"Red"}):FilterOnce()
-- We need the name list for the "StationaryList" methods
local RedSAMNames = RedSAMSet:GetSetNames()
local RedStaticNames = RedStaticSet:GetSetNames()

-- adjust to your PC
local Filepath = "C:\\Users\\post\\Saved Games\\DCS\\Missions\\SaveLoadTest\\"

local Filename = "RedGround.csv"
local SetFilename = "SetRedGround.csv"
local FilenameRandoms = "RedRandoms.csv"
local FilenameStatics = "RedStatics.csv"
local Saveinterval = 30

-- Save SAMs with SaveStationaryListOfGroups
function SaveRedSAM(list,Path,Fname)
  if UTILS.SaveStationaryListOfGroups(list,Path,Fname,true) then
    BASE:I("***** Red Ground positions saved successfully!")
  else
   BASE:I("***** Error saving Red Ground positions!")
  end
end

local TimerSaveRedSAM = TIMER:New(SaveRedSAM,RedSAMNames,Filepath,Filename)
TimerSaveRedSAM:Start(15,Saveinterval)

-- Save SAMs with SaveSetOfGroups
function SaveRedSAMSet(set,Path,Fname)
  if UTILS.SaveSetOfGroups(set,Path,Fname,true) then
    BASE:I("***** Red Ground positions [SET] saved successfully!")
  else
   BASE:I("***** Error saving Red Ground positions [SET]!")
  end
end

local TimerSaveRedSAM = TIMER:New(SaveRedSAMSet,RedSAMSet,Filepath,SetFilename)
TimerSaveRedSAM:Start(16,Saveinterval)

-- Reload SAMs with LoadStationaryListOfGroups
function LoadRedSAM(Path,Fname)
  if UTILS.LoadStationaryListOfGroups(Path,Fname,true,true,true,5) then
    BASE:I("***** Red Ground positions loaded successfully!")
  else
   BASE:I("***** Error loading Red Ground positions!")
  end
end

local TimerLoadRedSAM = TIMER:New(LoadRedSAM,Filepath,Filename)
TimerLoadRedSAM:Start(10)

-- Reload SAMs with LoadSetOfGroups
-- This is intended for groups which are spawned *during* the mission, i.e. the templates need to be set to late activated
-- Left as example here, but not used in the demo 
function LoadRedSAMSet(Path,Fname)
  if UTILS.LoadSetOfGroups(Path,Fname,true,true,true,2,0.6) then
    BASE:I("***** Red Ground positions loaded successfully!")
  else
   BASE:I("***** Error loading Red Ground positions!")
  end
end

-- Save Red Statics with SaveStationaryListOfStatics
function SaveRedStatics(list,Path,Fname)
  if UTILS.SaveStationaryListOfStatics(list,Path,Fname) then
    BASE:I("***** Red Static positions saved successfully!")
  else
   BASE:I("***** Error saving Red Ground positions!")
  end
end

local TimerSaveRedStatics = TIMER:New(SaveRedStatics,RedStaticNames,Filepath,FilenameStatics)
TimerSaveRedStatics:Start(17,Saveinterval)

-- Reload Red Statics with LoadStationaryListOfStatics
function LoadRedStatics(Path,Fname)
  if UTILS.LoadStationaryListOfStatics(Path,Fname,true,true,true,6,0.75) then
    BASE:I("***** Red Static positions loaded successfully!")
  else
   BASE:I("***** Error loading Red Ground positions!")
  end
end

local TimerLoadRedStatics = TIMER:New(LoadRedStatics,Filepath,FilenameStatics)
TimerLoadRedStatics:Start(11)

-- Destroy some units so we see the effect of the reload later
function Destruction()
  local bunker = STATIC:FindByName("Red Bunker-3-1")
  local bcoord = bunker:GetCoordinate()
  if bcoord then
    bcoord:Explosion(1000)
  end
  local radar1 = UNIT:FindByName("Red SAM SA-10-2")
  local radar2 = UNIT:FindByName("Red SAM SA-10-1")
  if radar1 and radar2 then
    local rcoord1 = radar1:GetCoordinate()
    local rcoord2 = radar2:GetCoordinate()
    if rcoord1 and rcoord2 then
      rcoord1:Explosion(100)
      rcoord2:Explosion(100)
    end
  end
end

local DestructionTimer = TIMER:New(Destruction)
DestructionTimer:Start(30)