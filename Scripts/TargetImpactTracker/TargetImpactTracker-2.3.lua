TITS  = {}
TITS.Version = '2.3.01'


--###################################################################################################################################################
-- #############	DCS - Target Impact Tracker Script																				################# 
-- #############	by Draken35																										################# 
--###################################################################################################################################################
--[[ Requirements:	
		>>>	 MIST 4.5.107 or above <https://github.com/mrSkortch/MissionScriptingTools/tree/master>
	
--]]
-----------------------------------------------------------------------------------------------------------------------------------------------------
--[[ Version history
	2.0.00		03/04/2022	Development starts
	2.0.01		05/03/2022	First release
	2.0.02		05/04/2022	Added uncorrected impact position and warhead category to weaponsFire
	2.1.00		05/10/2022	- Fired weapons grouping improvements
							- Results API
							- Added check on getAmmo to prevent ED bug ( getAmmo returns only 1 shell type for combat mix - A10C) 
							  from crashing the script.
	2.1.01		05/11/2022	- Fixed "no effect" message when target is killed by the weapon
							  (dead objects are not triggering hit event at this time)
	2.1.02		05/12/2022	- Fixed missing shell count when using "combat mix" type of loads
	2.2.00		05/15/2022	- Shell Burst recording
							- new fired shell counting method / remove need for pass end
							- added capture of shells display name and use it in the API if available
	2.2.01		05/16/2022	- Added release data for last shell burst in pass
	2.2.02		05/18/2022	- Added TargetImapct table to getGroupData
	2.3.00		07/27/2022	- Added roll-in position tracking
							- added polygonal zone targets types
	2.3.01		09/10/2022	- Fixed issue with recording strafing hits with unlimited ammo (star shooting event is not longer populating weapon name - ED issue)
--]]
-----------------------------------------------------------------------------------------------------------------------------------------------------
--[[ Results API

	count,{} = TITS.getWeponsFired(_unitName) 
		 returns simple table of weapons IDs fired in the pass 
		 
		 
		 
		 
		 
		 
		 
		 
	TITS.getWeponsInFlight() 
		 returns simple table of weapons IDs fired in the pass 
		 
	TITS.getWeaponData(WeaponID)
		returns a complex object with the following data for the specific WeaponID:
				weaponType
			,	releasePitch
			,	releaseYaw
			,	releaseRoll
			,	releaseHeading
			,	releaseSpeed
			,	releasePosition
			,	timeStamp
			, 	inFlight 
			,	unImpactPos  -- uncorrected position
			,	avgImpactPos  -- average corrected position
			,	group
			,	targetsHitList -- List of target hit by the weapon
			,	closestTargetHit -- complex object with:
								{
										target  
									,	distance (from corrected position to target)
									,	bearing	 (true degrees, from corrected position to target)
									,   slantRange (from release position to target)
								
								}
			,	TargetsHit -- complex object list with:
								{
										target  
									,	distance (from corrected position to target)
									,	bearing	 (true degrees, from corrected position to target)
									,   slantRange (from release position to target)
								
								}
								
		TITS.getWeaponGroupsFired()
			returns complex list of 
				{
						groupId
					,	weaponType
					,	quantityFired
				}
				
		TITS.getWeaponGroupsFiredData()
			returns complex list with
				{
						groupId
					,	weaponType
					,	quantityFired
					,	avgReleasePitch
					,	avgReleaseYaw
					,	avgReleaseRoll
					,	avgReleaseHeading
					,	avgReleaseSpeed
					,	avgReleasePosition
					,	groupPosition -- group center
					,	weaponList -- list of id of weapons in group 
					,	targetsHitList -- List of target hit by the weapon
					,	closestTargetHit -- complex object with:
										{
												target  
											,	distance (from group position to target)
											,	bearing	 (true degrees, from group position to target)
											,   slantRange (from avg release position to target)
										
										}
					,	TargetsHit -- complex object list with:
										{
												target  
											,	distance (from group position to target)
											,	bearing	 (true degrees, from group position to target)
											,   slantRange (from avg release position to target)
										
										}					
				}

--]]

