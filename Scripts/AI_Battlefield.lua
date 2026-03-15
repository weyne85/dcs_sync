----------------------------------------------------------------
--                      AI BATTLEFIELD                        --
----------------------------------------------------------------
--[[
  SCRIPT DE CONQUÊTE DYNAMIQUE POUR DCS WORLD
  
  Ce script génère automatiquement un champ de bataille vivant avec :
  - Détection automatique des agglomérations (zones urbaines) comme objectifs
  - Système de camps logistiques (LOGI) pour chaque coalition
  - IA de conquête autonome (CONTROLE, ASSAULT, RECO, COUNTER, ARTY)
  - Gestion des captures de secteurs avec RUNNERS et MANPADS
  - Transport de troupes et cargo par hélicoptère
  - Construction de FARPs avancées
  
  ZONES REQUISES DANS L'ÉDITEUR DE MISSION :
  - BATTLEFIELD ou BATTLEFIELD_M ou BATTLEFIELD_M_TT : Zone de combat principale
  - BLUELINE / REDLINE : Lignes de défense de chaque coalition
  - LOGIBLUE / LOGIRED : Zones où les camps logistiques peuvent apparaître
  - BLUESTORE / REDSTORE (optionnel) : Dépôts pour embarquement de troupes
  - REDAFB / BLUEAFB (optionnel) : Zones contenant un aérodrome pour la CAP
  - REDCAP_## / BLUECAP_## (optionnel) : Zones de patrouille aérienne
  
  MODES DE FONCTIONNEMENT :
  - Mode AUTO : Les objectifs PRIORITY sont générés automatiquement
    en détectant les agglomérations dans la zone BATTLEFIELD
  - Mode MANUEL : Utiliser une zone BATTLEFIELD_M et des zones numérotées
    (1, 2, 3...) pour placer manuellement les objectifs. IA utilise les routes.
  - Mode MANUEL TT : Utiliser une zone BATTLEFIELD_M_TT et des zones numérotées.
    IA préfère le tout-terrain (Off Road), adapté aux maps avec peu de routes.
    
  Auteur : Projet collaboratif avec assistance IA
  Version : 2.0
--]]




----------------------------------------------------------------
--              SECTION 1 : CONFIGURATION GLOBALE             --
----------------------------------------------------------------
--[[
  Ces constantes contrôlent le comportement général du script.
  Les paramètres marqués /CONFIGURABLE/ peuvent être ajustés
  selon les besoins de la mission.
--]]

-- === DÉTECTION DES AGGLOMÉRATIONS ===
-- Ces paramètres définissent ce qui constitue une "ville" valide pour créer un objectif
local AGGLO_RADIUS_M     = 500   -- /CONFIGURABLE/ Rayon de recherche (m) pour compter les bâtiments
local AGGLO_MIN_COUNT    = 120   -- /CONFIGURABLE/ Nombre minimum de bâtiments requis dans ce rayon
                                  -- Exemple : 120 bâtiments dans 500m = agglomération valide
local GRID_STEP_M        = 450   -- Pas de la grille de scan (m) pour parcourir les zones

-- === RÈGLES DE PLACEMENT DES CAMPS LOGISTIQUES (LOGI) ===
local LOGI_MIN_DIST_SCENERY_M = 500   -- Distance minimum (m) des bâtiments/décors existants
local LOGI_DENSITY_PER_KM2    = 20    -- /CONFIGURABLE/ Surface (km²) requise par camp LOGI
                                       -- Ex: zone de 40 km² = 2 camps LOGI maximum
local LOGI_FRONT_MAX_DIST_M   = 6000  -- Distance max (m) du front pour placer un LOGI
local LOGI_JITTER_MAX_M       = 1500  -- Variation aléatoire (m) de la position finale
                                       -- 1500 pour Caucase, 500 pour Mariannes (terrains plats)
local LOGI_EXCLUSION_RADIUS   = 100   -- Rayon (m) d'exclusion autour du LOGI (FARP invisible)
local LOGI_PRECLEAR_RADIUS    = 0     -- Rayon (m) de nettoyage forcé (arbres/bâtiments) - désactivé
local LOGI_SLOPE_RADIUS       = 500   -- Rayon (m) pour tester la planéité du terrain
local LOGI_SLOPE_MAX          = 0.05  -- Pente maximale autorisée (5%) - évite les flancs de montagne

-- === CONFIGURATION DES ZONES DE TRIGGERS ===
--[[
  Définit comment chaque type de zone est traité :
  - name : Nom de la zone dans l'éditeur DCS
  - prefix : Préfixe des marqueurs générés (ex: "PRIORITY #1")
  - coalition : Camp propriétaire (nil = tous)
  - min_spacing_m : Espacement minimum entre marqueurs
  - show_to_all : Visible par toutes les coalitions sur la carte F10
--]]
local ZONES_CFG = {
  { name="BLUELINE",    prefix="DEFENDBLUE", coalition=coalition.side.BLUE,  min_spacing_m=1000, max_markers=nil, show_to_all=false },
  { name="REDLINE",     prefix="DEFENDRED",  coalition=coalition.side.RED,   min_spacing_m=1000, max_markers=nil, show_to_all=false },
  { name="LOGIBLUE",    prefix="LOGIBLUE",   coalition=coalition.side.BLUE,  min_spacing_m=nil,  max_markers=nil, show_to_all=false },
  { name="LOGIRED",     prefix="LOGIRED",    coalition=coalition.side.RED,   min_spacing_m=nil,  max_markers=nil, show_to_all=false },
  { name="BATTLEFIELD", prefix="PRIORITY",   coalition=nil,                  min_spacing_m=2000, max_markers=nil, show_to_all=true  },
}


----------------------------------------------------------------
--       SECTION 1b : ECONOMIE (MODE DECORATIF / LECTURE)      --
----------------------------------------------------------------
--[[
  Module economique en mode LECTURE SEULE.
  Calcule les valeurs des secteurs et les revenus theoriques,
  mais N'AFFECTE PAS le spawn des unites.
  
  Fonctionnalites :
  - Calcul du poids de chaque secteur (1-5) selon sa position
  - Affichage de la valeur sous le numero du secteur sur F10
  - Menu F10 pour consulter l'etat economique
--]]

ECONOMY_CFG = {
  -- Poids des secteurs selon leur position (centre = plus de valeur)
  center_weight_min = 1,    -- Poids minimum (bords)
  center_weight_max = 5,    -- Poids maximum (centre)
  
  -- Revenus
  base_income_per_min = 10,  -- Revenu de base par minute SANS secteur
  target_income_multiplier = 1.4,
  expected_unit_lifetime_min = 12,
  
  -- Couts de reference (pour calcul du besoin)
  costs = {
    controle = 80, assault = 120, reco = 40,
    runner = 15, counter = 100, da = 50,
    da_escort = 45, arty = 90, commander = 0,
  },
  
  -- Credits initiaux
  starting_credits = 100,  -- Solde de depart fixe
  min_income_ratio = 0.25,
  comeback_threshold = 0.25,
  comeback_bonus = 1.3,
  
  -- Delai avant activation de l'economie (secondes)
  activation_delay_s = 120,  -- 2 minutes
}

ECONOMY_STATE = {
  BLUE = { credits = 0, income_per_min = 0, logi_count = 0, sectors_controlled = 0 },
  RED  = { credits = 0, income_per_min = 0, logi_count = 0, sectors_controlled = 0 },
  sector_weights = {},
  sector_income = {},
  total_weight = 0,
  initialized = false,
  init_time = 0,  -- Timestamp d'initialisation
}

-- Verifie si l'economie est active (delai de 2min ecoule)
function ECON_IsActive()
  if not ECONOMY_STATE.initialized then return false end
  local elapsed = timer.getTime() - ECONOMY_STATE.init_time
  return elapsed >= ECONOMY_CFG.activation_delay_s
end

-- Verifie si une coalition peut payer un cout
function ECON_CanAfford(sideKey, cost)
  if not ECON_IsActive() then return true end  -- Gratuit pendant les 2 premieres minutes
  local state = ECONOMY_STATE[sideKey]
  if not state then return true end
  return state.credits >= cost
end

-- Deduit un cout et affiche un message debug
-- Retourne true si le paiement a ete effectue, false sinon
function ECON_Spend(sideKey, cost, unitType, logiKey)
  if not ECON_IsActive() then return true end  -- Gratuit pendant les 2 premieres minutes
  
  local state = ECONOMY_STATE[sideKey]
  if not state then return true end
  
  if state.credits < cost then
    trigger.action.outText(string.format(
      "[ECON] %s %s: REFUSE - cout=%d, credits=%.0f (insuffisant)",
      sideKey, logiKey or "?", cost, state.credits
    ), 10)
    return false
  end
  
  state.credits = state.credits - cost
  trigger.action.outText(string.format(
    "[ECON] %s %s: ACHAT %s - cout=%d, reste=%.0f pts",
    sideKey, logiKey or "?", unitType or "?", cost, state.credits
  ), 8)
  return true
end

-- Retourne le cout d'un type d'unite
function ECON_GetCost(unitType)
  return ECONOMY_CFG.costs[unitType] or 50
end

