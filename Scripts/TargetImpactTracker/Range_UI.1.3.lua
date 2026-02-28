UI  = {}
UI.Version = '1.3.03'

--###################################################################################################################################################
-- #############	DCS - Range Control	User Interface for Target Impact Tracker Script 2.0											################# 
-- #############	by Draken35																										################# 
--###################################################################################################################################################
--[[ Requirements:	
		>>>	 MIST 4.5.107 or above <https://github.com/mrSkortch/MissionScriptingTools/tree/master>
		>>>  TITS 2.3.00 or above
--]]
-----------------------------------------------------------------------------------------------------------------------------------------------------
--[[ Version history
	1.0.00		04/06/2022	Development starts
	1.0.01		05/03/2022	First release
	1.0.02		05/08/2022	-fixed Apache automatic coordinates system detection
	1.1.00		05/10/2022	- Uses TITS 2.1.x results API to report results instead of raw data tables
	1.1.01		05/11/2022	- Fixed issue with popup script and new result reports		
							- replaced UI.MaxWFindRPT by I.MinWFgrpRPT
	1.1.02		05/12/2022	- Added optional abort message when shooting before starting a pass
	1.1.10		05/14/2022	- No mark designation will display the UI.Text1,UI.Text2 and UI.Text3, so they can be used to give a talk-on for the target.
							- Coordinates are now optional in the No-mark and laser/IR designation designation. Toggle option in designation menu
	1.2.00		05/15/2022	- Reorganization of Setting Menu							
							- Added optional Auto Pass Start and End
	1.2.01		05/18/2022	- Attack Radial added to designation
							- Added release heading to reports
							- Added reports based on designated target
							- Fixed and readded Pass BDA report
	1.2.02		05/25/2022	- Fixed call to designated/grouped report from menu
	1.2.03		07/10/2022	- Range comms improved for MP games
							- display on coordenates in 3 systems at the same time
	1.2.04		07/22/2022	- Fixed a crash in IR designation
	1.3.00		07/27/2022  - Added support for roll-in position tracking 
							- Added illumination zones
	1.3.01		07/30/2022	- Added talk-on fields to the laser/IR designation
	1.3.02		08/04/2022	- improved initialization of Auto pass start and end
	1.3.03		09/11/2022	- Lest we forget! 
	                        - Fixed issue with strafing reporting in missions with unlimited weapons.
							  A limitation is that it will only report passed with hits on target and it cannot report rate of hits.\
							- Fixed issue with automatic range clearance trigger for AI units spawned inside the zones  
							  
--]]
-----------------------------------------------------------------------------------------------------------------------------------------------------
--[[ Pass Data return tables
			Tables:
			shellsFired[ShellType] = {
											init = Shell Count at pass start
										, 	fired = Shells fired during the pass
									}
			shellHits 			-- per target per shell type
				shellHits[Target][ShellType] = Shell Hits Count
				
			weaponsFired		-- and their release params & designated target at the time, updated by shot event if TITS.onPass[_unitName] == true
				weaponsFired[WeaponID] = {
												weaponType
											,	releasePitch
											,	releaseYaw
											,	releaseRoll
											,	releaseHeading
											,	releaseSpeed
											,	releasePosition
											,	timeStamp
											, 	inFlight 
										}
			
			weaponHits			-- per target per weapon , updated by hit event if TITS.onPass[_unitName] == true
				weaponHits[WeaponID][Target] = 	timeStamp				
						
			
			impactData		-- per target per weapon 
				impactData[WeaponID][Target] = {
													targetPos
												,	impactPos	
												,	impactDistance
												,	timeStamp
											}
							
			
			targetHealth		-- per target. Health at the start and end of the pass
				targetHealth[Target] =	{
											start_health 
										,	end_health 
										}
				

--]]
--[[ Target List table
		TargetList[name] = {
				name					-- UNIQUE! Target name
			,	displayName				-- display name, accepts duplicates, if empty _TargetName will be used
			,	type					-- allowed values [ 'unit' | 'zone' | 'static' ] must be in lower case
			,	respawn					-- Only for units. if true, unit can be respawned. Respwan will only happen when ALL the units in the group are destroyed
			,	impact					-- use target to calculate distance to impact
			,	strafing				-- count strafing hits on target
			,	bda						-- reports splash damage from weapons
			,	des_zone				-- designation zone
			,	des_wp					-- Allow use of smoke designation for target
			,	des_laser				-- Allow use of laser designation for target
			,	des_ir					-- Allow use of IR designation for target
			,	des_nomark				-- Allow use of target designation with no marks (provides coordinates)
			,	list_coor				-- Allow list of target coordinates
			,	uiNum1					-- Numeric value for custom UI use
			,	uiNum2					-- Numeric value for custom UI use
			,	uiNum3					-- Numeric value for custom UI use
			,	uiBool1					-- Boolean value for custom UI use
			,	uiBool2					-- Boolean value for custom UI use
			,	uiBool3					-- Boolean value for custom UI use
			,	uiText1					-- Text value for custom UI use
			,	uiText2					-- Text value for custom UI use
			,	uiText3					-- Text value for custom UI use
					
				}

--]]


--###################################################################################################################################################
-- #############   Configuration section   																							################# 
--###################################################################################################################################################

UI.AutoPassStart				= false	
UI.AutoPassStartCoolDown		= 30	-- seconds
UI.AutoPassEndTimeOut			= 20 	-- seconds
UI.AutoPassEnd					= false -- If true, pass will automatically end if there aren't any weapons in the air and 
										-- UI.AutoPassEndTimeOut seconds had passed since the last shell was fired or weapon impact
										-- was recorded 

UI.MagneticVar					= 0		-- Magnetic variation for the map and date, used for designation attack radial calculation. East is +

UI.SpeedUnitsDefault			= 1    	-- 1 = Knots, 2 = Mph, 3 = Kph
UI.DistanceUnitsDefault			= 3    	-- 1 = feet, 2 = yards, 3 = meters
UI.AltitudeUnitsDefault			= 1    	-- 1 = feet, 3 = meters ( 2 is not used)
UI.CoordinateFormatDefault		= 2	   	-- 1 = MGRS, 2 = DMS, 3 = DM.mm
UI.DisplayReleaseDataDefault	= true	-- default for the option to display the release parameters in results
UI.DisplayAbortMsgDefault		= true -- if true, display abort message when shooting before starting a pass
UI.DisplayCoordsDefault			= true -- if true, display coordinates in designation messages
UI.desUseAttackRadialDefault	= false -- add an attack radial requiment if true	

UI.DefaultResultReport			= 0		-- 0 = Automatic
										-- 1 = Impact results (closest/individual)
										-- 2 = Impact results (closest/grouped)
										-- 3 = BDA Summary
										-- 4 = Impact results (designated/individual)
										
UI.MinWFgrpRPT					= 6		-- Minimun number of weapons fired in pass to display grouped report in automatic mode

UI.minWPmarkDist				= 50	-- meters. Minimum distance from target to mark using WP 
UI.maxWPmarkDist				= 150	-- meters. Maximum distance from target to mark using WP 


UI.AutoSetCoordinates			= true	-- if true use player's unit type to set coordinates, else use MPT.CoordinateFormatDefault	
UI.coordXtype = {}
UI.coordXtype['AV8BNA'] 		= 1	   	-- 1 = MGRS, 2 = DMS, 3 = DM.mm
UI.coordXtype['A-10C_2'] 		= 1	
UI.coordXtype['AH-64D_BLK_II'] 	= 1	
UI.coordXtype['F-16C_50'] 		= 3  
UI.coordXtype['FA-18C_hornet'] 	= 1	
UI.coordXtype['M-2000C'] 		= 3	

UI.messageBeep = '204521__redoper__roger-beep.ogg' -- Message alert sound. leave empty for no sound


--#################################################################################################################################################
-- #############   Initialization of globals   																						############### 
--#################################################################################################################################################

UI.unitConfig = {}
UI.menuAddedToGroup = {}
UI.debugMarkcenter = false
UI.DesignationZones = {}
UI.DesignationZones[1] = { id = 1, name = 'Default'}
UI.Designation = {
			Designator 	=	'' -- unit name
		,	Designated 	=	'' -- target name
		,	type		=	0 -- 0 = none, 1 = WP , 2 = laser, 3 = IR, 4 = No mark, 23 = laser/IR
		,	zone		= 1
		,	briefing = ''
		,	ray1 = nil
		,	ray2 = nil
		,	AttackRadial = 0
	}
UI.Designators = {}
UI.engagementZones = {}
UI.illuminationZones = {}
UI.illuminating = false

--#################################################################################################################################################
-- #############  UI code																											############### 
--#################################################################################################################################################
	UI.EventHandler = {}