--[[ Pass Data return tables
			Tables:
			shellsFired 	 	-- initial count of rounds per shell type at pass Start, updated to rounds fired in the pass at pass End
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
											,	impactPos  -- uncorrected
											,	group
										}
			
			weaponHits			-- per target per weapon , updated by hit event if TITS.onPass[_unitName] == true
				weaponHits[WeaponID][Target] = 	timeStamp				
						
			
			impactData		-- per target per weapon 
				impactData[WeaponID][Target] = {
													targetPosition
												,	impactPosition	
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
	TITS.TargetTrackingInterval  	= 	1 		-- in seconds. Time in between target checks
	TITS.WeaponTrackingInterval	 	=  	0.001 	-- in seconds. Time in between weapon tracking checks
	TITS.MaxMissDistance 			= 	1000 	-- meters. Any impact over this distance from the closest target will be considered as Miss
	TITS.MaxCorrectionDistance		=	15		-- meters
	TITS.weaponGroupInterval		=	1.5		-- in seconds. Minimun time between weapons shots to be considered a new group

--#################################################################################################################################################
-- #############   Initialization of globals   																						############### 
--#################################################################################################################################################
	TITS.TargetList = {}
	TITS.PassData = {} 
	TITS.onPass = {}
	TITS.lastOSclock = timer.getTime()
	TITS.avgTrackTic = 0

	
--#################################################################################################################################################
-- #############  Event Handler & weapon tracking 																					############### 
--#################################################################################################################################################
	TITS.coreEventHandler = {}
	function TITS.coreEventHandler:onEvent(_eventDCS)

		if _eventDCS == nil or _eventDCS.initiator == nil then
			return true
		end

		local status, err = pcall(function(_event)

				if (_event.id == world.event.S_EVENT_SHOT) and _event.initiator:getPlayerName()  then -- id == 1 Shot
					
					TITS.ShotEvent(_event)

				elseif  _event.id == world.event.S_EVENT_HIT and _event.initiator:getPlayerName()  then  -- id == 2 Hit
				 
					TITS.HitEvent(_event)
					
				elseif  _event.id == world.event.S_EVENT_SHOOTING_START and _event.initiator:getPlayerName()  then  -- id == 2 Hit
				 
					TITS.ShootingStart(_event)

				elseif  _event.id == world.event.S_EVENT_SHOOTING_END and _event.initiator:getPlayerName()  then  -- id == 2 Hit
				 
					TITS.ShootingEnd(_event)
								
				end --if (_event.id == world.event.S_EVENT_SHOT) and _event.initiator:getPlayerName()  then
			  -- ### End event processing

				return true
		end, _eventDCS) --  local status, err = pcall(function(_event)

		if (not status) then 
			local msg = string.format("Target Impact Tracker (v%s): Error while handling event %s",TITS.Version, err)
			env.error(msg,false)
		end
	end
	--=============================================================================================================================================
	function TITS.ShotEvent(_event)
		local _weapon = _event.weapon
		local _unitName = _event.initiator:getName()
		local data = TITS.PassData[_unitName] 
		-- recond weapon fired and release data
			
		if TITS.onPass[_unitName] then	
		
			if -- check for new group
				(data.lastWPNfired ~= _weapon:getTypeName()) or
				(timer.getTime()  - data.lastWPNts) > TITS.weaponGroupInterval			
			then
				data.lastWPNfired = _weapon:getTypeName()
				data.lastWPNts = timer.getTime()
				data.groupId = data.groupId + 1 
				data.groups[data.groupId] = {}
			end
		
			
			table.insert(data.groups[data.groupId],_weapon:getName())
		
		
			local r = {
								weaponType 		= _weapon:getTypeName()
							,	releasePitch 	= mist.utils.toDegree(mist.getClimbAngle(_event.initiator))
							,	releaseYaw 		= mist.utils.toDegree(mist.getYaw(_event.initiator))
							,	releaseRoll 	= mist.utils.toDegree(mist.getRoll(_event.initiator)) 
							,	releaseHeading 	= mist.utils.toDegree(mist.getHeading(_event.initiator)) 
							,	releaseSpeed 	= mist.vec.mag(_event.initiator:getVelocity()) 
							,	releasePosition = _event.initiator:getPosition().p
							,	timeStamp 		= timer.getTime() 
							,	inFlight 		= true 
							,	impactPos		= {}
							,	groupId			= data.groupId 
						}
			
			data.weaponsFired[_weapon:getName()] = r
			
			-- start tracking weapon
			local params = {}
			params.unitName = _event.initiator:getName()
			params.launchPos = _event.initiator:getPosition().p
			params.weapon = _weapon
			params.weaponID = _weapon:getName()
			params.weaponLastPoint = _weapon:getPoint()
			params.weaponLastVelocity = _weapon:getVelocity()
		
			TITS.lastOSclock = timer.getTime()
			TITS.avgTrackTic = 0
			timer.scheduleFunction(TITS.TrackWeapon, params,  timer.getTime() +  TITS.WeaponTrackingInterval ) 	
		end --if TITS.onPass[_unitName] then	
	end -- function
	--=============================================================================================================================================
	function TITS.HitEvent(_event)
		local unitName = _event.initiator:getName()
		local eventTarget = _event.target 
		local shellType = _event.weapon:getTypeName()
		local isStrafingWeapon = string.find(_event.weapon:getTypeName():lower(), "weapons.shell")
		local targetName = ''
		local data = TITS.PassData[unitName] 
		
		if eventTarget then
			targetName = eventTarget:getName()
		end
		
		if targetName ~= '' and TITS.onPass[unitName] then	
			if isStrafingWeapon then 
				local ts = data.shellHits[targetName]
				if not ts then
					target = TITS.TargetList[targetName]
					if target then
						if target.strafing then
							data.shellHits[targetName] = {}
							ts = data.shellHits[targetName]		
						end
					end
				end
				if ts then
					if ts[shellType] then
						data.shellHits[targetName][shellType] = data.shellHits[targetName][shellType] + 1
					else
						data.shellHits[targetName][shellType] = 1
					end
				end
				local desc = _event.weapon:getDesc()
				if desc then
					data.shellDisplayName[shellType] = desc.displayName
				end
			else -- it goes big boom	
				local target = TITS.getTargetObj(targetName)
				if target then
					-- record the target that got splashed by the weapon
					local t = TITS.TargetList[targetName]
					if t.bda then
						if not data.weaponHits[_event.weapon:getName()] then
							data.weaponHits[_event.weapon:getName()] = {}
						end
						
						data.weaponHits[_event.weapon:getName()][targetName] = timer.getTime() 
					end -- if t.bda then
				end -- if target then
			end -- if isStrafingWeapon then 
		end -- if targetName ~= '' and TITS.onPass[unitName] then	
		
		return true
	end -- function
	--=============================================================================================================================================
	function TITS.ShootingStart(_event)
		local _unitName = _event.initiator:getName()
		local unit = Unit.getByName(_unitName)
		local data = TITS.PassData[_unitName] 
		local ammoTable = unit:getAmmo()

		for _,v in pairs (ammoTable) do
			local t = v.desc	
			if string.find(t.typeName:lower(), "weapons.shell") then
			
				if _event.weapon_name then
					if data.shellsFired[_event.weapon_name]  then
						data.shellsFired[_event.weapon_name].init = v.count
					else		
						data.shellsFired[_event.weapon_name] = {
									init = v.count
								,	fired = 0
							}
					end
				else 
					if data.shellsFired[t.typeName]  then
						data.shellsFired[t.typeName].init = v.count
					else		
						data.shellsFired[t.typeName] = {
									init = v.count
								,	fired = 0
							}
					end
				end -- if _event.weapon_name then
			end--if string.find(t.typeName:lower(), "weapons.shell") then
		end -- for _,v in pairs (ammoTable) do
		

		data.LBreleasePitch 	= mist.utils.toDegree(mist.getClimbAngle(_event.initiator))
		data.LBreleaseYaw 		= mist.utils.toDegree(mist.getYaw(_event.initiator))
		data.LBreleaseRoll 		= mist.utils.toDegree(mist.getRoll(_event.initiator)) 
		data.LBreleaseHeading 	= mist.utils.toDegree(mist.getHeading(_event.initiator)) 
		data.LBreleaseSpeed 	= mist.vec.mag(_event.initiator:getVelocity()) 
		data.LBreleasePosition 	= _event.initiator:getPosition().p		

		
	end -- function
	--=============================================================================================================================================
	function TITS.ShootingEnd(_event)
		local _unitName = _event.initiator:getName()
		local unit = Unit.getByName(_unitName)
		local data = TITS.PassData[_unitName] 
		local ammoTable = unit:getAmmo()		
		local shellFounds = false
		
		data.lastShellFired	= timer.getTime()
		
		if ammoTable then
			for _,v in pairs (ammoTable) do
				local t = v.desc	
				if string.find(t.typeName:lower(), "weapons.shell") then
					shellFounds = true
					d = data.shellsFired[t.typeName]
					data.shellDisplayName[t.typeName] = t.displayName
					if d then
						d.fired = d.init - v.count
					end
				end
			end -- for _,v in pairs (ammoTable) do
		end

		if not ammoTable or not shellFounds then
			for _,d in pairs(data.shellsFired) do
				d.fired = d.init
			end
		end

	end -- function
	--=============================================================================================================================================
	function TITS.TrackWeapon(params,time)	
		local OSclock = timer.getTime()
		TITS.avgTrackTic = (TITS.avgTrackTic + (OSclock-TITS.lastOSclock))/2
		TITS.lastOSclock =  OSclock 
	
		local _status,_weaponData, _weaponVel =  pcall(function()
													return {params.weapon:getPoint(),params.weapon:getVelocity()}
												end)	
		if _status then
			params.weaponLastPoint = _weaponData[1]
			params.weaponLastVelocity =  _weaponData[2]
			return timer.getTime() + TITS.WeaponTrackingInterval -- keep tracking	
		else -- if _status then (weapon not longer exists)
			local data = TITS.PassData[params.unitName] 
			data.lastImpact	= timer.getTime()
			
			data.weaponsFired[params.weaponID].inFlight = false
			for targetName,targetData in pairs (TITS.TargetList) do
				if targetData.detected and targetData.impact then
					if (not targetData.dead) or ((targetData.dead) and ((targetData.dead >= data.timestamp))) then
						local targetPos = TITS.getTargetPos(targetName)
						local targetVel = TITS.getTargetVel(targetName)
						local ImpactPos = params.weaponLastPoint
						data.weaponsFired[params.weaponID].impactPos = ImpactPos
						local weaponVel = params.weaponLastVelocity
						local impactDistance = mist.utils.get3DDist(ImpactPos,targetPos)
						if impactDistance <= TITS.MaxMissDistance then
							
							ImpactPos = mist.vec.add(ImpactPos ,mist.vec.scalar_mult(weaponVel, TITS.WeaponTrackingInterval  ))

							if impactDistance <= TITS.MaxCorrectionDistance	then -- weapon hit the target's collision box, correct the impact							
								if params.weaponLastVelocity.y ~= 0  then		
									-- correct Weapon and Target position
									local deltaY = math.abs(ImpactPos.y - targetPos.y)
									local flightTime = math.abs(deltaY / weaponVel.y)					
									ImpactPos = mist.vec.add(ImpactPos ,mist.vec.scalar_mult(weaponVel , flightTime ))				
									targetPos = mist.vec.add(targetPos ,mist.vec.scalar_mult(targetVel, flightTime ))
								end -- params.weaponLastVelocity.y ~= 0			
								impactDistance = mist.utils.get3DDist(ImpactPos,targetPos)		
							
							end	-- if impactDistance <= TITS.MaxCorrectionDistance	then	
							
							-- check if the target is dead, and if so, record a hit
							if TITS.getTargetLife(targetName) == 0 then
							
								if not data.weaponHits[params.weaponID] then
									data.weaponHits[params.weaponID] = {}
								end						
								data.weaponHits[params.weaponID][targetName] = timer.getTime() 
							end	
							--record the impact
							if not data.impactData[params.weaponID] then
								data.impactData[params.weaponID] = {}
							end
							
							data.impactData[params.weaponID][targetName] = {
															targetPos = targetPos
														,	impactPos = ImpactPos	
														,	impactDistance = impactDistance
														,	timestamp = timer.getTime() 
													}
							-- see if target is a zone and the impact is with the radius
							if targetData.type == 'zone' and targetData.bda then
								local zone = trigger.misc.getZone(targetName)
								if impactDistance <= zone.radius then
									
									if not data.weaponHits[params.weaponID] then
										data.weaponHits[params.weaponID] = {}
									end				
									data.weaponHits[params.weaponID][targetName] = timer.getTime() 
								end
							end -- if targetData.type = 'zone' then
							if targetData.type == 'poly' and targetData.bda then
								if mist.pointInPolygon(ImpactPos,TITS.getTargetObj(targetName), 1000) then
									
									if not data.weaponHits[params.weaponID] then
										data.weaponHits[params.weaponID] = {}
									end				
									data.weaponHits[params.weaponID][targetName] = timer.getTime() 
								end
							end -- if targetData.type = 'poly' then
													
						end -- 	if impactDistance <= TITS.MaxMissDistance then
					end --if (not targetData.dead) or ((targetData.dead) and ((targetData.dead >= data.timestamp))) then
				end --  if targetData.detected and targetData.impact then
			end	-- for targetName,targetData in pairs (TITS.TargetList) do
		end -- if _status then
	
	end -- function
--
--#################################################################################################################################################
-- #############  target functions  																								############### 
--#################################################################################################################################################
--
	function TITS.AddTarget(
				_TargetName					-- UNIQUE! Target name
			,	_DisplayName				-- display name, accepts duplicates, if empty _TargetName will be used
			,	_Type						-- [ unit | zone | static ] must be in lower case
			,	_Respawn					-- Only for units. if true, unit can be respawned. Respwan will only happen when ALL the units in the group are destroyed
			,	_TrackImpact				-- use target to calculate distance to impact
			,	_TrackStrafing				-- count strafing hits on target
			,	_ReportHits					-- reports splash damage from weapons
			,	_desZone					-- designation zone
			,	_AllowSmokeDesignation		-- Allow use of smoke designation for target
			,	_AllowLaserDesignation		-- Allow use of laser designation for target
			,	_AllowIRDesignation			-- Allow use of IR designation for target
			,	_AllowNoMarkDesignation		-- Allow use of target designation with no marks (provides coordinates)
			,	_AllowListCoordinates		-- Allow list of target coordinates
			,	_uiNum1						-- Numeric value for custom UI use
			,	_uiNum2						-- Numeric value for custom UI use
			,	_uiNum3						-- Numeric value for custom UI use
			,	_uiBool1					-- Boolean value for custom UI use
			,	_uiBool2					-- Boolean value for custom UI use
			,	_uiBool3					-- Boolean value for custom UI use
			,	_uiText1					-- Text value for custom UI use
			,	_uiText2					-- Text value for custom UI use
			,	_uiText3					-- Text value for custom UI use
		)
							
		local dn = _DisplayName
		if dn == '' then
			dn = _TargetName
		end
		
		local life0 = 100
		if _Type == 'static' then
			local obj = StaticObject.getByName(_TargetName)
			if obj then
				life0 = obj:getLife()
			end
		end
		
		local gpn = ''
		if _Type == 'unit' then
			local u = Unit.getByName(_TargetName)
			gpn = u:getGroup():getName()
		end
		
		
		local v = {
					name	 	= 	_TargetName,
					displayName = 	dn,
					type 		= 	_Type, 
					respawn		=	_Respawn,
					impact 		=	_TrackImpact,	
					strafing 	= 	_TrackStrafing, 	
					bda 		= 	_ReportHits,		
					des_zone	= 	_desZone,
					des_wp 		= 	_AllowSmokeDesignation,	
					des_laser 	= 	_AllowLaserDesignation,	
					des_ir		=	_AllowIRDesignation,
					des_nomark	= 	_AllowNoMarkDesignation,
					list_coor 	= 	_AllowListCoordinates,
					uiNum1		=	_uiNum1,
					uiNum2		=	_uiNum2,
					uiNum3		=	_uiNum3,
					uiBool1		=	_uiBool1,
					uiBool2		=	_uiBool2,
					uiBool3		=	_uiBool3,
					uiText1		=	_uiText1,
					uiText2		=	_uiText2,
					uiText3		=	_uiText3,


					-- internal use attributes
					detected 	= 	nil,-- Detected = target detected as alive
					dead 		= 	nil,-- Dead = dead detection time 
					life0		= 	life0	, -- initial life for statics & zones
					groupName	= 	gpn,
					lastPos		=	{},	
					lastVel		=	{}
		}
		TITS.TargetList[_TargetName] = v
		
	end -- function
	--=============================================================================================================================================
	function TITS.respawnTarget(_TargetName, _override)
		local tgt = TITS.TargetList[_TargetName]

		if tgt then
			if tgt.type == 'unit' and (tgt.respawn or _override)  and tgt.dead then
				if not Group.getByName(tgt.groupName) then
					mist.respawnGroup(tgt.groupName, true)
					tgt.dead = nil
					tgt.detected = timer.getTime()
				end
			end
		end
	end -- function
	--=============================================================================================================================================
	function TITS.getTargetObj(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = nil
		
		if tgt.type == 'unit' then 
			obj = Unit.getByName(_TargetName)
		elseif tgt.type == 'static' then 
			obj = StaticObject.getByName(_TargetName)
		elseif tgt.type == 'zone' then
			obj = trigger.misc.getZone(_TargetName)
		elseif tgt.type == 'poly' then
			local u =  Unit.getByName(_TargetName)
			local g = u:getGroup()
			obj = mist.getGroupPoints(g:getName())
		end
		return obj
	end -- function
	--=============================================================================================================================================
	function TITS.getTargetLife(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = TITS.getTargetObj(_TargetName)
		local life = 0
		
		if obj then
			if tgt.type	== 'unit' or tgt.type == 'static' then 
				life = obj:getLife()
			elseif tgt.type == 'zone' then
				life = 100
			elseif tgt.type == 'poly' then
				life = 100
			end
		end
		return life
	end -- function
	--=============================================================================================================================================
	function TITS.getMaxTargetLife(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = TITS.getTargetObj(_TargetName)
		local life = 0
		
		if obj then
			if tgt.type	== 'unit'  then
				life = obj:getLife0()
			elseif tgt.type == 'static' or tgt.type == 'zone' then 
				life = tgt.life0
			end
		end
		return life
	end -- function
	--=============================================================================================================================================	
	function TITS.targetExists(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = TITS.getTargetObj(_TargetName)
		local exists = false
		
		if obj then
			if tgt.type	== 'unit' or tgt.type == 'static' then 
				exists = obj:isExist()
			elseif tgt.type == 'zone' then
				exists = true
			elseif tgt.type == 'poly' then
				exists = true
			end
		end
		return exists
	end -- function
	--=============================================================================================================================================
	function TITS.getTargetPos(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = TITS.getTargetObj(_TargetName)
		local Pos = nil
		
		if obj then
			if tgt.type	== 'unit' or tgt.type == 'static' then 
				Pos = obj:getPoint()
			elseif tgt.type == 'zone' then
				Pos = mist.utils.makeVec3GL(obj.point)
			elseif tgt.type == 'poly' then
				local n = 0
				Pos =  {x=0,y=0,z=0}
				for _,p in pairs(obj) do
					n = n + 1
					Pos =  mist.vec.add(Pos, mist.utils.makeVec3GL(p))
				end
				if n > 0 then
					Pos = mist.vec.scalar_mult(Pos , 1 / n)
				end
				
			end
		else -- if obj then
			-- target is dead
			Pos = tgt.lastPos
		end -- if obj then
		return Pos
		
	end -- function
	--=============================================================================================================================================
	function TITS.getTargetVel(_TargetName)
		local tgt = TITS.TargetList[_TargetName]
		local obj = TITS.getTargetObj(_TargetName)
		local Vel = nil
		
		if obj then
			if tgt.type	== 'unit' or tgt.type == 'static' then 
				Vel = obj:getVelocity()
			elseif tgt.type == 'zone' then
				Vel = { x=0, y=0, z=0}
			elseif tgt.type == 'poly' then
				Vel = { x=0, y=0, z=0}
			end
		else -- if obj then
			-- target is dead
			Vel = tgt.lastVel
		end -- if obj then
		return Vel
	end -- function
	--=============================================================================================================================================
	function TITS.trackTargets(_params,time)
		for k,v in pairs(TITS.TargetList) do
			if v.type ~='zone' and v.type ~='poly'  then
				local o = TITS.getTargetObj(k)
				local life = 0
				if o then
					 life = TITS.getTargetLife(k)
				end
				if life > 0 then
					-- target is alive
					if v.detected == nil then
						-- target detected
						v.detected = timer.getTime()
					end -- if v.Detected == nil then
				--	if v.lastPos == nil or v.lastVel == nil or v.canMove then
					if v.type == 'unit' then
						v.lastPos = TITS.getTargetPos(k)
						v.lastVel = TITS.getTargetVel(k)
					end --if v.type == 'unit' then
				--	end -- if v.lastPos == nil or v.lastVel == nil or v.canMove then			
				else -- 	if o then
					-- target is dead
					if v.detected and v.dead == nil then 
						v.dead = timer.getTime( )
					end -- if v.Detected and v.Dead == nil then 
				end -- if o then
			else
				if v.detected == nil then
						-- target detected
						v.detected = timer.getTime()
					end -- if v.Detected == nil then
			end -- if v.type ~='zone' then
		end -- for k,v in pairs(TITS.TargetList) do

		return timer.getTime() + TITS.TargetTrackingInterval -- keep tracking		
	end -- function
--
--#################################################################################################################################################
-- #############   Pass functions   																								############### 
--#################################################################################################################################################
--
	function TITS.passInit(_unitName)
		local unit = Unit.getByName(_unitName)
		TITS.PassData[_unitName] = {} 

		local r = {
					shellsFired 		= {} 	-- initial count of rounds per shell type at pass Start, updated to rounds fired in the pass at pass End
				,	shellHits 			= {}	-- per target per shell type
				,	shellDisplayName	= {}	-- display name per shell type
				,	weaponsFired		= {}	-- and their release params & designated target at the time, updated by shot event if TITS.onPass[_unitName] == true
				,	weaponHits			= {}	-- per target per weapon , updated by hit event if TITS.onPass[_unitName] == true
				,	impactData			= {}	-- per target per weapon & slant range from launch position
				,	targetHealth		= {}	-- per target at this time
				,	timestamp			= timer.getTime()  -- Pass start time
				,	groupId				= 0		-- fired weapons group counter
				,	lastWPNfired		= ''	-- last weapon TYPE fired
				,	lastWPNts			= 0		-- Last weapon fired time stamp
				,   groups				= {}	-- groups indexing
				,	lastShellFired		= timer.getTime()  -- to control Auto pass end in the UI
				,	lastImpact			= timer.getTime()	-- to control Auto pass end in the UI
				,	LBreleasePitch 		= 0
				,	LBreleaseYaw 		= 0
				,	LBreleaseRoll 		= 0
				,	LBreleaseHeading 	= 0
				,	LBreleaseSpeed 		= {}
				,	LBreleasePosition 	= {}	
				,	rollInPosition		=  unit:getPosition().p 
				
				
				}
				
		
		
		-- init shellsFired
		--[[
		local unit = Unit.getByName(_unitName)
		local ammoTable = unit:getAmmo()
		for _,v in pairs (ammoTable) do
			local t = v.desc	
			if string.find(t.typeName:lower(), "weapons.shell") then
				local c = { init = v.count, fired = 0 }
				r.shellsFired[t.typeName] = c
			end
		end -- for _,v in pairs (ammoTable) do
		]]--
		-- init targetHealth & shellHits
		for k,targetData in pairs (TITS.TargetList) do
			local th = TITS.getTargetLife(k)
			local h = {
						start_health = th
					,	end_health = th
				}
			r.targetHealth[k] = h
			
			--[[ shellHits	
			if targetData.strafing and targetData.type ~= 'zone' then --and TITS.getTargetLife(k) > 0 then
				r.shellHits[k]	= {}
				for v,_ in pairs(r.shellsFired) do
					r.shellHits[k][v] = 0
				end -- for v,_ in pairs(r.shellsFired) do
			end -- if k.strafing then
			--]]
		end -- for k,_ in pairs (TITS.TargetList) do
		
		TITS.PassData[_unitName] = r
	end -- function
	--=============================================================================================================================================
	function TITS.passStart(_unitName)
		TITS.onPass[_unitName] = true
	end -- function
	--=============================================================================================================================================
	function TITS.passEnd(_unitName)
		local weponsInFlight = false
		local d = TITS.PassData[_unitName]
		
		if d.weaponsFired then
			for _,y in pairs(d.weaponsFired) do
				weponsInFlight = weponsInFlight or y.inFlight
			end -- for _,y in pairs(d.weaponsFired) do
		end
		if not weponsInFlight then		
			TITS.onPass[_unitName] = false
			-- update PassData shellsFired
			local unit = Unit.getByName(_unitName)
			local ammoTable = unit:getAmmo()
			local r = d.shellsFired
			local ShellsFounds = false 
			if ammoTable then
				for _,v in pairs (ammoTable) do
					local t = v.desc	
					if string.find(t.typeName:lower(), "weapons.shell") then
						ShellsFounds = true
						local c = r[t.typeName]
						if c then
							c.fired = c.init - v.count  -- rounds fired
						else
							if r[1] then
								r[1].fired = r[1].init - v.count 
							else
								r[t.typeName] = {fired = 0}
							end
							local msg = string.format("Target Impact Tracker (v%s): %s ammo type load error",TITS.Version, t.typeName)
							env.error(msg,false)
						end
					end
				end -- for _,v in pairs (ammoTable) do
			end
			if not ammoTable or not ShellsFounds then
				-- all anmo was used
				for _,v in pairs(r) do
					v.fired = v.init
				end
			end
			
			-- update target health
			for k,targetData in pairs (TITS.TargetList) do
				local th = TITS.getTargetLife(k)
				local h = d.targetHealth[k]
				h.end_health = th
				d.targetHealth[k] = h
			end -- for k,targetData in pairs (TITS.TargetList) do
		end
		return not weponsInFlight
	end -- function
	--=============================================================================================================================================
	function TITS.passGetData(_unitName)
		local r = TITS.PassData
		if r ~= {} then
			r = TITS.PassData[_unitName]
		end
		return r
	end -- function
	--=============================================================================================================================================
	function TITS.weaponsInFlight(_unitName)
		local weponsInFlight = false
		local d = TITS.PassData[_unitName]
		
		if d.weaponsFired then
			for _,y in pairs(d.weaponsFired) do
				weponsInFlight = weponsInFlight or y.inFlight
			end -- for _,y in pairs(d.weaponsFired) do
		end
		return weponsInFlight
	end -- function
--
--#################################################################################################################################################
-- #############   Results API  	   																								############### 
--#################################################################################################################################################
--
	function TITS.getWeponsFired(_unitName)
		local wftable = {}
		local count = 0
		
		
		local data = TITS.passGetData(_unitName)
		if TITS.rowCount(data) > 0   then
			local wf = data.weaponsFired
			local r = {}
			
			if TITS.rowCount(wf) > 0 then
				for wID,_ in pairs(wf) do
					count = count + 1
					wftable[wID] = wID
				end
			end		
			
		end --if data ~= {} then		
		r = {count = count, list = wftable}
		return r
		
	end -- function
--=============================================================================================================================================	
	function TITS.getWeaponData(_unitName, _weaponID)
		--[[
					weaponType
				,	releasePitch
				,	releaseYaw
				,	releaseRoll
				,	releaseHeading
				,	releaseSpeed
				,	releasePosition
				, 	inFlight 
				,	impactPos  -- uncorrected
				,	group			
				,	impacts[target]
						  target
						, targetPos
						, hit
						, distance
						, impactPos -- corrected
				, 	closestTarget
				, 	miss  -- no impacts close to targets
				,	avgImpactPos  -- corrected
				,   targetsHit 
				, 	rollInDistance -- to closest target
				, 	rollInAltitudeAT -- Altitude above closest target
		--]]
		local data = TITS.passGetData(_unitName)
		local wData = data.weaponsFired[_weaponID]
		local wHits= data.weaponHits[_weaponID]	
		local r = {}
		if wData then
			r = {
					weaponType = wData.weaponType
				,	releasePitch = wData.releasePitch
				,	releaseYaw = wData.releaseYaw
				,	releaseRoll = wData.releaseRoll
				,	releaseHeading = wData.releaseHeading
				,	releaseSpeed = wData.releaseSpeed
				,	releasePosition = wData.releasePosition
				, 	inFlight = wData.inFlight 
				,	impactPos = wData.impactPos  -- uncorrected
				,	group = wData.group	
				,	impacts = {}
				,	closestTarget = ''
				, 	miss = true		
				,	avgImpactPos  = {x=0,y=0,z=0}
				,	targetsHit = {}
				, 	rollInDistance = 0
				,	rollInAltitudeAT = 0
			}
			-- get impacts and find closest target
			local impactData = data.impactData[_weaponID]	
			local minDist = TITS.MaxMissDistance * 2
 
			if impactData then
				r.miss = false
				local impactCount = 0
				for target, irow in pairs(impactData) do
					local hit = false
					impactCount  = impactCount + 1	
					r.avgImpactPos = mist.vec.add(r.avgImpactPos , irow.impactPos)
					if irow.impactDistance <= minDist then
						minDist = irow.impactDistance
						r.closestTarget = target
					end
					if wHits then
						if wHits[target] then
							hit = true
							table.insert(r.targetsHit,target)
						end
					end
					r.impacts[target] = {
						  target = target
						, targetPos = irow.targetPos
						, hit = hit
						, distance = irow.impactDistance
						, impactPos = irow.impactPos									
					}
			
				end -- for target, irow in pairs(impactData)
				r.avgImpactPos  = mist.vec.scalar_mult(r.avgImpactPos , 1/impactCount)
				if r.closestTarget ~= '' then
					local tp = TITS.getTargetPos(r.closestTarget)
					r.rollInDistance  = mist.utils.get2DDist(data.rollInPosition,tp)
					r.rollInAltitudeAT = data.rollInPosition.y - tp.y
				end
			end -- if impactData then		
			
		end -- if wData then
		
		return r
	end -- function
--=============================================================================================================================================
	function TITS.getShellsFired(_unitName)
		local shtable = {}
		local total = 0
		local data = TITS.passGetData(_unitName)
		if TITS.rowCount(data) > 0 then
			local sf = data.shellsFired
			local r = {}
			
			if TITS.rowCount(sf) > 0 then
				for shellType,s in pairs(sf) do
					if s.fired then
						total = total + s.fired
						shtable[shellType] = s.fired
					end
				end
			end
			
		end --if data ~= {} then
		r = {total = total, list = shtable, shootHeading = data.LBreleaseHeading}
		return r
		
	end -- function
--=============================================================================================================================================
	function TITS.getShellHits(_unitName)
		local shtable = {}
		local targets = {}
		local r = {}
		local total = 0
		local data = TITS.passGetData(_unitName)
		if  TITS.rowCount(data) > 0 then
			local sh = data.shellHits
		
			if TITS.rowCount(sh) > 0 then
				for target,sData in pairs(sh) do
					if not TITS.inTable(target,targets) then
						table.insert(targets,target)
					end
					for shellType,count in pairs(sData) do
						if count > 0 then
							total = total + count
							if data.shellDisplayName[shellType] then
								table.insert(shtable, {target = target, shellType = data.shellDisplayName[shellType], hits = count})
							else
								shellType = shellType:gsub("weapons.shells.", "")
								table.insert(shtable, {target = target, shellType = shellType, hits = count})
							end
						end
					end	-- for shellType,count in pairs(sData) do					
				end -- for target,sData in pairs(sh) do
			end
		end --if data ~= {} then	
		r = {total = total,  targets = targets, list = shtable}
		return r
		
	end -- function
--=============================================================================================================================================
	function TITS.getGroups(_unitName)
		local grptable = {}
		local count = 0
		local r = {}		
		local data = TITS.passGetData(_unitName)
		
		if TITS.rowCount(data) > 0  then
			local groups = data.groups
			
			
			if TITS.rowCount(groups) > 0 then
				for gID,_ in pairs(groups) do
					count = count + 1
					grptable[gID] = gID
				end
			end		
			
		end --if data ~= {} then		
		r = {count = count, list = grptable}
		return r
	
	end --function
--=============================================================================================================================================
	function TITS.getGroupData(_unitName, _groupID)
	--[[
		GroupID
		,   weaponType
		,	releasePitch
		,	releaseYaw
		,	releaseRoll
		,	releaseHeading
		,	releaseSpeed
		,	releasePosition
		,	impactPos  -- Average from weapon impacts
		,	weapons {id list}
		,	weaponPos {avgImpactPos list}
		, 	closestTarget
		,	closestTargetPos
		,	closestTargetHit
		, 	miss  -- no impacts close to targets
		,	avgImpactPos  -- corrected
		,   targetsHit 
		,	size (max dist )
		, 	TargetImpacts
	
	--]]
		local r = {}		
		local data = TITS.passGetData(_unitName)
		
		if TITS.rowCount(data) > 0  then
			local weapons = data.groups[_groupID]
			local impactCount = 0
			local weaponCount = 0
			local targetData = {}
			
			r = {
					groupId					= _groupID
				,	weaponType				= ''
				,	weaponCount				= 0
				,	releasePitch			= 0
				,	releaseYaw				= 0
				,	releaseRoll				= 0
				,	releaseHeading			= 0
				,	releaseSpeed			= 0
				,	releasePosition	 		= {x=0,y=0,z=0}		
				,	impactPos				= {x=0,y=0,z=0}	 -- center
				, 	weapons 				= weapons 
				,	weaponsPos				= {}
				, 	closestTarget			= ''
				,	closestTargetPos		= {}
				,	closestTargetHit		= false
				,	closestTargetDist		= 2 * TITS.MaxMissDistance 
				, 	closestTargetHitCount 	= 0
				,	miss					= true
				,	avgImpactPos  			= {x=0,y=0,z=0}	
				,   targetsHit 				= {}
				,	size 					= 0		
				,	TargetImpacts			={}
				,	rollInDistance			= 0
				,	rollInAltitudeAT		= 0
				
			}

			for _, weaponID in pairs(weapons) do
				local wd = TITS.getWeaponData(_unitName, weaponID)
				
				weaponCount = weaponCount + 1
				r.weaponType = wd.weaponType
				r.releasePitch = r.releasePitch + wd.releasePitch
				r.releaseYaw = r.releaseYaw + wd.releaseYaw
				r.releaseRoll = r.releaseRoll + wd.releaseRoll
				r.releaseHeading = r.releaseHeading + wd.releaseHeading
				r.releaseSpeed	= r.releaseSpeed + wd.releaseSpeed
				r.releasePosition = mist.vec.add(r.releasePosition,wd.releasePosition)	
				r.impactPos = mist.vec.add(r.impactPos,wd.avgImpactPos)	
				table.insert(r.weaponsPos,wd.avgImpactPos)
				
				if not wd.miss then
					r.miss = false
					for _,impact in pairs(wd.impacts) do
						table.insert(targetData,impact)
						if impact.hit and not TITS.inTable(impact.target,r.targetsHit) then
							table.insert(r.targetsHit,impact.target)
						end
					end --for _,impact in pairs(wd.impacts) do
				end -- 	if not wd.miss then
				
			end -- for _,weaponID in pairs(weapons) do
			r.TargetImpacts = targetData
			-- averages
			r.weaponCount = weaponCount
			if weaponCount > 0 then
				r.releasePitch = r.releasePitch / weaponCount
				r.releaseYaw = r.releaseYaw / weaponCount
				r.releaseRoll = r.releaseRoll / weaponCount
				r.releaseHeading = r.releaseHeading / weaponCount
				r.releaseSpeed	= r.releaseSpeed / weaponCount
				r.releasePosition =  mist.vec.scalar_mult(r.releasePosition , 1/weaponCount)
				r.impactPos  = mist.vec.scalar_mult(r.impactPos , 1/weaponCount)
				if not r.miss then
					-- get closestTarget
					for _,t in pairs(targetData) do	
						local d = mist.utils.get3DDist(r.impactPos, t.targetPos)
						if d <= r.closestTargetDist then
							r.closestTargetDist = d
							r.closestTarget	 = t.target
							r.closestTargetPos	= t.targetPos
							r.closestTargetHit	= t.hit				
						end
					end -- for _,t in pairs(targetData) do	
					
					if r.closestTarget ~= '' then
						local tp = TITS.getTargetPos(r.closestTarget)
						r.rollInDistance  = mist.utils.get2DDist(data.rollInPosition,tp)
						r.rollInAltitudeAT = data.rollInPosition.y - tp.y
					end
					
				end -- if not r.miss then			
				--get size
				for i = 1, weaponCount-1, 1 do
					for j = i+1, weaponCount, 1 do
						local d = mist.utils.get3DDist(r.weaponsPos[i],r.weaponsPos[j])
						if d > r.size then
							r.size = d
						end
					end --for j = i+1, weaponCount, 1 do
				end -- for i = 1, weaponCount, 1 do		
			
				for _, weaponID in pairs(weapons) do
					local wd = TITS.getWeaponData(_unitName, weaponID)
					if TITS.inTable(r.closestTarget,wd.targetsHit) then
						r.closestTargetHitCount = r.closestTargetHitCount + 1
					end
				end --for _, weaponID in pairs(weapons) do
				
			end -- if weaponCount > 0 then
	
		
		end --if data ~= {} then		

		return r
	
	end --function
--
--#################################################################################################################################################
-- #############   utils  																										############### 
--#################################################################################################################################################
--
	function TITS.rowCount(t)
		local r = 0
		if t then
			for _,_ in pairs(t) do
				r = r + 1
			end
		end
		return r
	end -- function
--=============================================================================================================================================		
	function TITS.inTable(v,t)
		local r = true
		for _,j in pairs(t) do
			if j == v then
				return true
			end
		end
		return false
		
	end -- function
--
--#################################################################################################################################################
-- #############   Main body   																										############### 
--#################################################################################################################################################
--
do
	-- load event handler
	world.addEventHandler(TITS.coreEventHandler)
	-- start tracking the targets
	timer.scheduleFunction(TITS.trackTargets,{},timer.getTime() + TITS.TargetTrackingInterval)
	
	trigger.action.outText( 'Target Impact Tracker Script- v'..TITS.Version, 1 )
end