-- Calcule le centre moyen d'une liste de points
function _calcCenter(points)
  if not points or #points == 0 then return nil end
  local sx, sz = 0, 0
  for _, p in ipairs(points) do
    sx = sx + p.x
    sz = sz + p.z
  end
  return { x = sx / #points, z = sz / #points }
end

-- Calcule la distance entre deux points
function _distPts(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return math.sqrt(dx*dx + dz*dz)
end

-- Trouve le secteur le plus proche d'un point de reference
function _findClosestSector(refPt, sectors)
  if not sectors or #sectors == 0 then return nil, math.huge end
  local closest, minDist = nil, math.huge
  for _, s in ipairs(sectors) do
    local d = _distPts(refPt, s)
    if d < minDist then
      minDist = d
      closest = s
    end
  end
  return closest, minDist
end

--[[
  Calcule le poids d'un secteur selon sa position entre les secteurs extremes.
  
  Methode :
  - Trouve le secteur le plus proche de LOGIBLUE = borne "BLUE" (poids min)
  - Trouve le secteur le plus proche de LOGIRED = borne "RED" (poids min)
  - Le milieu entre ces deux bornes = poids max
  - L'echelle 1-5 commence au premier secteur, pas au LOGI
--]]
function ECON_CalcSectorWeight(sectorPt)
  local blueCenter = _calcCenter(LOGI_BLUE_POINTS)
  local redCenter = _calcCenter(LOGI_RED_POINTS)
  
  if not blueCenter or not redCenter or not BATTLEFIELD_POINTS or #BATTLEFIELD_POINTS == 0 then
    return (ECONOMY_CFG.center_weight_min + ECONOMY_CFG.center_weight_max) / 2
  end
  
  -- Trouve les secteurs extremes (les plus proches de chaque LOGI)
  local sectorNearBlue, distBlueToSector = _findClosestSector(blueCenter, BATTLEFIELD_POINTS)
  local sectorNearRed, distRedToSector = _findClosestSector(redCenter, BATTLEFIELD_POINTS)
  
  if not sectorNearBlue or not sectorNearRed then
    return (ECONOMY_CFG.center_weight_min + ECONOMY_CFG.center_weight_max) / 2
  end
  
  -- Distance entre les deux secteurs extremes (= plage de l'echelle)
  local sectorSpan = _distPts(sectorNearBlue, sectorNearRed)
  if sectorSpan < 100 then
    return (ECONOMY_CFG.center_weight_min + ECONOMY_CFG.center_weight_max) / 2
  end
  
  local halfSpan = sectorSpan / 2
  
  -- Distance du secteur courant aux secteurs extremes
  local distFromBlueSector = _distPts(sectorPt, sectorNearBlue)
  local distFromRedSector = _distPts(sectorPt, sectorNearRed)
  
  -- Calcul du ratio depuis le secteur proche de BLUE
  -- 0 (au secteur extreme) -> 1 (au milieu) -> 0 (a l'autre extreme)
  local ratioFromBlue
  if distFromBlueSector <= halfSpan then
    ratioFromBlue = distFromBlueSector / halfSpan  -- 0 -> 1
  else
    ratioFromBlue = 1 - ((distFromBlueSector - halfSpan) / halfSpan)
    ratioFromBlue = math.max(0, ratioFromBlue)
  end
  
  -- Calcul du ratio depuis le secteur proche de RED (symetrique)
  local ratioFromRed
  if distFromRedSector <= halfSpan then
    ratioFromRed = distFromRedSector / halfSpan
  else
    ratioFromRed = 1 - ((distFromRedSector - halfSpan) / halfSpan)
    ratioFromRed = math.max(0, ratioFromRed)
  end
  
  -- Moyenne des deux ratios
  local avgRatio = (ratioFromBlue + ratioFromRed) / 2
  
  -- Interpolation : ratio 0 = min, ratio 1 = max
  local weight = ECONOMY_CFG.center_weight_min + avgRatio * (ECONOMY_CFG.center_weight_max - ECONOMY_CFG.center_weight_min)
  
  return weight
end

-- Retourne le texte de valeur d'un secteur pour l'affichage F10
function ECON_GetSectorValueText(sectorIndex)
  if not ECONOMY_STATE.initialized then return "" end
  
  local weight = ECONOMY_STATE.sector_weights[sectorIndex] or 0
  local income = ECONOMY_STATE.sector_income[sectorIndex] or 0
  
  if weight == 0 then return "" end

  local weightInt = math.floor(weight + 0.5)
  
  if weightInt == 1 then return "★" end
  if weightInt == 2 then return "★★" end
  if weightInt == 3 then return "★★★" end
  if weightInt == 4 then return "★★★★" end
  if weightInt == 5 then return "★★★★★" end
  
  return string.format("[%d]", weightInt)
end

-- Initialise le systeme economique (calcul des valeurs uniquement)
function ECON_Init()
  if ECONOMY_STATE.initialized then return end
  
  local nbBlue = LOGI_BLUE_POINTS and #LOGI_BLUE_POINTS or 0
  local nbRed = LOGI_RED_POINTS and #LOGI_RED_POINTS or 0
  local nbPriority = BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS or 0
  
  if nbPriority == 0 then
    trigger.action.outText("[ECONOMIE] Aucun secteur detecte.", 10)
    return
  end
  
  ECONOMY_STATE.BLUE.logi_count = nbBlue
  ECONOMY_STATE.RED.logi_count = nbRed
  
  -- Calcul des poids par secteur
  local totalWeight = 0
  for i, pt in ipairs(BATTLEFIELD_POINTS) do
    local w = ECON_CalcSectorWeight(pt)
    ECONOMY_STATE.sector_weights[i] = w
    totalWeight = totalWeight + w
  end
  ECONOMY_STATE.total_weight = totalWeight
  
  -- Calcul du revenu theorique par secteur
  local maxLogi = math.max(nbBlue, nbRed, 1)
  local costs = ECONOMY_CFG.costs
  local lifetime = ECONOMY_CFG.expected_unit_lifetime_min
  local cycleCost = (costs.controle or 80) + (costs.assault or 120) + (costs.reco or 40) + (costs.runner or 15) * 0.5
  local needPerLogi = cycleCost / lifetime
  local targetIncome = maxLogi * needPerLogi * ECONOMY_CFG.target_income_multiplier
  local basePerWeight = targetIncome / totalWeight
  
  for i = 1, nbPriority do
    local w = ECONOMY_STATE.sector_weights[i] or 1
    ECONOMY_STATE.sector_income[i] = w * basePerWeight
  end
  
  -- Credits initiaux fixes
  local startingCredits = ECONOMY_CFG.starting_credits
  ECONOMY_STATE.BLUE.credits = startingCredits
  ECONOMY_STATE.RED.credits = startingCredits
  
  -- Enregistre le timestamp d'initialisation
  ECONOMY_STATE.init_time = timer.getTime()
  ECONOMY_STATE.initialized = true
  
  trigger.action.outText(string.format(
    "[ECONOMIE] Initialise : %d secteurs, poids total=%.1f\n" ..
    "  BLUE: %d LOGI | RED: %d LOGI\n" ..
    "  Credits initiaux: %.0f pts | Revenu base: %.0f pts/min\n" ..
    "  Economie active dans %d secondes",
    nbPriority, totalWeight, nbBlue, nbRed, startingCredits, ECONOMY_CFG.base_income_per_min, ECONOMY_CFG.activation_delay_s
  ), 15)
  
  -- Programme un message quand l'economie devient active
  timer.scheduleFunction(function()
    trigger.action.outText("[ECONOMIE] Systeme economique ACTIF - les spawns coutent desormais des credits.", 15)
  end, {}, timer.getTime() + ECONOMY_CFG.activation_delay_s)
end

-- Met a jour les revenus (appele periodiquement)
function ECON_UpdateIncomes()
  if not ECONOMY_STATE.initialized then return end
  
  for _, sideKey in ipairs({"BLUE", "RED"}) do
    local state = ECONOMY_STATE[sideKey]
    
    -- Compte les secteurs controles
    local sectorsControlled = 0
    local sectorIncome = 0
    
    for i, _ in ipairs(BATTLEFIELD_POINTS or {}) do
      -- Utilise la fonction globale PRIO_GetSectorOwner
      local owner = PRIO_GetSectorOwner and PRIO_GetSectorOwner(i)
      if owner == sideKey then
        sectorsControlled = sectorsControlled + 1
        sectorIncome = sectorIncome + (ECONOMY_STATE.sector_income[i] or 0)
      end
    end
    
    state.sectors_controlled = sectorsControlled
    
    -- Revenu = base fixe + secteurs
    local baseIncome = ECONOMY_CFG.base_income_per_min
    state.income_per_min = baseIncome + sectorIncome
  end
end

-- Tick economique (mise a jour periodique des revenus et credits)
function ECON_Tick()
  if not ECONOMY_STATE.initialized then
    return timer.getTime() + 60
  end
  
  ECON_UpdateIncomes()
  
  -- Ajoute les revenus aux credits
  ECONOMY_STATE.BLUE.credits = ECONOMY_STATE.BLUE.credits + ECONOMY_STATE.BLUE.income_per_min
  ECONOMY_STATE.RED.credits = ECONOMY_STATE.RED.credits + ECONOMY_STATE.RED.income_per_min
  
  return timer.getTime() + 60  -- Toutes les minutes
end

-- Affiche le rapport economique pour une coalition (menu F10)
function ECON_ShowReport(coalitionId)
  if not ECONOMY_STATE.initialized then
    trigger.action.outTextForCoalition(coalitionId, "[ECONOMIE] Systeme non initialise.", 10)
    return
  end
  
  local sideKey = (coalitionId == coalition.side.BLUE) and "BLUE" or "RED"
  local enemyKey = (sideKey == "BLUE") and "RED" or "BLUE"
  local state = ECONOMY_STATE[sideKey]
  local enemyState = ECONOMY_STATE[enemyKey]
  
  local msg = string.format(
    "=== RAPPORT ECONOMIQUE %s ===\n\n" ..
    "Credits: %.0f pts\n" ..
    "Revenu: +%.1f pts/min\n" ..
    "LOGI: %d\n" ..
    "Secteurs controles: %d\n\n" ..
    "--- Ennemi (%s) ---\n" ..
    "Secteurs ennemis: %d",
    sideKey,
    state.credits,
    state.income_per_min,
    state.logi_count,
    state.sectors_controlled,
    enemyKey,
    enemyState.sectors_controlled
  )
  
  trigger.action.outTextForCoalition(coalitionId, msg, 25)
end

-- Cree les menus F10 pour l'economie
function ECON_InitMenus()
  local blueMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Economie")
  missionCommands.addCommandForCoalition(coalition.side.BLUE, "Rapport economique", blueMenu,
    function() ECON_ShowReport(coalition.side.BLUE) end)
  
  local redMenu = missionCommands.addSubMenuForCoalition(coalition.side.RED, "Economie")
  missionCommands.addCommandForCoalition(coalition.side.RED, "Rapport economique", redMenu,
    function() ECON_ShowReport(coalition.side.RED) end)
end


----------------------------------------------------------------
--              SECTION 2 : GÉNÉRATEUR ALÉATOIRE (RNG)        --
----------------------------------------------------------------
--[[
  Générateur de nombres pseudo-aléatoires déterministe.
  Utilise l'algorithme LCG (Linear Congruential Generator) pour
  garantir une reproductibilité si nécessaire.
  
  Fonctions disponibles :
  - RNG.seed(s) : Initialise le générateur avec une graine
  - RNG.random() : Retourne un float entre 0 et 1
  - RNG.randomInt(a,b) : Retourne un entier entre a et b inclus
  - RNG.shuffle(t) : Mélange aléatoirement une table
--]]
RNG = RNG or {}
do
  local state = 1
  -- Initialise le générateur avec une graine (seed)
  function RNG.seed(s) 
    s = math.floor(tonumber(s) or 1)
    if s <= 0 then s = 1 end
    state = s % 2147483647
    if state == 0 then state = 1 end 
  end
  -- Génère un nombre aléatoire entre 0 et 1 (algorithme LCG)
  function RNG.random() 
    state = (state * 48271) % 2147483647
    return state / 2147483647 
  end
  -- Génère un entier aléatoire entre a et b (inclus)
  function RNG.randomInt(a, b) 
    if not b then return 1 + math.floor(RNG.random() * a) end 
    return a + math.floor(RNG.random() * (b - a + 1)) 
  end
  -- Mélange aléatoirement les éléments d'une table (Fisher-Yates)
  function RNG.shuffle(t) 
    for i = #t, 2, -1 do 
      local j = RNG.randomInt(1, i)
      t[i], t[j] = t[j], t[i] 
    end 
  end
end

-- Initialisation automatique du RNG avec le temps actuel
do
  local t
  local ok, now = pcall(function() return os and os.time and os.time() end)
  if ok and now then 
    t = now 
  elseif timer and timer.getAbsTime then 
    t = timer.getAbsTime() 
  elseif timer and timer.getTime then 
    t = timer.getTime() 
  else 
    t = 1 
  end
  RNG.seed((math.floor((t or 1) * 1000) % 2147483646) + 1)
  -- Avance le générateur de quelques itérations pour éviter les patterns initiaux
  for _ = 1, 5 do RNG.random() end
end


----------------------------------------------------------------
--              SECTION 3 : UTILITAIRES GÉOMÉTRIQUES          --
----------------------------------------------------------------
--[[
  Fonctions de base pour la manipulation de coordonnées 2D
  et les calculs géométriques (distances, polygones, etc.)
  
  Convention DCS : x = axe Est-Ouest, z = axe Nord-Sud
  (y est réservé à l'altitude dans les vecteurs 3D)
--]]

-- Crée un vecteur 2D {x, z}
function V2(x, z) return {x = x, z = z} end

-- Convertit un vertex de zone DCS en vecteur 2D
-- Gère les différents formats possibles (x/z, x/y, tableau indexé)
function toV2_vertex(p) 
  local x = p.x or (p[1] or 0) 
  local z = (p.z ~= nil) and p.z or (p.y or p[2] or 0) 
  return V2(x, z) 
end

-- Calcule la distance 2D entre deux points
function dist2D(a, b) 
  local dx, dz = a.x - b.x, a.z - b.z 
  return math.sqrt(dx * dx + dz * dz) 
end

-- Point-In-Polygon : teste si un point est à l'intérieur d'un polygone
-- Utilise l'algorithme du ray-casting (nombre de croisements impair = dedans)
function pip(pt, poly) 
  local inside = false 
  local j = #poly 
  for i = 1, #poly do 
    local xi, zi = poly[i].x, poly[i].z 
    local xj, zj = poly[j].x, poly[j].z 
    local inter = ((zi > pt.z) ~= (zj > pt.z)) and (pt.x < (xj - xi) * (pt.z - zi) / ((zj - zi) + 1e-9) + xi) 
    if inter then inside = not inside end 
    j = i 
  end 
  return inside 
end

-- Calcule la bounding box (rectangle englobant) d'un polygone
-- Retourne : minX, minZ, maxX, maxZ
function bbox(poly) 
  local minx, maxx, minz, maxz = math.huge, -math.huge, math.huge, -math.huge 
  for _, v in ipairs(poly) do 
    if v.x < minx then minx = v.x end 
    if v.x > maxx then maxx = v.x end 
    if v.z < minz then minz = v.z end 
    if v.z > maxz then maxz = v.z end 
  end 
  return minx, minz, maxx, maxz 
end

-- Calcule le centroïde (centre géométrique) d'un polygone
function zoneCenter(poly) 
  local cx, cz = 0, 0 
  for _, v in ipairs(poly) do 
    cx = cx + v.x 
    cz = cz + v.z 
  end 
  return V2(cx / #poly, cz / #poly) 
end

--[[
  Lit une zone polygonale depuis les triggers de la mission DCS.
  
  @param name : Nom de la zone à chercher
  @return : Table {poly = {...}} ou nil si non trouvée
  
  Note : Gère les différentes orthographes DCS (verticies/vertices/points)
--]]
function readPolygonZone(name)
  if not (env and env.mission and env.mission.triggers and env.mission.triggers.zones) then 
    return nil, "env.mission.triggers.zones missing" 
  end
  for _, z in ipairs(env.mission.triggers.zones) do
    if z.name == name then
      local verts = z.verticies or z.vertices or z.points
      if not (verts and #verts >= 3) then return nil, "zone is not polygon" end
      local poly = {} 
      for i, p in ipairs(verts) do poly[i] = toV2_vertex(p) end
      return { poly = poly }
    end
  end
  return nil, "zone not found"
end

-- Forward declaration nécessaire pour éviter l'erreur "nil value"
-- placeMarkers est défini plus bas mais référencé dans BATTLEFIELD_BuildManualPoints
local placeMarkers


----------------------------------------------------------------
--       SECTION 4 : MODE MANUEL (BATTLEFIELD_M)              --
----------------------------------------------------------------
--[[
  Le mode manuel permet de placer les objectifs PRIORITY à la main
  plutôt que de les générer automatiquement par détection d'agglomérations.
  
  Pour activer le mode manuel :
  1. Créer une zone polygonale nommée "BATTLEFIELD_M" dans l'éditeur
  2. Créer des zones (cercles ou polygones) nommées "1", "2", "3", etc.
     aux emplacements souhaités pour les objectifs
  
  Le script détectera automatiquement ce mode au démarrage.
--]]

BATTLEFIELD_MANUAL = BATTLEFIELD_MANUAL or false
BATTLEFIELD_OFFROAD = BATTLEFIELD_OFFROAD or false

--[[
  Détecte si le mode manuel doit être activé.
  Conditions requises :
  - Une zone "BATTLEFIELD_M" ou "BATTLEFIELD_M_TT" existe
  - Au moins une zone avec un nom numérique ("1", "2", "3"...) existe
  
  BATTLEFIELD_M    : Mode standard, l'IA utilise les routes (On Road)
  BATTLEFIELD_M_TT : Mode tout-terrain, l'IA préfère le hors-piste (Off Road)
--]]
function BATTLEFIELD_DetectManualMode()
  BATTLEFIELD_MANUAL  = false
  BATTLEFIELD_OFFROAD = false

  -- Vérifie l'existence de BATTLEFIELD_M_TT d'abord (prioritaire)
  local z, _ = readPolygonZone("BATTLEFIELD_M_TT")
  if z then
    BATTLEFIELD_OFFROAD = true
  else
    -- Sinon vérifie BATTLEFIELD_M classique
    z, _ = readPolygonZone("BATTLEFIELD_M")
  end

  if not z then
    return
  end

  local zonesTable = env
    and env.mission
    and env.mission.triggers
    and env.mission.triggers.zones

  if not zonesTable then
    return
  end

  local foundNumeric = false
  for _, zinfo in ipairs(zonesTable) do
    local nm = tostring(zinfo.name or "")
    if nm:match("^%d+$") then
      foundNumeric = true
      break
    end
  end

  if not foundNumeric then
    trigger.action.outText("[BATTLEFIELD_M] Zone BATTLEFIELD_M présente mais aucune zone numérotée (1,2,3,...) trouvée.", 10)
    return
  end

  BATTLEFIELD_MANUAL = true
  if BATTLEFIELD_OFFROAD then
    trigger.action.outText("[BATTLEFIELD_M_TT] Mode PRIORITY manuel activé — TOUT-TERRAIN (zones 1,2,3,...).", 10)
  else
    trigger.action.outText("[BATTLEFIELD_M] Mode PRIORITY manuel activé — ROUTES (zones 1,2,3,...).", 10)
  end
end

-- Construit BATTLEFIELD_POINTS à partir des zones de triggers "1","2","3",...
-- et place les marqueurs PRIORITY correspondants.
function BATTLEFIELD_BuildManualPoints()
  local zonesTable = env
    and env.mission
    and env.mission.triggers
    and env.mission.triggers.zones

  if not zonesTable then
    trigger.action.outText("[BATTLEFIELD_M] env.mission.triggers.zones introuvable.", 10)
    return
  end

  local nodes = {}

  for _, zinfo in ipairs(zonesTable) do
    local nm = tostring(zinfo.name or "")
    if nm:match("^%d+$") then
      local cx, cz

      -- Cas polygonal (poly zone)
      local verts = zinfo.verticies or zinfo.vertices or zinfo.points
      if verts and #verts >= 3 then
        local poly = {}
        for i, p in ipairs(verts) do
          poly[i] = toV2_vertex(p)
        end
        local c = zoneCenter(poly)
        cx, cz = c.x, c.z
      else
        -- Cas cercle classique : centre (x,y/z)
        local x = zinfo.x or zinfo[1] or 0
        local z = zinfo.z or zinfo.y or zinfo[2] or 0
        cx, cz = x, z
      end

      nodes[#nodes + 1] = { x = cx, z = cz, _num = tonumber(nm) }
    end
  end

  -- Tri par numéro de zone pour que zone "1" → secteur 1, zone "2" → secteur 2, etc.
  table.sort(nodes, function(a, b) return a._num < b._num end)

  if #nodes == 0 then
    trigger.action.outText("[BATTLEFIELD_M] Aucune zone numérotée (1,2,3,...) trouvée.", 10)
    return
  end

  -- On remplace complètement les BATTLEFIELD_POINTS par ces nodes
  BATTLEFIELD_POINTS = {}

  -- On réutilise la fonction existante pour placer les marqueurs PRIORITY
  -- et remplir BATTLEFIELD_POINTS en même temps.
  placeMarkers(nodes, "PRIORITY", nil, true)

  trigger.action.outText(string.format("[BATTLEFIELD_M] %d PRIORITY créés à partir des zones numérotées.", #nodes), 10)
end


----------------------------------------------------------------
--       SECTION 4b : MODE MANUEL LOGI (LOGIBLUE_M / LOGIRED_M) --
----------------------------------------------------------------
--[[
  Mode manuel pour les centres logistiques.
  
  Utilisation :
  1. Créer une zone polygonale nommée "LOGIBLUE_M" et/ou "LOGIRED_M"
  2. Créer des zones trigger nommées "B1", "B2", "B3"... pour BLUE
  3. Créer des zones trigger nommées "R1", "R2", "R3"... pour RED
  
  Le script placera les LOGI aux centres de ces zones.
--]]

LOGI_MANUAL_BLUE = LOGI_MANUAL_BLUE or false
LOGI_MANUAL_RED = LOGI_MANUAL_RED or false

--[[
  Détecte si le mode manuel LOGI doit être activé pour un camp.
  Conditions requises :
  - Une zone "LOGIBLUE_M" ou "LOGIRED_M" existe
  - Au moins une zone avec le préfixe correspondant ("B#" ou "R#") existe
--]]
function LOGI_DetectManualMode()
  LOGI_MANUAL_BLUE = false
  LOGI_MANUAL_RED = false

  local zonesTable = env
    and env.mission
    and env.mission.triggers
    and env.mission.triggers.zones

  if not zonesTable then
    return
  end

  -- Vérifie LOGIBLUE_M
  local zBlue, _ = readPolygonZone("LOGIBLUE_M")
  if zBlue then
    -- Cherche des zones B1, B2, B3...
    local foundBlue = false
    for _, zinfo in ipairs(zonesTable) do
      local nm = tostring(zinfo.name or "")
      if nm:match("^B%d+$") then
        foundBlue = true
        break
      end
    end
    
    if foundBlue then
      LOGI_MANUAL_BLUE = true
      trigger.action.outText("[LOGIBLUE_M] Mode LOGI manuel BLUE activé (zones B1, B2, B3...).", 10)
    else
      trigger.action.outText("[LOGIBLUE_M] Zone LOGIBLUE_M présente mais aucune zone B# trouvée.", 10)
    end
  end

  -- Vérifie LOGIRED_M
  local zRed, _ = readPolygonZone("LOGIRED_M")
  if zRed then
    -- Cherche des zones R1, R2, R3...
    local foundRed = false
    for _, zinfo in ipairs(zonesTable) do
      local nm = tostring(zinfo.name or "")
      if nm:match("^R%d+$") then
        foundRed = true
        break
      end
    end
    
    if foundRed then
      LOGI_MANUAL_RED = true
      trigger.action.outText("[LOGIRED_M] Mode LOGI manuel RED activé (zones R1, R2, R3...).", 10)
    else
      trigger.action.outText("[LOGIRED_M] Zone LOGIRED_M présente mais aucune zone R# trouvée.", 10)
    end
  end
end

--[[
  Construit LOGI_BLUE_POINTS à partir des zones "B1", "B2", "B3"...
  et place les marqueurs LOGIBLUE correspondants.
--]]
function LOGI_BuildManualBluePoints()
  local zonesTable = env
    and env.mission
    and env.mission.triggers
    and env.mission.triggers.zones

  if not zonesTable then
    trigger.action.outText("[LOGIBLUE_M] env.mission.triggers.zones introuvable.", 10)
    return
  end

  local nodes = {}

  for _, zinfo in ipairs(zonesTable) do
    local nm = tostring(zinfo.name or "")
    if nm:match("^B%d+$") then
      local cx, cz

      -- Cas polygonal (poly zone)
      local verts = zinfo.verticies or zinfo.vertices or zinfo.points
      if verts and #verts >= 3 then
        local poly = {}
        for i, p in ipairs(verts) do
          poly[i] = toV2_vertex(p)
        end
        local c = zoneCenter(poly)
        cx, cz = c.x, c.z
      else
        -- Cas cercle classique : centre (x,y/z)
        local x = zinfo.x or zinfo[1] or 0
        local z = zinfo.z or zinfo.y or zinfo[2] or 0
        cx, cz = x, z
      end

      nodes[#nodes + 1] = { x = cx, z = cz }
    end
  end

  if #nodes == 0 then
    trigger.action.outText("[LOGIBLUE_M] Aucune zone B# trouvée.", 10)
    return
  end

  -- On remplace complètement LOGI_BLUE_POINTS
  LOGI_BLUE_POINTS = {}
  for _, p in ipairs(nodes) do
    LOGI_BLUE_POINTS[#LOGI_BLUE_POINTS + 1] = { x = p.x, z = p.z }
  end

  -- Place les marqueurs LOGIBLUE
  placeMarkers(LOGI_BLUE_POINTS, "LOGIBLUE", coalition.side.BLUE, false)

  trigger.action.outText(string.format("[LOGIBLUE_M] %d LOGI BLUE créés à partir des zones B#.", #nodes), 10)
end

--[[
  Construit LOGI_RED_POINTS à partir des zones "R1", "R2", "R3"...
  et place les marqueurs LOGIRED correspondants.
--]]
function LOGI_BuildManualRedPoints()
  local zonesTable = env
    and env.mission
    and env.mission.triggers
    and env.mission.triggers.zones

  if not zonesTable then
    trigger.action.outText("[LOGIRED_M] env.mission.triggers.zones introuvable.", 10)
    return
  end

  local nodes = {}

  for _, zinfo in ipairs(zonesTable) do
    local nm = tostring(zinfo.name or "")
    if nm:match("^R%d+$") then
      local cx, cz

      -- Cas polygonal (poly zone)
      local verts = zinfo.verticies or zinfo.vertices or zinfo.points
      if verts and #verts >= 3 then
        local poly = {}
        for i, p in ipairs(verts) do
          poly[i] = toV2_vertex(p)
        end
        local c = zoneCenter(poly)
        cx, cz = c.x, c.z
      else
        -- Cas cercle classique : centre (x,y/z)
        local x = zinfo.x or zinfo[1] or 0
        local z = zinfo.z or zinfo.y or zinfo[2] or 0
        cx, cz = x, z
      end

      nodes[#nodes + 1] = { x = cx, z = cz }
    end
  end

  if #nodes == 0 then
    trigger.action.outText("[LOGIRED_M] Aucune zone R# trouvée.", 10)
    return
  end

  -- On remplace complètement LOGI_RED_POINTS
  LOGI_RED_POINTS = {}
  for _, p in ipairs(nodes) do
    LOGI_RED_POINTS[#LOGI_RED_POINTS + 1] = { x = p.x, z = p.z }
  end

  -- Place les marqueurs LOGIRED
  placeMarkers(LOGI_RED_POINTS, "LOGIRED", coalition.side.RED, false)

  trigger.action.outText(string.format("[LOGIRED_M] %d LOGI RED créés à partir des zones R#.", #nodes), 10)
end



----------------------------------------------------------------
--       SECTION 5 : CALCUL DES SURFACES DE ZONES             --
----------------------------------------------------------------
--[[
  Calcule et affiche les surfaces (en km²) de toutes les zones
  définies dans la mission. Utile pour le debug et l'équilibrage.
--]]

-- Table globale stockant les surfaces calculées
ZONE_AREAS_KM2 = ZONE_AREAS_KM2 or {}

-- Calcule la surface d'un polygone en m² (formule du lacet/shoelace)
function _poly_area_m2(poly) 
  local s = 0 
  local n = #poly 
  for i = 1, n do 
    local a = poly[i]
    local b = poly[(i % n) + 1]
    s = s + (a.x * b.z - b.x * a.z) 
  end 
  return math.abs(s) * 0.5 
end

-- Initialise et affiche les surfaces de toutes les zones au démarrage
function initAreas()
  local names = { "BLUELINE", "REDLINE", "BATTLEFIELD", "BATTLEFIELD_M", "BATTLEFIELD_M_TT", "LOGIBLUE", "LOGIRED", "LOGIBLUE_M", "LOGIRED_M" }

  local lines = {}
  for _, nm in ipairs(names) do
    local z = readPolygonZone(nm)
    if z then 
      local km2 = _poly_area_m2(z.poly) / 1e6
      ZONE_AREAS_KM2[nm] = km2
      lines[#lines + 1] = string.format("%s : %.2f km2", nm, km2)
    else 
      ZONE_AREAS_KM2[nm] = 0
      lines[#lines + 1] = string.format("%s : N/A", nm) 
    end
  end
  trigger.action.outText("BIENVENUE ! VOUS ALLEZ AVOIR LE PLAISIR DE VOUS ENTRETUER SUR LE TERRITOIRE SUIVANT AHAHAHAHOHOHOHO HIRK HIRK HIRK : \n [ZONES] Surfaces (km2)\n" .. table.concat(lines, "\n"), 60)
end


----------------------------------------------------------------
--       SECTION 6 : DÉTECTION DES BÂTIMENTS (SCENERY)        --
----------------------------------------------------------------
--[[
  Fonctions pour scanner les objets de décor (bâtiments, arbres...)
  et créer une grille de points à l'intérieur des zones polygonales.
  Utilisé pour détecter les agglomérations et placer les objectifs.
--]]

-- Collecte tous les bâtiments/décors à l'intérieur d'un polygone
-- @param poly : Polygone à scanner
-- @return : Table de points {x, z} représentant chaque bâtiment
function collectBuildingsInPoly(poly)
  local c = zoneCenter(poly) 
  -- Calcule le rayon max pour englober tout le polygone
  local rmax = 0 
  for _, v in ipairs(poly) do 
    local d = dist2D(c, v) 
    if d > rmax then rmax = d end 
  end
  
  local pts = {}
  -- Recherche tous les objets SCENERY dans une sphère englobante
  world.searchObjects(Object.Category.SCENERY, {
    id = world.VolumeType.SPHERE, 
    params = {
      point = {x = c.x, y = land.getHeight({x = c.x, y = c.z}), z = c.z}, 
      radius = rmax + 50
    }
  }, function(obj)
    if obj and obj.getPoint then 
      local p = obj:getPoint() 
      local p2 = V2(p.x, p.z) 
      -- Ne garde que les objets réellement dans le polygone
      if pip(p2, poly) then pts[#pts + 1] = p2 end 
    end 
    return true 
  end)
  return pts
end

-- Génère une grille de points à l'intérieur d'un polygone
-- @param poly : Polygone délimitant la zone
-- @param step : Espacement entre les points (en mètres)
-- @return : Table de points {x, z} mélangés aléatoirement
function makeGridInside(poly, step) 
  local minx, minz, maxx, maxz = bbox(poly) 
  local nodes, row = {}, 0 
  for z = minz, maxz, step do 
    -- Décalage aléatoire des rangées pour éviter un quadrillage régulier
    local shiftFrac = ((row % 2) == 0) and 0 or (RNG.random() * 0.5 - 0.25) 
    local xoff = step * shiftFrac 
    for x = minx, maxx, step do 
      local p = V2(x + xoff, z) 
      if pip(p, poly) then nodes[#nodes + 1] = p end 
    end 
    row = row + 1 
  end 
  RNG.shuffle(nodes) 
  return nodes 
end

-- Compte le nombre de bâtiments dans un rayon autour d'un point
-- @param buildings : Table de positions de bâtiments
-- @param center : Point central de recherche
-- @param radius : Rayon de recherche (en mètres)
-- @return : Nombre de bâtiments trouvés
function countBuildingsWithin(buildings, center, radius) 
  local n = 0 
  for i = 1, #buildings do 
    if dist2D(center, buildings[i]) <= radius then n = n + 1 end 
  end 
  return n 
end


----------------------------------------------------------------
--       SECTION 7 : MARQUEURS F10 ET POINTS D'INTÉRÊT        --
----------------------------------------------------------------
--[[
  Gestion des marqueurs visibles sur la carte F10 de DCS.
  Les marqueurs PRIORITY représentent les objectifs de conquête.
  Les marqueurs DEFEND représentent les positions défensives.
  Les marqueurs LOGI représentent les camps logistiques.
--]]

-- Compteur d'ID pour les marqueurs (doit être unique dans toute la mission)
local _markId = 3500000

-- Tables globales des points d'intérêt
BATTLEFIELD_POINTS = BATTLEFIELD_POINTS or {}        -- Objectifs de conquête (PRIORITY)
LOGI_BLUE_POINTS, LOGI_RED_POINTS = {}, {}           -- Camps logistiques par coalition
DEFEND_BLUE_POINTS, DEFEND_RED_POINTS = {}, {}       -- Points de défense par coalition
LOG_FARP_GROUPS = LOG_FARP_GROUPS or { BLUE = {}, RED = {} }  -- Groupes de convois FARP
LOG_FARP_STATE  = LOG_FARP_STATE  or { BLUE = {}, RED = {} }  -- État des convois FARP

--[[
  Place des marqueurs sur la carte F10 pour une liste de points.
  
  @param points : Table de points {x, z} à marquer
  @param prefix : Préfixe du texte (ex: "PRIORITY" -> "PRIORITY #1")
  @param coalitionSide : Coalition qui voit les marqueurs (nil = tous)
  @param show_to_all : Si true, visible par tous
  @return : Nombre de marqueurs placés
--]]
placeMarkers = function(points, prefix, coalitionSide, show_to_all) 
  local placed = 0 
  for idx, p in ipairs(points) do 
    _markId = _markId + 1 
    local pos = {x = p.x, y = land.getHeight({x = p.x, y = p.z}), z = p.z} 
    local txt = string.format("%s #%d", prefix, idx) 
    
    if show_to_all then 
      trigger.action.markToAll(_markId, txt, pos, true) 
    elseif coalitionSide then 
      trigger.action.markToCoalition(_markId, txt, pos, coalitionSide, true) 
    else 
      trigger.action.markToAll(_markId, txt, pos, true) 
    end 
    
    placed = placed + 1 
    -- Les marqueurs PRIORITY sont aussi stockés pour le système de conquête
    if prefix == "PRIORITY" then 
      BATTLEFIELD_POINTS[#BATTLEFIELD_POINTS + 1] = {x = p.x, z = p.z} 
    end 
  end 
  return placed 
end


----------------------------------------------------------------
--       SECTION 8 : CALCUL DES ORIENTATIONS (BEARINGS)       --
----------------------------------------------------------------
--[[
  Calcule les orientations entre les zones BLUELINE et REDLINE.
  Utilisé pour orienter les unités défensives face à l'ennemi.
--]]

-- Stocke les caps calculés (en degrés)
DEFEND_BEARINGS = DEFEND_BEARINGS or { blue_to_red_deg = nil, red_to_blue_deg = nil }

-- Calcule le cap (bearing) de a vers b en degrés (0-360)
function _bearing_deg(a, b) 
  local dx = b.x - a.x 
  local dz = b.z - a.z 
  local br = math.atan2(dx, dz) 
  local bd = math.deg(br) 
  if bd < 0 then bd = bd + 360 end 
  return bd 
end

-- Retourne le centre d'une zone par son nom
function zoneCenterFromName(nm) 
  local z = readPolygonZone(nm) 
  return z and zoneCenter(z.poly) or nil 
end

-- Calcule les caps BLUE->RED et RED->BLUE (+180° pour faire face)
function compute_caps() 
  local cB = zoneCenterFromName("BLUELINE") 
  local cR = zoneCenterFromName("REDLINE") 
  if not cB or not cR then return end 
  local b2r = _bearing_deg(cB, cR) 
  local r2b = _bearing_deg(cR, cB) 
  -- +180° car les unités doivent FAIRE FACE à l'ennemi, pas lui tourner le dos
  DEFEND_BEARINGS.blue_to_red_deg = (b2r + 180) % 360 
  DEFEND_BEARINGS.red_to_blue_deg = (r2b + 180) % 360 
end


----------------------------------------------------------------
--       SECTION 9 : CALCULS DE DISTANCE AUX BORDURES         --
----------------------------------------------------------------
--[[
  Fonctions pour calculer la distance d'un point aux bords d'un polygone.
  Utilisé notamment pour placer les LOGI près du front mais pas trop loin.
--]]

-- Distance d'un point à un segment de droite (projection orthogonale)
function dist_pt_seg(px, pz, ax, az, bx, bz)
  local vx, vz = bx-ax, bz-az
  local wx, wz = px-ax, pz-az
  local vv = vx*vx + vz*vz
  local t = (vv > 1e-9) and ((wx*vx + wz*vz) / vv) or 0
  -- Clamp t entre 0 et 1 pour rester sur le segment
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local cx, cz = ax + t*vx, az + t*vz
  local dx, dz = px - cx, pz - cz
  return math.sqrt(dx*dx + dz*dz)
end
function dist_to_poly_edges(pt, poly)
  local best=math.huge; local n=#poly
  for i=1,n do local a=poly[i]; local b=poly[(i%n)+1]; local d=dist_pt_seg(pt.x,pt.z,a.x,a.z,b.x,b.z); if d<best then best=d end end
  return best
end

-- ===== Slope check (<= 5% within 500 m) =====
function isFlatEnough(pt)
  local R = LOGI_SLOPE_RADIUS
  local samples = {
    {dx= 0,  dz= 0},
    {dx= R,  dz= 0}, {dx=-R, dz= 0},
    {dx= 0,  dz= R}, {dx= 0,  dz=-R},
    {dx= R*0.7071, dz= R*0.7071}, {dx=-R*0.7071, dz= R*0.7071},
    {dx= R*0.7071, dz=-R*0.7071}, {dx=-R*0.7071, dz=-R*0.7071},
  }
  local h0 = land.getHeight({x=pt.x, y=pt.z})
  local maxGrade = 0
  for i=2,#samples do
    local x = pt.x + samples[i].dx
    local z = pt.z + samples[i].dz
    local h = land.getHeight({x=x, y=z})
    local d = math.sqrt(samples[i].dx^2 + samples[i].dz^2)
    local g = math.abs(h - h0) / math.max(d,1)
    if g > maxGrade then maxGrade = g end
  end
  return maxGrade <= LOGI_SLOPE_MAX
end

-- ===== Front axis & distribution =====
function axis_from_poly(poly)
  local ai, aj, best=1,1,-1
  for i=1,#poly do for j=i+1,#poly do local dx,dz=poly[j].x-poly[i].x, poly[j].z-poly[i].z local d2=dx*dx+dz*dz if d2>best then best=d2; ai=i; aj=j end end end
  local a,b=poly[ai], poly[aj]; local ux,uz=b.x-a.x, b.z-a.z; local len=math.sqrt(ux*ux+uz*uz); if len<1e-6 then ux,uz=1,0; len=1 end; ux,uz=ux/len,uz/len
  local origin={x=(a.x+b.x)*0.5, z=(a.z+b.z)*0.5}
  local smin,smax=1e9,-1e9
  for i=1,#poly do local vx,vz=poly[i].x-origin.x, poly[i].z-origin.z local s=vx*ux+vz*uz if s<smin then smin=s end if s>smax then smax=s end end
  return origin,ux,uz,smin,smax
end
function selectLogiDistributed(cands, want, frontPoly)
  if want<=0 or #cands==0 then return {} end
  local origin,ux,uz,smin,smax = axis_from_poly(frontPoly)
  local proj={} for i,p in ipairs(cands) do local vx,vz=p.x-origin.x, p.z-origin.z proj[i]=vx*ux+vz*uz end
  local slots={}
  if want==1 then slots[1]=0.5*(smin+smax) else for k=1,want do slots[k]=smin+(k-0.5)*(smax-smin)/want end end
  local chosen,used={},{}
  for k=1,#slots do local bestIdx,bestDist=nil,1e9 for i=1,#cands do if not used[i] then local d=math.abs(proj[i]-slots[k]) if d<bestDist then bestDist=d; bestIdx=i end end end if bestIdx then used[bestIdx]=true; chosen[#chosen+1]=cands[bestIdx] end end
  return chosen
end

-- ===== LOGI candidates =====
function buildLogiCandidates(poly)
  local buildings=collectBuildingsInPoly(poly)
  local nodes=makeGridInside(poly, GRID_STEP_M)
  local cands={}
  for _,p in ipairs(nodes) do
    if countBuildingsWithin(buildings,p,LOGI_MIN_DIST_SCENERY_M)==0 and isFlatEnough(p) then
      cands[#cands+1]=p
    end
  end
  RNG.shuffle(cands)
  return cands, buildings
end
function filterByFrontDistance(cands, frontPoly, maxD)
  if not (frontPoly and #frontPoly>=3) then return cands end
  local out={}
  for _,p in ipairs(cands) do if dist_to_poly_edges(p, frontPoly) <= maxD then out[#out+1]=p end end
  return out
end
function jitterValidated(p0, logiPoly, frontPoly, maxD, buildings)
  for _=1,8 do
    local r = RNG.randomInt(0, LOGI_JITTER_MAX_M)
    local a = RNG.random() * 2 * math.pi
    local p = { x = p0.x + r*math.cos(a), z = p0.z + r*math.sin(a) }
    if pip(p, logiPoly)
       and dist_to_poly_edges(p, frontPoly) <= maxD
       and countBuildingsWithin(buildings, p, LOGI_MIN_DIST_SCENERY_M) == 0
       and isFlatEnough(p)
    then return p end
  end
  return p0
end

-- ===== SCENERY CLEAR (reliable) =====
function _terrainY(x,z) return land.getHeight({x=x,y=z}) end

function destroySceneryInRadius(x,z,r)
  local removed=0
  world.searchObjects(Object.Category.SCENERY, {
    id=world.VolumeType.SPHERE,
    params={ point={x=x,y=_terrainY(x,z),z=z}, radius=r }
  }, function(obj)
    if obj and obj.destroy then obj:destroy(); removed=removed+1 end
    return true
  end)
  return removed
end

-- Fallback: small blast sweep to force tree removal on maps not exposing SCENERY objects
function blastClear(x,z,r)
  local step=40
  for dz=-r,r,step do
    for dx=-r,r,step do
      local px, pz = x+dx, z+dz
      if (dx*dx+dz*dz) <= r*r then
        trigger.action.explosion({x=px, y=_terrainY(px,pz), z=pz}, 20) -- low power
      end
    end
  end
end

function tryPlaceInvisibleFARP(countryId, x, z)
  local data={country=countryId,name="INVIS_FARP_"..RNG.randomInt(10^6,10^9),type="FARP Invisible",x=x,y=z,heading=0}
  local ok=coalition.addStaticObject(countryId,data)
  if not ok then data.type="Invisible FARP"; ok=coalition.addStaticObject(countryId,data) end
  return ok
end

function preClearSceneryAroundLOGI(radius)
  local total=0
  for _,list in ipairs({LOGI_BLUE_POINTS or {}, LOGI_RED_POINTS or {}}) do
    for _,p in ipairs(list) do
      local n = destroySceneryInRadius(p.x, p.z, radius)
      if n==0 then blastClear(p.x, p.z, radius) end
      total = total + 1
    end
  end
  trigger.action.outText(string.format("[LOGI] Pre-clear scenery %dm around %d LOGI(s).", radius, total), 6)
end

function buildExclusionAt(countryId, x, z, radius)
  destroySceneryInRadius(x,z,radius)
  tryPlaceInvisibleFARP(countryId,x,z)  -- small “no-tree” core
end





-- ==== RINGS: cercles LOGI (compat "circleToAll") ====







local _ringIdBase = 7200000
function _nextRingId() _ringIdBase = _ringIdBase + 1; return _ringIdBase end

function _to255(t)
  return {
    math.floor(255*(t[1] or 1)+0.5),
    math.floor(255*(t[2] or 1)+0.5),
    math.floor(255*(t[3] or 1)+0.5),
    math.floor(255*(t[4] or 1)+0.5)
  }
end

-- coalitionId: coalition.side.BLUE / coalition.side.RED
function _circleToAll_compat(coalitionId, id, center3, radius, colorRGBA)
  local fill = { colorRGBA[1], colorRGBA[2], colorRGBA[3], 0.12 }
  -- Essai 0..1 puis 0..255 (certains builds)
  return pcall(trigger.action.circleToAll, coalitionId, id, center3, radius, colorRGBA, fill, 1, true)
      or pcall(trigger.action.circleToAll, coalitionId, id, center3, radius, _to255(colorRGBA), _to255(fill), 1, true)
end

function _polyCircleFallback(coalitionId, baseId, center3, radius, colorRGBA)
  local N, a0 = 36, 0
  local prev = nil
  for k=1,N do
    local a = a0 + (k-1)*2*math.pi/N
    local px = center3.x + radius*math.cos(a)
    local pz = center3.z + radius*math.sin(a)
    local p  = { x=px, y=land.getHeight({x=px, y=pz}), z=pz }
    if prev then
      if type(trigger.action.lineToAll)=="function" then
        pcall(trigger.action.lineToAll, coalitionId, baseId+k, prev, p, colorRGBA, 1, true)
      end
    end
    prev = p
  end
  -- fermeture
  local pFirst = {
    x = center3.x + radius, y = land.getHeight({x=center3.x+radius, y=center3.z}), z = center3.z
  }
  if type(trigger.action.lineToAll)=="function" then
    pcall(trigger.action.lineToAll, coalitionId, baseId+N+1, prev, pFirst, colorRGBA, 1, true)
  end
end

local LOGI_RING_IDS = { BLUE={}, RED={} }

function DrawAllLogiRings()
  local R = 1000  -- 1 km de diamètre
  local colBlue = {0.20, 0.45, 1.00, 1.0}
  local colRed  = {1.00, 0.20, 0.20, 1.0}

  -- BLEU
  LOGI_RING_IDS.BLUE = {}
  for _,p in ipairs(LOGI_BLUE_POINTS or {}) do
    local id = _nextRingId()
    local c3 = { x=p.x, y=land.getHeight({x=p.x,y=p.z}), z=p.z }
    local ok = _circleToAll_compat(coalition.side.BLUE, id, c3, R, colBlue)
    if not ok then _polyCircleFallback(coalition.side.BLUE, id, c3, R, colBlue) end
    LOGI_RING_IDS.BLUE[#LOGI_RING_IDS.BLUE+1] = id
  end

  -- ROUGE
  LOGI_RING_IDS.RED = {}
  for _,p in ipairs(LOGI_RED_POINTS or {}) do
    local id = _nextRingId()
    local c3 = { x=p.x, y=land.getHeight({x=p.x,y=p.z}), z=p.z }
    local ok = _circleToAll_compat(coalition.side.RED, id, c3, R, colRed)
    if not ok then _polyCircleFallback(coalition.side.RED, id, c3, R, colRed) end
    LOGI_RING_IDS.RED[#LOGI_RING_IDS.RED+1] = id
  end
end


-- ==== CONTOURS DES ZONES (lignes visibles par tous) ====
-- ==== CONTOUR D'UNE ZONE PAR LIGNES (VISIBLE PAR TOUS) ====
-- ==== CONTOUR D'UNE ZONE PAR LIGNES (VISIBLE PAR TOUS) ====
function _drawZoneOutlineToAll(zoneName, colorRGBA)
  local z = readPolygonZone(zoneName)
  if not z or not z.poly or #z.poly < 2 then
    -- debug optionnel
    -- trigger.action.outText("[OUTLINE] zone "..zoneName.." invalide (#pts="..tostring(z and z.poly and #z.poly or 0)..")", 10)
    return
  end
  if type(trigger.action.lineToAll) ~= "function" then
    return
  end

  local poly = z.poly

  local function v2toV3(v)
    return {
      x = v.x,
      y = land.getHeight({ x = v.x, y = v.z }),
      z = v.z
    }
  end

  -- on part du premier point
  local first2 = poly[1]
  local prev   = v2toV3(first2)

  -- segments 2..N
  for i = 2, #poly do
    local cur2 = poly[i]
    local cur  = v2toV3(cur2)
    local id   = _nextRingId()

    -- coalition = -1 (tous), lineType = 1 (ton build : pointillé), readOnly = true
    pcall(trigger.action.lineToAll, -1, id, prev, cur, colorRGBA, 1, true)

    prev = cur
  end

  -- fermeture du polygone : dernier -> premier
  local first3 = v2toV3(first2)
  local idClose = _nextRingId()
  pcall(trigger.action.lineToAll, -1, idClose, prev, first3, colorRGBA, 1, true)
end



function DrawZoneTriggerFrames()
  local colLogiBlueLight = { 0.30, 0.60, 1.00, 1.0 }
  local colLogiRedLight  = { 1.00, 0.35, 0.35, 1.0 }
  local colBlueDark      = { 0.00, 0.20, 0.70, 1.0 }
  local colRedDark       = { 0.70, 0.00, 0.00, 1.0 }
  local colYellow        = { 1.00, 0.90, 0.00, 1.0 }

  _drawZoneOutlineToAll("LOGIBLUE",    colLogiBlueLight)
  _drawZoneOutlineToAll("LOGIRED",     colLogiRedLight)
  _drawZoneOutlineToAll("LOGIBLUE_M",  colLogiBlueLight)
  _drawZoneOutlineToAll("LOGIRED_M",   colLogiRedLight)
  _drawZoneOutlineToAll("BLUELINE",    colBlueDark)
  _drawZoneOutlineToAll("REDLINE",     colRedDark)
  _drawZoneOutlineToAll("BATTLEFIELD", colYellow)
  _drawZoneOutlineToAll("BATTLEFIELD_M", colYellow)
  _drawZoneOutlineToAll("BATTLEFIELD_M_TT", colYellow)
end


-- ==== PRIORITY RINGS (stable, no flicker) ====
-- Dépendances attendues:
--  - BATTLEFIELD_POINTS (vec2)
--  - _nextRingId(), _circleToAll_compat(), _polyCircleFallback(), _vec3_on_ground()
--  - (déjà définis dans ton script)

local PRIO_RADIUS   = 1000 -- m
local _colGREY = {0.00, 0.85, 0.00, 1.0}  -- vert
local _colRED  = {1.00, 0.20, 0.20, 1.0}
local _colBLU  = {0.20, 0.45, 1.00, 1.0}

-- Etat interne: par index de BATTLEFIELD_POINTS
-- { mode="circle"|"poly", colorKey="GREY"/"RED"/"BLUE", ids={...}, center={x,z} }
local PRIO_RING_STATE = {}

function _colorKeyEq(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
function _keyOfColor(c)
  if _colorKeyEq(c,_colGREY) then return "GREEN"  -- <<<<<<<<<< neutre doit s'appeler "GREEN"
  elseif _colorKeyEq(c,_colRED) then return "RED"
  elseif _colorKeyEq(c,_colBLU) then return "BLUE"
  else return "GREEN" end                          -- par défaut = neutre
end


-- Présence dans le disque R=1km
function _prioColorFromPresence(center2)
  local hasBlue, hasRed = false, false
  local vol = { id=world.VolumeType.SPHERE, params={ point={x=center2.x, y=land.getHeight({x=center2.x,y=center2.z}), z=center2.z}, radius=PRIO_RADIUS } }
    world.searchObjects(Object.Category.UNIT, vol, function(obj)
    if obj and obj.getCoalition and obj.getLife and Unit.isExist(obj) then
      local life = obj:getLife() or 0
      if life > 1 then  -- ignore épaves/units mortes
        local c = obj:getCoalition()
        if c == coalition.side.BLUE then hasBlue = true
        elseif c == coalition.side.RED then hasRed = true end
        if hasBlue and hasRed then return false end
      end
    end
    return true
  end)

  if hasBlue and hasRed then return _colGREY
  elseif hasBlue then       return _colBLU
  elseif hasRed then        return _colRED
  else                      return _colGREY
  end
end

-- Nettoyage ciblé d’un anneau (selon son mode)
function _clearPrioRing(i)
  local st = PRIO_RING_STATE[i]; if not st or not st.ids then return end
  if st.mode == "circle" then
    -- un seul id
    pcall(trigger.action.removeMark, st.ids[1])
  elseif st.mode == "poly" then
    -- plusieurs segments
    for _,id in ipairs(st.ids) do pcall(trigger.action.removeMark, id) end
  end
  PRIO_RING_STATE[i] = nil
end

-- === Helpers coords (MGRS + deg/min décimal) ===
function _fmtDM(lat, lon)
  local function one(a, isLat)
    local hemi = isLat and (a >= 0 and "N" or "S") or (a >= 0 and "E" or "W")
    a = math.abs(a)
    local d = math.floor(a)
    local m = (a - d) * 60
    return string.format("%s %02d°%06.3f'", hemi, d, m)
  end
  return one(lat, true) .. ", " .. one(lon, false)
end

function _coordStrings(center2)
  local p3 = { x=center2.x, y=land.getHeight({x=center2.x, y=center2.z}), z=center2.z }
  local lat, lon = coord.LOtoLL(p3)
  local mgrs = coord.LLtoMGRS(lat, lon)
  -- MGRS format: "Zone Digraph Easting Northing"
  local mgrsStr = string.format("%s %s %05d %05d",
    tostring(mgrs.UTMZone or ""),
    tostring(mgrs.MGRSDigraph or ""),
    math.floor((mgrs.Easting or 0) + 0.5),
    math.floor((mgrs.Northing or 0) + 0.5)
  )
  local dmStr = _fmtDM(lat, lon)
  return mgrsStr, dmStr
end

---------------------------------------------------------
-- FARP LOGISTIQUE : détection des cargos & dispatch   --
---------------------------------------------------------

function _sideKeySimple(sideId)
  return (sideId == coalition.side.BLUE) and "BLUE" or "RED"
end

function _zoneCenterRadius(zoneName)
  local z = readPolygonZone(zoneName)
  if not z or not z.poly or #z.poly == 0 then return nil end

  local poly = z.poly
  local sx, sz = 0, 0
  for _, v in ipairs(poly) do
    sx = sx + v.x
    sz = sz + v.z
  end
  local cx, cz = sx / #poly, sz / #poly

  local maxR = 0
  for _, v in ipairs(poly) do
    local dx, dz = v.x - cx, v.z - cz
    local r = math.sqrt(dx*dx + dz*dz)
    if r > maxR then maxR = r end
  end

  return { x = cx, z = cz }, maxR
end

function _pointInPoly(pt, poly)
  local inside = false
  local x, z = pt.x, pt.z
  local j = #poly
  for i = 1, #poly do
    local xi, zi = poly[i].x, poly[i].z
    local xj, zj = poly[j].x, poly[j].z
    if ((zi > z) ~= (zj > z)) then
      local xint = xi + (z - zi) * (xj - xi) / ((zj - zi) + 1e-6)
      if x < xint then inside = not inside end
    end
    j = i
  end
  return inside
end

local function _dist2(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return math.sqrt(dx*dx + dz*dz)
end

-----------------------------------------------------------------
-- MENUS BATTLEFIELD / SECTEURS (coordonnées PRIORITY pour joueurs)
-----------------------------------------------------------------

BATTLEFIELD_MENU_STATE = BATTLEFIELD_MENU_STATE or {}
local BF_SECTOR_PAGE_SIZE = 10  -- 10 secteurs par "plage"

-- Envoie les coordonnées d'un secteur donné au groupe (message privé)
function BF_SendSectorCoords(gid, sectorIdx)
  if not (BATTLEFIELD_POINTS and BATTLEFIELD_POINTS[sectorIdx]) then return end

  local pt  = BATTLEFIELD_POINTS[sectorIdx]
  local num = (PRIO_SECTOR_NUM and PRIO_SECTOR_NUM[sectorIdx]) or sectorIdx

  local mgrsStr, dmStr
  if _coordStrings then
    mgrsStr, dmStr = _coordStrings(pt)
  else
    mgrsStr = string.format("X: %.1f  Z: %.1f", pt.x, pt.z)
    dmStr   = ""
  end

  local msg
  if dmStr ~= "" and dmStr ~= nil then
    msg = string.format(
      "Coordonnées Secteur %d :\n%s\n%s",
      num, mgrsStr, dmStr
    )
  else
    msg = string.format(
      "Coordonnées Secteur %d :\n%s",
      num, mgrsStr
    )
  end

  trigger.action.outTextForGroup(gid, msg, 90)
end

-- Construit les sous-menus "Secteurs 1–10", "Secteurs 11–20", etc. pour un groupe
function BF_BuildSectorMenusForGroup(gid, gname, st)
  if not missionCommands or not missionCommands.addSubMenuForGroup then return end
  if not (BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0) then return end

  -- Liste triée des secteurs par numéro (PRIO_SECTOR_NUM ou index)
  local entries = {}
  for idx, _ in ipairs(BATTLEFIELD_POINTS) do
    local num = (PRIO_SECTOR_NUM and PRIO_SECTOR_NUM[idx]) or idx
    entries[#entries+1] = { idx = idx, num = num }
  end
  table.sort(entries, function(a, b) return a.num < b.num end)

  local total     = #entries
  local totalPage = math.ceil(total / BF_SECTOR_PAGE_SIZE)
  st.sectorSubmenus = st.sectorSubmenus or {}

  local i = 1
  for page = 1, totalPage do
    local startIdx = i
    local endIdx   = math.min(i + BF_SECTOR_PAGE_SIZE - 1, total)

    local firstNum = entries[startIdx].num
    local lastNum  = entries[endIdx].num

    local label
    if firstNum == lastNum then
      label = string.format("Secteur %d", firstNum)
    else
      label = string.format("Secteurs %d–%d", firstNum, lastNum)
    end

    local sub = missionCommands.addSubMenuForGroup(gid, label, st.sectorsMenu)
    st.sectorSubmenus[#st.sectorSubmenus+1] = sub

    for j = startIdx, endIdx do
      local e         = entries[j]
      local sectorIdx = e.idx
      local num       = e.num
      local lblSec    = string.format("Secteur %d", num)

      missionCommands.addCommandForGroup(
        gid,
        lblSec,
        sub,
        function()
          BF_SendSectorCoords(gid, sectorIdx)
        end
      )
    end

    i = endIdx + 1
  end
end

-- Crée / assure la présence du menu Battlefield / Secteurs pour un groupe
function BF_EnsureSectorMenuForGroup(gid, gname)
  if not missionCommands or not missionCommands.addSubMenuForGroup then
    return nil, nil
  end

  BATTLEFIELD_MENU_STATE[gname] = BATTLEFIELD_MENU_STATE[gname] or {}
  local st = BATTLEFIELD_MENU_STATE[gname]

  -- Root "Battlefield"
  if not st.root then
    st.root = missionCommands.addSubMenuForGroup(gid, "Battlefield")
  end

  -- Sous-menu racine "Secteurs"
  if not st.sectorsMenu then
    st.sectorsMenu = missionCommands.addSubMenuForGroup(gid, "Secteurs", st.root)
  end

  -- Construire les sous-menus seulement une fois
  if not st.built and BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0 then
    BF_BuildSectorMenusForGroup(gid, gname, st)
    st.built = true
  end

  return st.root, st.sectorsMenu
end

-- Scan périodique pour donner les menus "Battlefield / Secteurs" à tous les joueurs
local function BF_MenuScanPlayers()
  if not missionCommands or not missionCommands.addSubMenuForGroup then
    return timer.getTime() + 10
  end

  -- Pas de PRIORITY ? On réessaie plus tard
  if not (BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0) then
    return timer.getTime() + 10
  end

  local now = timer.getTime()

  local sides = {
    coalition.side.BLUE,
    coalition.side.RED,
  }

  for _, side in ipairs(sides) do
    local players = coalition.getPlayers and coalition.getPlayers(side) or nil
    if players then
      for _, u in ipairs(players) do
        if u and Unit.isExist(u) then
          local g = u:getGroup()
          if g and Group.isExist(g) then
            local gname = g:getName()
            local gid   = g:getID()
            if gname and gid then
              -- Si ce groupe n'a pas encore reçu le menu Battlefield/Secteurs, on le crée
              if not (BATTLEFIELD_MENU_STATE[gname] and BATTLEFIELD_MENU_STATE[gname].root) then
                BF_EnsureSectorMenuForGroup(gid, gname)
              end
            end
          end
        end
      end
    end
  end

  -- Tick toutes les 20 s, ça suffit largement
  return now + 20
end



-----------------------------------------------------------------
-- DEPOT – Embarquement troupes depuis BLUESTORE / REDSTORE
-----------------------------------------------------------------

STORE_EMBARK_STATE = STORE_EMBARK_STATE or {}


local function _vec3From2(pt)
  return {
    x = pt.x,
    y = land.getHeight({ x = pt.x, y = pt.z }),
    z = pt.z
  }
end

local function _sendLOGFARPToSite(sideId, sitePt)
  local sideKey = _sideKeySimple(sideId)
  local list    = LOG_FARP_GROUPS[sideKey]
  local state   = LOG_FARP_STATE[sideKey]

  if not list or #list == 0 then return end

  -- logi le plus proche du site
  local bestIdx, bestD
  for idx, info in ipairs(list) do
    local d = _dist2(info.logiPt, sitePt)
    if (not bestD) or d < bestD then
      bestD, bestIdx = d, idx
    end
  end
  if not bestIdx then return end

   state[bestIdx] = state[bestIdx] or { status = "idle" }
  if state[bestIdx].status ~= "idle" then
    -- déjà en mission
    return
  end

  local gname = list[bestIdx].gname
  local g     = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end

  local us = g:getUnits()
  if not us or not us[1] or not Unit.isExist(us[1]) then return end
  local p0 = us[1]:getPoint()

  local route = {
    points = {
      {
        x = p0.x, y = p0.z,
        type = "Turning Point",
        action = "Off Road",
        speed = 80 / 3.6,
        speed_locked = true,
        task  = { id="ComboTask", params={tasks={}} }
      },
      {
        x = sitePt.x, y = sitePt.z,
        type = "Turning Point",
        action = "Off Road",
        speed = 80 / 3.6,
        speed_locked = true,
        task  = { id="ComboTask", params={tasks={}} }
      }
    }
  }

  local ctrl = g:getController()
  if ctrl then
    Controller.setTask(ctrl, { id = 'Mission', params = { route = route } })
  end

  state[bestIdx].status        = "moving"
  state[bestIdx].target        = { x = sitePt.x, z = sitePt.z }
  state[bestIdx].buildStart    = nil
  state[bestIdx].buildPos      = nil
  state[bestIdx].farpSpawned   = false


  -- message radio Vieille Pantoufle
  if _coordStrings then
    local mgrsStr, dmStr = _coordStrings(sitePt)
    local msg = "Ici Vieille Pantoufle, logistique en déplacement pour construction de FARP.\nCoordonnées :\n"
      .. mgrsStr .. "\n" .. dmStr
    trigger.action.outTextForCoalition(sideId, msg, 45)
  else
    trigger.action.outTextForCoalition(sideId,
      "Ici Vieille Pantoufle, logistique en déplacement pour construction de FARP.", 30)
  end
end

local function LOGI_FARP_ScanAndDispatch()
  -- scan d'un côté et d'une zone LOGI donnée
  local function scanSide(sideId, zoneName)
    local z = readPolygonZone(zoneName)
    if not z or not z.poly or #z.poly == 0 then
      return
    end

    -- centre + “rayon” approx de la zone LOGI
    local center, radius = _zoneCenterRadius(zoneName)
    if not center then return end

    -- marge de sécurité pour le volume de recherche
    radius = (radius or 0) + 1500

    local vol = {
      id     = world.VolumeType.SPHERE,
      params = { point = _vec3From2(center), radius = radius }
    }

    local poly = z.poly
    local fuels, ammos = {}, {}

    -- collecte des cargos potentiels
    local function handleObj(obj)
      if not obj or not obj.getTypeName or not obj.getPoint then
        return
      end

      local tname = obj:getTypeName()
      if not tname then return end
      local lname = string.lower(tname)

      -- on matche large : "fueltank" et "ammo" dans le nom
      local isfuel  = string.find(lname, "fueltank", 1, true) ~= nil
      local isAmmo = string.find(lname, "ammo",    1, true) ~= nil
      if not (isfuel or isAmmo) then
        return
      end

      -- coalition identique à celle de la zone LOGI
      if obj.getCoalition and obj:getCoalition() ~= sideId then
        return
      end

      local p3  = obj:getPoint()
      local pt  = { x = p3.x, z = p3.z }
      local gnd = land.getHeight({ x = pt.x, y = pt.z })

      -- posé au sol (tolérance un peu large)
      if math.abs(p3.y - gnd) > 20 then
        return
      end

      -- réellement dans le polygone LOGI
      if not _pointInPoly(pt, poly) then
        return
      end

      if isfuel then
        fuels[#fuels+1] = pt
      elseif isAmmo then
        ammos[#ammos+1] = pt
      end
    end

    -- STATIC
    world.searchObjects(Object.Category.STATIC, vol, function(obj)
      handleObj(obj)
      return true
    end)

    -- CARGO (si dispo dans le build)
    if Object.Category.CARGO then
      world.searchObjects(Object.Category.CARGO, vol, function(obj)
        handleObj(obj)
        return true
      end)
    end

    if #fuels == 0 or #ammos == 0 then
      return
    end

    -- cherche un couple fuel / AMMO à < 200 m
    local bestSite, bestD
    for _, o in ipairs(fuels) do
      for _, a in ipairs(ammos) do
        local d = _dist2(o, a)
        if d <= 200 then
          if not bestD or d < bestD then
            bestD    = d
            bestSite = { x = (o.x + a.x) * 0.5, z = (o.z + a.z) * 0.5 }
          end
        end
      end
    end

    if not bestSite then
      return
    end

    -- on envoie le LOG_FARP du logi le plus proche
    _sendLOGFARPToSite(sideId, bestSite)
  end

  -- BLUE -> LOGIBLUE, RED -> LOGIRED
  scanSide(coalition.side.BLUE, "LOGIBLUE")
  scanSide(coalition.side.RED,  "LOGIRED")

  -- re-scan toutes les 15 s
  return timer.getTime() + 15
end

local function _configureFarpWarehouse(farpName)
  if not farpName or type(farpName) ~= "string" then return end
  if not Airbase or not Airbase.getByName then return end

  local attempts = 0
  local maxAttempts = 15  -- Plus de tentatives

  local function _doConfigure(_, t)
    attempts = attempts + 1

    local ab = Airbase.getByName(farpName)
    if not ab then
      if attempts < maxAttempts then
        return t + 2  -- Attendre 2 secondes entre chaque tentative
      end
      return
    end

    local wh = ab.getWarehouse and ab:getWarehouse()
    if not wh then 
      -- Retry si warehouse pas encore disponible
      if attempts < maxAttempts then
        return t + 2
      end
      return 
    end

    ----------------------------------------------------------------
    -- Carburant : quantités massives
    ----------------------------------------------------------------
    if wh.setLiquidAmount then
      wh:setLiquidAmount(0, 10000000)  -- 10 millions
      wh:setLiquidAmount(1, 10000000)
      wh:setLiquidAmount(2, 10000000)
      wh:setLiquidAmount(3, 10000000)
    elseif wh.addLiquid then
      wh:addLiquid(0, 10000000)
      wh:addLiquid(1, 10000000)
      wh:addLiquid(2, 10000000)
      wh:addLiquid(3, 10000000)
    end

    ----------------------------------------------------------------
    -- Munitions
    ----------------------------------------------------------------
    if Warehouse and Warehouse.getResourceMap and wh.setItem then
      local resMap = Warehouse.getResourceMap()
      if resMap then
        for key, _ in pairs(resMap) do
          if type(key) == "string" and string.sub(key, 1, 8) == "weapons." then
            wh:setItem(key, 99999)  -- Augmenté
          end
        end
      end
    end

    ----------------------------------------------------------------
    -- RÉPARATION : Toutes les ressources possibles
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Message de confirmation
    ----------------------------------------------------------------
    trigger.action.outText(
      string.format("[FARP] %s prête", farpName),
      20
    )

    return
  end

  -- Première tentative après 2 secondes
  timer.scheduleFunction(_doConfigure, {}, timer.getTime() + 2)
end



-- Suivi des convois LOG_FARP et construction des FARPs
-- Helpers locaux pour LOGI_FARP (évite les problèmes de portée avec l'autoconquest)
-- Helpers locaux FARP (indépendants de l'autoconquest)
function _farpLeaderSpeedMS(gname)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return 0 end
  local us = g:getUnits()
  if not us or not us[1] or not Unit.isExist(us[1]) then return 0 end
  local v = us[1]:getVelocity() or {x=0,y=0,z=0}
  return math.sqrt((v.x or 0)^2 + (v.y or 0)^2 + (v.z or 0)^2)
end

function _farpRandomId()
  if RNG and RNG.randomInt then
    return RNG.randomInt(100000, 999999)
  end
  return math.random(100000, 999999)
end

function _farpAdjustToGround(x, z)
  if type(adjustAnchorToFlatSpot) == "function" then
    -- on encapsule dans un pcall au cas où la signature ne correspond pas
    local ok, ax, az = pcall(adjustAnchorToFlatSpot, x, z)
    if ok and ax and az then
      return ax, az
    end
  end
  -- fallback : on renvoie tel quel
  return x, z
end


function _farpNormalize(dx, dz)
  local L = math.sqrt(dx*dx + dz*dz)
  if L < 1e-6 then
    return 1, 0
  end
  return dx / L, dz / L
end

-- Suivi des convois LOG_FARP et construction des FARPs
-- Suivi des convois LOG_FARP et construction des FARPs
local function LOGI_FARP_UpdateAndBuild()
  local now        = timer.getTime()
  local buildDelay = (AUTO_CONQUEST_CFG and AUTO_CONQUEST_CFG.farp_build_seconds) or 600

  for sideKey, sideState in pairs(LOG_FARP_STATE or {}) do
    local sideId    = (sideKey == "BLUE") and coalition.side.BLUE or coalition.side.RED
    local countryId = (sideId == coalition.side.BLUE) and country.id.USA or country.id.RUSSIA

    local groups = LOG_FARP_GROUPS[sideKey] or {}

    for idx, st in pairs(sideState) do
      local info = groups[idx]

      -- sécurité basique
      if not info or not info.gname then
        st.status = "dead"

      elseif st.status == "moving" and st.target then
        local g = Group.getByName(info.gname)
        if not g or not Group.isExist(g) then
          st.status = "dead"
        else
          local us = g:getUnits()
          if us and us[1] and Unit.isExist(us[1]) then
            local p3   = us[1]:getPoint()
            local pos2 = { x = p3.x, z = p3.z }
            local d    = _dist2(pos2, st.target)
            local spd  = _farpLeaderSpeedMS(info.gname) or 0

            -- Arrivé sur site (proche et quasi immobile)
            if d < 50 and spd <= 1.0 then
              st.status     = "building"
              st.buildStart = now
              st.buildPos   = { x = p3.x, z = p3.z }
            end
          end
        end

      elseif st.status == "building" and not st.farpSpawned then
        if st.buildStart and (now - st.buildStart >= buildDelay) then
          local baseX, baseZ, hdg, farpX, farpZ, tentX, tentZ

          -- On relit la position/orientation du convoi si possible
          local g = Group.getByName(info.gname)
          if g and Group.isExist(g) then
            local us = g:getUnits()
            if us and us[1] and Unit.isExist(us[1]) then
              local u   = us[1]
              local p3  = u:getPoint()
              baseX     = p3.x
              baseZ     = p3.z

              local m   = u:getPosition()
              local fx, fz = 1, 0
              if m and m.x then
                -- vecteur "avant" approximatif (utilise l'axe X de la matrice)
                fx, fz = m.x.x or 1, m.x.z or 0
                local L = math.sqrt(fx*fx + fz*fz)
                if L > 1e-6 then
                  fx, fz = fx / L, fz / L
                else
                  fx, fz = 1, 0
                end
              end

              hdg = math.atan2(fx, fz)

              -- vecteur "à droite"
              local rx, rz = fz, -fx

              farpX = baseX + rx * 30
              farpZ = baseZ + rz * 30
              tentX = baseX + rx * 45
              tentZ = baseZ + rz * 45
            end
          end

          -- fallback : si on n'a pas réussi à lire la position du convoi
          if not baseX and st.buildPos then
            baseX = st.buildPos.x
            baseZ = st.buildPos.z
            hdg   = 0
            farpX = baseX + 30
            farpZ = baseZ
            tentX = baseX + 45
            tentZ = baseZ
          end

                    if baseX and farpX and tentX then
            -- FARP principale (Heliport)
                       local farpData = {
              country    = countryId,
              category   = "Heliports",
              type       = "FARP_SINGLE_01",
              shape_name = "FARP_SINGLE_01",
              x          = farpX,
              y          = farpZ,
              heading    = hdg or 0,
              name       = string.format("FARP_BUILT_%s_%02d_%06d", sideKey, idx, _farpRandomId()),
            }
            coalition.addStaticObject(countryId, farpData)

-- AJOUTER CES LIGNES ICI :
if _configureFarpWarehouse then
  _configureFarpWarehouse(farpData.name)
end

            -- On remplit le warehouse de ce FARP
            if _configureFarpWarehouse then
              _configureFarpWarehouse(farpData.name)
            end


            -- Tente FARP (fortification classique)
            local tentData = {
              country    = countryId,
              category   = "Fortification",    -- ce que l’éditeur utilise
              type       = "FARP Tent",
              shape_name = "FARP Tent",
              x          = tentX,
              y          = tentZ,
              heading    = hdg or 0,
              name       = farpData.name .. "_TENT",
            }
            coalition.addStaticObject(countryId, tentData)
          end

          st.farpSpawned = true
          st.status      = "deployed"

        end
      end
    end
  end

  return now + 2 -- check toutes les 2 s
end





local PRIO_RADIUS   = 1000 -- m
local _colGREY = {0.00, 0.85, 0.00, 1.0}  -- vert
local _colRED  = {1.00, 0.20, 0.20, 1.0}
local _colBLU  = {0.20, 0.45, 1.00, 1.0}

-- Etat interne: par index de BATTLEFIELD_POINTS
-- { mode="circle"|"poly", colorKey="GREY"/"RED"/"BLUE", ids={...}, center={x,z} }
local PRIO_RING_STATE = {}




-------------------------------------------------
-- NUMÉROTATION DES SECTEURS PAR DISTANCE LOGI --
-------------------------------------------------
PRIO_SECTOR_NUM = PRIO_SECTOR_NUM or {}

function PRIO_RecomputeSectorNumbers()
  PRIO_SECTOR_NUM = {}

  if not (BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0) then
    return
  end

  -- En mode MANUEL (BATTLEFIELD_M / BATTLEFIELD_M_TT), on garde
  -- l'ordre des zones trigger : zone "1" → secteur 1, zone "2" → secteur 2, etc.
  if BATTLEFIELD_MANUAL then
    for idx = 1, #BATTLEFIELD_POINTS do
      PRIO_SECTOR_NUM[idx] = idx
    end
    return
  end

  -- Mode AUTO : classe par distance croissante au LOGI central
  local allLogi = {}

  if LOGI_BLUE_POINTS then
    for _, p in ipairs(LOGI_BLUE_POINTS) do
      allLogi[#allLogi+1] = { x = p.x, z = p.z }
    end
  end

  if LOGI_RED_POINTS then
    for _, p in ipairs(LOGI_RED_POINTS) do
      allLogi[#allLogi+1] = { x = p.x, z = p.z }
    end
  end

  -- Choix du “logi central” :
  -- 1) on calcule le centre géométrique de tous les LOGI
  -- 2) on prend le LOGI le plus proche de ce centre
  local ref

  if #allLogi > 0 then
    local sx, sz = 0, 0
    for _, p in ipairs(allLogi) do
      sx = sx + p.x
      sz = sz + p.z
    end
    local cx, cz = sx / #allLogi, sz / #allLogi

    local best, bestD2 = nil, 1e18
    for _, p in ipairs(allLogi) do
      local dx, dz = p.x - cx, p.z - cz
      local d2 = dx*dx + dz*dz
      if d2 < bestD2 then
        bestD2 = d2
        best   = p
      end
    end
    ref = best
  end

  -- Si vraiment aucun LOGI, on se rabat sur le centre des PRIORITY
  if not ref then
    local sx, sz = 0, 0
    for _, p in ipairs(BATTLEFIELD_POINTS) do
      sx = sx + p.x
      sz = sz + p.z
    end
    ref = { x = sx / #BATTLEFIELD_POINTS, z = sz / #BATTLEFIELD_POINTS }
  end

  -- Classe les PRIORITY par distance croissante au logi central
  local tmp = {}
  for idx, pt in ipairs(BATTLEFIELD_POINTS) do
    local dx, dz = pt.x - ref.x, pt.z - ref.z
    local d2 = dx*dx + dz*dz
    tmp[#tmp+1] = { idx = idx, d2 = d2 }
  end

  table.sort(tmp, function(a, b) return a.d2 < b.d2 end)

  -- Assigne un “numéro de secteur” 1,2,3,... suivant l’ordre trié
  for num, entry in ipairs(tmp) do
    PRIO_SECTOR_NUM[entry.idx] = num
  end
end

-- ===== NUMÉROS "DRAW" SUR LES PRIORITY =====
-- ===== NUMÉROS "DRAW" SUR LES PRIORITY =====
-- ===== NUMÉROS "DRAW" SUR LES PRIORITY =====
local PRIO_TEXT_IDS = PRIO_TEXT_IDS or {}

function DrawPriorityNumbers()
  PRIO_TEXT_IDS = {}

  if not (BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0) then
    return
  end

  if type(trigger.action.textToAll) ~= "function" then
    return
  end

  local textColor = { 1.0, 1.0, 1.0, 1.0 }   -- blanc
  local fillColor = { 0.0, 0.0, 0.0, 0.25 } -- fond léger
  local fontSize  = 18

  for i, pt in ipairs(BATTLEFIELD_POINTS) do
    -- On prend le numéro de secteur calculé, ou i par défaut
    local num = PRIO_SECTOR_NUM[i] or i
    
    -- Texte affiche : numero + valeur economique si disponible
    local displayText = tostring(num)
    local econText = ECON_GetSectorValueText(i)
    if econText and econText ~= "" then
      displayText = displayText .. "\n" .. econText
    end

    -- id unique, tu peux continuer à utiliser ton générateur global
    local id = _nextRingId()

    local pos = {
      x = pt.x,
      y = land.getHeight({ x = pt.x, y = pt.z }),
      z = pt.z
    }

    -- coalition = -1 -> visible par tous
    local ok = pcall(
      trigger.action.textToAll,
      -1,           -- coalition (tous)
      id,           -- id unique
      pos,          -- vec3
      textColor,    -- couleur du texte
      fillColor,    -- fond
      fontSize,     -- taille police
      true,         -- readOnly
      displayText   -- texte affiche (numero + valeur eco)
    )

    if ok then
      PRIO_TEXT_IDS[i] = id
    end
  end
end



-- Dessine (ou remplace si couleur change) l’anneau i en colorRGBA
-- Dessine (ou remplace si couleur change) l’anneau i en colorRGBA + NOTIFS
-- Dessine (ou remplace si couleur change) l’anneau i en colorRGBA + NOTIFS + HOOK conquête
-- Dessine (ou remplace si couleur change) l’anneau i en colorRGBA + NOTIFS + HOOK conquête
function _ensurePrioRing(i, center2, colorRGBA)
  local key = _keyOfColor(colorRGBA)
  local st  = PRIO_RING_STATE[i]

  -- si déjà à la bonne couleur → ne rien faire (évite flicker)
  if st and st.colorKey == key then return end

  -- ==== NOTIFICATION (changement d'état) ====
  local mgrsStr, dmStr = _coordStrings(center2)
  local sectorNum = PRIO_SECTOR_NUM[i] or i
  local sectorStr = tostring(sectorNum)


  if key == "BLUE" then
    -- Camp bleu : message avec numéro de secteur
    trigger.action.outTextForCoalition(
      coalition.side.BLUE,
      "Ici Vieille Pantoufle, nous avons pris le contrôle du secteur "..sectorStr..".",
      30
    )
    -- Camp rouge : conserve le message avec coordonnées
    trigger.action.outTextForCoalition(
      coalition.side.RED,
      "Ici Vieille Pantoufle, l'ennemi a pris le contrôle du secteur "..sectorStr.."." ,
      30
    )

  elseif key == "RED" then
    -- Camp rouge : message avec numéro de secteur
    trigger.action.outTextForCoalition(
      coalition.side.RED,
      "Ici Vieille Pantoufle, nous avons pris le contrôle du secteur "..sectorStr..".",
      30
    )
    -- Camp bleu : conserve le message avec coordonnées
    trigger.action.outTextForCoalition(
      coalition.side.BLUE,
      "Ici Vieille Pantoufle, l'ennemi a pris le contrôle du secteur "..sectorStr..".",
      30
    )

  else -- GREEN (contesté / par défaut)
    trigger.action.outTextForCoalition(
      coalition.side.BLUE,
      "Ici Vieille Pantoufle, secteur " ..sectorStr.. " contesté, renforts nécessaires.",
      30
    )
    trigger.action.outTextForCoalition(
      coalition.side.RED,
      "Ici Vieille Pantoufle, secteur " ..sectorStr.. " contesté, renforts nécessaires.",
      30
    )
  end
  -- ==========================================

  -- purge ancien rendu si présent
  if st then _clearPrioRing(i) end

  -- (re)dessin
  local c3 = { x=center2.x, y=land.getHeight({x=center2.x,y=center2.z}), z=center2.z }
  local id = _nextRingId()
  local ok = _circleToAll_compat(-1, id, c3, PRIO_RADIUS, colorRGBA)

  if ok then
    PRIO_RING_STATE[i] = { mode="circle", colorKey=key, ids={id}, center=center2 }
  else
    local segIds = {}
    local N, a0 = 36, 0
    local prev = nil
    for k=1,N do
      local a = a0 + (k-1)*2*math.pi/N
      local px = c3.x + PRIO_RADIUS*math.cos(a)
      local pz = c3.z + PRIO_RADIUS*math.sin(a)
      local p  = { x=px, y=land.getHeight({x=px, y=pz}), z=pz }
      if prev then
        local sid = _nextRingId()
        segIds[#segIds+1] = sid
        pcall(trigger.action.lineToAll, -1, sid, prev, p, colorRGBA, 1, true)
      end
      prev = p
    end
    local pFirst = {
      x = c3.x + PRIO_RADIUS,
      y = land.getHeight({x=c3.x+PRIO_RADIUS,y=c3.z}),
      z = c3.z
    }
    local sid = _nextRingId()
    segIds[#segIds+1] = sid
    pcall(trigger.action.lineToAll, -1, sid, prev, pFirst, colorRGBA, 1, true)

    PRIO_RING_STATE[i] = { mode="poly", colorKey=key, ids=segIds, center=center2 }
  end

  -- HOOK vers l'autoconquest
  if _G.AUTO_CONQUEST and AUTO_CONQUEST.OnZoneColorChange then
    AUTO_CONQUEST.OnZoneColorChange(i, key)
  end
end




-- Init + polling
function PRIO_Rings_InitAndPoll()
  -- initial: gris
  for i,pt in ipairs(BATTLEFIELD_POINTS or {}) do
    _ensurePrioRing(i, pt, _colGREY)
  end
  -- update 5s : ne redessine que si la couleur change
  local function _tick()
    for i,pt in ipairs(BATTLEFIELD_POINTS or {}) do
      local col = _prioColorFromPresence(pt)
      _ensurePrioRing(i, pt, col)
    end
    return timer.getTime() + 5
  end
  timer.scheduleFunction(_tick, {}, timer.getTime() + 5)
end

-- Fonction GLOBALE pour obtenir le proprietaire d'un secteur
-- Retourne "BLUE", "RED", ou nil (neutre/conteste)
-- Utilisee par le systeme economique
function PRIO_GetSectorOwner(sectorIndex)
  local st = PRIO_RING_STATE and PRIO_RING_STATE[sectorIndex]
  if not st then return nil end
  local key = st.colorKey
  if key == "BLUE" then return "BLUE" end
  if key == "RED" then return "RED" end
  return nil  -- GREEN = neutre/conteste
end


-- ===== ZONE pipeline =====
function run_zone(cfg)
  local z,err=readPolygonZone(cfg.name)
  if not z then trigger.action.outText(string.format("[MARK] %s - %s",cfg.name,tostring(err)),8) return end
  local poly=z.poly

  if cfg.name=="LOGIBLUE" or cfg.name=="LOGIRED" then
    local s=0 local n=#poly for i=1,n do local a=poly[i]; local b=poly[(i%n)+1]; s=s+(a.x*b.z - b.x*a.z) end
    local area_km2 = math.abs(s)*0.5/1e6
    local want     = math.max(1, math.floor(area_km2 / LOGI_DENSITY_PER_KM2 + 1e-9))

    local cands, buildings = buildLogiCandidates(poly)
    local frontName = (cfg.name=="LOGIBLUE") and "BLUELINE" or "REDLINE"
    local frontZone = readPolygonZone(frontName)
    local frontPoly = frontZone and frontZone.poly or nil

    cands = filterByFrontDistance(cands, frontPoly, LOGI_FRONT_MAX_DIST_M)

    local chosen
    if frontPoly and #frontPoly>=3 then chosen = selectLogiDistributed(cands, want, frontPoly)
    else chosen = {}; for i=1,math.min(want,#cands) do chosen[#chosen+1]=cands[i] end end

    for i=1,#chosen do
      chosen[i] = jitterValidated(chosen[i], poly, frontPoly or poly, LOGI_FRONT_MAX_DIST_M, buildings)
    end

    trigger.action.outText(string.format("[LOGI] %s: area=%.2f km2, want=%d, base=%d, <=6km=%d, placed=%d.",
      cfg.name, area_km2, want, #cands, #cands, #chosen), 10)

    if cfg.name=="LOGIBLUE" then
      LOGI_BLUE_POINTS={} for _,p in ipairs(chosen) do LOGI_BLUE_POINTS[#LOGI_BLUE_POINTS+1]={x=p.x,z=p.z} end
      placeMarkers(LOGI_BLUE_POINTS,"LOGIBLUE",cfg.coalition,cfg.show_to_all)
    else
      LOGI_RED_POINTS ={} for _,p in ipairs(chosen) do LOGI_RED_POINTS [#LOGI_RED_POINTS +1]={x=p.x,z=p.z} end
      placeMarkers(LOGI_RED_POINTS,"LOGIRED", cfg.coalition,cfg.show_to_all)
    end
    return
  end

  -- Other zones: DEFENDBLUE/RED/BATTLEFIELD
  local nodes = (function()
    local buildings=collectBuildingsInPoly(poly)
    local arr=makeGridInside(poly, GRID_STEP_M)
    local out={} for _,n in ipairs(arr) do if countBuildingsWithin(buildings,n,AGGLO_RADIUS_M)>=AGGLO_MIN_COUNT then out[#out+1]=n end end
    return out
  end)()
  if cfg.min_spacing_m then
    local kept={} for _,p in ipairs(nodes) do local ok=true for __,k in ipairs(kept) do if dist2D(p,k) < cfg.min_spacing_m then ok=false break end end if ok then kept[#kept+1]=p end end
    nodes=kept
  end
  if cfg.max_markers and #nodes>cfg.max_markers then RNG.shuffle(nodes) local chosen={} for i=1,cfg.max_markers do chosen[#chosen+1]=nodes[i] end nodes=chosen end

  if cfg.name=="BATTLEFIELD" then BATTLEFIELD_POINTS={} end
  local placed=placeMarkers(nodes,cfg.prefix,cfg.coalition,cfg.show_to_all)
  if cfg.name=="BLUELINE" then DEFEND_BLUE_POINTS={} for _,p in ipairs(nodes) do DEFEND_BLUE_POINTS[#DEFEND_BLUE_POINTS+1]={x=p.x,z=p.z} end
  elseif cfg.name=="REDLINE" then DEFEND_RED_POINTS={} for _,p in ipairs(nodes) do DEFEND_RED_POINTS[#DEFEND_RED_POINTS+1]={x=p.x,z=p.z} end end
  trigger.action.outText(string.format("[MARK] %s - %d marker(s).", cfg.name, placed), 8)
end


-- ===== LOGI template & defenders / AD =====
local TYPE_CATEGORY = {
  [".Command Center"]       = "Fortifications",
  ["HESCO_wallperimeter_1"] = "Fortifications",
  ["HESCO_watchtower_1"]    = "Fortifications",
  ["Tent01"]                = "Fortifications",
  ["Tent02"]                = "Fortifications",
  ["Tent03"]                = "Fortifications",
  ["Tent05"]                = "Fortifications",

  -- Dépôt / FARP store
  ["Building01_PBR"]        = "Fortifications",
  ["Building08_PBR"]        = "Fortifications",
  ["FARP Ammo Dump Coating"]= "Fortifications",
  ["FARP CP Blindage"]      = "Fortifications",
  ["FARP Fuel Depot"]       = "Fortifications",
  ["FARP Tent"]             = "Fortifications",
  ["FARP_SINGLE_01"]        = "Heliports",
  ["M 818"]                 = "Unarmed",
  ["ammo_cargo"]            = "Cargos",
  ["fueltank_cargo"]        = "Cargos",
}


-- ===== DEPOT / STORE template statique (camp dépôt) =====
-- Le centre du template (dx=0, dz=0) sera posé sur le centre de BLUESTORE / REDSTORE.

STORE_STATIC_TEMPLATE = {
  { type = "Building01_PBR", name = "STORE_STATIC_1", rel = { dx = -19.12, dz = 41.57 }, heading = 1.570796 },
  { type = "Building08_PBR", name = "STORE_STATIC_2", rel = { dx = 42.38, dz = 4.83 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_3", rel = { dx = 51.69, dz = 20.18 }, heading = 1.570796 },
  { type = "Tent03", name = "STORE_STATIC_4", rel = { dx = 51.71, dz = 34.79 }, heading = 1.570796 },
  { type = "Tent03", name = "STORE_STATIC_5", rel = { dx = 51.59, dz = 49.33 }, heading = 1.570796 },
  { type = "Tent03", name = "STORE_STATIC_6", rel = { dx = 51.59, dz = 64.03 }, heading = 1.570796 },
  { type = "Tent03", name = "STORE_STATIC_7", rel = { dx = 41.03, dz = 23.28 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_8", rel = { dx = 41.25, dz = 37.42 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_9", rel = { dx = 41.31, dz = 46.25 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_10", rel = { dx = 41.36, dz = 54.19 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_11", rel = { dx = 41.08, dz = 30.32 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_12", rel = { dx = 41.14, dz = 16.51 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_13", rel = { dx = 41.25, dz = 61.74 }, heading = 0.000000 },
  { type = "Tent03", name = "STORE_STATIC_14", rel = { dx = 41.25, dz = 69.01 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_15", rel = { dx = 16.31, dz = 13.95 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_16", rel = { dx = 16.32, dz = 16.24 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_17", rel = { dx = 16.30, dz = 18.65 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_18", rel = { dx = 12.98, dz = 18.85 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_19", rel = { dx = 12.96, dz = 16.13 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_20", rel = { dx = 12.93, dz = 13.70 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_21", rel = { dx = 12.86, dz = 21.80 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_22", rel = { dx = 16.27, dz = 21.71 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_23", rel = { dx = 16.15, dz = 27.45 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_24", rel = { dx = 12.76, dz = 24.90 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_25", rel = { dx = 16.13, dz = 29.86 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_26", rel = { dx = 12.69, dz = 33.00 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_27", rel = { dx = 12.81, dz = 30.05 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_28", rel = { dx = 16.14, dz = 25.15 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_29", rel = { dx = 12.78, dz = 27.34 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_30", rel = { dx = 16.09, dz = 32.91 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_31", rel = { dx = 16.20, dz = 38.81 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_32", rel = { dx = 12.86, dz = 41.41 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_33", rel = { dx = 12.80, dz = 36.26 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_34", rel = { dx = 16.19, dz = 36.51 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_35", rel = { dx = 16.17, dz = 41.22 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_36", rel = { dx = 16.14, dz = 44.28 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_37", rel = { dx = 12.73, dz = 44.37 }, heading = 0.000000 },
  { type = "ammo_cargo", name = "STORE_STATIC_38", rel = { dx = 12.83, dz = 38.70 }, heading = 0.000000 },
  { type = "fueltank_cargo", name = "STORE_STATIC_39", rel = { dx = 16.11, dz = 55.91 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_40", rel = { dx = 12.58, dz = 55.99 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_41", rel = { dx = 12.58, dz = 61.43 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_42", rel = { dx = 16.03, dz = 61.35 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_43", rel = { dx = 4.68, dz = 56.07 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_44", rel = { dx = 8.21, dz = 56.00 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_45", rel = { dx = 4.68, dz = 61.52 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_46", rel = { dx = 8.13, dz = 61.44 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_47", rel = { dx = 4.44, dz = 68.30 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_48", rel = { dx = 4.44, dz = 73.74 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_49", rel = { dx = 7.96, dz = 68.22 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_50", rel = { dx = 7.89, dz = 73.67 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_51", rel = { dx = 16.12, dz = 68.90 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_52", rel = { dx = 12.59, dz = 74.42 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_53", rel = { dx = 12.59, dz = 68.98 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_54", rel = { dx = 16.04, dz = 74.35 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_55", rel = { dx = 20.74, dz = 74.30 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_56", rel = { dx = 24.27, dz = 68.78 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_57", rel = { dx = 24.19, dz = 74.22 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_58", rel = { dx = 20.74, dz = 68.85 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_59", rel = { dx = 20.92, dz = 61.76 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_60", rel = { dx = 24.45, dz = 56.24 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_61", rel = { dx = 24.37, dz = 61.69 }, heading = 1.570796 },
  { type = "fueltank_cargo", name = "STORE_STATIC_62", rel = { dx = 20.92, dz = 56.32 }, heading = 1.570796 },
  { type = "FARP_SINGLE_01", name = "STORE_STATIC_63", rel = { dx = 0.00, dz = 0.00 }, heading = 0.000000 },
  { type = "FARP Fuel Depot", name = "STORE_STATIC_64", rel = { dx = -10.28, dz = 15.33 }, heading = 0.000000 },
  { type = "FARP Tent", name = "STORE_STATIC_65", rel = { dx = -16.19, dz = 0.33 }, heading = 1.570796 },
  { type = "FARP Ammo Dump Coating", name = "STORE_STATIC_66", rel = { dx = -20.39, dz = 15.80 }, heading = 0.000000 },
  { type = "FARP CP Blindage", name = "STORE_STATIC_67", rel = { dx = -16.93, dz = 67.38 }, heading = 4.712389 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_68", rel = { dx = -28.97, dz = -21.04 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_69", rel = { dx = -17.51, dz = -21.04 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_70", rel = { dx = -7.11, dz = -21.04 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_71", rel = { dx = 4.78, dz = -21.10 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_72", rel = { dx = 16.74, dz = -21.10 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_73", rel = { dx = 28.61, dz = -21.10 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_74", rel = { dx = 40.38, dz = -21.10 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_75", rel = { dx = 51.95, dz = -21.10 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_76", rel = { dx = 58.91, dz = 42.35 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_77", rel = { dx = 58.85, dz = -15.23 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_78", rel = { dx = 58.85, dz = 6.62 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_79", rel = { dx = 58.91, dz = 30.48 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_80", rel = { dx = 58.91, dz = 54.12 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_81", rel = { dx = 58.85, dz = -3.78 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_82", rel = { dx = 58.91, dz = 18.52 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_83", rel = { dx = 58.91, dz = 65.69 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_84", rel = { dx = 39.19, dz = 94.70 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_85", rel = { dx = 3.59, dz = 94.70 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_86", rel = { dx = -30.16, dz = 94.76 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_87", rel = { dx = -18.71, dz = 94.76 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_88", rel = { dx = 27.42, dz = 94.70 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_89", rel = { dx = -8.30, dz = 94.76 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_90", rel = { dx = 50.76, dz = 94.70 }, heading = 0.000000 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_91", rel = { dx = -35.73, dz = 30.16 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_92", rel = { dx = -35.73, dz = 42.03 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_93", rel = { dx = -35.73, dz = 53.80 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_94", rel = { dx = -35.79, dz = -15.55 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_95", rel = { dx = -35.79, dz = -4.10 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_96", rel = { dx = -35.79, dz = 6.30 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_97", rel = { dx = -35.73, dz = 18.19 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_98", rel = { dx = -35.73, dz = 65.37 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_99", rel = { dx = 58.97, dz = 77.52 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_100", rel = { dx = 58.97, dz = 89.63 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_101", rel = { dx = -35.89, dz = 77.34 }, heading = 1.570796 },
  { type = "HESCO_wallperimeter_1", name = "STORE_STATIC_102", rel = { dx = -35.85, dz = 89.23 }, heading = 1.570796 },
  { type = "HESCO_watchtower_1", name = "STORE_STATIC_103", rel = { dx = 52.26, dz = 88.24 }, heading = 4.712389 },
  { type = "HESCO_watchtower_1", name = "STORE_STATIC_104", rel = { dx = -30.21, dz = 87.15 }, heading = 4.712389 },
  { type = "HESCO_watchtower_1", name = "STORE_STATIC_105", rel = { dx = -30.66, dz = -13.01 }, heading = 1.570796 },
  { type = "HESCO_watchtower_1", name = "STORE_STATIC_106", rel = { dx = 52.31, dz = -14.45 }, heading = 1.570796 },
  { type = "M 818", name = "STORE_STATIC_107", rel = { dx = 36.26, dz = -1.29 }, heading = 3.159046 },
  { type = "M 818", name = "STORE_STATIC_108", rel = { dx = 36.09, dz = -5.54 }, heading = 3.159046 },
  { type = "M 818", name = "STORE_STATIC_109", rel = { dx = 36.00, dz = -9.79 }, heading = 3.159046 },
  { type = "M 818", name = "STORE_STATIC_110", rel = { dx = -13.59, dz = 78.79 }, heading = 0.017453 },
  { type = "M 818", name = "STORE_STATIC_111", rel = { dx = -13.70, dz = 83.64 }, heading = 0.017453 },
  { type = "M 818", name = "STORE_STATIC_112", rel = { dx = -13.52, dz = 88.78 }, heading = 0.017453 },
}



local LOGI_STATIC_TEMPLATE = {
  { type = ".Command Center", name = "LOGI_STATIC_1",  rel = { dx = -3.30, dz = 26.31 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_2",  rel = { dx = -43.69, dz = 1.50 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_3",  rel = { dx = -35.71, dz = 10.45 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_4",  rel = { dx = -27.82, dz = 19.41 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_5",  rel = { dx = -19.60, dz = 28.60 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_6",  rel = { dx = -11.57, dz = 37.68 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_7",  rel = { dx = -3.19, dz = 47.01 }, heading = 0.844739 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_8",  rel = { dx = -43.34, dz = -6.63 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_9",  rel = { dx = -7.16, dz = -38.74 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_10", rel = { dx = -34.39, dz = -14.61 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_11", rel = { dx = 2.17,  dz = -47.13 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_12", rel = { dx = -25.42, dz = -22.50 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_13", rel = { dx = -16.24, dz = -30.71 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_14", rel = { dx = 39.80, dz = 15.22 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_15", rel = { dx = 30.72, dz = 23.25 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_16", rel = { dx = 12.57, dz = 39.35 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_17", rel = { dx = 49.13, dz = 6.84 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_18", rel = { dx = 3.62,  dz = 47.34 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_19", rel = { dx = 21.53, dz = 31.47 }, heading = 5.557128 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_20", rel = { dx = 35.51, dz = -19.23 }, heading = 3.986332 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_21", rel = { dx = 19.26, dz = -37.50 }, heading = 3.986332 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_22", rel = { dx = 43.39, dz = -10.27 }, heading = 3.986332 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_23", rel = { dx = 10.88, dz = -46.83 }, heading = 3.986332 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_24", rel = { dx = 51.38, dz = -1.31 }, heading = 3.986332 },
  { type = "HESCO_watchtower_1",   name = "LOGI_STATIC_25", rel = { dx = 5.97,  dz = -41.57 }, heading = 2.432989 },
  { type = "HESCO_wallperimeter_1", name = "LOGI_STATIC_26", rel = { dx = 7.59,  dz = 34.00 }, heading = 5.557128 },
  { type = "HESCO_watchtower_1",   name = "LOGI_STATIC_27", rel = { dx = 44.51, dz = 1.85 }, heading = 2.432989 },
  { type = "Tent01",               name = "LOGI_STATIC_28", rel = { dx = 6.58,  dz = -21.55 }, heading = 5.574582 },
  { type = "Tent02",               name = "LOGI_STATIC_29", rel = { dx = 23.74, dz = 10.86 }, heading = 5.557128 },
  { type = "Tent03",               name = "LOGI_STATIC_30", rel = { dx = -33.60, dz = -3.79 }, heading = 5.557128 },
  { type = "Tent03",               name = "LOGI_STATIC_31", rel = { dx = -22.70, dz = -13.34 }, heading = 5.557128 },
  { type = "Tent03",               name = "LOGI_STATIC_32", rel = { dx = -13.61, dz = -7.28 }, heading = 3.986332 },
  { type = "Tent03",               name = "LOGI_STATIC_33", rel = { dx = -18.22, dz = -2.81 }, heading = 3.986332 },
  { type = "Tent03",               name = "LOGI_STATIC_34", rel = { dx = -24.38, dz = 2.56 }, heading = 3.986332 },
  { type = "Tent03",               name = "LOGI_STATIC_35", rel = { dx = -29.38, dz = 7.01 }, heading = 3.986332 },
  { type = "Tent05",               name = "LOGI_STATIC_36", rel = { dx = -11.30, dz = -17.88 }, heading = 3.986332 },
}

function pickCountryForSide(sideId)
  if not (env and env.mission and env.mission.coalition) then return (sideId==coalition.side.BLUE) and country.id.USA or country.id.RUSSIA end
  local sideTbl = (sideId==coalition.side.BLUE) and env.mission.coalition.blue or env.mission.coalition.red
  if sideTbl and sideTbl.country then for _,c in pairs(sideTbl.country) do if type(c)=="table" and c.id then return c.id end end end
  return (sideId==coalition.side.BLUE) and country.id.USA or country.id.RUSSIA
end

local _logi_uid=0
local function _uniqueName(base,idx,x,z) _logi_uid=_logi_uid+1 return string.format("%s_%d_%d_%d_%d",base or "LOGI_STATIC",_logi_uid,idx or 0,math.floor(x or 0),math.floor(z or 0)) end
function spawnLOGITemplateAt(ax, az, baseHeading, rotateRel, countryId)
  baseHeading=baseHeading or 0; if rotateRel==nil then rotateRel=true end; countryId=countryId or country.id.USA
  local spawned,failed=0,0
  for i,ent in ipairs(LOGI_STATIC_TEMPLATE) do
    local dx,dz=ent.rel.dx,ent.rel.dz
    if rotateRel then local ca,sa=math.cos(baseHeading),math.sin(baseHeading) local rx=dx*ca-dz*sa local rz=dx*sa+dz*ca dx,dz=rx,rz end
    local x=ax+dx local z=az+dz local hdg=((ent.heading or 0)+baseHeading)%(2*math.pi)
    local staticData={country=countryId,name=_uniqueName(ent.name or "LOGI_STATIC",i,x,z),type=ent.type,x=x,y=z,heading=hdg,category=TYPE_CATEGORY[ent.type]}
    coalition.addStaticObject(countryId,staticData)
  end
end

-- ===== DEPOT / STORE static template & spawn (BLUESTORE / REDSTORE) =====

-- Centre 2D d'une zone standard (cercle) via trigger.misc.getZone
function _zoneCenter2D(name)
  if not (trigger and trigger.misc and trigger.misc.getZone) then return nil end
  local z = trigger.misc.getZone(name)
  if not (z and z.point) then return nil end
  return { x = z.point.x, z = z.point.z }
end

-- Spawn d'un camp STORE sur une position (ax, az) pour un pays donné
function spawnStoreTemplateAt(ax, az, countryId)
  countryId = countryId or country.id.USA
  local spawned, failed = 0, 0

  for idx, ent in ipairs(STORE_STATIC_TEMPLATE or {}) do
    local x   = ax + (ent.rel.dx or 0)
    local z   = az + (ent.rel.dz or 0)
    local hdg = ent.heading or 0

    -- Cas particulier : le pad FARP
    if ent.type == "FARP_SINGLE_01" then
      local farpData = {
        country    = countryId,
        category   = "Heliports",
        type       = "FARP_SINGLE_01",
        shape_name = "FARP_SINGLE_01",
        x          = x,
        y          = z,
        heading    = hdg,
        name       = _uniqueName(ent.name or "STORE_FARP", idx, x, z),

        -- Optionnel, mais ça recopie ce que tu as dans le .miz
        heliport_frequency   = 127.5,
        heliport_modulation  = 0,
        heliport_callsign_id = 1,
        rate                 = 100,
      }

      local ok, err = pcall(coalition.addStaticObject, countryId, farpData)
            local ok, err = pcall(coalition.addStaticObject, countryId, farpData)
      if ok then
        spawned = spawned + 1

        -- Remplir le warehouse du FARP de dépôt
        if _configureFarpWarehouse then
          _configureFarpWarehouse(farpData.name)
        end
      else
        failed  = failed + 1
      end


    else
      -- Cas général : tous les autres statics du camp dépôt
      local staticData = {
        country  = countryId,
        name     = _uniqueName(ent.name or "STORE_STATIC", idx, x, z),
        type     = ent.type,
        x        = x,
        y        = z,
        heading  = hdg,
        category = TYPE_CATEGORY[ent.type],
      }

      if staticData.category then
        local ok, err = pcall(coalition.addStaticObject, countryId, staticData)
        if ok then
          spawned = spawned + 1
        else
          failed  = failed + 1
        end
      else
        failed = failed + 1
      end
    end
  end

  return spawned, failed
end


-- Cherche les zones BLUESTORE / REDSTORE et spawn le camp correspondant
function spawnStoreCamps()
  -- Zones facultatives : si la zone n'existe pas, on ne fait rien
  local blueCenter = _zoneCenter2D("BLUESTORE")
  local redCenter  = _zoneCenter2D("REDSTORE")

  if blueCenter then
    local ctryBlue = (pickCountryForSide and pickCountryForSide(coalition.side.BLUE)) or country.id.USA
    spawnStoreTemplateAt(blueCenter.x, blueCenter.z, ctryBlue)
  end

  if redCenter then
    local ctryRed = (pickCountryForSide and pickCountryForSide(coalition.side.RED)) or country.id.RUSSIA
    spawnStoreTemplateAt(redCenter.x, redCenter.z, ctryRed)
  end
end

-----------------------------------------------------------------------
--                   STORE – INFANTRY DROPS                         --
-----------------------------------------------------------------------
--[[
  SYSTÈME D'EMBARQUEMENT / DÉBARQUEMENT DE TROUPES ET CARGO
  
  Permet aux joueurs en hélicoptère (ou avion) de :
  - Embarquer des troupes depuis les zones BLUESTORE / REDSTORE
  - Déposer ces troupes n'importe où sur la carte
  - Embarquer et déposer des cargos (fuel / ammo)
  
  UTILISATION :
  1. Se poser dans la zone BLUESTORE ou REDSTORE (rayon 250m, AGL < 10m)
  2. Un menu F10 "Battlefield > Embarquement" apparaît
  3. Sélectionner le nombre de troupes (8/16/24/30) ou un cargo
  4. Décoller et se poser ailleurs
  5. Utiliser "Dépose Troupes" ou "Dépose Cargo" pour larguer
  
  Les troupes spawnées se déplacent automatiquement vers un WP aléatoire
  à 300m de leur point de dépose (formation diamant).
  
  La masse embarquée affecte le vol via setUnitInternalCargo() de DCS.
--]]

-- === COMPOSITIONS D'INFANTERIE PAR PRESET ===
--[[
  Définit la composition des groupes pour chaque preset d'effectif.
  - groups : Nombre de groupes DCS créés lors de la dépose
  - units : Types d'unités dans chaque groupe
  
  Exemple : [8] = 2 groupes de 4 soldats = 8 hommes total
  
  Poids par homme : 100 kg (défini dans STORE_EmbarkTroops)
--]]
local STORE_INF_COMPOSITIONS = {
  BLUE = {
    -- 8 hommes : 2 pelotons de 4
    [8] = {
      groups = 2,
      units  = { "Soldier M249", "Soldier M4", "Soldier M4", "Soldier RPG" },
    },
    -- 16 hommes : 4 pelotons de 4
    [16] = {
      groups = 4,
      units  = { "Soldier M249", "Soldier M4", "Soldier M4", "Soldier RPG" },
    },
    -- 24 hommes : 6 pelotons de 4
    [24] = {
      groups = 6,
      units  = { "Soldier M249", "Soldier M4", "Soldier M4", "Soldier RPG" },
    },
    -- 30 hommes : 6 pelotons de 5 (avec Stinger)
    [30] = {
      groups = 6,
      units  = { "Soldier M249", "Soldier M4", "Soldier M4", "Soldier RPG", "Soldier stinger" },
    },
  },
  RED = {
    -- 8 hommes : 2 pelotons de 4
    [8] = {
      groups = 2,
      units  = { "Infantry AK ver2", "Infantry AK ver2", "Infantry AK ver2", "Soldier RPG" },
    },
    -- 16 hommes : 4 pelotons de 4
    [16] = {
      groups = 4,
      units  = { "Infantry AK ver2", "Infantry AK ver2", "Infantry AK ver2", "Soldier RPG" },
    },
    -- 24 hommes : 6 pelotons de 4
    [24] = {
      groups = 6,
      units  = { "Infantry AK ver2", "Infantry AK ver2", "Infantry AK ver2", "Soldier RPG" },
    },
    -- 30 hommes : 6 pelotons de 5 (avec Igla)
    [30] = {
      groups = 6,
      units  = { "Infantry AK ver2", "Infantry AK ver2", "Infantry AK ver2", "Soldier RPG", "SA-18 Igla manpad" },
    },
  }
}

-- Configuration des cargos embarquables (fuel / ammo)
-- Types détectés : noms contenant "fueltank" ou "ammo" (cf. LOGI_FARP_ScanAndDispatch)
local STORE_CARGO_CFG = {
  mass_kg = 1500,  -- masse d'un cargo (fuel ou ammo)
  types = {
    BLUE = {
      fuel = "ammo_cargo",        -- Type DCS pour cargo fuel BLUE
      ammo = "ammo_cargo",        -- Type DCS pour cargo ammo BLUE
    },
    RED = {
      fuel = "ammo_cargo",        -- Type DCS pour cargo fuel RED
      ammo = "ammo_cargo",        -- Type DCS pour cargo ammo RED
    },
  },
}

-- Petit random int/float compatible avec le RNG global si présent
function _storeRandInt(a, b)
  if RNGi then return RNGi(a, b) end
  return a + math.floor(math.random() * (b - a + 1))
end

function _storeRandFloat()
  if RNGf then return RNGf() end
  return math.random()
end

-- Dir avant de l’unité (fx,fz normalisé)
function _storeForwardDir(u)
  local m = u:getPosition()
  if not m or not m.x then return 1, 0 end
  local fx, fz = m.x.x or 1, m.x.z or 0
  local L = math.sqrt(fx*fx + fz*fz)
  if L < 1e-6 then return 1, 0 end
  return fx / L, fz / L
end


-- Retourne / crée l'état d'un groupe (clé = nom de groupe)
function _storeGetTroopState(gname)
  local st = STORE_EMBARK_STATE[gname]
  if not st then
    st = {
      gname       = gname,
      embarkedKg  = 0,
      embarkedMen = 0,
      lastPreset  = nil, -- 8, 16, 24 ou 30 selon le dernier embarquement
      -- Cargo (fuel / ammo)
      embarkedCargo = nil,  -- nil, "fuel" ou "ammo"
      cargoKg       = 0,
    }
    STORE_EMBARK_STATE[gname] = st
  end
  return st
end


-- Récupère l'unité "joueur" du groupe (ou à défaut la première)
function _storeGetPlayerUnitOfGroup(g)
  if not g or not Group.isExist(g) then return nil end
  local units = g:getUnits()
  if not units or #units == 0 then return nil end

  local candidate = nil
  for _, u in ipairs(units) do
    if u and Unit.isExist(u) then
      candidate = candidate or u
      if u.getPlayerName and u:getPlayerName() then
        candidate = u
        break
      end
    end
  end
  return candidate
end

-- Spawn d'un groupe d'infanterie issu du STORE
-- args = {
--   heliName, side, sideKey, preset, unitTypes,
--   idx, total
-- }
function _storeSpawnInfantryGroup(args, time)
  local heli = Unit.getByName(args.heliName)
  if not heli or not Unit.isExist(heli) then
    return -- hélico plus là -> on arrête la séquence
  end

  local side     = args.side
  local sideKey  = args.sideKey
  local preset   = args.preset
  local unitTypes = args.unitTypes or {}
  local idx      = args.idx or 1
  local total    = args.total or 1

  -- Position derrière l'hélico (15 m)
  local p3 = heli:getPoint()
  local fx, fz = _storeForwardDir(heli)
  local backDist = 15
  local sx = p3.x - fx * backDist
  local sz = p3.z - fz * backDist
  local sy = land.getHeight({ x = sx, y = sz })

  local spawnPos = { x = sx, y = sy, z = sz }

  -- WP aléatoire dans un rayon de 300 m
  local r   = 300 * math.sqrt(_storeRandFloat()) -- répartition uniforme disque
  local ang = 2 * math.pi * _storeRandFloat()
  local dx  = r * math.cos(ang)
  local dz  = r * math.sin(ang)
  local tx  = sx + dx
  local tz  = sz + dz
  local ty  = land.getHeight({ x = tx, y = tz })
  local destPos = { x = tx, y = ty, z = tz }

  local ctry = heli:getCountry() or _country(side)
  local speed = 5 -- m/s approximatif
  local skill = "Average"

  local gname = string.format("STORE_%s_INF_%02d_%06d", sideKey, idx, _storeRandInt(100000, 999999))

  -- On écarte légèrement les unités latéralement
  local units  = {}
  local count  = #unitTypes
  local spread = 2.0 -- m entre hommes
  local lx, lz = -fz, fx -- vers la gauche

  for i, utype in ipairs(unitTypes) do
    local ofs = (i - (count + 1)/2) * spread
    local ux  = sx + lx * ofs
    local uz  = sz + lz * ofs

    units[#units+1] = {
      type    = utype,
      name    = gname .. "_U" .. i,
      x       = ux,
      y       = uz,
      heading = math.atan2(fx, fz),
      skill   = skill
    }
  end

  local route = {
    points = {
      {
        x = spawnPos.x, y = spawnPos.z,
        alt = spawnPos.y,
        speed = speed, speed_locked = true,
        type  = "Turning Point",
        action = "Off Road",
        task = { id = "ComboTask", params = { tasks = {} } }
      },
      {
        x = destPos.x, y = destPos.z,
        alt = destPos.y,
        speed = speed, speed_locked = true,
        type  = "Turning Point",
        -- IMPORTANT : formation "Diamond"
        action = "Diamond",
        task = { id = "ComboTask", params = { tasks = {} } }
      }
    }
  }

  pcall(coalition.addGroup, ctry, Group.Category.GROUND, {
    visible        = true,
    lateActivation = false,
    route          = route,
    tasks          = {},
    units          = units,
    name           = gname
  })

  -- S'il reste des groupes à déposer, on reprogramme dans 5 s
  if idx < total then
    args.idx = idx + 1
    return time + 5
  end

  return
end

-- Lance la séquence de dépôts (1 groupe toutes les 5 s)
-- Lance la séquence de dépôts (1 groupe toutes les 5 s)
function _storeStartDropSequence(u, st, gname, gid)
  if not u or not Unit.isExist(u) then
    trigger.action.outTextForGroup(gid, "Battlefield – Dépose impossible : appareil introuvable.", 6)
    return
  end

  -- Déterminer la coalition via le pays de l'unité
  local ctry = u:getCountry()
  local side = nil
  if ctry and coalition.getCountryCoalition then
    side = coalition.getCountryCoalition(ctry)
  end
  if not side then
    -- fallback très basique
    side = coalition.side.BLUE
  end

  -- Dans ton script, c'est _sideKeySimple qui existe
  local sideKey = _sideKeySimple(side)

  local men = st.embarkedMen or 0
  if men <= 0 then
    trigger.action.outTextForGroup(gid, "Battlefield – Aucun personnel à déposer.", 6)
    return
  end

  -- On se base sur le dernier preset (8, 16, 24 ou 30). Fallback sur le nombre embarqué.
  local preset = st.lastPreset
  if not preset then
    if men >= 30 then
      preset = 30
    elseif men >= 24 then
      preset = 24
    elseif men >= 16 then
      preset = 16
    elseif men >= 8 then
      preset = 8
    else
      trigger.action.outTextForGroup(
        gid,
        "Battlefield – Effectif embarqué invalide pour la dépose (minimum 8).",
        8
      )
      return
    end
  end

  local sideCfg = STORE_INF_COMPOSITIONS[sideKey]
  if not sideCfg or not sideCfg[preset] then
    trigger.action.outTextForGroup(
      gid,
      "Battlefield – Aucune composition d'infanterie définie pour ce camp / effectif.",
      8
    )
    return
  end

  local cfg   = sideCfg[preset]
  local total = cfg.groups or 1
  local units = cfg.units or {}

  local args = {
    heliName  = u:getName(),  -- fonctionne aussi pour les avions
    side      = side,
    sideKey   = sideKey,
    preset    = preset,
    unitTypes = units,
    idx       = 1,
    total     = total,
  }

  -- On démarre la séquence quasi immédiatement
  timer.scheduleFunction(_storeSpawnInfantryGroup, args, timer.getTime() + 0.1)
end


-- Embarquement de troupes (8, 16, 24 ou 30 hommes)
local function STORE_EmbarkTroops(gname, count)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end

  local gid = g:getID()
  local st  = _storeGetTroopState(gname)
  local u   = _storeGetPlayerUnitOfGroup(g)

  if not u or not Unit.isExist(u) then return end
  if not count or count <= 0 then return end

  local weightPer = 100 -- kg / homme
  local addKg     = count * weightPer

  st.embarkedMen = (st.embarkedMen or 0) + count
  st.embarkedKg  = (st.embarkedKg  or 0) + addKg
  st.lastPreset  = count            -- on retient 8, 16, 24 ou 30 pour la dépose

  -- Calcul du poids total (troupes + cargo)
  local totalKg = st.embarkedKg + (st.cargoKg or 0)

  -- On utilise la cargo interne pour simuler la charge
  if trigger and trigger.action and trigger.action.setUnitInternalCargo then
    pcall(trigger.action.setUnitInternalCargo, u:getName(), totalKg)
  end

  local msg = string.format(
    "Battlefield – %d hommes embarqués (+%d kg, total embarqué : %d kg).",
    count, addKg, totalKg
  )
  trigger.action.outTextForGroup(gid, msg, 10)
end

-- Embarquement d'un cargo (fuel ou ammo) - 1500 kg
-- cargoType = "fuel" ou "ammo"
local function STORE_EmbarkCargo(gname, cargoType)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end

  local gid = g:getID()
  local st  = _storeGetTroopState(gname)
  local u   = _storeGetPlayerUnitOfGroup(g)

  if not u or not Unit.isExist(u) then return end

  -- Vérifie qu'on n'a pas déjà un cargo embarqué
  if st.embarkedCargo then
    local msg = string.format(
      "Battlefield – Cargo %s déjà embarqué. Déposez-le d'abord.",
      st.embarkedCargo == "fuel" and "FUEL" or "AMMO"
    )
    trigger.action.outTextForGroup(gid, msg, 8)
    return
  end

  local cargoMass = STORE_CARGO_CFG.mass_kg or 1500

  st.embarkedCargo = cargoType
  st.cargoKg       = cargoMass

  -- Calcul du poids total (troupes + cargo)
  local totalKg = (st.embarkedKg or 0) + st.cargoKg

  -- On utilise la cargo interne pour simuler la charge
  if trigger and trigger.action and trigger.action.setUnitInternalCargo then
    pcall(trigger.action.setUnitInternalCargo, u:getName(), totalKg)
  end

  local cargoLabel = (cargoType == "fuel") and "FUEL" or "AMMO"
  local msg = string.format(
    "Battlefield – Cargo %s embarqué (+%d kg, total embarqué : %d kg).",
    cargoLabel, cargoMass, totalKg
  )
  trigger.action.outTextForGroup(gid, msg, 10)
end

-- Dépose d'un cargo (fuel ou ammo) - spawn d'un objet statique
local function STORE_DropCargo(gname)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end

  local gid = g:getID()
  local st  = _storeGetTroopState(gname)
  local u   = _storeGetPlayerUnitOfGroup(g)

  if not u or not Unit.isExist(u) then return end

  -- Vérifie qu'on a bien un cargo embarqué
  if not st.embarkedCargo then
    trigger.action.outTextForGroup(gid, "Battlefield – Aucun cargo à déposer.", 6)
    return
  end

  local cargoType = st.embarkedCargo
  local cargoMass = st.cargoKg or 1500

  -- Position derrière l'hélico (20 m)
  local p3 = u:getPoint()
  local fx, fz = _storeForwardDir(u)
  local backDist = 20
  local sx = p3.x - fx * backDist
  local sz = p3.z - fz * backDist

  -- Déterminer la coalition
  local ctry = u:getCountry()
  local side = nil
  if ctry and coalition.getCountryCoalition then
    side = coalition.getCountryCoalition(ctry)
  end
  if not side then
    side = coalition.side.BLUE
  end
  local sideKey = (side == coalition.side.BLUE) and "BLUE" or "RED"

  -- Type de cargo à spawner (statique)
  -- Utilise les types standards DCS pour les cargos
  local staticType
  if cargoType == "fuel" then
    staticType = "fueltank_cargo"  -- ou "Fueltank_Cargo" selon la map/version
  else
    staticType = "ammo_cargo"      -- ou "Ammo_Cargo" selon la map/version
  end

  -- Nom unique pour l'objet statique
  local staticName = string.format("CARGO_%s_%s_%06d", sideKey, string.upper(cargoType), _storeRandInt(100000, 999999))

  -- Spawn du cargo statique
  local staticData = {
    name    = staticName,
    type    = staticType,
    x       = sx,
    y       = sz,
    heading = math.atan2(fx, fz),
  }

  local spawnOk = pcall(coalition.addStaticObject, ctry, staticData)

  -- Reset de l'état cargo
  st.embarkedCargo = nil
  st.cargoKg       = 0

  -- Mise à jour du poids total
  local totalKg = st.embarkedKg or 0
  if trigger and trigger.action and trigger.action.setUnitInternalCargo then
    pcall(trigger.action.setUnitInternalCargo, u:getName(), totalKg)
  end

  local cargoLabel = (cargoType == "fuel") and "FUEL" or "AMMO"
  local msg
  if spawnOk then
    msg = string.format(
      "Battlefield – Cargo %s déposé (-%d kg, total embarqué : %d kg).",
      cargoLabel, cargoMass, totalKg
    )
  else
    msg = string.format(
      "Battlefield – Cargo %s largué (-%d kg). [Spawn échoué]",
      cargoLabel, cargoMass
    )
  end
  trigger.action.outTextForGroup(gid, msg, 10)
end


-- Dépose des troupes
-- Dépose des troupes
local function STORE_DropTroops(gname)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end

  local gid = g:getID()
  local st  = STORE_EMBARK_STATE[gname]
  if not st or (st.embarkedMen or 0) <= 0 then
    trigger.action.outTextForGroup(gid, "Battlefield – Aucun personnel à déposer.", 6)
    return
  end

  local u = _storeGetPlayerUnitOfGroup(g)
  if not u or not Unit.isExist(u) then return end

  local men = st.embarkedMen or 0
  local kg  = st.embarkedKg  or 0

  -- Lance la séquence de spawn des groupes (1 toutes les 5 s, diamant + WP 300 m)
  _storeStartDropSequence(u, st, gname, gid)

  -- On remet la charge troupes à 0 mais on conserve le cargo
  local remainingKg = st.cargoKg or 0
  if trigger and trigger.action and trigger.action.setUnitInternalCargo then
    pcall(trigger.action.setUnitInternalCargo, u:getName(), remainingKg)
  end

  st.embarkedMen = 0
  st.embarkedKg  = 0
  st.lastPreset  = nil

  local msg = string.format("Battlefield – Dépose en cours : %d hommes (%d kg).", men, kg)
  trigger.action.outTextForGroup(gid, msg, 10)
end


local function _storeEnsureMenusForGroup(g)
  if not g or not Group.isExist(g) then return end

  local gid   = g:getID()
  local gname = g:getName()
  local st    = _storeGetTroopState(gname)

  if st.menuVisible and st.menuEmbark then
    return
  end

  -- On récupère/ crée le root Battlefield / Secteurs
  local root = BF_EnsureSectorMenuForGroup(gid, gname)
  if type(root) == "table" then
    -- Au cas où BF_EnsureSectorMenuForGroup renverrait (root, sectorsMenu),
    -- on ne garde que le 1er retour.
    root = root
  end

  -- Sous-menu Embarquement
  local embarkMenu = missionCommands.addSubMenuForGroup(gid, "Embarquement", root)

  st.menuRoot    = root
  st.menuEmbark  = embarkMenu
  st.menuVisible = true

  -- Actions Embarquement Troupes (8, 16, 24, 30 hommes)
  st.cmd8    = missionCommands.addCommandForGroup(gid, "8 Hommes (800 kg)",   embarkMenu, STORE_EmbarkTroops, gname, 8)
  st.cmd16   = missionCommands.addCommandForGroup(gid, "16 Hommes (1600 kg)", embarkMenu, STORE_EmbarkTroops, gname, 16)
  st.cmd24   = missionCommands.addCommandForGroup(gid, "24 Hommes (2400 kg)", embarkMenu, STORE_EmbarkTroops, gname, 24)
  st.cmd30   = missionCommands.addCommandForGroup(gid, "30 Hommes (3000 kg)", embarkMenu, STORE_EmbarkTroops, gname, 30)

  -- Actions Embarquement Cargo (fuel / ammo)
  st.cmdFuel = missionCommands.addCommandForGroup(gid, "Cargo FUEL (1500 kg)", embarkMenu, STORE_EmbarkCargo, gname, "fuel")
  st.cmdAmmo = missionCommands.addCommandForGroup(gid, "Cargo AMMO (1500 kg)", embarkMenu, STORE_EmbarkCargo, gname, "ammo")

  -- Les menus de dépose sont gérés séparément par _storeEnsureDropMenus
end

-- Assure que les menus de dépose existent si nécessaire (cargo ou troupes embarqués)
local function _storeEnsureDropMenus(gname)
  local st = _storeGetTroopState(gname)
  if not st then return end

  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return end
  local gid = g:getID()

  -- On récupère/ crée le root Battlefield
  local root = BF_EnsureSectorMenuForGroup(gid, gname)
  if type(root) == "table" then root = root end
  st.menuRoot = root

  -- Vérifie si on a des troupes ou du cargo embarqués
  local hasTroops = (st.embarkedMen or 0) > 0
  local hasCargo  = st.embarkedCargo ~= nil

  -- Menu Dépose Troupes
  if hasTroops and not st.cmdDrop then
    st.cmdDrop = missionCommands.addCommandForGroup(gid, "Dépose Troupes", root, STORE_DropTroops, gname)
  elseif not hasTroops and st.cmdDrop then
    pcall(missionCommands.removeItemForGroup, gid, st.cmdDrop)
    st.cmdDrop = nil
  end

  -- Menu Dépose Cargo
  if hasCargo and not st.cmdDropCargo then
    st.cmdDropCargo = missionCommands.addCommandForGroup(gid, "Dépose Cargo", root, STORE_DropCargo, gname)
  elseif not hasCargo and st.cmdDropCargo then
    pcall(missionCommands.removeItemForGroup, gid, st.cmdDropCargo)
    st.cmdDropCargo = nil
  end
end



-- Supprime les menus d'EMBARQUEMENT d'un groupe (quand il quitte la zone STORE)
-- Les menus de DEPOSE sont gérés séparément et persistent tant qu'il y a du cargo/troupes
local function _storeRemoveMenusForGroup(gname)
  local st = STORE_EMBARK_STATE[gname]
  if not st then return end

  local g   = Group.getByName(gname)
  local gid = g and g:getID() or nil

  if missionCommands then
    if gid and missionCommands.removeItemForGroup then
      -- On ne supprime QUE les éléments liés à l'embarquement (pas les menus de dépose)
      if st.cmd8        then pcall(missionCommands.removeItemForGroup, gid, st.cmd8)        end
      if st.cmd16       then pcall(missionCommands.removeItemForGroup, gid, st.cmd16)       end
      if st.cmd24       then pcall(missionCommands.removeItemForGroup, gid, st.cmd24)       end
      if st.cmd30       then pcall(missionCommands.removeItemForGroup, gid, st.cmd30)       end
      if st.cmdFuel     then pcall(missionCommands.removeItemForGroup, gid, st.cmdFuel)     end
      if st.cmdAmmo     then pcall(missionCommands.removeItemForGroup, gid, st.cmdAmmo)     end
      if st.menuEmbark  then pcall(missionCommands.removeItemForGroup, gid, st.menuEmbark)  end
    elseif missionCommands.removeItem then
      if st.cmd8        then pcall(missionCommands.removeItem, st.cmd8)        end
      if st.cmd16       then pcall(missionCommands.removeItem, st.cmd16)       end
      if st.cmd24       then pcall(missionCommands.removeItem, st.cmd24)       end
      if st.cmd30       then pcall(missionCommands.removeItem, st.cmd30)       end
      if st.cmdFuel     then pcall(missionCommands.removeItem, st.cmdFuel)     end
      if st.cmdAmmo     then pcall(missionCommands.removeItem, st.cmdAmmo)     end
      if st.menuEmbark  then pcall(missionCommands.removeItem, st.menuEmbark)  end
    end
  end

  -- On conserve st.menuRoot (Battlefield + Secteurs) et les menus de dépose
  st.menuEmbark   = nil
  st.cmd8         = nil
  st.cmd16        = nil
  st.cmd24        = nil
  st.cmd30        = nil
  st.cmdFuel      = nil
  st.cmdAmmo      = nil
  -- st.cmdDrop et st.cmdDropCargo sont conservés !
  st.menuVisible  = false
end



-- Scan périodique des appareils (hélicos + avions) dans les zones STORE
local function STORE_CheckEmbarkCandidates()
  local now = timer.getTime()

  -- Centres des zones dépôt (zones facultatives, comme pour le spawn)
  local blueCenter = _zoneCenter2D("BLUESTORE")
  local redCenter  = _zoneCenter2D("REDSTORE")

  local AIR_CATEGORIES = {
    Group.Category.HELICOPTER,
    Group.Category.AIRPLANE,
  }

  local function checkSide(sideId, center)
    -- center peut être nil si la zone n'existe pas
    
    for _, cat in ipairs(AIR_CATEGORIES) do
      local groups = coalition.getGroups(sideId, cat) or {}
      for _, g in ipairs(groups) do
        if g and Group.isExist(g) then
          local gname    = g:getName()
          local st       = _storeGetTroopState(gname)
          local inZone   = false
          local hasPilot = false

          local units = g:getUnits()
          if units then
            for _, u in ipairs(units) do
              if u and Unit.isExist(u) and u.getPlayerName and u:getPlayerName() then
                hasPilot = true
                
                -- Vérifie si dans la zone STORE (si elle existe)
                if center then
                  local p  = u:getPoint()
                  if p then
                    local pos2 = { x = p.x, z = p.z }
                    local d    = _dist2(pos2, center)

                    if d <= 250 then
                      local agl = p.y - land.getHeight({ x = p.x, y = p.z })
                      if agl <= 10 then
                        inZone = true
                        break
                      end
                    end
                  end
                end
              end
            end
          end

          -- Gestion des menus d'EMBARQUEMENT (seulement dans la zone STORE)
          if hasPilot and inZone then
            -- Appareil joueur posé dans la zone dépôt -> menus embarquement ON
            _storeEnsureMenusForGroup(g)
            st.inZone = true
          else
            -- plus dans la zone ou plus de pilote -> menus embarquement OFF
            if st.inZone or st.menuVisible then
              _storeRemoveMenusForGroup(gname)
              st.inZone = false
            end
          end

          -- Gestion des menus de DEPOSE (partout, tant qu'il y a du cargo/troupes)
          if hasPilot then
            _storeEnsureDropMenus(gname)
          end
        end
      end
    end
  end

  -- Vérifie les deux camps (même si le centre est nil, on vérifie les menus de dépose)
  checkSide(coalition.side.BLUE, blueCenter)
  checkSide(coalition.side.RED,  redCenter)

  return now + 10 -- re-check dans 10 s
end




function placeLOGITemplateOnMarkers(opts)
  opts=opts or {}
  local blueCountry=opts.blueCountry or pickCountryForSide(coalition.side.BLUE)
  local redCountry =opts.redCountry  or pickCountryForSide(coalition.side.RED)
  local baseHeadingBlue=math.rad(opts.baseHeadingBlueDeg or 0)
  local baseHeadingRed =math.rad(opts.baseHeadingRedDeg  or 0)
  for _,p in ipairs(LOGI_BLUE_POINTS or {}) do buildExclusionAt(blueCountry,p.x,p.z,LOGI_EXCLUSION_RADIUS) spawnLOGITemplateAt(p.x,p.z,baseHeadingBlue,true,blueCountry) end
  for _,p in ipairs(LOGI_RED_POINTS or {})  do buildExclusionAt(redCountry ,p.x,p.z,LOGI_EXCLUSION_RADIUS) spawnLOGITemplateAt(p.x,p.z,baseHeadingRed ,true,redCountry ) end
end

-- ===== DEFENSE pools & spawns =====
local RED_DEFEND_POOL = {
  {w=20, kind="INF",  types={"Infantry AK ver2","Infantry AK ver3"} , count=8},
  {w=15, kind="TMB",  types={"T-55","T-72B"}                        , count=2},
  {w=15, kind="TMH",  types={"T-72B3","T-90","CHAP_T90M"}           , count=2},
  {w=30, kind="APC",  types={"BMP-2","BTR-80"}                      , count=2},
  {w=20, kind="SAM",  types={"Strela-10M3","ZSU-23-4 Shilka","Osa 9A33 ln","2S6 Tunguska"}, count=1},
}
local BLUE_DEFEND_POOL = {
  {w=20, kind="INF",  types={"Soldier M4"}                           , count=8},
  {w=15, kind="TMB",  types={"M-60","M-1 Abrams","LAV-25"}           , count=2},
  {w=15, kind="TMH",  types={"M1A2C_SEP_V3","M-2 Bradley"}           , count=2},
  {w=30, kind="APC",  types={"M1043 HMMWV Armament","LAV-25"}        , count=2},
  {w=20, kind="SAM",  types={"Vulcan","M1097 Avenger","Roland ADS","M48 Chaparral"}, count=1},
}
function weightedPick(pool) local tot=0 for _,e in ipairs(pool) do tot=tot+e.w end local r=RNG.random()*tot local acc=0 for _,e in ipairs(pool) do acc=acc+e.w if r<=acc then return e end end return pool[#pool] end
local function _ri(a,b) return a + math.floor(RNG.random()*(b-a+1)) end
local function _r() return RNG.random() end

local function _nearestLogiFor(sideId, markerPt) local list=(sideId==coalition.side.BLUE) and LOGI_BLUE_POINTS or LOGI_RED_POINTS local best,bestD=nil,math.huge if list then for _,p in ipairs(list) do local d=dist2D(markerPt,p) if d<bestD then bestD=d; best={x=p.x,z=p.z} end end end return best or {x=markerPt.x, z=markerPt.z} end
local function _selectMarkersWithSpacing(markers, minD) local kept={} for _,pt in ipairs(markers or {}) do local ok=true for __,kp in ipairs(kept) do local dx,dz=pt.x-kp.x,pt.z-kp.z if (dx*dx+dz*dz)<(minD*minD) then ok=false break end end if ok then kept[#kept+1]=pt end end return kept end

function spawnGroupAt(sideId, countryId, pt_on_marker, headingDeg, pool)
  local choice=weightedPick(pool) local count=choice.count or 1 local isInf=(choice.kind=="INF") local hdgRad=math.rad((headingDeg or 0)%360)
  local logiPt=_nearestLogiFor(sideId, pt_on_marker) local dirx,dirz=pt_on_marker.x-logiPt.x, pt_on_marker.z-logiPt.z local len=math.sqrt(dirx*dirx+dirz*dirz) local ux,uz=(len>0) and (dirx/len) or 0, (len>0) and (dirz/len) or 0
  local center=isInf and {x=pt_on_marker.x,z=pt_on_marker.z} or {x=pt_on_marker.x+800*ux, z=pt_on_marker.z+800*uz}
  local units={}
  if isInf then
    local R=25; for i=1,count do local r=R*math.sqrt(_r()); local ang=2*math.pi*_r(); local ux_i=center.x+r*math.cos(ang); local uz_i=center.z+r*math.sin(ang)
      units[#units+1]={ type=choice.types[_ri(1,#choice.types)], name=string.format("%s_%s_%d",(sideId==coalition.side.BLUE) and "BLU" or "RED",choice.kind,_ri(100000,999999)), x=ux_i, y=uz_i, heading=hdgRad, skill="High" } end
  else
    local vx,vz=-uz,ux; local gap=50; local mid=(count-1)*0.5
    for i=1,count do local ofs=(i-1-mid)*gap; local ux_i=center.x+vx*ofs; local uz_i=center.z+vz*ofs
      units[#units+1]={ type=choice.types[_ri(1,#choice.types)], name=string.format("%s_%s_%d",(sideId==coalition.side.BLUE) and "BLU" or "RED",choice.kind,_ri(100000,999999)), x=ux_i, y=uz_i, heading=hdgRad, skill="High" } end
  end
  local gp={visible=false,lateActivation=false,tasks={},route={points={[1]={x=center.x,y=center.z,type="Turning Point",action="Off Road",speed=0,speed_locked=true,task={id="ComboTask",params={tasks={}}}}}},units=units,name=string.format("DEF_%s_%s_%d",(sideId==coalition.side.BLUE) and "BLU" or "RED",choice.kind,_ri(100000,999999))}
  coalition.addGroup(countryId, Group.Category.GROUND, gp)
end

function spawnDefendersOnMarkers()
  local blueCountry=pickCountryForSide(coalition.side.BLUE); local redCountry=pickCountryForSide(coalition.side.RED)
  local hBlue=DEFEND_BEARINGS.blue_to_red_deg or 0; local hRed=DEFEND_BEARINGS.red_to_blue_deg or 0
  local minSpacing=2000
  local blueMarkers=_selectMarkersWithSpacing(DEFEND_BLUE_POINTS or {},minSpacing)
  local redMarkers =_selectMarkersWithSpacing(DEFEND_RED_POINTS  or {},minSpacing)
  local jobs={}
  for _,p in ipairs(blueMarkers) do jobs[#jobs+1]={side=coalition.side.BLUE, country=blueCountry, pt=p, hdg=hBlue, pool=BLUE_DEFEND_POOL} end
  for _,p in ipairs(redMarkers ) do jobs[#jobs+1]={side=coalition.side.RED,  country=redCountry,  pt=p, hdg=hRed,  pool=RED_DEFEND_POOL } end
  local t0=timer.getTime()+10
  for i,job in ipairs(jobs) do timer.scheduleFunction(function() spawnGroupAt(job.side,job.country,job.pt,job.hdg,job.pool) end, {}, t0+(i-1)*5) end
  trigger.action.outText(string.format("[DEFENSE] %d groups planned (>=2km, T+10, +5s).", #jobs), 8)
end

-- ===== AD around LOGI (guarantee >=1) =====
function spawnSingleVehicleGroup(sideId,countryId,unitType,pt)
  local gp={visible=false,lateActivation=false,tasks={},route={ points={ [1]={ x=pt.x, y=pt.z, type="Turning Point", action="Off Road", speed=0, task={id="ComboTask",params={tasks={}}}} } },units={ [1]={ type=unitType, name="AD_"..unitType.."_"..RNG.randomInt(100000,999999), x=pt.x, y=pt.z, heading=0, skill="High" } }, name=(sideId==coalition.side.BLUE and "AD_GRP_BLU_" or "AD_GRP_RED_")..RNG.randomInt(100000,999999)}
  coalition.addGroup(countryId, Group.Category.GROUND, gp)
end
function randomAround(pt) local r=RNG.randomInt(150,450) local a=RNG.random()*2*math.pi return { x=pt.x+r*math.cos(a), z=pt.z+r*math.sin(a) } end

local RED_AD_SPECS = { {count=3,p=30,types={"Strela-10M3"}}, {count=3,p=30,types={"ZSU-23-4 Shilka"}}, {count=2,p=15,types={"2S6 Tunguska"}}, {count=2,p=20,types={"Osa 9A33 ln"}}, {count=1,p=5,types={"CHAP_PantsirS1"}}, }
local BLUE_AD_SPECS= { {count=3,p=30,types={"Vulcan"}}, {count=3,p=30,types={"M1097 Avenger"}}, {count=2,p=15,types={"HEMTT_C-RAM_Phalanx"}}, {count=2,p=20,types={"M48 Chaparral"}}, {count=2,p=5,types={"Roland ADS"}}, }
function rollSpawn(spec) return RNG.randomInt(1,100) <= spec.p end

function spawnADAroundLOGI()
  local blueCountry=pickCountryForSide(coalition.side.BLUE)
  local redCountry =pickCountryForSide(coalition.side.RED)

  local function doSide(list, specs, sideId, ctry)
    for _,p in ipairs(list or {}) do
      local spawned=0
      for _,spec in ipairs(specs) do
        for i=1,spec.count do
          if rollSpawn(spec) then
            local pt=randomAround(p)
            spawnSingleVehicleGroup(sideId,ctry,spec.types[_ri(1,#spec.types)],pt)
            spawned=spawned+1
          end
        end
      end
      if spawned==0 then
        local fallback = specs[1]
        local pt=randomAround(p)
        spawnSingleVehicleGroup(sideId,ctry,fallback.types[1],pt)
      end
    end
  end

  doSide(LOGI_RED_POINTS,  RED_AD_SPECS,  coalition.side.RED,  redCountry)
  doSide(LOGI_BLUE_POINTS, BLUE_AD_SPECS, coalition.side.BLUE, blueCountry)
end


function spawnLOGFARPAroundLOGI()
  local blueCountry = pickCountryForSide(coalition.side.BLUE)
  local redCountry  = pickCountryForSide(coalition.side.RED)

  LOG_FARP_GROUPS = { BLUE = {}, RED = {} }
  LOG_FARP_STATE  = { BLUE = {}, RED = {} }
  
  -- Remplit automatiquement le warehouse d'un FARP fraîchement créé
-- Requiert DCS 2.8.8+ (fonctions Warehouse/airbase:getWarehouse)


  

  local function doSide(logiList, sideId, ctry)
    local sideKey = (sideId == coalition.side.BLUE) and "BLUE" or "RED"

    for idx, p in ipairs(logiList or {}) do
      -- position du FARP : à 1000 m du centre LOGI, angle aléatoire
      local R  = 1000
      local a  = RNG.random() * 2 * math.pi
      local cx = p.x + R * math.cos(a)
      local cz = p.z + R * math.sin(a)

      local baseName = string.format("LOG_FARP_%s_%02d_%06d", sideKey, idx, RNG.randomInt(100000, 999999))

      local types
      if sideId == coalition.side.BLUE then
        -- BLEU : 2 Hummer, 2 M818, 1 M978 HEMTT Tanker
        types = {
          "Hummer",
          "Hummer",
          "M818",
          "M818",
          "M978 HEMTT Tanker",
        }
      else
        -- ROUGE : 1 SKP-11, 2 Ural-375, 1 ATZ-10, 1 ZiL-131 APA-80
        types = {
          "SKP-11",
          "Ural-375",
          "Ural-375",
          "ATZ-10",
          "ZiL-131 APA-80",
        }
      end

      local units = {}
      local gap   = 8
      local mid   = (#types + 1) * 0.5

      for i, utype in ipairs(types) do
        local ofs = (i - mid) * gap
        units[#units+1] = {
          type    = utype,
          name    = string.format("%s_U%d", baseName, i),
          x       = cx + ofs,
          y       = cz,
          heading = 0,
          skill   = "Average",
        }
      end

      local route = {
        points = {{
          x = cx, y = cz,
          type  = "Turning Point",
          action= "Off Road",
          speed = 0,
          speed_locked = true,
          task  = { id="ComboTask", params={tasks={}} }
        }}
      }

      coalition.addGroup(ctry, Group.Category.GROUND, {
        visible        = true,
        lateActivation = false,
        tasks          = {},
        route          = route,
        units          = units,
        name           = baseName,
      })

      -- mémorisation pour la logique FARP
      LOG_FARP_GROUPS[sideKey][#LOG_FARP_GROUPS[sideKey]+1] = {
        gname  = baseName,
        logiPt = { x = p.x, z = p.z },
      }
      LOG_FARP_STATE[sideKey][#LOG_FARP_GROUPS[sideKey]] = {
        status = "idle",    -- "idle" / "moving"
        target = nil,
      }
    end
  end

  doSide(LOGI_BLUE_POINTS or {}, coalition.side.BLUE, blueCountry)
  doSide(LOGI_RED_POINTS  or {}, coalition.side.RED,  redCountry)
end




-----------------------------------------------------------------------
--           SECTION AIR : COMBAT AÉRIEN RED + BLUE                 --
-----------------------------------------------------------------------
--[[
  MODULE AÉRIEN — CAP DYNAMIQUE BILATÉRAL
  
  Spawne des chasseurs en vol (air start) pour RED et BLUE.
  Chaque camp patrouille sur ses propres zones CAP posées par le MM.
  Distribution automatique : chaque avion choisit la zone la moins couverte.
  
  ZONES REQUISES (éditeur de mission) :
    RED  : REDAFB / REDAFB_1...   + REDCAP_1, REDCAP_2...
    BLUE : BLUEAFB / BLUEAFB_1... + BLUECAP_1, BLUECAP_2...
  
  Sélection du type : double lancé de dés (2×d500, distribution triangulaire).
  Skill : aléatoire (Average / Good / High / Excellent).
  Altitude : aléatoire par type d'appareil (plage configurable).
  Emports de combat (pylons) configurés par type.
--]]

-----------------------------------------------------------------------
--                         CONFIGURATION                             --
-----------------------------------------------------------------------

AIR_COMBAT_CFG = AIR_COMBAT_CFG or {

  red = {
    aircraft = {
      { type = "MiG-21Bis", weight = 0.40, alt_min = 3500, alt_max = 7500  },
      { type = "MiG-29A",   weight = 0.25, alt_min = 1500, alt_max = 10000 },
      { type = "Su-27",     weight = 0.25, alt_min = 1500, alt_max = 10000 },
      { type = "MiG-31",    weight = 0.10, alt_min = 8000, alt_max = 12000 },
    },
    aircraft_per_base       = 4,
    takeoff_interval_s      = 90,
    patrol_speed_kmh        = 800,
    initial_delay_min_s     = 600,     -- 10 min
    initial_delay_max_s     = 1800,    -- 30 min
    respawn_delay_min_s     = 900,     -- 15 min
    respawn_delay_max_s     = 1800,    -- 30 min
    max_airborne_per_base   = 2,
    country_id              = country.id.RUSSIA,
    afb_prefix              = "REDAFB",   -- zones trigger bases
    cap_prefix              = "REDCAP",   -- zones trigger patrouille
    group_prefix            = "REDAIR",   -- préfixe noms de groupes
    label                   = "RED",      -- pour les messages
  },

  blue = {
    aircraft = {
      { type = "F-5E-3",         weight = 0.40, alt_min = 3500, alt_max = 7500  },
      { type = "F-16C bl.52d",   weight = 0.25, alt_min = 1500, alt_max = 10000 },
      { type = "F-15C",          weight = 0.25, alt_min = 1500, alt_max = 10000 },
      { type = "F-14B",          weight = 0.10, alt_min = 8000, alt_max = 12000 },
    },
    aircraft_per_base       = 4,
    takeoff_interval_s      = 90,
    patrol_speed_kmh        = 800,
    initial_delay_min_s     = 600,
    initial_delay_max_s     = 1800,
    respawn_delay_min_s     = 900,
    respawn_delay_max_s     = 1800,
    max_airborne_per_base   = 2,
    country_id              = country.id.USA,
    afb_prefix              = "BLUEAFB",
    cap_prefix              = "BLUECAP",
    group_prefix            = "BLUEAIR",
    label                   = "BLUE",
  },
}

-----------------------------------------------------------------------
--         EMPORTS DE COMBAT (PYLONS) PAR TYPE D'APPAREIL            --
-----------------------------------------------------------------------

AIR_COMBAT_PAYLOADS = AIR_COMBAT_PAYLOADS or {

  -- ===================== RED =====================

  -- MiG-21Bis : 2×R-3R + 2×R-60M + bidon ventral
  ["MiG-21Bis"] = {
    [1] = { CLSID = "{R-3R}" },
    [2] = { CLSID = "{R-60M}" },
    [3] = { CLSID = "{PTB_490C_MIG21}" },
    [4] = { CLSID = "{R-60M}" },
    [5] = { CLSID = "{R-3R}" },
  },

  -- MiG-29A : 2×R-27R + 4×R-73 + bidon 1150L
  ["MiG-29A"] = {
    [1] = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [2] = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [3] = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [4] = { CLSID = "{2BEC576B-CDF5-4B7F-961F-A1FA99B9D789}" },  -- Bidon 1150L
    [5] = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [6] = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [7] = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
  },

  -- Su-27 : 4×R-27R + 2×R-27ER + 4×R-73
  ["Su-27"] = {
    [1]  = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [2]  = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [3]  = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [4]  = { CLSID = "{E8069896-8435-4B90-95C0-01A03AE6E400}" },  -- R-27ER
    [5]  = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [6]  = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
    [7]  = { CLSID = "{E8069896-8435-4B90-95C0-01A03AE6E400}" },  -- R-27ER
    [8]  = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [9]  = { CLSID = "{9B25D316-0434-4954-868F-D51FB7FC3AC4}" },  -- R-27R
    [10] = { CLSID = "{FBC29BFE-3D24-4C64-B81D-941239D12249}" },  -- R-73
  },

  -- MiG-31 : 4×R-33
  ["MiG-31"] = {
    [1] = { CLSID = "{F1243568-8EF0-49D4-9CB5-4DA90D92BC1D}" },
    [2] = { CLSID = "{F1243568-8EF0-49D4-9CB5-4DA90D92BC1D}" },
    [3] = { CLSID = "{F1243568-8EF0-49D4-9CB5-4DA90D92BC1D}" },
    [4] = { CLSID = "{F1243568-8EF0-49D4-9CB5-4DA90D92BC1D}" },
  },

  -- ===================== BLUE =====================

  -- F-5E-3 : 2×AIM-9P5 wingtip + bidon central 275gal
  ["F-5E-3"] = {
    [1] = { CLSID = "{AIM-9P5}" },                                   -- AIM-9P5 wingtip gauche
    [3] = { CLSID = "{0395076D-2F77-4420-9D33-087A4398130B}" },      -- Bidon 275 gal
    [5] = { CLSID = "{AIM-9P5}" },                                   -- AIM-9P5 wingtip droit
  },

  -- F-16C bl.52d : 4×AIM-120C-5 + 2×AIM-9M + 2×bidon 370gal (exactement comme fichier mission)
  ["F-16C bl.52d"] = {
    [1]  = { CLSID = "{C8E06185-7CD6-4C90-959F-044679E90751}" },    -- AIM-120C-5
    [2]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [3]  = { CLSID = "{C8E06185-7CD6-4C90-959F-044679E90751}" },    -- AIM-120C-5
    [4]  = { CLSID = "{F376DBEE-4CAE-41BA-ADD9-B2910AC95DEC}" },    -- Bidon 370 gal
    [6]  = { CLSID = "{6D21ECEA-F85B-4E8D-9D51-31DC9B8AA4EF}" },    -- AIM-120C-7
    [7]  = { CLSID = "{F376DBEE-4CAE-41BA-ADD9-B2910AC95DEC}" },    -- Bidon 370 gal
    [8]  = { CLSID = "{C8E06185-7CD6-4C90-959F-044679E90751}" },    -- AIM-120C-5
    [9]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [10] = { CLSID = "{C8E06185-7CD6-4C90-959F-044679E90751}" },    -- AIM-120C-5
  },

  -- F-15C : 4×AIM-120C + 4×AIM-9M
  ["F-15C"] = {
    [1]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [2]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [3]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [4]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [5]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [6]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [7]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [8]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [9]  = { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}" },    -- AIM-120C
    [10] = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
  },

  -- F-14B : 4×AIM-54C Phoenix + 2×AIM-9M + bidon ventral
  ["F-14B"] = {
    [1]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
    [2]  = { CLSID = "{SHOULDER AIM_54C_Mk47}" },                    -- AIM-54C
    [3]  = { CLSID = "{BELLY AIM_54C_Mk47}" },                       -- AIM-54C
    [4]  = { CLSID = "{BELLY AIM_54C_Mk47}" },                       -- AIM-54C
    [5]  = { CLSID = "{F14-300gal}" },                                -- Bidon 267 gal
    [6]  = { CLSID = "{BELLY AIM_54C_Mk47}" },                       -- AIM-54C
    [7]  = { CLSID = "{BELLY AIM_54C_Mk47}" },                       -- AIM-54C
    [8]  = { CLSID = "{SHOULDER AIM_54C_Mk47}" },                    -- AIM-54C
    [9]  = { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}" },    -- AIM-9M
  },
}

-----------------------------------------------------------------------
--                              ÉTAT                                 --
-----------------------------------------------------------------------

AIR_COMBAT_STATE = AIR_COMBAT_STATE or {
  sides = {
    red  = { bases = {}, flights = {}, spawn_schedule = {}, cap_zones = {}, initialized = false },
    blue = { bases = {}, flights = {}, spawn_schedule = {}, cap_zones = {}, initialized = false },
  },
}

_airSeqId = _airSeqId or 0

-----------------------------------------------------------------------
--           FONCTIONS GÉNÉRIQUES (paramétrées par camp)             --
-----------------------------------------------------------------------

-- Détecte les zones trigger qui matchent un préfixe (ex: "REDAFB", "BLUEAFB")
function _airFindZonesByPrefix(prefix)
  local zonesTable = env and env.mission and env.mission.triggers and env.mission.triggers.zones
  if not zonesTable then return {} end

  local found = {}
  local pat = "^" .. prefix .. "$"
  local patN = "^" .. prefix .. "_%d+$"

  for _, zinfo in ipairs(zonesTable) do
    local nm = tostring(zinfo.name or "")
    if nm:match(pat) or nm:match(patN) then
      local cx, cz, radius
      local verts = zinfo.verticies or zinfo.vertices or zinfo.points
      if verts and #verts >= 3 then
        local sx, sz = 0, 0
        for _, p in ipairs(verts) do
          local px = p.x or p[1] or 0
          local pz = (p.z ~= nil) and p.z or (p.y or p[2] or 0)
          sx = sx + px; sz = sz + pz
        end
        cx = sx / #verts; cz = sz / #verts
        radius = 0
        for _, p in ipairs(verts) do
          local px = p.x or p[1] or 0
          local pz = (p.z ~= nil) and p.z or (p.y or p[2] or 0)
          local d = math.sqrt((px-cx)^2 + (pz-cz)^2)
          if d > radius then radius = d end
        end
      else
        cx = zinfo.x or 0
        cz = zinfo.z or zinfo.y or 0
        radius = zinfo.radius or 5000
      end
      found[#found+1] = { zoneName = nm, cx = cx, cz = cz, radius = radius or 5000 }
    end
  end

  -- Tri par numéro si présent
  table.sort(found, function(a, b)
    local na = tonumber(a.zoneName:match("(%d+)$")) or 0
    local nb = tonumber(b.zoneName:match("(%d+)$")) or 0
    return na < nb
  end)

  return found
end

-- Trouve l'aérodrome DCS le plus proche du centre d'une zone
function _airFindAirbaseInZone(zoneInfo)
  local allBases = world.getAirbases() or {}
  local bestBase, bestDist = nil, math.huge
  for _, ab in ipairs(allBases) do
    if ab and ab.getPoint and ab.getName then
      local okP, p = pcall(ab.getPoint, ab)
      if okP and p then
        local d = math.sqrt((p.x - zoneInfo.cx)^2 + (p.z - zoneInfo.cz)^2)
        if d <= zoneInfo.radius and d < bestDist then
          bestDist = d; bestBase = ab
        end
      end
    end
  end
  return bestBase
end

-- Choisit la zone CAP la moins couverte pour un camp donné
function _airPickCAPZone(sideState)
  local zones = sideState.cap_zones
  if not zones or #zones == 0 then return nil, nil end

  local count = {}
  for i = 1, #zones do count[i] = 0 end
  for _, fState in pairs(sideState.flights) do
    if fState.status == "airborne" and fState.cap_idx then
      if count[fState.cap_idx] then
        count[fState.cap_idx] = count[fState.cap_idx] + 1
      end
    end
  end

  local bestIdx, bestCount = 1, count[1] or 0
  for i = 2, #zones do
    if (count[i] or 0) < bestCount then
      bestCount = count[i] or 0; bestIdx = i
    end
  end
  return bestIdx, zones[bestIdx]
end

-- Spawn un chasseur en vol pour le camp donné
function _airSpawnOne(sideKey, sideState, cfg, baseInfo, baseIdx)
  local ctryId = cfg.country_id or country.id.RUSSIA

  -- Double lancé de dés (2×d500) pour sélection du type
  local dice = math.random(1, 500) + math.random(1, 500)
  local acType  = cfg.aircraft[1] and cfg.aircraft[1].type or "MiG-29A"
  local altMin  = 3000
  local altMax  = 8000
  if cfg.aircraft and #cfg.aircraft > 0 then
    local total = 0
    for _, e in ipairs(cfg.aircraft) do total = total + (e.weight or 1) end
    local threshold = (dice / 1000) * total
    local acc = 0
    for _, e in ipairs(cfg.aircraft) do
      acc = acc + (e.weight or 1)
      if threshold <= acc then
        acType = e.type; altMin = e.alt_min or 3000; altMax = e.alt_max or 8000
        break
      end
    end
  end

  _airSeqId = _airSeqId + 1
  local gname = (cfg.group_prefix or "AIR") .. "_" .. _airSeqId
  local uname = gname .. "_U1"

  local alt   = altMin + math.random() * (altMax - altMin)
  alt = math.floor(alt / 100) * 100
  local speed = (cfg.patrol_speed_kmh or 800) / 3.6
  local spawnX = baseInfo.x
  local spawnZ = baseInfo.z

  -- Zone CAP la moins couverte
  local capIdx, capZone = _airPickCAPZone(sideState)
  local destX, destZ
  if capZone then
    destX = capZone.cx; destZ = capZone.cz
  else
    destX = spawnX + 20000; destZ = spawnZ
  end

  local dx = destX - spawnX
  local dz = destZ - spawnZ
  local hdg = math.atan2(dx, dz)
  if hdg < 0 then hdg = hdg + 2 * math.pi end

  -- Skill aléatoire
  local skills = { "Average", "Good", "High", "Excellent" }
  local skill  = skills[math.random(1, #skills)]

  -- Pylons : format indexé comme dans le fichier mission
  local pylons = AIR_COMBAT_PAYLOADS[acType]
  local pylonData = {}
  if pylons then
    for pIdx, pInfo in pairs(pylons) do
      pylonData[pIdx] = { CLSID = pInfo.CLSID }
    end
  end

  -- Construction du WP1 tasks : EngageTargets CAP + Options via WrappedAction
  -- Reproduit fidèlement la structure d'un groupe CAP DCS (fichier mission)
  local wp1Tasks = {
    [1] = {
      enabled = true, key = "CAP", id = "EngageTargets",
      number = 1, auto = true,
      params = { targetTypes = { "Air" }, priority = 0 },
    },
    [2] = {
      enabled = true, auto = true, id = "WrappedAction", number = 2,
      params = { action = { id = "Option", params = { value = true, name = 17 } } },  -- PROHIBIT_JETT
    },
    [3] = {
      enabled = true, auto = true, id = "WrappedAction", number = 3,
      params = { action = { id = "Option", params = { value = 4, name = 18 } } },     -- RADAR_USING = FOR_CONTINUOUS_SEARCH
    },
    [4] = {
      enabled = true, auto = true, id = "WrappedAction", number = 4,
      params = { action = { id = "Option", params = { value = true, name = 19 } } },  -- PROHIBIT_AA (false=engage)
    },
    [5] = {
      enabled = true, auto = true, id = "WrappedAction", number = 5,
      params = { action = { id = "Option", params = {
        name = 21, value = "none;",
        targetTypes = {},
        noTargetTypes = {
          "Fighters", "Multirole fighters", "Bombers", "Helicopters", "UAVs",
          "Infantry", "Fortifications", "Tanks", "IFV", "APC", "Artillery",
          "Unarmed vehicles", "AAA", "SR SAM", "MR SAM", "LR SAM",
          "Aircraft Carriers", "Cruisers", "Destroyers", "Frigates", "Corvettes",
          "Light armed ships", "Unarmed ships", "Submarines",
          "Cruise missiles", "Antiship Missiles", "AA Missiles", "AG Missiles", "SA Missiles",
        },
      } } },
    },
    [6] = {
      enabled = true, auto = true, id = "WrappedAction", number = 6,
      params = { action = { id = "EPLRS", params = { value = true, groupId = 1 } } },
    },
    [7] = {
      enabled = true, auto = true, id = "WrappedAction", number = 7,
      params = { action = { id = "Option", params = { value = true, name = 35 } } },
    },
    [8] = {
      enabled = true, auto = false, id = "WrappedAction", number = 8,
      params = { action = { id = "Option", params = { value = 3, name = 3 } } },      -- REACTION_ON_THREAT = EVADE_FIRE (3)
    },
  }

  local groupData = {
    name           = gname,
    visible        = true,
    lateActivation = false,
    uncontrolled   = false,
    task           = "CAP",          -- MISSION DU GROUPE = CAP
    communication  = true,
    frequency      = 251,
    modulation     = 0,
    tasks          = {},
    route = {
      points = {
        [1] = {
          type = "Turning Point", action = "Turning Point",
          x = spawnX, y = spawnZ,
          alt = alt, alt_type = "BARO",
          speed = speed, speed_locked = true,
          ETA = 0, ETA_locked = true,
          formation_template = "",
          task = { id = "ComboTask", params = { tasks = wp1Tasks } },
        },
        [2] = {
          type = "Turning Point", action = "Turning Point",
          x = destX, y = destZ,
          alt = alt, alt_type = "BARO",
          speed = speed, speed_locked = true,
          ETA_locked = false,
          formation_template = "",
          task = {
            id = "ComboTask",
            params = {
              tasks = {
                [1] = {
                  enabled = true, auto = false, id = "Orbit", number = 1,
                  params = { altitude = alt, pattern = "Circle", speed = speed },
                },
              },
            },
          },
        },
      },
    },
    units = {
      [1] = {
        type = acType, name = uname,
        x = spawnX, y = spawnZ,
        alt = alt, alt_type = "BARO",
        speed = speed, heading = hdg,
        skill = skill,
        payload = {
          pylons = pylonData,
          fuel   = "3104",
          flare  = 45,
          chaff  = 90,
          gun    = 100,
        },
      },
    },
  }

  local ok, err = pcall(coalition.addGroup, ctryId, Group.Category.AIRPLANE, groupData)
  if not ok then
    trigger.action.outText(string.format("[AIR %s] Erreur spawn %s : %s", cfg.label or "?", acType, tostring(err)), 15)
    return nil
  end

  -- Les options de combat sont intégrées dans la route (WrappedAction/Option)
  -- comme dans un fichier mission DCS natif — pas besoin de setOption post-spawn

  local capName = capZone and capZone.zoneName or "FALLBACK"
  trigger.action.outText(string.format(
    "[AIR %s] %s (%s) → %s alt %dm [%s]",
    cfg.label or "?", gname, acType, capName, alt, skill
  ), 15)

  sideState.flights[gname] = {
    base_idx   = baseIdx,
    acType     = acType,
    status     = "airborne",
    spawn_time = timer.getTime(),
    cap_idx    = capIdx,
  }

  return gname
end

-----------------------------------------------------------------------
--               TICK GÉNÉRIQUE (un par camp)                        --
-----------------------------------------------------------------------

function _airMakeTick(sideKey)
  local cfg       = AIR_COMBAT_CFG[sideKey]
  local sideState = AIR_COMBAT_STATE.sides[sideKey]
  if not cfg or not sideState then return nil end

  return function()
    local now = timer.getTime()

    local interval    = cfg.takeoff_interval_s or 90
    local maxPerBase  = cfg.aircraft_per_base or 4
    local maxAirborne = cfg.max_airborne_per_base or 2

    -- 1) SPAWN ÉCHELONNÉ
    for baseIdx, sched in pairs(sideState.spawn_schedule) do
      local airborne = 0
      for _, fState in pairs(sideState.flights) do
        if fState.base_idx == baseIdx and fState.status == "airborne" then
          airborne = airborne + 1
        end
      end
      if airborne < maxAirborne and sched.total_spawned < maxPerBase then
        if now >= sched.next_spawn_t then
          local baseInfo = sideState.bases[baseIdx]
          if baseInfo then
            local gname = _airSpawnOne(sideKey, sideState, cfg, baseInfo, baseIdx)
            if gname then
              sched.total_spawned = sched.total_spawned + 1
              sched.next_spawn_t  = now + interval
            else
              sched.next_spawn_t = now + 30
            end
          end
        end
      end
    end

    -- 2) SURVEILLANCE
    local toRemove = {}
    for gname, fState in pairs(sideState.flights) do
      if fState.status == "airborne" then
        local grp = Group.getByName(gname)
        local alive = false
        if grp and Group.isExist(grp) then
          local units = grp:getUnits()
          if units then
            for _, u in ipairs(units) do
              if u and Unit.isExist(u) and (u:getLife() or 0) > 1 then
                alive = true; break
              end
            end
          end
        end
        if not alive then
          fState.status = "dead"; fState.death_time = now
        end
      end
    end

    -- 3) RESPAWN (délai aléatoire)
    for gname, fState in pairs(sideState.flights) do
      if fState.status == "dead" and fState.death_time then
        if not fState.respawn_at then
          local rMin = cfg.respawn_delay_min_s or 900
          local rMax = cfg.respawn_delay_max_s or 1800
          fState.respawn_at = fState.death_time + rMin + math.random() * (rMax - rMin)
        end
        if now >= fState.respawn_at then
          toRemove[#toRemove+1] = gname
          local sched = sideState.spawn_schedule[fState.base_idx]
          if sched then
            sched.total_spawned = math.max(0, sched.total_spawned - 1)
          end
        end
      end
    end
    for _, gname in ipairs(toRemove) do
      sideState.flights[gname] = nil
    end

    return now + 10
  end
end

-----------------------------------------------------------------------
--           INITIALISATION GÉNÉRIQUE (appelée par camp)             --
-----------------------------------------------------------------------

function _airInitSide(sideKey)
  local cfg       = AIR_COMBAT_CFG[sideKey]
  local sideState = AIR_COMBAT_STATE.sides[sideKey]
  if not cfg or not sideState then return end
  if sideState.initialized then return end

  local label     = cfg.label or sideKey:upper()
  local afbPrefix = cfg.afb_prefix or (sideKey:upper() .. "AFB")
  local capPrefix = cfg.cap_prefix or (sideKey:upper() .. "CAP")

  -- Détecte les zones AFB
  local afbZones = _airFindZonesByPrefix(afbPrefix)
  if #afbZones == 0 then
    trigger.action.outText(string.format("[AIR %s] Aucune zone %s. Module OFF.", label, afbPrefix), 10)
    return
  end

  -- Détecte les zones CAP
  sideState.cap_zones = _airFindZonesByPrefix(capPrefix)
  local nbCap = #sideState.cap_zones
  if nbCap > 0 then
    local names = {}
    for _, z in ipairs(sideState.cap_zones) do names[#names+1] = z.zoneName end
    trigger.action.outText(string.format(
      "[AIR %s] %d zone(s) CAP : %s", label, nbCap, table.concat(names, ", ")
    ), 15)
  else
    trigger.action.outText(string.format("[AIR %s] Aucune zone %s_## — fallback 20km.", label, capPrefix), 10)
  end

  -- Détecte les airbases
  for _, zInfo in ipairs(afbZones) do
    local airbase = _airFindAirbaseInZone(zInfo)
    if airbase then
      local p      = airbase:getPoint()
      local abName = airbase:getName()

      local baseIdx = #sideState.bases + 1
      sideState.bases[baseIdx] = {
        name = abName, x = p.x, z = p.z, zoneName = zInfo.zoneName,
      }

      local delayMin = cfg.initial_delay_min_s or 600
      local delayMax = cfg.initial_delay_max_s or 1800
      sideState.spawn_schedule[baseIdx] = {
        total_spawned = 0,
        next_spawn_t  = timer.getTime() + delayMin + math.random() * (delayMax - delayMin),
      }

      trigger.action.outText(string.format(
        "[AIR %s] Base : %s — 1ère vague %d–%d min.",
        label, abName, math.floor(delayMin / 60), math.floor(delayMax / 60)
      ), 15)
    end
  end

  if #sideState.bases == 0 then return end

  -- Lance le tick
  timer.scheduleFunction(_airMakeTick(sideKey), {}, timer.getTime() + 30)

  sideState.initialized = true

  trigger.action.outText(string.format(
    "[AIR %s] Module init : %d base(s), %d av/base, %d zone(s) CAP. Vague %d–%d min, respawn %d–%d min.",
    label,
    #sideState.bases,
    cfg.aircraft_per_base or 4,
    nbCap,
    math.floor((cfg.initial_delay_min_s or 600) / 60),
    math.floor((cfg.initial_delay_max_s or 1800) / 60),
    math.floor((cfg.respawn_delay_min_s or 900) / 60),
    math.floor((cfg.respawn_delay_max_s or 1800) / 60)
  ), 20)
end

-----------------------------------------------------------------------
--                    POINT D'ENTRÉE PRINCIPAL                       --
-----------------------------------------------------------------------

function AIR_COMBAT_Init()
  _airInitSide("red")
  _airInitSide("blue")
end

-- ===== RUN =====
initAreas()

-- Détection éventuelle du mode "BATTLEFIELD_M"
BATTLEFIELD_DetectManualMode()

-- Détection éventuelle du mode manuel LOGI (LOGIBLUE_M / LOGIRED_M)
LOGI_DetectManualMode()

-- Traitement des zones automatiques
for _, cfg in ipairs(ZONES_CFG) do
  -- En mode manuel BATTLEFIELD, on NE génère PAS de PRIORITY auto pour la zone "BATTLEFIELD"
  if BATTLEFIELD_MANUAL and cfg.name == "BATTLEFIELD" then
    -- skip
  -- En mode manuel LOGI BLUE, on NE génère PAS de LOGI auto pour LOGIBLUE
  elseif LOGI_MANUAL_BLUE and cfg.name == "LOGIBLUE" then
    -- skip
  -- En mode manuel LOGI RED, on NE génère PAS de LOGI auto pour LOGIRED
  elseif LOGI_MANUAL_RED and cfg.name == "LOGIRED" then
    -- skip
  else
    run_zone(cfg)
  end
end

-- En mode manuel BATTLEFIELD, on construit les PRIORITY à partir des zones numérotées
if BATTLEFIELD_MANUAL then
  BATTLEFIELD_BuildManualPoints()
end

-- En mode manuel LOGI, on construit les LOGI à partir des zones B# et R#
if LOGI_MANUAL_BLUE then
  LOGI_BuildManualBluePoints()
end
if LOGI_MANUAL_RED then
  LOGI_BuildManualRedPoints()
end

compute_caps()

-- init des anneaux PRIORITY une fois les points posés + numéros dessinés
timer.scheduleFunction(function()
  PRIO_RecomputeSectorNumbers()
  PRIO_Rings_InitAndPoll()
  
  -- Initialise l'economie APRES les PRIORITY et avant DrawPriorityNumbers
  ECON_Init()
  
  DrawPriorityNumbers()
  DrawZoneTriggerFrames()
  
  -- Cree les menus F10 economie
  ECON_InitMenus()
  
  -- Demarre le tick economique
  timer.scheduleFunction(ECON_Tick, {}, timer.getTime() + 60)
end, {}, timer.getTime() + 1)





-- T0
local t0=timer.getTime()

-- 1) Tracer les anneaux LOGI (coalition-only) juste après sélection des LOGI
timer.scheduleFunction(function() DrawAllLogiRings() end, {}, t0+4)

-- 2) Pre-clear (trees/buildings) 5s après, puis spawn à +10s
timer.scheduleFunction(function() preClearSceneryAroundLOGI(LOGI_PRECLEAR_RADIUS) end, {}, t0+5)
timer.scheduleFunction(function()
  placeLOGITemplateOnMarkers({
    baseHeadingBlueDeg = DEFEND_BEARINGS.blue_to_red_deg or 0,
    baseHeadingRedDeg  = DEFEND_BEARINGS.red_to_blue_deg or 0,
  })
  spawnDefendersOnMarkers()
  spawnADAroundLOGI()
  spawnLOGFARPAroundLOGI()
  if AUTO_CONQUEST and AUTO_CONQUEST.Init then AUTO_CONQUEST.Init() end
  -- Initialise le module aérien RED + BLUE (REDAFB/BLUEAFB + REDCAP/BLUECAP)
  if AIR_COMBAT_Init then AIR_COMBAT_Init() end
end, {}, t0+10)



timer.scheduleFunction(LOGI_FARP_ScanAndDispatch, {}, t0 + 20)

timer.scheduleFunction(LOGI_FARP_UpdateAndBuild, {}, t0 + 22)

-- 3) Spawn des camps dépôt BLUESTORE / REDSTORE à +60 s
timer.scheduleFunction(spawnStoreCamps, {}, t0 + 60)

-- 4) Scan des hélicos posés sur les camps dépôt (menus Battlefield / Embarquement)
timer.scheduleFunction(STORE_CheckEmbarkCandidates, {}, t0 + 65)

-- 5) Menus "Battlefield / Secteurs" pour tous les joueurs
timer.scheduleFunction(BF_MenuScanPlayers, {}, t0 + 20)


-----------------------------------------------------------------
-- PRIO – "LOCK" tracking (zone capturée avec runner immobile) --
----------------------------------------------------------------
PRIO_ZONE_LOCKED = PRIO_ZONE_LOCKED or { BLUE = {}, RED = {} }

-- Track interne (immobilité continue avant lock)
local _LOCK_TRACK = _LOCK_TRACK or { BLUE = {}, RED = {} }

-- Seuils (réutilise ceux du runner si présents)
local _LOCK_IDLE_MS   = (AUTO_CONQUEST_CFG and AUTO_CONQUEST_CFG.runner and AUTO_CONQUEST_CFG.runner.idle_speed_threshold_ms) or 1.0
local _LOCK_IDLE_NEED = (AUTO_CONQUEST_CFG and AUTO_CONQUEST_CFG.runner and AUTO_CONQUEST_CFG.runner.idle_required_s) or 10

-- Utilitaires
local function _d2(a,b) local dx=a.x-b.x local dz=a.z-b.z return math.sqrt(dx*dx+dz*dz) end
local function _vec3g(v2) return { x=v2.x, y=land.getHeight({x=v2.x, y=v2.z}), z=v2.z } end

-- Renvoie "BLUE"/"RED"/nil depuis PRIO_RING_STATE[i].colorKey (déjà géré par ton moteur)
local function _ownerKey(i)
  local s = PRIO_RING_STATE and PRIO_RING_STATE[i] and PRIO_RING_STATE[i].colorKey or "GREEN"
  if s == "BLUE" then return "BLUE" end
  if s == "RED"  then return "RED"  end
  return nil
end

-- Scanner indépendant qui met PRIO_ZONE_LOCKED[coal][idx]=true si une unité de la coalition est immobile dans le cercle ≥ _LOCK_IDLE_NEED
local function PRIO_LockScan_Tick()
  if not BATTLEFIELD_POINTS or #BATTLEFIELD_POINTS==0 then
    return timer.getTime()+2
  end
  local R = PRIO_RADIUS or 1000
  for i,pt in ipairs(BATTLEFIELD_POINTS) do
    local owner = _ownerKey(i)
    if owner then
      local center3 = _vec3g(pt)
      local hasImmobile = false
      world.searchObjects(Object.Category.UNIT, {
        id = world.VolumeType.SPHERE,
        params = { point = center3, radius = R }
      }, function(u)
        if u and Unit.isExist(u) and (u:getLife() or 0) > 1 and u.getCoalition then
          local side = u:getCoalition()
          if (owner=="BLUE" and side==coalition.side.BLUE) or (owner=="RED" and side==coalition.side.RED) then
            local v = u:getVelocity() or {x=0,y=0,z=0}
            local spd = math.sqrt((v.x or 0)^2 + (v.y or 0)^2 + (v.z or 0)^2)
            if spd <= _LOCK_IDLE_MS then hasImmobile = true; return false end
          end
        end
        return true
      end)
      local tr = _LOCK_TRACK[owner][i] or { since=nil, locked=false }
      if hasImmobile then
        tr.since = tr.since or timer.getTime()
        if (not tr.locked) and (timer.getTime() - tr.since >= _LOCK_IDLE_NEED) then
          tr.locked = true
          PRIO_ZONE_LOCKED[owner][i] = true
          if _G.AUTO_CONQUEST and AUTO_CONQUEST.OnZoneLocked then
            AUTO_CONQUEST.OnZoneLocked(i, owner)
          end
        end
      else
        tr.since = nil
      end
      _LOCK_TRACK[owner][i] = tr
    end
  end
  return timer.getTime()+3  -- scan toutes les 3 s
end
timer.scheduleFunction(PRIO_LockScan_Tick, {}, timer.getTime()+3)



-----------------------------------------------------------------------
--                   AUTO_CONQUEST — module complet                   --
-----------------------------------------------------------------------
--[[
  SYSTÈME DE CONQUÊTE AUTOMATIQUE (IA)
  
  Ce module gère l'ensemble des unités IA qui participent à la conquête
  du champ de bataille. Chaque camp dispose de plusieurs types d'unités
  avec des rôles spécifiques :
  
  TYPES D'UNITÉS :
  ================
  
  CONTROLE (APC/IFV) - Capture les zones NEUTRES
  - Bradley, LAV-25, BMP-2... (véhicules blindés légers/moyens)
  - Se déplace vers les secteurs non contrôlés
  - Envoie un RUNNER une fois arrivé pour capturer
  
  ASSAULT (MBT) - Attaque les zones ENNEMIES
  - Abrams, Leopard, T-72, T-80... (chars de bataille)
  - Cible les secteurs contrôlés par l'ennemi
  - Plus agressif, cherche le combat
  
  RECO (véhicules légers) - Reconnaissance
  - HMMWV, BRDM-2... (véhicules rapides)
  - Explore vers les positions ennemies
  - Escorté par un groupe ASSAULT
  
  COUNTER (MBT rapides) - Interception
  - Réagit aux assauts ennemis
  - Protège les secteurs récemment capturés
  
  RUNNER (transport) - Capture effective
  - HMMWV, Ural... (véhicules rapides non armés)
  - Envoyé par CONTROLE/ASSAULT pour "verrouiller" un secteur
  - Doit rester immobile X secondes pour capturer
  
  DA (Défense Aérienne) - Protection AA fixe
  - Avenger, Vulcan, Strela, Shilka...
  - Déployé sur les premiers objectifs
  
  DA_ASSAULT / DA_CONTROLE - Escorte AA mobile
  - Accompagne les groupes offensifs
  - Se positionne en retrait pour couvrir
  
  ARTY (Artillerie) - Appui feu indirect
  - M-109, Msta... (canons automoteurs)
  - Fait la navette entre positions
  - Tire sur les secteurs ennemis à portée
  
  COMMANDER - Unité de commandement
  - 1 par LOGI, ne respawn pas
  - Si détruit, bloque les opérations de ce LOGI
--]]

AUTO_CONQUEST = AUTO_CONQUEST or {}

-----------------------------------------------------------------------
--                       CONFIG GLOBALE                              --
-----------------------------------------------------------------------
--[[
  Configuration complète de l'IA de conquête.
  Modifiez ces valeurs pour ajuster la difficulté et le comportement.
--]]

-- Timestamps de démarrage différé (remplis dans Init)
local AUTO_CONQUEST_START = {
  reco     = 0,
  controle = 0,
  assault  = 0,
  da       = 0,
  arty     = 0,
}


AUTO_CONQUEST_CFG = AUTO_CONQUEST_CFG or {
  
  -- === CONTROLE : Capture des zones neutres ===
  controle = {
    speed_kmh = 45,
    blue = {
      count   = 4,
      -- 50% M2 Bradley, 50% LAV-25 (peloton homogène)
      platoons = {
        { types = { "M-2 Bradley" }, weight = 0.5 },
        { types = { "LAV-25"      }, weight = 0.3 },
		{ types = { "M-113"      }, weight = 0.2 },
      },
      skill = "Random",
    },
    red  = {
      count   = 5,
      -- 50% BMP-3, 50% BMP-2 (peloton homogène)
      platoons = {
        { types = { "BMP-1" }, weight = 0.3 },
        { types = { "BMP-2" }, weight = 0.5 },
		{ types = { "BTR-80" }, weight = 0.2 },
      },
      skill = "Random",
    },
    initial_choices = 3,
  },

  -- Peloton ASSAULT : ENEMY-ONLY (avec répartition inter-LOGI)
   -- Peloton ASSAULT : ENEMY-ONLY (avec répartition inter-LOGI)
     -- Peloton ASSAULT : ENEMY / NEUTRAL, ne s’intéresse qu’aux secteurs non-amis
  assault = {
    speed_kmh = 40,

    -- Anti-camping / anti-blocage :
    idle_reset_s        = 45,  -- temps max à camper sur un objectif (dans la zone, immobile) avant de changer de secteur
    global_idle_reset_s = 90,  -- temps global immobile (où qu’il soit) avant reset complet de l’ASSAULT

    blue = {
      count   = 3,
      platoons = {
        -- 35% M-60
        { types = { "M-60"           }, weight = 0.35 },
        -- 35% Chieftain_mk3
        { types = { "Leopard1A3"  }, weight = 0.35 },
        -- 30% M1A2C_SEP_V3
        { types = { "leopard-2A4"   }, weight = 0.30 },
      },
      skill = "Random",
    },

    red  = {
      count   = 5,
      platoons = {
        -- 35% T-55
        { types = { "T-72B"     }, weight = 0.35 },
        -- 35% T-80UD
        { types = { "T-80UD"   }, weight = 0.35 },
        -- 30% CHAP_T90M
        { types = { "T-80B"}, weight = 0.30 },
      },
      skill = "Random",
    },

    initial_choices = 3,
  },



  -- Peloton COUNTER : intercepter/détruire un ASSAULT ennemi ; ne capture pas
  counter = {
    speed_kmh = 55,
    blue = { count = 4, types = { "M-1 Abrams" },  skill = "Random" },
    red  = { count = 4, types = { "T-72B" },       skill = "Random" },
    idle_speed_threshold_ms = 1.0,
    idle_required_s         = 10,
    recheck_s               = 5,
    runner_threat_radius_m  = 800,
    recent_ownership_s      = 300,
  },

  -- Runners (véhicule de capture)
  runner = {
    speed_kmh = 100,
    blue_type = "M1043 HMMWV Armament",
    red_type  = "Ural-375 PBU",
    idle_speed_threshold_ms = 1.0,
    idle_required_s         = 10,
    wait_timeout_s          = 240,

    -- Manpads largués une fois la zone tenue
    blue_manpad_type = "Soldier stinger",
    red_manpad_type  = "SA-18 Igla manpad",
  },
  
    -- Groupes RECO (léger, mobilité élevée)
  reco = {
    speed_kmh  = 50,
    respawn_s  = 900,  -- délai de respawn par défaut (15 min)
    blue = {
      -- 2 HMMWV cal .50 + 1 LAV-25
      units = {
        "M1043 HMMWV Armament",
        "M1043 HMMWV Armament",
        "LAV-25",
      },
      skill = "Random",
    },
    red  = {
      -- 2 BRDM-2 + 1 BTR-80
      units = {
        "BRDM-2",
        "BRDM-2",
        "BTR-80",
      },
      skill = "Random",
    },
  },


  -- Défense AA “fixe” sur premiers objectifs
  da = {
    speed_kmh = 35,
    blue = { groups = {
      { count = 1, type = "M1097 Avenger" },
      { count = 1, type = "Vulcan" },
      { count = 1, type = "Vulcan" },
    }},
    red  = { groups = {
      { count = 1, type = "Strela-10M3" },
      { count = 1, type = "ZSU-23-4 Shilka" },
      { count = 1, type = "ZSU-23-4 Shilka" },
    }},
    skill = "Random",
  },

  -- DA_Assault : escorte des groupes ASSAULT
  da_assault = {
    speed_kmh       = 35,
    delay_s         = 60,   -- démarre 60 s après ASSAULT
    back_m          = 500,  -- WP 500 m plus proche du LOGI que celui d’ASSAULT
    spawn_offset_m  = 20,   -- spawn 20 m derrière ASSAULT
    skill           = "Random",

    blue = {
      -- 30% Vulcan, 70% Avenger
      types = {
        { type = "Vulcan",          weight = 0.3 },
        { type = "M1097 Avenger",   weight = 0.7 },
      }
    },
    red = {
      -- 30% Shilka, 70% Strela-10M3
      types = {
        { type = "ZSU-23-4 Shilka", weight = 0.3 },
        { type = "Strela-10M3",     weight = 0.6 },
		{ type = "Osa 9A33 ln",     weight = 0.1 },
      }
    },
  },

  -- DA_Controle : escorte des groupes CONTROLE
  da_controle = {
    speed_kmh       = 35,
    delay_s         = 60,
    back_m          = 500,
    spawn_offset_m  = 20,
    skill           = "Random",

    blue = {
      types = {
        { type = "Vulcan",          weight = 0.3 },
        { type = "M1097 Avenger",   weight = 0.7 },
      }
    },
    red = {
      types = {
        { type = "ZSU-23-4 Shilka", weight = 0.8 },
        { type = "Strela-10M3",     weight = 0.2 },
      }
    },
  },

  -- Artillerie
  arty = {
    speed_kmh       = 20,
    max_range_m     = 30000,
    fire_minutes    = 4,
    dispersion_m    = 500,
    check_every_s   = 2.5,
    skill           = "Excellent",
    blue = { tubes = 2, tube_type = "M-109",    truck_type = "M978 HEMTT Tanker" },
    red  = { tubes = 2, tube_type = "SAU Msta", truck_type = "Ural-375" },
  },

  respawn_seconds = 300,
  farp_build_seconds = 60,
}

-----------------------------------------------------------------------
--                       UTILITAIRES GLOBALES                        --
-----------------------------------------------------------------------
function _kmh2ms(v) return (v or 0)/3.6 end
function _vec3g(v2) return { x=v2.x, y=land.getHeight({x=v2.x, y=v2.z}), z=v2.z } end
function _d2(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx + dz*dz) end
function _norm(dx,dz)
  local L = math.sqrt(dx*dx+dz*dz)
  if L < 1e-6 then return 1,0,1e-6 end
  return dx/L, dz/L, L
end
function _sideKey(side) return (side==coalition.side.BLUE) and "BLUE" or "RED" end
function _country(side) return (side==coalition.side.BLUE) and country.id.USA or country.id.RUSSIA end

-- RNG


local RNGi = (RNG and RNG.randomInt) or function(a,b) return a + math.floor(math.random()*(b-a+1)) end
local RNGf = (RNG and RNG.random)    or function() return math.random() end

local function _shuffle(t)
  if RNG and RNG.shuffle then return RNG.shuffle(t) end
  for i=#t,2,-1 do
    local j = RNGi(1,i)
    t[i],t[j] = t[j],t[i]
  end
end

-- Compétences
local _skills = {"Average","Good","High","Excellent"}
local function _pickSkill(spec)
  if type(spec)=="string" then
    if spec=="Random" then return _skills[RNGi(1,#_skills)] end
    return spec
  elseif type(spec)=="table" then
    return spec[RNGi(1,#spec)]
  end
  return "High"
end

-- Weighted type pick (DA & contrôle)
local function _pickWeightedType(desc)
  if not desc or #desc==0 then return nil end
  local total = 0
  for _,e in ipairs(desc) do total = total + (e.weight or 1) end
  if total <= 0 then return desc[1].type end
  local r = RNGf()*total
  local acc = 0
  for _,e in ipairs(desc) do
    acc = acc + (e.weight or 1)
    if r <= acc then return e.type end
  end
  return desc[#desc].type
end

-- Group helpers
local function _groupAlive(gname)
  local g = Group.getByName(gname)
  if not g or not Group.isExist(g) then return false end
  local us = g:getUnits()
  if not us or #us == 0 then return false end
  for _,u in ipairs(us) do
    if u and Unit.isExist(u) and (u:getLife() or 0) > 0 then
      return true
    end
  end
  return false
end

local function _leaderPoint(gname)
  local g = Group.getByName(gname)
  if not g then return nil end
  local us = g:getUnits()
  if not us or not us[1] or not Unit.isExist(us[1]) then return nil end
  local p = us[1]:getPoint()
  return { x=p.x, z=p.z }
end

local function _leaderSpeedMS(gname)
  local g = Group.getByName(gname)
  if not g then return 0 end
  local us = g:getUnits()
  if not us or not us[1] or not Unit.isExist(us[1]) then return 0 end
  local v = us[1]:getVelocity() or {x=0,y=0,z=0}
  return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

PRIO_RADIUS      = PRIO_RADIUS or 1000
PRIO_RING_STATE  = PRIO_RING_STATE or {}
PRIO_ZONE_LOCKED = PRIO_ZONE_LOCKED or { BLUE={}, RED={} }

-- LOGI / DEFENSE
local function _nearestLogi(side, pt)
  local list = (side==coalition.side.BLUE) and (LOGI_BLUE_POINTS or {}) or (LOGI_RED_POINTS or {})
  local best,bd = nil, 1e9
  for _,p in ipairs(list) do
    local d = _d2(pt, p)
    if d < bd then bd = d; best = p end
  end
  return best or {x=pt.x, z=pt.z}
end

local function _randomDefensePoint(side)
  local list = (side==coalition.side.BLUE) and (BLUELINE_POINTS or {}) or (REDLINE_POINTS or {})
  if not list or #list == 0 then return nil end
  local i = RNGi(1,#list)
  return { x=list[i].x, z=list[i].z }
end

-- Point d’attaque sur le cercle
local function _attackPointOnCircle(center, fromPt)
  local vx, vz = center.x-fromPt.x, center.z-fromPt.z
  local ux,uz,_ = _norm(vx,vz)
  local jitter = (RNGf()*40 - 20) * math.pi/180
  local cj, sj = math.cos(jitter), math.sin(jitter)
  local rx = ux*cj - uz*sj
  local rz = ux*sj + uz*cj
  local R  = (PRIO_RADIUS or 1000) - 20
  return { x = center.x + rx*R, z = center.z + rz*R }
end

-- Sélection zones
local function _nearestNeutral(side, fromPt, forbid)
  local bestI,bestP,bestD=nil,nil,1e9
  for i,pt in ipairs(BATTLEFIELD_POINTS or {}) do
    if not (forbid and forbid[i]) then
      local col = (PRIO_RING_STATE[i] and PRIO_RING_STATE[i].colorKey) or "GREEN"
      if col=="GREEN" then
        local d = _d2(fromPt,pt)
        if d < bestD then bestD,bestI,bestP = d,i,pt end
      end
    end
  end
  return bestI,bestP,bestD
end

local function _nearestEnemyLocked(side, fromPt, forbid)
  local myKey = _sideKey(side)
  local enemy = (myKey=="BLUE") and "RED" or "BLUE"
  local bestI,bestP,bestD=nil,nil,1e9
  for i,pt in ipairs(BATTLEFIELD_POINTS or {}) do
    if not (forbid and forbid[i]) then
      local col = (PRIO_RING_STATE[i] and PRIO_RING_STATE[i].colorKey) or "GREEN"
      if (col~="GREEN") and (col~=myKey) and (PRIO_ZONE_LOCKED[enemy] and PRIO_ZONE_LOCKED[enemy][i]) then
        local d = _d2(fromPt,pt)
        if d < bestD then bestD,bestI,bestP=d,i,pt end
      end
    end
  end
  return bestI,bestP,bestD
end

local function _collectK(side, fromPt, k, mode, forbid)
  local myKey = _sideKey(side)
  local enemy = (myKey=="BLUE") and "RED" or "BLUE"
  local all = {}
  for i,pt in ipairs(BATTLEFIELD_POINTS or {}) do
    if not (forbid and forbid[i]) then
      local col = (PRIO_RING_STATE[i] and PRIO_RING_STATE[i].colorKey) or "GREEN"

      if mode=="neutral" then
        -- CONTROLE : uniquement les secteurs neutres
        if col=="GREEN" then
          all[#all+1] = i
        end

      elseif mode=="enemy" then
        -- ASSAULT : secteurs ennemis (locked) OU neutres
        local enemyLocked = (col~="GREEN") and (col~=myKey)
                            and PRIO_ZONE_LOCKED[enemy]
                            and PRIO_ZONE_LOCKED[enemy][i]
        local neutral     = (col=="GREEN")

        if enemyLocked or neutral then
          all[#all+1] = i
        end
      end
    end
  end
  table.sort(all, function(a,b)
    return _d2(fromPt, BATTLEFIELD_POINTS[a]) < _d2(fromPt, BATTLEFIELD_POINTS[b])
  end)
  local res = {}
  for _,i in ipairs(all) do
    res[#res+1] = i
    if #res >= k then break end
  end
  return res
end


-----------------------------------------------------------------------
--                    SPAWN & ROUTAGE DE BASE                        --
-----------------------------------------------------------------------
local seqId = 0
local function _name(prefix)
  seqId = seqId + 1
  return prefix.."_"..seqId.."_"..RNGi(100000,999999)
end

local function _assignRouteToPoint(gname, goal, v_kmh)
  local g = Group.getByName(gname)
  if not g then return end
  local u = g:getUnits()
  if not u or not u[1] or not Unit.isExist(u[1]) then return end

  local p0 = u[1]:getPoint()

  local dx   = goal.x - p0.x
  local dz   = goal.z - p0.z
  local dist = math.sqrt(dx*dx + dz*dz)
  local v_ms = _kmh2ms(v_kmh)

  -- Mode TT (tout-terrain) : tout en Off Road, pas de point intermédiaire route
  if BATTLEFIELD_OFFROAD then
    local route = {
      points = {
        {
          x = p0.x, y = p0.z,
          type  = "Turning Point",
          action= "Off Road",
          speed = v_ms, speed_locked = true,
          task  = { id="ComboTask", params={ tasks={} } }
        },
        {
          x = goal.x, y = goal.z,
          type  = "Turning Point",
          action= "Off Road",
          speed = v_ms, speed_locked = true,
          task  = { id="ComboTask", params={ tasks={} } }
        }
      }
    }
    local ctrl = g:getController()
    if not ctrl then return end
    local function _apply()
      Controller.setTask(ctrl, { id='Mission', params={ route = route } })
    end
    timer.scheduleFunction(function() _apply() end, {}, timer.getTime() + 0.2)
    timer.scheduleFunction(function() _apply() end, {}, timer.getTime() + 0.7)
    return
  end

  -- Mode standard : route puis Off Road pour le dernier km
  local exitX, exitZ
  if dist > 2500 then
    -- on reste sur route jusqu'à dist-1000 m, puis dernier km en tout-terrain
    local ratio = (dist - 2500) / dist
    exitX = p0.x + dx * ratio
    exitZ = p0.z + dz * ratio
  else
    -- trajet trop court : point intermédiaire au milieu
    exitX = p0.x + dx * 0.5
    exitZ = p0.z + dz * 0.5
  end

  local route = {
    points = {
      {
        x = p0.x, y = p0.z,
        type  = "Turning Point",
        action= "On Road",
        speed = v_ms, speed_locked = true,
        task  = { id="ComboTask", params={ tasks={} } }
      },
      {
        x = exitX, y = exitZ,
        type  = "Turning Point",
        action= "On Road",
        speed = v_ms, speed_locked = true,
        task  = { id="ComboTask", params={ tasks={} } }
      },
      {
        x = goal.x, y = goal.z,
        type  = "Turning Point",
        action= "Off Road",
        speed = v_ms, speed_locked = true,
        task  = { id="ComboTask", params={ tasks={} } }
      }
    }
  }

  local ctrl = g:getController()
  if not ctrl then return end

  local function _apply()
    Controller.setTask(ctrl, { id='Mission', params={ route = route } })
  end

  timer.scheduleFunction(function() _apply() end, {}, timer.getTime() + 0.2)
  timer.scheduleFunction(function() _apply() end, {}, timer.getTime() + 0.7)
end


-- Spawn peloton blindé (controle/assault/counter)
local function _spawnPlatoon(side, logiPt, role, logiKey)
  local sideKey = _sideKey(side)
  local cost = ECON_GetCost(role)
  
  -- Verification economique (apres 2 minutes)
  if not ECON_CanAfford(sideKey, cost) then
    return nil  -- Pas assez de credits
  end
  
  -- Paiement (avec message debug)
  if not ECON_Spend(sideKey, cost, role, logiKey) then
    return nil
  end

  local cfgRole = AUTO_CONQUEST_CFG[role]

  -- alias : ASSAULT_RECO utilise la même config que ASSAULT
  if role == "assault_reco" then
    cfgRole = AUTO_CONQUEST_CFG.assault
  end

  local campCfg = (side==coalition.side.BLUE) and cfgRole.blue or cfgRole.red

  local ctry    = _country(side)

  -- spawn 200 m devant le LOGI dans la direction de la 1re cible
  local spawn = { x = logiPt.x, z = logiPt.z }
  do
        local idx, pt
    if role=="controle" then
      idx,pt = _nearestNeutral(side, logiPt)
    elseif role=="assault" or role=="assault_reco" then
      idx,pt = _nearestEnemyLocked(side, logiPt)
    else
      idx,pt = _nearestEnemyLocked(side, logiPt)
    end

    local vx, vz
    if pt then
      vx, vz = pt.x-logiPt.x, pt.z-logiPt.z
    else
      local a = RNGf()*2*math.pi
      vx, vz = math.cos(a), math.sin(a)
    end
    local ux,uz,_ = _norm(vx,vz)
    spawn.x = logiPt.x + ux*200
    spawn.z = logiPt.z + uz*200
  end

  -- détermination de la "famille" de peloton (pour CONTROLE) ou types direct
  local typesList
  if campCfg.platoons and #campCfg.platoons>0 then
    local chosenTypes = nil
    do
      local totalW = 0
      for _,pl in ipairs(campCfg.platoons) do totalW = totalW + (pl.weight or 1) end
      if totalW <= 0 then
        chosenTypes = campCfg.platoons[1].types
      else
        local r = RNGf()*totalW
        local acc = 0
        local chosen = campCfg.platoons[#campCfg.platoons]
        for _,pl in ipairs(campCfg.platoons) do
          acc = acc + (pl.weight or 1)
          if r <= acc then chosen = pl; break end
        end
        chosenTypes = chosen.types
      end
    end
    typesList = chosenTypes or {}
  else
    typesList = campCfg.types or {}
  end
  if not typesList or #typesList==0 then
    typesList = {"M-2 Bradley"}
  end

  local units   = {}
  local count   = math.max(1, tonumber(campCfg.count or 3))
  local gap     = 8
  local dirx    = spawn.x-logiPt.x
  local dirz    = spawn.z-logiPt.z
  local ux,uz,_ = _norm(dirx,dirz)
  local lx,lz   = -uz, ux
  local skill   = _pickSkill(campCfg.skill)

  for i=1,count do
    local ofs = (i-(count+1)/2)*gap
    local px  = spawn.x + lx*ofs
    local pz  = spawn.z + lz*ofs
    local utype = typesList[RNGi(1,#typesList)]
    units[i] = {
      type    = utype,
      name    = _name(_sideKey(side).."_"..string.upper(role)),
      x       = px,
      y       = pz,
      heading = math.atan2(ux,uz),
      skill   = skill
    }
  end

  local gname = _name(_sideKey(side).."_"..string.upper(role).."_GRP")
  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible=false, lateActivation=false,
    route = { points = {
      {
        x=spawn.x, y=spawn.z,
        type="Turning Point", action="Off Road",
        speed=0, task={id="ComboTask",params={tasks={}}}
      }
    }},
    tasks={}, units=units, name=gname
  })
  return gname
end


-- RECO : groupe léger de reconnaissance
local function _spawnReco(side, logiPt, logiKey)
  local sideKey = _sideKey(side)
  local cost = ECON_GetCost("reco")
  
  -- Verification economique (apres 2 minutes)
  if not ECON_CanAfford(sideKey, cost) then
    return nil, nil
  end
  
  -- Paiement (avec message debug)
  if not ECON_Spend(sideKey, cost, "reco", logiKey) then
    return nil, nil
  end

  local cfg = AUTO_CONQUEST_CFG.reco
  if not cfg then return nil,nil end

  local campCfg = (side == coalition.side.BLUE) and cfg.blue or cfg.red
  if not campCfg then return nil,nil end

  -- On cherche d'abord le LOGI ennemi le plus proche de CE LOGI
  local enemySide   = (side == coalition.side.BLUE) and coalition.side.RED or coalition.side.BLUE
  local enemyLogis  = (enemySide == coalition.side.BLUE) and LOGI_BLUE_POINTS or LOGI_RED_POINTS
  local refPt       = { x = logiPt.x, z = logiPt.z }

  if enemyLogis and #enemyLogis > 0 then
    local bestD = 1e9
    for _,p in ipairs(enemyLogis) do
      local dx = p.x - logiPt.x
      local dz = p.z - logiPt.z
      local d  = dx*dx + dz*dz
      if d < bestD then
        bestD = d
        refPt = { x = p.x, z = p.z }
      end
    end
  end

  -- Puis la zone NEUTRE la plus proche de ce LOGI ennemi
  local targetIdx, targetPt = _nearestNeutral(side, refPt)
  if (not targetPt) and (refPt ~= logiPt) then
    -- fallback : aucune zone neutre autour du LOGI ennemi, on tente autour du nôtre
    targetIdx, targetPt = _nearestNeutral(side, logiPt)
  end
  if not targetPt then
    return nil,nil
  end

  -- Position de spawn : 200 m vers la cible depuis le LOGI ami
  local dx, dz   = targetPt.x - logiPt.x, targetPt.z - logiPt.z
  local ux, uz,_ = _norm(dx,dz)
  if not ux or not uz then ux,uz = 1,0 end
  local spawn = {
    x = logiPt.x + ux * 200,
    z = logiPt.z + uz * 200,
  }

  local typesList = campCfg.units or {}
  if (not typesList) or (#typesList == 0) then
    if side == coalition.side.BLUE then
      typesList = { "M1043 HMMWV Armament", "M1043 HMMWV Armament", "LAV-25" }
    else
      typesList = { "BRDM-2", "BRDM-2", "BTR-80" }
    end
  end

  local ctry  = _country(side)
  local count = #typesList
  local gap   = 8
  local lx,lz = -uz, ux
  local skill = _pickSkill(campCfg.skill)

  local units = {}
  for i = 1, count do
    local ofs = (i - (count + 1) / 2) * gap
    local px  = spawn.x + lx * ofs
    local pz  = spawn.z + lz * ofs
    local uname = string.format("%s_RECO_U_%06d_%d", _sideKey(side), RNGi(100000,999999), i)
    units[#units+1] = {
      type    = typesList[i],
      name    = uname,
      x       = px,
      y       = pz,
      heading = math.atan2(ux,uz),
      skill   = skill,
    }
  end

  local gname = string.format("%s_RECO_G_%06d", _sideKey(side), RNGi(100000,999999))
  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible          = true,
    lateActivation   = false,
    route = { points = {
      {
        x      = spawn.x,
        y      = spawn.z,
        type   = "Turning Point",
        action = "Off Road",
        speed  = _kmh2ms(cfg.speed_kmh or 50),
        task   = { id = "ComboTask", params = { tasks = {} } },
      }
    }},
    tasks = {},
    units = units,
    name  = gname,
  })

  -- Route directe vers la zone neutre désignée
  _assignRouteToPoint(gname, targetPt, cfg.speed_kmh or 50)

  return gname, targetIdx
end


-----------------------------------------------------------------------
--                  RUNNERS & MANPADS (capture)                     --
-----------------------------------------------------------------------
RUNNERS = RUNNERS or { BLUE={}, RED={} }

local function _spawnRunner(side, fromLogi, sectorIdx, logiKey)
  local sideKey = _sideKey(side)
  local cost = ECON_GetCost("runner")
  
  -- Verification economique (apres 2 minutes)
  if not ECON_CanAfford(sideKey, cost) then
    return nil, nil
  end
  
  -- Paiement (avec message debug)
  if not ECON_Spend(sideKey, cost, "runner", logiKey) then
    return nil, nil
  end

  local rcfg = AUTO_CONQUEST_CFG.runner
  local ctry = _country(side)
  local vtyp = (side==coalition.side.BLUE) and rcfg.blue_type or rcfg.red_type
  local cen  = BATTLEFIELD_POINTS[sectorIdx]
  if not cen then return nil,nil end
  local dest  = cen
  local spd   = _kmh2ms(rcfg.speed_kmh or 100)
  local gname = string.format("%s_RUNNER_G_%06d", _sideKey(side), RNGi(100000,999999))
  local uname = string.format("%s_RUNNER_U_%06d", _sideKey(side), RNGi(100000,999999))
  local runnerAction = BATTLEFIELD_OFFROAD and "Off Road" or "On Road"
  local route = { points = {
    {
      x=fromLogi.x, y=fromLogi.z,
      type="Turning Point", action=runnerAction,
      speed=spd, task={id="ComboTask",params={tasks={}}}
    },
    {
      x=dest.x, y=dest.z,
      type="Turning Point", action=runnerAction,
      speed=spd, task={id="ComboTask",params={tasks={}}}
    }
  } }
  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible=true, lateActivation=false,
    route=route, tasks={},
    units = {
      {
        type=vtyp, name=uname,
        x=fromLogi.x, y=fromLogi.z,
        heading=0, skill="Good"
      }
    },
    name=gname
  })
  RUNNERS[_sideKey(side)][gname] = { sectorIdx = sectorIdx }
  return gname, dest
end

local function _runnerAlive(side, gname)
  local entry = RUNNERS[_sideKey(side)][gname]
  if not entry then return false end
  if not _groupAlive(gname) then
    RUNNERS[_sideKey(side)][gname] = nil
    return false
  end
  return true
end

-- Bâtiment le plus proche (pour manpad)
local function _nearestBuildingInRadius(center2, radius)
  local center3 = _vec3g(center2)
  local best,bd = nil, 1e9
  world.searchObjects(Object.Category.SCENERY, {
      id=world.VolumeType.SPHERE,
      params={point=center3, radius=radius}
    },
    function(obj)
      if obj and obj.getPoint then
        local p = obj:getPoint()
        local p2 = {x=p.x,z=p.z}
        local d = _d2(center2, p2)
        if d < bd then bd = d; best = p2 end
      end
      return true
    end
  )
  return best
end

local function _spawnManpad(side, sectorIdx)
  local cfg = AUTO_CONQUEST_CFG.runner
  local cen = BATTLEFIELD_POINTS[sectorIdx]
  if not cen then return end
  local bpos = _nearestBuildingInRadius(cen, PRIO_RADIUS or 1000) or cen
  local ctry = _country(side)
  local vtyp = (side==coalition.side.BLUE) and cfg.blue_manpad_type or cfg.red_manpad_type
  local gname = string.format("MANPAD_%s_%06d", _sideKey(side), RNGi(100000,999999))
  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible=true, lateActivation=false,
    route={points={{
      x=bpos.x, y=bpos.z,
      type="Turning Point", action="Off Road",
      speed=_kmh2ms(4), task={id="ComboTask",params={tasks={}}}
    }}},
    tasks={},
    units = {
      {
        type=vtyp, name=gname.."_U1",
        x=bpos.x, y=bpos.z, heading=0, skill="High"
      }
    },
    name=gname
  })
end

-----------------------------------------------------------------------
--                  ÉTATS & RÉSERVATIONS                            --
-----------------------------------------------------------------------

local STATE_CONTROLE    = {}
local STATE_ASSAULT     = {}
local STATE_COUNTER     = {}
local STATE_DA_ASSAULT  = {}
local STATE_DA_CONTROLE = {}
local STATE_RECO        = {}


-- COMMANDERS : 1 par LOGI, pas de respawn
local COMMANDERS = {}  -- [logiKey] = { side=..., gname=..., index=..., dead=false }

local RESERVED_ASSAULT = { BLUE={}, RED={} }
local function _reserveIfFree(side, idx)
  if not idx then return false end
  local k = _sideKey(side)
  if RESERVED_ASSAULT[k][idx] then return false end
  RESERVED_ASSAULT[k][idx] = true
  return true
end
local function _releaseReservation(side, idx)
  if not idx then return end
  RESERVED_ASSAULT[_sideKey(side)][idx] = nil
end

-- Pour COUNTER : journal des captures
local LAST_OWN_TS = { BLUE={}, RED={} }
local function _noteOwnership(idx, key)
  if key=="BLUE" or key=="RED" then
    LAST_OWN_TS[key][idx] = timer.getTime()
  end
end

-----------------------------------------------------------------------
--                    COMMANDER : gestion vie/mort                    --
-----------------------------------------------------------------------
local function _spawnCommander(side, logiPt, index)
  local ctry  = _country(side)
  local utype = (side==coalition.side.BLUE) and "Predator GCS" or "SKP-11"
  local gname = string.format("CMD_%s_%02d_%06d", _sideKey(side), index or 0, RNGi(100000,999999))

  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible = true,
    lateActivation = false,
    tasks = {},
    route = {
      points = {{
        x = logiPt.x, y = logiPt.z,
        type  = "Turning Point",
        action= "Off Road",
        speed = 0, speed_locked = true,
        task  = { id="ComboTask", params={tasks={}} }
      }}
    },
    units = {{
      type    = utype,
      name    = gname.."_U1",
      x       = logiPt.x,
      y       = logiPt.z,
      heading = 0,
      skill   = "High",
    }},
    name = gname,
  })

  return gname
end

local function _commanderAliveForKey(key)
  local c = COMMANDERS[key]
  if not c then return true end  -- pas de commander => pas de blocage

  if c.dead then return false end
  if _groupAlive(c.gname) then return true end

  -- Il vient de mourir → marquer et notifier tout le monde
  c.dead = true
  COMMANDERS[key] = c
  local txtSide = (c.side==coalition.side.BLUE) and "Bleu" or "Rouge"
  local idx     = c.index or 0
  trigger.action.outText(
    string.format("Centre de logistique %s n°%02d inopérant.", txtSide, idx),
    15
  )
  return false
end

-----------------------------------------------------------------------
--       ASSIGNATION D’OBJECTIFS (NEUTRAL/ENEMY) & DA escorts        --
-----------------------------------------------------------------------
local function _assignDAForAssault(aState, goal)
  local daName = aState.daName
  if not daName or not _groupAlive(daName) then return end

  local cfg  = AUTO_CONQUEST_CFG.da_assault
  local back = cfg.back_m or 500
  local logi = aState.logiPt

  local dx, dz        = goal.x-logi.x, goal.z-logi.z
  local ux,uz,dist    = _norm(dx,dz)
  local newDist       = math.max(0, dist - back)
  local target        = { x = logi.x + ux*newDist, z = logi.z + uz*newDist }
  local delay         = cfg.delay_s or 60
  local speed         = cfg.speed_kmh or (AUTO_CONQUEST_CFG.assault.speed_kmh or 50)

  timer.scheduleFunction(function()
    if _groupAlive(daName) then
      _assignRouteToPoint(daName, target, speed)
    end
  end, {}, timer.getTime() + delay)
end

local function _assignDAForControle(cState, goal)
  local daName = cState.daCName
  if not daName or not _groupAlive(daName) then return end

  local cfg  = AUTO_CONQUEST_CFG.da_controle or AUTO_CONQUEST_CFG.da_assault
  local back = cfg.back_m or 500
  local logi = cState.logiPt

  local dx, dz        = goal.x-logi.x, goal.z-logi.z
  local ux,uz,dist    = _norm(dx,dz)
  local newDist       = math.max(0, dist - back)
  local target        = { x = logi.x + ux*newDist, z = logi.z + uz*newDist }
  local delay         = cfg.delay_s or 60
  local speed         = cfg.speed_kmh or (AUTO_CONQUEST_CFG.controle.speed_kmh or 50)

  timer.scheduleFunction(function()
    if _groupAlive(daName) then
      _assignRouteToPoint(daName, target, speed)
    end
  end, {}, timer.getTime() + delay)
end

function _issueOrder(state, mode) -- mode = "neutral" | "enemy"
  if state.waitingRunner and state.waitingRunner.sectorIdx then
    return
  end

  local side   = state.side
  local logiPt = state.logiPt
  local forbid = (mode=="enemy") and RESERVED_ASSAULT[_sideKey(side)] or nil

  local idx, pt
  if (not state.usedInitial) and state.initialChoices and #state.initialChoices>0 then
    if mode=="enemy" then
      local pool = {}
      for _,i in ipairs(state.initialChoices) do
        if not (forbid and forbid[i]) then
          pool[#pool+1] = i
        end
      end
      if #pool > 0 then
        idx = pool[RNGi(1,#pool)]
        pt  = BATTLEFIELD_POINTS[idx]
      end
    else
      idx = state.initialChoices[RNGi(1,#state.initialChoices)]
      pt  = BATTLEFIELD_POINTS[idx]
    end
    state.usedInitial = true
  end

  if not idx then
    if mode=="neutral" then
      idx,pt = _nearestNeutral(side, logiPt, forbid)
    else
      -- ASSAULT : en priorité une zone ennemie locked, sinon une zone neutre
      idx,pt = _nearestEnemyLocked(side, logiPt, forbid)
      if not idx then
        idx,pt = _nearestNeutral(side, logiPt, forbid)
      end
    end
    if not idx then return end
  end

  if mode=="enemy" then
    if not _reserveIfFree(side, idx) then
      -- Essaye une autre cible : ennemi locked, puis neutre
      local newIdx,newPt = _nearestEnemyLocked(side, logiPt, forbid)
      if not newIdx or not _reserveIfFree(side, newIdx) then
        newIdx,newPt = _nearestNeutral(side, logiPt, forbid)
        if not newIdx or not _reserveIfFree(side, newIdx) then
          return
        end
      end
      idx,pt = newIdx,newPt
    end
    state.reservedIdx = idx
  end

  state.targetIdx = idx
  state.stuckRef  = nil
  local goal      = _attackPointOnCircle(pt, logiPt)
  local v         = (mode=="neutral") and (AUTO_CONQUEST_CFG.controle.speed_kmh or 50)
                                        or (AUTO_CONQUEST_CFG.assault.speed_kmh  or 50)

  _assignRouteToPoint(state.gname, goal, v)

  if mode=="neutral" and state.daCName then
    _assignDAForControle(state, goal)
  elseif mode=="enemy" and state.daName then
    _assignDAForAssault(state, goal)
  end
end


-----------------------------------------------------------------------
--                      COUNTER : DÉTECTION                          --
-----------------------------------------------------------------------
local function _scanCounterAlert(side)
  local enemySide = (side==coalition.side.BLUE) and coalition.side.RED or coalition.side.BLUE
  local myKey     = _sideKey(side)
  local now       = timer.getTime()
  local cfgC      = AUTO_CONQUEST_CFG.counter

  -- 1) Ennemi ASSAULT immobile dans une zone possédée récemment
  for _,stE in pairs(STATE_ASSAULT) do
    if stE.side==enemySide and _groupAlive(stE.gname) and stE.targetIdx then
      local lp  = _leaderPoint(stE.gname)
      local cen = BATTLEFIELD_POINTS[stE.targetIdx]
      if lp and cen and _d2(lp,cen) <= (PRIO_RADIUS or 1000) then
        local lastMine = LAST_OWN_TS[myKey][stE.targetIdx] or -1e9
        if (now - lastMine) <= (cfgC.recent_ownership_s or 300) then
          local spd = _leaderSpeedMS(stE.gname) or 0
          if spd <= (cfgC.idle_speed_threshold_ms or 1.0) then
            return { enemyAssaultName=stE.gname, zoneIdx=stE.targetIdx }
          end
        end
      end
    end
  end

  -- 2) Runner ami menacé par un ASSAULT ennemi
  local threatR = cfgC.runner_threat_radius_m or 800
  for rname,_ in pairs(RUNNERS[myKey] or {}) do
    if _runnerAlive(side, rname) then
      local rp = _leaderPoint(rname)
      if rp then
        for _,stE in pairs(STATE_ASSAULT) do
          if stE.side==enemySide and _groupAlive(stE.gname) then
            local ep = _leaderPoint(stE.gname)
            if ep and _d2(rp,ep) <= threatR then
              return { enemyAssaultName=stE.gname, zoneIdx=stE.targetIdx }
            end
          end
        end
      end
    end
  end

  return nil
end

local function _setModeCounter(st, m)
  st.mode     = m
  st.assigned = false
end

-----------------------------------------------------------------------
--                    ANTI-BLOCAGE GÉNÉRIQUE                         --
-----------------------------------------------------------------------
-----------------------------------------------------------------------
--                    ANTI-BLOCAGE GÉNÉRIQUE                         --
-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- ANTI-BLOCAGE GÉNÉRIQUE (CONTROLE + ASSAULT)
--  - mode == "neutral" : utilisé par CONTROLE
--  - mode == "enemy"   : utilisé par ASSAULT
-----------------------------------------------------------------------
-----------------------------------------------------------------------
--                    ANTI-BLOCAGE GÉNÉRIQUE                         --
--  mode = "neutral" pour CONTROLE, "enemy" pour ASSAULT             --
-----------------------------------------------------------------------
local function _updateStuckWatch(state, mode)
  -- Groupe mort ou pas de cible → on reset la ref, mais on ne fait rien
  if not state.gname or not _groupAlive(state.gname) then
    state.stuckRef = nil
    return
  end
  if not state.targetIdx then
    state.stuckRef = nil
    return
  end

  local lp = _leaderPoint(state.gname)
  if not lp then return end

  local now = timer.getTime()

  -- Première référence
  if not state.stuckRef then
    state.stuckRef = { pos = { x = lp.x, z = lp.z }, t = now }
    return
  end

  -- S’ils ont bougé de plus de 50 m, on remet le chrono à zéro
  local moved = _d2(lp, state.stuckRef.pos)
  if moved > 50 then
    state.stuckRef.pos.x = lp.x
    state.stuckRef.pos.z = lp.z
    state.stuckRef.t     = now
    return
  end

  -- Pas bougé de façon significative : on regarde depuis combien de temps
  local dt    = now - state.stuckRef.t
  -- Pour ASSAULT (enemy) : on tolère moins longtemps que pour CONTROLE
  local limit = (mode == "enemy") and 45 or 60
  if dt < limit then return end

  local cen = BATTLEFIELD_POINTS[state.targetIdx]
  if not cen then return end

  local distTarget = _d2(lp, cen)

  -- CONTROLE : si déjà dans la zone, on ne relance pas (ils peuvent camper pour attendre le runner)
  if mode == "neutral" and distTarget <= (PRIO_RADIUS or 1000) then
    return
  end

  -- Sinon on relance un ordre vers un nouvel objectif équivalent
  if mode == "neutral" then
    _issueOrder(state, "neutral")
  else -- "enemy"
    _issueOrder(state, "enemy")
  end

  -- On remet une nouvelle ref à l’endroit actuel
  state.stuckRef = { pos = { x = lp.x, z = lp.z }, t = now }
end



-----------------------------------------------------------------------
--                            TICKS                                  --
-----------------------------------------------------------------------
local function _tickControle()
  local now      = timer.getTime()
  local rc       = AUTO_CONQUEST_CFG.runner
  local idleMS   = rc.idle_speed_threshold_ms or 1.0
  local idleNeed = rc.idle_required_s         or 10
  local timeout  = rc.wait_timeout_s          or 240

  for key,st in pairs(STATE_CONTROLE) do
    -- respawn
    if st.gname and not _groupAlive(st.gname) then
      if not _commanderAliveForKey(st.logiKey or key) then
        st.nextRespawn = 0
      else
        if st.nextRespawn==0 then
          st.nextRespawn = now + (AUTO_CONQUEST_CFG.respawn_seconds or 300)
        elseif now >= st.nextRespawn then
          st.gname = _spawnPlatoon(st.side, st.logiPt, "controle", key)
          st.nextRespawn   = 0
          st.waitingRunner = nil
          st.usedInitial   = false
          st.targetIdx     = nil
          st.initialChoices = _collectK(
            st.side, st.logiPt,
            (AUTO_CONQUEST_CFG.controle.initial_choices or 3),
            "neutral"
          )
          timer.scheduleFunction(function()
            _issueOrder(st,"neutral")
          end, {}, timer.getTime()+2)
        end
      end
    end

    -- gestion runner & lock
    if st.targetIdx and _groupAlive(st.gname) then
      local ring = PRIO_RING_STATE[st.targetIdx]
      if ring and ring.colorKey == _sideKey(st.side) then
        local lp  = _leaderPoint(st.gname)
        local spd = _leaderSpeedMS(st.gname) or 0
        if lp and _d2(lp, BATTLEFIELD_POINTS[st.targetIdx]) <= (PRIO_RADIUS or 1000) and spd<=idleMS then
          st.waitingRunner = st.waitingRunner or {
            sectorIdx=st.targetIdx,
            stillSince=nil, runnerName=nil,
            lockSince=nil, timeout=now+timeout
          }
          st.waitingRunner.stillSince = st.waitingRunner.stillSince or now

          if (now - st.waitingRunner.stillSince >= idleNeed) and (not st.waitingRunner.runnerName) then
            local nl = _nearestLogi(st.side, BATTLEFIELD_POINTS[st.targetIdx])
            local rn,_ = _spawnRunner(st.side, nl, st.targetIdx, key)
            st.waitingRunner.runnerName = rn
          end

          if st.waitingRunner and st.waitingRunner.runnerName then
            local rSpd = _leaderSpeedMS(st.waitingRunner.runnerName) or 0
            local rp   = _leaderPoint(st.waitingRunner.runnerName)
            if rp and _d2(rp,BATTLEFIELD_POINTS[st.waitingRunner.sectorIdx]) <= (PRIO_RADIUS or 1000) and rSpd<=idleMS then
              st.waitingRunner.lockSince = st.waitingRunner.lockSince or now
              if now - st.waitingRunner.lockSince >= idleNeed then
                local myKey = _sideKey(st.side)
                PRIO_ZONE_LOCKED[myKey][st.waitingRunner.sectorIdx] = true
                _spawnManpad(st.side, st.waitingRunner.sectorIdx)
                if AUTO_CONQUEST.OnZoneLocked then
                  AUTO_CONQUEST.OnZoneLocked(st.waitingRunner.sectorIdx, myKey)
                end
                st.targetIdx     = nil
                st.waitingRunner = nil
                timer.scheduleFunction(function() _issueOrder(st,"neutral") end, {}, timer.getTime()+1.0)
              end
            else
              st.waitingRunner.lockSince = nil
            end
          elseif st.waitingRunner and now >= st.waitingRunner.timeout then
            st.targetIdx     = nil
            st.waitingRunner = nil
            timer.scheduleFunction(function() _issueOrder(st,"neutral") end, {}, timer.getTime()+1.0)
          end
        else
          if st.waitingRunner then st.waitingRunner.stillSince = nil end
        end
      end
    end

       -- Anti-blocage (neutres)
    _updateStuckWatch(st, "neutral")

    local startControle = (AUTO_CONQUEST_START and AUTO_CONQUEST_START.controle) or 0
    if now >= startControle then
      if _groupAlive(st.gname)
        and not st.targetIdx
        and not (st.waitingRunner and st.waitingRunner.sectorIdx)
      then
        timer.scheduleFunction(
          function() _issueOrder(st, "neutral") end,
          {},
          timer.getTime() + 1.0
        )
      end
    end

  end

  return now + 5
end

-----------------------------------------------------------------------
-- TICK ASSAULT : logique calquée sur CONTROLE, mais en "enemy-only"
--  + anti-blocage identique
--  + watchdog global si le groupe ne bouge plus du tout
-----------------------------------------------------------------------
local function _tickAssault()
  local now      = timer.getTime()
  local rc       = AUTO_CONQUEST_CFG.runner or {}
  local idleMS   = rc.idle_speed_threshold_ms or 1.0
  local idleNeed = rc.idle_required_s         or 10   -- utilisé pour les runners, pas ici
  local timeout  = rc.wait_timeout_s          or 240  -- idem

  -- délai avant qu’un ASSAULT immobile sur son objectif reparte vers une autre zone
  local assaultIdleReset = (AUTO_CONQUEST_CFG.assault and AUTO_CONQUEST_CFG.assault.idle_reset_s) or 45
  -- watchdog global : si le groupe NE BOUGE PLUS DU TOUT pendant longtemps, on le réinitialise
  local globalIdleReset  = (AUTO_CONQUEST_CFG.assault and AUTO_CONQUEST_CFG.assault.global_idle_reset_s) or 90

  for key,st in pairs(STATE_ASSAULT) do
    ------------------------------------------------------------------
    -- 1) GESTION DES RESPAWNS (même logique que CONTROLE)
    ------------------------------------------------------------------
    if st.gname and not _groupAlive(st.gname) then
      if not _commanderAliveForKey(st.logiKey or key) then
        -- Centre logistique mort -> plus de respawn
        st.nextRespawn = 0
      else
        if st.nextRespawn == 0 then
          st.nextRespawn = now + (AUTO_CONQUEST_CFG.respawn_seconds or 300)
        elseif now >= st.nextRespawn then
          -- Respawn du peloton ASSAULT
          _releaseReservation(st.side, st.reservedIdx)
          st.reservedIdx    = nil
          st.gname          = _spawnPlatoon(st.side, st.logiPt, "assault", key)
          st.nextRespawn    = 0
          st.waitingRunner  = nil
          st.usedInitial    = false
          st.targetIdx      = nil
          st.initialChoices = _collectK(
            st.side, st.logiPt,
            (AUTO_CONQUEST_CFG.assault.initial_choices or 3),
            "enemy", RESERVED_ASSAULT[_sideKey(st.side)]
          )
          st.stuckRef       = nil
          st.arriveSince    = nil
          st.globalIdleSince= nil

          -- petit délai avant de lui donner un nouvel objectif ENEMY
          timer.scheduleFunction(function()
            _issueOrder(st, "enemy")
          end, {}, timer.getTime() + 2)
        end
      end
    end

    ------------------------------------------------------------------
    -- 2) LOGIQUE D’OBJECTIF (copie de CONTROLE mais en ENEMY)
    --    a) Si la zone visée devient amie -> on passe à la suivante
    --    b) S’ils campent sur la zone (neutre/enemy) trop longtemps -> on passe à la suivante
    ------------------------------------------------------------------
    if st.gname and _groupAlive(st.gname) and st.targetIdx then
      local myKey = _sideKey(st.side)
      local ring  = PRIO_RING_STATE[st.targetIdx]

      -- a) La zone devient amie -> on libère tout et on repart vers un autre objectif ENEMY
      if ring and ring.colorKey == myKey then
        _releaseReservation(st.side, st.reservedIdx)
        st.reservedIdx    = nil
        st.targetIdx      = nil
        st.waitingRunner  = nil
        st.stuckRef       = nil
        st.arriveSince    = nil
        st.globalIdleSince= nil

        timer.scheduleFunction(function()
          _issueOrder(st, "enemy")
        end, {}, timer.getTime() + 1.0)

      else
        -- b) Ils sont SUR leur objectif (neutre/enemy) ET immobiles : ASSAULT NE DOIT PAS CAMPER
        local cen = BATTLEFIELD_POINTS[st.targetIdx]
        if cen then
          local lp  = _leaderPoint(st.gname)
          local spd = _leaderSpeedMS(st.gname) or 0
          if lp and _d2(lp, cen) <= (PRIO_RADIUS or 1000) and spd <= idleMS then
            st.arriveSince = st.arriveSince or now
            if now - st.arriveSince >= assaultIdleReset then
              -- On libère cette zone et on en cherche une autre ENEMY
              _releaseReservation(st.side, st.reservedIdx)
              st.reservedIdx    = nil
              st.targetIdx      = nil
              st.waitingRunner  = nil
              st.stuckRef       = nil
              st.arriveSince    = nil
              st.globalIdleSince= nil

              timer.scheduleFunction(function()
                _issueOrder(st, "enemy")
              end, {}, timer.getTime() + 1.0)
            end
          else
            -- Ils ne sont plus collés au centre de la zone -> on remet le chrono "campeur" à zéro
            st.arriveSince = nil
          end
        end
      end
    else
      -- Pas de cible pour ce groupe -> on s’assure que le timer d’arrivée est reset
      st.arriveSince = nil
    end

    ------------------------------------------------------------------
    -- 3) WATCHDOG GLOBAL : si le groupe ne bouge plus DU TOUT
    --    pendant globalIdleReset s, on réinitialise complètement
    ------------------------------------------------------------------
    if st.gname and _groupAlive(st.gname) then
      local spd = _leaderSpeedMS(st.gname) or 0
      if spd <= idleMS then
        st.globalIdleSince = st.globalIdleSince or now
        if now - st.globalIdleSince >= globalIdleReset then
          _releaseReservation(st.side, st.reservedIdx)
          st.reservedIdx    = nil
          st.targetIdx      = nil
          st.waitingRunner  = nil
          st.stuckRef       = nil
          st.arriveSince    = nil
          st.globalIdleSince= nil

          timer.scheduleFunction(function()
            _issueOrder(st, "enemy")
          end, {}, timer.getTime() + 1.0)
        end
      else
        st.globalIdleSince = nil
      end
    else
      st.globalIdleSince = nil
    end

    ------------------------------------------------------------------
    -- 4) ANTI-BLOCAGE "classique" : même mécanique que CONTROLE
    --    -> relance un ordre vers la même cible ENEMY si bloqué
    ------------------------------------------------------------------
    _updateStuckWatch(st, "enemy")

    ------------------------------------------------------------------
    -- 5) DÉMARRAGE / RELANCE SI PAS D’OBJECTIF
    --    -> identique à CONTROLE, mais en "enemy"
    ------------------------------------------------------------------
    local startAssault = (AUTO_CONQUEST_START and AUTO_CONQUEST_START.assault) or 0
    if now >= startAssault then
      if _groupAlive(st.gname)
        and not st.targetIdx
        and not (st.waitingRunner and st.waitingRunner.sectorIdx)
      then
        timer.scheduleFunction(
          function() _issueOrder(st, "enemy") end,
          {},
          timer.getTime() + 1.0
        )
      end
    end
  end

  return now + 5
end



-- COUNTER (anti-spam + 1 counter par zone au plus)
local function _tickCounter()
  local now  = timer.getTime()
  local cfgC = AUTO_CONQUEST_CFG.counter

  for key,st in pairs(STATE_COUNTER) do
    if st.gname and not _groupAlive(st.gname) then
      if not _commanderAliveForKey(st.logiKey or key) then
        st.nextRespawn = 0
      else
        if st.nextRespawn==0 then
          st.nextRespawn = now + (AUTO_CONQUEST_CFG.respawn_seconds or 300)
        elseif now>=st.nextRespawn then
          st.gname      = _spawnPlatoon(st.side, st.logiPt, "counter", key)
          st.nextRespawn= 0
          _setModeCounter(st,"idle")
          st.targetAssault = nil
          st.targetZone    = nil
          st.homeGoal      = nil
        end
      end
    end

    if st.mode=="idle" and _groupAlive(st.gname) then
      if (not st.nextScan) or now >= st.nextScan then
        st.nextScan = now + (cfgC.recheck_s or 5)
        local alert = _scanCounterAlert(st.side)
        if alert then
          local taken = false
          for _,st2 in pairs(STATE_COUNTER) do
            if st2 ~= st and st2.mode~="idle" and st2.targetZone == alert.zoneIdx then
              taken = true
              break
            end
          end
          if not taken then
            st.targetAssault = alert.enemyAssaultName
            st.targetZone    = alert.zoneIdx
            _setModeCounter(st,"intercept")
          end
        end
      end

    elseif st.mode=="intercept" then
      if not st.assigned and st.targetAssault and _groupAlive(st.gname) then
        local ep = _leaderPoint(st.targetAssault)
        if not ep and st.targetZone then
          ep = BATTLEFIELD_POINTS[st.targetZone]
        end
        if not ep then ep = st.logiPt end
        _assignRouteToPoint(st.gname, ep, (cfgC.speed_kmh or 55))
        st.assigned = true
      end
      if (not st.targetAssault) or (not _groupAlive(st.targetAssault)) then
        _setModeCounter(st,"rtb")
      end

    elseif st.mode=="rtb" then
      if not st.assigned and _groupAlive(st.gname) then
        st.homeGoal = _randomDefensePoint(st.side) or st.logiPt
        _assignRouteToPoint(st.gname, st.homeGoal, (cfgC.speed_kmh or 55))
        st.assigned    = true
        st.settleSince = nil
      else
        local lp  = _leaderPoint(st.gname)
        local spd = _leaderSpeedMS(st.gname) or 0
        if lp and st.homeGoal and _d2(lp, st.homeGoal) < 150 and spd <= (cfgC.idle_speed_threshold_ms or 1.0) then
          st.settleSince = st.settleSince or now
          if now - st.settleSince >= 10 then
            _setModeCounter(st,"idle")
            st.targetAssault = nil
            st.targetZone    = nil
            st.homeGoal      = nil
            st.nextScan      = now + (cfgC.recheck_s or 5)
          end
        else
          st.settleSince = nil
        end
      end
    end
  end

  return now + 2
end

-----------------------------------------------------------------------
--                         DA FIXE PAR LOGI                          --
-----------------------------------------------------------------------
local function _spawnDAForLogi(side, logiPt, firstTargets, startTime)

  local cfg   = AUTO_CONQUEST_CFG.da
  local camp  = (side==coalition.side.BLUE) and cfg.blue or cfg.red
  local ctry  = _country(side)
  local skill = _pickSkill(cfg.skill)

  for i,def in ipairs(camp.groups) do
    local name = string.format("DA_%s_%02d_%06d", _sideKey(side), i, RNGi(100000,999999))
    local units = {}
    for n=1,def.count do
      units[#units+1] = {
        type = def.type,
        name = name.."_U"..n,
        x    = logiPt.x + (n-1)*5,
        y    = logiPt.z,
        heading = 0,
        skill   = skill
      }
    end
    coalition.addGroup(ctry, Group.Category.GROUND, {
      visible=true, lateActivation=false,
      name=name, tasks={},
      route={points={{
        x=logiPt.x, y=logiPt.z,
        type="Turning Point", action="Off Road",
        speed=_kmh2ms(cfg.speed_kmh or 35),
        task={id="ComboTask",params={tasks={}}}
      }}},
      units=units
    })

    if firstTargets and #firstTargets>0 then
      local idx = firstTargets[((i-1)%#firstTargets)+1]
      local cen = BATTLEFIELD_POINTS[idx]
      if cen then
        local a = RNGf() * 2 * math.pi
        local r = (PRIO_RADIUS - 40) * math.sqrt(RNGf())
        local p = { x = cen.x + r * math.cos(a), z = cen.z + r * math.sin(a) }

        local now    = timer.getTime()
        local startT = startTime or now

        if startT <= now then
          -- Si la date est déjà passée (cas rare), on part tout de suite
          _assignRouteToPoint(name, p, (cfg.speed_kmh or 35))
        else
          timer.scheduleFunction(
            function()
              _assignRouteToPoint(name, p, (cfg.speed_kmh or 35))
            end,
            {},
            startT
          )
        end
      end
    end

  end
end

-----------------------------------------------------------------------
--                          ARTILLERIE                              --
-----------------------------------------------------------------------
local ARTY_STATE   = {}
local ARTY_LIST    = { BLUE={}, RED={} }
local RUNNER_LOCK  = {}    -- runnerName -> artyKey

local function _artyFireAtVec2(gname, point2, radius_m)
  local grp = Group.getByName(gname)
  if not grp or not Group.isExist(grp) then return false end
  local ctrl = grp:getController()
  if not ctrl then return false end

  local ROE_ID, ROE_OPEN    = AI.Option.Ground.id.ROE,        AI.Option.Ground.val.ROE.OPEN_FIRE
  local ALARM_ID, ALARM_RED = AI.Option.Ground.id.ALARM_STATE,AI.Option.Ground.val.ALARM_STATE.RED
  local task = {
    id    = 'FireAtPoint',
    params = {
      point             = {x=point2.x, y=point2.z},
      radius            = radius_m or 300,
      expendQty         = 60,
      expendQtyEnabled  = true,
    }
  }

  pcall(Controller.setOption, ctrl, ROE_ID, ROE_OPEN)
  pcall(Controller.setOption, ctrl, ALARM_ID, ALARM_RED)
  pcall(Controller.pushTask,   ctrl, task)

  local us = grp:getUnits() or {}
  for _,u in ipairs(us) do
    if u and Unit.isExist(u) then
      local uc = u:getController()
      if uc then
        pcall(Controller.setOption, uc, ROE_ID, ROE_OPEN)
        pcall(Controller.setOption, uc, ALARM_ID, ALARM_RED)
        pcall(Controller.pushTask,  uc, task)
      end
    end
  end
  return true
end

local function _spawnArty(side, atPt)
  local cfg   = AUTO_CONQUEST_CFG.arty
  local camp  = (side==coalition.side.BLUE) and cfg.blue or cfg.red
  local ctry  = _country(side)
  local units = {}
  local gap   = 10

  for i=1,camp.tubes do
    units[#units+1] = {
      type  = camp.tube_type,
      name  = string.format("ARTY_%s_T_%06d", _sideKey(side), RNGi(100000,999999)),
      x     = atPt.x + (i-1)*gap,
      y     = atPt.z,
      heading = 0,
      skill   = cfg.skill or "Excellent"
    }
  end
  units[#units+1] = {
    type  = camp.truck_type,
    name  = string.format("ARTY_%s_TR_%06d", _sideKey(side), RNGi(100000,999999)),
    x     = atPt.x - 12,
    y     = atPt.z - 12,
    heading = 0,
    skill   = "Good"
  }

  local route = { points = {{
    x=atPt.x, y=atPt.z,
    type="Turning Point", action="Off Road",
    speed=0, speed_locked=true,
    task={id="ComboTask",params={tasks={}}}
  }} }

  local gname = string.format("ARTY_%s_G_%06d", _sideKey(side), RNGi(100000,999999))
  coalition.addGroup(ctry, Group.Category.GROUND, {
    visible=false, lateActivation=false,
    route=route, tasks={}, units=units, name=gname
  })
  return gname
end

-- runners éligibles au tir (immobiles près d’un marker)
local function _eligibleRunners()
  local out = {}
  local function closeIdx(pt, maxR)
    local bestI,bestD=nil,(maxR or 500)+1
    for i,cen in ipairs(BATTLEFIELD_POINTS or {}) do
      local d=_d2(pt,cen)
      if d<bestD then bestD, bestI = d,i end
    end
    if bestI and bestD <= (maxR or 500) then return bestI end
    return nil
  end

  for keySide, list in pairs(RUNNERS or {}) do
    for rname,_ in pairs(list) do
      local grp = Group.getByName(rname)
      if grp and Group.isExist(grp) then
        local p = _leaderPoint(rname)
        if p and (_leaderSpeedMS(rname) < 1.0) then
          local idx = closeIdx(p, 500)
          if idx then
            out[#out+1] = {
              side      = keySide,
              name      = rname,
              pos       = p,
              markerIdx = idx
            }
          end
        end
      end
    end
  end
  return out
end

local function _assignOneArtyForRunner(r)
  if RUNNER_LOCK[r.name] then return end
  local enemyKey = (r.side=="BLUE") and "RED" or "BLUE"
  local pool     = ARTY_LIST[enemyKey] or {}
  if #pool == 0 then return end

  local cand = {}
  for i=1,#pool do cand[i] = pool[i] end
  _shuffle(cand)

  for _,akey in ipairs(cand) do
    local st = ARTY_STATE[akey]
    if st and _groupAlive(st.gname) and (not st.order) then
      RUNNER_LOCK[r.name] = akey
      local center = BATTLEFIELD_POINTS[r.markerIdx]
      if not center then return end
      local lp   = _leaderPoint(st.gname) or st.home
      local dist = _d2(lp, center)
      local maxR = AUTO_CONQUEST_CFG.arty.max_range_m or 30000

      if dist > maxR then
        local dx,dz   = lp.x-center.x, lp.z-center.z
        local ux,uz,_ = _norm(dx,dz)
        local stagePt = { x = center.x + ux*20000, z = center.z + uz*20000 }
        st.order = { markerIdx=r.markerIdx, phase="stage", stagePt=stagePt, targetPt={x=center.x,z=center.z} }
        _assignRouteToPoint(st.gname, stagePt, AUTO_CONQUEST_CFG.arty.speed_kmh or 20)
      else
        st.order = { markerIdx=r.markerIdx, phase="fire", targetPt={x=center.x,z=center.z} }
      end
      st.lockedRunner = r.name
      return
    end
  end
end

local function _tickReco()
  local now         = timer.getTime()
  local cfgReco     = AUTO_CONQUEST_CFG.reco or {}
  local respawnReco = cfgReco.respawn_s or 900

  -- on réutilise le délai global de respawn pour l'escorte ASSAULT_RECO
  local respawnAss  = AUTO_CONQUEST_CFG.respawn_seconds or 300
  local speedAss    = (AUTO_CONQUEST_CFG.assault and AUTO_CONQUEST_CFG.assault.speed_kmh) or 40

  -- paramètres d'immobilité (mêmes bases que le runner / assault)
  local rc              = AUTO_CONQUEST_CFG.runner or {}
  local idleMS          = rc.idle_speed_threshold_ms or 1.0
  local globalIdleReset = (AUTO_CONQUEST_CFG.assault and AUTO_CONQUEST_CFG.assault.global_idle_reset_s) or 90

  for key, st in pairs(STATE_RECO) do
    ----------------------------------------------------------------
    -- 1) RECO : respawn comme avant
    ----------------------------------------------------------------
    if (not st.gname) or (not _groupAlive(st.gname)) then
      if not st.nextRespawn or st.nextRespawn == 0 then
        st.nextRespawn = now + respawnReco
      elseif now >= st.nextRespawn then
        local gname, idx = _spawnReco(st.side, st.logiPt, key)
        st.gname       = gname
        st.targetIdx   = idx
        st.nextRespawn = 0

        -- on reset aussi l'escorte pour repartir sur la nouvelle cible
        st.assaultName        = nil
        st.nextAssaultRespawn = 0
        st.assaultIdleSince   = nil
      end
    end

    ----------------------------------------------------------------
    -- 2) ASSAULT_RECO : spawn + route initiale vers la cible RECO
    ----------------------------------------------------------------
    if st.targetIdx and st.gname and _groupAlive(st.gname) then
      -- si pas d'escorte ou morte, on gère son respawn
      if (not st.assaultName) or (not _groupAlive(st.assaultName)) then
        if not st.nextAssaultRespawn or st.nextAssaultRespawn == 0 then
          st.nextAssaultRespawn = now + respawnAss
        elseif now >= st.nextAssaultRespawn then
          local gnameAss = _spawnPlatoon(st.side, st.logiPt, "assault_reco", key)
          st.assaultName        = gnameAss
          st.nextAssaultRespawn = 0
          st.assaultIdleSince   = nil

          if gnameAss and BATTLEFIELD_POINTS and BATTLEFIELD_POINTS[st.targetIdx] then
            local cen  = BATTLEFIELD_POINTS[st.targetIdx]
            local goal = _attackPointOnCircle(cen, st.logiPt)
            _assignRouteToPoint(gnameAss, goal, speedAss)
          end
        end
      end
    end

    ----------------------------------------------------------------
    -- 3) WATCHDOG d'immobilité pour ASSAULT_RECO
    --    -> si l'escorte reste plantée trop longtemps (après manœuvre
    --       AI_Advanced par exemple), on lui REPOUSSE sa route
    --       vers la cible actuelle du RECO.
    ----------------------------------------------------------------
    if st.assaultName
      and _groupAlive(st.assaultName)
      and st.targetIdx
      and BATTLEFIELD_POINTS
      and BATTLEFIELD_POINTS[st.targetIdx]
    then
      local spd = _leaderSpeedMS(st.assaultName) or 0

      if spd <= idleMS then
        st.assaultIdleSince = st.assaultIdleSince or now
        if now - st.assaultIdleSince >= globalIdleReset then
          -- on renvoie l'ASSAULT_RECO vers la zone du RECO
          local cen  = BATTLEFIELD_POINTS[st.targetIdx]
          local goal = _attackPointOnCircle(cen, st.logiPt)
          _assignRouteToPoint(st.assaultName, goal, speedAss)

          st.assaultIdleSince = nil
        end
      else
        st.assaultIdleSince = nil
      end
    else
      st.assaultIdleSince = nil
    end
  end

  return now + 5
end


local function _tickArty()
  local now    = timer.getTime()
  local cfg    = AUTO_CONQUEST_CFG.arty
  local maxR   = cfg.max_range_m or 30000
  local fireDur= 60*(cfg.fire_minutes or 4)

  local cands = _eligibleRunners()
  for _,r in ipairs(cands) do
    _assignOneArtyForRunner(r)
  end

  for _,st in pairs(ARTY_STATE) do
    if st.gname and not _groupAlive(st.gname) then
      if st.logiKey and not _commanderAliveForKey(st.logiKey) then
        st.nextRespawn = 0
      else
        if st.nextRespawn==0 then
          st.nextRespawn = now + (AUTO_CONQUEST_CFG.respawn_seconds or 300)
        elseif now>=st.nextRespawn then
          st.gname       = _spawnArty(st.side, st.home)
          st.nextRespawn = 0
          st.busyUntil   = 0
          st.order       = nil
          st.lockedRunner= nil
          st.leg         = 1
          local dest     = st.other or st.home
          if dest then
            _assignRouteToPoint(st.gname, dest, cfg.speed_kmh or 20)
          end
        end
      end
    else
      if st.busyUntil and now < st.busyUntil then
      else
        if st.order then
          local lp = _leaderPoint(st.gname) or st.home
          if st.order.phase=="stage" then
            local spd = _leaderSpeedMS(st.gname) or 0
            if _d2(lp, st.order.stagePt) < 200 and spd <= 1.0 then
              st.order.phase = "fire"
            end
          end
          if st.order.phase=="fire" then
            local center = st.order.targetPt
            local dist   = _d2(lp, center)
            if dist <= maxR then
              local a = RNGf()*2*math.pi
              local r = (cfg.dispersion_m or 500)*math.sqrt(RNGf())
              local tgt = { x=center.x + r*math.cos(a), z=center.z + r*math.sin(a) }
              if _artyFireAtVec2(st.gname, tgt, math.floor(PRIO_RADIUS*0.5)) then
                st.busyUntil = now + fireDur
                if st.lockedRunner then
                  RUNNER_LOCK[st.lockedRunner] = nil
                end
                st.order = nil
              end
            else
              local dx,dz   = lp.x-center.x, lp.z-center.z
              local ux,uz,_ = _norm(dx,dz)
              local stagePt = { x=center.x + ux*20000, z=center.z + uz*20000 }
              st.order.phase  = "stage"
              st.order.stagePt= stagePt
              _assignRouteToPoint(st.gname, stagePt, cfg.speed_kmh or 20)
            end
          end
        else
          if st.other then
            local lp  = _leaderPoint(st.gname) or st.home
            local goal= (st.leg==1) and st.other or st.home
            local spd = _leaderSpeedMS(st.gname) or 0
            if _d2(lp,goal) < 120 and spd<=1.0 then
              st.leg = (st.leg==1) and 2 or 1
              local dest = (st.leg==1) and st.other or st.home
              if dest then _assignRouteToPoint(st.gname, dest, cfg.speed_kmh or 20) end
            end
          end
        end
      end
    end
  end

  return now + (cfg.check_every_s or 2.5)
end

-----------------------------------------------------------------------
--                             HOOKS                                --
-----------------------------------------------------------------------
function AUTO_CONQUEST.OnZoneColorChange(idx, key)
  if key=="BLUE" or key=="RED" then _noteOwnership(idx, key) end
end

function AUTO_CONQUEST.OnZoneLocked(idx, key)
  -- hook dispo pour debug si besoin
end

-----------------------------------------------------------------------
--                              INIT                                --
-----------------------------------------------------------------------
function AUTO_CONQUEST.Init()
  -- T0 pour l’auto-conquest (appel d’Init)
  local baseT = timer.getTime()

  -- Calendrier des départs (relatif à baseT)
  AUTO_CONQUEST_START.reco     = baseT             -- RECO + ASSAULT d’escorte
  AUTO_CONQUEST_START.controle = baseT + 180        -- CONTROLE
  AUTO_CONQUEST_START.assault  = baseT + 300      -- ASSAULT principal
  AUTO_CONQUEST_START.da       = baseT + 600      -- DA fixe (spawnDAForLogi)
  AUTO_CONQUEST_START.arty     = baseT + 900       -- Artillerie

  local function setupSide(side, logis)

    for idx,p in ipairs(logis or {}) do
      local key    = string.format("%s_%d_%d", _sideKey(side):sub(1,1), math.floor(p.x), math.floor(p.z))
      local logiPt = {x=p.x,z=p.z}

      -- COMMANDER
      local cmdName = _spawnCommander(side, logiPt, idx)
      COMMANDERS[key] = {
        side  = side,
        gname = cmdName,
        index = idx,
        dead  = false,
      }

      -- CONTROLE
      STATE_CONTROLE[key] = {
        side         = side,
        logiPt       = logiPt,
        logiKey      = key,
        gname        = _spawnPlatoon(side, logiPt, "controle", key),
        targetIdx    = nil,
        nextRespawn  = 0,
        waitingRunner= nil,
        initialChoices = _collectK(
          side, logiPt,
          (AUTO_CONQUEST_CFG.controle.initial_choices or 3),
          "neutral"
        ),
        usedInitial  = false,
        stuckRef     = nil,
        daCName      = nil,
      }

      -- DA_Controle (escorte)
      do
        local cfg     = AUTO_CONQUEST_CFG.da_controle or AUTO_CONQUEST_CFG.da_assault
        local campCfg = (side==coalition.side.BLUE) and cfg.blue or cfg.red
        local ctry    = _country(side)
        local ap      = _leaderPoint(STATE_CONTROLE[key].gname) or logiPt
        local dx,dz   = ap.x-logiPt.x, ap.z-logiPt.z
        local ux,uz,_ = _norm(dx,dz)
        local back    = cfg.spawn_offset_m or 20
        local sx,sz   = ap.x - ux*back, ap.z - uz*back
        local utype   = _pickWeightedType(campCfg.types)
        local skill   = _pickSkill(cfg.skill)

        local gnameDAc = _name(_sideKey(side).."_DA_CONTROLE_GRP")
        coalition.addGroup(ctry, Group.Category.GROUND, {
          visible=true, lateActivation=false,
          route={points={{
            x=sx, y=sz,
            type="Turning Point", action="Off Road",
            speed=_kmh2ms(cfg.speed_kmh or 35),
            task={id="ComboTask",params={tasks={}}}
          }}},
          tasks={},
          units={{
            type=utype, name=gnameDAc.."_U1",
            x=sx, y=sz,
            heading=math.atan2(ux,uz), skill=skill
          }},
          name=gnameDAc
        })

        STATE_CONTROLE[key].daCName = gnameDAc
        STATE_DA_CONTROLE[key] = {
          side       = side,
          logiPt     = logiPt,
          gname      = gnameDAc,
          controleKey= key,
        }
      end

timer.scheduleFunction(
  function()
    _issueOrder(STATE_CONTROLE[key], "neutral")
  end,
  {},
  AUTO_CONQUEST_START.controle
)

      -- ASSAULT
      STATE_ASSAULT[key] = {
        side         = side,
        logiPt       = logiPt,
        logiKey      = key,
        gname        = _spawnPlatoon(side, logiPt, "assault", key),
        targetIdx    = nil,
        nextRespawn  = 0,
        waitingRunner= nil,
        reservedIdx  = nil,
        initialChoices = _collectK(
          side, logiPt,
          (AUTO_CONQUEST_CFG.assault.initial_choices or 3),
          "enemy", RESERVED_ASSAULT[_sideKey(side)]
        ),
        usedInitial  = false,
        stuckRef     = nil,
        daName       = nil,
      }

      -- DA_Assault (escorte)
      do
        local cfg     = AUTO_CONQUEST_CFG.da_assault
        local campCfg = (side==coalition.side.BLUE) and cfg.blue or cfg.red
        local ctry    = _country(side)
        local ap      = _leaderPoint(STATE_ASSAULT[key].gname) or logiPt
        local dx,dz   = ap.x-logiPt.x, ap.z-logiPt.z
        local ux,uz,_ = _norm(dx,dz)
        local back    = cfg.spawn_offset_m or 20
        local sx,sz   = ap.x - ux*back, ap.z - uz*back
        local utype   = _pickWeightedType(campCfg.types)
        local skill   = _pickSkill(cfg.skill)

        local gnameDA = _name(_sideKey(side).."_DA_ASSAULT_GRP")
        coalition.addGroup(ctry, Group.Category.GROUND, {
          visible=true, lateActivation=false,
          route={points={{
            x=sx, y=sz,
            type="Turning Point", action="Off Road",
            speed=_kmh2ms(cfg.speed_kmh or 35),
            task={id="ComboTask",params={tasks={}}}
          }}},
          tasks={},
          units={{
            type=utype, name=gnameDA.."_U1",
            x=sx, y=sz,
            heading=math.atan2(ux,uz), skill=skill
          }},
          name=gnameDA
        })

        STATE_ASSAULT[key].daName = gnameDA
        STATE_DA_ASSAULT[key] = {
          side       = side,
          logiPt     = logiPt,
          gname      = gnameDA,
          assaultKey = key,
        }
      end

timer.scheduleFunction(
  function()
    _issueOrder(STATE_ASSAULT[key], "enemy")
  end,
  {},
  AUTO_CONQUEST_START.assault
)


      -- RECO + ASSAULT d'escorte
      STATE_RECO[key] = {
        side                = side,
        logiPt              = logiPt,
        logiKey             = key,
        gname               = nil,
        targetIdx           = nil,
        nextRespawn         = 0,
        assaultName         = nil,  -- ASSAULT d’escorte du RECO
        nextAssaultRespawn  = 0,
      }

      do
        -- Spawn du RECO
        local gnameReco, idxReco = _spawnReco(side, logiPt, key)
        STATE_RECO[key].gname     = gnameReco
        STATE_RECO[key].targetIdx = idxReco

        -- Spawn immédiat d'un 2e ASSAULT pour accompagner le RECO
        local gnameAss = _spawnPlatoon(side, logiPt, "assault", key)
        STATE_RECO[key].assaultName        = gnameAss
        STATE_RECO[key].nextAssaultRespawn = 0

        if gnameAss and idxReco and BATTLEFIELD_POINTS and BATTLEFIELD_POINTS[idxReco] then
          local cen  = BATTLEFIELD_POINTS[idxReco]
          local goal = _attackPointOnCircle(cen, logiPt)
          local vAss = (AUTO_CONQUEST_CFG.assault and AUTO_CONQUEST_CFG.assault.speed_kmh) or 40
          _assignRouteToPoint(gnameAss, goal, vAss)
        end
      end


      -- DA fixe : premiers objectifs neutres, départ à AUTO_CONQUEST_START.da
      local firstTargets = _collectK(side, logiPt, 3, "neutral")
      _spawnDAForLogi(side, logiPt, firstTargets, AUTO_CONQUEST_START.da)


      --[[ ARTY DESACTIVE
      -- ARTY : navette entre une position batterie (à 800 m du LOGI) et le LOGI voisin
      local logiCenter = { x = p.x, z = p.z }

      -- "other" = LOGI ami le plus proche (ou soi-même s'il est seul)
      local list  = (side==coalition.side.BLUE) and (LOGI_BLUE_POINTS or {}) or (LOGI_RED_POINTS or {})
      local other = logiCenter
      do
        local best, bd = nil, 1e9
        for _,q in ipairs(list) do
          local d = _d2(logiCenter, q)
          if d > 5 and d < bd then
            bd   = d
            best = q
          end
        end
        other = best or logiCenter
      end

      -- Position de la batterie d'artillerie : à 800 m du centre LOGI
      local artyHome = (function()
        local dx, dz = 0, 0
        if other and (other.x ~= logiCenter.x or other.z ~= logiCenter.z) then
          dx, dz = other.x - logiCenter.x, other.z - logiCenter.z
        elseif BATTLEFIELD_POINTS and #BATTLEFIELD_POINTS > 0 then
          dx, dz = BATTLEFIELD_POINTS[1].x - logiCenter.x, BATTLEFIELD_POINTS[1].z - logiCenter.z
        else
          local a = RNGf() * 2 * math.pi
          dx, dz = math.cos(a), math.sin(a)
        end
        local ux, uz, _ = _norm(dx, dz)
        return {
          x = logiCenter.x + ux * 800,
          z = logiCenter.z + uz * 800,
        }
      end)()

      local aKey  = string.format("ARTY_%s_%d_%d", _sideKey(side), math.floor(p.x), math.floor(p.z))
      local gname = _spawnArty(side, artyHome)
      ARTY_STATE[aKey] = {
        side        = side,
        home        = artyHome,
        other       = other,
        gname       = gname,
        leg         = 1,
        busyUntil   = 0,
        nextRespawn = 0,
        order       = nil,
        lockedRunner= nil,
        logiKey     = key,
      }
      ARTY_LIST[_sideKey(side)][#ARTY_LIST[_sideKey(side)]+1] = aKey

      timer.scheduleFunction(
        function()
          _assignRouteToPoint(gname, other, AUTO_CONQUEST_CFG.arty.speed_kmh or 20)
        end,
        {},
        AUTO_CONQUEST_START.arty
      )
      --]] -- FIN ARTY DESACTIVE


    end
  end

  setupSide(coalition.side.BLUE, LOGI_BLUE_POINTS or {})
  setupSide(coalition.side.RED,  LOGI_RED_POINTS  or {})

   timer.scheduleFunction(_tickControle, {}, timer.getTime()+5.0)
  timer.scheduleFunction(_tickAssault,  {}, timer.getTime()+5.1)

  timer.scheduleFunction(_tickReco,     {}, timer.getTime()+5.25)
  -- timer.scheduleFunction(_tickArty,     {}, timer.getTime()+5.3)  -- ARTY DESACTIVE
end
