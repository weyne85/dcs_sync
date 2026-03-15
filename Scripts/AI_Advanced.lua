-- =========================================================
--  SMOKE WINDOW 30s (tick 2s, puff 5–8s) + anti-LOS
--  v1.5-altSafe — même logique que ta version, altimétrie fiable
--  + délai aléatoire 2–5 s par unité avant déclenchement
-- =========================================================

local CFG = {
  -- Fenêtre fumigènes
  triggerPercent   = 30,     -- % chance auto à l'impact (IA uniquement)
  windowSec        = 45.0,
  tickSec          = 2.0,
  puffLife         = 2,
  dist             = 30,
  arcMinDeg        = -45,
  arcMaxDeg        =  45,
  points           = 10,
  preset           = 5,      -- 5 = small smoke
  density          = 0.35,
  boomPower        = 1,      -- 0 = off

  -- Anti-spam
  cooldownHit      = 300,    -- impact (par unité)
  cooldownShot     = 5,      -- tir FUMIRCW (par unité)
  supportCooldown  = 300.0,  -- (s) pour un répondant groupe entre deux réactions

  -- Anti-LOS
  smokeRadius      = 6.0,
  checkPeriod      = 1.0,
  holdSeconds      = 2.0,
  maxCheckRange    = 10000,

  -- Déclencheur par munition
  triggerWeaponName = "FUMIRCW",

  -- Support de groupe
  supportEnabled       = true,
  supportTriggerPct    = 30,     -- chance de réaction (hit)
  supportCriticalPct   = 60,     -- chance de réaction (HP<20%)
  supportDeathPct      = 90,     -- chance de réaction (unité détruite)
  supportMaxRespond    = 2,      -- nb max de blindés AI du groupe qui répondent
  criticalHPThreshold  = 0.20,   -- 20%

  -- Fallback altimétrie
  puffAGL         = 1.2,    -- m au-dessus du sol/ASL pour chaque puff
  explodeAGL      = 0.8,    -- m au-dessus pour l’explosion initiale
  groundTol       = 10.0,  -- tolérance vs ASL char avant fallback (m)

  sides = { coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL },
}

-- API Big Smoke requise
if not (trigger and trigger.action and trigger.action.effectSmokeBig and trigger.action.effectSmokeStop) then
  trigger.action.outText("API Big Smoke indisponible: effectSmokeBig/Stop manquants.", 8)
  return
end

-- ============== Helpers ==============
local function vlenXZ(v) return math.sqrt(v.x*v.x + v.z*v.z) end
local function vnormXZ(v) local l=vlenXZ(v); if l<0.001 then return {x=0,y=0,z=1} end; return {x=v.x/l,y=0,z=v.z/l} end
local function vmul(v,s) return {x=v.x*s, y=0, z=v.z*s} end
local function vadd(a,b) return {x=a.x+b.x, y=(a.y or 0)+(b.y or 0), z=a.z+b.z} end
local function rotY(v, rad) local c,s=math.cos(rad),math.sin(rad); return {x=v.x*c - v.z*s, y=0, z=v.x*s + v.z*c} end
local function isArmored(u) return Unit.hasAttribute(u, "Tanks") or Unit.hasAttribute(u, "IFV")  end
local function isPlayer(u) return pcall(Unit.getPlayerName, u) and (u:getPlayerName() ~= nil) end
local function groundY(x,z) return land.getHeight({x=x,y=0,z=z}) or 0 end

-- Altitude de référence (ASL) du char
local function unitASL(u) local p=u:getPoint(); return (p and p.y) or 0 end

-- Hauteur “fiable” à (x,z) pour puffs/explosion :
--  1) on tente land.getHeight
--  2) si 0 ou trop loin de l’ASL du char => fallback sur ASL + AGL
local function groundSafeAt(u, x, z, agl, tol)
  agl = agl or CFG.puffAGL
  tol = tol or CFG.groundTol
  local h = groundY(x,z)
  local asl = unitASL(u)
  if h <= 0.1 or math.abs(h - asl) > tol then
    return asl + agl
  else
    return h + agl
  end
end

local function distPointSegXZ(P, A, B)
  local vx, vz = B.x - A.x, B.z - A.z
  local wx, wz = P.x - A.x, P.z - A.z
  local vv = vx*vx + vz*vz
  if vv < 1e-6 then return math.sqrt(wx*wx + wz*wz) end
  local t = (wx*vx + wz*vz) / vv
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local qx, qz = A.x + t*vx, A.z + t*vz
  local dx, dz = P.x - qx, P.z - qz
  return math.sqrt(dx*dx + dz*dz)
end