function UI.EventHandler:onEvent(_eventDCS)

	if _eventDCS == nil or _eventDCS.initiator == nil then
		return true
	end

	local status, err = pcall(function(_event)

			if (_event.id == world.event.S_EVENT_BIRTH  or _event.id == world.event.S_EVENT_TAKEOFF 
			or  _event.id == world.event.S_EVENT_ENGINE_STARTUP) and _event.initiator:getPlayerName()  then  

				UI.initUnit(_event.initiator:getName())
		
			elseif ((_event.id == world.event.S_EVENT_SHOT) or (_event.id == world.event.S_EVENT_SHOOTING_START) ) and _event.initiator:getPlayerName()  then -- id == 1 Shot
				local _unitName = _event.initiator:getName()
				local cfg = UI.unitConfig[_unitName]
				if not TITS.onPass[_unitName]  and  cfg.abortMSG then
					UI.messageToUnit(_unitName,"Abort! You are not cleared to fired!",{},10)
				end
		
			end --_event.id ==
		  -- ### End event processing

			return true
	end, _eventDCS) --  local status, err = pcall(function(_event)

	if (not status) then 
		local msg = string.format("Target Impact Tracker UI (v%s): Error while handling event %s",UI.Version, err)
		env.error(msg,false)
	end
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.initUnit(unitName)
	local unit = Unit.getByName(unitName)
	local groupID = unit:getGroup():getID()

	local rConfig = {
				SpeedUOM	= UI.SpeedUnitsDefault	
			,	DistanceUOM = UI.DistanceUnitsDefault	
			,	AltitudeUOM	= UI.AltitudeUnitsDefault
			,	CoordFormat = UI.CoordinateFormatDefault
			, 	DisplayReleaseData = UI.DisplayReleaseDataDefault
			,	rootPath = nil
			,	rollInPath = nil
			,	offPath = nil
			, 	resultsRPT = UI.DefaultResultReport
			,	unitType = unit:getTypeName()
			, 	abortMSG = UI.DisplayAbortMsgDefault
			,	desDisplayCoords = UI.DisplayCoordsDefault	
			,	desUseAttackRadial = UI.desUseAttackRadialDefault	
			, 	lastPassEnd = timer.getTime()
			, 	firstPass = true
		}

	if UI.coordXtype[rConfig.unitType] and UI.AutoSetCoordinates	then
		rConfig.CoordFormat = UI.coordXtype[rConfig.unitType]
	end
		
		
	if UI.menuAddedToGroup[groupID]  == {} then
		UI.menuAddedToGroup[groupID]  = false
	end
	if not UI.menuAddedToGroup[groupID] then
		-- Add Menu
		rConfig.rootPath = missionCommands.addSubMenuForGroup(groupID, "Range")	-- Root level
		
		local _reportsPath = 	missionCommands.addSubMenuForGroup(groupID,"Reports", rConfig.rootPath)
								missionCommands.addCommandForGroup(groupID,"List coordinates"							, _reportsPath,  UI.rptListCoord				, unitName)
								missionCommands.addCommandForGroup(groupID,"Results (closest/individual)"				, _reportsPath,  UI.rptImpactResults			, unitName)
								missionCommands.addCommandForGroup(groupID,"Results (closest/grouped)"					, _reportsPath,  UI.rptImpactResultsGrouped		, unitName)
								missionCommands.addCommandForGroup(groupID,"Results (designated/individual)"			, _reportsPath,  UI.rptImpactResultsDes			, unitName)
								missionCommands.addCommandForGroup(groupID,"Results (designated/grouped)"				, _reportsPath,  UI.rptImpactResultsDesGrouped	, unitName)
								missionCommands.addCommandForGroup(groupID,"BDA Pass summary"							, _reportsPath,  UI.rptBDAsummary				, unitName)
								missionCommands.addCommandForGroup(groupID,"Weapons in flight"							, _reportsPath,  UI.rptWeaponsInFlight			, unitName)
								--missionCommands.addCommandForGroup(groupID,"Debug: Inspect Data"						, _reportsPath,  UI.debugPassData				, unitName)
		local _designationPath = missionCommands.addSubMenuForGroup(groupID, "Designation", rConfig.rootPath)	
									missionCommands.addCommandForGroup(groupID,"New smoke (WP) designation"		, _designationPath, UI.desWP		, {unitName, true}) 
									missionCommands.addCommandForGroup(groupID,"Repeat smoke (WP) mark"			, _designationPath, UI.desWP		, {unitName, false}) 
									missionCommands.addCommandForGroup(groupID,"New Laser designation"			, _designationPath, UI.desLaserIR	, {unitName,'laser'}) 
									missionCommands.addCommandForGroup(groupID,"New IR pointer designation"		, _designationPath, UI.desLaserIR	, {unitName,'IR'})
									missionCommands.addCommandForGroup(groupID,"New Laser/IR  designation"		, _designationPath, UI.desLaserIR	, {unitName,'laser/IR'})
									missionCommands.addCommandForGroup(groupID,"New No Mark designation"		, _designationPath, UI.desNM		, unitName)																		
									missionCommands.addCommandForGroup(groupID,"Cancel designation"				, _designationPath, UI.desCancel	, unitName) 	
									missionCommands.addCommandForGroup(groupID,"Repeat briefing"				, _designationPath, UI.desRPTBrief	, unitName) 	
		----------------------------------------------------------------------------------------
		local _settingsPath = missionCommands.addSubMenuForGroup(groupID, "Settings", rConfig.rootPath)
				missionCommands.addCommandForGroup(groupID,"Display current settings"				, _settingsPath, UI.Settings		, {unitName,0}) 
				missionCommands.addCommandForGroup(groupID,"Toggle illumination"					, _settingsPath, UI.Settings		, {unitName,70}) 				
				missionCommands.addCommandForGroup(groupID,"Respawn targets"						, _settingsPath, UI.Settings		, {unitName,66}) 	
				missionCommands.addCommandForGroup(groupID,"Toggle abort message"					, _settingsPath, UI.Settings		, {unitName,1}) 
				missionCommands.addCommandForGroup(groupID,"Toggle display of Release data"			, _settingsPath, UI.Settings		, {unitName,2}) 

		
			local _settings6Path = missionCommands.addSubMenuForGroup(groupID, "Designation", _settingsPath) 		
				local _designation1Path = missionCommands.addSubMenuForGroup(groupID, "Select designation zone", _settings6Path)	
					for _,z in pairs(UI.DesignationZones) do
						local n = string.format('%s', z.name)
						missionCommands.addCommandForGroup(groupID,n		, _designation1Path, UI.desSetZone		, {unitName,z.id}) 		
					end
				missionCommands.addCommandForGroup(groupID,"Toggle attack radial"			, _settings6Path, UI.Settings		, {unitName,31})
				missionCommands.addCommandForGroup(groupID,"Toggle coods. display"			, _settings6Path, UI.Settings		, {unitName,30})
			
			local _settings1Path = missionCommands.addSubMenuForGroup(groupID, "Distance units", _settingsPath) 
				missionCommands.addCommandForGroup(groupID,"Distance: set to meters"				, _settings1Path, UI.Settings		, {unitName,3}) 
				missionCommands.addCommandForGroup(groupID,"Distance: set to feet"					, _settings1Path, UI.Settings		, {unitName,4}) 
				missionCommands.addCommandForGroup(groupID,"Distance: set to yards"					, _settings1Path, UI.Settings		, {unitName,5}) 
			local _settings2Path = missionCommands.addSubMenuForGroup(groupID, "Altitude units", _settingsPath) 
				missionCommands.addCommandForGroup(groupID,"Altitude: set to meters"				, _settings2Path, UI.Settings		, {unitName,6}) 
				missionCommands.addCommandForGroup(groupID,"Altitude: set to feet"					, _settings2Path, UI.Settings		, {unitName,7}) 		
			local _settings3Path = missionCommands.addSubMenuForGroup(groupID, "Speed units", _settingsPath) 
				missionCommands.addCommandForGroup(groupID,"Speed: set to kph"						, _settings3Path, UI.Settings		, {unitName,8}) 
				missionCommands.addCommandForGroup(groupID,"Speed: set to knots"					, _settings3Path, UI.Settings		, {unitName,9}) 
				missionCommands.addCommandForGroup(groupID,"Speed: set to mph"						, _settings3Path, UI.Settings		, {unitName,10}) 	
			--local _settings4Path = missionCommands.addSubMenuForGroup(groupID, "Coordinates format", _settingsPath) 
			--	missionCommands.addCommandForGroup(groupID,"Coord. format set to MGRS"				, _settings4Path, UI.Settings		, {unitName,11}) 
			--	missionCommands.addCommandForGroup(groupID,"Coord. format set to DMS"				, _settings4Path, UI.Settings		, {unitName,12}) 
			--	missionCommands.addCommandForGroup(groupID,"Coord. format set to DM.mm"				, _settings4Path, UI.Settings		, {unitName,13}) 
			local _settings5Path = missionCommands.addSubMenuForGroup(groupID, "Results report", _settingsPath) 	
				missionCommands.addCommandForGroup(groupID,"Automatic selection"						, _settings5Path, UI.Settings		, {unitName,20}) 
				missionCommands.addCommandForGroup(groupID,"Impact results (individual)"				, _settings5Path, UI.Settings		, {unitName,21}) 
				missionCommands.addCommandForGroup(groupID,"Impact results (grouped)"					, _settings5Path, UI.Settings		, {unitName,22}) 
				missionCommands.addCommandForGroup(groupID,"BDA Pass summary"							, _settings5Path, UI.Settings		, {unitName,23}) 
		----------------------------------------------------------------------------------------
		rConfig.rollInPath = missionCommands.addCommandForGroup(groupID,"Rolling in"			, rConfig.rootPath , UI.passStartEnd, {unitName,'in'})
		UI.menuAddedToGroup[groupID] = true
		
		UI.unitConfig[unitName] = rConfig
	
		UI.Settings({unitName,0})
		
		if UI.AutoPassStart then
			-- launch pass end checker
			local params = {unitName = unitName}
			timer.scheduleFunction(UI.passStartCheck, params,  timer.getTime() +  1 ) 	
		end	
			
		if UI.AutoPassEnd then
			-- launch pass end checker
			local params = {unitName = unitName}
			timer.scheduleFunction(UI.passEndCheck, params,  timer.getTime() +  1 ) 	
		end
		
	end --if not UI.menuAddedToGroup[groupID] then
		
		


	return true
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.passStartCheck(params, time)
	if  not TITS.onPass[params.unitName] then
		if UI.rowCount(UI.engagementZones) > 0 then
			local inZone = false
			for z,t in pairs(UI.engagementZones) do
				local ut = mist.makeUnitTable({params.unitName})
				if t == 'zone' then
					local u = mist.getUnitsInZones(ut, {z},'cylinder')
					inZone = inZone or (UI.rowCount(u) > 0) 
				else
					local p = mist.getGroupPoints(z)
					local u = mist.getUnitsInPolygon(ut, p)
					inZone = inZone or (UI.rowCount(u) > 0) 				
				end		
			end -- for z,t in pairs(UI.engagementZones) do
			if inZone then
				local cfg = UI.unitConfig[params.unitName]
				if (timer.getTime() - cfg.lastPassEnd ) >= UI.AutoPassStartCoolDown  or  cfg.firstPass then	
					cfg.firstPass = false
					UI.passStartEnd({params.unitName, 'in'})
				end
			end	
		end --if UI.rowCount(UI.engagementZones) > 0 then
	end -- if  not TITS.onPass[params.unitName] then
	
	return timer.getTime() + 1
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.passEndCheck(params, time)
	if  TITS.onPass[params.unitName] then
		local passData = TITS.passGetData(params.unitName)
		local wf = TITS.getWeponsFired(params.unitName)
		local sf = TITS.getShellsFired(params.unitName)
		if wf.count > 0 or sf.total > 0 then
			if not TITS.weaponsInFlight(params.unitName) then
				local cTime =  timer.getTime()
				if (cTime - passData.lastShellFired) > UI.AutoPassEndTimeOut and
				   (cTime - passData.lastImpact) > UI.AutoPassEndTimeOut then
					UI.passStartEnd({params.unitName, 'off'})
				end -- if (cTime - passData.lastShellFired) > UI.AutoPassEndTimeOut and			
			end -- if not TITS.weaponsInFlight(params.unitName) then
		end -- if wf.count > 0 or sf.count > 0 then
	end -- if  TITS.onPass[params.unitName] then
	return timer.getTime() + 1
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.AddEngagementZone(_name, _type)

	UI.engagementZones[_name] = _type

end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.Settings(_args)
	local unitName = _args[1]
	local setting = _args[2]
	local cfg = UI.unitConfig[unitName]

	if setting ==  0 then -- Display settings
		local _msg  = ''
		
		_msg = string.format ('Flying: %s',cfg.unitType)
		
		if cfg.abortMSG then
			_msg = string.format ('%s\nAbort message is ON',_msg)
		else
			_msg = string.format ('%s\nAbort message is OFF',_msg)
		end
		
		if cfg.DisplayReleaseData then
			_msg = string.format ('%s\nRelease data display is ON',_msg)
		else
			_msg = string.format ('%s\nRelease data display is OFF',_msg)
		end	
		
		if cfg.DistanceUOM == 3 then -- Distance meters
			_msg = string.format ('%s\nDistance: Using meters',_msg)
		elseif cfg.DistanceUOM == 2 then --Distance  feet
			_msg = string.format ('%s\nDistance: Using feet',_msg)
		else -- Distance yards
			_msg = string.format ('%s\nDistance: Using yards',_msg)
		end 
		
		if cfg.AltitudeUOM == 3  then -- Altitude meters 
			_msg = string.format ('%s\nAltitude: Using meters',_msg)	
		else
			_msg = string.format ('%s\nAltitude: Using feet',_msg)	
		end
		
		if cfg.SpeedUOM == 3 then -- Speed kph
			_msg = string.format ('%s\nSpeed: Using kph',_msg)
		elseif cfg.SpeedUOM == 1  then -- Speed kt
			_msg = string.format ('%s\nSpeed: Using knots',_msg)
		else -- Speed mph
			_msg = string.format ('%s\nSpeed: Using mph',_msg)		
		end
		--[[
		if cfg.CoordFormat == 1  then -- Coordinate format MGRS	
			_msg = string.format ('%s\nCoordinate format: Using MGRS',_msg)
		elseif cfg.CoordFormat == 2 then -- Coordinate format DMS	
			_msg = string.format ('%s\nCoordinate format: Using DMS',_msg)	
		else -- Coordinate format DM.mm		
			_msg = string.format ('%s\nCoordinate format: Using DM.mm',_msg)			
		end 
		--]]
		if cfg.resultsRPT == 0  then
			_msg = string.format ('%s\nResults using Automatic selection',_msg)
		elseif cfg.resultsRPT == 1  then -- 
			_msg = string.format ('%s\nResults using Impact results (individual) report',_msg)
		elseif cfg.resultsRPT == 2 then 	
			_msg = string.format ('%s\nResults using Impact results (grouped) report',_msg)
		elseif cfg.resultsRPT == 3 then 	
			_msg = string.format ('%s\nResults using BDA Pass Summary report',_msg)			
		end 
	
		_msg = string.format ('%s\nDesignation zone: %s',_msg,UI.DesignationZones[UI.Designation.zone].name)
		
		if cfg.desDisplayCoords then
			_msg = string.format ('%s\nDisplay coordinates in designation msgs is ON',_msg)
		else
			_msg = string.format ('%s\nDisplay coordinates in designation msgs is OFF',_msg)
		end
	
		if cfg.desUseAttackRadial then
			_msg = string.format ('%s\nRequire attack radial in designation is ON',_msg)
		else
			_msg = string.format ('%s\nRequire attack radial in designation is OFF',_msg)
		end	
	
		UI.messageToUnit(unitName,_msg,{},10,false)
		
		
		
	elseif setting == 1 then -- Toggle display of Abort message 
		cfg.abortMSG  = not cfg.abortMSG  		
		if cfg.abortMSG  then
			UI.messageToUnit(unitName,'Abort message is ON',false)
		else
			UI.messageToUnit(unitName,'Abort message is OFF',false)
		end	
	
	elseif setting == 2 then -- Toggle display of Release data
		cfg.DisplayReleaseData = not cfg.DisplayReleaseData 		
		if cfg.DisplayReleaseData then
			UI.messageToUnit(unitName,'Release data display is ON',false)
		else
			UI.messageToUnit(unitName,'Release data display is OFF',false)
		end	
	-- Distancce
	elseif setting == 3 then -- Distance meters
		cfg.DistanceUOM = 3 -- 1 = feet, 2 = yards, 3 = meters
		UI.messageToUnit(unitName,'Distance: Using meters',false)
	elseif setting == 4 then --Distance  feet
		cfg.DistanceUOM = 1 -- 1 = feet, 2 = yards, 3 = meters
		UI.messageToUnit(unitName,'Distance: Using feet',false)
	elseif setting == 5 then -- Distance yards
		cfg.DistanceUOM = 2 --1 = feet, 2 = yards, 3 = meters
		UI.messageToUnit(unitName,'Distance: Using yards',false)
	-- Altitude
	elseif setting == 6 then -- Altitude meters 
		cfg.AltitudeUOM = 3 -- 1 = feet,  3 = meters
		UI.messageToUnit(unitName,'Altitude: Using meters',false)	
	elseif setting == 7 then -- Altitude feet 
		cfg.AltitudeUOM = 1 -- 1 = feet,  3 = meters
		UI.messageToUnit(unitName,'Altitude: Using feet',false)	
	-- Speed
	elseif setting == 8 then -- Speed kph
		cfg.SpeedUOM = 3 -- 1 = Knots, 2 = Mph, 3 = Kph	
		UI.messageToUnit(unitName,'Speed: Using kph',false)
	elseif setting == 9 then -- Speed kt
		cfg.SpeedUOM= 1 -- 1 = Knots, 2 = Mph, 3 = Kph	
		UI.messageToUnit(unitName,'Speed: Using knots',false)
	elseif setting == 10 then -- Speed mph
		cfg.SpeedUOM = 2 -- 1 = Knots, 2 = Mph, 3 = Kph	
		UI.messageToUnit(unitName,'Speed: Using mph',false)		
	-- Coordinate format
	--[[
	elseif setting == 11 then -- Coordinate format MGRS	
		cfg.CoordFormat = 1 -- 1 = MGRS, 2 = DMS, 3 = DM.mm	
		UI.messageToUnit(unitName,'Coordinate format: Using MGRS',false)
	elseif setting == 12 then -- Coordinate format DMS	
		cfg.CoordFormat = 2 -- 1 = MGRS, 2 = DMS, 3 = DM.mm	
		UI.messageToUnit(unitName,'Coordinate format: Using DMS',false)	
	elseif setting == 13 then -- Coordinate format DM.mm		
		cfg.CoordFormat = 3 -- 1 = MGRS, 2 = DMS, 3 = DM.mm	
		UI.messageToUnit(unitName,'Coordinate format: Using DM.mm',false)			
	--]]
	elseif setting == 20 then -- Results reports	
		cfg.resultsRPT = 0 
		UI.messageToUnit(unitName,'Results using Automatic selection',false)	
	elseif setting == 21 then -- Results reports	
		cfg.resultsRPT = 1 
		UI.messageToUnit(unitName,'Results using Impact results (individual) report',false)	
	elseif setting == 22 then -- Results reports	
		cfg.resultsRPT = 2 
		UI.messageToUnit(unitName,'Results using Impact results (grouped) report',false)	
	elseif setting == 23 then -- Results reports	
		cfg.resultsRPT = 3 
		UI.messageToUnit(unitName,'Results using BDA Pass Summary report',false)		
	elseif setting == 30 then -- Toggle coords display  in designation
		cfg.desDisplayCoords = not cfg.desDisplayCoords	
		if cfg.desDisplayCoords then
			UI.messageToUnit(unitName,'Display coordinates in designation msgs is ON',false)
		else
			UI.messageToUnit(unitName,'Display coordinates in designation msgs is OFF',false)
		end	
	elseif setting == 31 then -- Toggle coords display  in designation
		cfg.desUseAttackRadial = not cfg.desUseAttackRadial	
		if cfg.desUseAttackRadial then
			UI.messageToUnit(unitName,'Require attack radial in designation is ON',false)
		else
			UI.messageToUnit(unitName,'Require attack radial in designation is OFF',false)
		end	
	elseif setting == 66 then -- respawn test
		for u,_ in pairs(TITS.TargetList) do
			TITS.respawnTarget(u)
		end -- for u,v in pairs(TITS.TargetList) do
		
	elseif setting == 70 then -- toggle illumination
		UI.illuminating = not UI.illuminating
		if UI.illuminating then
			trigger.action.outText( 'Starting illumination', 10 )
			timer.scheduleFunction(UI.illuminate, {},  timer.getTime() +  1 ) 	
		else
			trigger.action.outText( 'Stoping illumination', 10 )
		end
	end -- main if		
		

	return true
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.messageToUnit(_unitName,_messageText,_soundTable,_displayTime,_displayToAll)
	--[[
	local msg = {} 
	msg.text = _messageText		
	msg.msgFor = {units = {_unitName}}
	
	if TITS.messageBeep ~= '' then
		msg.sound = TITS.messageBeep 
	end
	
	if _soundTable ~= nil then
		msg.multSound  = _soundTable
	end
	
	if _displayTime == nil then
		_displayTime = 5
	end 

	msg.displayTime = _displayTime
	
	mist.message.add(msg)
	--]]
 
	
 
	-- bypass mist because of message history spamming
	if _displayToAll == nil then
		_displayToAll = true
	end
	if _displayTime == nil then
		_displayTime = 5
	end 
	local _unit = Unit.getByName(_unitName)
	local _groupId = _unit:getGroup():getID()
	local _callSign = _unit:getCallsign()
	if UI.messageBeep ~= '' then
		if _displayToAll then
			trigger.action.outSound(UI.messageBeep)
		else
			trigger.action.outSoundForGroup(_groupId,UI.messageBeep)
		end 
	end
	local _msg = string.format('(%s): %s',_callSign,_messageText)
	if _displayToAll then
		trigger.action.outText( _msg, _displayTime)
	else
		trigger.action.outTextForGroup(_groupId, _msg, _displayTime)
	end
	
	return true
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.passStartEnd(_args)
	local unitName = _args[1]
	local value = _args[2]
	--local groupID = Unit.getByName(unitName):getGroup():getID()
	local unit = Unit.getByName(unitName)
	local groupID = unit:getGroup():getID()

	if unit:getPlayerName() then 
		if  value == 'in' then

			UI.messageToUnit(unitName,'Cleared in hot',{},10)

			-- reset prior attack results
			TITS.passInit(unitName)
			TITS.passStart(unitName)
			
			UI.toggleAttackMenu(unitName, "in")
			
			if pcall(function() return PTC.Version end ) then
				PTC.passTargetsUP = 0
				PTC.passTargetsHIT = 0
			end

		else -- value == 'off'
			local cfg = UI.unitConfig[unitName]
			local canEnd = TITS.passEnd(unitName)
			cfg.lastPassEnd = timer.getTime()
			if canEnd then
				local cfg = UI.unitConfig[unitName]
				UI.messageToUnit(unitName,'Standby for report',{},10)		
				-- Show results
				if cfg.resultsRPT == 0 then -- automatic
					local passData = TITS.passGetData(unitName)
					local wf = passData.weaponsFired
					if UI.rowCount(wf) >= UI.MinWFgrpRPT then
						if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
							UI.rptImpactResultsDesGrouped(unitName)
						else
							UI.rptImpactResultsGrouped(unitName)
						end
					else
						if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
							UI.rptImpactResultsDes(unitName)
						else
							UI.rptImpactResults(unitName)
						end
					end		
				elseif cfg.resultsRPT == 1 then
					UI.rptImpactResults(unitName)
				elseif cfg.resultsRPT == 2 then
					UI.rptImpactResultsGrouped(unitName)
				elseif cfg.resultsRPT == 3 then	
					UI.rptBDAsummary(unitName)
				end -- 	if UI.DefaultResultReport 
				UI.toggleAttackMenu(unitName, "off")
				
			else
				UI.messageToUnit(unitName,'Standby, weapons still in the air',{},10)		
			end
		end
	end --if unit:getPlayerName() then 

	return true
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.toggleAttackMenu(unitName, action)
	local unit = Unit.getByName(unitName)
	local groupID = unit:getGroup():getID()
	local cfg = UI.unitConfig[unitName]

	if action == 'in' then
		missionCommands.removeItemForGroup(groupID, cfg.rollInPath)
		cfg.offPath =  missionCommands.addCommandForGroup(groupID,"Off - attack completed"	,  cfg.rootPath, 	UI.passStartEnd		, {unitName,'off'})		
	else
		missionCommands.removeItemForGroup(groupID, cfg.offPath)
		cfg.rollInPath= missionCommands.addCommandForGroup(groupID,"Rolling in"				, cfg.rootPath,		UI.passStartEnd		, {unitName,'in'})
	end -- if action...

	return true
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.debugPassData(_unitName)
	local d = TITS.passGetData(_unitName)
	
	--local unit = Unit.getByName(_unitName)
	--local ammoTable = unit:getAmmo()
	
	--trigger.action.outText("ammoTable", 1)
	--trigger.action.outText(mist.utils.tableShow(ammoTable), 1)
	
	--trigger.action.outText("TargetList", 1)
	--trigger.action.outText(mist.utils.tableShow(TITS.TargetList), 1)
	
	--trigger.action.outText("targetHealth", 1)
	--trigger.action.outText(mist.utils.tableShow(d.targetHealth), 1)

	--trigger.action.outText("pass data", 1)
	--trigger.action.outText(mist.utils.tableShow(d), 1)

	trigger.action.outText("shellsFired", 1)
	trigger.action.outText(mist.utils.tableShow(d.shellsFired), 1)

	trigger.action.outText("shellHits", 1)
	trigger.action.outText(mist.utils.tableShow(d.shellHits), 1)
	
	trigger.action.outText("shellDisplayName", 1)
	trigger.action.outText(mist.utils.tableShow(d.shellDisplayName), 1)
	
	trigger.action.outText("getShellsFired", 1)
	local shellsFired = TITS.getShellsFired(_unitName)
	trigger.action.outText(mist.utils.tableShow(shellsFired), 1)


	--trigger.action.outText("weaponHits", 1)
	--trigger.action.outText(mist.utils.tableShow(d.weaponHits), 1)

	--trigger.action.outText("weaponsFired", 1)
	--trigger.action.outText(mist.utils.tableShow(d.weaponsFired), 1)

	--trigger.action.outText("impactData", 1)
	--trigger.action.outText(mist.utils.tableShow(d.impactData), 1)
	
	--trigger.action.outText("groups", 1)
	--trigger.action.outText(mist.utils.tableShow(d.groups), 1)

	return true
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.rptWeaponsInFlight(_unitName)
	local passData = TITS.passGetData(_unitName)
	local weaponsFired = passData.weaponsFired
	local rpt = ''
	local t = timer.getTime() 
	for k,v in pairs(weaponsFired) do
		if v.inFlight then
			et = t - v.timeStamp
			rpt = string.format('%s\n %s (%s s)',rpt, v.weaponType,mist.utils.round(et,0))
		end
	end
	
	if rpt == '' then
		rpt = 'No weapons in flight'
	else
		rpt = string.format('Weapons in flight:%s',rpt)
	end
	UI.messageToUnit(_unitName,rpt,{},30)
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.rptBDAsummary(_unitName)
	if TITS.onPass[_unitName] then
		UI.messageToUnit(_unitName,'Data not available yet, finish the pass',{},5)
	else
		local passData = TITS.passGetData(_unitName)
		local shellHits = passData.shellHits
		local weaponHits = passData.weaponHits
		local weaponsFired = passData.weaponsFired
		local targetHealth = passData.targetHealth
		local rptHitsData = {}
		local rptTargetsHit = {}
		local config = UI.unitConfig[_unitName] 
		
		
		-- Get targets hit by shells and count of hits per shell type
		if #shellHits > 0 then
			for target,_ in pairs(shellHits) do
				if not rptTargetsHit[target] then
					rptTargetsHit[target] = true
				end
				for shellType,count in pairs(shellHits[target]) do
					if not rptHitsData[target] then
						rptHitsData[target] = {}					
					end  -- if not rptHitsData[target] then
					if not rptHitsData[target][shellType] then
						rptHitsData[target][shellType] = count
					else
						rptHitsData[target][shellType] = rptHitsData[target][shellType] + count
					end					
				end -- for _,shellType in pairs(shellHits[target]) do				
			end -- for target,_ in pairs(shellHits) do
		end --	if #shellHits > 0 then
			
		-- Get targets hit by weapons and count of hits by weapon type	
		if 	UI.rowCount(weaponHits) > 0 then
			for weaponID, _ in pairs(weaponHits) do
				local weaponType = weaponsFired[weaponID].weaponType
				for target,_ in pairs (weaponHits[weaponID]) do
					if not rptTargetsHit[target] then
						rptTargetsHit[target] = true
					end
					if not rptHitsData[target] then
						rptHitsData[target] = {}					
					end  -- if not rptHitsData[target] then
					if not rptHitsData[target][weaponType] then
						rptHitsData[target][weaponType] = 1
					else
						rptHitsData[target][weaponType] = rptHitsData[target][weaponType] + 1
					end							
				end -- for target,_ in pairs (weaponHits[weaponID] do
			end -- for weaponID, _ in pairs(weaponHits) do		
		end -- if 	#weaponHits > 0 then
	

----- Show number of rows per table
	
		-- Process the data and generate report
		local rpt = ''
		if UI.rowCount(rptTargetsHit) > 0 then
			for target,_ in pairs(rptTargetsHit) do 
				local section = ''
				local t_row = TITS.TargetList[target]
				local t_health = targetHealth[target]
				local hits = rptHitsData[target]
				
				local max_h = TITS.getMaxTargetLife(target)
				local sp_h = t_health.start_health
				local ep_h = t_health.end_health
			
				local pass_delta = (sp_h - ep_h)*100/max_h
				local overall_delta =  ep_h*100/max_h
				
				local t_status = ''
				if overall_delta >= 0 and overall_delta < 10 then
					t_status = 'destroyed'
				elseif overall_delta >= 10 and overall_delta < 25 then
					t_status = 'heavily damaged'
				elseif overall_delta >= 25 and overall_delta < 50 then
					t_status = 'moderately damaged'
				elseif overall_delta >= 50 and overall_delta < 75 then
					t_status = 'slightly damaged'
				else
					t_status = 'operational'
				end -- if overall_delta >= 0 and overall_delta < 10 then
				
				section = string.format("   >>> %s is %s (pass damage: %s%%)",t_row.displayName,t_status,mist.utils.round(pass_delta,1))
				-- hit details?
			
				rpt = string.format("%s\n%s",rpt,section)
			end -- for target,_ in pairs(rptHitsData) do 	
		end --if #rptHitsData > 0 then
			
		if rpt == '' then
			rpt = 'No targets hit in this pass'	
		end
		if TITS.onPass[_unitName] then
			rpt = string.format('Pass BDA Summary (partial:)\n%s',rpt)
		else
			rpt = string.format('Pass BDA Summary:\n%s',rpt)
		end
		UI.messageToUnit(_unitName,rpt,{},30)
		
	end --if TITS.onPass[_unitName] then
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.rptListCoord(_unitName)	
	local _msg = ''
	local cfg = UI.unitConfig[_unitName]
	
	for t,v in pairs(TITS.TargetList) do
		if v.list_coor then
			local pos = TITS.getTargetPos(t)
			--local _coord, alt, auom = UI.getCoords(_unitName,pos)
			local _coord_mgrs,_coord_dms,_coord_dm, alt, auom = UI.getCoords(_unitName,pos)

			_msg = _msg..string.format('[%s]-> Elev: %i%s MSL\n          %s\n          %s\n          %s\n',v.displayName,alt,auom,_coord_mgrs,_coord_dms,_coord_dm)
		end
	end -- if v.list_coor then
	if _msg ~= '' then
		_msg = string.format('Coordinates:\n%s',_msg)
	else
		_msg = 'Coordinates not available'
	end
	UI.messageToUnit(_unitName, _msg,{},30)
    return true	
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.rptImpactResults(_unitName)
	local config = UI.unitConfig[_unitName] 
	local weaponsFired = TITS.getWeponsFired(_unitName)
	local shellsFired = TITS.getShellsFired(_unitName)
	local shellHits =  TITS.getShellHits(_unitName)
	local title = '\nIndividual Impact Report (closest target)'
	
	if  TITS.onPass[_unitName] then
		title = title..' (partial)'
	end

	if weaponsFired.count > 0 or shellsFired.total > 0 or shellHits.total > 0 then 
		local rpt = ''
		local sec = ''
		--
		-- Shell Hits ==========================================================
		--
		if shellsFired.total > 0 or shellHits.total > 0 then
			
			local ROT = 0
			if shellsFired.total > 0 then
				ROT = mist.utils.round(100*shellHits.total/shellsFired.total,1)
				sec = string.format('    %s Rounds fired / hits: %s%%\n',shellsFired.total,ROT)	
			end

			
			--loop thru shells
			for _, d in pairs(shellHits.list) do	
				local targetName = TITS.TargetList[d.target].displayName
				if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
						if d.target == UI.Designation.Designated then
							sec = string.format('%s    -> %s hit %s rnds: %s - On Target!',sec,targetName, d.hits, d.shellType)
						else
							sec = string.format('%s    -> %s hit %s rnds: %s - Wrong target!',sec,targetName, d.hits, d.shellType)
						end
						if config.desUseAttackRadial and UI.Designation.Designated == d.target then
							local delta = mist.utils.round((shellsFired.shootHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
							if delta >= 180 then
								delta = 360-delta
							end
							if delta == 0 then
								sec = sec..' <on radial>\n'
							else
								sec = string.format('%s <off %s°>\n', sec,delta)
							end
						end
					
					
					else
							sec = string.format('%s    -> %s hit %s rnds: %s\n',sec,targetName, d.hits, d.shellType)
					end	
			end -- for shellType, count in pairs(shellsFired.list) do
			
		end --if shellsFired.total > 0 then
	
		rpt = sec
		sec = ''
		
		--
		-- Weapon Hits ==========================================================
		--
		if weaponsFired.count > 0 then
			for _,wID in pairs(weaponsFired.list) do
				local weaponData = TITS.getWeaponData(_unitName, wID)		
				local targetLN = string.format("    -> %s :",weaponData.weaponType)
				
				if weaponData.miss then
					local missDist,missDistUOM = UI.convertDistance(_unitName,TITS.MaxMissDistance)
					missDist = mist.utils.round(missDist,0)
					targetLN = string.format("%s no targets within %s%s from the impact",targetLN,missDist,missDistUOM)				
				else
				
					local ct = weaponData.closestTarget
					local ctd = weaponData.impacts[ct]
					local ctDN= TITS.TargetList[ct].displayName		
					local hitTXT = 'No effect'		
					if ctd.hit then
						hitTXT ='Good effect'
					end
					if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
						if UI.Designation.Designated == ct then
							hitTXT =hitTXT..' on designated target!'
						else
							hitTXT =hitTXT..' on wrong target!'
						end
						if config.desUseAttackRadial and UI.Designation.Designated == ct then
							local delta = mist.utils.round((weaponData.releaseHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
							if delta >= 180 then
								delta = 360-delta
							end
							if delta == 0 then
								hitTXT = hitTXT..' <on radial>'
							else
								hitTXT = string.format('%s <off %s°>', hitTXT,delta)
							end
						end
						
					else
						hitTXT =hitTXT..' on target!'
					end
					targetLN = string.format("%s %s\n",targetLN,hitTXT)	
					-- Impact data
					local dist,distUOM = UI.convertDistance(_unitName,ctd.distance)		
					dist = mist.utils.round(dist,0)	
					
					local direction = UI.getRelativeDirection(weaponData.releaseHeading ,ctd.targetPos, ctd.impactPos)
					direction = UI.getClockDirection(direction)		
						
					local slantRange = mist.utils.get3DDist(weaponData.releasePosition, ctd.targetPos)
						
					local angDist,angDistUOM = UI.convertAngDistance(_unitName,ctd.distance/(slantRange * 0.1))			
					angDist = mist.utils.round(angDist,2)			
							
					targetLN = string.format("%s       %s %s from %s @ %s o'clock (%s %s)\n"
						,	targetLN
						, 	dist
						,	distUOM
						, 	ctDN
						, 	direction
						, 	angDist
						, 	angDistUOM
					)							
					--Release params
					if config.DisplayReleaseData then	
						local pos = weaponData.releasePosition
						local height =  land.getHeight({x = pos.x, y = pos.z})
						local releaseAlt = pos.y - height -- in meters. Release AGL
						local alt, altUOM =  UI.convertAltitude(_unitName,releaseAlt)
						alt = mist.utils.round(alt,0)
						local speed, speedUOM =  UI.convertSpeed(_unitName,weaponData.releaseSpeed)
						speed = mist.utils.round(speed,0)
						local slant,slantUOM = UI.convertDistance(_unitName,slantRange)		
						slant = mist.utils.round(slant,0)	
						
						local pitch = mist.utils.round(weaponData.releasePitch,1)	
						local roll = mist.utils.round(weaponData.releaseRoll,1)	
						local yaw = mist.utils.round(weaponData.releaseYaw,1)	
						
						local RIdistance,RIdistUOM = UI.convertDistance(_unitName,weaponData.rollInDistance)
						local RIat,RIatUOM = UI.convertAltitude(_unitName,weaponData.rollInAltitudeAT)
						RIdistance = mist.utils.round(RIdistance,0)
						RIat = mist.utils.round(RIat,0)
					
						local relP = string.format("        Rel. Params:     Alt: %s%s AGL    Speed: %s%s    Hdg:%s°\n"
						  
												   , alt , altUOM
												   , speed , speedUOM
												   ,mist.utils.round(weaponData.releaseHeading,0)
												  )
						relP = string.format("%s                                 S.RNG: %s%s      P: %s  R:%s  Y:%s\n"
											,	relP
											,	slant , slantUOM
											,	pitch
											, 	roll
											, 	yaw
											)
											
						relP = string.format("%s        Roll-in:         Dist: %s%s       Alt: %s%s (above target)\n",relP,RIdistance,RIdistUOM,RIat,RIatUOM)
											
						targetLN = string.format("%s%s",targetLN,relP)
					end -- if cfg.DisplayReleaseData then					
					
				end -- if weaponData.miss then
				
				sec = sec..targetLN
			end -- for _,wID in pairs(weaponsFired.list) do
		end --if weaponsFired.count > 0
		
		if rpt ~= '' then
			rpt = string.format ('%s\n%s',rpt,sec)
		else
			rpt = sec
		end
		sec = ''
		--
		-- Popups Hits ==========================================================
		--
		if pcall(function() return PTC.Version end ) then
			if PTC.passTargetsUP > 0 then
				sec = string.format("%s    Popups hit: %s/%s",sec,PTC.passTargetsHIT ,PTC.passTargetsUP )	
			end
		end	

		if rpt ~= '' then
			rpt = string.format ('%s\n%s',rpt,sec)
		else
			rpt = sec
		end
		sec = ''
		--
		-- Show report ==========================================================
		--
		rpt = string.format ('%s\n%s',title,rpt)
		UI.messageToUnit(_unitName,rpt,{},30)
	else -- if weaponsFired.count > 0 or shellsFired.total > 0 then
		UI.messageToUnit(_unitName,title..'\nThere is nothing to report.',{},5)
	end -- if weaponsFired.count > 0 or shellsFired.total > 0 then

end --function	
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.rptImpactResultsGrouped(_unitName)
	local config = UI.unitConfig[_unitName] 
	local weaponsFired = TITS.getWeponsFired(_unitName)
	local shellsFired = TITS.getShellsFired(_unitName)
	local shellHits =  TITS.getShellHits(_unitName)
	local title = '\nGrouped Impact Report (closest target)'
	
	if  TITS.onPass[_unitName] then
		title = title..' (partial)'
	end
	
	if weaponsFired.count > 0 or shellsFired.total > 0 or shellHits.total > 0 then 
		local rpt = ''
		local sec = ''
		--
		-- Shell Hits ==========================================================
		--
		if shellsFired.total > 0  or shellHits.total > 0  then

			local ROT = 0
			if shellsFired.total > 0 then
				ROT = mist.utils.round(100*shellHits.total/shellsFired.total,1)
				sec = string.format('    %s Rounds fired / hits: %s%%\n',shellsFired.total,ROT)	
			end

			--loop thru shells
			for _, d in pairs(shellHits.list) do	
				local targetName = TITS.TargetList[d.target].displayName
				if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
						if d.target == UI.Designation.Designated then
							sec = string.format('%s    -> %s hit %s rnds: %s - On Target!',sec,targetName, d.hits, d.shellType)
						else
							sec = string.format('%s    -> %s hit %s rnds: %s - Wrong target!',sec,targetName, d.hits, d.shellType)
						end
						
						if config.desUseAttackRadial and UI.Designation.Designated == d.target then
							local delta = mist.utils.round((shellsFired.shootHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
							if delta >= 180 then
								delta = 360-delta
							end
							if delta == 0 then
								sec = sec..' <on radial>\n'
							else
								sec = string.format('%s <off %s°>\n', sec,delta)
							end
						end
						
						
					else
							sec = string.format('%s    -> %s hit %s rnds: %s\n',sec,targetName, d.hits, d.shellType)
					end	
			end -- for shellType, count in pairs(shellsFired.list) do
			
		end --if shellsFired.total > 0 then
	
		rpt = sec
		sec = ''
		
		--
		-- Groups ==========================================================
		--
		local groups = TITS.getGroups(_unitName)
		for _ , groupID in pairs(groups.list) do
			local groupData = TITS.getGroupData(_unitName, groupID)
			local targetLN = string.format("    -> %s :",groupData.weaponType)
				
			if groupData.miss then
				local missDist,missDistUOM = UI.convertDistance(_unitName,TITS.MaxMissDistance)
				missDist = mist.utils.round(missDist,0)
				targetLN = string.format("%s no targets within %s%s from the impact",targetLN,missDist,missDistUOM)				
			else
			
				local ct = groupData.closestTarget
				local ctDN= TITS.TargetList[ct].displayName		
				local hitTXT = 'No effect'		
				if groupData.closestTargetHit then
					hitTXT ='Good effect'
				end
				if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
					if UI.Designation.Designated == ct then
						hitTXT =hitTXT..' on designated target!'
					else
						hitTXT =hitTXT..' on wrong target!'
					end
					
					if config.desUseAttackRadial and UI.Designation.Designated == ct then
						local delta = mist.utils.round((weaponData.releaseHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
						if delta >= 180 then
							delta = 360-delta
						end
						if delta == 0 then
							hitTXT = hitTXT..' <on radial>'
						else
							hitTXT = string.format('%s <off %s°>', hitTXT,delta)
						end
					end
					
					
				else
					hitTXT =hitTXT..' on target!'
				end
				
				targetLN = string.format("%s %s (%s/%s hits)\n",targetLN,hitTXT,groupData.closestTargetHitCount, groupData.weaponCount)	
				-- Impact data
				local dist,distUOM = UI.convertDistance(_unitName,groupData.closestTargetDist)		
				dist = mist.utils.round(dist,0)	
				
				local direction = UI.getRelativeDirection(groupData.releaseHeading ,groupData.closestTargetPos, groupData.impactPos)
				direction = UI.getClockDirection(direction)		
					
				local slantRange = mist.utils.get3DDist(groupData.releasePosition, groupData.closestTargetPos)
					
				local angDist,angDistUOM = UI.convertAngDistance(_unitName,groupData.closestTargetDist/(slantRange * 0.1))			
				angDist = mist.utils.round(angDist,2)			

				local grpSize,grpSizeUOM = UI.convertAngDistance(_unitName,groupData.size)			
				grpSize = mist.utils.round(grpSize,2)	
				
	
				-- hit count / weapon count

				targetLN = string.format("%s       %s %s from %s @ %s o'clock (%s %s)\n"
					,	targetLN
					, 	dist
					,	distUOM
					, 	ctDN
					, 	direction
					, 	angDist
					, 	angDistUOM
					)
				targetLN = string.format("%s       Group size: %s%s\n"
					,	targetLN
					, 	grpSize
					,	grpSizeUOM
					)							
				--Release params
				if config.DisplayReleaseData then	
					local pos = groupData.releasePosition
					local height =  land.getHeight({x = pos.x, y = pos.z})
					local releaseAlt = pos.y - height -- in meters. Release AGL
					local alt, altUOM =  UI.convertAltitude(_unitName,releaseAlt)
					alt = mist.utils.round(alt,0)
					local speed, speedUOM =  UI.convertSpeed(_unitName,groupData.releaseSpeed)
					speed = mist.utils.round(speed,0)
					local slant,slantUOM = UI.convertDistance(_unitName,slantRange)		
					slant = mist.utils.round(slant,0)	
					
					local pitch = mist.utils.round(groupData.releasePitch,1)	
					local roll = mist.utils.round(groupData.releaseRoll,1)	
					local yaw = mist.utils.round(groupData.releaseYaw,1)	
					
					local RIdistance,RIdistUOM = UI.convertDistance(_unitName,groupData.rollInDistance)
					local RIat,RIatUOM = UI.convertAltitude(_unitName,groupData.rollInAltitudeAT)
					RIdistance = mist.utils.round(RIdistance,0)
					RIat = mist.utils.round(RIat,0)
			
				
						local relP = string.format("        Rel. Params:     Alt: %s%s AGL    Speed: %s%s    Hdg:%s°\n"
												   , alt , altUOM
												   , speed , speedUOM
												   ,mist.utils.round(groupData.releaseHeading,0)
												  )
					relP = string.format("%s                                 S.RNG: %s%s      P: %s  R:%s  Y:%s\n"
										,	relP
										,	slant , slantUOM
										,	pitch
										, 	roll
										, 	yaw
										)
										
					relP = string.format("%s        Roll-in:         Dist: %s%s       Alt: %s%s (above target)\n",relP,RIdistance,RIdistUOM,RIat,RIatUOM)
					
					targetLN = string.format("%s%s",targetLN,relP)
				end -- if cfg.DisplayReleaseData then					
				
			end -- if weaponData.miss then
			
			sec = sec..targetLN			

		end -- for _,groupID in pairs(groups) do
		

		--
		-- Popups Hits ==========================================================
		--
		if pcall(function() return PTC.Version end ) then
			if PTC.passTargetsUP > 0 then
				sec = string.format("%s    Popups hit: %s/%s",sec,PTC.passTargetsHIT ,PTC.passTargetsUP )	
			end
		end	

		if rpt ~= '' then
			rpt = string.format ('%s\n%s',rpt,sec)
		else
			rpt = sec
		end
		sec = ''
		--
		-- Show report ==========================================================
		--
		rpt = string.format ('%s\n%s',title,rpt)
		UI.messageToUnit(_unitName,rpt,{},30)
	else -- if weaponsFired.count > 0 or shellsFired.total > 0 then
		UI.messageToUnit(_unitName,title..'\nThere is nothing to report.',{},5)
	end -- if weaponsFired.count > 0 or shellsFired.total > 0 then


	
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.rptImpactResultsDes(_unitName)
	local config = UI.unitConfig[_unitName] 
	local weaponsFired = TITS.getWeponsFired(_unitName)
	local shellsFired = TITS.getShellsFired(_unitName)
	local shellHits =  TITS.getShellHits(_unitName)
	local title = '\nIndividual Impact Report (designated target)'
	
	if  TITS.onPass[_unitName] then
		title = title..' (partial)'
	end

	if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
		if weaponsFired.count > 0 or shellsFired.total > 0  or  shellHits.total > 0  then 
				local rpt = ''
				local sec = ''
				-- Header
				local ct = UI.Designation.Designated 
				local ctDN= TITS.TargetList[ct].displayName		
				rpt = string.format('   Target: %s',ctDN)
				if config.desUseAttackRadial then
					rpt = string.format('%s  / Attack radial: %s°',rpt,UI.Designation.AttackRadial)
				end
				
				--
				-- Shell Hits ==========================================================
				--			
				if shellsFired.total > 0  or shellHits.total > 0 then
					local ROT = 0
					if shellsFired.total > 0 then
						ROT = mist.utils.round(100*shellHits.total/shellsFired.total,1)
						sec = string.format('    %s Rounds fired / hits: %s%%\n',shellsFired.total,ROT)	
					end

					--loop thru shells
					for _, d in pairs(shellHits.list) do	
						local targetName = TITS.TargetList[d.target].displayName
						if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
								if d.target == UI.Designation.Designated then
									sec = string.format('%s    -> %s hit %s rnds: %s - On Target!',sec,targetName, d.hits, d.shellType)
								else
									sec = string.format('%s    -> %s hit %s rnds: %s - Wrong target!',sec,targetName, d.hits, d.shellType)
								end
								if config.desUseAttackRadial and UI.Designation.Designated == d.target then
									local delta = mist.utils.round((shellsFired.shootHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
									if delta >= 180 then
										delta = 360-delta
									end
									if delta == 0 then
										sec = sec..' <on radial>\n'
									else
										sec = string.format('%s <off %s°>\n', sec,delta)
									end
								end
							
							
							else
									sec = string.format('%s    -> %s hit %s rnds: %s\n',sec,targetName, d.hits, d.shellType)
							end	
					end -- for shellType, count in pairs(shellsFired.list) do
					
				end --if shellsFired.total > 0 then
			
				if sec ~= '' then
					if rpt ~= '' then
						rpt = string.format ('%s\n%s',rpt,sec)
					else
						rpt = sec
					end
					sec = ''
				end
				
				--
				-- Weapon Hits ==========================================================
				--
				if weaponsFired.count > 0 then
					for _,wID in pairs(weaponsFired.list) do
						local weaponData = TITS.getWeaponData(_unitName, wID)		
						local targetLN = string.format("    -> %s :",weaponData.weaponType)
						local missDist,missDistUOM = UI.convertDistance(_unitName,TITS.MaxMissDistance)
						if weaponData.miss then						
							missDist = mist.utils.round(missDist,0)
							targetLN = string.format("%s no targets within %s%s from the impact",targetLN,missDist,missDistUOM)				
						else													
							local ctd = weaponData.impacts[ct]							
							local hitTXT = 'No effect'		
							
							if ctd then
								
								if ctd.hit then
									hitTXT ='Good effect'
								end
								
								if config.desUseAttackRadial and UI.Designation.Designated == ct then
									local delta = mist.utils.round((weaponData.releaseHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
									if delta >= 180 then
										delta = 360-delta
									end
									if delta == 0 then
										hitTXT = hitTXT..' <on radial>'
									else
										hitTXT = string.format('%s <off %s°>', hitTXT,delta)
									end
								end
								
								
								targetLN = string.format("%s %s\n",targetLN,hitTXT)	
								-- Impact data
								local dist,distUOM = UI.convertDistance(_unitName,ctd.distance)		
								dist = mist.utils.round(dist,0)	
								
								local direction = UI.getRelativeDirection(weaponData.releaseHeading ,ctd.targetPos, ctd.impactPos)
								direction = UI.getClockDirection(direction)		
									
								local slantRange = mist.utils.get3DDist(weaponData.releasePosition, ctd.targetPos)
									
								local angDist,angDistUOM = UI.convertAngDistance(_unitName,ctd.distance/(slantRange * 0.1))			
								angDist = mist.utils.round(angDist,2)		

										
								targetLN = string.format("%s       %s %s from target @ %s o'clock (%s %s)\n"
									,	targetLN
									, 	dist
									,	distUOM
									, 	direction
									, 	angDist
									, 	angDistUOM
									)	
							
								--Release params
								if config.DisplayReleaseData then	
									local pos = weaponData.releasePosition
									local height =  land.getHeight({x = pos.x, y = pos.z})
									local releaseAlt = pos.y - height -- in meters. Release AGL
									local alt, altUOM =  UI.convertAltitude(_unitName,releaseAlt)
									alt = mist.utils.round(alt,0)
									local speed, speedUOM =  UI.convertSpeed(_unitName,weaponData.releaseSpeed)
									speed = mist.utils.round(speed,0)
									local slant,slantUOM = UI.convertDistance(_unitName,slantRange)		
									slant = mist.utils.round(slant,0)	
									
									local pitch = mist.utils.round(weaponData.releasePitch,1)	
									local roll = mist.utils.round(weaponData.releaseRoll,1)	
									local yaw = mist.utils.round(weaponData.releaseYaw,1)	
								
									local relP = string.format("        Rel. Params:     Alt: %s%s AGL    Speed: %s%s    Hdg:%s°\n"
												   , alt , altUOM
												   , speed , speedUOM
												   ,mist.utils.round(weaponData.releaseHeading,0)
												  )
									relP = string.format("%s                                 S.RNG: %s%s      P: %s  R:%s  Y:%s\n"
														,	relP
														,	slant , slantUOM
														,	pitch
														, 	roll
														, 	yaw
														)
														
									targetLN = string.format("%s%s",targetLN,relP)
								end -- if cfg.DisplayReleaseData then					
							else -- if ctd then
								targetLN = string.format("%s no impact within %s%s of the designated target",targetLN,missDist,missDistUOM)	
							end -- if ctd then
						end -- if weaponData.miss then
						
						sec = sec..targetLN
					end -- for _,wID in pairs(weaponsFired.list) do
				end --if weaponsFired.count > 0
				
				if rpt ~= '' then
					rpt = string.format ('%s\n%s',rpt,sec)
				else
					rpt = sec
				end
				sec = ''
				--
				-- Popups Hits ==========================================================
				--
				if pcall(function() return PTC.Version end ) then
					if PTC.passTargetsUP > 0 then
						sec = string.format("%s    Popups hit: %s/%s",sec,PTC.passTargetsHIT ,PTC.passTargetsUP )	
					end
				end	

				if rpt ~= '' then
					rpt = string.format ('%s\n%s',rpt,sec)
				else
					rpt = sec
				end
				sec = ''
				--
				-- Show report ==========================================================
				--
				rpt = string.format ('%s\n%s',title,rpt)
				UI.messageToUnit(_unitName,rpt,{},30)
			else -- if weaponsFired.count > 0 or shellsFired.total > 0 then
				UI.messageToUnit(_unitName,title..'\nThere is nothing to report.',{},5)
			end -- if weaponsFired.count > 0 or shellsFired.total > 0 then
			
	else
		UI.messageToUnit(_unitName,title..'\nThere is no designated target.',{},5)
	end --if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then

end --function	
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.rptImpactResultsDesGrouped(_unitName)
	local config = UI.unitConfig[_unitName] 
	local weaponsFired = TITS.getWeponsFired(_unitName)
	local shellsFired = TITS.getShellsFired(_unitName)
	local shellHits =  TITS.getShellHits(_unitName)
	local title = '\nGrouped Impact Report (designated target)'
	
	if  TITS.onPass[_unitName] then
		title = title..' (partial)'
	end

	if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
		if weaponsFired.count > 0 or shellsFired.total > 0 or shellHits.total > 0 then 
				local rpt = ''
				local sec = ''
				-- Header
				local ct = UI.Designation.Designated 
				local ctDN= TITS.TargetList[ct].displayName		
				rpt = string.format('   Target: %s',ctDN)
				if config.desUseAttackRadial then
					rpt = string.format('%s  / Attack radial: %s°',rpt,UI.Designation.AttackRadial)
				end
				
				--
				-- Shell Hits ==========================================================
				--			
				if shellsFired.total > 0 or shellHits.total > 0  then
					local ROT = 0
					if shellsFired.total > 0 then
						ROT = mist.utils.round(100*shellHits.total/shellsFired.total,1)
						sec = string.format('    %s Rounds fired / hits: %s%%\n',shellsFired.total,ROT)	
					end

					--loop thru shells
					for _, d in pairs(shellHits.list) do	
						local targetName = TITS.TargetList[d.target].displayName
						if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then
								if d.target == UI.Designation.Designated then
									sec = string.format('%s    -> %s hit %s rnds: %s - On Target!',sec,targetName, d.hits, d.shellType)
								else
									sec = string.format('%s    -> %s hit %s rnds: %s - Wrong target!',sec,targetName, d.hits, d.shellType)
								end
								if config.desUseAttackRadial and UI.Designation.Designated == d.target then
									local delta = mist.utils.round((shellsFired.shootHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
									if delta >= 180 then
										delta = 360-delta
									end
									if delta == 0 then
										sec = sec..' <on radial>\n'
									else
										sec = string.format('%s <off %s°>\n', sec,delta)
									end
								end
							
							
							else
									sec = string.format('%s    -> %s hit %s rnds: %s\n',sec,targetName, d.hits, d.shellType)
							end	
					end -- for shellType, count in pairs(shellsFired.list) do
					
				end --if shellsFired.total > 0 then
			
				if sec ~= '' then
					if rpt ~= '' then
						rpt = string.format ('%s\n%s',rpt,sec)
					else
						rpt = sec
					end
					sec = ''
				end
				
				--
				-- Groups ==========================================================
				--
				if weaponsFired.count > 0 then
					local groups = TITS.getGroups(_unitName)
					for _,groupID in pairs(groups.list) do
						local groupData = TITS.getGroupData(_unitName, groupID)		
						local targetLN = string.format("    -> %s :",groupData.weaponType)
						local missDist,missDistUOM = UI.convertDistance(_unitName,TITS.MaxMissDistance)
						if groupData.miss then						
							missDist = mist.utils.round(missDist,0)
							targetLN = string.format("%s no targets within %s%s from the impact",targetLN,missDist,missDistUOM)				
						else					

							-- get all the weapons in the group with an impact on the target
							local ctd = {}
							local ctPos = {}
							local ctHits = 0
							for _,row in pairs(groupData.TargetImpacts) do
								if row.target == UI.Designation.Designated  then
									table.insert(ctd,row.targetPos)
									ctPos =row.targetPos
									if row.hit then
										 ctHits =  ctHits + 1
									end
								end
							end
							
						
							--local ctd = weaponData.impacts[ct]							
							local hitTXT = 'No effect'		
							
							if UI.rowCount(ctd) > 0 then
								
								if UI.inTable(UI.Designation.Designated,groupData.targetsHit) then
									hitTXT ='Good effect'
								end
								
								if config.desUseAttackRadial and UI.Designation.Designated == ct then
									local delta = mist.utils.round((groupData.releaseHeading - UI.MagneticVar) - UI.Designation.AttackRadial, 0)
									if delta >= 180 then
										delta = 360-delta
									end
									if delta == 0 then
										hitTXT = hitTXT..' <on radial>'
									else
										hitTXT = string.format('%s <off %s°>', hitTXT,delta)
									end
								end
								
								targetLN = string.format("%s %s (%s/%s hits)\n",targetLN,hitTXT,ctHits, groupData.weaponCount)	
								--targetLN = string.format("%s %s\n",targetLN,hitTXT)	
								-- Impact data from group center
								local distance = mist.utils.get3DDist(groupData.impactPos,ctPos)
								
								local dist,distUOM = UI.convertDistance(_unitName,distance)		
								dist = mist.utils.round(dist,0)	
								
								local direction = UI.getRelativeDirection(groupData.releaseHeading ,ctPos, groupData.impactPos)
								direction = UI.getClockDirection(direction)		
									
								local slantRange = mist.utils.get3DDist(groupData.releasePosition, ctPos)
									
								local angDist,angDistUOM = UI.convertAngDistance(_unitName,distance/(slantRange * 0.1))			
								angDist = mist.utils.round(angDist,2)		

								local grpSize,grpSizeUOM = UI.convertAngDistance(_unitName,groupData.size)			
								grpSize = mist.utils.round(grpSize,2)								
										
								targetLN = string.format("%s       %s %s from target @ %s o'clock (%s %s)\n"
									,	targetLN
									, 	dist
									,	distUOM
									, 	direction
									, 	angDist
									, 	angDistUOM
									)	
								targetLN = string.format("%s       Group size: %s%s\n"
									,	targetLN
									, 	grpSize
									,	grpSizeUOM
									)	
								--Release params
								if config.DisplayReleaseData then	
									local pos = groupData.releasePosition
									local height =  land.getHeight({x = pos.x, y = pos.z})
									local releaseAlt = pos.y - height -- in meters. Release AGL
									local alt, altUOM =  UI.convertAltitude(_unitName,releaseAlt)
									alt = mist.utils.round(alt,0)
									local speed, speedUOM =  UI.convertSpeed(_unitName,groupData.releaseSpeed)
									speed = mist.utils.round(speed,0)
									local slant,slantUOM = UI.convertDistance(_unitName,slantRange)		
									slant = mist.utils.round(slant,0)	
									
									local pitch = mist.utils.round(groupData.releasePitch,1)	
									local roll = mist.utils.round(groupData.releaseRoll,1)	
									local yaw = mist.utils.round(groupData.releaseYaw,1)	
								
									local relP = string.format("        Rel. Params:     Alt: %s%s AGL    Speed: %s%s    Hdg:%s°\n"
												   , alt , altUOM
												   , speed , speedUOM
												   , mist.utils.round(groupData.releaseHeading,0)
												  )
									relP = string.format("%s                                 S.RNG: %s%s      P: %s  R:%s  Y:%s\n"
														,	relP
														,	slant , slantUOM
														,	pitch
														, 	roll
														, 	yaw
														)
														
									targetLN = string.format("%s%s",targetLN,relP)
								end -- if cfg.DisplayReleaseData then					
							else -- if ctd then
								targetLN = string.format("%s no impact within %s%s of the designated target",targetLN,missDist,missDistUOM)	
							end -- if ctd then
						end -- if weaponData.miss then
						
						sec = sec..targetLN
					end -- for _,wID in pairs(weaponsFired.list) do
				end --if weaponsFired.count > 0
				
				if rpt ~= '' then
					rpt = string.format ('%s\n%s',rpt,sec)
				else
					rpt = sec
				end
				sec = ''
				--
				-- Popups Hits ==========================================================
				--
				if pcall(function() return PTC.Version end ) then
					if PTC.passTargetsUP > 0 then
						sec = string.format("%s    Popups hit: %s/%s",sec,PTC.passTargetsHIT ,PTC.passTargetsUP )	
					end
				end	

				if rpt ~= '' then
					rpt = string.format ('%s\n%s',rpt,sec)
				else
					rpt = sec
				end
				sec = ''
				--
				-- Show report ==========================================================
				--
				rpt = string.format ('%s\n%s',title,rpt)
				UI.messageToUnit(_unitName,rpt,{},30)
			else -- if weaponsFired.count > 0 or shellsFired.total > 0 then
				UI.messageToUnit(_unitName,title..'\nThere is nothing to report.',{},5)
			end -- if weaponsFired.count > 0 or shellsFired.total > 0 then
			
	else
		UI.messageToUnit(_unitName,title..'\nThere is no designated target.',{},5)
	end --if UI.Designation.type ~=0 and UI.Designation.Designated ~= '' then

end --function	

--
--#################################################################################################################################################
-- #############   Illumination	 																									############### 
--#################################################################################################################################################
--
function UI.AddIlluminationZone(_zoneName, _Rounds)
	UI.illuminationZones[_zoneName] = _Rounds
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.illuminate(params, time)
	if  UI.illuminating  then
		if UI.rowCount(UI.illuminationZones) > 0 then
			for z,r in pairs(UI.illuminationZones) do
				for i=1,r do
					local pos = mist.utils.makeVec3(mist.getRandomPointInZone(z),mist.random(450,550))
					trigger.action.illuminationBomb(pos,7500)
				end
			end
		end
		return timer.getTime() + 150
	else
		return nil
	end
end -- function
--------------------
--
--#################################################################################################################################################
-- #############   Designation	 																									############### 
--#################################################################################################################################################
--
function UI.AddDesignationZone(_ID, _Name)
	UI.DesignationZones[_ID] = { id = _ID, name = _Name}
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.AddDesignator(_name, _displayName, _zones, _allowLaser, _allowIR, _code)
	local dn = _displayName
	if _displayName == '' then
		dn = _name
	end
	UI.Designators[_name] = {
				name = _name
			,	displayName = dn
			,	zones = _zones
			,	allowLaser = _allowLaser
			, 	allowIR	= _allowIR
			, 	code = _code
			
		}
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desSetZone(_args)

	local unitName = _args[1]
	local zoneID = _args[2]
	
	UI.Designation.zone = zoneID
	local z = UI.DesignationZones[zoneID]
	UI.messageToUnit(unitName,string.format('Designation zone set to: %s',z.name))	
	
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desWP(_args)
	local _unitName = _args[1]
	local isNew = _args[2]
	local ERROR = 0
	local targetList = {}
	local n = 0 -- Number of designatable targets in zone
	local tgt	-- selectec target
	local cfg = UI.unitConfig[_unitName]
	-- Get WP designatable targets in the selected zone
	if isNew then
		for _,row in pairs(TITS.TargetList) do
			if row.des_zone == UI.Designation.zone and row.des_wp and TITS.getTargetLife(row.name) > 0  then
				n = n + 1
				targetList[n] = row.name
			end
		end -- for t,row in pairs(TITS.TargetList) do
		if n == 0 then
			ERROR = 1 -- No designatable targets in zone
		else
			local r = mist.random(1,n)
			tgt = targetList[r]
		end
	else -- if isNew  or UI.Designation.Designated == '' then
		tgt = UI.Designation.Designated
		if TITS.getTargetLife(tgt) <= 0 then
			ERROR = 2 -- prior designated target is dead
		end
	end -- if isNew   then
	if ERROR == 0 then -- Designate the target
		--select a random target
		local tgtPos = TITS.getTargetPos(tgt)
		local markPos =  mist.utils.makeVec3GL(mist.getRandPointInCircle(tgtPos,UI.maxWPmarkDist,UI.minWPmarkDist,0,360))
		local _dir = mist.utils.toDegree(mist.utils.getDir(mist.vec.sub(tgtPos, markPos)))
		local _dist = mist.utils.get2DDist(markPos,tgtPos)
		local _direction = ''
		local oTarget = TITS.TargetList[tgt]

		if _dir >= 0 and _dir <  22 then
				_direction = 'North'
			elseif _dir >= 22 and _dir <  68 then
				_direction = 'North East'
			elseif _dir >= 68 and _dir <  113 then
				_direction = 'East'
			elseif _dir >= 113 and _dir <  158 then
				_direction = 'South East'
			elseif _dir >= 158 and _dir <  203 then
				_direction = 'South'
			elseif _dir >= 203 and _dir <  248 then
				_direction = 'South West'
			elseif _dir >= 248 and _dir <  293 then
				_direction = 'West'
			elseif _dir >= 293 and _dir <  338 then
				_direction = 'North West'
			elseif _dir >= 338 and _dir <=  360 then
				_direction = 'North'
		end

		local ar_brief = ''
		if cfg.desUseAttackRadial then
			UI.Designation.AttackRadial =  mist.random(1,359)
			ar_brief = string.format('\nAttack radial %s° (magnetic)',UI.Designation.AttackRadial)
		end

		-- prepare the briefing
		local dist,distUOM = UI.convertDistance(_unitName,_dist)		
		dist = mist.utils.round(dist,0)	
		if distUOM == 'ft' then 
			dist = math.floor(dist / 25) * 25
		else
			dist = math.floor(dist / 10) * 10
		end
		
		local briefing = string.format("%s marked with WP\n%i %s, %s from the mark%s",oTarget.displayName, dist,distUOM, _direction,ar_brief)	
		
		UI.Designation.Designator 	=	'' -- unit name
		UI.Designation.Designated 	=	tgt
		UI.Designation.type		=	1 -- 0 = none, 1 = WP , 2 = laser, 3 = IR
		UI.Designation.briefing = briefing
	
		trigger.action.smoke(markPos, trigger.smokeColor.White )
		UI.messageToUnit(_unitName,briefing,{},45)
	else
		local errorMSG =''
		if ERROR == 1 then
			errorMSG = string.format('There are no designatable targets in zone %s',UI.DesignationZones[UI.Designation.zone].name )
		elseif ERROR == 2 then
			errorMSG ='Target is dead. Select a new one'
		end	
		UI.messageToUnit(_unitName,errorMSG,{},45)

		UI.Designation.Designator 	=	'' -- unit name
		UI.Designation.Designated 	=	''
		UI.Designation.type		=	0 -- 0 = none, 1 = WP , 2 = laser, 3 = IR
		UI.Designation.briefing = ''
		
			
	end --if not ERROR then


end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desNM(_unitName)
	local config = UI.unitConfig[_unitName] 
	local ERROR = 0
	local targetList = {}
	local n = 0 -- Number of designatable targets in zone
	local tgt	-- selectec target
	-- Get WP designatable targets in the selected zone
	
	for _,row in pairs(TITS.TargetList) do
		if row.des_zone == UI.Designation.zone and row.des_nomark and TITS.getTargetLife(row.name) > 0  then
			n = n + 1
			targetList[n] = row.name
		end
	end -- for t,row in pairs(TITS.TargetList) do
	if n == 0 then
		ERROR = 1 -- No designatable targets in zone
	else
		local r = mist.random(1,n)
		tgt = targetList[r]
	end


	if ERROR == 0 then -- Designate the target
		-- prepare the briefing
		local oTarget = TITS.TargetList[tgt]
		local cfg = UI.unitConfig[_unitName]

		local ar_brief = ''
		if cfg.desUseAttackRadial then
			UI.Designation.AttackRadial =  mist.random(1,359)
			ar_brief = string.format('\nAttack radial %s° (magnetic)',UI.Designation.AttackRadial)
		end


		local briefing = ''
		if config.desDisplayCoords then
			local pos = TITS.getTargetPos(tgt)
			--local _coord, alt, auom = UI.getCoords(_unitName,pos)
			local _coord_mgrs,_coord_dms,_coord_dm, alt, auom = UI.getCoords(_unitName,pos)
			--Elev: %i%s MSL\n          %s\n          %s\n          %s\n'
			briefing = string.format("\nYour target is %s at  Elev: %i%s MSL\n          %s\n          %s\n          %s\n",oTarget.displayName,alt,auom,_coord_mgrs,_coord_dms,_coord_dm)	
		else
			briefing = string.format("\nYour target is %s",oTarget.displayName)	
		end
		
		briefing = string.format("%s%s",briefing,ar_brief)	
		
		if oTarget.uiText1 ~= '' then
			briefing = string.format('%s\n%s',briefing,oTarget.uiText1)
		end
		
		if oTarget.uiText2 ~= '' then
			briefing = string.format('%s\n%s',briefing,oTarget.uiText2)
		end
		
		if oTarget.uiText3 ~= '' then
			briefing = string.format('%s\n%s',briefing,oTarget.uiText3)
		end
	
		UI.Designation.Designator 	=	'' -- unit name
		UI.Designation.Designated 	=	tgt
		UI.Designation.type		=	4 -- 0 = none, 1 = WP , 2 = laser, 3 = IR, 4 = No mark
		UI.Designation.briefing = briefing

		UI.messageToUnit(_unitName,briefing,{},45)
	else
		local errorMSG =''
		if ERROR == 1 then
			errorMSG = string.format('There are no designatable targets in zone %s',UI.DesignationZones[UI.Designation.zone].name )
		end	
		UI.messageToUnit(_unitName,errorMSG,{},45)

		UI.Designation.Designator 	=	'' -- unit name
		UI.Designation.Designated 	=	''
		UI.Designation.type		=	0 -- 0 = none, 1 = WP , 2 = laser, 3 = IR
		UI.Designation.briefing = ''
		
			
	end --if not ERROR then


end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desRPTBrief(_unitName)	
	if UI.Designation.type  ~= 0 then
		UI.messageToUnit(_unitName,UI.Designation.briefing,{},45)
	else
		UI.messageToUnit(_unitName,'No targets designated',{},45)
	end
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desCancel(_unitName)

	UI.Designation.Designator 	=	'' -- unit name
	UI.Designation.Designated 	=	''
	UI.Designation.type		=	0 -- 0 = none, 1 = WP , 2 = laser, 3 = IR, 4 = No mark, 23 = laser/IR
	UI.Designation.briefing = ''
	UI.Designation.spotON = false
	UI.messageToUnit(_unitName,'Designation cancelled',{},5)

end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	
function UI.desLaserIR(_args)
	local _unitName = _args[1]
	local desType = _args[2] -- laser | IR
	local designators = {}
	local targets = {}
	local Nt = 0
	local Nd = 0
	local cfg = UI.unitConfig[_unitName]
	
	if UI.Designation.type == 2 or UI.Designation.type == 3 or UI.Designation.type == 23 then
		UI.messageToUnit(_unitName,'There is a prior laser/IR designation. Cancel it first',{},15)
		return false
	end
	
	-- get designatable targets is zone
	for _,row in pairs(TITS.TargetList) do
		if row.des_zone == UI.Designation.zone  and TITS.getTargetLife(row.name) > 0 and 
		((row.des_laser and desType == 'laser') or (row.des_ir and desType == 'IR')   or (desType ==  'laser/IR' and row.des_laser and row.des_ir ) )  then
			Nt = Nt + 1
			targets[Nt] = row.name
		end
	end -- for t,row in pairs(TITS.TargetList) do
	
	-- get designators in zone
	for _,row in pairs(UI.Designators) do
		if UI.inTable(UI.Designation.zone, row.zones )  and  ((row.allowLaser and desType == 'laser') or (row.allowIR and desType == 'IR')  or (desType ==  'laser/IR' and row.allowLaser and row.allowIR  ) )  then
			-- check designator life
			local u = Unit.getByName(row.name)
			if u then
				Nd = Nd + 1
				designators[Nd] = row.name
			end
		end
	end -- for t,row in pairs(TITS.TargetList) do
	if Nt > 0 and Nd > 0 then
		local Rt = mist.random(1,Nt)
		local Rd = mist.random(1,Nd)
		UI.Designation.Designator = designators[Rd]
		UI.Designation.Designated = targets[Rt]
		local designator = Unit.getByName(UI.Designation.Designator )
		
		local desPos = TITS.getTargetPos(UI.Designation.Designated)
		desPos = { x = desPos.x, y = desPos.y + 2.0, z = desPos.z }
		if desType == 'laser' then 
			UI.Designation.type		=	2 
			UI.Designation.ray1 = Spot.createLaser(designator, {x = 0, y = 1, z = 0}, desPos , UI.Designators[UI.Designation.Designator].code)
		elseif desType == 'IR' then 
			UI.Designation.type		=	3
			UI.Designation.ray1 = Spot.createInfraRed(designator, {x = 0, y = 1, z = 0}, desPos)
		else
			UI.Designation.type		=	23
			UI.Designation.ray1 = Spot.createLaser(designator, {x = 0, y = 1, z = 0}, desPos, UI.Designators[UI.Designation.Designator].code)
			UI.Designation.ray2 = Spot.createInfraRed(designator, {x = 0, y = 1, z = 0}, desPos)
		end
		local function updateRay()
				if UI.Designation.type == 2 or UI.Designation.type == 3 then
					local pos = TITS.getTargetPos(UI.Designation.Designated)
					pos = { x = pos.x, y = pos.y + 2.0, z = pos.z }
					UI.Designation.ray1:setPoint(pos)
					timer.scheduleFunction(updateRay, {}, timer.getTime() + 0.5)
				elseif UI.Designation.type == 23 then
					local pos = TITS.getTargetPos(UI.Designation.Designated)
					pos = { x = pos.x, y = pos.y + 2.0, z = pos.z }
					UI.Designation.ray1:setPoint(pos)
					UI.Designation.ray2:setPoint(pos)
					timer.scheduleFunction(updateRay, {}, timer.getTime() + 0.5)
				else
					UI.Designation.ray1:destroy()
					if UI.Designation.ray2 then
						UI.Designation.ray2:destroy()
					end
				end
			end
		timer.scheduleFunction(updateRay, {}, timer.getTime() + 0.5)
		-- prepare briefing
		
		local ar_brief = ''
		if cfg.desUseAttackRadial then
			UI.Designation.AttackRadial =  mist.random(1,359)
			ar_brief = string.format('\nAttack radial %s° (magnetic)',UI.Designation.AttackRadial)
		end

		
		local dDN = UI.Designators[UI.Designation.Designator].displayName
		local t = TITS.TargetList[UI.Designation.Designated]
		local brief = string.format('%s designated by %s from %s', t.displayName, desType, dDN)
		if UI.Designation.type == 2 or UI.Designation.type == 23 then
			brief = string.format('%s with code: %s',brief,UI.Designators[UI.Designation.Designator].code)
		end

		if cfg.desDisplayCoords then
			local pos = TITS.getTargetPos(UI.Designation.Designated)
			--local _coord, alt, auom = UI.getCoords(_unitName,pos)
			local _coord_mgrs,_coord_dms,_coord_dm, alt, auom = UI.getCoords(_unitName,pos)
			brief = string.format('%s\ntarget coords: Elev: %i%s MSL\n          %s\n          %s\n          %s',brief,alt,auom, _coord_mgrs,_coord_dms,_coord_dm)
		end
		brief = string.format('%s%s',brief,ar_brief)
		
		local oTarget = TITS.TargetList[UI.Designation.Designated]
		if oTarget.uiText1 ~= '' then
			brief = string.format('%s\n%s',brief,oTarget.uiText1)
		end
		
		if oTarget.uiText2 ~= '' then
			brief = string.format('%s\n%s',brief,oTarget.uiText2)
		end
		
		if oTarget.uiText3 ~= '' then
			brief = string.format('%s\n%s',brief,oTarget.uiText3)
		end
		
		
		UI.messageToUnit(_unitName,brief,{},45)
	
	else -- if Nt > 0 and Nd > 0 then
		local errorMSG = string.format('There are no designatable targets or designators in zone %s',UI.DesignationZones[UI.Designation.zone].name )
		UI.messageToUnit(_unitName,errorMSG,{},45)
	end
	return true	
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------	

--
--#################################################################################################################################################
-- #############   Utility	 																										############### 
--#################################################################################################################################################
--
function UI.getCoords(_unitName,pos)
	local lat, lon, alt = coord.LOtoLL(pos)

	--MGRS
	local _coord_mgrs = mist.tostringMGRS(coord.LLtoMGRS(coord.LOtoLL(pos)), 5):gsub(string.char(9),'   ')
	-- DMS
	local _coord_dms = mist.tostringLL(lat, lon, 3, true):gsub(string.char(9),'   ')	
	-- DM.mm
	local _coord_dm = mist.tostringLL(lat, lon, 4):gsub(string.char(9),'   ')
	local a,auom = UI.convertAltitude(_unitName,alt)
	return _coord_mgrs,_coord_dms,_coord_dm, a, auom
--[[
	local cfg = UI.unitConfig[_unitName]
	local _coord = ''
	local lat, lon, alt = coord.LOtoLL(pos)
	
	
	if cfg.CoordFormat == 1 then --MGRS
		_coord = mist.tostringMGRS(coord.LLtoMGRS(coord.LOtoLL(pos)), 5)
	elseif  cfg.CoordFormat == 2 then -- DMS
		_coord = mist.tostringLL(lat, lon, 2, true)	
	else -- DM.mm
		_coord = mist.tostringLL(lat, lon, 2)
	end	

	_coord = _coord:gsub(string.char(9),'   ')
	local a,auom = UI.convertAltitude(_unitName,alt)
	return _coord, a, auom
--]]
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.convertSpeed(_unitName,_speed)
	local s
	local u
	local cfg = UI.unitConfig[_unitName] 
	 -- 1 = Knots, 2 = Mph, 3 = Kph	
	 -- _speed in m/s
	if cfg.SpeedUOM == 1 then
		s = _speed * 1.943844
		u = 'kt'
	elseif cfg.SpeedUOM == 2 then
		s = _speed * 2.23694
		u = 'mph'
	else
		s = _speed * 36
		u = 'kph'
	end
	return s,u
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.convertDistance(_unitName,_distance)
	local s
	local u
	local cfg = UI.unitConfig[_unitName] 
	-- 1 = feet, 2 = yards, 3 = meters
	-- _distance in meters
	if cfg.DistanceUOM == 1 then
		s = _distance * 3.28084
		u = 'ft'
	elseif cfg.DistanceUOM == 2 then
		s = _distance * 1.093613
		u = 'yd'
	else
		s = _distance 
		u = 'm'
	end
	return s,u
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.convertAngDistance(_unitName,_distance)
	local s
	local u
	local cfg = UI.unitConfig[_unitName] 
	-- 1 = feet, 2 = yards, 3 = meters
	-- _distance in meters
	if cfg.DistanceUOM == 1 or cfg.DistanceUOM == 2 then
		s = _distance * 3.4377492368197 
		u = 'MOA'
	else
		s = _distance 
		u = 'mils'
	end
	return s,u
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.convertAltitude(_unitName,_altitude)
	local s
	local u
	local cfg = UI.unitConfig[_unitName] 
	-- 1 = feet, 2 = yards, 3 = meters
	-- _distance in meters
	if cfg.AltitudeUOM == 1 then
		s = _altitude * 3.28084
		u = 'ft'
	else
		s = _altitude 
		u = 'm'
	end
	return s,u
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.getRelativeDirection(_refHeading,_point1, _point2)
    local tgtBearing
    local xUnit = _point1.x
    local yUnit = _point1.z
    local xZone = _point2.x
    local yZone = _point2.z
    
    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone
    
    local tgtAngle = math.deg(math.atan(yDiff/xDiff))
    
    if xDiff > 0 then 
    tgtBearing = 180 + tgtAngle 
    end
    
    if xDiff < 0 and tgtAngle > 0 then
		tgtBearing = tgtAngle 
    end
    
    if xDiff < 0 and tgtAngle < 0 then
		tgtBearing = 360 + tgtAngle
    end   
	
	tgtBearing = tgtBearing - _refHeading
	if tgtBearing > 360 then
		tgtBearing = tgtBearing - 360
	end
	if tgtBearing < 0 then
		tgtBearing =  360 + tgtBearing 
	end
	
    return tgtBearing
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.getClockDirection(_direction)
	-- by cfrag
	if not _direction then return 0 end
	while _direction < 0 do 
		_direction = _direction + 360
	end
		
	if _direction < 15 then -- special case 12 o'clock past 12 o'clock
		return 12
	end
	
	_direction = _direction + 15 -- add offset so we get all other times correct
	return math.floor(_direction/30)
	
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.getDirection(_point1, _point2)
    local tgtBearing
    local xUnit = _point1.x
    local yUnit = _point1.z
    local xZone = _point2.x
    local yZone = _point2.z
    
    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone
    
    local tgtAngle = math.deg(math.atan(yDiff/xDiff))
    
    if xDiff > 0 then 
    tgtBearing = 180 + tgtAngle 
    end
    
    if xDiff < 0 and tgtAngle > 0 then
    tgtBearing = tgtAngle 
    end
    
    if xDiff < 0 and tgtAngle < 0 then
    tgtBearing = 360 + tgtAngle
    end
    
   
    return tgtBearing
end
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.rowCount(t)
	local r = 0
	if t then
		for _,_ in pairs(t) do
			r = r + 1
		end
	end
	return r
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------
function UI.inTable(v,t)
	local r = true
	for _,j in pairs(t) do
		if j == v then
			return true
		end
	end
	return false
	
end -- function
-----------------------------------------------------------------------------------------------------------------------------------------------------

--
--#################################################################################################################################################
-- #############   Main body   																										############### 
--#################################################################################################################################################
--
do
	-- load event handler
	world.addEventHandler(UI.EventHandler)
	
	trigger.action.outText( 'Range UI - v'..UI.Version, 1 )
end