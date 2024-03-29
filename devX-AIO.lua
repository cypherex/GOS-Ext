
local Heroes = {"Swain","RekSai","Elise","Syndra","Gangplank","Gnar","Zeri","LeeSin","Qiyana","Karthus","Rengar", "Soraka", "Mordekaiser","Nidalee","Ziggs","Kindred","Viktor"}

if not table.contains(Heroes, myHero.charName) then 
    print("DevX AIO does not support " .. myHero.charName)
    return 
end

require "DamageLib"
require "MapPositionGOS"
require "GGPrediction"
require "PremiumPrediction"

if not _G.SDK then
    print("GGOrbwalker is not enabled. DevX-AIO will exit")
    return
end
-------------------------------------------------
-- Variables
------------

-- Spell data for GGPrediction

-- Reference variables
local GameTurret = Game.Turret
local GameTurretCount = Game.TurretCount
local GameHeroCount     = Game.HeroCount
local GameHero          = Game.Hero
local GameMinionCount     = Game.MinionCount
local GameMinion          = Game.Minion

local GameObjectCount     = Game.ObjectCount
local GameObject       = Game.Object
local TableInsert       = _G.table.insert

local orbwalker         = _G.SDK.Orbwalker
local HealthPrediction         = _G.SDK.HealthPrediction



--------------------------------------------------
-- General Functions
--------------------
local function isSpellReady(spell)
    return  myHero:GetSpellData(spell).currentCd == 0 and myHero:GetSpellData(spell).level > 0 and Game.CanUseSpell(spell) == 0
end

local function getDistanceSqr(Pos1, Pos2)
    local Pos2 = Pos2 or myHero.pos
    local dx = Pos1.x - Pos2.x
    local dz = (Pos1.z or Pos1.y) - (Pos2.z or Pos2.y)
    return dx^2 + dz^2
end

local function getDistance(Pos1, Pos2)
    return math.sqrt(getDistanceSqr(Pos1, Pos2))
end

local function getEnemyHeroes()
    local EnemyHeroes = {}
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy and not Hero.dead then
            table.insert(EnemyHeroes, Hero)
        end
    end
    return EnemyHeroes
end



local function isValid(unit)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        return true;
    end
    return false;
end

local function getEnemyHeroesWithinDistanceOfUnit(location, distance)
    local EnemyHeroes = {}
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy and not Hero.dead and Hero.pos:DistanceTo(location) < distance then
            table.insert(EnemyHeroes, Hero)
        end
    end
    return EnemyHeroes
end


local function getAllyHeroesWithinDistanceOfUnit(location, distance)
    local Allies = {}
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if not Hero.isEnemy and not Hero.dead and Hero.pos:DistanceTo(location) < distance then
            table.insert(Allies, Hero)
        end
    end
    return Allies
end

local function ClosestToMouse(p1, p2) 
	if p1:DistanceTo(mousePos) > p2:DistanceTo(mousePos) then return p2 else return p1 end
end

local function GetClosestEnemyToMouse(maxDistance)
    local closest = nil
    local closestDistance = 1000000000
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        local distanceToMouse = Hero.pos:DistanceTo(Vector(mousePos))
        if Hero.isEnemy and not Hero.dead and distanceToMouse < maxDistance then
            if closest == nil then
                closest = Hero.pos
            else
                if distanceToMouse < closest then
                    closest = Hero.pos
                    closestDistance = distanceToMouse
                end
            end
            
        end
    end
    return closest
end

local function getEnemyMinionsWithinDistanceOfLocation(location, distance)
    local EnemyMinions = {}
    for i = 1, Game.MinionCount() do
        local minion = Game.Minion(i)
        if minion and minion.isEnemy and not minion.dead and minion.pos:DistanceTo(location) < distance then
            table.insert(EnemyMinions, minion)
        end
    end
    return EnemyMinions
end

local function getAOEMinion(maxRange, abilityRadius) 
    local bestCount = 0
    local bestPosition = nil
    for i = 1, GameMinionCount() do
        local minion1 = GameMinion(i)
        local count = 0
        if minion1 and not minion1.dead and minion1.isEnemy and myHero.pos:DistanceTo(minion1.pos) < maxRange then 
            local count = #getEnemyMinionsWithinDistanceOfLocation(minion1.pos, abilityRadius)
            if count > bestCount then
                bestCount = count
                bestPosition = minion1.pos
            end
        end
    end
    return bestPosition, bestCount
end

local function getWardSlot()
    local WardKey = {[ITEM_1] = HK_ITEM_1, [ITEM_2] = HK_ITEM_2,[ITEM_3] = HK_ITEM_3, [ITEM_4] = HK_ITEM_4, [ITEM_5] = HK_ITEM_5, [ITEM_6] = HK_ITEM_6, [ITEM_7] = HK_ITEM_7}				
   
    -- 2055 pink ward, 3340 normal
    for slot = ITEM_1, ITEM_7 do
		if myHero:GetItemData(slot).itemID and myHero:GetItemData(slot).itemID == 3340 and myHero:GetSpellData(slot).ammo > 0  then
			return slot, WardKey[slot]
		end
    end
    for slot = ITEM_1, ITEM_7 do
		
		if myHero:GetItemData(slot).itemID and myHero:GetItemData(slot).itemID == 2055  then
            return slot, WardKey[slot]
		end
    end
    return nil, nil
end

local function getFlashSlot()
    if myHero:GetSpellData(SUMMONER_1).name:find("Flash") and isSpellReady(SUMMONER_1) then
        return SUMMONER_1, HK_SUMMONER_1
    elseif myHero:GetSpellData(SUMMONER_2).name:find("Flash") and isSpellReady(SUMMONER_2)  then
        return  SUMMONER_2, HK_SUMMONER_2
    end
    return nil, nil
end
local function ClosestPointOnLineSegment(p, p1, p2)
    local px = p.x
    local pz = p.z
    local ax = p1.x
    local az = p1.z
    local bx = p2.x
    local bz = p2.z
    local bxax = bx - ax
    local bzaz = bz - az
    local t = ((px - ax) * bxax + (pz - az) * bzaz) / (bxax * bxax + bzaz * bzaz)
    if (t < 0) then
        return p1, false
    end
    if (t > 1) then
        return p2, false
    end
    return {x = ax + t * bxax, z = az + t * bzaz}, true
end

local function getEnemyHeroesWithinDistance(distance)
    return getEnemyHeroesWithinDistanceOfUnit(myHero.pos, distance)
end
local function doesMyChampionHaveBuff(buffName)
    for i = 0, myHero.buffCount do
        local buff = myHero:GetBuff(i)
        if buff.name == buffName and buff.count > 0 then 
            return true
        end
    end
    return false
end

local function getChampionBuffCount(buffName)
    for i = 0, myHero.buffCount do
        local buff = myHero:GetBuff(i)
        if buff.name == buffName then 
            return buff.count
        end
    end
    return -1
end

local function printChampionBuffs(champ)
    for i = 0, champ.buffCount do
        local buff = champ:GetBuff(i)
        if buff.count > 0 then 
            print(string.format("%s - stacks: %f count %f",buff.name, buff.stacks, buff.count))
        end
    end
end

local function doesThisChampionHaveBuff(target, buffName)
    if not target then
        return false
    end
    for i = 0, target.buffCount do
        local buff = target:GetBuff(i)
        if buff.name == buffName and buff.count > 0 then 
            return true
        end
    end
    return false
end

local function isTargetImmobileOrSlowed(target)
    local buffTypeList = {5, 7, 8, 10, 11, 12, 22, 23, 25, 30, 33, 35} 
	for i = 0, target.buffCount do
        local buff = target:GetBuff(i)
        for _, buffType in pairs(buffTypeList) do
		    if buff.type == buffType and buff.count > 0 then
                return true, buff.duration
            end
		end
	end
	return false, 0
end

local function isTargetImmobile(target)
    local buffTypeList = {5, 8, 12, 22, 23, 25, 30, 35} 
	for i = 0, target.buffCount do
        local buff = target:GetBuff(i)
        for _, buffType in pairs(buffTypeList) do
		    if buff.type == buffType and buff.count > 0 then
                return true, buff.duration
            end
		end
	end
	return false, 0
end

local function getPrediction(spellData, target)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)

    return pred
end

local function canSpellHitNormal(spellData, target)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)
    local canHit = pred:CanHit(GGPrediction.HITCHANCE_COLLISION)
    print(not canHit)
    return { canHit = not canHit, castPos = pred.CastPosition }
end

local function castSpell(spellData, hotkey, target)

    local castDetails = canSpellHitNormal(spellData, target)
    if castDetails.canHit then
        if myHero.pos:DistanceTo(pred.CastPosition) <= spellData.Range + 15 then
            Control.CastSpell(hotkey, pred.CastPosition)	
            
        end
        --print("Can hit ", spellData)
        return true
    else
        --print("Cant hit ", spellData)
    end
    return false
end

local function castSpellHigh(spellData, hotkey, target)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)
    if pred:CanHit(GGPrediction.HITCHANCE_HIGH) then
        Control.CastSpell(hotkey, pred.CastPosition)	
    end
end
local function castSpellExtended(spellData, hotkey, target, extendAmount)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)
    if pred:CanHit(GGPrediction.HITCHANCE_NORMAL) then
        local castPos = Vector(pred.CastPosition):Extended(Vector(myHero.pos), extendAmount) 
        Control.CastSpell(hotkey, castPos)	
    end
end

local function isBeingAttackedByTower()
    for i = 1, GameTurretCount() do
        local turret = GameTurret(i)
        if turret.isEnemy and not turret.dead and not turret.isImmortal then
            if turret.targetID == myHero.networkID then
                return true
            end
        end
    end
    return false
end

local function getTowerDamage()
    local minutes = Game.Timer() / 60
    return 9 * math.floor(minutes - 1.5) + 170
end


-- credit to pussy qiyana
local function Rotate(startPos, endPos, height, theta)
    local dx, dy = endPos.x - startPos.x, endPos.z - startPos.z
    local px, py = dx * math.cos(theta) - dy * math.sin(theta), dx * math.sin(theta) + dy * math.cos(theta)
    return Vector(px + startPos.x, height, py + startPos.z)
end

-- credit to pussy qiyana
local function FindClosestWall(mode)
    local startPos, mPos, height = Vector(myHero.pos), Vector(mousePos), myHero.pos.y
    for i = 100, 2000, 100 do -- search range
        local endPos = startPos:Extended(mPos, i)
        for j = 20, 360, 20 do -- angle step
            local testPos = Rotate(startPos, endPos, height, math.rad(j))
            if testPos:ToScreen().onScreen then 
                if MapPosition:inWall(testPos) then
                    return testPos
                end
            end
        end
    end
    return nil
end


local function ClosestPointOnLineSegment(p, p1, p2)
    local px = p.x
    local pz = p.z
    local ax = p1.x
    local az = p1.z
    local bx = p2.x
    local bz = p2.z
    local bxax = bx - ax
    local bzaz = bz - az
    local t = ((px - ax) * bxax + (pz - az) * bzaz) / (bxax * bxax + bzaz * bzaz)
    if (t < 0) then
        return p1, false
    end
    if (t > 1) then
        return p2, false
    end
    return {x = ax + t * bxax, z = az + t * bzaz}, true
end

local _nextVectorCast = Game.Timer()
local _nextSpellCast = Game.Timer()
local _vectorMousePos = mousePos
function VectorCast(startPos, endPos, hotkey)
	if _nextSpellCast > Game.Timer() then return end	
	if _nextVectorCast > Game.Timer() then return end

	_nextVectorCast = Game.Timer() + 2
	_nextSpellCast = Game.Timer() + .25
    _vectorMousePos = mousePos

	Control.SetCursorPos(startPos)	
    orbwalker:SetMovement(false)
    orbwalker:SetAttack(false)
    
	DelayAction(function()Control.KeyDown(hotkey) end,.05)
	DelayAction(function()Control.SetCursorPos(endPos) end,.1)
	DelayAction(function()
        Control.KeyUp(hotkey) 
        orbwalker:SetMovement(true)
        orbwalker:SetAttack(true)
    end,.15) 
	DelayAction(function()Control.SetCursorPos(_vectorMousePos) end,.15)
end
--------------------------------------------------
-- Swain
--------------
class "Swain"
    local qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Width = 100, Range = 750, Speed = 5000, Collision = false}
    local eSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Width = 60, Range = 850, Speed = 935, Collision = false}
    local wSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 1.5, Width = 100, Range = 5500, Speed = 935, Collision = false}
        
    function Swain:__init()	     
        print("devX-Swain Loaded") 
        self:LoadMenu()   
        
        
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)   
        Callback.Add('WndMsg', function(msg, wParam) self:onWndMsg(msg, wParam) end); 
    end

    --
    -- Menu 
    function Swain:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devSwain", name = "devSwain v1.0"})
        
        
        self.Menu:MenuElement({type = MENU, id = "ManualW", name = "Manual [W] - Z Key"})
        -- ComboMenu  
        self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo Mode"})
            self.Menu.Combo:MenuElement({id = "UseQ", name = "[Q]", value = true})
            self.Menu.Combo:MenuElement({id = "UseE", name = "[E]", value = true})

        
        self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass Mode"})
            self.Menu.Harass:MenuElement({id = "UseQ", name = "[Q]", value = true, toggle = true, key = string.byte("T")})

        -- Auto Menu    
        self.Menu:MenuElement({type = MENU, id = "Auto", name = "Auto"})
            self.Menu.Auto:MenuElement{{id= "PullRoot", name="Pull rooted enemies", value = true}}
            self.Menu.Auto:MenuElement({id = "W", name = "Use W on Root", value = true})
            self.Menu.Auto:MenuElement({id = "WCC", name = "W on Stun/Slow", value = true})
        
            
        self.Menu:MenuElement({type = MENU, id = "Draw", name = "Draw"})
            self.Menu.Draw:MenuElement({id = "Q", name = "[Q] Range", value = true})
            self.Menu.Draw:MenuElement({id = "E", name = "[E] Range", value = true})
    end

    function Swain:Draw()
        if myHero.dead then return end
                                                       
        if self.Menu.Draw.Q:Value() then
            Draw.Circle(myHero, qSpellData.Range, 1, Draw.Color(225, 225, 0, 10))
        end
       	    
        if self.Menu.Draw.E:Value() then
            Draw.Circle(myHero, eSpellData.Range, 1, Draw.Color(225, 0, 0, 10))
        end
       		
    end


    --------------------------------------------------
    -- Callbacks
    ------------

    
    function Swain:delayAndDisableOrbwalker(delay) 
        _nextSpellCast = Game.Timer() + delay
        orbwalker:SetMovement(false)
        orbwalker:SetAttack(false)
        DelayAction(function() 
            orbwalker:SetMovement(true)
            orbwalker:SetAttack(true)
        end, delay)
    end

    function Swain:manualW()
        local target = GetClosestEnemyToMouse(1000)
        
        if target == nil  then return end
        if target:DistanceTo(myHero.pos) > wSpellData.Range then return end

        local enemyPos = target:ToMM()
        Control.CastSpell(HK_W, enemyPos.x, enemyPos.y)
        self:delayAndDisableOrbwalker(0.5)
        
    end

    function Swain:onWndMsg(msg, wParam)
        if wParam == 90 then
            self:manualW()
        end
    end

    function Swain:onTickEvent()
        wSpellData.Range = myHero:GetSpellData(_W).range

        if isSpellReady(_W) then
            self:rootCheck()
        end
        
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
    end
    ----------------------------------------------------
    -- Combat Functions
    ---------------------
    function Swain:rootCheck()
        
        local enemies = getEnemyHeroes()
        

        for i, enemy in pairs(enemies) do
            if isValid(enemy) and not enemy.dead  then

                local distance = getDistance(myHero.pos, enemy.pos)
                local isImmobile, duration = isTargetImmobile(enemy)
                isImmobile = isImmobile or (not self.Menu.Auto.WCC:Value() and isTargetImmobileOrSlowed())

                if isSpellReady(_W) and self.Menu.Auto.W:Value() and distance <  wSpellData.Range and isImmobile then
                    local enemyPos = enemy.pos:ToMM()
                    Control.CastSpell(HK_W, enemyPos.x, enemyPos.y)
                    self:delayAndDisableOrbwalker(0.5)
                    return
                end
                
                if distance < 1125 and isSpellReady(_E) and doesThisChampionHaveBuff(enemy, "swaineroot") then
                    Control.CastSpell(HK_E)
                end
            end
        end


    end

    ----------------------------------------------------
    -- Combat Modes
    ---------------------

    function Swain:CastE1(target)
        local spellData = eSpellData
        local pred = GGPrediction:SpellPrediction(spellData)
        pred:GetPrediction(target, myHero)
        if pred:CanHit(GGPrediction.HITCHANCE_NORMAL) then
            local distanceVector =(pred.CastPosition - myHero.pos):Normalized()
            local castPos =  myHero.pos + distanceVector * eSpellData.Range
            
            local _, _, collisionCount = GGPrediction:GetCollision(
                castPos, 
                pred.CastPosition, 
                600, 
                eSpellData.Delay, 
                eSpellData.Width, 
                {GGPrediction.COLLISION_MINION}
            )
            if collisionCount == 0 then
                Control.CastSpell(HK_E, castPos)	
            end
        end
    end

    function Swain:Combo()
        if _nextSpellCast > Game.Timer() then return end
        local target = _G.SDK.TargetSelector:GetTarget(1200, _G.SDK.DAMAGE_TYPE_MAGICAL);
            
        if target then
            local distance = getDistance(myHero.pos, target.pos)
            if isSpellReady(_E) and self.Menu.Combo.UseE:Value() then
                if distance < eSpellData.Range + 100  then
                    self:CastE1(target)
                end
            end

            if isSpellReady(_Q) and self.Menu.Combo.UseQ:Value() then
                if distance < qSpellData.Range + 100 then
                    castSpell(qSpellData, HK_Q, target)
                end
            end
        end
    end

    function Swain:Harass()
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
            
        if target then
            if isSpellReady(_Q) and self.Menu.Harass.UseQ:Value() then
                local distance = getDistance(myHero.pos, target.pos)

                
                if distance < qSpellData.Range + 100 then
                    castSpell(qSpellData, HK_Q, target)
                end
            end
        end
    end

