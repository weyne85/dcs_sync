-------------------------------------------------------------------------
-- SPA-400 - OnSpawnGroup
-------------------------------------------------------------------------
-- Documentation
-- 
-- SPAWN: https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Core.Spawn.html##(SPAWN).OnSpawnGroup
-- 
-------------------------------------------------------------------------
-- Join the game master slot. The 2nd A-10 will start following the 
-- 1st A-10 around.
-------------------------------------------------------------------------
-- Date: Feb 2023
-------------------------------------------------------------------------

local group1 = SPAWN:New("Aerial-1")
  :OnSpawnGroup(
    function(grp) -- this anonymous function will be called with the already spawned GROUP object for group one
      local group2 = SPAWN:New("Aerial-2")
        :OnSpawnGroup(
          function(grp2) -- this anonymous function will be called with the already spawned GROUP object for group two
            local task = grp2:TaskFollow(grp,{x=100,y=0,z=100}) -- create a DCS task structure
            grp2:SetTask(task,1) -- set this as only task for group two
          end
        )
        :Spawn() -- Spawn group two
    end
  )
  :Spawn() -- Spawn group one