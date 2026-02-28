--[[ 

	DCS - Target Impact Tracker Script - Range Control
	by Draken35
	
	Requires MIST 4.4.90 or above <https://github.com/mrSkortch/MissionScriptingTools/tree/master>
	
    Version history
	1.00		10/04/2021	Initial release / Development start


	
--]]

TITS  = {}
trigger.action.outText( 'Target Impact Tracker Script- V1.00', 2 )


--############################################################################################################################################
-- #############   Configuration section   ############# 
--############################################################################################################################################
TITS.MaxMissDistance = 1000 -- Any impact over this distance from the closest target will be considered as Miss

TITS.TargetList = {} -- These are the targets that the script handles 
					 -- for the unit, use the UNIT name, not the group.
					 -- Only units can be strafed and have a bda (hit)
					 -- target names need to be UNIQUE. It is also case sensitive.
					 -- impact = true will consider the target when calculating the closest target to the weapon impact. If false it will not be considered.
					 -- strafing = true will allow the target to count strafing hits. If false, it will not
					 -- bda = true will make the script check if the target was in the weapon blast radio and was "hit" by the blast.  If false, it will not
					 -- The existance or type of the targets IS NOT VALIDATED by the script to save some CPU cycles. Make sure the list match the mission
					 
	table.insert(TITS.TargetList,	{	name = 'Circle A', 		type = 'unit', impact =true,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Moving Target', type = 'unit', impact =true,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Circle B', 		type = 'zone', impact =true,	strafing = false, 	bda = false	})	
	table.insert(TITS.TargetList,	{	name = 'Blue Sealand', 	type = 'unit', impact =false,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Brown Sealand', type = 'unit', impact =false,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Green Sealand', type = 'unit', impact =false,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Tan Sealand', 	type = 'unit', impact =false,	strafing = true, 	bda = true	})
	table.insert(TITS.TargetList,	{	name = 'Strafe pit', 	type = 'unit', impact =false,	strafing = true, 	bda = false	})


--############################################################################################################################################
-- #############   Sound Files     ############# 
--############################################################################################################################################
	TITS.messageBeep = '204521__redoper__roger-beep.ogg' -- leave empty for no sound



--############################################################################################################################################
-- #############   Code section   ############# 
--############################################################################################################################################
-- Initialization of globals

TITS.eventHandler = {}
TITS.menuAddedToGroup = {}
TITS.attackingUnits = {}
TITS.isStrafingAttack = {}
TITS.reportWeaponsDistance = {} -- report non-strafing hits
TITS.reportWeaponsHits = {} -- report non-strafing hits
TITS.strafingHitCounter = {}
TITS.weponsHit = {}
TITS.rootPath = {}
TITS.rollInPath = {}
TITS.offPath = {}
TITS.lastAbortMSG = {}
TITS.passCounter = {}
TITS.uom ={} -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
TITS.DisplayDBA = {}
TITS.DisplayReleaseData = {}


--############################################################################################################################################
function TITS.eventHandler:onEvent(_eventDCS)

    if _eventDCS == nil or _eventDCS.initiator == nil then
        return true
    end

    local status, err = pcall(function(_event)


	-- ### player entered unit   _event.id == 15   
    if _event.id == 15 then -- id == 15 Enter

		TITS.EnterUnitEvent(_event)
			
	elseif (_event.id == world.event.S_EVENT_SHOT) and _event.initiator:getPlayerName()  then -- id == 1 Shot
		
		TITS.ShotEvent(_event)
		
	 elseif  _event.id == world.event.S_EVENT_HIT and _event.initiator:getPlayerName()  then  -- id == 2 Hit
	 
		TITS.HitEvent(_event)
		
	 elseif  _event.id == world.event.S_EVENT_SHOOTING_START and _event.initiator:getPlayerName()  then   -- id == 23 Start Shooting
	 
		TITS.StartShootingEvent(_event)
				
	end -- if _event.id == S_EVENT_PLAYER_ENTER_UNIT then --player entered unit
  -- ### End event processing

        return true
    end, _eventDCS)

    if (not status) then
        env.error(string.format("Target Impact Tracker: Error while handling event %s", err),false)
		trigger.action.outText( string.format("Target Impact Tracker: Error while handling event %s", err), 30 )
    end
end
--############################################################################################################################################
function TITS.EnterUnitEvent(_event)
	local groupID = _event.initiator:getGroup():getID()
	local unitName = _event.initiator:getName()
	
	-- inits
	TITS.attackingUnits[unitName] = false
	TITS.reportWeaponsHits[unitName] = false
	TITS.lastAbortMSG[unitName] = timer.getTime() - 5
	TITS.passCounter[unitName] = 0
	TITS.uom[unitName] = 2 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
	TITS.DisplayDBA[unitName] = true
	TITS.DisplayReleaseData[unitName] = true
	
	-- Menu
	if not TITS.menuAddedToGroup[groupID] then
		TITS.rootPath[unitName] = missionCommands.addSubMenuForGroup(groupID, "Range")			
		local _reportsPath = missionCommands.addSubMenuForGroup(groupID, "Reports", TITS.rootPath[unitName])
			missionCommands.addCommandForGroup(groupID,"Attack results"	, _reportsPath, TITS.ReportAttackResults		, unitName)
			
		local _settingsPath = missionCommands.addSubMenuForGroup(groupID, "Settings", TITS.rootPath[unitName])
			missionCommands.addCommandForGroup(groupID,"Toggle non strafing hits (BDA) report"	, _settingsPath, TITS.Settings		, {unitName,1})
			missionCommands.addCommandForGroup(groupID,"Toggle display of Release data"			, _settingsPath, TITS.Settings		, {unitName,2})
			missionCommands.addCommandForGroup(groupID,"Use metric units"						, _settingsPath, TITS.Settings		, {unitName,3})
			missionCommands.addCommandForGroup(groupID,"Use imperial units (knots)"				, _settingsPath, TITS.Settings		, {unitName,4})
			missionCommands.addCommandForGroup(groupID,"Use imperial units (mph)"				, _settingsPath, TITS.Settings		, {unitName,5})
	
		TITS.rollInPath[unitName] = missionCommands.addCommandForGroup(groupID,"Rolling in"				, TITS.rootPath[unitName], TITS.ReportAttack		, {unitName,'in'})
		
	end -- if not TITS.menuAddedToGroup[groupID] then
	return true
end
--############################################################################################################################################
function TITS.ShotEvent(_event)
	local _weapon = _event.weapon
	local _target = _weapon:getTarget() 
	local unitName = _event.initiator:getName()
	
	if not TITS.attackingUnits[unitName] then
		local t =  timer.getTime() 
		if (t - TITS.lastAbortMSG[unitName]) > 5 then 
			TITS.messageToUnit(unitName,'Abort! Abort! Abort!. You are not cleared to employ weapons.',{},10)
			TITS.lastAbortMSG[unitName] = t
		end
	else
		local params = {}
		params.unitName = _event.initiator:getName()
		params.releaseHeading =  mist.utils.toDegree(mist.getHeading(_event.initiator)) -- in degrees. Players release heading
		local pos = _event.initiator:getPosition().p
		local height =  land.getHeight({x = pos.x, y = pos.z})
		params.releaseAlt = pos.y - height -- in meters. Release AGL
		params.releasePitch =  mist.utils.toDegree(mist.getClimbAngle(_event.initiator)) -- in degrees. Release dive angle
		params.releaseRoll =  mist.utils.toDegree(mist.getRoll(_event.initiator)) -- in degrees. 
		params.releaseYaw =  mist.utils.toDegree(mist.getYaw(_event.initiator)) -- in degrees. 
		params.releaseSpeed = mist.vec.mag(_event.initiator:getVelocity()) -- meters/second
		params.weapon = _weapon
		params.weponName = _weapon:getTypeName()
		params.weaponID = _weapon:getName()
		params.weaponLastPoint = _weapon:getPoint()
	
		
		timer.scheduleFunction(TITS.TrackWeapon, params,  timer.getTime() +  0.001 ) 					
	end
	return true
end
--############################################################################################################################################
function TITS.StartShootingEvent(_event)
	local unitName = _event.initiator:getName()


	if not TITS.attackingUnits[unitName] then
		local t =  timer.getTime() 
		if (t - TITS.lastAbortMSG[unitName]) > 5 then 
			TITS.messageToUnit(unitName,'Abort! Abort! Abort!. You are not cleared to employ weapons.',{},10)
			TITS.lastAbortMSG[unitName] = t
		end
	else
		TITS.isStrafingAttack[unitName] = true
	end
	return true
end
--############################################################################################################################################
function TITS.HitEvent(_event)
	local unitName = _event.initiator:getName()
	local eventTarget = _event.target 
	local isStrafingWeapon = string.find(_event.weapon:getTypeName():lower(), "weapons.shell")
	local targetName = ''
	
	if eventTarget then
		targetName = eventTarget:getName()
	end
	
	
	if TITS.attackingUnits[unitName] and targetName ~= '' then	
		if isStrafingWeapon then 
			local list = TITS.strafingHitCounter[unitName]
			for t,v in pairs(list) do
				
				if t == targetName then
					
					TITS.strafingHitCounter[unitName][targetName] = TITS.strafingHitCounter[unitName][targetName] + 1
					break
				end
			end
		else -- it goes big boom	
			local target = TITS.getTarget(targetName)
			if target then
				if target.bda then
					-- record the target that got splashed by the weapon BDA
					local r = {
									weaponID = _event.weapon:getName()
								,	weaponType = _event.weapon:getTypeName()
								,	Target = targetName
							}				
					table.insert(TITS.reportWeaponsHits[unitName],r)

				end
			end
		end -- if isStrafingWeapon then 
	end
	
	return true
end
--############################################################################################################################################
function TITS.ReportAttack(_args)
	local unitName = _args[1]
	local value = _args[2]
	local groupID = Unit.getByName(unitName):getGroup():getID()
	
	TITS.passCounter[unitName] = TITS.passCounter[unitName] + 1

	TITS.attackingUnits[unitName] = (value == 'in')
	if TITS.attackingUnits[unitName] then
		TITS.messageToUnit(unitName,'Roger. Cleared in hot',{},10)
		-- reset non-strafing results
		TITS.ResetStrafingHitCounter(unitName)
		TITS.reportWeaponsDistance[unitName] = {}
		TITS.reportWeaponsHits[unitName] = {}
		missionCommands.removeItemForGroup(groupID, TITS.rollInPath[unitName])
		TITS.offPath[unitName] =  missionCommands.addCommandForGroup(groupID,"Off - attack completed"	,  TITS.rootPath[unitName], TITS.ReportAttack		, {unitName,'off'})		
	else
		TITS.messageToUnit(unitName,'Roger. Standby for report',{},10)

		TITS.ReportAttackResults(unitName)
		
		missionCommands.removeItemForGroup(groupID, TITS.offPath[unitName])
		TITS.rollInPath[unitName] = missionCommands.addCommandForGroup(groupID,"Rolling in"				,  TITS.rootPath[unitName], TITS.ReportAttack		, {unitName,'in'})
	end
	return true
end
--############################################################################################################################################
function TITS.ReportAttackResults(_unitName)
	local unit = Unit.getByName(_unitName)
	local player = unit:getPlayerName()	
	local dist_uom 
	
	if TITS.uom[_unitName] == 1 then
		dist_uom = 'm'
	elseif TITS.uom[_unitName] == 2 then
		dist_uom = 'ft'
	else
		dist_uom = 'ft'
	end
	-- Strafing results
	local strafingResults = ''
	local unitTargetList = TITS.strafingHitCounter[_unitName]
	if TITS.strafingHitCounter[_unitName] ~= nil then
		for t,v in pairs(unitTargetList) do
			if v > 0 then
				local target = TITS.getTarget(t)
				if target then
					strafingResults = strafingResults..string.format("\n%s,  %i hit(s)",target.name,v)
				end
			end
		end
	end
	
	if TITS.isStrafingAttack[_unitName] then
		if strafingResults == '' then
			strafingResults = 'no targets hit'
		end
		strafingResults = 'Strafing attack: '.. strafingResults
	end 
	
-- Impact distace results and BDA
	
	local distanceResult = ''
	
	for _,r in pairs(TITS.reportWeaponsDistance[_unitName]) do
		
		local impact = 'Miss'
		local targetsHit = ''
		if r.impactDistance <= TITS.MaxMissDistance  then
			impact = string.format("%s %s of %s @ %s o'clock"
					, math.floor(TITS.convertDistance(_unitName,r.impactDistance)) 
					, dist_uom
					, r.closestTarget 
					, r.impactDirection 
			)
		end 
		------ BDA
		local targetsHit = ''
		for _,h in pairs(TITS.reportWeaponsHits[_unitName]) do
			if h.weaponID == r.weaponID then
				if not string.find(targetsHit, h.Target) then
					if targetsHit ~= '' then
						targetsHit = targetsHit..', '
					end
					targetsHit = targetsHit..h.Target
				end			
			end			 			
		end
		if targetsHit == '' then
			targetsHit = 'none'
		end
		
		local tempStr = string.format( ">>> %s   : %s"								   
						, r.weaponType 
						, impact
					)
		if TITS.DisplayDBA[_unitName] then
			tempStr = string.format("%s\n     Targets hit: %s",tempStr,targetsHit)
		end
		
		
		-- Release parameters
		local alt = string.format("%s",math.floor(TITS.convertDistance(_unitName,r.releaseAlt )+0.5))
		local Speed = string.format("%s",math.floor(TITS.convertSpeed(_unitName,r.releaseSpeed  )+0.5))
		if TITS.uom[_unitName] == 1 then
			 alt = alt..' m'
			 Speed = Speed..' kph'
		elseif TITS.uom[_unitName] == 2 then
			alt = alt..' ft'
			Speed = Speed..' knots'
		else
			alt = alt..' ft'
			Speed = Speed..' mph'
		end
		local Pitch = string.format("%s°",math.floor((r.releasePitch+0.05) *100 )/100)
		local Roll = string.format("%s°",math.floor((r.releaseRoll +0.05) *100 )/100)
		local Yaw = string.format("%s°",math.floor((r.releaseYaw  +0.05) *100 )/100)
		local relP = string.format("     Release Parameters:\n     Alt: %s AGL     Speed: %s\n     P: %s  R:%s  Y:%s"
								   , alt
								   , Speed
								   , Pitch
								   , Roll
								   , Yaw
								  )
		
		if TITS.DisplayReleaseData[_unitName] then
			tempStr = string.format("%s\n%s",tempStr,relP)
		end
	
		if tempStr ~= '' then
			distanceResult = distanceResult..'\n'..tempStr
		end
	end


	local results = ''
	if strafingResults ~= '' then
		results = strafingResults..'\n\n'
	end
	if distanceResult ~= '' then
		results = results..distanceResult..'\n\n'
	end

	TITS.messageToUnit(_unitName,results,{},45)
	return true
end
--############################################################################################################################################
function TITS.messageToUnit(_unitName,_messageText,_soundTable,_displayTime)
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

	return true
end
--############################################################################################################################################
function TITS.Settings(_args)
	local unitName = _args[1]
	local setting = _args[2]

	if setting ==  1 then -- Toggle non strafing hits report
		TITS.DisplayDBA[unitName] = not TITS.DisplayDBA[unitName] 		
		if TITS.DisplayDBA[unitName] then
			TITS.messageToUnit(unitName,'Non-strafing hits (BDA) reports is ON')
		else
			TITS.messageToUnit(unitName,'Non-strafing hits (BDA) reports is OFF')
		end
	elseif setting == 2 then -- Toggle display of Release data
		TITS.DisplayReleaseData[unitName] = not TITS.DisplayReleaseData[unitName] 		
		if TITS.DisplayReleaseData[unitName] then
			TITS.messageToUnit(unitName,'Release data display is ON')
		else
			TITS.messageToUnit(unitName,'Release data display is OFF')
		end
	elseif setting == 3 then -- use metric units
		TITS.uom[unitName] = 1 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
		TITS.messageToUnit(unitName,'Using metric units')
	elseif setting == 4 then -- use imperial units(knots)
		TITS.uom[unitName] = 2 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
		TITS.messageToUnit(unitName,'Using imperial units (knots)')
	elseif setting == 5 then -- use imperial units(mph
		TITS.uom[unitName] = 3 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
		TITS.messageToUnit(unitName,'Using imperial units (mph)')
	end -- main if
	return true
end
--############################################################################################################################################
function TITS.ResetStrafingHitCounter(_unitName)

	TITS.isStrafingAttack[_unitName] = false
	for _,t in pairs(TITS.TargetList) do
		if t.strafing and t.type ==  'unit' then
			u = Unit.getByName(t.name)
			if u then
				if  TITS.strafingHitCounter[_unitName] == nil then
					TITS.strafingHitCounter[_unitName] = {}
				end
				TITS.strafingHitCounter[_unitName][t.name] = 0
			-- else ignore it, doesn't exists
			end -- if u then
		end -- if t.strafing and type ==  'unit'then
		
	end

	return true
end
--############################################################################################################################################
function TITS.getTarget(_name)
	for _,t in pairs(TITS.TargetList) do
		if t.name  == _name then
			return t
		end
	end
	return nil
end
--############################################################################################################################################
function TITS.TrackWeapon(params,time)	
	
	 local _status,_weaponPos =  pcall(function()
									return params.weapon:getPoint()
									end)
	if _status then
		-- weapon still in fly, update last point
		params.weaponLastPoint = _weaponPos
		return timer.getTime() + 0.001 -- keep tracking		
	else -- wepon hit
		local target 
		local targetPos
		local tempTarget 
		local tempDist = nil
		local tempPos
		-- weapon had no valid target so look for the closest to impact
		for t,v in pairs(TITS.TargetList) do
			if v.impact then -- impact tracking target
				local oTarget
				local oTargetPos

				if v.type == 'unit' then
					oTarget = Unit.getByName(v.name)
					oTargetPos = oTarget:getPoint()
				else -- it's a zone
					oTarget = trigger.misc.getZone(v.name)
					oTargetPos = oTarget.point
				end		-- if v.type == 'unit' then	
				local d =  math.floor(TITS.getDistance(params.weaponLastPoint,oTargetPos)) -- in meters
				if  tempDist then
					if d < tempDist then
						tempTarget = v.name
						tempPos = oTargetPos
						tempDist = d
					end -- if d < tempDist then
				else -- if  tempDist then
					tempTarget = v.name
					tempPos = oTargetPos
					tempDist = d
				end -- if not tempDist then
			end --if v.impact then -- impact tracking target
		end -- for t,v in pairs(TITS.TargetList) do
		target = tempTarget
		targetPos = tempPos

		
		local _impactDistance = math.floor(TITS.getDistance(params.weaponLastPoint,targetPos)) -- in meters
		local _direction = TITS.getRelativeDirection(params.releaseHeading ,targetPos,params.weaponLastPoint)
		_direction = TITS.getClockDirection(_direction)
		
		-- store the data
		
		local r = {
						weaponID = params.weaponID 
					,	weaponType = params.weponName 
					,	intendedTarget = 'unk'
					,	closestTarget = target
					, 	impactDistance = _impactDistance
					, 	impactDirection = _direction
					,	releaseHeading = params.releaseHeading
					,	releaseAlt = params.releaseAlt
					,	releaseSpeed = params.releaseSpeed
					, 	releasePitch = params.releasePitch
					, 	releaseRoll = params.releaseRoll
					, 	releaseYaw = params.releaseYaw
		}
		if params.weponHasTarget then
			r.intendedTarget = params.target:getName()
		end
		table.insert(TITS.reportWeaponsDistance[params.unitName],r)
		return nil
	end
end
--############################################################################################################################################
function TITS.convertSpeed(_unitName,_speed)
	local s
	 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
	if TITS.uom[_unitName] == 1 then
		s = _speed * 3.6
	elseif TITS.uom[_unitName] == 2 then
		s = _speed * 1.943844
	else
		s = _speed * 2.23694
	end
	return s
end
--############################################################################################################################################
function TITS.convertDistance(_unitName,_distance)
	local s
	 -- 1 metric (kph), 2 imperial (knots) , 3 imperial (mph)
	if TITS.uom[_unitName] == 1 then
		s = _distance 
	else
		s = _distance * 3.28084
	end
	return s
end
--############################################################################################################################################
function TITS.getDistance(_point1, _point2)

    local xUnit = _point1.x
    local yUnit = _point1.z
    local xZone = _point2.x
    local yZone = _point2.z

    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone

    return math.sqrt(xDiff * xDiff + yDiff * yDiff)
end
--############################################################################################################################################
function TITS.getRelativeDirection(_refHeading,_point1, _point2)
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
--############################################################################################################################################
function TITS.getClockDirection(_direction)
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
--############################################################################################################################################
function TITS.getDirection(_point1, _point2)
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
    
    
 env.info("xDiff "..xDiff.." yDiff "..yDiff)    
    return tgtBearing
end
--############################################################################################################################################



--############################################################################################################################################
-- Main Body
world.addEventHandler(TITS.eventHandler)