----------------------------------------------------
-- RekSai
--------------------- 
class "RekSai"
    local QspellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.3, Speed = 4000, Range = 1625, Radius = 60, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    local isTunnelling = false
    local isUnderground = false

    function RekSai:__init()	     
        print("devX-RekSai Loaded") 

        self:LoadMenu()   
        
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)   
        orbwalker:OnPostAttack(function(...) self:onPostAttack(...) end) 
    end

    --
    -- Menu 
    function RekSai:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devRekSai", name = "devX-Reksai v1.0"})
                
        -- ComboMenu  
        self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo Mode"})
            self.Menu.Combo:MenuElement({id = "AttackReset", name = "Use Q&E on Attack Reset", value = true})
            self.Menu.Combo:MenuElement({id = "UseQ", name = "[Q]", value = true})
            self.Menu.Combo:MenuElement({id = "UseE", name = "[E]", value = true})
            self.Menu.Combo:MenuElement({id = "UseW", name = "[W] to unburrow", value = true})

        
        self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass Mode"})

        -- Auto Menu
        self.Menu:MenuElement({type = MENU, id = "Auto", name = "Auto"})
        
            
        self.Menu:MenuElement({type = MENU, id = "Draw", name = "Draw"})
            self.Menu.Draw:MenuElement({id = "Q", name = "Underground [Q] Range", value = true})
    end

    function RekSai:Draw()
        if myHero.dead then return end
                                                    
        if self.Menu.Draw.Q:Value() then
            Draw.Circle(myHero, QspellData.Range, 1, Draw.Color(225, 225, 0, 10))
        end
    end


    --------------------------------------------------
    -- Callbacks
    ------------

    function RekSai:onPostAttack(args)
        if self.Menu.Combo.AttackReset:Value() then
            local target = orbwalker:GetTarget();
        
            if isSpellReady(_Q) and target and self.Menu.Combo.UseQ:Value()  then
                Control.CastSpell(HK_Q, target)
                Control.Attack(target)
                return
            end
            
            if isSpellReady(_E) and target and self.Menu.Combo.UseE:Value() and not (myHero.mana > 80 and myHero.mana < 90) then
                local distance = getDistance(myHero.pos, target.pos)
                if distance < 350 then
                    Control.CastSpell(HK_E, target)
                end
            end
        end
    end

    function RekSai:onTickEvent()
        
        self:updateBuffs()
        
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] and not isInTunnelling then
            self:Combo()
        end

    end
    ----------------------------------------------------
    -- Combat Functions
    ---------------------

    function RekSai:updateBuffs()
        -- Check if currently burrowed
        if doesMyChampionHaveBuff("RekSaiW") then
            isUnderground = true
        else
            isUnderground = false
        end
        
        -- Check if currently tunnelling
        if doesMyChampionHaveBuff("reksaitunneltime2") or doesMyChampionHaveBuff("RekSaiEBurrowed") then
            isInTunnelling = true
        else
            isInTunnelling = false
        end
    end

    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    function RekSai:Combo()
        local target = _G.SDK.TargetSelector:GetTarget(1600, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if isUnderground and target then
            local distance = getDistance(myHero.pos, target.pos)
            if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < 1600 and self.Menu.Combo.UseQ:Value() then
                castSpell(QspellData, HK_Q, target)
            end

            if distance < 285 and isSpellReady(_W) and self.Menu.Combo.UseW:Value() then
                Control.CastSpell(HK_W)
            end
        elseif not self.Menu.Combo.AttackReset:Value() and target then
            target = _G.SDK.TargetSelector:GetTarget(500, _G.SDK.DAMAGE_TYPE_MAGICAL)
            if isSpellReady(_Q) and target and self.Menu.Combo.UseQ:Value()  then
                Control.CastSpell(HK_Q, target)
                Control.Attack(target)
                return
            end
             
            if isSpellReady(_E) and target and self.Menu.Combo.UseE:Value() and not (myHero.mana > 80 and myHero.mana < 90) then
                local distance = getDistance(myHero.pos, target.pos)
                if distance < 350 then
                    Control.CastSpell(HK_E, target)
                end
            end
            
        end
    end


    function UltimateMode()
        if isSpellReady(_R) then
            for i, enemy in pairs(enemies) do
                if isValid(enemy) and not enemy.dead  then

                    if doesThisChampionHaveBuff(enemy, "reksairprey") then
                        
                        local distance = getDistance(myHero.pos, enemy.pos)
                    end
                end
            end
        end
    end

    function RekSai:Harass()
        
    end


    class "Elise"
  
    function Elise:__init()	     
        print("DevX-Elise Loaded") 

        self:LoadMenu()   
        
        self.eSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.3, Speed = 1600, Range = 1075, Radius = 55, Width=55, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)   
        orbwalker:OnPostAttack(function(...) self:onPostAttack(...) end )
        
    end

    function Elise:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devElise", name = "DevX-Elise v1.0"})
        
        self.Menu:MenuElement({type = MENU, id = "ELogic", name = "Rappel Logic"})
            self.Menu.ELogic:MenuElement({TYPE = _G.SPACE, name = "Auto Rappel will be active if being attacked by a tower that can kill"})
            self.Menu.ELogic:MenuElement({id = "HP", name = "Percent HP", value = 25, min = 0, max = 100})

        self.Menu:MenuElement({id = "AttackReset", name = "Use Attack Resets and Spacing", value = true, toggle = true})
        self.Menu:MenuElement({id = "Clear", name = "Lane / JG Clear - Use Abilities", value = true, toggle = true, key = string.byte("T")})
    end

    function Elise:Draw()
        if myHero.dead then return end
    end


    --------------------------------------------------
    -- Callbacks
    ------------

    function Elise:onPostAttack(args)
        if not self.Menu.AttackReset:Value() then return end
        if not self.Menu.Clear:Value() and (orbwalker.Modes[_G.SDK.ORBWALKER_MODE_JUNGLECLEAR] or orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR]) then
            return
        end

        local target = orbwalker:GetTarget();
        
        if target then
            if self.isInSpiderForm then
                
                if isSpellReady(_W) then
                    Control.CastSpell(HK_W, target)
                    orbwalker:__OnAutoAttackReset()
                    return
                end
                
                if isSpellReady(_Q) then
                    Control.CastSpell(HK_Q, target)
                end  
            end
            
        end
    end

    function Elise:onTickEvent()
        self:updateBuffs()
        self:autoRappel()
        
        if orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end
        if self.Menu.Clear:Value() and (orbwalker.Modes[_G.SDK.ORBWALKER_MODE_JUNGLECLEAR] or orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR]) then
            self:Clear()
        end
        
    end
    ----------------------------------------------------
    -- Combat Functions
    ---------------------

    function Elise:updateBuffs()
        self.isInSpiderForm = doesMyChampionHaveBuff("EliseR")
        self.isRapelled = myHero:GetSpellData(_Q).name == "EliseSpideElnitial"
    end

    function Elise:autoRappel()
        if self.isRapelled then return end
        
        local shouldRappel = false

        if isBeingAttackedByTower() then
            local towerDamage = getTowerDamage()
            if towerDamage >= myHero.health then
                shouldRappel = true
            end
        end

        local percentHp = myHero.health / myHero.maxHealth
        if percentHp < self.Menu.ELogic.HP:Value() / 100 and #getEnemyHeroesWithinDistance(800) >= 1 then
            shouldRappel = true
        end

        if shouldRappel then
            if self.isInSpiderForm then
                Control.CastSpell(HK_E)
            else
                Control.CastSpell(HK_R)
                Control.CastSpell(HK_E)
            end
        end
    end

    
    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    function Elise:Combo()
        
        local target = orbwalker:GetTarget(1200, _G.SDK.DAMAGE_TYPE_MAGICAL)
        if target then
            if not self.isInSpiderForm then
                if isSpellReady(_E) and myHero.pos:DistanceTo(target.pos) <= 1075 then
                    castSpell(self.eSpellData, HK_E, target)
                end
                if orbwalker:CanAttack(target) then
                    Control.Attack(target)
                end
                if isSpellReady(_Q)  and myHero.pos:DistanceTo(target.pos) <= 750 then
                    Control.CastSpell(HK_Q, target)
                    print("Cast Qx")
                end
                
                
                
                if isSpellReady(_W) and myHero.pos:DistanceTo(target.pos) <= 950 then
                    Control.CastSpell(HK_W, target)
                    print("Cast W")
                end
                if isSpellReady(_R) and not isSpellReady(_Q) and not isSpellReady(_W) then
                    Control.CastSpell(HK_R)
                    if myHero.pos:DistanceTo(target.pos) >= 300 then
                        Control.CastSpell(HK_Q)
                        print("Casting Q2")
                    end
                    self.isInSpiderForm = true
                end
            end 
            if self.isInSpiderForm then
                
                
                if isSpellReady(_Q) then
                    Control.CastSpell(HK_Q, target)
                    print("Casting Q")
                end  
                if not self.Menu.AttackReset:Value() then
                    
                    if isSpellReady(_W) then
                        Control.CastSpell(HK_W, target)
                        orbwalker:__OnAutoAttackReset()
                    end
                end
            end 
        end
    end


    function Elise:Clear()
        local target = orbwalker:GetTarget()
        if target then
            if not self.isInSpiderForm then
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 475 then
                    Control.CastSpell(HK_Q, target)
                end
                if isSpellReady(_W) and myHero.pos:DistanceTo(target.pos) <= 950 then
                    Control.CastSpell(HK_W, target)
                end
                if isSpellReady(_R) and not isSpellReady(_Q) and not isSpellReady(_W) then
                    Control.CastSpell(HK_R)
                    self.isInSpiderForm = true
                end
            end 
            if self.isInSpiderForm then
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 475 then
                    Control.CastSpell(HK_Q, target)
                end
                if not self.Menu.AttackReset:Value() then
                    if isSpellReady(_W) then
                        Control.CastSpell(HK_W, target)
                    end
                end
            end
        end
    end