-- ============== Registre fumées ==============
local SMK = { active = {} }  -- {x,y,z,expire}
local function addSmokePoint(pt, life)
  SMK.active[#SMK.active+1] = { x=pt.x, y=pt.y, z=pt.z, expire=timer.getTime() + life }
end
local function purgeSmokes()
  local now = timer.getTime()
  local j=1
  for i=1,#SMK.active do
    if SMK.active[i].expire > now then
      if i~=j then SMK.active[j] = SMK.active[i] end
      j=j+1
    end
  end
  for k=j,#SMK.active do SMK.active[k]=nil end
end

-- ============== Orientation TOURELLE figée à t0 ==============
-- Arg 0: [-100..+100] -> [-180..+180] ; inversion demandée : deg = -arg0*1.8
local function getTurretDirNow(u)
  local ok, a0 = pcall(Unit.getDrawArgumentValue, u, 0)
  local hullFwd = vnormXZ(u:getPosition().x)
  if not ok or a0 == nil then return hullFwd end
  if math.abs(a0) <= 1.001 then a0 = a0 * 100.0 end
  local deg = -a0 * 1.8
  return rotY(hullFwd, math.rad(deg))
end

-- ============== Big Smoke (fenêtre + salves) ==============
local BSW = {
  hitLast     = {},  -- cooldown impact
  shotLast    = {},  -- cooldown FUMIRCW
  supportLast = {},  -- cooldown support pour répondants
  active      = {},  -- [unitID] = { stopTime, salvo, frame={base,fwd,right,unitRef} }
  pending     = {},  -- [unitID] = true si fenêtre planifiée (délai 2–5s)
}

local function stopEffectLater(args, time)
  local name = args[1]; if name then pcall(trigger.action.effectSmokeStop, name) end
end

-- Points de l’arc (altitude fiable via groundSafeAt)
local function computeArcPointsStatic(frame)
  local pts = {}
  local n = math.max(1, CFG.points)
  local a0, a1 = CFG.arcMinDeg, CFG.arcMaxDeg
  for i=0, n-1 do
    local t   = (n==1) and 0.5 or (i/(n-1))
    local deg = a0 + (a1 - a0)*t
    local rad = math.rad(deg)
    local c, s = math.cos(rad), math.sin(rad)
    local dir = { x = frame.fwd.x*c + frame.right.x*s, y = 0, z = frame.fwd.z*c + frame.right.z*s }
    local p   = vadd(frame.base, vmul(dir, CFG.dist))
    p.y = groundSafeAt(frame.unitRef, p.x, p.z, CFG.puffAGL, CFG.groundTol)
    pts[#pts+1] = p
  end
  return pts
end

local function spawnSalvoStatic(u, salvoIdx, frame)
  if not u or not Unit.isExist(u) then return end
  local pts = computeArcPointsStatic(frame)
  local now = timer.getTime()
  for i,pt in ipairs(pts) do
    local name = string.format("Puff_%d_%d_%02d", u:getID(), salvoIdx, i)
    trigger.action.effectSmokeBig(pt, CFG.preset, CFG.density, name)
    timer.scheduleFunction(stopEffectLater, {name}, now + CFG.puffLife)
    addSmokePoint(pt, CFG.puffLife)
    if salvoIdx == 1 and CFG.boomPower and CFG.boomPower > 0 then
      local ep = { x = pt.x, y = pt.y + (CFG.explodeAGL or 0.8), z = pt.z }
      trigger.action.explosion(ep, CFG.boomPower)
    end
  end
end

local function windowTick(args, time)
  local uid, uname = args[1], args[2]
  local st = BSW.active[uid]; if not st then return end
  local u = Unit.getByName(uname); if not u or not Unit.isExist(u) then BSW.active[uid]=nil; return end
  local now = timer.getTime()
  if now >= st.stopTime then BSW.active[uid]=nil; return end
  spawnSalvoStatic(u, st.salvo, st.frame)
  st.salvo = st.salvo + 1
  timer.scheduleFunction(windowTick, {uid, uname}, now + CFG.tickSec)
end

-- Callback réel déclenchant la fenêtre de fumée (après délai 2–5 s)
local function startWindowNow(args, time)
  local id, name = args[1], args[2]
  BSW.pending[id] = nil
  local u = Unit.getByName(name)
  if not u or not Unit.isExist(u) then return end
  if BSW.active[id] then return end

  local base = u:getPosition().p      -- on garde la base XY du char
  local fwd  = getTurretDirNow(u)
  local right= { x = -fwd.z, y = 0, z =  fwd.x }
  local now = timer.getTime()
  BSW.active[id] = {
    stopTime = now + CFG.windowSec,
    salvo    = 1,
    frame    = {
      base = {x=base.x, y=unitASL(u), z=base.z}, -- y stocké = ASL ref (ne sert que d’info)
      fwd = fwd, right = right, unitRef = u      -- unitRef utilisé par groundSafeAt()
    },
  }
  windowTick({id, name}, now)
end

-- API publique : demande de fumigènes
-- -> applique un délai aléatoire 2–5 s par unité
local function startWindow(u)
  if not u or not Unit.isExist(u) then return end
  local id   = u:getID()
  local name = u:getName() or ("unit_"..id)

  -- Si déjà actif ou déjà en attente de déclenchement, on ne double pas
  if BSW.active[id] or BSW.pending[id] then return end

  local delay = math.random(2, 5)  -- 2 à 5 secondes
  BSW.pending[id] = true
  timer.scheduleFunction(startWindowNow, {id, name}, timer.getTime() + delay)
end

-- ============== Anti-LOS : hold si fumée coupe la ligne ==============
local FIRE = { restoreAt = {} }
local ROE_ID   = AI.Option.Ground.id.ROE
local ROE_OPEN = AI.Option.Ground.val.ROE.OPEN_FIRE
local ROE_HOLD = AI.Option.Ground.val.ROE.WEAPON_HOLD

local function setHoldFor(u, seconds)
  local ctrl = u:getController(); if not ctrl then return end
  local id = u:getID()
  local untilT = timer.getTime() + seconds
  FIRE.restoreAt[id] = math.max(FIRE.restoreAt[id] or 0, untilT)
  ctrl:setOption(ROE_ID, ROE_HOLD)
end
local function maybeRestoreROE(u)
  local id = u:getID(); local t = FIRE.restoreAt[id]
  if t and timer.getTime() >= t then
    local ctrl = u:getController(); if ctrl then ctrl:setOption(ROE_ID, ROE_OPEN) end
    FIRE.restoreAt[id] = nil
  end
end
local function isOccludedBySmoke(Apos, Bpos)
  for i=1,#SMK.active do
    local S = SMK.active[i]
    if distPointSegXZ({x=S.x, z=S.z}, Apos, Bpos) <= CFG.smokeRadius then return true end
  end
  return false
end
local function getEnemiesNear(u, side, maxR)
  local enemies = {}
  for _,otherSide in ipairs(CFG.sides) do
    if otherSide ~= side then
      local groups = coalition.getGroups(otherSide, Group.Category.GROUND)
      if groups then
        for _,g in ipairs(groups) do
          local units = g:getUnits()
          if units then
            for _,e in ipairs(units) do
              if e and Unit.isExist(e) then
                local up = u:getPoint(); local ep = e:getPoint()
                local dx, dz = ep.x - up.x, ep.z - up.z
                if (dx*dx + dz*dz) <= (maxR*maxR) then enemies[#enemies+1] = e end
              end
            end
          end
        end
      end
    end
  end
  return enemies
end
local function fireGuardTick(args, time)
  -- On ne purge et ne scanne lourdement que s'il y a de la fumée active
  purgeSmokes()
  local hasSmoke = (#SMK.active > 0)

  for _,side in ipairs(CFG.sides) do
    local groups = coalition.getGroups(side, Group.Category.GROUND)
    if groups then
      for _,g in ipairs(groups) do
        local units = g:getUnits()
        if units then
          for _,u in ipairs(units) do
            if u and Unit.isExist(u) and isArmored(u) then
              -- Toujours vérifier la fin du HOLD, même sans fumée
              maybeRestoreROE(u)

              if hasSmoke then
                local enemies = getEnemiesNear(u, side, CFG.maxCheckRange)
                if #enemies > 0 then
                  local up = u:getPoint()
                  for _,tgt in ipairs(enemies) do
                    if tgt and Unit.isExist(tgt) then
                      if isOccludedBySmoke(up, tgt:getPoint()) then
                        setHoldFor(u, CFG.holdSeconds); break
                      end
                    end
                  end
                end
              end -- hasSmoke
            end
          end
        end
      end
    end
  end
  timer.scheduleFunction(fireGuardTick, {}, timer.getTime() + CFG.checkPeriod)
end

-- ============== Support de groupe ==============
local function pickRespondersFromGroup(grp)
  if not grp then return {} end
  local responders, units = {}, grp:getUnits()
  if not units then return responders end
  for _,u in ipairs(units) do
    if u and Unit.isExist(u) and isArmored(u) and not isPlayer(u) and (not BSW.active[u:getID()]) then
      responders[#responders+1] = u
    end
  end
  return responders
end

local function startGroupSupport(grp, chancePct)
  if not CFG.supportEnabled then return end
  if not grp then return end
  if (math.random()*100.0) > (chancePct or CFG.supportTriggerPct) then return end

  local responders = pickRespondersFromGroup(grp)
  if #responders == 0 then return end

  -- shuffle
  for i=#responders,2,-1 do local j=math.random(1,i); responders[i],responders[j]=responders[j],responders[i] end

  local now = timer.getTime()
  local maxN = math.max(1, math.min(CFG.supportMaxRespond or 1, #responders))
  local N = math.random(1, maxN)
  local count = 0
  for _,u in ipairs(responders) do
    local id = u:getID()
    if (now - (BSW.supportLast[id] or -1e9)) >= CFG.supportCooldown then
      BSW.supportLast[id] = now
      startWindow(u)  -- => délai aléatoire 2–5 s par blindé
      count = count + 1
      if count >= N then break end
    end
  end
end

-- ============== Event handler : SHOT / HIT / DEAD (fix) ==============
local EH = {}
function EH:onEvent(e)
  if not e then return end

  -- Tir : déclenche FUMIRCW (IA + joueur)
  if e.id == world.event.S_EVENT_SHOT then
    local shooter = e.initiator
    if shooter and Unit.isExist(shooter) and isArmored(shooter) then
      local w = e.weapon
      if w and w.getTypeName and (w:getTypeName() == CFG.triggerWeaponName) then
        local id=shooter:getID(); local now=timer.getTime()
        if (now - (BSW.shotLast[id] or -1e9)) >= CFG.cooldownShot then
          BSW.shotLast[id]=now
          startWindow(shooter)  -- délai 2–5 s
        end
      end
    end
    return
  end

  -- Impact : auto (IA) + support de groupe (HIT / HP <= 20%)
  if e.id == world.event.S_EVENT_HIT then
    local tgt = e.target
    if not tgt or not tgt.getGroup then return end   -- ne pas faire isExist ici
    local grp = tgt:getGroup()

    startGroupSupport(grp, CFG.supportTriggerPct)

    local okL0, l0 = pcall(Unit.getLife0, tgt)
    local okL,  l  = pcall(Unit.getLife,  tgt)
    if okL0 and okL and l0 and l0 > 0 then
      local hp = math.max(0, l) / l0
      if hp <= (CFG.criticalHPThreshold or 0.2) then
        startGroupSupport(grp, CFG.supportCriticalPct)
      end
    end

    if isArmored(tgt) then
      if isPlayer(tgt) then return end
      local id=tgt:getID(); local now=timer.getTime()
      if (now - (BSW.hitLast[id] or -1e9)) < CFG.cooldownHit then return end
      BSW.hitLast[id]=now
      if (math.random()*100.0) <= (CFG.triggerPercent or 100) then
        startWindow(tgt)  -- délai 2–5 s
      end
    end
    return
  end

  -- Destruction : support de groupe (DEAD)
  if e.id == world.event.S_EVENT_DEAD then
    local deadObj = e.initiator or e.target
    if not deadObj then return end
    local grp = nil
    if deadObj.getGroup then
      local ok, g = pcall(deadObj.getGroup, deadObj)
      if ok then grp = g end
    end
    if not grp then return end
    startGroupSupport(grp, CFG.supportDeathPct)
    return
  end
end

world.addEventHandler(EH)

-- ============== Boot ==============
timer.scheduleFunction(fireGuardTick, {}, timer.getTime() + 0.5)


----------------------------------------------------------------
-- RTE v2.1 + AI Tanks/IFV (poursuite/flanc) + Diamond (Off Road)
----------------------------------------------------------------

-----------------------------
-- Exclusions & utilitaires
-----------------------------
local EXCL = {}
function EXCL.byGroupName(name)
  if not name or name=="" then return false end
  if name=="XLBis" then return true end
  local s=string.lower(name)
  return string.find(s,"aioff",1,true)~=nil
end

local function leaderPoint(g)
  local u=g:getUnit(1)
  if u and Unit.isExist(u) then local p=u:getPoint(); return {x=p.x,y=p.y,z=p.z} end
  return nil
end
local function dist2D(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx+dz*dz) end
local function posAlt(x,z) return land.getHeight({x=x,y=0,z=z})+0.5 end

-------------------------------------------------
-- RTE v2.1 — Capture / Suivi / Reprise routes
-------------------------------------------------
local RTE = {}
_G.ROUTE_DB = _G.ROUTE_DB or {}

function RTE.findMEGroupByName(gName)
  if not env or not env.mission or not env.mission.coalition then return nil end
  for _, sideTbl in pairs(env.mission.coalition) do
    local ctry = sideTbl and sideTbl.country
    if ctry then
      for _, cty in ipairs(ctry) do
        local c = cty.country or cty
        for _,cat in ipairs({'vehicle','static','plane','helicopter','ship'}) do
          local t = c[cat]
          if t and t.group then
            for _,grp in ipairs(t.group) do
              if grp and grp.name == gName then return grp end
            end
          end
        end
      end
    end
  end
  return nil
end

local function deepCopyTask(t)
  if type(t)~='table' then return {id='ComboTask',params={tasks={}}} end
  local c={}; for k,v in pairs(t) do c[k]=v end
  if not (c.params and c.params.tasks) then c={id='ComboTask',params={tasks={}}} end
  return c
end

function RTE.getRouteME(gName, useAlt)
  local g = RTE.findMEGroupByName(gName)
  if not g or not g.route or not g.route.points then return nil end
  local pts={}
  for i,wp in ipairs(g.route.points) do
    pts[#pts+1]={
      idx=i,
      vec3={x=wp.x, y=(useAlt and (wp.alt or 0) or 0), z=wp.y},
      alt=wp.alt, alt_type=wp.alt_type,
      speed=wp.speed, speed_locked=wp.speed_locked,
      ETA=wp.ETA, ETA_locked=wp.ETA_locked,
      type=wp.type, action=wp.action, name=wp.name,
      task=deepCopyTask(wp.task)
    }
  end
  return pts
end

local function listAllGroundGroups()
  local out={}
  for _,side in ipairs({coalition.side.RED,coalition.side.BLUE,coalition.side.NEUTRAL}) do
    local gs=coalition.getGroups(side, Group.Category.GROUND)
    if gs then
      for _,g in ipairs(gs) do
        if g and Group.isExist(g) and not EXCL.byGroupName(g:getName()) then
          out[#out+1]=g
        end
      end
    end
  end
  return out
end

function RTE.captureGroup(g)
  if not g or not Group.isExist(g) then return nil end
  local name=g:getName(); if EXCL.byGroupName(name) then return nil end
  if ROUTE_DB[name] and ROUTE_DB[name].routeME then return ROUTE_DB[name] end
  local me=RTE.getRouteME(name,true); if not me or #me==0 then return nil end
  ROUTE_DB[name]={ routeME=me, progress={passed={}, currentIdx=1}, meta={captured_at=timer.getTime()} }
  return ROUTE_DB[name]
end

function RTE.captureAll()
  local n=0
  for _,g in ipairs(listAllGroundGroups()) do if RTE.captureGroup(g) then n=n+1 end end
  return n
end

local PASS_THRESHOLD=120 -- m (WP considéré “passé”)
local function updateProgress(g)
  local name=g:getName(); local rec=ROUTE_DB[name]; if not rec then return end
  local pts=rec.routeME; if not pts then return end
  local n=#pts; if n==0 then return end
  local L=leaderPoint(g); if not L then return end
  local prog=rec.progress or {passed={},currentIdx=1}; rec.progress=prog

  if not prog.currentIdx or prog.currentIdx<1 then
    local bestI, bestD=1,1e15
    for i=1,n do local p=pts[i].vec3; local d=dist2D(L,{x=p.x,z=p.z}); if d<bestD then bestD, bestI=d,i end end
    prog.currentIdx=bestI
  end

  while prog.currentIdx<=n do
    local p=pts[prog.currentIdx].vec3
    if dist2D(L,{x=p.x,z=p.z})<=PASS_THRESHOLD then
      prog.passed[prog.currentIdx]=true
      prog.currentIdx=prog.currentIdx+1
    else break end
  end
end

local function rteTick()
  for _,g in ipairs(listAllGroundGroups()) do if ROUTE_DB[g:getName()] then updateProgress(g) end end
  timer.scheduleFunction(rteTick, {}, timer.getTime()+1.0)
end

local function buildResumeTask(g, rec)
  local pts=rec.routeME; local n=#pts; if n==0 then return nil end
  local prog=rec.progress or {currentIdx=1}; local startIdx=prog.currentIdx or 1
  if startIdx>n then return nil end
  local L=leaderPoint(g); if not L then return nil end
  local routePts={}
  local firstSpeed = pts[startIdx].speed or 15

  routePts[#routePts+1]={ x=L.x,y=L.z,alt=L.y, speed=firstSpeed, speed_locked=true,
    type="Turning Point", action=pts[startIdx].action or "On Road",
    task={id='ComboTask',params={tasks={}}} }

  for i=startIdx,n do
    local p=pts[i]
    routePts[#routePts+1]={
      x=p.vec3.x, y=p.vec3.z, alt=(p.alt or posAlt(p.vec3.x,p.vec3.z)),
      speed=p.speed or firstSpeed, speed_locked=p.speed_locked or true,
      type=p.type or "Turning Point", action=p.action or "On Road",
      task=deepCopyTask(p.task)
    }
  end

  return { id='Mission', params={ route={ points=routePts } } }
end

function RTE.resume(groupName)
  local g=Group.getByName(groupName); if not (g and Group.isExist(g)) then return false end
  if EXCL.byGroupName(g:getName()) then return false end
  local rec=ROUTE_DB[groupName]; if not rec then return false end
  updateProgress(g)
  local task=buildResumeTask(g, rec); if not task then return false end
  g:getController():setTask(task)
  return true
end

function RTE.resumeAll()
  local n=0; for _,g in ipairs(listAllGroundGroups()) do if ROUTE_DB[g:getName()] and RTE.resume(g:getName()) then n=n+1 end end
  return n
end

-- Boot RTE (modifié) : pas de capture automatique, RTE/RSL sont
-- appelés seulement quand une manœuvre démarre ou se termine.
_G.RTE = RTE
trigger.action.outText("IA Avancée initialisée avec succés", 4)

---------------------------------------------------------
-- AI: Tanks (poursuite ±20°) & IFV (flanc 25–30°)
--  + détection capteurs only, reprise RTE après combat
--  + forçage Diamond à la manœuvre (sans changer Off Road)
---------------------------------------------------------
local AIB = {
  tick = 1.0,
  tankMaxRange = 4500,  -- m
  ifvMaxRange  = 3500,  -- m
  tankSpeedKmh = 40,
  ifvSpeedKmh  = 40,
  tankOffsetDegRange = {15,25},  -- vise ±20°
  ifvFlankDegRange  = {25,30},   -- 25–30°
  aimConeDeg   = 15,    -- tourelle orientée si angle ≤ 15°
  sides = { coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL },
}

AIB._sideIndex = 1

-- Attributs / catégories
local function isTank(u) return Unit.hasAttribute(u,"Tanks") end
local function isIFV(u)  return Unit.hasAttribute(u,"IFV")   end
local function isInfantry(u) return Unit.hasAttribute(u,"Infantry") end

-- Vecteurs/angles
local function vecTo(a,b) local dx=b.x-a.x; local dz=b.z-a.z; local l=math.sqrt(dx*dx+dz*dz); if l<1e-6 then return {x=0,z=1},0 end; return {x=dx/l,z=dz/l}, l end
local function dot2D(a,b) return a.x*b.x + a.z*b.z end
local function angleBetweenDeg(a,b) local d=math.max(-1,math.min(1,dot2D(a,b))); return math.deg(math.acos(d)) end
local function rightOf(v) return {x=-v.z, z=v.x} end

-- Tourelle via arg0 inversé ([-100..+100] → [-180..+180])
local function turretDir(u)
  local hullFwd = u:getPosition().x
  local ok,a0 = pcall(Unit.getDrawArgumentValue, u, 0)
  if not ok or a0==nil then return {x=hullFwd.x,y=0,z=hullFwd.z} end
  if math.abs(a0) <= 1.001 then a0 = a0*100.0 end
  local deg = -a0*1.8
  local c,s=math.cos(math.rad(deg)), math.sin(math.rad(deg))
  return { x=hullFwd.x*c - hullFwd.z*s, y=0, z=hullFwd.x*s + hullFwd.z*c }
end
local function turretAimingAt(u, tgt, coneDeg)
  local up=u:getPoint(); local tp=tgt:getPoint()
  local toTgt,_ = vecTo(up,{x=tp.x,z=tp.z})
  local gun = turretDir(u)
  local ang = angleBetweenDeg(gun, toTgt)
  return ang <= (coneDeg or AIB.aimConeDeg)
end

-- Détection capteurs only
local DET={}
pcall(function()
  DET.RADAR=Controller.Detection.RADAR; DET.OPTIC=Controller.Detection.OPTIC
  DET.IRST=Controller.Detection.IRST;   DET.RWR=Controller.Detection.RWR
  DET.DLINK=Controller.Detection.DLINK
end)
local function sees(ctrl, tgt)
  if not ctrl or not tgt then return false end
  local ok,seen=pcall(function()
    return (ctrl:isTargetDetected(tgt,DET.RADAR) or ctrl:isTargetDetected(tgt,DET.OPTIC)
         or ctrl:isTargetDetected(tgt,DET.IRST)  or ctrl:isTargetDetected(tgt,DET.RWR)
         or ctrl:isTargetDetected(tgt,DET.DLINK))
  end)
  return ok and seen
end

-- Cible sol (hors infanterie) la plus proche vue
local function findGroundTarget(u, maxR)
  local side = u:getCoalition()
  local up   = u:getPoint()
  local ctrl = u:getController()
  local best, bestD = nil, 1e15
  for _,s in ipairs(AIB.sides) do
    if s ~= side then
      local gs = coalition.getGroups(s, Group.Category.GROUND)
      if gs then
        for _,g in ipairs(gs) do
          local us = g:getUnits()
          if us then
            for _,t in ipairs(us) do
              if t and Unit.isExist(t) and (not Unit.hasAttribute(t,"Infantry")) then
                local tp = t:getPoint()
                local dx, dz = tp.x - up.x, tp.z - up.z
                local d = math.sqrt(dx*dx + dz*dz)
                if d <= maxR and sees(ctrl, t) then
                  if d < bestD then best, bestD = t, d end
                end
              end
            end
          end
        end
      end
    end
  end
  return best, bestD
end

-------------------------------------------------
-- Forçage formation "Diamond" (sans toucher Off Road)
-------------------------------------------------
local function _forceDiamond_setOption(ctrl)
  if AI and AI.Option and AI.Option.Ground and AI.Option.Ground.id and AI.Option.Ground.val then
    return pcall(function()
      ctrl:setOption(AI.Option.Ground.id.FORMATION, AI.Option.Ground.val.FORMATION.Diamond)
    end)
  end
  return false
end
local function _forceDiamond_legacyOption(ctrl)
  local nameId = (Option and Option.Ground and Option.Ground.id and Option.Ground.id.FORMATION) or 5
  local valDiamond = (Option and Option.Ground and Option.Ground.val and Option.Ground.val.FORMATION and Option.Ground.val.FORMATION.Diamond) or 4
  return pcall(function()
    ctrl:setCommand({ id = 'Option', params = { name = nameId, value = valDiamond } })
  end)
end
local function _forceDiamond_wrapped(ctrl)
  return pcall(function()
    ctrl:pushTask({ id='WrappedAction', params={ action={ id='SetFormation', params={ formation="Diamond" } } } })
  end)
end
local function forceDiamond(ctrl)
  if not ctrl then return end
  local ok = _forceDiamond_setOption(ctrl)
  if not ok then ok = _forceDiamond_legacyOption(ctrl) end
  if not ok then _forceDiamond_wrapped(ctrl) end
end
local function forceDiamondRepeated(ctrl)
  forceDiamond(ctrl)
  timer.scheduleFunction(function() forceDiamond(ctrl) end, {}, timer.getTime()+0.4)
  timer.scheduleFunction(function() forceDiamond(ctrl) end, {}, timer.getTime()+1.2)
  timer.scheduleFunction(function() forceDiamond(ctrl) end, {}, timer.getTime()+2.5)
end

-------------------------------------------------
-- Mission 2 points (OFF ROAD) + Diamond forcé
-------------------------------------------------
-- ===== Helpers autonomes (pas besoin de MIST chargé) =====
local function utils_kmphToMps(kmh) return (kmh or 0)/3.6 end

local function ground_buildWP(point, overRideForm, overRideSpeed)
  local wp = {}
  wp.x = point.x
  wp.y = point.z or point.y
  -- speed
  if point.speed and (overRideSpeed == nil) then
    wp.speed = point.speed
  elseif type(overRideSpeed) == 'number' then
    wp.speed = overRideSpeed
  else
    wp.speed = utils_kmphToMps(20)
  end
  -- form/action
  local form
  if point.form and (overRideForm == nil) then
    form = point.form
  else
    form = overRideForm
  end
  if not form then
    wp.action = 'Cone'
  else
    local f = string.lower(tostring(form))
    if f == 'off_road' or f == 'off road' then
      wp.action = 'Off Road'
    elseif f == 'on_road' or f == 'on road' then
      wp.action = 'On Road'
    elseif f == 'rank' or f == 'line_abrest' or f == 'line abrest' or f == 'lineabrest'then
      wp.action = 'Rank'
    elseif f == 'cone' then
      wp.action = 'Cone'
    elseif f == 'diamond' then
      wp.action = 'Diamond'
    elseif f == 'vee' then
      wp.action = 'Vee'
    elseif f == 'echelon_left' or f == 'echelon left' or f == 'echelonl' then
      wp.action = 'EchelonL'
    elseif f == 'echelon_right' or f == 'echelon right' or f == 'echelonr' then
      wp.action = 'EchelonR'
    else
      wp.action = 'Cone'
    end
  end
  wp.type = 'Turning Point'
  return wp
end

-- ===== Remplacement de setTwoPointMission =====
--  -> WP1 Off Road (comme avant), WP2 Diamond (impose la formation)
local function setTwoPointMission(u, p2, speedKmh)
  local g=u:getGroup(); if not g then return false end
  if EXCL.byGroupName(g:getName()) then return false end
  local ctrl=g:getController(); if not ctrl then return false end

  local p1=u:getPoint()
  local spd = utils_kmphToMps(speedKmh or 30)

  -- WP1 : Off Road, depuis la position actuelle (ne change pas ton comportement)
  local wp1 = ground_buildWP({ x=p1.x, z=p1.z, speed=spd }, 'off_road', spd)
  -- WP2 : Diamond, vers le point d'attaque (force la formation Diamond au WP)
  local wp2 = ground_buildWP({ x=p2.x, z=p2.z, speed=spd }, 'diamond',  spd)

  local task = {
    id='Mission', params={ route={ points={
      { x=wp1.x, y=wp1.y, alt=p1.y, speed=wp1.speed, speed_locked=true,
        type=wp1.type, action=wp1.action, task={id='ComboTask', params={tasks={}}} },
      { x=wp2.x, y=wp2.y, alt=p2.y, speed=wp2.speed, speed_locked=true,
        type=wp2.type, action=wp2.action, task={id='ComboTask', params={tasks={}}} },
    }}}
  }

  ctrl:setTask(task)
  return true
end


-------------------------------------------------
-- Points d’attaque
-------------------------------------------------
local function pursuitPoint(u, tgt, degMin, degMax, distAhead)
  local up=u:getPoint(); local tp=tgt:getPoint()
  local dir, d = vecTo(up,{x=tp.x,z=tp.z})
  local sign = (math.random()<0.5) and -1 or 1
  local offDeg = (degMin + math.random()*(degMax-degMin))*sign
  local rad = math.rad(offDeg)
  local dir2 = { x = dir.x*math.cos(rad) - dir.z*math.sin(rad),
                 z = dir.x*math.sin(rad) + dir.z*math.cos(rad) }
  local L = math.max(100, math.min(d-50, distAhead or 600))
  local x = up.x + dir2.x * L
  local z = up.z + dir2.z * L
  return { x=x, y=posAlt(x,z), z=z }
end

local function flankPoint(u, tgt, degMin, degMax)
  local up=u:getPoint(); local tp=tgt:getPoint()
  local toTgt, d = vecTo(up,{x=tp.x,z=tp.z})
  local sign = (math.random()<0.5) and -1 or 1
  local offDeg = (degMin + math.random()*(degMax-degMin)) * sign
  local rad = math.rad(offDeg)
  local dir2 = { x = toTgt.x*math.cos(rad) - toTgt.z*math.sin(rad),
                 z = toTgt.x*math.sin(rad) + toTgt.z*math.cos(rad) }
  local L = math.max(150, math.min(d, 800))
  local x = up.x + dir2.x * L
  local z = up.z + dir2.z * L
  return { x=x, y=posAlt(x,z), z=z }
end

-------------------------------------------------
-- États & boucle IA Tanks / IFV
-------------------------------------------------
local STATE = {} -- [unitName] = { mode='IDLE'|'ENGAGE', kind='TANK'|'IFV', target=unitName, lastSeen=t }

local function clearState(u) if u and Unit.isExist(u) then STATE[u:getName()] = nil end end

local function processUnit(u)
  if not u or not Unit.isExist(u) then return end
  local kind = isTank(u) and "TANK" or (isIFV(u) and "IFV" or nil)
  if not kind then return end
  local g = u:getGroup(); if not g or EXCL.byGroupName(g:getName()) then return end

  local st = STATE[u:getName()]
  if not st then st = { mode = 'IDLE', kind = kind }; STATE[u:getName()] = st end

  if st.mode == 'IDLE' then
    local maxR = (kind == "TANK") and AIB.tankMaxRange or AIB.ifvMaxRange
    local tgt, d = findGroundTarget(u, maxR)
    if tgt then
      if kind == "TANK" then
        if turretAimingAt(u, tgt, AIB.aimConeDeg) then
          -- on sauvegarde le plan courant (script/ME) avant la poursuite
          if RSL and RSL.push then RSL.push(g) end
          local p = pursuitPoint(u, tgt, AIB.tankOffsetDegRange[1], AIB.tankOffsetDegRange[2], 600)
          setTwoPointMission(u, p, AIB.tankSpeedKmh)
          st.mode = 'ENGAGE'; st.target = tgt:getName(); st.lastSeen = timer.getTime()
        end
      else -- IFV
        -- idem pour le flanc IFV
        if RSL and RSL.push then RSL.push(g) end
        local p = flankPoint(u, tgt, AIB.ifvFlankDegRange[1], AIB.ifvFlankDegRange[2])
        setTwoPointMission(u, p, AIB.ifvSpeedKmh)
        st.mode = 'ENGAGE'; st.target = tgt:getName(); st.lastSeen = timer.getTime()
      end
    end

  elseif st.mode == 'ENGAGE' then
    local tgt = st.target and Unit.getByName(st.target) or nil
    local valid = tgt and Unit.isExist(tgt)
    if valid then
      local ctrl = u:getController()
      if sees(ctrl, tgt) then st.lastSeen = timer.getTime() end
      if (timer.getTime() - (st.lastSeen or 0)) > 20.0 then valid = false end
    end
    if not valid then
      local gname = g:getName()
      -- on demande toujours une reprise ; RTE.resume tente d'abord RSL.restore,
      -- sinon il retombe sur la route ME (si elle existe dans ROUTE_DB)
      RTE.resume(gname)
      clearState(u)
    end
  end
end

local function aiTick()
  -- On répartit la charge : un seul camp traité par tick
  local side = AIB.sides[AIB._sideIndex]
  AIB._sideIndex = AIB._sideIndex + 1
  if AIB._sideIndex > #AIB.sides then AIB._sideIndex = 1 end

  local gs = coalition.getGroups(side, Group.Category.GROUND)
  if gs then
    for _,g in ipairs(gs) do
      if g and Group.isExist(g) and not EXCL.byGroupName(g:getName()) then
        local us=g:getUnits()
        if us then
          for _,u in ipairs(us) do
            processUnit(u)
          end
        end
      end
    end
  end

  timer.scheduleFunction(aiTick, {}, timer.getTime()+AIB.tick)
end
timer.scheduleFunction(aiTick, {}, timer.getTime()+1.0)





----------------------------------------------------------------
-- CONVOY EVASION TO VILLAGE + RTE RESUME
----------------------------------------------------------------

local CFG = {
  scanRadius_m       = 1500,
  minBuildings       = 4,
  decisionDelayMin_s = 15,
  decisionDelayMax_s = 30,
  goProbability_pct  = 100,      -- % de chance d'y aller (décision unique)
  travelSpeed_kmh    = 55,
  manpadChance_pct   = 100,      -- % si le convoi contient IFV/APC
  resumeQuiet_s      = 300,     -- 5 min sans attaque => reprise route
}

-- === Exclusions (si besoin, ajoute "AIOFF"/etc) ===
local function groupExcludedByName(name)
  if not name or name=="" then return false end
  if name=="XLBis" then return true end
  local s=string.lower(name)
  if s:find("aioff",1,true) then return true end
  return false
end

-- === Helpers géo ===
local function dist2D(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx+dz*dz) end
local function posXZ(obj) local p=obj:getPoint(); return {x=p.x, z=p.z, y=p.y} end
local function kmphToMps(kmh) return (kmh or 0)/3.6 end

-- === Détection types ===
local function isIFV(u)      return Unit.hasAttribute(u,"IFV") end
local function isAPC(u)      return Unit.hasAttribute(u,"APC") or Unit.hasAttribute(u,"APCs") end
local function isInfantry(u) return Unit.hasAttribute(u,"Infantry") end

-- === Waypoint builder (formation via action du WP) ===
local function buildGroundWP(point, form, speed_mps)
  local wp={ x=point.x, y=point.z, alt=point.y or land.getHeight({x=point.x,y=0,z=point.z}),
             speed=speed_mps or kmphToMps(30), speed_locked=true, type="Turning Point" }
  local f = (form and string.lower(form)) or "off_road"
  if f=="off_road" or f=="off road" then wp.action="Off Road"
  elseif f=="diamond" then wp.action="Diamond"
  elseif f=="cone" then wp.action="Cone"
  elseif f=="on_road" or f=="on road" then wp.action="On Road"
  else wp.action="Off Road" end
  wp.task={ id='ComboTask', params={tasks={}} }
  return wp
end

local function setTwoPointMissionDiamond(g, p2, speedKmh)
  local ctrl=g:getController(); if not ctrl then return false end
  local u1=g:getUnit(1); if not u1 then return false end
  local p1=u1:getPoint(); local here={x=p1.x,y=p1.y,z=p1.z}
  local spd=kmphToMps(speedKmh or CFG.travelSpeed_kmh)
  local wp1=buildGroundWP({x=here.x,y=here.y,z=here.z}, 'off_road', spd)
  local wp2=buildGroundWP({x=p2.x,  y=p2.y,  z=p2.z }, 'diamond',  spd)
  ctrl:setTask({ id='Mission', params={ route={ points={wp1, wp2} } } })
  return true
end

-- === Scan bâtiments décor & barycentre ===
local function isSceneryBuilding(obj)
  if not obj or not obj.isExist or not obj:isExist() then return false end
  -- Heuristique robuste : desc.category "House" ou box volumique non nulle, et pas 'TREE'
  local ok, desc = pcall(Object.getDesc, obj)
  if ok and desc then
    if desc.category and (tostring(desc.category):lower():find("house") or desc.category==3) then return true end
    if desc.life and desc.life>0 and desc.box and desc.box.max and desc.box.min then
      local tn = (obj.getTypeName and obj:getTypeName()) or ""
      if not tostring(tn):upper():find("TREE") then return true end
    end
  else
    -- fallback: typeName non vide & pas "TREE"
    local tn = (obj.getTypeName and obj:getTypeName()) or ""
    if tn ~= "" and not tostring(tn):upper():find("TREE") then return true end
  end
  return false
end

local function findBuildingsCentroid(center, radius, minCount)
  local found={}
  world.searchObjects(Object.Category.SCENERY,
    { id=world.VolumeType.SPHERE, params={ point={x=center.x, y=0, z=center.z}, radius=radius } },
    function(obj)
      if isSceneryBuilding(obj) then
        local p=obj:getPoint()
        found[#found+1]={x=p.x, y=p.y, z=p.z}
      end
      return true
    end)
  if #found < (minCount or CFG.minBuildings) then return nil end
  local sx,sz,sy=0,0,0
  for _,p in ipairs(found) do sx=sx+p.x; sz=sz+p.z; sy=sy+p.y end
  local n=#found
  return { x=sx/n, z=sz/n, y=sy/n }
end

-- === MANPAD spawn (selon coalition) ===
local function spawnManpadNear(u)
  if not u or not Unit.isExist(u) then return end
  local side = u:getCoalition()
  local countryId = u:getCountry()
  local ut
  if side == coalition.side.BLUE then
    ut = "Soldier stinger"      -- nom d’unité DCS courant (US)
  else
    ut = "SA-18 Igla manpad"    -- nom d’unité DCS courant (RU)
  end
  local p = u:getPoint()
  local offset = { x = p.x + math.random(-12,12), y = p.y, z = p.z + math.random(-12,12) }

  local grpName = string.format("MANPAD_%s_%d", u:getGroup():getName(), math.random(1000,9999))
  local tpl = {
    category = Group.Category.GROUND,
    country = countryId,
    coalition = side,
    name = grpName,
    task = "Ground Nothing",
    route = { points = {
      { x = offset.x, y = offset.z, alt = offset.y, type="Turning Point", action="Off Road",
        speed=0, speed_locked=true, task={ id='ComboTask', params={tasks={}} } }
    }},
    units = { {
      type = ut, name = grpName.."_1", x = offset.x, y = offset.z, heading = 0,
    } }
  }
  coalition.addGroup(countryId, Group.Category.GROUND, tpl)
end

-- === État par convoi ===
local STATE = {} -- [groupName] = { decided=false, go=false, diverted=false, target=nil, lastAttack=t, timerHandle=nil, manpadDone=false }

local function getGroupState(g)
  local n=g:getName()
  local st=STATE[n]
  if not st then st={ decided=false, go=false, diverted=false, target=nil, lastAttack=nil, timerHandle=nil, manpadDone=false } STATE[n]=st end
  return st
end

-- === Départ vers le barycentre (une seule décision) ===
local function decideAndMaybeGo(g, centroid)
  if not g or not Group.isExist(g) then return end
  local st=getGroupState(g)
  if st.decided then return end
  st.decided = true
  st.go = (math.random(100) <= (CFG.goProbability_pct or 75))
  if not st.go then return end

  -- Départ : RSL patchera setTwoPointMissionDiamond pour sauvegarder le plan courant
  setTwoPointMissionDiamond(g, centroid, CFG.travelSpeed_kmh)
  st.diverted = true
  st.target = centroid
end

-- === Sur zone : dépôt éventuel d’un MANPAD si IFV/APC présent ===
local function maybeDropManpad(g)
  if not g or not Group.isExist(g) then return end
  local st=getGroupState(g)
  if st.manpadDone then return end
  if math.random(100) > (CFG.manpadChance_pct or 30) then st.manpadDone=true; return end
  local us=g:getUnits(); if not us then return end
  -- choisir un IFV/APC
  local cand={}
  for _,u in ipairs(us) do if u and Unit.isExist(u) and (isIFV(u) or isAPC(u)) then cand[#cand+1]=u end end
  if #cand==0 then st.manpadDone=true; return end
  local u = cand[math.random(1,#cand)]
  spawnManpadNear(u)
  st.manpadDone = true
end

-- === Tick de suivi arrivée + reprise route si calme 5 min ===
local function followTick(args, time)
  for name,st in pairs(STATE) do
    local g=Group.getByName(name)
    if g and Group.isExist(g) then
      -- arrivée proche de la cible ?
      if st.diverted and st.target then
        local u1=g:getUnit(1)
        if u1 then
          local p=posXZ(u1)
          if dist2D(p, st.target) <= 120 then
            maybeDropManpad(g)
          end
        end
      end
      -- reprise si calme 5 min
      if st.diverted and st.lastAttack and (timer.getTime() - st.lastAttack >= CFG.resumeQuiet_s) then
        -- on repasse par RSL pour restaurer le plan sauvegardé (script/ME)
        if RSL and RSL.restoreOrResume then
          RSL.restoreOrResume(g)
        end
        st.diverted=false
        -- on ne re-décide plus : une seule décision par convoi
      end
    end
  end
  timer.scheduleFunction(followTick, {}, timer.getTime()+1.0)
end

-- === Détection des attaques aériennes : HIT/DEAD sur une unité du convoi, initiateur héli/avion ===
local function isAirUnit(obj)
  if not obj or not obj.getCategory then return false end
  local ok, cat = pcall(obj.getCategory, obj)
  if ok and (cat==Object.Category.UNIT) then
    local u = obj
    local tn = (u.getTypeName and u:getTypeName()) or ""
    tn = string.lower(tn)
    if tn:find("helicopter") or tn:find("mi%-") or tn:find("ah%-") or tn:find("ka%-")
       or tn:find("uh%-") or tn:find("ch%-") then return true end
    if tn:find("f%-") or tn:find("^su") or tn:find("^mig") or tn:find("a%-10") or tn:find("mirage")
       or tn:find("tornado") or tn:find("typhoon") or tn:find("hornet") or tn:find("viper") then return true end
  end
  return false
end

local function handleAirAttackOnGroup(g)
  if not g or not Group.isExist(g) then return end
  if groupExcludedByName(g:getName()) then return end
  local st=getGroupState(g)
  st.lastAttack = timer.getTime()

  -- si déjà décidé (go/no-go), ne rien replanifier
  if st.decided then return end

  -- planifier la décision dans 15–30s (unique)
  local delay = (CFG.decisionDelayMin_s or 15) + math.random()*((CFG.decisionDelayMax_s or 30) - (CFG.decisionDelayMin_s or 15))
  timer.scheduleFunction(function()
    if not Group.isExist(g) then return end
    -- recheck : si déjà décidé, on sort
    local st2=getGroupState(g); if st2.decided then return end
    -- chercher des bâtiments autour du leader
    local u1=g:getUnit(1); if not u1 then return end
    local center = posXZ(u1)
    local centroid = findBuildingsCentroid(center, CFG.scanRadius_m, CFG.minBuildings)
    if centroid then
      decideAndMaybeGo(g, centroid)
    else
      -- pas de village => décision quand même (ne va pas bouger)
      st2.decided = true; st2.go=false
    end
  end, {}, timer.getTime()+delay)
end

-- === Event handler principal (convois) ===
local EH = {}
function EH:onEvent(e)
  if not e then return end

  if e.id == world.event.S_EVENT_HIT then
    local tgt = e.target
    local atk = e.initiator
    if tgt and tgt.getGroup and atk then
      local g = tgt:getGroup()
      if g and Group.isExist(g) and not groupExcludedByName(g:getName()) then
        -- un véhicule détruit ou endommagé => HIT suffit
        if isAirUnit(atk) then handleAirAttackOnGroup(g) end
      end
    end
    return
  end

  if e.id == world.event.S_EVENT_DEAD then
    local tgt = e.initiator or e.target
    local atk = e.initiator
    if tgt and tgt.getGroup then
      local ok,g = pcall(tgt.getGroup, tgt)
      if ok and g and Group.isExist(g) and not groupExcludedByName(g:getName()) then
        if atk and isAirUnit(atk) then handleAirAttackOnGroup(g) end
      end
    end
    return
  end
end
world.addEventHandler(EH)

-- === Boot : uniquement suivi, plus de snapshot RTE automatique ===
timer.scheduleFunction(followTick, {}, timer.getTime()+1.0)

----------------------------------------------------------------
-- SAM/AAA COVER-CRAWL (MANPADS inclus) — nearest hide & robust resume
----------------------------------------------------------------

local CFG = {
  threatRange_m      = 8500,     -- 8.5 km
  scanBuildings_m    = 1500,     -- recherche bâtiments
  maxHideHop_m       = 600,      -- distance max souhaitée vers une nouvelle cache (si possible)

  minHideDist_m      = 12,       -- derrière le bâtiment
  exposeAhead_m      = 25,       -- devant le bâtiment (côté menace)
  moveSpeed_kmh      = 80,

  hideTimeMin_s      = 30,
  hideTimeMax_s      = 45,
  exposeTimeMin_s    = 10,
  exposeTimeMax_s    = 30,
  resumeSpeed_kmh    = 40,   -- vitesse minimale à appliquer lors de la reprise de route

  calmResume_s       = 60,       -- pas de menace depuis 60s => reprise route

  tick_s             = 1.0,
}

-- === Helpers
local function kmphToMps(kmh) return (kmh or 0)/3.6 end
local function dist2D(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx+dz*dz) end
local function norm2D(v) local L=math.sqrt(v.x*v.x+v.z*v.z); if L<1e-6 then return {x=1,z=0},0 end; return {x=v.x/L,z=v.z/L},L end
local function add2(a,b) return {x=a.x+b.x, y=(a.y or 0)+(b.y or 0), z=a.z+b.z} end
local function sub2(a,b) return {x=a.x-b.x, y=0, z=a.z-b.z} end
local function mul2(v,s) return {x=v.x*s, y=0, z=v.z*s} end
local function posXZ(obj) local p=obj:getPoint(); return {x=p.x, y=p.y, z=p.z} end

-- === Filtre groupes SAM/AAA only
local function isAirDef(u)
  return Unit.hasAttribute(u,"Air Defence") or Unit.hasAttribute(u,"AirDefence") or Unit.hasAttribute(u,"AAA") or Unit.hasAttribute(u,"SAM")
end
local function groupIsExclusiveAirDef(g)
  if not g or not Group.isExist(g) then return false end
  local us=g:getUnits(); if not us or #us==0 then return false end
  for _,u in ipairs(us) do
    if not (u and Unit.isExist(u) and isAirDef(u)) then return false end
  end
  return true
end

-- === Détection menace aérienne
local DET={}
pcall(function()
  DET.RADAR=Controller.Detection.RADAR; DET.OPTIC=Controller.Detection.OPTIC
  DET.IRST=Controller.Detection.IRST;   DET.RWR=Controller.Detection.RWR
  DET.DLINK=Controller.Detection.DLINK
end)

local function isAirUnit(u)
  if not u or not Unit.isExist(u) then return false end
  local cat = u:getDesc() and u:getDesc().category
  if cat==0 or cat==1 then return true end
  local tn = string.lower(u:getTypeName() or "")
  if tn:find("helicopter") or tn:find("ah%-") or tn:find("ka%-") or tn:find("mi%-") then return true end
  if tn:find("f%-") or tn:find("^su") or tn:find("^mig") or tn:find("mirage") or tn:find("tornado") or tn:find("typhoon")
     or tn:find("hornet") or tn:find("viper") or tn:find("a%-10") then return true end
  return false
end

local function controllerSees(ctrl, tgt)
  if not ctrl or not tgt then return false end
  local ok, seen = pcall(function()
    return (ctrl:isTargetDetected(tgt, DET.RADAR) or ctrl:isTargetDetected(tgt, DET.OPTIC)
         or ctrl:isTargetDetected(tgt, DET.IRST)  or ctrl:isTargetDetected(tgt, DET.RWR)
         or ctrl:isTargetDetected(tgt, DET.DLINK))
  end)
  return ok and seen
end

local sides = { coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL }

local _samSideIndex = 1

local function findNearestAirThreat(u, maxR)
  local up = u:getPoint()
  local ctrl = u:getController()
  local mySide = u:getCoalition()
  local bestT, bestD = nil, 1e15
  for _,side in ipairs(sides) do
    if side ~= mySide then
      local function scanGroupCat(cat)
        local gs = coalition.getGroups(side, cat)
        if not gs then return end
        for _,g in ipairs(gs) do
          local us = g:getUnits()
          if us then
            for _,t in ipairs(us) do
              if t and Unit.isExist(t) then
                local tp=t:getPoint()
                local dx, dz = tp.x - up.x, tp.z - up.z
                local d = math.sqrt(dx*dx + dz*dz)
                if d <= maxR and controllerSees(ctrl, t) then
                  if d < bestD then bestD, bestT = d, t end
                end
              end
            end
          end
        end
      end
      scanGroupCat(Group.Category.AIRPLANE)
      scanGroupCat(Group.Category.HELICOPTER)
    end
  end
  return bestT, bestD
end

-- === Bâtiments & points cover/expose
local function isSceneryBuilding(obj)
  if not obj or not obj.isExist or not obj:isExist() then return false end
  local ok, desc = pcall(Object.getDesc, obj)
  if ok and desc then
    if desc.category and (tostring(desc.category):lower():find("house") or desc.category==3) then return true end
    if desc.life and desc.life>0 and desc.box and desc.box.max and desc.box.min then
      local tn = (obj.getTypeName and obj:getTypeName()) or ""
      if not tostring(tn):upper():find("TREE") then return true end
    end
  else
    local tn = (obj.getTypeName and obj:getTypeName()) or ""
    if tn ~= "" and not tostring(tn):upper():find("TREE") then return true end
  end
  return false
end

local function collectBuildings(center, radius)
  local res={}
  world.searchObjects(Object.Category.SCENERY,
    { id=world.VolumeType.SPHERE, params={ point={x=center.x, y=0, z=center.z}, radius=radius } },
    function(obj)
      if isSceneryBuilding(obj) then
        local p=obj:getPoint()
        res[#res+1]={x=p.x,y=p.y,z=p.z,_obj=obj}
      end
      return true
    end)
  return res
end

-- 👉 Choix “proche” : on privilégie la proximité à l’ANCRAGE (position actuelle du leader).
-- On limite le saut à CFG.maxHideHop_m si possible.
local function chooseNearestBuilding(buildings, anchorPos, used)
  if not buildings or #buildings==0 then return nil end
  local cand={}
  local closest, closestD = nil, 1e15
  for _,b in ipairs(buildings) do
    local skip=false
    if used then
      for _,u in ipairs(used) do
        if dist2D(b,u) < 40 then skip=true; break end
      end
    end
    if not skip then
      local d = dist2D(b, anchorPos)
      if d < (CFG.maxHideHop_m or 1e9) then
        cand[#cand+1]=b
      end
      if d < closestD then closestD = d; closest = b end
    end
  end
  if #cand==0 then cand={closest} end  -- si rien dans le rayon max, on prend le plus proche absolu
  if not cand or #cand==0 then return nil end
  table.sort(cand, function(a,b) return dist2D(a, anchorPos) < dist2D(b, anchorPos) end)
  -- petit random parmi les 3 plus proches pour éviter le ping-pong
  local k = math.min(3, #cand)
  return cand[ math.random(1,k) ]
end

local function coverAndExposePoints(buildingPos, threatPos)
  local dir = { x = buildingPos.x - threatPos.x, z = buildingPos.z - threatPos.z }
  local n,_ = norm2D(dir)
  local cover  = add2(buildingPos, mul2(n, CFG.minHideDist_m))              -- derrière
  local expose = add2(buildingPos, mul2({x=-n.x,z=-n.z}, CFG.exposeAhead_m)) -- devant
  cover.y  = land.getHeight({x=cover.x,  y=0, z=cover.z})
  expose.y = land.getHeight({x=expose.x, y=0, z=expose.z})
  return cover, expose
end

-- === Missions déplacement
local function buildWP(point, action, spd_mps)
  return {
    x=point.x, y=point.z, alt=point.y or land.getHeight({x=point.x,y=0,z=point.z}),
    type="Turning Point", action=action or "Off Road",
    speed=spd_mps or kmphToMps(CFG.moveSpeed_kmh), speed_locked=true,
    task={ id='ComboTask', params={tasks={}} }
  }
end
local function setMissionTwoPoints(g, p1, p2, action2)
  local ctrl=g:getController(); if not ctrl then return false end
  local spd=kmphToMps(CFG.moveSpeed_kmh)
  local wp1=buildWP(p1, "Off Road", spd)
  local wp2=buildWP(p2, action2 or "Off Road", spd)
  ctrl:setTask({ id='Mission', params={ route={ points={ wp1, wp2 } } } })
  return true
end

-- === État groupe
-- mode: "IDLE" | "HIDE" | "EXPOSE"
local STATE = {} -- [groupName] = { mode, calmStart, used={}, coverP=nil, exposeP=nil, nextSwitchAt=0 }
local function stFor(g)
  local n=g:getName(); local s=STATE[n]
  if not s then s={mode="IDLE", calmStart=nil, used={}, nextSwitchAt=0} STATE[n]=s end
  return s
end

-- === Traitement par groupe
local function processGroup(g, now)
  if not g or not Group.isExist(g) then return end
  if not groupIsExclusiveAirDef(g) then return end

  local s = stFor(g)
  local u1 = g:getUnit(1); if not (u1 and Unit.isExist(u1)) then return end

  local threat, d = findNearestAirThreat(u1, CFG.threatRange_m)
  if not threat then
    if not s.calmStart then s.calmStart = now end
    if (now - s.calmStart) >= CFG.calmResume_s then
      if s.mode ~= "IDLE" then
        -- on restaure d'abord un éventuel plan sauvegardé (script/ME)
        if RSL and RSL.restoreOrResume then
          RSL.restoreOrResume(g)
        end
      end
      s.mode="IDLE"; s.used={}; s.coverP=nil; s.exposeP=nil; s.nextSwitchAt=0
    end
    return
  else
    s.calmStart = nil
  end

  local here = posXZ(u1)

  if s.mode=="IDLE" or s.mode=="EXPOSE" then
    local buildings = collectBuildings(here, CFG.scanBuildings_m)
    if #buildings >= 1 then
      -- on choisit par proximité AU GROUPE (here)
      local choice = chooseNearestBuilding(buildings, here, s.used)
      if choice then
        local cover, expose = coverAndExposePoints(choice, posXZ(threat))
        s.coverP = cover; s.exposeP = expose
        s.used[#s.used+1] = {x=choice.x,y=choice.y,z=choice.z}
        -- avant de partir se cacher, on snapshot le plan courant
        if RSL and RSL.push then RSL.push(g) end
        setMissionTwoPoints(g, here, cover, "Off Road")
        s.mode = "HIDE"
        s.nextSwitchAt = now + (CFG.hideTimeMin_s + math.random()*(CFG.hideTimeMax_s - CFG.hideTimeMin_s))
        return
      end
    end
    return
  end

  if s.mode=="HIDE" then
    if now >= s.nextSwitchAt then
      if s.exposeP then
        setMissionTwoPoints(g, here, s.exposeP, "Off Road")
        s.mode="EXPOSE"
        s.nextSwitchAt = now + (CFG.exposeTimeMin_s + math.random()*(CFG.exposeTimeMax_s - CFG.exposeTimeMin_s))
      else
        s.mode="EXPOSE"; s.nextSwitchAt = now + 5
      end
    end
    return
  end
end

-- === Boucles SAM/AAA
local function tick()
  local now = timer.getTime()

  -- On étale la charge : un seul camp traité par tick
  local side = sides[_samSideIndex]
  _samSideIndex = _samSideIndex + 1
  if _samSideIndex > #sides then _samSideIndex = 1 end

  local gs = coalition.getGroups(side, Group.Category.GROUND)
  if gs then
    for _,g in ipairs(gs) do
      processGroup(g, now)
    end
  end

  timer.scheduleFunction(tick, {}, now + CFG.tick_s)
end

local function postTick()
  local now = timer.getTime()
  for name,s in pairs(STATE) do
    if s.mode=="EXPOSE" and now >= (s.nextSwitchAt or 0) then
      -- Forcer une nouvelle recherche de cache au prochain tick
      s.mode="IDLE"
    end
  end
  timer.scheduleFunction(postTick, {}, now + 0.5)
end

-- Boot : seulement la logique de crawl
timer.scheduleFunction(tick, {}, timer.getTime()+1.0)
timer.scheduleFunction(postTick, {}, timer.getTime()+0.7)


----------------------------------------------------------------
-- ROUTE SAVER LAYER (RSL) — sauvegarde/restitue le plan de route
-- s’applique à : Tanks/IFV, Convois, SAM/AAA
----------------------------------------------------------------

-- ==== Pré-requis légers ====
local function _kmh2mps(k) return (k or 0)/3.6 end
local function _posAlt(x,z) return land.getHeight({x=x,y=0,z=z})+0.5 end
local function _dist2(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx+dz*dz) end

-- ==== Helpers nom groupe ====
local function _grpName(g) return (type(g)=="table" and g.getName and g:getName()) or (type(g)=="string" and g) or nil end

-- ==== Extension RTE : build d’un task de reprise "maintenant" ====
if not RTE then RTE = {} end

RTE._resumeMinKmh = RTE._resumeMinKmh or 40

function RTE._findMEGroupByName(gName)
  if not env or not env.mission or not env.mission.coalition then return nil end
  for _, sideTbl in pairs(env.mission.coalition) do
    local ctry = sideTbl and sideTbl.country
    if ctry then
      for _,cty in ipairs(ctry) do
        local c=cty.country or cty
        local t=c['vehicle']; if t and t.group then
          for _,grp in ipairs(t.group) do if grp and grp.name==gName then return grp end end
        end
      end
    end
  end
  return nil
end

function RTE._deepCopyTask(t)
  if type(t)~='table' then return {id='ComboTask',params={tasks={}}} end
  local c={}; for k,v in pairs(t) do c[k]=v end
  if not (c.params and c.params.tasks) then c={id='ComboTask',params={tasks={}}} end
  return c
end

function RTE._getRouteME(gName)
  local g=RTE._findMEGroupByName(gName)
  if not g or not g.route or not g.route.points then return nil end
  local pts={}
  for i,wp in ipairs(g.route.points) do
    pts[#pts+1]={
      idx=i,
      vec3={x=wp.x,y=(wp.alt or 0),z=wp.y},
      alt=wp.alt, alt_type=wp.alt_type,
      speed=wp.speed, speed_locked=wp.speed_locked,
      ETA=wp.ETA, ETA_locked=wp.ETA_locked,
      type=wp.type, action=wp.action, name=wp.name,
      task=RTE._deepCopyTask(wp.task)
    }
  end
  return pts
end

_G.ROUTE_DB = _G.ROUTE_DB or {}
function RTE.captureGroupIfNeeded(g)
  if not g or not Group.isExist(g) then return end
  local name=g:getName()
  if ROUTE_DB[name] and ROUTE_DB[name].routeME then return end
  local me=RTE._getRouteME(name); if not me or #me==0 then return end
  ROUTE_DB[name]={ routeME=me }
end

local function _pickResumeIndex(name, here)
  local rec=ROUTE_DB[name]; if not rec then return 1 end
  local r=rec.routeME; if not r or #r==0 then return 1 end
  local bestI, bestD = 1, 1e15
  for i=1,#r do
    local p=r[i].vec3
    local d=_dist2(here,{x=p.x,z=p.z})
    if d<bestD then bestD, bestI=d,i end
  end
  if bestD < 40 and bestI < #r then return bestI+1 end
  return bestI
end

function RTE.buildResumeTaskNow(g)
  if not g or not Group.isExist(g) then return nil end
  local name=g:getName()
  RTE.captureGroupIfNeeded(g)
  local rec=ROUTE_DB[name]; if not rec or not rec.routeME or #rec.routeME==0 then return nil end

  local lead=g:getUnit(1); if not lead then return nil end
  local L=lead:getPoint(); local here={x=L.x, y=L.y, z=L.z}
  local route=rec.routeME
  local k=_pickResumeIndex(name, {x=here.x,z=here.z})

  local minSpd = _kmh2mps(RTE._resumeMinKmh or 40)
  local pts={}

  local act = route[k].action or "On Road"
  pts[#pts+1]={
    x=here.x, y=here.z, alt=here.y,
    speed=minSpd, speed_locked=true,
    type="Turning Point", action=act,
    task={ id='ComboTask', params={tasks={}} }
  }

  local wp=route[k]
  local tx,tz,ty = wp.vec3.x, wp.vec3.z, (wp.alt or wp.vec3.y)
  pts[#pts+1]={
    x=tx, y=tz, alt=ty,
    speed=(wp.speed and wp.speed>0) and math.max(wp.speed, minSpd) or minSpd, speed_locked=true,
    type=wp.type or "Turning Point", action=wp.action or act,
    task=RTE._deepCopyTask(wp.task)
  }

  for i=k+1,#route do
    local w=route[i]
    local s=(w.speed and w.speed>0) and math.max(w.speed, minSpd) or minSpd
    pts[#pts+1]={
      x=w.vec3.x, y=w.vec3.z, alt=w.alt or w.vec3.y,
      speed=s, speed_locked=true,
      type=w.type or "Turning Point", action=w.action or "On Road",
      task=RTE._deepCopyTask(w.task)
    }
  end

  return { id='Mission', params={ route={ points=pts } } }
end

-- ==== RSL : pile de sauvegarde par groupe ====
RSL = RSL or { saved = {} }
local RSL = RSL

function RSL.push(g)
  if not g or not Group.isExist(g) then return false end
  local name = g:getName()

  local ctrl = g:getController()
  if not ctrl then return false end

  local task = nil
  -- 1) on tente d'abord de récupérer le task courant (inclut les ordres script)
  local ok, current = pcall(ctrl.getTask, ctrl)
  if ok and current and type(current) == 'table' then
    task = current
  elseif RTE and RTE.buildResumeTaskNow then
    -- 2) fallback : on reconstruit un task depuis la route ME
    task = RTE.buildResumeTaskNow(g)
  end

  if not task then return false end
  RSL.saved[name] = { task = task, savedAt = timer.getTime() }
  return true
end


function RSL.have(g)
  local name=_grpName(g); if not name then return false end
  return RSL.saved[name] ~= nil
end

function RSL.restore(g)
  if not g or not Group.isExist(g) then return false end
  local name=g:getName()
  local rec=RSL.saved[name]; if not rec then return false end
  local ctrl=g:getController(); if not ctrl then return false end
  ctrl:setTask(rec.task)
  RSL.saved[name]=nil
  return true
end

-- Enregistrer explicitement un plan de route pour un groupe (depuis un autre script)
function RSL.saveMissionForGroup(g, missionTask)
  if not g or not Group.isExist(g) then return false end
  if not missionTask or type(missionTask) ~= "table" then return false end
  local name = g:getName()
  RSL.saved[name] = { task = missionTask, savedAt = timer.getTime() }
  return true
end


function RSL.restoreOrResume(gOrName)
  local g = type(gOrName)=="string" and Group.getByName(gOrName) or gOrName
  if g and Group.isExist(g) then
    if RSL.restore(g) then return true end
    -- fallback : reprise classique RTE si dispo
    if RTE and RTE.buildResumeTaskNow then
      local t=RTE.buildResumeTaskNow(g)
      if t then g:getController():setTask(t); return true end
    end
  end
  return false
end

-- ==== Wrapper : appliquer une manœuvre en sauvegardant d’abord ====
function RSL.applyTask(g, missionTask)
  if not g or not Group.isExist(g) then return false end
  local ctrl=g:getController(); if not ctrl then return false end
  -- À chaque manœuvre, on met à jour le snapshot
  RSL.push(g)
  ctrl:setTask(missionTask)
  return true
end

----------------------------------------------------------------
-- PATCH AUTOMATIQUE DES FONCTIONS DE MANOEUVRE
----------------------------------------------------------------

-- Helpers pour (re)construire un WP similaire
local function _buildWP(point, action, spd_mps)
  return {
    x=point.x, y=point.z, alt=point.y or _posAlt(point.x, point.z),
    type="Turning Point", action=action or "Off Road",
    speed=spd_mps or _kmh2mps(30), speed_locked=true,
    task={ id='ComboTask', params={tasks={}} }
  }
end

-- 1) Patch setTwoPointMissionDiamond
do
  local _orig = rawget(_G, "setTwoPointMissionDiamond")
  if _orig then
    _G.setTwoPointMissionDiamond = function(g, p2, speedKmh)
      if not g or not Group.isExist(g) then return false end
      local u1=g:getUnit(1); if not u1 then return false end
      local p1=u1:getPoint(); local here={x=p1.x,y=p1.y,z=p1.z}
      local spd=_kmh2mps(speedKmh or 40)
      local wp1=_buildWP(here, 'Off Road', spd)
      local wp2=_buildWP(p2,   'Diamond',  spd)
      local task={ id='Mission', params={ route={ points={wp1,wp2} } } }
      return RSL.applyTask(g, task)
    end
  end
end

-- 2) Patch setTwoPointMission (depuis une unité)
do
  local _orig = rawget(_G, "setTwoPointMission")
  if _orig then
    _G.setTwoPointMission = function(u, p2, speedKmh)
      if not u or not Unit.isExist(u) then return false end
      local g=u:getGroup(); if not g then return false end
      local p1=u:getPoint(); local here={x=p1.x,y=p1.y,z=p1.z}
      local spd=_kmh2mps(speedKmh or 40)
      local wp1=_buildWP(here, 'Off Road', spd)
      local wp2=_buildWP(p2,   'Diamond',  spd)  -- on force Diamond comme avant
      local task={ id='Mission', params={ route={ points={wp1,wp2} } } }
      return RSL.applyTask(g, task)
    end
  end
end

-- 3) Patch setMissionTwoPoints (SAM/AAA)
do
  local _orig = rawget(_G, "setMissionTwoPoints")
  if _orig then
    _G.setMissionTwoPoints = function(g, p1, p2, action2)
      if not g or not Group.isExist(g) then return false end
      local spd=_kmh2mps(80)
      local wp1=_buildWP(p1, "Off Road", spd)
      local wp2=_buildWP(p2, action2 or "Off Road", spd)
      local task={ id='Mission', params={ route={ points={wp1,wp2} } } }
      return RSL.applyTask(g, task)
    end
  end
end

----------------------------------------------------------------
-- REMPLACE RTE.resume POUR PRIVILÉGIER LA RESTITUTION EXACTE
----------------------------------------------------------------
if RTE and RTE.resume and not RTE._orig_resume then
  RTE._orig_resume = RTE.resume
  RTE.resume = function(groupNameOrGroup)
    local g = (type(groupNameOrGroup)=="string") and Group.getByName(groupNameOrGroup) or groupNameOrGroup
    if g and Group.isExist(g) then
      if RSL and RSL.restore(g) then return true end
    end
    -- fallback : reprise route ME « classique » si on a un snapshot RTE
    return RTE._orig_resume(groupNameOrGroup)
  end
end

----------------------------------------------------------------
-- APC ESCAPE TO BUILDING + INFANTRY DROP + RTE/RSL RESUME
----------------------------------------------------------------

-- Config APC
local APC_CFG = {
  scanRadius_m        = 1500,    -- recherche de bâtiments autour de l’APC
  fleeSpeed_kmh       = 40,      -- vitesse de fuite
  arriveRadius_m      = 120,     -- distance pour considérer “arrivé au bâtiment”
  resumeQuiet_s       = 120,     -- 120 s sans attaque => reprise route
  bigBuildingMinArea  = 400,     -- seuil surface pour “gros” bâtiment
  infantryWalkSpeed_m = 3.0,     -- ~10 km/h
  infantryWpRadius_m  = 500,     -- WP aléatoire dans un cercle de 500 m
}

-- Types APC explicitement listés (typeName DCS)
local APC_TYPES = {
  ["BRDM-2"]                 = true,
  ["BTR-80"]                 = true,
  ["BTR-82A"]                = true,
  ["M 818"]                  = true,
  ["M-113"]                  = true,
  ["M1043 HMMWV Armament"]   = true,
  ["M1126 Stryker ICV"]      = true,
  ["Ural-4320T"]             = true,
  ["MTLB"]                   = true,
  ["LAV-25"]                 = true,
}

local function apc_isAPCUnit(u)
  if not u or not u.getTypeName then return false end
  local ok, tn = pcall(u.getTypeName, u)
  if not ok or not tn then return false end
  return APC_TYPES[tn] == true
end

local function apc_groupHasAPC(g)
  if not g or not Group.isExist(g) then return false end
  local us = g:getUnits()
  if not us then return false end
  for _,u in ipairs(us) do
    if u and apc_isAPCUnit(u) then return true end
  end
  return false
end

-- Détection si l’attaquant est un char ou un IFV
local function apc_isTankOrIFV(u)
  if not u or not Unit.isExist(u) then return false end
  return Unit.hasAttribute(u,"Tanks") or Unit.hasAttribute(u,"IFV")
end

-- Helpers géo (propres à cette section pour éviter les collisions de noms)
local function apc_posXZ(obj)
  local p = obj:getPoint()
  return { x = p.x, y = p.y, z = p.z }
end

local function apc_dist2D(a,b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return math.sqrt(dx*dx + dz*dz)
end

local function apc_kmphToMps(kmh) return (kmh or 0)/3.6 end

-- Recherche du “gros bâtiment” le plus proche
local function apc_findBestBuilding(center, radius)
  local bestAny, bestAnyD = nil, 1e15
  local bestBig, bestBigD = nil, 1e15

  world.searchObjects(
    Object.Category.SCENERY,
    { id = world.VolumeType.SPHERE, params = { point = {x=center.x, y=0, z=center.z}, radius = radius } },
    function(obj)
      if not obj or not obj.isExist or not obj:isExist() then return true end

      local ok, desc = pcall(Object.getDesc, obj)
      local isBuilding = false
      local area = 0

      if ok and desc then
        local tn = (obj.getTypeName and obj:getTypeName()) or ""
        tn = tostring(tn):upper()
        if desc.box and desc.box.max and desc.box.min then
          local dx = desc.box.max.x - desc.box.min.x
          local dz = desc.box.max.z - desc.box.min.z
          area = math.abs(dx * dz)
        end
        if desc.category and (tostring(desc.category):lower():find("house") or desc.category == 3) then
          isBuilding = true
        end
        if desc.life and desc.life > 0 and area > 0 and not tn:find("TREE") then
          isBuilding = true
        end
      else
        local tn = (obj.getTypeName and obj:getTypeName()) or ""
        tn = tostring(tn):upper()
        if tn ~= "" and not tn:find("TREE") then
          isBuilding = true
        end
      end

      if isBuilding then
        local p = obj:getPoint()
        local pt = { x=p.x, y=p.y, z=p.z }
        local d = apc_dist2D(center, pt)
        if d <= radius then
          -- Meilleur “gros” bâtiment
          if area >= APC_CFG.bigBuildingMinArea and d < bestBigD then
            bestBigD = d
            bestBig  = pt
          end
          -- Meilleur tout court (fallback)
          if d < bestAnyD then
            bestAnyD = d
            bestAny  = pt
          end
        end
      end
      return true
    end
  )

  return bestBig or bestAny
end

-- Construction d’une mission 2 WP (Off Road -> Diamond) pour le groupe
local function apc_sendGroupToBuilding(g, dest)
  if not g or not Group.isExist(g) then return false end
  local ctrl = g:getController(); if not ctrl then return false end
  local u1   = g:getUnit(1); if not u1 then return false end
  local p1   = u1:getPoint()
  local spd  = apc_kmphToMps(APC_CFG.fleeSpeed_kmh or 70)

  local wp1 = {
    x = p1.x, y = p1.z,
    alt = p1.y,
    type = "Turning Point",
    action = "Off Road",
    speed = spd, speed_locked = true,
    task = { id='ComboTask', params={tasks={}} }
  }
  local wp2 = {
    x = dest.x, y = dest.z,
    alt = dest.y or land.getHeight({x=dest.x,y=0,z=dest.z}),
    type = "Turning Point",
    action = "Diamond",
    speed = spd, speed_locked = true,
    task = { id='ComboTask', params={tasks={}} }
  }

  local mission = { id='Mission', params={ route={ points={ wp1, wp2 } } } }

  if RSL and RSL.applyTask then
    return RSL.applyTask(g, mission)
  else
    -- fallback : on ne profite pas de RSL mais au moins ça bouge
    ctrl:setTask(mission)
    return true
  end
end

-- State APC par groupe
-- [groupName] = {
--   mode = "IDLE"|"FLEE",
--   lastAttack = t,
--   target = {x,y,z} ou nil,
--   infDropped = { [unitId]=true, ... }
-- }
local APC_STATE = {}

local function apc_getState(g)
  local name = g:getName()
  local st = APC_STATE[name]
  if not st then
    st = { mode="IDLE", lastAttack=nil, target=nil, infDropped={} }
    APC_STATE[name] = st
  end
  return st
end

-- Spawn d’un groupe d’infanterie à partir d’un APC donné
-- Spawn d’un groupe d’infanterie à partir d’un APC donné
-- -> l’infanterie apparaît juste à côté du véhicule (±5 m)
local function apc_spawnInfantryFromUnit(u, st)
  if not u then return end
  local id = u:getID()
  if st.infDropped[id] then return end

  local side    = u:getCoalition()
  local country = u:getCountry()
  if not country then return end

  local p = u:getPoint()
  local basePos = { x = p.x, y = p.y, z = p.z }

  local baseName = string.format("APC_INF_%s_%d_%d",
    u:getGroup():getName(), id, math.random(1000,9999))

  -- Composition Blue / Red
  local types
  if side == coalition.side.BLUE then
    types = { "Soldier M249", "Soldier M4", "Soldier M4", "Soldier RPG" }
  else
    -- par défaut tout ce qui n’est pas BLUE sera traité comme ROUGE
    types = { "Infantry AK ver2", "Infantry AK ver2", "Infantry AK ver2", "Soldier RPG" }
  end

  local units = {}
  for i,ut in ipairs(types) do
    -- chaque soldat spawn à ±5 m du véhicule
    local sx = basePos.x + math.random(-5, 5)
    local sz = basePos.z + math.random(-5, 5)
    units[#units+1] = {
      type    = ut,
      name    = baseName .. "_U" .. i,
      x       = sx,
      y       = sz,
      heading = 0,
    }
  end

  -- WP aléatoire dans un cercle de 500 m autour du véhicule
  local angle  = math.random()*2*math.pi
  local radius = math.random() * (APC_CFG.infantryWpRadius_m or 500)
  local wx     = basePos.x + math.cos(angle)*radius
  local wz     = basePos.z + math.sin(angle)*radius
  local wy     = land.getHeight({x=wx,y=0,z=wz})

  local route = {
    points = {
      {
        x = basePos.x, y = basePos.z,
        alt = basePos.y,
        type  = "Turning Point", action="Off Road",
        speed = APC_CFG.infantryWalkSpeed_m, speed_locked=true,
        task  = { id='ComboTask', params={tasks={}} }
      },
      {
        x = wx, y = wz,
        alt = wy,
        type  = "Turning Point", action="Diamond",
        speed = APC_CFG.infantryWalkSpeed_m, speed_locked=true,
        task  = { id='ComboTask', params={tasks={}} }
      }
    }
  }

  local tpl = {
    category  = Group.Category.GROUND,
    country   = country,
    coalition = side,
    name      = baseName,
    task      = "Ground Nothing",
    route     = route,
    units     = units,
  }

  coalition.addGroup(country, Group.Category.GROUND, tpl)
  st.infDropped[id] = true
end


-- Quand le groupe est arrivé au bâtiment : chaque APC lâche son groupe d’infanterie
local function apc_dropInfantryIfNeeded(g, st)
  if not g or not Group.isExist(g) then return end
  local us = g:getUnits()
  if not us then return end
  for _,u in ipairs(us) do
    if u and apc_isAPCUnit(u) then
      apc_spawnInfantryFromUnit(u, st)
    end
  end
end

-- Gestion globale d’une “attaque” sur un APC du groupe
local function apc_onGroupAttacked(g)
  if not g or not Group.isExist(g) then return end
  if EXCL and EXCL.byGroupName and EXCL.byGroupName(g:getName()) then return end
  if not apc_groupHasAPC(g) then return end

  local st  = apc_getState(g)
  local now = timer.getTime()
  st.lastAttack = now

  if st.mode ~= "FLEE" then
    local u1 = g:getUnit(1)
    if not u1 then return end
    local center = apc_posXZ(u1)
    local dest   = apc_findBestBuilding(center, APC_CFG.scanRadius_m)
    if dest then
      if apc_sendGroupToBuilding(g, dest) then
        st.mode   = "FLEE"
        st.target = dest
      end
    end
  end
end

-- Tick APC : arrivée + reprise route
local function apc_tick(args, time)
  local now = timer.getTime()
  for name,st in pairs(APC_STATE) do
    local g = Group.getByName(name)
    if not (g and Group.isExist(g)) then
      APC_STATE[name] = nil
    else
      -- Arrivée au bâtiment => drop infanterie
      if st.mode == "FLEE" and st.target then
        local u1 = g:getUnit(1)
        if u1 then
          local p  = apc_posXZ(u1)
          local d  = apc_dist2D(p, st.target)
          if d <= (APC_CFG.arriveRadius_m or 120) then
            apc_dropInfantryIfNeeded(g, st)
          end
        end
      end

      -- 120 s sans nouvelle attaque => reprise route + retour IDLE
      if st.lastAttack and (now - st.lastAttack) >= (APC_CFG.resumeQuiet_s or 120) then
        if st.mode == "FLEE" then
          if RSL and RSL.restoreOrResume then
            RSL.restoreOrResume(g)
          elseif RTE and RTE.resume then
            RTE.resume(g:getName())
          end
        end
        st.mode   = "IDLE"
        st.target = nil
      end
    end
  end

  timer.scheduleFunction(apc_tick, {}, timer.getTime() + 1.0)
end
timer.scheduleFunction(apc_tick, {}, timer.getTime() + 1.0)

-- Event handler APC : HIT / DEAD, attaquant char ou IFV
local APC_EH = {}
function APC_EH:onEvent(e)
  if not e then return end

  if e.id == world.event.S_EVENT_HIT then
    local tgt = e.target
    local atk = e.initiator
    if not tgt or not tgt.getGroup then return end

    -- NE PAS faire Unit.isExist sur tgt ici (peut être one-shot)
    local okT, tn = pcall(tgt.getTypeName, tgt)
    if not okT or not tn or not APC_TYPES[tn] then return end

    if not (atk and apc_isTankOrIFV(atk)) then return end

    local okG, g = pcall(tgt.getGroup, tgt)
    if okG and g and Group.isExist(g) then
      apc_onGroupAttacked(g)
    end
    return
  end

  if e.id == world.event.S_EVENT_DEAD then
    -- DEAD pour gérer le cas “one shot” sans HIT exploitable
    local tgt = e.target or e.initiator
    local atk = e.initiator
    if not tgt or not tgt.getGroup then return end

    local okT, tn = pcall(tgt.getTypeName, tgt)
    if not okT or not tn or not APC_TYPES[tn] then return end

    if not (atk and apc_isTankOrIFV(atk)) then return end

    local okG, g = pcall(tgt.getGroup, tgt)
    if okG and g and Group.isExist(g) then
      apc_onGroupAttacked(g)
    end
    return
  end
end
world.addEventHandler(APC_EH)
