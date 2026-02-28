--[[
Targets fot TITS v2.0Xx
]]--


--[[   Add target parameters
	function TITS.AddTarget(
				_TargetName					-- UNIQUE! Target name
			,	_DisplayName				-- display name, accepts duplicates, if empty _TargetName will be used
			,	_Type						-- [ unit | zone | static ] must be in lower case
			,	_Respawn					-- Only for units. if true, unit can be respawned. Respwan will only happen when ALL the units in the group are destroyed
			,	_TrackImpact				-- use target to calculate distance to impact
			,	_TrackStrafing				-- count strafing hits on target
			,	_ReportHits					-- reports splash damage from weapons
			,	_AllowSmokeDesignation		-- Allow use of smoke designation for target
			,	_AllowLaserDesignation		-- Allow use of laser designation for target
			,	_AllowIRDesignation			-- Allow use of IR designation for target
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
				
--]]

UI.MagneticVar	= 6

-- Load Targets
--								Display								Track	Track		Report	Designation		Allow Smoke		Allow Laser		Allow IR		Allow Nomark	List 		UI		UI		UI		UI		UI		UI		UI		UI		UI
--				Name 			name		Type		Reswpan		Impact	Strafing	Hits	Zone			Designation		Designation		Designation		designation		Coords.		Num1	Num2	Num3	Bool1	Bool2	Bool3	Text1	Text2	Text3

TITS.AddTarget(	'Circle-A',			'', 	'unit', 	true,		true,	true,		true,	1,				false,			false,			false,			true,			true,		0,		0,		0,		false,	false,	false,	'',		'',		''		)		
TITS.AddTarget(	'Circle-B',			'', 	'unit', 	true,		true,	true,		true,	1,				false,			false,			false,			true,			true,		0,		0,		0,		false,	false,	false,	'',		'',		''		)		
TITS.AddTarget(	'Strafe Pit'		,'', 	'unit', 	true,		true,	true,		true,	1,				false,			false,			false,			true,			true,		0,		0,		0,		false,	false,	false,	'',		'',		''		)		
TITS.AddTarget(	'Tank',				'', 	'unit', 	true,		true,	true,		true,	1,				true,			true,			true,			true,			false,		0,		0,		0,		false,	false,	false,	'Left target',		'',		''		)		
TITS.AddTarget(	'Truck',			'', 	'unit', 	true,		true,	true,		true,	1,				true,			true,			true,			true,			false,		0,		0,		0,		false,	false,	false,	'Right Target',		'',		''		)		

TITS.AddTarget(	'Ground-23-1','Bridge-1', 	'poly', 	true,		true,	true,		true,	2,				true,			true,			true,			true,			true,		0,		0,		0,		false,	false,	false,	'It is oriented in the 147°/327° (mmagnetic) radial',		'',		''		)		
TITS.AddTarget(	'white','Goverment bldg.', 	'unit', 	true,		true,	true,		true,	2,				true,			true,			true,			true,			true,		0,		0,		0,		false,	false,	false,	'White Building.',		'North of the Bridge',		''		)		
TITS.AddTarget(	'red',	'Factory', 			'unit', 	true,		true,	true,		true,	2,				true,			true,			true,			true,			true,		0,		0,		0,		false,	false,	false,	'Red Building',		'West of the Bridge',		''		)		
TITS.AddTarget(	'wAr','Refinary', 			'unit', 	true,		true,	true,		true,	2,				true,			true,			true,			true,			true,		0,		0,		0,		false,	false,	false,	'White and Red Building',		'South of th Bridge',		''		)		




-- Laod laser/ir designator list
--					name 		displayName 	zones 	allowLaser		allowIR 	laser code
 UI.AddDesignator(	'Predator'	,		''	,		{1,2}	,	 true	, 		true	,	 '1688'	)



-- Engagement Zones
--						Name					Type
UI.AddEngagementZone (	'Engagement Zone',		'zone' )

--designation zones
UI.AddDesignationZone( 1,	'BSA' )
UI.AddDesignationZone( 2,	'Structures' )


-- Illumination Zones (circular ME zones)
--						Name			Number of shells per round
UI.AddIlluminationZone( 'Illumination-1', 3 )
UI.AddIlluminationZone( 'Illumination-2', 2 )

-- Confirm load
trigger.action.outText( "CA BSA 3 targets", 2 )