--------------------------------------------------
-- Syndra
--------------
class "Syndra"
        
    function Syndra:__init()	     
        print("devX-Syndra Loaded") 
        self:LoadMenu()   
        
        self.qSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.65, Radius = 180, Range = 800, Speed = math.huge, Collision = false}
        self.wSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.25, Radius = 200, Range = 925, Speed = 1450, Collision = false}

        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)    
    end

    --
    -- Menu 
    function Syndra:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devSyndra", name = "DevX Syndra v1.0"})
        -- ComboMenu  

        self.Menu:MenuElement({type = MENU, id = "BlockR", name = "Ultimate Blacklist"})
            DelayAction(function()
                for i, Hero in pairs(getEnemyHeroes()) do
                    self.Menu.BlockR:MenuElement({id = Hero.charName, name = "Block Ult on: "..Hero.charName, value = false})		
                end		
            end,0.2)
        
        self.Menu:MenuElement({id = "Clear", name = "Q Clear", value = true, toggle = true, key = string.byte("T")})
        self.Menu:MenuElement({id = "WHarrass", name = "W Harass", value = true, toggle = true, key = string.byte("G")})
        self.Menu:MenuElement({id = "AntiMelee", name = "Anti-Melee Range", value = 365, min = 0, max = 500, step = 1})
        self.Menu:MenuElement({id = "DrawAntiMelee", name = "Draw Anti-Melee Range", value = true, toggle = true})
                
    end

    function Syndra:Draw()
        
        local hero2d = myHero.pos2D
        if self.Menu.Clear:Value() then
            Draw.Text("Lane Clear Enabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 0, 255, 0))
        else
            Draw.Text("Lane Clear Disabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 255, 0, 0))
        end
        
        if self.Menu.WHarrass:Value() then
            Draw.Text("W Harass Enabled [G]", 15, hero2d.x - 30, hero2d.y + 50, Draw.Color(255, 0, 255, 0))
        else
            Draw.Text("W Harass  Disabled [G]", 15, hero2d.x - 30, hero2d.y + 50, Draw.Color(255, 255, 0, 0))
        end
        if self.Menu.DrawAntiMelee:Value() then
            
            Draw.Circle(myHero.pos, self.Menu.AntiMelee:Value(), 1, Draw.Color(255, 0, 0, 10))
        end
    end


    --------------------------------------------------
    -- Callbacks
    ------------
    function Syndra:onTickEvent()

        if isSpellReady(_Q) then
            self:AutoQ()
        end
        self:AutoUlt()
        self:AntiMelee()
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] and self.Menu.Clear:Value() then
            self:LaneClear()
        end
    end
    ----------------------------------------------------
    -- Combat Functions
    ---------------------
 
    function Syndra:castQE(target)
        local pos = myHero.pos + (target.pos - myHero.pos):Normalized() * 690
        self.isInEQ = true

        Control.CastSpell(HK_E, target.pos)
        orbwalker:SetMovement(false)
        DelayAction(
            function ()
                Control.CastSpell(HK_Q, pos)
                orbwalker:SetMovement(true)
                self.isInEQ = false
            end, 0.2
        )
    end

    function Syndra:castEQ(target, distance)
        local castPosition = myHero.pos + (target.pos - myHero.pos):Normalized() * math.min(distance*9/10, 750)

        Control.CastSpell(HK_Q, castPosition) 
        orbwalker:SetMovement(false)
        self.isInEQ = true
        DelayAction(function()
            Control.CastSpell(HK_E, target.pos)
            self.isInEQ = false
            orbwalker:SetMovement(true)
        end,0.22)	
    end

    function Syndra:castW(wObject, target)
        Control.CastSpell(HK_W, wObject)
        self.isInW = true
        DelayAction(function()
            castSpell(self.wSpellData, HK_W, target)
            self.isInW = false
        end
        , 0.05)
    end

    ----------------------------------------------------
    -- Other Functions
    ---------------------

    function Syndra:getWObject()
        for i = 1, GameObjectCount() do
            local gameObj = GameObject(i)
            if gameObj and gameObj.name == "Seed" and not gameObj.dead then
                local distance = myHero.pos:DistanceTo(gameObj.pos)
                if distance < 900 then
                    return gameObj
                end
            end
        end 

        for i = 1, GameMinionCount() do
            local minion = GameMinion(i)
            
            if minion and minion.isEnemy and not minion.dead and minion.pos:To2D().onScreen  then
                local distance = myHero.pos:DistanceTo(minion.pos)
                if distance < 900 then
                    return minion
                end
            end
        end 
        return nil
    end

    function Syndra:getEObject(targetPosition)
        for i = 1, GameObjectCount() do
            local gameObj = GameObject(i)
            if gameObj and gameObj.name == "Seed" and not gameObj.dead then
                local spellLine = ClosestPointOnLineSegment(gameObj.pos, myHero.pos, targetPosition)
                local distance = myHero.pos:DistanceTo(gameObj.pos)
                
                if distance < 700 and gameObj.pos:DistanceTo(spellLine) < 67 then
                    return gameObj
                end
            end
        end 

        return nil
    end
    function Syndra:getRDamage(target)
        return getdmg("R", target, myHero, 2) * myHero:GetSpellData(_R).ammo
    end

    function Syndra:getQDamage(target)
        if myHero:GetSpellData(_Q).level > 0 and myHero:GetSpellData(_Q).level < 5 then
            return getdmg("Q", target, myHero)
        elseif myHero:GetSpellData(_Q).level == 5 then
                return getdmg("Q", target, myHero) + (getdmg("Q", target, myHero)*0.25)
        end
        return 0
    end
    
    function Syndra:getWDamage(target)
        if myHero:GetSpellData(_W).level > 0 and myHero:GetSpellData(_W).level < 5 then
            return getdmg("W", target, myHero)
        elseif myHero:GetSpellData(_W).level == 5 then
            return getdmg("W", target, myHero) + (0.2 * (({70, 110, 150, 190, 230})[myHero:GetSpellData(_W).level] + 0.7 * myHero.ap))
        end
        return 0
    end
    
    function Syndra:getBestClearMinion()
        local bestCount = 0
        local bestPosition = nil
        for i = 1, GameMinionCount() do
            local minion1 = GameMinion(i)
            local count = 0
            if minion1 and not minion1.dead and minion1.isEnemy and myHero.pos:DistanceTo(minion1.pos) < 800 then 
                for j = 1, GameMinionCount() do
                    local minion2 = GameMinion(j)
                    if minion2 and not minion2.dead and minion2.isEnemy and minion1.pos:DistanceTo(minion2.pos) < self.qSpellData.Radius then
                        count = count + 1
                    end
                end
                if count > bestCount then
                    bestCount = count
                    bestPosition = minion1.pos
                end
            end
        end
        return bestPosition, bestCount
    end
    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    
    function Syndra:AutoUlt()
        if self.isInEQ or self.isInW or not isSpellReady(_R) then return end
        for i, enemy in pairs(getEnemyHeroes()) do
            if enemy and not enemy.dead and myHero.pos:DistanceTo(enemy.pos) <  725 then
                local notBlacklisted = self.Menu.BlockR[enemy.charName] and not self.Menu.BlockR[enemy.charName]:Value()
                local enemyCountClose = #getEnemyHeroesWithinDistance(1500)
                if notBlacklisted or enemyCountClose == 1 then
                    local damages = self:getRDamage(enemy) 
                    if enemy.health <= damages then
                        Control.CastSpell(HK_R, enemy)
                    end
                end
            end
        end
    end

    function Syndra:Combo()
        
        local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if self.isInEQ or self.isInW then return end
        if target then
            
            local distance = myHero.pos:DistanceTo(target.pos)
            
            if isSpellReady(_R) and distance < 700 then
                local notBlacklisted = self.Menu.BlockR[target.charName] and not self.Menu.BlockR[target.charName]:Value()
                local enemyCountClose = #getEnemyHeroesWithinDistance(1500)

                if notBlacklisted or enemyCountClose == 1 then
                    local QDmg = isSpellReady(_Q) and self:getQDamage(target) or 0
                    local WDmg = isSpellReady(_W) and self:getWDamage(target) or 0
                    local EDmg = isSpellReady(_E) and getdmg("E", target, myHero) or 0
                    local damages = self:getRDamage(target) + QDmg + WDmg + EDmg
                    if target.health <= damages then
                        Control.CastSpell(HK_R, target)
                    end
                end
            end

            if isSpellReady(_E) then
                if distance < 1000 then
                    self:castEQ(target, distance)
                end

                if self.isInEQ then return end

                local ePos = self:getEObject(target.pos)
                if ePos then
                    Control.CastSpell(HK_E, ePos)
                    orbwalker:SetMovement(false)
                    self.isInEQ = true
                    DelayAction(function ()
                        orbwalker:SetMovement(true)
                        self.isInEQ = false
                    end, 0.2)
                
                    
                end
                --elseif distance < 650 then
                --    self:castQE(target)
                
            end
            
            if self.isInEQ then return end

            if distance < 805 and isSpellReady(_Q) then
                castSpell(self.qSpellData, HK_Q, target)
            end

            if isSpellReady(_W) and distance < 850 and not isSpellReady(_E) then
                local wObject = self:getWObject()
                if wObject then
                    self:castW(wObject, target)
                end
            end

        end
    end

    function Syndra:Harass()
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if self.isInEQ or self.isInW then return end

        if target then
            
            local distance = myHero.pos:DistanceTo(target.pos)
            if distance < 807 and isSpellReady(_Q) then
                castSpell(self.qSpellData, HK_Q, target)
            end

            if isSpellReady(_W) and distance < 850 and self.Menu.WHarrass:Value() then
                local wObject = self:getWObject()
                if wObject then
                    self:castW(wObject, target)
                end
            end
        end
    end

    function Syndra:AutoQ()
        
        if self.isInEQ or self.isInW then return end

        local target = _G.SDK.TargetSelector:GetTarget(870, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if target and target.activeSpell and target.activeSpell.valid and myHero.pos:DistanceTo(target.pos) < 805 then
            castSpell(self.qSpellData, HK_Q, target)
        end
    end

    function Syndra:LaneClear()
        if HealthPrediction:ShouldWait() then return end
        local bestQPosition, bestCount = self:getBestClearMinion()
        
        if bestQPosition and bestCount > 1 and isSpellReady(_Q) then
            Control.CastSpell(HK_Q, bestQPosition)
        end
    end
    
    function Syndra:AntiMelee()
        if not isSpellReady(_E) then return end

        for i, enemy in pairs(getEnemyHeroes()) do
            if enemy and not enemy.dead and enemy.valid and enemy.visible and myHero.pos:DistanceTo(enemy.pos) < self.Menu.AntiMelee:Value() + myHero.boundingRadius then
                
                self:castQE(enemy)
            end
        end
    end

--------------------------------------------------
-- Gangplank
--------------
class "Gangplank"
        
function Gangplank:__init()	     
    print("devX-Gangplank Loaded") 
    self:LoadMenu()   
    
    Callback.Add("Draw", function() self:Draw() end)           
    Callback.Add("Tick", function() self:onTickEvent() end)    
end

--
-- Menu 
function Gangplank:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devGangplank", name = "DevX Gangplank v1.0"})
    -- ComboMenu  

    self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
    self.Menu.Combo:MenuElement({id = "BlockQMax", name = "Block Q - E cooldown less than x", value = 0.6, min = 0, max = 2, step = 0.01})
    self.Menu.Combo:MenuElement({id = "BlockQMin", name = "Block Q - E cooldown more than x", value = 0.25, min = 0, max = 2, step = 0.01})
    self.Menu.Combo:MenuElement({id = "FirstBarrel", name = "Place first barrel", value = true, toggle = true})
    self.Menu.Combo:MenuElement({id = "NextBarrel", name = "Place additional barrels", value = true, toggle = true})
    self.Menu.Combo:MenuElement({id = "BlockHanging", name = "Do not place hanging barrels", value = true, toggle = true})
    self.Menu.Combo:MenuElement({id = "MinBarrels", name = "Minimum barrels before placing", value = 2, min = 0, max = 3, step = 1})
    self.Menu.Combo:MenuElement({id = "PhantomBarrel", name = "Phantom Barrel", value = true, toggle = true})

    
    self.Menu:MenuElement({id = "LastHit", name = "Last Hit Minions", value = true, toggle = true})
    self.Menu:MenuElement({id = "AutoUlt", name = "Ult killable", value = true, toggle = true})
    self.Menu:MenuElement({id = "AutoCleanse", name = "Auto W", value = true, toggle = true})
end

function Gangplank:Draw()
    for i, champ in pairs(getEnemyHeroes()) do
        local percentHP = (champ.health / champ.maxHealth * 100)
        if percentHP < 30 then
            Draw.Text(champ.charName .. " - " .. percentHP .. " % HP", 15, 10, 70 + i*15, Draw.Color(255, 0, 255, 0))
        else
            Draw.Text(champ.charName .. " - " .. percentHP .. " % HP", 15, 10, 70 + i*15, Draw.Color(255, 0, 70, 255))

        end
    end
end


--------------------------------------------------
-- Callbacks
------------
function Gangplank:onTickEvent()
    if self.Menu.AutoCleanse:Value() and isSpellReady(_W) and isTargetImmobile(myHero)  then
        Control.CastSpell(HK_W, myHero)
    end
    if self.Menu.AutoUlt:Value() and isSpellReady(_R) then
        self:AutoUlt()
    end
    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end
    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end
    if self.Menu.LastHit:Value() and _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LASTHIT] then
        self:LastHit()
    end
end
----------------------------------------------------
-- Combat Functions
---------------------

----------------------------------------------------
-- Other Functions
---------------------

function Gangplank:getBarrels()
    local barrelList = {}

    for i = 1, GameObjectCount() do
        local obj = GameObject(i)
        if obj.charName == 'GangplankBarrel' and not obj.dead and isValid(obj) then
            table.insert(barrelList, obj)
        end
    end
    return barrelList
end

function Gangplank:getFirstBarrel(target, barrels)
    local furthestDistance = 0
    local furthestBarrel = nil
    local closestDistance = math.huge
    local closestBarrel = nil

    for i, barrel in pairs(barrels) do 
        local distance = barrel.pos:DistanceTo(target.pos)
        if distance > furthestDistance then
            furthestDistance = distance
            furthestBarrel = barrel
        end

        if distance < closestDistance then
            closestDistance = distance
            closestBarrel = barrel
        end
    end
    return furthestBarrel, closestBarrel
end
----------------------------------------------------
-- Combat Modes
---------------------

function Gangplank:AutoUlt()
    local enemies = getEnemyHeroes()
    for i, enemy in pairs(enemies) do
    
        if enemy and isValid(enemy) and not enemy.dead then
            local dmg = getdmg("R", enemy)
            if dmg * 3 > enemy.health then
                local enemyPos = enemy.pos:ToMM()
                Control.CastSpell(HK_R, enemyPos.x, enemyPos.y)
            end
        end
    end
end

function Gangplank:delayAndDisableOrbwalker(delay) 
    _nextSpellCast = Game.Timer() + delay
    orbwalker:SetMovement(false)
    orbwalker:SetAttack(false)
    DelayAction(function() 
        orbwalker:SetMovement(true)
        orbwalker:SetAttack(true)
    end, delay)
end
function Gangplank:Combo()
	if _nextSpellCast > Game.Timer() then return end	
   
    local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target == nil then return end

    local barrels = self:getBarrels();
    
    if self.Menu.Combo.FirstBarrel:Value() and #barrels == 0 and isSpellReady(_E) and myHero:GetSpellData(_E).ammo >= self.Menu.Combo.MinBarrels:Value() then
        Control.CastSpell(HK_E, myHero.pos)
        --self:delayAndDisableOrbwalker(0.2)
        return
    end

    if #barrels > 0 then
        local firstBarrel, closestBarrel = self:getFirstBarrel(target, barrels)
        if target.pos:DistanceTo(closestBarrel.pos) < 340 and firstBarrel.health == 1 then
            if myHero.pos:DistanceTo(firstBarrel.pos) < myHero.boundingRadius + 20 then
                Control.Attack(firstBarrel)
                self:delayAndDisableOrbwalker(0.35)
                return
            elseif myHero.pos:DistanceTo(firstBarrel.pos) < 660 and isSpellReady(_Q) then
                Control.CastSpell(HK_Q, firstBarrel)
                self:delayAndDisableOrbwalker(0.35)
                return
            elseif myHero.pos:DistanceTo(firstBarrel.pos) < 350 then
                --Control.Move(firstBarrel.pos)
                Control.Attack(firstBarrel)
                self:delayAndDisableOrbwalker(1)        
                return
            end
        end
        if isSpellReady(_E) then
            local nextPosition = closestBarrel.pos + (target.pos - closestBarrel.pos):Normalized() * 570
            if self.Menu.Combo.NextBarrel:Value() and #barrels == 1 and nextPosition:DistanceTo(myHero.pos) < 1000 then     
                local distToNextPosition = target.pos:DistanceTo(nextPosition)
                local placeBarrel = true
                 
                if (self.Menu.Combo.BlockHanging:Value() and myHero:GetSpellData(_E).ammo == 1) or myHero:GetSpellData(_E).ammo < self.Menu.Combo.MinBarrels:Value() then
                    if distToNextPosition > 500 and distToNextPosition < 850 then
                        print("Blocking barrel placement")
                        placeBarrel = false
                    end
                    
                end
                if placeBarrel then
                    Control.CastSpell(HK_E, nextPosition)
                    self:delayAndDisableOrbwalker(0.1)
                    return
                end
            end
            
            if  self.Menu.Combo.PhantomBarrel:Value() and #barrels > 1 and nextPosition:DistanceTo(myHero.pos) < 1000 and nextPosition:DistanceTo(target.pos) < 340 then
                
                local attacked = false
                if myHero.pos:DistanceTo(firstBarrel.pos) < myHero.boundingRadius + 20 then
                    Control.Attack(firstBarrel)
                    attacked = true
                elseif myHero.pos:DistanceTo(firstBarrel.pos) < 625 and isSpellReady(_Q) then
                    Control.CastSpell(HK_Q, firstBarrel)
                    attacked = true
                end
                if attacked then
                    DelayAction(function () Control.CastSpell(HK_E, nextPosition) end,0.2)
                    self:delayAndDisableOrbwalker(0.4)
                    return
                end
            end
        end
    end
    
    if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < 625 then
        
        local eCd = myHero:GetSpellData(_E).cd
        if eCd < self.Menu.Combo.BlockQMin:Value() or eCd >  self.Menu.Combo.BlockQMax:Value() then
            if #barrels > 0 then
                local firstBarrel, closestBarrel = self:getFirstBarrel(target, barrels)
                if not firstBarrel.health == 1 then
                    Control.CastSpell(HK_Q, target)
                end
            else
                Control.CastSpell(HK_Q, target)
            end
        end
    end
end

function Gangplank:Harass()
    local target = _G.SDK.TargetSelector:GetTarget(700, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target == nil then return end
    if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 630 then
        Control.CastSpell(HK_Q, target)
    end
   
end

function Gangplank:LastHit()
    if not isSpellReady(_Q) then return end

    for i = 1, GameMinionCount() do 
        local minion = GameMinion(i)
        local qDmg = getdmg("Q", minion)
        if minion and isValid(minion) and minion.isEnemy and minion.pos:DistanceTo(myHero.pos) < 630 and minion.health <= qDmg and minion.pos:DistanceTo(myHero.pos) > 350 then
            Control.CastSpell(HK_Q, minion)
        end
    end
end


--------------------------------------------------
-- Gnar
--------------
class "Gnar"
        
function Gnar:__init()	     
    print("devX-Gnar Loaded") 
    self:LoadMenu()   
    self.QspellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.066, Speed = 1200, Range = 1100, Radius = 60, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    self.WspellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Speed = math.huge, Range = 525, Radius = 80, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    
    Callback.Add("Tick", function() self:onTickEvent() end)    
end

--
-- Menu 
function Gnar:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devGnar", name = "DevX Gnar v1.0"})
    -- ComboMenu  

    self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
    self.Menu.Combo:MenuElement({name = "[E] Logic - Mini", id = "ETransform", value = 1, drop = {"None", "Always", "When about to transform", "Gapcloser"}})
    self.Menu.Combo:MenuElement({name = "[E] Logic - Mega", id = "ETransformMega", value = 1, drop = {"None", "Always", "When about to transform", "Gapcloser"}})
    
    self.Menu.Combo:MenuElement({id = "UltHP", name = "Ult if HP < x %", value = 30, min = 0, max = 110, step = 1})
    self.Menu.Combo:MenuElement({id = "UltHeroes", name = "Ult if x enemies within wall range", value = 2, min = 0, max = 5, step = 1})
    self.Menu.Combo:MenuElement({id = "UltAuto", name = "Auto-Ult outside of combo", value = false, toggle = true})
end



--------------------------------------------------
-- Callbacks
------------
function Gnar:onTickEvent()
    
    self:updateBuffs()

    if self.Menu.Combo.UltAuto:Value() and isSpellReady(_R) then
        self:UltimateLogic()
    end 
    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end

end

----------------------------------------------------
-- Combat Functions
---------------------

function Gnar:UltimateLogic()
	if _nextSpellCast > Game.Timer() then return end	
    local wallLocation = FindClosestWall()

    if wallLocation and myHero.pos:DistanceTo(wallLocation) < 400 then
        local enemiesInRange = getEnemyHeroesWithinDistanceOfUnit(wallLocation, 550)
        print(#enemiesInRange)

        if #enemiesInRange >= self.Menu.Combo.UltHeroes:Value() then
            local firstEnemy = enemiesInRange[1]
            VectorCast(wallLocation, firstEnemy.pos, HK_R)
            
        elseif #enemiesInRange > 0 then
            for i, hero in pairs(enemiesInRange) do
                if hero.health <= self.Menu.Combo.UltHP:Value() then
                    VectorCast(wallLocation, hero.pos, HK_R)
                end
            end
        end
    end
end


----------------------------------------------------
-- Other Functions
---------------------

function Gnar:updateBuffs()
    if doesMyChampionHaveBuff( "gnartransformsoon") or doesMyChampionHaveBuff( "gnartransform") then
        self.isMega = true
    else 
        self.isMega = false
    end

    
    if doesMyChampionHaveBuff( "gnarfuryhigh") or doesMyChampionHaveBuff( "gnartransformsoon")  then
        self.transformingSoon = true
    else 
        self.transformingSoon = false
    end
end

----------------------------------------------------
-- Combat Modes
---------------------

function Gnar:Combo()
    if isSpellReady(_R) then
        self:UltimateLogic()
    end
	if _nextSpellCast > Game.Timer() then return end	
    --{"None", "Always", "When about to transform", "Gapcloser"}
    local target = _G.SDK.TargetSelector:GetTarget(800, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target then
        if isSpellReady(_Q) then
            castSpell(self.QspellData, HK_Q, target)
        end

        if isSpellReady(_W) and self.isMega then
            castSpell(self.WspellData, HK_W, target)
        end
        if isSpellReady(_E)  then
            local transformCondition = self.Menu.Combo.ETransform:Value()
            if self.isMega then
                transformCondition = self.Menu.Combo.ETransformMega:Value()
            end
            if transformCondition == 2 then
                Control.CastSpell(HK_E, target)
            elseif transformCondition == 3 and self.transformingSoon  then
                Control.CastSpell(HK_E, target)
            elseif transformCondition == 4 and myHero.pos:DistanceTo(target.pos) > 400 then 
                Control.CastSpell(HK_E, target)
            end
        end

    end
end

function Gnar:Harass()
    local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target then
        
        if isSpellReady(_Q) then
            castSpell(self.QspellData, HK_Q, target)
        end

    end
   
end


--------------------------------------------------
-- Zeri
--------------
class "Zeri"
        
function Zeri:__init()	     
    print("devX-Zeri Loaded") 
    self:LoadMenu()   
    
    Callback.Add("Tick", function() self:onTickEvent() end)    
    self.qRange = 825

    
    _G.SDK.Spell:SpellClear(_Q, 
                            {Range=750, Speed = 2600, Delay = 0.1, Radius = 40 },
                            function ()
                                return isSpellReady(_Q)
                            end,
                            function ()
                                return _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LASTHIT] and self.Menu.QSpell.QLHEnabled:Value() and isSpellReady(_Q)
                            end,
                            function ()
                                return _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] and self.Menu.QSpell.QLCEnabled:Value()  and isSpellReady(_Q)
                            end,
                            function () 
                                local levelDmgTbl  = {15 , 18 , 21 , 24 , 27}
                                local levelPctTbl  = {1.04 , 1.08 , 1.12 , 1.16 , 1.2}

                                local levelDmg = levelDmgTbl[myHero:GetSpellData(_Q).level]
                                local levelPct = levelPctTbl[myHero:GetSpellData(_Q).level]
                                local dmg = levelDmg + myHero.totalDamage*levelPct
                                return dmg
                            end
    )
    
end

--
-- Menu 
function Zeri:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devZeri", name = "DevX Zeri v1.0"})
    -- ComboMenu  
    
    self.Menu:MenuElement({ id = "BlockAuto", name = "Block auto without Q passive", value = true})

    self.Menu:MenuElement({type = MENU, id = "QSpell", name = "Q"})
        self.Menu.QSpell:MenuElement({ id = "QEnabled", name = "Combo Enabled", value = true})
        self.Menu.QSpell:MenuElement({ id = "QHEnabled", name = "Harass Enabled", value = true})
        self.Menu.QSpell:MenuElement({ id = "QLCEnabled", name = "Lane Clear Enabled", value = true})
        self.Menu.QSpell:MenuElement({ id = "QLHEnabled", name = "LastHit Enabled", value = true})

    self.Menu:MenuElement({type = MENU, id = "WSpell", name = "W"})
        self.Menu.WSpell:MenuElement({ id = "WEnabled", name = "Combo Enabled", value = true})
        self.Menu.WSpell:MenuElement({ id = "WTerrain", name = "Use only through Walls", value = true})

    self.Menu:MenuElement({type = MENU, id = "ESpell", name = "E"})
        self.Menu.ESpell:MenuElement({ id = "EEnabled", name = "Combo Enabled", value = true})
    
    self.Menu:MenuElement({type = MENU, id = "RSpell", name = "R"})
        self.Menu.RSpell:MenuElement({ id = "RCount", name = "Use Ultimate when can hit >= X enemies", min = 0, max = 5, value=2})
end



--------------------------------------------------
-- Callbacks
------------


function Zeri:onTickEvent()
    self.hasPassive = doesMyChampionHaveBuff("zeriqpassiveready")

    if self.hasPassive and self.Menu.BlockAuto:Value() then
        orbwalker:SetAttack(true)
    elseif not self.hasPassive then
        orbwalker:SetAttack(false)
    end

    local hasLethal = doesMyChampionHaveBuff("ASSETS/Perks/Styles/Precision/LethalTempo/LethalTempo.lua")
    if hasLethal then
        self.qRange = 900
        self.aaRange = 575
    else
        self.qRange = 825
        self.aaRange = 500
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end

end
----------------------------------------------------
-- Other Functions
---------------------
function Zeri:castQ(target)
    local qData = {Type = GGPrediction.SPELLTYPE_LINE, Range=self.qRange, Speed = 2600, Delay = 0.1, Radius = 40,  Collision = false, CollisionTypes = { GGPrediction.COLLISION_MINION}}
    castSpell(qData,HK_Q, target)
end
function Zeri:assessWOptions(target)
    local distanceTarget = myHero.pos:DistanceTo(target.pos)
    --if distance >= 1550 then return end

    local direction = (target.pos - myHero.pos):Normalized()
    for distance = 50, 1100, 50 do
        local testPosition = myHero.pos + direction * distance
        if testPosition:ToScreen().onScreen then
            
            for i = 1, GameMinionCount() do -- blocked by minion
                local minion = GameMinion(i)
                if minion and minion.isEnemy and isValid(minion) and minion.pos:DistanceTo(testPosition) < 50 then
                    return false
                end 
            end
            if target.pos:DistanceTo(testPosition) < 50 then -- it will hit champion before it hits wall
                if not self.Menu.WSpell.WTerrain:Value() then -- The user selected to allow hitting even when not through terrain
                    Control.CastSpell(HK_W, testPosition)
                    return true
                else
                    return false
                end
            end
            if MapPosition:inWall(testPosition) then
                if target.pos:DistanceTo(testPosition) > 1500 then
                    return false
                end
                Control.CastSpell(HK_W, testPosition)
                return true
            end
        end
    end
    return false
end
----------------------------------------------------
-- Combat Modes
---------------------

function Zeri:Combo()
    local target = orbwalker:GetTarget()
    
    if not target then
        target = _G.SDK.TargetSelector:GetTarget(2700, _G.SDK.DAMAGE_TYPE_MAGICAL);
    end
    if target then
        local distance = myHero.pos:DistanceTo(target.pos) 
        if self.hasPassive and distance <= self.aaRange then return end --lets use charged auto instead
        
        if isSpellReady(_W) and self.Menu.WSpell.WEnabled:Value() then
            self:assessWOptions(target)
        end
        if self.Menu.QSpell.QEnabled:Value() and distance < self.qRange and isSpellReady(_Q) and not orbwalker:IsAutoAttacking() then
            self:castQ(target)
        end

        if self.Menu.ESpell.EEnabled:Value() and isSpellReady(_E) then
            local pos = myHero.pos + (mousePos - myHero.pos):Normalized() * 300
            Control.CastSpell(HK_E, pos)
        end

        local closeEnemies = getEnemyHeroesWithinDistance(825)
        if #closeEnemies >= self.Menu.RSpell.RCount:Value() and isSpellReady(_R) then
            Control.CastSpell(HK_R, myHero)
        end
    end
end

function Zeri:Harass()
    local target = orbwalker:GetTarget()
    if not target then
        target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    end
    if target then
        local distance = myHero.pos:DistanceTo(target.pos) 
        if self.hasPassive and distance <= self.aaRange then return end --lets use charged auto instead
        
        if self.Menu.QSpell.QHEnabled:Value() and myHero.pos:DistanceTo(target.pos) < self.qRange and isSpellReady(_Q) and not orbwalker:IsAutoAttacking()  then
            self:castQ(target)
        end

    end
   
end


--------------------------------------------------
-- LeeSin
--------------
class "LeeSin"
        
function LeeSin:__init()	     
    print("devX-LeeSin Loaded") 
    self:LoadMenu()   
    
    self.qPrediction = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Radius = 60, Range = 1200, Speed = 1800, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    
    Callback.Add("Tick", function() self:onTickEvent() end)    
    Callback.Add("Draw", function() self:onDrawEvent() end)

    self.state = "idle"
    self.substate = "idle"

    self.nextQTimer = Game.Timer()
    self.passiveCount = 0
    
end

--
-- Menu 
function LeeSin:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devLeeSin", name = "DevX LeeSin v1.0"})


    self.Menu:MenuElement({type = MENU, id = "Flee", name = "Flee"})
        self.Menu.Flee:MenuElement({id = "Wards", name = "Wards", value = true})
        self.Menu.Flee:MenuElement({id = "Allies", name = "Allies", value = true})
        self.Menu.Flee:MenuElement({id = "Minions", name = "Minions", value = true})

    self.Menu:MenuElement({type = MENU, id = "Clear", name = "Clear"})
        self.Menu.Clear:MenuElement({id = "Enabled", name = "Enabled", value = true})
        self.Menu.Clear:MenuElement({id = "Passive", name = "Manage Passive", value = true})
        self.Menu.Clear:MenuElement({id = "QSpell", name = "[Q]", value = true})
        self.Menu.Clear:MenuElement({id = "WSpell", name = "[W]", value = true})
        self.Menu.Clear:MenuElement({id = "ESpell", name = "[E]", value = true})
    
    self.Menu:MenuElement({type = MENU, id = "Safeguard", name = "Safeguard"})
        self.Menu.Safeguard:MenuElement({id = "HPCombo", name = "Combo - Min. HP Self", min = 1, max = 100, value = 60})
        self.Menu.Safeguard:MenuElement({id = "HPAlly", name = "Combo - Min. HP Ally", min = 1, max = 100, value = 30})
        self.Menu.Safeguard:MenuElement({id = "HPClear", name = "Clear - Min. HP Self", min = 1, max = 100, value = 100})

    self.Menu:MenuElement({type = MENU, id = "Insec", name = "Insec"})  
        self.Menu.Insec:MenuElement({id="Enabled", name = "Enabled", value = true, toggle = true})
        self.Menu.Insec:MenuElement({id = "MinHP", name = "Target > X% HP", min = 1, max = 100, value = 15})
        self.Menu.Insec:MenuElement({id = "WardJump", name = "Ward jump insec", value = true, toggle = true})
        self.Menu.Insec:MenuElement({id = "Flash", name = "Flash insec", value = true, toggle = true})
        self.Menu.Insec:MenuElement({id = "FlashWard", name = "'Chinese' insec (Flash - Ward Jump)", value = true, toggle = true})
    

    self.Menu:MenuElement({type = MENU, id = "Ultimate", name = "Ultimate Logic"})
        self.Menu.Ultimate:MenuElement({type = MENU, id = "Duelling", name = "Duelling - Not implemented"})
        self.Menu.Ultimate:MenuElement({type = MENU, id = "MultiUlt", name = "Multi-target ultimate"})
            self.Menu.Ultimate.MultiUlt:MenuElement({id = "Enabled", name = "Enabled", value = true, toggle = true})
            self.Menu.Ultimate.MultiUlt:MenuElement({id = "UltAmount", name = "Ult if hit >= x enemies", min = 1, max = 5, value = 2})
            self.Menu.Ultimate.MultiUlt:MenuElement({id = "Walk", name = "Walk into position - 50 > dist < 200 ", value = true, toggle = true})
            self.Menu.Ultimate.MultiUlt:MenuElement({id = "WardJump", name = "Ward jump into position - 200 > dist < 400", value = true, toggle = true})

    
end



--------------------------------------------------
-- Callbacks
------------

function LeeSin:onDrawEvent()
    --Draw.Circle(myHero.pos, 700, 1,  Draw.Color(255,255,255,0))

        
    if self.insecAlly then

        Draw.Circle(self.insecAlly.pos, 50, 1,  Draw.Color(255,0,255,0))
        Draw.Circle(self.insecPosition, 50, 1,  Draw.Color(255,0,0,255))
        
        if self.target and self.insecPosition then
            target2d = self.target.pos2D
            local insec2d = self.insecPosition:To2D()
            Draw.Text("Flash Insec Range", 7, target2d.x, target2d.y + 30, Draw.Color(255, 255, 255, 255))
            Draw.Circle(self.target.pos, 260, 1,  Draw.Color(255,255,0,0))
            Draw.Text("Ward Hop Insec Range", 7, insec2d.x, insec2d.y + 230, Draw.Color(255, 255, 255, 255))
            Draw.Circle(self.insecPosition, 700, 1,  Draw.Color(255,0,255,0))
            Draw.Text("Chinese Range", 7, insec2d.x, insec2d.y + 450, Draw.Color(255, 255, 255, 255))
            Draw.Circle(self.insecPosition, 1100, 1,  Draw.Color(255,0,0,255))
        end
    end
    if self.tripleUltTarget then
       Draw.Circle(self.tripleUltPos, 50, 1,  Draw.Color(255,255,255,255))
    end
end

function LeeSin:onTickEvent()
    self.wardSlot, self.wardKey = getWardSlot()
    self.flashSlot, self.flashKey = getFlashSlot()
    self.passiveCount = getChampionBuffCount("blindmonkpassive_cosmetic")
    
    local target = _G.SDK.TargetSelector:GetTarget(1800, _G.SDK.DAMAGE_TYPE_MAGICAL);
    self.target = target

    if self.target and isSpellReady(_R) then
        if self.Menu.Insec.Enabled:Value() then
            self.insecAlly, self.insecPosition = self:identifyInsecOpportunity(target)
        else
            self.insecAlly, self.insecPosition = nil, nil
        end

        self:identifyTripleUlt()
    end
    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_JUNGLECLEAR] or _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
        self:Clear()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_FLEE] then
        self:Flee()
    end
end
----------------------------------------------------
-- Other Functions
---------------------

function LeeSin:identifyInsecOpportunity(target)
    if self.Menu.Insec.MinHP:Value() > target.health / target.maxHealth * 100  then return end

    local closestAlly = nil
    local closestDistance = math.huge
    for i = 1, GameTurretCount() do
        local turret = GameTurret(i)
        local distance = turret.pos:DistanceTo(target.pos)
        if turret and not turret.dead and turret.isAlly and distance < closestDistance then
            closestDistance = distance
            closestAlly = turret
        end
    end
    for i = 1, GameHeroCount() do
        local hero = GameHero(i)
        local distance = hero.pos:DistanceTo(target.pos)
        if hero and not hero.dead and hero.isAlly and not hero.isMe and distance < closestDistance then
            closestDistance = distance
            closestAlly = hero
        end
    end
    if closestDistance < 2000 then
        return closestAlly, target.pos + (target.pos - closestAlly.pos):Normalized() * 280
    end
    return nil, nil
end

function LeeSin:identifyTripleUlt()
    local enemies = getEnemyHeroesWithinDistance(1200)
    if #enemies < self.Menu.Ultimate.MultiUlt.UltAmount:Value() then 
        self.tripleUltTarget = nil;
        self.tripleUltPos = nil;
        return 
    end
    
    self.tripleUltTarget = nil;
    self.tripleUltPos = nil;

    if not self.Menu.Ultimate.MultiUlt.Enabled:Value() then return end

    for i, enemy in pairs(enemies) do
        local distance = enemy.pos:DistanceTo(myHero.pos)
        
        if distance < 600 and self.Menu.Insec.MinHP:Value() < enemy.health / enemy.maxHealth * 100 then
            local startPos, mPos, height = Vector(myHero.pos), Vector(mousePos), myHero.pos.y
            for i = 200, 600, 25 do -- search range
                local endPos = startPos:Extended(mPos, i)
                for j = 20, 360, 20 do -- angle step
                    local testPos = Rotate(startPos, endPos, height, math.rad(j))
                    if self:evaluateUlt(testPos, enemy, enemies) then
                        self.tripleUltTarget = enemy;
                        self.tripleUltPos = testPos;
                        return
                    end
                end
            end
        end
    end
end

function LeeSin:evaluateUlt(position, enemy, enemies)
    if position:DistanceTo(enemy.pos) > 400 then return false end

    local targetPosition = enemy.pos  + Vector( enemy.pos - position ):Normalized() * 1200
    local count = 1
    for i, otherEnemy in pairs(enemies) do
        if otherEnemy.networkID ~= enemy.networkID then
            
            local spellLine = ClosestPointOnLineSegment(otherEnemy.pos, myHero.pos, targetPosition)
            if otherEnemy.pos:DistanceTo(spellLine) < 100 then
                count = count+1
            end
        end
    end
    if count >= self.Menu.Ultimate.MultiUlt.UltAmount:Value() then
        return true
    end
    return false
end

function LeeSin:getAllyWTarget()
    
    for i = 1, GameHeroCount() do
        local hero = GameHero(i)
        if hero and not hero.dead and hero.isAlly and not hero.isMe then
            local distance = mousePos:DistanceTo(hero.pos)
            
            if distance < 700 and self.Menu.Safeguard.HPAlly:Value() > hero.health / hero.maxHealth * 100 then
                return hero
            end
        end
    end
    return nil
end
function LeeSin:getWardJumpTarget()
    local closestTarget = nil
    local closestDistance = math.huge

    if self.Menu.Flee.Wards:Value() then
        for i = 1, Game.WardCount() do
            local ward = Game.Ward(i)
            if ward and ward.valid and ward.isAlly then
                local distance = mousePos:DistanceTo(ward.pos)
                if distance < closestDistance then
                    closestDistance = distance
                    closestTarget = ward
                end
            end
        end	
    end
    
    if self.Menu.Flee.Allies:Value() then
        for i = 1, GameHeroCount() do
            local hero = GameHero(i)
            if hero and not hero.dead and hero.isAlly and not hero.isMe then
                local distance = mousePos:DistanceTo(hero.pos)
                
                if distance < closestDistance then
                    closestDistance = distance
                    closestTarget = hero
                end
            end
        end
    end
    
    if self.Menu.Flee.Minions:Value() then
        for i = 1, GameMinionCount() do
            local minion = GameMinion(i)
            if minion and minion.isAlly and not minion.dead then
                local distance = mousePos:DistanceTo(minion.pos)
                
                if distance < closestDistance then
                    closestDistance = distance
                    closestTarget = minion
                end
            end
        end
    end

    return closestTarget, closestDistance
end

function LeeSin:delayAndDisableOrbwalker(delay) 
    _nextSpellCast = Game.Timer() + delay
    orbwalker:SetMovement(false)
    orbwalker:SetAttack(false)
    DelayAction(function() 
        orbwalker:SetMovement(true)
        orbwalker:SetAttack(true)
    end, delay)
end

function LeeSin:disableOrbwalker(delay) 
    orbwalker:SetMovement(false)
    orbwalker:SetAttack(false)
    DelayAction(function() 
        orbwalker:SetMovement(true)
        orbwalker:SetAttack(true)
    end, delay)
end
----------------------------------------------------
-- Combat Modes
---------------------

function LeeSin:Flee()
	if _nextSpellCast > Game.Timer() then return end	
    if orbwalker:IsAutoAttacking() then return end
    if not isSpellReady(_W) and string.find(myHero:GetSpellData(_Q).name, 'One') then
        return
    end

    local closestTarget, closestDistance = self:getWardJumpTarget()

    if closestTarget then
        local distance = myHero.pos:DistanceTo(closestTarget.pos)
        if (distance  > 400 or not self.wardSlot) and distance < 700 then
            Control.CastSpell(HK_W, closestTarget)
            self:delayAndDisableOrbwalker(0.6)
            return
        end
    end

    if self.wardSlot and self.Menu.Flee.Wards:Value() then
        local distance = mousePos:DistanceTo(myHero.pos)
        local wardPosition = myHero.pos + (mousePos - myHero.pos):Normalized() * math.min(distance, 650)
        
        self:delayAndDisableOrbwalker(0.6)
        
        Control.CastSpell(self.wardKey, wardPosition)
        DelayAction(function () Control.CastSpell(HK_W, wardPosition) end, 0.16)
        
    end

end

function LeeSin:isUltCloseEnough(targetCurrentPosition, targetUltPosition)
    
    local currentDelta = targetCurrentPosition  + Vector( targetCurrentPosition - myHero.pos ):Normalized() * 1200
    local targetDelta = targetCurrentPosition  + Vector( targetCurrentPosition - targetUltPosition ):Normalized() * 1200

    return currentDelta:DistanceTo(targetDelta) < 325 
end

function LeeSin:Combo()
    
	if _nextSpellCast > Game.Timer() then return end	
    
    if self.target then
        local distance = myHero.pos:DistanceTo(self.target.pos) 
        if self.Menu.Ultimate.MultiUlt.Enabled:Value() and self.tripleUltTarget and isSpellReady(_R) then
            local distTriple = myHero.pos:DistanceTo(self.tripleUltPos) 
            local tripleUltTargDistance = myHero.pos:DistanceTo(self.tripleUltTarget)

            if self.Menu.Ultimate.MultiUlt.Walk:Value() and distTriple > 100 and distTriple < 200 then 
                Control.Move(self.tripleUltPos)
                self:delayAndDisableOrbwalker(0.35)
                return
            elseif self.Menu.Ultimate.MultiUlt.WardJump:Value() and distTriple > 400 and self.wardSlot  then
                self:delayAndDisableOrbwalker(0.7)
                Control.CastSpell(self.wardKey, self.insecPosition)
                
                DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.14)
                DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.38)
                return
            elseif distTriple < 100  then
                Control.CastSpell(HK_R, self.tripleUltTarget)
                return
            end
        end

        if self.Menu.Insec.Enabled:Value() and self.insecPosition and isSpellReady(_R) and not self.tripleUltTarget then 
            -- ward insec    
            local distanceFromPos = myHero.pos:DistanceTo(self.insecPosition)
            local distanceFromTarget = myHero.pos:DistanceTo(self.target.pos)
            
            local closeEnough = self:isUltCloseEnough(self.target.pos, self.insecPosition) and distanceFromTarget < 400

            if closeEnough then
                self:delayAndDisableOrbwalker(0.35)
                Control.CastSpell(HK_R, self.target) 
                return
            end
            if self.Menu.Insec.WardJump:Value() and self.wardSlot and distanceFromPos > 50 and distanceFromPos <= 700 then
                local extraDelay = 0.005 * (distanceFromPos - 290) / 100
                print(extraDelay)
                self:delayAndDisableOrbwalker(1 + extraDelay)
                Control.CastSpell(self.wardKey, self.insecPosition)
                DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.25 + extraDelay)
                
                DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.42 + extraDelay)
                return
            end

            if self.Menu.Insec.Flash:Value() and self.flashSlot and distanceFromTarget > 50 and distanceFromTarget <= 290 then
                self:delayAndDisableOrbwalker(0.7)
                local castDetails = canSpellHitNormal(self.qPrediction, self.target)
                if isSpellReady(_Q) and castDetails.canHit then
                    Control.CastSpell(HK_Q, castDetails.castPos)
                    DelayAction(
                        function ()
                            if Control.CastSpell(HK_R, self.target) then
                                DelayAction(function () Control.CastSpell(self.flashKey, self.insecPosition) end, 0.2)
                                DelayAction(function () Control.CastSpell(HK_Q) end, 0.4)
                            end
                        end
                        , 0.2
                    )
                else
                    if Control.CastSpell(HK_R, self.target) then
                        DelayAction(function () Control.CastSpell(self.flashKey, self.insecPosition) end, 0.2)
                    end
                end
                
                return
            end

            if self.Menu.Insec.FlashWard:Value() and self.flashSlot and self.wardSlot and distanceFromPos < 1100 then
                
                local castDetails = canSpellHitNormal(self.qPrediction, self.target)
                local extraDelay = 0.05 * (distanceFromPos - 700) / 100
                
                if isSpellReady(_Q) and castDetails.canHit then
                    self:delayAndDisableOrbwalker(1.6 + extraDelay)

                    Control.CastSpell(HK_Q, castDetails.castPos)
                    DelayAction(function () Control.CastSpell(self.wardKey, self.insecPosition) end, 0.2 + extraDelay)
                    DelayAction(function () Control.CastSpell(self.flashKey, self.insecPosition) end, 0.4 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.55 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.74 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_Q) end, 1.4 + extraDelay)
                else
                    self:delayAndDisableOrbwalker(1.3 + extraDelay)
                    Control.CastSpell(self.wardKey, self.insecPosition)
                    DelayAction(function () Control.CastSpell(self.flashKey, self.insecPosition) end, 0.2 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.42 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.62 + extraDelay)
                    DelayAction(function () Control.CastSpell(HK_Q, self.target) end, 0.92 + extraDelay)
                end
                return
            end
        end

        if isSpellReady(_Q)  and distance < self.qPrediction.Range + 50 then
            if  string.find(myHero:GetSpellData(_Q).name, 'One')  then
                
                local castDetails = canSpellHitNormal(self.qPrediction, self.target)
                if castDetails.canHit then
                    Control.CastSpell(HK_Q, castDetails.castPos)
                    _nextSpellCast = Game.Timer() + 0.3
                    
                    if distance < 400 then
                        self.nextQTimer = Game.Timer() + 1
                    end
                    return
                end
            elseif Game.Timer() > self.nextQTimer or  distance > 400   then

                Control.CastSpell(HK_Q)
                _nextSpellCast = Game.Timer() + 0.3
                return
            end
        end

        
        if isSpellReady(_E) and distance < 200 then
            Control.CastSpell(HK_E)
            _nextSpellCast = Game.Timer() + 0.3
            return
        end

        
        if isSpellReady(_W) then 
            local allyTarget = self:getAllyWTarget()
            if allyTarget then
                Control.CastSpell(HK_W, allyTarget)
            elseif distance < 200 and self.Menu.Safeguard.HPCombo:Value()  > myHero.health / myHero.maxHealth * 100 then
                Control.CastSpell(HK_W, myHero)
            end
            _nextSpellCast = Game.Timer() + 0.2
        end
    end
end

function LeeSin:Clear()
	if not self.Menu.Clear.Enabled:Value() then return end
    if _nextSpellCast > Game.Timer() then return end
    if orbwalker:IsAutoAttacking() then return end

    if self.passiveCount > 0 and self.Menu.Clear.Passive:Value() then return end

    local target = HealthPrediction:GetJungleTarget()
    if not target then
        target = HealthPrediction:GetLaneClearTarget()
    end
    if target then
        if self.Menu.Clear.QSpell:Value() and isSpellReady(_Q) and Game.Timer() > self.nextQTimer then
            Control.CastSpell(HK_Q, target.pos)
            _nextSpellCast = Game.Timer() + 0.7
            self.nextQTimer = Game.Timer() + 1.2
            return
        end
        if self.Menu.Clear.ESpell:Value() and isSpellReady(_E) then
            Control.CastSpell(HK_E, target.pos)
            _nextSpellCast = Game.Timer() + 0.7
            return
        end
        if self.Menu.Clear.WSpell:Value() and isSpellReady(_W) and self.Menu.Safeguard.HPClear:Value()  > myHero.health / myHero.maxHealth * 100 then
            Control.CastSpell(HK_W, myHero)
            _nextSpellCast = Game.Timer() + 0.7
            return
        end
    end
end
function LeeSin:Harass()
    local target = orbwalker:GetTarget()
    if not target then
        target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    end
    if target then
        local distance = myHero.pos:DistanceTo(target.pos) 
       
        if isSpellReady(_Q) and string.find(myHero:GetSpellData(_Q).name, 'One')  and distance < self.qPrediction.Range + 50 then
            castSpell(self.qPrediction, HK_Q, target)
            self:delayAndDisableOrbwalker(0.1)
        end
    end
   
end


--------------------------------------------------
-- Qiyana
--------------

class "Qiyana"
        
    function Qiyana:__init()	     
        print("devX-Qiyana Loaded") 
        self:LoadMenu()   

        self.ELEMENT = {
            NONE = 0,
            ROCK = 1,
            WATER = 2,
            GRASS = 3
        }

        self.previousElement = self.ELEMENT.NONE
        self.BEST_NEXT_ELEMENT = {
            [self.ELEMENT.NONE] = { self.ELEMENT.GRASS, self.ELEMENT.ROCK, self.ELEMENT.WATER},
            [self.ELEMENT.ROCK] = { self.ELEMENT.GRASS, self.ELEMENT.WATER, self.ELEMENT.ROCK},
            [self.ELEMENT.WATER] = { self.ELEMENT.ROCK, self.ELEMENT.GRASS, self.ELEMENT.WATER},
            [self.ELEMENT.GRASS] = { self.ELEMENT.ROCK, self.ELEMENT.WATER, self.ELEMENT.GRASS},
        }
        self.BEST_NEXT_ELEMENT_LOW = {
            [self.ELEMENT.NONE] = { self.ELEMENT.GRASS, self.ELEMENT.WATER, self.ELEMENT.ROCK},
            [self.ELEMENT.ROCK] = {  self.ELEMENT.GRASS, self.ELEMENT.WATER,  self.ELEMENT.ROCK},
            [self.ELEMENT.WATER] = {  self.ELEMENT.GRASS, self.ELEMENT.WATER, self.ELEMENT.ROCK},
            [self.ELEMENT.GRASS] = { self.ELEMENT.GRASS, self.ELEMENT.WATER, self.ELEMENT.ROCK},
        }
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:onDrawEvent() end)
        
    end

    --
    -- Menu 
    function Qiyana:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devQiyana", name = "DevX Qiyana v1.0"})
        -- ComboMenu  

        
    end



--------------------------------------------------
-- Callbacks
------------

    function Qiyana:onDrawEvent()
        
    end

    function Qiyana:onTickEvent()
        
        self.hasWater = doesMyChampionHaveBuff("QiyanaQ_Water")
        self.hasGrass = doesMyChampionHaveBuff("QiyanaQ_Grass")
        self.hasRock = doesMyChampionHaveBuff("QiyanaQ_Rock")

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_JUNGLECLEAR] then
            self:Clear()
        end
    end
----------------------------------------------------
-- Other Functions
---------------------

    function Qiyana:delayAndDisableOrbwalker(delay) 
        _nextSpellCast = Game.Timer() + delay
        orbwalker:SetMovement(false)
        orbwalker:SetAttack(false)
        DelayAction(function() 
            orbwalker:SetMovement(true)
            orbwalker:SetAttack(true)
        end, delay)
    end

    function Qiyana:FindClosestElement(element)
        -- add a target parameter
        -- should try grab the closest position to target where possible
        local startPos, mPos, height = Vector(myHero.pos), Vector(mousePos), myHero.pos.y
        for i = 100, 2000, 100 do -- search range
            local endPos = startPos:Extended(mPos, i)
            for j = 20, 360, 20 do -- angle step
                local testPos = Rotate(startPos, endPos, height, math.rad(j))
                if testPos:ToScreen().onScreen then 
                    local foundElement =    (element == self.ELEMENT.ROCK and MapPosition:inWall(testPos)) or 
                                            (element == self.ELEMENT.WATER and MapPosition:inRiver(testPos)) or 
                                            (element == self.ELEMENT.GRASS and MapPosition:inBush(testPos))
                    if foundElement then
                        return testPos
                    end
                end
            end
        end
        return nil
    end

    function Qiyana:FindClosestElementToTarget(element, target)
        
        -- add a target parameter
        -- should try grab the closest position to target where possible
        local startPos, mPos, height = Vector(myHero.pos), Vector(target), myHero.pos.y
        for i = 100, 2000, 100 do -- search range
            local endPos = startPos:Extended(mPos, i)
            for j = 20, 360, 20 do -- angle step
                local testPos = Rotate(startPos, endPos, height, math.rad(j))
                if testPos:ToScreen().onScreen then 
                    local foundElement =    (element == self.ELEMENT.ROCK and MapPosition:inWall(testPos)) or 
                                            (element == self.ELEMENT.WATER and MapPosition:inRiver(testPos)) or 
                                            (element == self.ELEMENT.GRASS and MapPosition:inBush(testPos))
                    if foundElement then
                        return testPos
                    end
                end
            end
        end
        return nil
    end

    function Qiyana:castW(comboMode, target)

        local findElementList = nil
        if myHero.health / myHero.maxHealth < 0.3 then 
            findElementList = self.BEST_NEXT_ELEMENT_LOW[self.previousElement] 
        else findElementList = self.BEST_NEXT_ELEMENT[self.previousElement] end
        
        for i, element in pairs(findElementList) do
            local castPosition = nil

            if comboMode then castPosition = self:FindClosestElementToTarget(element, target)     
            else castPosition = self:FindClosestElement(element) end

            if castPosition then
                Control.CastSpell(HK_W, castPosition)
                self.previousElement = element
                return true
            end
        end
        return false
    end

    function Qiyana:findBestETarget(target)
        local closestTarget = nil
        local closestDistance = math.huge

        for i = 1, GameMinionCount() do
            local minion = GameMinion(i)
            if minion and isValid(minion) and not minion.isAlly then
                local distance = minion.pos:DistanceTo(target.pos)
                if distance < closestDistance and myHero.pos:DistanceTo(minion.pos) < 600 then
                    closestDistance = distance
                    closestTarget = minion
                end
            end
        end

        for i, enemy in pairs(getEnemyHeroesWithinDistance(600)) do
            if enemy and isValid(enemy) and not enemy.dead then
                local distance = enemy.pos:DistanceTo(target.pos)
                if distance < closestDistance and myHero.pos:DistanceTo(enemy.pos) < 600 then
                    closestDistance = distance
                    closestTarget = enemy
                end
            end
        end

        return closestTarget
        
    end
----------------------------------------------------
-- Combat Modes
---------------------
    function Qiyana:performGapCloseCombo(useUlt, target)
        local bestETarget = self:findBestETarget(target)
        print(target.pos:DistanceTo(bestETarget.pos))
        if bestETarget then
            print("Gapclose")

            local willUseUltimate = false
        
            local dmgWithoutUlt =  getdmg("Q", target, myHero) * 2 +  getdmg("W", target, myHero) +  getdmg("E", target, myHero) + getdmg("AA", target, myHero)
            local dmgWithUlt = getdmg("R", target, myHero) + getdmg("AA", target, myHero) * 2 + dmgWithoutUlt

            if useUlt and target.health < dmgWithUlt and target.health > dmgWithoutUlt  * 0.6  then
                willUseUltimate = true
            end
            Control.CastSpell(HK_E, bestETarget)

            if willUseUltimate then
                
                DelayAction(function () Control.CastSpell(HK_R, target) end, 0.35)
                DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.48)
                DelayAction(function () self:castW(true, target) end, 0.63)
                DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.72)
                self:delayAndDisableOrbwalker(1.3) 
            
            else
                
                DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.35)
                DelayAction(function () self:castW(true, target) end, 0.45)
                DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.64)
                self:delayAndDisableOrbwalker(1.3) 

            end
            return true
        end
        return false
    end

    function Qiyana:performNormalCombo(useUlt, target)
        print("EQWQ")
        local willUseUltimate = false
        
        local dmgWithoutUlt =  getdmg("Q", target, myHero) * 2 +  getdmg("W", target, myHero) +  getdmg("E", target, myHero) 
        local dmgWithUlt = getdmg("R", target, myHero) + getdmg("AA", target, myHero) * 2 + dmgWithoutUlt

        if useUlt and target.health < dmgWithUlt and target.health > dmgWithoutUlt * 0.6 then
            willUseUltimate = true
        end

        if willUseUltimate then
            Control.CastSpell(HK_R, target)
            DelayAction(function () Control.CastSpell(HK_E, target) end, 0.3)
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.45)
            DelayAction(function () self:castW(true, target) end, 0.6)
            DelayAction(function () 
                local dist = target.pos:DistanceTo(myHero.pos)
                if dist < 300 then
                    orbwalker:Attack(target)
                    DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.2)
                end
            end, 0.75)
            self:delayAndDisableOrbwalker(2) 
            
        else
            
            local dist = target.pos:DistanceTo(myHero.pos)
            if dist > 300 then
                Control.CastSpell(HK_E, target)
            end
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.3)
            DelayAction(function () self:castW(true, target) end, 0.48)
            DelayAction(function () 
                local dist = target.pos:DistanceTo(myHero.pos)
                if dist < 300 then
                    orbwalker:Attack(target)
                    DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.12)
                else
                    Control.CastSpell(HK_Q, target) 
                end
            end, 0.68)
            self:delayAndDisableOrbwalker(2) 
        end
        return true
    end

    function Qiyana:Combo()
        if _nextSpellCast > Game.Timer() then return end	

        local target = _G.SDK.TargetSelector:GetTarget(1300, _G.SDK.DAMAGE_TYPE_MAGICAL);
        local hasElement = self.hasGrass or self.hasRock or self.hasWater

        
        if not hasElement and isSpellReady(_W) then
            self:castW(true, target)
            self:delayAndDisableOrbwalker(0.3) 
            return
        end
        if target then
            local distance = myHero.pos:DistanceTo(target.pos)
            local closestWall = FindClosestWall(target)
            
            local canUseUlt = closestWall ~= nil and closestWall:DistanceTo(target.pos) < 600 and isSpellReady(_R)
            if distance < 1200 and isSpellReady(_Q) and isSpellReady(_W) and isSpellReady(_E) then
                if self:performGapCloseCombo(canUseUlt, target) then
                    self:delayAndDisableOrbwalker(0.4) 
                    return
                end 
            end

            if distance <  400 then
                if not isSpellReady(_W) then
                    if isSpellReady(_Q) and hasElement and myHero:GetSpellData(_W).currentCd > 4.5 then
                        print("Adhoc Empowered Q")
                        Control.CastSpell(HK_Q, target)
                        self:delayAndDisableOrbwalker(0.4) 
                        return
                    elseif isSpellReady(_Q) and hasElement and myHero:GetSpellData(_W).currentCd > 4 then
                        print("Adhoc Q")
                        Control.CastSpell(HK_Q,target)
                        self:delayAndDisableOrbwalker(0.4) 
                        return
                    end

                    if isSpellReady(_E) and not isSpellReady(_Q) and not isSpellReady(_W) and myHero:GetSpellData(_W).currentCd > 3.5 then
                        print("Adhoc E")
                        Control.CastSpell(HK_E,target)
                        self:delayAndDisableOrbwalker(0.4) 
                        return
                    end
                end
            end
            
            
        end
        
        
    end

    function Qiyana:Clear()
        if _nextSpellCast > Game.Timer() then return end	
        local target = HealthPrediction:GetJungleTarget()
        if not target then
            target = HealthPrediction:GetLaneClearTarget()
        end
        if target then
            
            local hasElement = self.hasGrass or self.hasRock or self.hasWater
            if not hasElement and isSpellReady(_W) then 
                self:castW()
                self:delayAndDisableOrbwalker(0.3) 
                return
            end

            if isSpellReady(_Q) and (hasElement or myHero:GetSpellData(_W).currentCd > 4) then
                Control.CastSpell(HK_Q, target)

                self:delayAndDisableOrbwalker(0.4) 
                return
            end
        end
    end
    function Qiyana:Harass()
        local target = orbwalker:GetTarget()
        if not target then
            target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        end
        
        local hasElement = self.hasGrass or self.hasRock or self.hasWater
        if not hasElement and isSpellReady(_W) then
            self:castW()
            self:delayAndDisableOrbwalker(0.3) 
            return
        end

        if target then
            if isSpellReady(_Q) and isSpellReady(_W) then
                if myHero.pos:DistanceTo(target.pos) < 600 then
                    
                    Control.CastSpell(HK_Q, target) 
                    DelayAction(function () self:castW(true, target) end, 0.25)
                    DelayAction(function () Control.CastSpell(HK_Q, target) end, 4)
                    self:delayAndDisableOrbwalker(1.3) 
                    return
                else
                    local anything = self:findBestETarget(target)
                    if anything then
                        
                        Control.CastSpell(HK_Q, target)
                        DelayAction(function () self:castW(true, target) end, 0.25)
                        DelayAction(function () Control.CastSpell(HK_Q, target) end, 4)
                        self:delayAndDisableOrbwalker(1.3) 
                        return
                    end
                end
            end
        end
    
    end

--------------------------------------------------
-- Karthus
--------------
class "Karthus"
        
    function Karthus:__init()	     
        print("devX-Karthus Loaded") 
        
        self:LoadMenu()   
        
        self.qSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.2, Radius = 160, Range = 870, Speed = math.huge, Collision = false}
        self.nextQTimer = Game.Timer()
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)    
        
           

    end

    --
    -- Menu 
    function Karthus:LoadMenu() --MainMenu
        

        self.Menu = MenuElement({type = MENU, id = "devKarthus", name = "DevX Karthus v1.0"})
            self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
                self.Menu.Combo:MenuElement({id = "Q", name = "[Q]", value = true})
                self.Menu.Combo:MenuElement({id = "W", name = "[W]", value = true})
                self.Menu.Combo:MenuElement({id = "E", name = "[E]", value = true})
                self.Menu.Combo:MenuElement({id = "WHP", name = "[W] Min HP", value = 40, min = 0, max = 100})
            
            self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass"})
                self.Menu.Harass:MenuElement({id = "Q", name = "[Q]", value = true})
                
            self.Menu:MenuElement({type = MENU, id = "LaneClear", name = "Lane Clear"})
                self.Menu.LaneClear:MenuElement({id = "Q", name = "[Q]", value = true, key=string.byte("T"), toggle = true})
            
            self.Menu:MenuElement({type = MENU, id = "JungleClear", name = "Jungle Clear"})
                self.Menu.JungleClear:MenuElement({id = "Q", name = "[Q]", value = true})
                self.Menu.JungleClear:MenuElement({id = "E", name = "[E]", value = true})
                self.Menu.JungleClear:MenuElement({id = "EMana", name = "[E] - Min Mana", value = 40, min = 0, max = 100})
            
            self.Menu:MenuElement({type = MENU, id = "AutoUlt", name = "Ultimate"})
                self.Menu.AutoUlt:MenuElement({id = "MinDead", name = "Dead - Min # of Enemies to kill", value = 1, min=1, max=5})
                self.Menu.AutoUlt:MenuElement({id = "MinAlive", name = "Alive - Min # of Enemies to kill", value = 1, min=1, max=5})
                self.Menu.AutoUlt:MenuElement({id = "AliveBlockRange", name = "Don't use R if enemy is within range", value = 1200, min=200, max=2000})
    end

    function Karthus:Draw()
        
        local hero2d = myHero.pos2D
        if self.Menu.LaneClear.Q:Value() then
            Draw.Text("Lane Clear Enabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 0, 255, 0))
        else
            Draw.Text("Lane Clear Disabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 255, 0, 0))
        end

        
        for i, champ in pairs(getEnemyHeroes()) do
            			
            local RDmg = getdmg("R", champ)
            local Hp = champ.health + (6 * champ.hpRegen)
            if champ.health <= RDmg then
                Draw.Text(champ.charName .. " - " .. Hp .. " % HP", 15, 10, 70 + i*15, Draw.Color(255, 0, 255, 0))
            end	
        end
    end


    --------------------------------------------------
    -- Callbacks
    ------------
    function Karthus:onTickEvent()
        self:AutoUlt()

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            self:LaneClear()
        end
    end
    
    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    

    function Karthus:Combo()
        
        local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if target   then
            orbwalker:SetAttack(false)
            local distance = target.pos:DistanceTo(myHero.pos)
            if self.Menu.Combo.E:Value() and isSpellReady(_Q) and distance <= 875 and  self.nextQTimer < Game.Timer() then
                castSpell(self.qSpellData, HK_Q, target)
                self.nextQTimer = Game.Timer() + 0.6
            end

            
            if self.Menu.Combo.W:Value() and isSpellReady(_W) and myHero.pos:DistanceTo(target.pos) < 800 then
                if myHero.pos:DistanceTo(target.pos) > 500 and target.health/target.maxHealth <= self.Menu.Combo.WHP:Value() / 100 then
                    local castPos = target.pos:Extended(myHero.pos, -300)
                    Control.CastSpell(HK_W, castPos)
                end
            end	
            
            if not myHero.dead then
                    
                local num_enemies = #getEnemyHeroesWithinDistance(550)
                local toggled = doesMyChampionHaveBuff("KarthusDefile")
                if num_enemies == 0 and toggled then
                    Control.CastSpell(HK_E)
                elseif self.Menu.Combo.E:Value() and num_enemies >= 1 and not toggled then
                    Control.CastSpell(HK_E)
                end
            end
            orbwalker:SetAttack(true)
        end
    end

    function Karthus:Harass()
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target and not _G.SDK.Attack:IsActive()  then
            local distance = target.pos:DistanceTo(myHero.pos)
            if isSpellReady(_Q) and distance <= 900  and  self.nextQTimer < Game.Timer() and self.Menu.Harass.Q:Value() then
                castSpell(self.qSpellData, HK_Q, target)
                self.nextQTimer = Game.Timer() + 0.6
            end
        end
    end

    function Karthus:LaneClear()
        local toggled = doesMyChampionHaveBuff("KarthusDefile")
        local target = HealthPrediction:GetJungleTarget()
        local jungleClear = true
        if not target then
            jungleClear = false
            target = HealthPrediction:GetLaneClearTarget()
            if not target then
                local minions = _G.SDK.ObjectManager:GetEnemyMinions(870, false, true)
                local bestTarget = nil
                for i, minion in pairs(minions) do
                    local dmg = getdmg("Q", minion)
                    hp = HealthPrediction:GetPrediction(minion,self.qSpellData.Delay)
                    if minion.health <= dmg then
                        bestTarget = target
                        break
                    end
                end
                if not bestTarget and #minions > 0 then
                    target = minions[0]
                else
                    target = bestTarget
                end
            end
        end
        if target then
            orbwalker:SetAttack(false)
            if (isSpellReady(_Q) or myHero.dead) and  self.nextQTimer < Game.Timer() then
                
                if  (jungleClear and self.Menu.JungleClear.Q:Value()) or 
                    (not jungleClear and self.Menu.LaneClear.Q:Value())  
                then
                    Control.CastSpell(HK_Q, target)
                    self.nextQTimer = Game.Timer() + 0.6
                end
            end
            if not toggled and target.pos:DistanceTo(myHero.pos) < 550 and myHero.mana/myHero.maxMana > 0.4 and jungleClear and self.Menu.JungleClear.E:Value() then
               Control.CastSpell(HK_E)
            elseif toggled and myHero.mana/myHero.maxMana <= 0.4   then
                Control.CastSpell(HK_E)
            end
            orbwalker:SetAttack(true)
        elseif toggled then
            Control.CastSpell(HK_E)
        end
    end

    function Karthus:AutoUlt()
        if not isSpellReady(_R) then return end

        local count = 0
        for i, enemy in  pairs(getEnemyHeroes()) do 					
            local RDmg = getdmg("R", enemy)
            local Hp = enemy.health + (6 * enemy.hpRegen)
            if enemy.health <= RDmg then
                count = count + 1
            end	
        end
	    
        if doesMyChampionHaveBuff("KarthusDeathDefiedBuff") and count >= self.Menu.AutoUlt.MinDead:Value() then
            Control.CastSpell(HK_R)
        elseif count >= self.Menu.AutoUlt.MinAlive:Value() then
            local enemiesInRange = #getEnemyHeroesWithinDistance(self.Menu.AutoUlt.AliveBlockRange:Value())
            
            if enemiesInRange == 0  then
                Control.CastSpell(HK_R)
            end

        end
    end


--------------------------------------------------
-- Rengar
--------------
class "Rengar"
        
    function Rengar:__init()	     
        print("devX-Rengar Loaded") 
        
        self:LoadMenu()   
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)    

        self.lastAuto = Game.Timer()
        self.lastEStun = Game.Timer()

        orbwalker:OnPostAttack(function(...) self:PostAuto(...) end) 
        self.lastMode = ""
        self.lastHP = myHero.health
        self.nextCheck = Game.Timer()
        self.eSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Radius = 70, Range = 1000, Speed = 1500, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    end

    --
    -- Menu 
    function Rengar:LoadMenu() --MainMenu
        

        self.Menu = MenuElement({type = MENU, id = "devRengar", name = "DevX Rengar Alpha"})
        self.Menu:MenuElement({name = "Empowered [Q] or [E]", id = "EmpoweredQ", value = true, key=string.byte("T"), toggle = true})
    end

    function Rengar:Draw()
        local hero2d = myHero.pos2D
        if self.Menu.EmpoweredQ:Value() then
            Draw.Text("Empowered [Q] - [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 0, 255, 0))
        else
            Draw.Text("Empowered [E] - [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 255, 0, 0))
        end

    end


    --------------------------------------------------
    -- Callbacks
    ------------
    function Rengar:onTickEvent()
        if doesMyChampionHaveBuff("RengarR") then
            self.UltActive = true 
        else
            self.UltActive = false
        end
        
        local isImmobile, duration = isTargetImmobile(myHero)
        if myHero.mana == 4 and isSpellReady(_W) and isImmobile then
            Control.CastSpell(HK_W)
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            
            self:LaneClear()
        end
    end
    
    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    
    function Rengar:useQ(target)
        

        Control.CastSpell(HK_Q) 
        orbwalker:__OnAutoAttackReset()
        DelayAction( function() orbwalker:Attack(target) end, 0.12)
        
        _nextSpellCast = Game.Timer() + 0.41
    end

    function Rengar:isDashing()
        return myHero.pathing.isDashing and myHero.pathing.dashSpeed > 500
    end


    function Rengar:Combo()
        
        self.lastMode = "combo"
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target   then

            local numAllies = #getAllyHeroesWithinDistanceOfUnit(target.pos, 800)

            if self.UltActive then
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < 850 then 
                    Control.CastSpell(HK_Q) 
                end
                if isSpellReady(_E) and self:isDashing() then 
                    Control.CastSpell(HK_E, target) 
                    if myHero.mana == 4 then self.lastEStun = Game.Timer() end
                end
            else
                
                local isImmobile, duration = isTargetImmobile(myHero)
        
                if myHero.mana == 4 and isSpellReady(_W) and (isImmobile or myHero.health / myHero.maxHealth < 0.3) then
                    Control.CastSpell(HK_W, myHero)
                end

                if _G.SDK.Attack:IsActive() then return end
                if Game.Timer() - self.lastAuto > 1.5 then return end

                if isSpellReady(_Q) then 
                    if  myHero.pos:DistanceTo(target.pos) < 400 and 
                        (
                            myHero.mana < 4 or 
                            self.Menu.EmpoweredQ:Value() or 
                            (
                                self.lastEStun < Game.Timer() - 10 and
                                numAllies < 1
                            )
                        ) 
                        and not isImmobile 
                    then	
                        self:useQ(target)
                        return
                    end
                end
                
                if _nextSpellCast > Game.Timer() then return end	
                    if isSpellReady(_E) then 
                            
                        if  myHero.pos:DistanceTo(target.pos) < 1000 and 
                            (
                                myHero.mana < 4 or 
                                not self.Menu.EmpoweredQ:Value() or
                                (
                                    self.lastEStun >Game.Timer() - 10 and
                                    numAllies >= 1
                                )
                            ) then
                            castSpell(self.eSpellData, HK_E, target)
                            if myHero.mana == 4 then self.lastEStun = Game.Timer() end
                            return
                        end
                    end
                    if isSpellReady(_W) and myHero.mana < 4 then 
                        if myHero.pos:DistanceTo(target.pos) < 450 then
                            Control.CastSpell(HK_W)
                            return
                        end
                    end
                    
                end
            end
    end


    function Rengar:Harass()
            local target = orbwalker:GetTarget();
    end

    function Rengar:PostAuto()
        
        self.lastAuto = Game.Timer()
        if myHero.mana == 4 and not self.Menu.EmpoweredQ:Value() and self.lastMode == "combo" then return end

        local target = orbwalker:GetTarget();

        
        local isImmobile, duration = isTargetImmobile(myHero)
        
        if myHero.mana == 4 and isSpellReady(_W) and isImmobile  then
            Control.CastSpell(HK_W, myHero)
            return
        end

        if target ~= nil and isSpellReady(_Q) then
            self:useQ(target)
            return
        end

    end

    function Rengar:LaneClear()

        if _G.SDK.Attack:IsActive() then return end
        if Game.Timer() - self.lastAuto > 0.45 then return end
        self.lastMode = "clear"

        local jungle = HealthPrediction:GetJungleTarget()
        if jungle == nil then
            jungle = HealthPrediction:GetLaneClearTarget()
        end
        if jungle ~= nil then
            
            if myHero.mana == 4 and isSpellReady(_W) and myHero.health / myHero.maxHealth < 0.4 then
                Control.CastSpell(HK_W, myHero)
                return
            end

            if isSpellReady(_Q) then 
                if myHero.pos:DistanceTo(jungle.pos) < 400 then	
                    self:useQ(jungle)
                    return
                end
            end
            if _nextSpellCast > Game.Timer() then return end	

            if myHero.mana < 4 and not isSpellReady(_Q) then 
                if isSpellReady(_E) then
                    Control.CastSpell(HK_E, jungle);
                    return
                end
                
                if isSpellReady(_W) then
                    Control.CastSpell(HK_W);
                    return
                end
            end
        end
    end

    
--------------------------------------------------
-- Soraka
--------------
class "Soraka"
        
function Soraka:__init()	     
    print("devX-Soraka Loaded") 
    
    self:LoadMenu()   
    Callback.Add("Draw", function() self:Draw() end)           
    Callback.Add("Tick", function() self:onTickEvent() end)    
       

    self.qSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.5, Radius = 235, Range = 800, Speed = 1750, Collision = false}
    self.eSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.5, Radius = 250, Range = 925, Speed = 1750, Collision = false}
end

--
-- Menu 
function Soraka:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devSoraka", name = "DevX Soraka"})

    self.Menu:MenuElement({id = "WHP", name = "W Min. HP %", value = 50, min=0, max=100})
    self.Menu:MenuElement({id = "UltHP", name = "Ultimate Min. HP %", value = 20, min=0, max=100})
    self.Menu:MenuElement({type = MENU, id = "Draw", name = "Draw"})
        self.Menu.Draw:MenuElement({id = "Q", name = "[Q]", value = false})
        self.Menu.Draw:MenuElement({id = "E", name = "[E]", value = false})
    self.Menu:MenuElement({type = MENU, id = "UltWhitelist", name = "Ultimate white list"})
    
    for i = 1, GameHeroCount() do
        local hero = GameHero(i)
        if hero and hero.isAlly then 
            self.Menu.UltWhitelist:MenuElement({id = hero.charName, name = hero.charName, toggle = true, value = true})
        end
    end
end

function Soraka:Draw()
    if self.Menu.Draw.Q:Value() then
        Draw.Circle(myHero, 790, 2, Draw.Color(255, 127, 234, 19))
    end
    if self.Menu.Draw.E:Value() then
        Draw.Circle(myHero, 900, 2, Draw.Color(255, 0, 0, 0))
    end
end


--------------------------------------------------
-- Callbacks
------------
function Soraka:onTickEvent()

    self:autoHeal()
    self:EonImmobile()

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end
    
end

----------------------------------------------------
-- Combat Modes
---------------------

function Soraka:EonImmobile()
    local heroes = getEnemyHeroesWithinDistance(920)
    if heroes then
        for i, enemy in pairs(heroes) do
            if enemy and not enemy.dead then
                if isTargetImmobile(enemy) then
                    castSpell(self.eSpellData, HK_E, enemy)
                end
            end
        end
    end
end

function Soraka:autoHeal()
    local healTarget = nil
    for i = 1, GameHeroCount() do
        local hero = GameHero(i)
        if hero and not hero.dead and hero.isAlly then 
            if isSpellReady(_R) and self.Menu.UltWhitelist[hero.charName] and self.Menu.UltWhitelist[hero.charName]:Value() and hero.health / hero.maxHealth * 100 < self.Menu.UltHP:Value() then
                Control.CastSpell(HK_R)
            end
            if isSpellReady(_W) and not hero.isMe and hero.health / hero.maxHealth * 100 < self.Menu.WHP:Value() and myHero.pos:DistanceTo(hero.pos) <= 550  then
                Control.CastSpell(HK_W, hero)
            end
        end
    end
end

function Soraka:Combo()
    local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target then
        if isSpellReady(_Q) and target.pos:DistanceTo(myHero.pos) < self.qSpellData.Range then
            castSpell(self.qSpellData, HK_Q, target)
        end
        if isSpellReady(_E) and target.pos:DistanceTo(myHero.pos) < self.eSpellData.Range then
            castSpell(self.eSpellData, HK_E, target)
        end
    end
end


function Soraka:Harass()
    local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    if target then
        if isSpellReady(_Q) and target.pos:DistanceTo(myHero.pos) < self.qSpellData.Range then
            castSpell(self.qSpellData, HK_Q, target)
        end
        
    end
    
end


--------------------------------------------------
-- Rengar
--------------
class "Mordekaiser"
        
    function Mordekaiser:__init()	     
        print("devX-Mordekaiser Loaded") 
        
        self:LoadMenu()   
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)    
        
        self.qSpell = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.4, Radius = 200, Range = 675, Speed = MathHuge, Collision = false}
        self.eSpell = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.9, Radius = 120, Range = 900, Speed = MathHuge, Collision = false}

    end

    --
    -- Menu 
    function Mordekaiser:LoadMenu() --MainMenu
        

        self.Menu = MenuElement({type = MENU, id = "devMordekaiser", name = "DevX Mordekaiser"})


        self.Menu:MenuElement({type = MENU, id = "WSpell", name = "[W] Logic"})
            self.Menu.WSpell:MenuElement({id = "Combo", name = "Combo vs Auto", toggle = true, value = false})
            self.Menu.WSpell:MenuElement({id = "WHP", name = "Use W below HP %", value =  50, min=0, max = 100 })
            self.Menu.WSpell:MenuElement({id = "WRange", name = "Only use when enemies within range", value = 1200, min=0, max = 2000 })
            
        self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
            self.Menu.Combo:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})
            self.Menu.Combo:MenuElement({id = "E", name = "[E]", toggle = true, value = true})

        self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass"})
            self.Menu.Harass:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})
            self.Menu.Harass:MenuElement({id = "E", name = "[E]", toggle = true, value = true})

        self.Menu:MenuElement({type = MENU, id = "Clear", name = "Lane Clear"})
            self.Menu.Clear:MenuElement({id = "Enemies", name = "Try to hit enemies", toggle = true, value = true})
            self.Menu.Clear:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})
            self.Menu.Clear:MenuElement({id = "E", name = "[E]", toggle = true, value = true})

        self.Menu:MenuElement({type = MENU, id = "JClear", name = "Jungle Clear"})
            self.Menu.JClear:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})
            self.Menu.JClear:MenuElement({id = "E", name = "[E]", toggle = true, value = true})
        

    end

    function Mordekaiser:Draw()
    end


    --------------------------------------------------
    -- Callbacks
    ------------
    function Mordekaiser:onTickEvent()

        if not self.Menu.WSpell.WHP:Value() and isSpellReady(_W) and myHero.health/myHero.maxHealth * 100 <= self.Menu.WSpell.WHP:Value() then
            local numEnemies = #getEnemyHeroesWithinDistance(self.Menu.WSpell.WRange:Value())
            if numEnemies > 0 then
                Control.CastSpell(HK_W)
            end
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            self:LaneClear()
        end
    end
    
    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    
    function Mordekaiser:Combo()
        if _G.SDK.Attack:IsActive() then return end

        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target then
                
            if self.Menu.WSpell.WHP:Value() and isSpellReady(_W) and myHero.health/myHero.maxHealth * 100 <= self.Menu.WSpell.WHP:Value() then
                Control.CastSpell(HK_W)
            end

            if self.Menu.Combo.E:Value() and isSpellReady(_E) and myHero.pos:DistanceTo(target.pos) < self.eSpell.Range then
                castSpell(self.eSpell, HK_E, target)
            end

            if self.Menu.Combo.Q:Value() and isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < self.qSpell.Range then
                castSpell(self.qSpell, HK_Q, target)
            end

        end
    end


    function Mordekaiser:Harass()
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target then
            
            if self.Menu.Harass.E:Value() and isSpellReady(_E) and myHero.pos:DistanceTo(target.pos) < self.eSpell.Range then
                castSpell(self.eSpell, HK_E, target)
            end
            
            if self.Menu.Harass.Q:Value() and isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < self.qSpell.Range then
                castSpell(self.qSpell, HK_Q, target)
            end

        end
    end

    function Mordekaiser:LaneClear()

        if _G.SDK.Attack:IsActive() then return end

        local isJungle = true
        local target = HealthPrediction:GetJungleTarget()
        if target == nil then
            isJungle = false

            local bestCount = 0
            local bestTarget = nil
            for i = 1, GameMinionCount() do
                local minion1 = GameMinion(i)
                local count = 0
                
                if minion1 and minion1.isEnemy and not minion1.dead and minion1.pos:To2D().onScreen  then
                    local targetPosition = minion1.pos  + Vector( minion1.pos - myHero.pos ):Normalized() * self.qSpell.Range
                    for j = 1, GameMinionCount() do
                        local minion2 = GameMinion(j)
                        
                        if minion2 and minion2.isEnemy and not minion2.dead and minion2.pos:To2D().onScreen  then
                            local spellLine = ClosestPointOnLineSegment(minion2.pos, myHero.pos, targetPosition)
                            
                            if minion2.pos:DistanceTo(spellLine) < self.eSpell.Radius then
                                count = count + 1
                            end
                        end
                    end
                    if self.Menu.Clear.Enemies:Value() then
                        local heroes = getEnemyHeroesWithinDistance(920)
                        if heroes then
                            for i, enemy in pairs(heroes) do
                                if enemy and not enemy.dead and enemy.pos:To2D().onScreen  then
                                    local spellLine = ClosestPointOnLineSegment(enemy.pos, myHero.pos, targetPosition)
                                    
                                    if enemy.pos:DistanceTo(spellLine) < self.eSpell.Radius then
                                        count = count + 2.5
                                    end
                                end
                            end
                        end
                    end
                    if count > bestCount then
                        bestCount = count
                        bestTarget = minion1
                    end
                end
            end
            target = bestTarget
        end
        if target ~= nil then

            if isSpellReady(_E) and ((isJungle and self.Menu.JClear.E:Value()) or (not isJungle and self.Menu.Clear.E:Value())) then
                local targetPosition = target.pos  + Vector( target.pos - myHero.pos ):Normalized() * self.eSpell.Range
                Control.CastSpell(HK_E, targetPosition)
            end
            if isSpellReady(_Q) and ((isJungle and self.Menu.JClear.Q:Value()) or (not isJungle and self.Menu.Clear.Q:Value()))then
                Control.CastSpell(HK_Q, target)
            end
        end
    end

    
--------------------------------------------------
-- Nidalee
--------------
class "Nidalee"
        
function Nidalee:__init()	     
    print("devX-Nidalee Loaded") 
    
    self:LoadMenu()   
    self.rTimer = Game.Timer()
    Callback.Add("Draw", function() self:Draw() end)           
    Callback.Add("Tick", function() self:onTickEvent() end)    
    orbwalker:OnPostAttack(function(...) self:onPostAttack(...) end) 

    self.qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Radius = 40, Range = 1500, Speed = 1300, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
end

--
-- Menu 
function Nidalee:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devNidalee", name = "DevX Nidalee"})

end

function Nidalee:Draw()
end


--------------------------------------------------
-- Callbacks
------------
function Nidalee:onTickEvent()

    

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
        self:Combo()
    end

    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
        self:Harass()
    end
    
    if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
        self:Clear()
    end
end

----------------------------------------------------
-- Combat Modes
---------------------

function Nidalee:updateRanges(target)
    if myHero:GetSpellData(_Q).name == "JavelinToss" then
        self.qRange = 1500
    else
        self.qRange = 400
    end

    if myHero:GetSpellData(_W).name == "Bushwhack" then
        self.wRange = 800
    else
        if doesThisChampionHaveBuff(target, "NidaleePassiveHunting")  then
            self.wRange = 750
        else
            self.wRange = 375
        end
    end

    self.eRange = 350
end

function Nidalee:castW(target)
    local targetPosition = target.pos
            
    if myHero:GetSpellData(_W).name == "Bushwhack" then
        targetPosition = target:GetPrediction(math.huge, 0.25)
    elseif doesThisChampionHaveBuff(target, "NidaleePassiveHunting") then
        self.rTimer = Game.Timer() + 2.05
    end
    Control.CastSpell(HK_W, targetPosition)
end

function Nidalee:onPostAttack()
    local target = orbwalker:GetTarget();
    self:updateRanges(target)
    if target then
        local distance = myHero.pos:DistanceTo(target.pos)
        
        self:updateRanges(target)

        if isSpellReady(_Q) and distance < self.qRange then
            Control.CastSpell(HK_Q, target)
            return
        end

        if isSpellReady(_W) and distance < self.wRange then
            self:castW(target)
            return
        end

        
        if isSpellReady(_E) and distance < self.eRange then
            if myHero:GetSpellData(_E).name ~= "PrimalSurge" then
                Control.CastSpell(HK_E, target)
                return
            end
        end

        

    end
end


function Nidalee:Clear()
    
    local target = HealthPrediction:GetJungleTarget()
    if not target then
        target = HealthPrediction:GetLaneClearTarget()
    end
    if target then
        self:updateRanges(target)
        local distance = myHero.pos:DistanceTo(target.pos)
        
        if isSpellReady(_W) and distance > 325 and distance < self.wRange and self.wRange == 750 then
            self:castW(target)
        end

        if self:changeUltimate(distance) then
            Control.CastSpell(HK_R, target)
            DelayAction(
                    function ()
                        orbwalker:__OnAutoAttackReset() 
                    end
                ,
                0.05
            )
            return
        end

        if isSpellReady(_E) and distance < self.eRange then
            if myHero:GetSpellData(_E).name == "PrimalSurge"  and myHero.health / myHero.maxHealth < 0.65 then
                Control.CastSpell(HK_E, myHero)
            end
        end

        if _G.SDK.Attack:IsActive() then return end


        if isSpellReady(_Q) and distance < self.qRange then
            Control.CastSpell(HK_Q, target)
            return
        end

        if isSpellReady(_E) and distance < self.eRange then
            if myHero:GetSpellData(_E).name == "PrimalSurge"  and myHero.health / myHero.maxHealth < 0.65 then
                Control.CastSpell(HK_E, myHero)
                return
            end
        end
    end
end

function Nidalee:changeUltimate(distance)
    return  isSpellReady(_R) and 
            Game.Timer() > self.rTimer and
            (
                (
                    (   
                        not isSpellReady(_W) or distance > self.wRange
                    ) and
                    (
                        not isSpellReady(_Q) or distance > self.qRange
                    ) and 
                    (
                        not isSpellReady(_E) or distance > self.eRange
                        or (myHero:GetSpellData(_E).name == "PrimalSurge" and myHero.health / myHero.maxHealth > 0.5)
                    ) 
                )
                or  (
                    not myHero:GetSpellData(_Q).name == "JavelinToss" and distance > 800
                )
            )   
end
function Nidalee:Combo()
    local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
    
    if target then
        local distance = myHero.pos:DistanceTo(target.pos)
        self:updateRanges(target)
        if self:changeUltimate(distance) then
            Control.CastSpell(HK_R, target)
            DelayAction(
                    function ()
                        orbwalker:__OnAutoAttackReset() 
                    end
                ,
                0.05
            )
            return
        end

        
        if isSpellReady(_W) and distance < self.wRange then
            local targetPosition = target.pos
            
            if myHero:GetSpellData(_W).name == "Bushwhack" then
            elseif doesThisChampionHaveBuff(target, "NidaleePassiveHunting") then
                self.rTimer = Game.Timer() + 2.05
                Control.CastSpell(HK_W, targetPosition)
                return
            end
        end

        
        if _G.SDK.Attack:IsActive() then return end

        if isSpellReady(_Q) and distance < self.qRange then
            castSpell(self.qSpellData, HK_Q, target)
            return
        end

        if doesThisChampionHaveBuff(target, "NidaleePassiveHunting") and myHero:GetSpellData(_Q).name == "JavelinToss" then
            
            Control.CastSpell(HK_R, target)
            DelayAction(
                    function ()
                        orbwalker:__OnAutoAttackReset() 
                    end
                ,
                0.05
            )
            return
        end

        if isSpellReady(_E) and distance < self.eRange then
            if myHero:GetSpellData(_E).name == "PrimalSurge"  and myHero.health / myHero.maxHealth < 0.65 then
                Control.CastSpell(HK_E, myHero)
                return
            end
        end

        
    end
end


function Nidalee:Harass()
    local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
    
    self:updateRanges()
    if target then
        local distance = myHero.pos:DistanceTo(target.pos)
        
        if isSpellReady(_Q) and myHero:GetSpellData(_Q).name == "JavelinToss" and distance < self.qRange then
            castSpell(self.qSpellData, HK_Q, target)
            return
        end
    end
end

class "Ziggs"
    function Ziggs:__init()	     
        print("devX-Ziggs Loaded") 
        self:LoadMenu()   
        
        self.qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Radius = 240, Range = 1400, Speed = 1700, Collision = false}
        self.wSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.25, Radius = 325, Range = 1000, Speed = 1750, Collision = false}
        self.eSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.25, Radius = 325, Range = 900, Speed = 1550, Collision = false}
        self.rSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 0.375, Radius = 525, Range = 5000, Speed = 2250, Collision = false}
     
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:Draw() end)    
    end


    --
    -- Menu 
    function Ziggs:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devZiggs", name = "devZiggs v1.0"})

        self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
            self.Menu.Combo:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})
            self.Menu.Combo:MenuElement({id = "E", name = "[E]", toggle = true, value = true})

        self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass"})
            self.Menu.Harass:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true})

        self.Menu:MenuElement({type = MENU, id = "Clear", name = "Lane Clear"})
            self.Menu.Clear:MenuElement({id = "Q", name = "[Q]", toggle = true, value = true, key=string.byte("T")})
            self.Menu.Clear:MenuElement({id = "E", name = "[E]", toggle = true, value = true, key=string.byte("T")})

        
        self.Menu:MenuElement({type = MENU, id = "Draw", name = "Draw"})
        self.Menu.Draw:MenuElement({id = "Bounce", name = "Draw Bounce Position", toggle = true, value = false})
    end

    function Ziggs:onTickEvent()
        if isSpellReady(_R) then
            self:AutoR()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
        
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            self:Clear()
        end
    end

    function Ziggs:Draw()
        if self.Menu.Draw.Bounce:Value() then
            local position = Vector(mousePos)
            local distance = math.min(myHero.pos:DistanceTo(position),850)
            local direction = (position - myHero.pos):Normalized()
            
            local bounce1 = myHero.pos + direction * distance
            local bounce2 = bounce1 + direction * distance * 0.4
            local bounce3 = bounce2 + direction * distance * 0.6 * 0.4

            Draw.Circle(bounce1, 50, 1, Draw.Color(225, 225, 0, 10))
            Draw.Circle(bounce2, 50, 1, Draw.Color(225, 225, 0, 10))
            Draw.Circle(bounce3, 50, 1, Draw.Color(225, 225, 0, 10))
        end

    end
    function Ziggs:AutoR()
        
        local target = _G.SDK.TargetSelector:GetTarget(5000, _G.SDK.DAMAGE_TYPE_MAGICAL);

        if target and target.pos:DistanceTo(myHero.pos) > 1400 then
            dmg = getdmg("R", target)

            if dmg > target.health then

                if target.pos:To2D().onScreen then
                    print("Cast R")
                    castSpell(self.rSpellData, HK_R, target)
                    return
                else
                    print(target.charName)
                end
            end
        end
        
        target = _G.SDK.TargetSelector:GetTarget(500, _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target and myHero.pos:DistanceTo(target.pos) < 320 then
            castSpell(self.wSpellData, HK_W, target)
            DelayAction(
                function () Control.CastSpell(HK_W) end,
                0.1
            )
        end
    end

    function Ziggs:Combo()
            
        if _G.SDK.Attack:IsActive() then return end
        local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if target then
            local distance = myHero.pos:DistanceTo(target.pos)
            if self.Menu.Combo.Q:Value() and isSpellReady(_Q) and distance < self.qSpellData.Range then
                self:useQ(target)
            end

            if self.Menu.Combo.E:Value() and isSpellReady(_E) and distance < self.eSpellData.Range then
                castSpell(self.eSpellData, HK_E, target)
                
            end
        end
    end

    function Ziggs:Harass()
        if _G.SDK.Attack:IsActive() then return end
        local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
        if target then
            local distance = myHero.pos:DistanceTo(target.pos)
            
            if self.Menu.Harass.Q:Value() and isSpellReady(_Q) and distance < self.qSpellData.Range then
                self:useQ(target)
            end
        end
    end

    function Ziggs:Clear()
        local target = HealthPrediction:GetJungleTarget()
        if not target then
            target = HealthPrediction:GetLaneClearTarget()
        end
        if target then
            if self.Menu.Clear.Q:Value() and isSpellReady(_Q) then
                bestPosition, bestCount = getAOEMinion(850, self.qSpellData.Radius)
                if bestCount > 0 then 
                    Control.CastSpell(HK_Q, bestPosition)
                end
            end

            if self.Menu.Clear.E:Value() and isSpellReady(_E) then
                
                bestPosition, bestCount = getAOEMinion(self.eSpellData.Range, self.eSpellData.Radius)
                if bestCount > 2 then 
                    Control.CastSpell(HK_E, bestPosition)
                end
            end
        end
    end
    function Ziggs:useQ(target)
            
        local pred = GGPrediction:SpellPrediction(self.qSpellData)
        pred:GetPrediction(target, myHero)

        if pred:CanHit(GGPrediction.HITCHANCE_NORMAL) then

            local position = Vector(pred.CastPosition)
            local unitPos = Vector(pred.UnitPosition)
            if position:DistanceTo(unitPos) < 100 then
                Control.CastSpell(HK_Q, position)    
            else
                local distance = math.min(myHero.pos:DistanceTo(position),850)
                local direction = (position - myHero.pos):Normalized()
                
                local bounce1 = myHero.pos + direction * distance
                local bounce2 = bounce1 + direction * distance * 0.4
                local bounce3 = bounce2 + direction * distance * 0.6 * 0.4
                
                -- bounce 1
                local minionsBounce1 = getEnemyMinionsWithinDistanceOfLocation(bounce1, 200)
                if #minionsBounce1 > 0 then
                    local minion = minionsBounce1[0]
                    if minion and bounce1:DistanceTo(unitPos) < 240 then
                        Control.CastSpell(HK_Q, position)
                    else
                        return
                    end
                end

                -- bounce 2
                local minionsBounce2 = getEnemyMinionsWithinDistanceOfLocation(bounce2, 200)
                if #minionsBounce2 > 0 then
                    local minion = minionsBounce2[0]
                    if minion and bounce2:DistanceTo(unitPos) < 240 then
                        Control.CastSpell(HK_Q, position)
                    else
                        return
                    end
                end

                -- bounce 3
                local minionsBounce3 = getEnemyMinionsWithinDistanceOfLocation(bounce3, 200)
                if #minionsBounce3 > 0 then
                    local minion = minionsBounce3[0]
                    if minion and bounce3:DistanceTo(unitPos) < 240 then
                        Control.CastSpell(HK_Q, position)
                    else
                        return
                    end
                end

                
                Control.CastSpell(HK_Q, position)
            end

        end
    end

class "Kindred"
    function Kindred:__init()	     
        print("devX-Kindred Loaded") 
        self:LoadMenu()   
        self.lastAuto = Game.Timer()
            
        orbwalker:OnPostAttack(function(...) self:PostAuto(...) end) 
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:Draw() end)    
    end
    
    function Kindred:onTickEvent()

        self:AutoR()

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end
    
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end
        
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            self:Clear()
        end
    end

    function Kindred:AutoR()
        if not isSpellReady(_R) then return end

        local allies = getAllyHeroesWithinDistanceOfUnit(myHero.pos, 501)
        
        for k, ally in pairs(allies) do
            if self.Menu.AutoR[ally.charName] and ally.health / ally.maxHealth < 0.23 then
                local enemies = getEnemyHeroesWithinDistanceOfUnit(ally.pos, 800)
                if #enemies >= 1 then
                    Control.CastSpell(HK_R)
                    return
                end 
            end
        end

        if myHero.health / myHero.maxHealth < 0.23 then
            local enemies = getEnemyHeroesWithinDistanceOfUnit(myHero.pos, 800)
            if #enemies >= 1 then
                Control.CastSpell(HK_R)
                return
            end 
        end
    end

    function Kindred:Draw()

    end
    function Kindred:useQ(pos)
        Control.CastSpell(HK_Q, pos) 
        orbwalker:__OnAutoAttackReset()
        DelayAction( function() orbwalker:Attack(target) end, 0.12)
    end
    function Kindred:PostAuto()
        
        self.lastAuto = Game.Timer()
        if self.mode == "harass" then return end

        local target = orbwalker:GetTarget();
        if target then
            if isSpellReady(_Q) then
                self:useQ(mousePos)
            end
        end
    end
    function Kindred:Combo()
        if _G.SDK.Attack:IsActive() or not orbwalker:CanMove() then return end

        self.mode = "combo"
        
        local target = _G.SDK.TargetSelector:GetTarget(math.max(myHero.range + 5, 700), _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target then
            local distance = getDistance(myHero.pos, target.pos)
            if distance > 450 then 
                Control.CastSpell(HK_Q, mousePos)
                return
            end
            
            if Game.Timer() - self.lastAuto > 0.45 then return end
            if isSpellReady(_Q) then return end

            if isSpellReady(_W) and distance < 500 then
                Control.CastSpell(HK_W)
                return
            end

            if isSpellReady(_E) and distance < myHero.boundingRadius + myHero.range and target.health/target.maxHealth < 0.75 then
                Control.CastSpell(HK_E, target)
                return
            end
        end
    end

    function Kindred:Harass()
        if _G.SDK.Attack:IsActive() or not orbwalker:CanMove() then return end
        if Game.Timer() - self.lastAuto > 0.45 then return end

        
        self.mode = "harass"
        
        local target = _G.SDK.TargetSelector:GetTarget(math.max(myHero.range + 5, 700), _G.SDK.DAMAGE_TYPE_MAGICAL);
        if target then
            local distance = getDistance(myHero.pos, target.pos)
            
            if isSpellReady(_W) and distance < 500 then
                Control.CastSpell(HK_W)
                return
            end
            if isSpellReady(_E) and distance < myHero.boundingRadius + myHero.range and target.health/target.maxHealth < 0.75  then
                Control.CastSpell(HK_E, target)
                return
            end
        end
    end

    function Kindred:Clear()
        
        if _G.SDK.Attack:IsActive() then return end
        if Game.Timer() - self.lastAuto > 0.45 then return end

        local jungle = HealthPrediction:GetJungleTarget()
        if jungle == nil then
            jungle = HealthPrediction:GetLaneClearTarget()
        end
        if jungle ~= nil then
            local distance = getDistance(myHero.pos, jungle.pos)
            if isSpellReady(_Q) then return end

            if isSpellReady(_E) and distance < myHero.boundingRadius + myHero.range then
                Control.CastSpell(HK_E, jungle)
                return
            end
            if isSpellReady(_W) and distance < 500 then
                Control.CastSpell(HK_W)
                return
            end
        end
    end
    function Kindred:LoadMenu()
        self.Menu = MenuElement({type = MENU, id = "devKindred", name = "devKindred v1.0"})
        self.Menu:MenuElement({type = MENU, id = "AutoR", name = "Auto R Ally"})

        
        for i = 1, Game.HeroCount() do
            local obj = Game.Hero(i)
            if obj.isAlly then
                self.Menu.AutoR:MenuElement({id = obj.charName, name = obj.charName, value = true})
            end
        end
    end   

class "Taliyah"
    function Taliyah:__init()	     
        print("devX-Taliyah Loaded") 
        self:LoadMenu()   
             
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:Draw() end)    
    end

    function Taliyah:onTickEvent()

    end

    function Taliyah:Draw()

    end

    function Taliyah:LoadMenu()
        self.Menu = MenuElement({type = MENU, id = "devTaliyah", name = "devTaliyah v1.0"})

    end   



class "Kled"
    function Kled:__init()	     
        print("devX-Kled Loaded") 
        self:LoadMenu()   
        
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:Draw() end)    
        self.qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.066, Speed = 1200, Range = 1100, Radius = 60, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    
    end

    function Kled:onTickEvent()
        
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end
    end

    function Kled:Combo()

    end

    function Kled:Draw()

    end

    function Kled:LoadMenu()
        self.Menu = MenuElement({type = MENU, id = "devKled", name = "devKled v1.0"})

    end   

class "Viktor"
    function Viktor:__init()	     
        print("devX-Viktor Loaded") 

        self:LoadMenu()   
        
        Callback.Add("Tick", function() self:onTickEvent() end)    
        Callback.Add("Draw", function() self:Draw() end)    

        orbwalker:OnPostAttack(function(...) self:PostAuto(...) end) 

        _nextSpellCast = Game.Timer()

        self.lastPosition = myHero.pos
        self.lastUlt = Game.Timer()
        self.eUsage = { numHit = 0, startPos = nil, endPos = nil}

        self.qSpellData = {Range = 600}
        self.wSpellData = {
            Type = GGPrediction.SPELLTYPE_CIRCLE, 
            Delay = 1.75, 
            Speed = math.huge, 
            Range = 800, 
            Radius = 270, 
            Collision = false, 
            CollisionTypes = {}
        }
        self.eSpellData = {
            Type = GGPrediction.SPELLTYPE_LINE,
            Delay = 0,
            Speed = 1050,
            Range = 700,
            Radius = 80,
            Collision = false, 
            CollisionTypes = {}
        }
        self.rSpellData = {
            Type = GGPrediction.SPELLTYPE_CIRCLE, 
            Delay = 0.25, 
            Speed = math.huge, 
            Range = 700, 
            Radius = 325, 
            Collision = false, 
            CollisionTypes = {}
        }
    end

    function Viktor:delayAndDisableOrbwalker(delay) 
        _nextSpellCast = Game.Timer() + delay
        orbwalker:SetMovement(false)
        orbwalker:SetAttack(false)
        DelayAction(function() 
            orbwalker:SetMovement(true)
            orbwalker:SetAttack(true)
        end, delay)
    end

    function Viktor:castE(startPos, endPos)
        
        local startMousePos = mousePos

        Control.SetCursorPos(startPos)
        DelayAction(function() Control.KeyDown(HK_E) end, 0.07)
        DelayAction(function() Control.SetCursorPos(endPos) end, 0.13)
        DelayAction(function() Control.KeyUp(HK_E) end, 0.17)
        DelayAction(function() Control.SetCursorPos(startMousePos) end, 0.26)

        
        
        self:delayAndDisableOrbwalker(0.35)
    end

    function Viktor:getTargetPredPosition(target)
        local UnitPosition, CastPosition, TimeToHit = GGPrediction:GetPrediction(target, myHero, self.eSpellData.Speed, self.eSpellData.Delay, self.eSpellData.Radius)
        return UnitPosition
    end

    function Viktor:getEPosition(entityTable)

        if #entityTable == 0 then return { numHit = 0, startPos = nil, endPos = nil} end

        local bestStartPos, bestEndPos
        local bestHit = 0


        for i, entity in pairs(entityTable) do
            for i2, entity2 in pairs(entityTable) do
                local entityPos1 = Vector(self:getTargetPredPosition(entity))
                local entityPos2 = Vector(self:getTargetPredPosition(entity2))
                
                local endPoint = nil
                local closePoint = nil
                if myHero.pos:DistanceTo(entityPos1) < myHero.pos:DistanceTo(entityPos2) then 
                    endPoint = entityPos2
                    closePoint = entityPos1 
                else 
                    endPoint = entityPos1 
                    closePoint = entityPos2
                end
                
                local directionFromHero = (closePoint - myHero.pos):Normalized()
                
                for i = 300, 550, 50 do -- search range
                    closePoint = myHero.pos + directionFromHero * i
                    direction = (endPoint - closePoint):Normalized()
                    closePoint = closePoint - direction * 50

                    endPoint = closePoint + direction * 550

                    local numHit = 0
                    for i3, entity3 in pairs(entityTable) do
                        local ent3pos = Vector(self:getTargetPredPosition(entity3))
                        if ent3pos then
                            local spellLine = ClosestPointOnLineSegment(ent3pos, closePoint, endPoint)
                            if ent3pos and spellLine and ent3pos:DistanceTo(spellLine) < 90 then
                                numHit = numHit + 1
                            end 
                        end
                    end
                    if numHit > bestHit then
                        bestHit = numHit
                        bestStartPos = closePoint
                        bestEndPos = closePoint + (endPoint - closePoint):Normalized() * 300
                    end
                end

                
            end
        end
        return {numHit = bestHit, startPos = bestStartPos, endPos = bestEndPos}
    end

    function Viktor:onTickEvent()
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            self:Combo()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
            self:Harass()
        end

        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
            self:Clear()
        end
    end

    function Viktor:Clear()
        
        if _nextSpellCast > Game.Timer() then return end
        if not self.Menu.Clear.Enabled:Value() then return end

        if doesMyChampionHaveBuff("ViktorPowerTransfer") then
            local numMinions = #getEnemyMinionsWithinDistanceOfLocation(600);
            if numMinions > 0 then
                --orbwalker:__OnAutoAttackReset()
                self:delayAndDisableOrbwalker(0.2)
                return
            end
        end


        if self.Menu.Clear.E:Value() then
            if isSpellReady(_E) then
                local minions = getEnemyMinionsWithinDistanceOfLocation(myHero.pos, 1000)
                self.eUsage = self:getEPosition(minions)
                if self.eUsage.numHit > 0 then
                    self:delayAndDisableOrbwalker(0.25)
                    self:castE(self.eUsage.startPos, self.eUsage.endPos)
                    return
                end
            end
        end

        if self.Menu.Clear.Q:Value() then
            local minions = getEnemyMinionsWithinDistanceOfLocation(myHero.pos, 600)
            if isSpellReady(_Q) and #minions > 0 then
                Control.CastSpell(HK_Q, minions[0])
            end
        end
    end
    
    function Viktor:PostAuto()
        
        self.lastAuto = Game.Timer()

        local target = orbwalker:GetTarget();
        if target and isSpellReady(_Q) then
            if myHero.pos:DistanceTo(target.pos) <= self.qSpellData.Range then
                Control.CastSpell(HK_Q, target)
                self:delayAndDisableOrbwalker(0.08)
                return
            end
        end
    end
    
    function Viktor:Combo()
        

        if _nextSpellCast > Game.Timer() then return end

        
        if self.Menu.Combo.R2:Value() then
            local hasUlt = doesMyChampionHaveBuff("viktorchaosstormtimer")
            if hasUlt and self.lastUlt < Game.Timer() then
                local target = _G.SDK.TargetSelector:GetTarget(1500, _G.SDK.DAMAGE_TYPE_MAGICAL);
                if target and self.lastPosition:DistanceTo(target.pos) > 60 then
                    Control.CastSpell(HK_R, target.pos)
                    self.lastPosition = target.pos
                    self.lastUlt = Game.Timer() + 0.22
                    return
                end
            end
        end

        if doesMyChampionHaveBuff("ViktorPowerTransfer") then
            local target = _G.SDK.TargetSelector:GetTarget(myHero.range + myHero.boundingRadius, _G.SDK.DAMAGE_TYPE_MAGICAL);
            if target then
                self:delayAndDisableOrbwalker(0.1)
                return
            end
        end
        
        if self.Menu.Combo.Q:Value() then
            local target = _G.SDK.TargetSelector:GetTarget(620, _G.SDK.DAMAGE_TYPE_MAGICAL);
            if target then
                local distance = myHero.pos:DistanceTo(target.pos)
                if isSpellReady(_Q) and distance < self.qSpellData.Range and distance > myHero.range then
                    Control.CastSpell(HK_Q, target)
                    self:delayAndDisableOrbwalker(0.08)
                    return
                end
            end
        end

        if self.Menu.Combo.W:Value() then
            local target = _G.SDK.TargetSelector:GetTarget(800, _G.SDK.DAMAGE_TYPE_MAGICAL);
            if target then
                local enemiesAround = getEnemyHeroesWithinDistanceOfUnit(target.pos, self.wSpellData.Radius)
                if #enemiesAround >= self.Menu.Combo.WMin:Value() then
                    castSpell(self.wSpellData, HK_W, target)
                end
            end
        end

        if self.Menu.Combo.E:Value() then
            if isSpellReady(_E) then
                local enemies = getEnemyHeroesWithinDistance(1000)
                if #enemies > 0 then
                    self.eUsage = self:getEPosition(enemies)
                    if self.eUsage.numHit > 0 then
                        self:delayAndDisableOrbwalker(0.25)
                        self:castE(self.eUsage.startPos, self.eUsage.endPos)
                        return
                    end
                end
            end
        end
        
        
    end

    function Viktor:Harass()
        if _nextSpellCast > Game.Timer() then return end

        if doesMyChampionHaveBuff("ViktorPowerTransfer") then
            local target = _G.SDK.TargetSelector:GetTarget(myHero.range + myHero.boundingRadius, _G.SDK.DAMAGE_TYPE_MAGICAL);
            if target then
                orbwalker:__OnAutoAttackReset()
                self:delayAndDisableOrbwalker(0.03)
                return
            end
        end
        if self.Menu.Harass.Q:Value() then
            local target = _G.SDK.TargetSelector:GetTarget(620, _G.SDK.DAMAGE_TYPE_MAGICAL);
            if target then
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < self.qSpellData.Range then
                    Control.CastSpell(HK_Q, target)
                    self:delayAndDisableOrbwalker(0.08)
                    return
                end
            end
        end
        if self.Menu.Harass.E:Value() then
            if isSpellReady(_E) then
                local enemies = getEnemyHeroesWithinDistance(1000)
                if #enemies > 0 then
                    self.eUsage = self:getEPosition(enemies)
                    if self.eUsage.numHit > 0 then
                        self:delayAndDisableOrbwalker(0.25)
                        self:castE(self.eUsage.startPos, self.eUsage.endPos)
                        return
                    end
                end
            end
        end
        
        
    end

    function Viktor:Draw()
        if self.Menu.Draw.EPos:Value() then
            if self.eUsage.numHit > 0 then
                
                Draw.Circle(self.eUsage.startPos, 50, Draw.Color(150,0,0,255))
                Draw.Circle(self.eUsage.endPos, 50, Draw.Color(150,150,150,255))
                
                Draw.Text(string.format("Number Hit: %d", self.eUsage.numHit), 10, 15, 50, Draw.Color(150,0,255,0))
            end
        end

        if self.Menu.Draw.ClearState:Value() then
            local hero2d = myHero.pos2D
            if self.Menu.Clear.Enabled:Value() then
                Draw.Text("Lane Clear Enabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 0, 255, 0))
            else
                Draw.Text("Lane Clear Disabled [T]", 15, hero2d.x - 30, hero2d.y + 30, Draw.Color(255, 255, 0, 0))
            end
        end
    end

    function Viktor:LoadMenu()
        self.Menu = MenuElement({type = MENU, id = "devViktor", name = "devViktor v1.0"})
        self.Menu:MenuElement({id = "Combo", name = "Combo", type = MENU})
            self.Menu.Combo:MenuElement({id = "Q", name = "[Q]", value = true})
            self.Menu.Combo:MenuElement({id = "W", name = "[W]", value = true})
            self.Menu.Combo:MenuElement({id = "WMin", name = "[W] >= X Hit", value = 2, min = 1, max = 5, step = 1})
            self.Menu.Combo:MenuElement({id = "E", name = "[E]", value = true})
            self.Menu.Combo:MenuElement({id = "R2", name = "[R2]", value = true})

        self.Menu:MenuElement({id = "Harass", name = "Harass", type = MENU})
            self.Menu.Harass:MenuElement({id = "Q", name = "[Q]", value = true})
            self.Menu.Harass:MenuElement({id = "E", name = "[E]", value = true})

        self.Menu:MenuElement({id = "Clear", name = "Clear", type = MENU})
            self.Menu.Clear:MenuElement({id = "Enabled", name = "Clear Enabled", value = true, toggle = true, key = string.byte("T")})
            self.Menu.Clear:MenuElement({id = "Q", name = "[Q]", value = true})
            self.Menu.Clear:MenuElement({id = "E", name = "[E]", value = true})

        self.Menu:MenuElement({id = "Draw", name = "Draw", type = MENU})
            self.Menu.Draw:MenuElement({id = "ClearState", name = "Clear State", value = true})
            self.Menu.Draw:MenuElement({id = "EPos", name = "E Position", value = false})
    end   
----------------------------------------------------
-- Script starts here
---------------------
function onLoadEvent()
    print(myHero.charName)
    if table.contains(Heroes, myHero.charName) then
		_G[myHero.charName]()
    else
        print ("DevX-AIO does not support " .. myHero.charName)
    end
end


Callback.Add('Load', onLoadEvent)