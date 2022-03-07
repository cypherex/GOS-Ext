
local Heroes = {"Swain","RekSai","Elise","Syndra","Gangplank","Gnar","Zeri","LeeSin","Qiyana"}

if not table.contains(Heroes, myHero.charName) then 
    print("DevX AIO does not support "+ myHero.charName)
    return 
end

require "DamageLib"
require "MapPositionGOS"
require "GGPrediction"

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
    for i = 0, target.buffCount do
        local buff = target:GetBuff(i)
        if buff.name == buffName and buff.count > 0 then 
            return true
        end
    end
    return false
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

local function castSpell(spellData, hotkey, target)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)
    if pred:CanHit(GGPrediction.HITCHANCE_NORMAL) then
        if myHero.pos:DistanceTo(pred.CastPosition) <= spellData.Range + 15 then
            Control.CastSpell(hotkey, pred.CastPosition)	
        end
    end
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
    local qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.075, Width = 100, Range = 750, Speed = 5000, Collision = false}
    local eSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.075, Width = 60, Range = 850, Speed = 935, Collision = false}
    local wSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 1, Radius = 100, Range = 5500, Speed = 935, Collision = false}
        
    function Swain:__init()	     
        print("devX-Swain Loaded") 
        self:LoadMenu()   
        
        
        Callback.Add("Draw", function() self:Draw() end)           
        Callback.Add("Tick", function() self:onTickEvent() end)    
    end

    --
    -- Menu 
    function Swain:LoadMenu() --MainMenu
        self.Menu = MenuElement({type = MENU, id = "devSwain", name = "devSwain v1.0"})
                
        -- ComboMenu  
        self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo Mode"})
            self.Menu.Combo:MenuElement({id = "UseQ", name = "[Q]", value = true})
            self.Menu.Combo:MenuElement({id = "UseE", name = "[E]", value = true})

        
        self.Menu:MenuElement({type = MENU, id = "Harass", name = "Harass Mode"})
            self.Menu.Harass:MenuElement({id = "UseQ", name = "[Q]", value = true, toggle = true, key = string.byte("T")})

        -- Auto Menu
        self.Menu:MenuElement({type = MENU, id = "Auto", name = "Auto"})
            self.Menu.Auto:MenuElement{{id="PullRoot", "Pull rooted enemies", value = true}}
            self.Menu.Auto:MenuElement({id = "W", name = "Use W on Root", value = true})
        
            
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

                if isSpellReady(_W) and self.Menu.Auto.W:Value() and distance <  wSpellData.Range and isImmobile then
                    local enemyPos = enemy.pos:ToMM()
                    Control.CastSpell(HK_W, enemyPos.x, enemyPos.y)
                end
                
                if distance < 1125 and doesThisChampionHaveBuff(enemy, "swaineroot") then
                    Control.Attack(enemy)  
                end
            end
        end


    end

    ----------------------------------------------------
    -- Combat Modes
    ---------------------
    function Swain:Combo()
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
            
        if target then

            local distance = getDistance(myHero.pos, target.pos)
            if isSpellReady(_E) and self.Menu.Combo.UseE:Value() then
                if distance < eSpellData.Range + 100  then
                    castSpellExtended(eSpellData, HK_E, target, -200)
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
        print(Game.mapID)
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

    for i = 1, Game.ObjectCount() do
        local obj = Game.Object(i)
        local name = string.lower(obj.charName)
        if string.match(name, "dragon") or string.match(name, "soul") then
            print(obj.charName)
        end
    end
   
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
                Control.Move(firstBarrel.pos)
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
                            {Range=785, Speed = 2600, Delay = 0.1, Radius = 80 },
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
                                local levelDmg  = {10 , 15 , 20 , 25 , 30}
                                levelDmg = levelDmg[myHero:GetSpellData(_Q).level]
                                local dmg = levelDmg + myHero.totalDamage*1.1 
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
    else
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
    local qData = {Type = GGPrediction.SPELLTYPE_LINE, Range=self.qRange, Speed = 2600, Delay = 0.1, Radius = 80,  Collision = false, CollisionTypes = {}}
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
        if #closeEnemies >= self.Menu.RSpell.RCount:Value() then
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
    print("devX-LeeSin Loaded2") 
    self:LoadMenu()   
    
    self.qPrediction = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.25, Radius = 60, Range = 1200, Speed = 1800, Collision = true, CollisionTypes = {GGPrediction.COLLISION_MINION}}
    
    print("x21")
    Callback.Add("Tick", function() self:onTickEvent() end)    
    Callback.Add("Draw", function() self:onDrawEvent() end)
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
    if self.insecAlly then
        Draw.Circle(self.insecAlly.pos, 50, 1,  Draw.Color(255,0,255,0))
        Draw.Circle(self.insecPosition, 50, 1,  Draw.Color(255,0,0,255))
        --Draw.Circle(self.target.pos, 50, 1,  Draw.Color(255,255,0,0))
    end
    if self.tripleUltTarget then
       -- Draw.Circle(self.tripleUltPos, 50, 1,  Draw.Color(255,0,0,255))
       -- Draw.Circle(self.tripleUltTarget.pos, 50, 1,  Draw.Color(255,255,0,0))
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
    if self.Menu.Insec.MinHP:Value() > hero.health / hero.maxHealth * 100  then return end

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
        
        if distance < 600 and self.Menu.Insec.MinHP:Value() < hero.health / hero.maxHealth * 100 then
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
        DelayAction(function () Control.CastSpell(HK_W, wardPosition) end, 0.2)
        
    end

end

function LeeSin:Combo()
    
	if _nextSpellCast > Game.Timer() then return end	
    
    if self.target then
        local distance = myHero.pos:DistanceTo(self.target.pos) 
        if self.Menu.Ultimate.MultiUlt.Enabled:Value() and self.tripleUltTarget and isSpellReady(_R) then
            local distTriple = myHero.pos.DistanceTo(self.tripleUltPos) 
            if self.Menu.Ultimate.MultiUlt.Walk:Value() and distTriple > 100 and distTriple < 200 then 
                Control.Move(self.tripleUltPos)
                self:delayAndDisableOrbwalker(0.2)
                return
            elseif self.Menu.Ultimate.MultiUlt.WardJump:Value() and distTriple > 400 and self.wardSlot then
                self:delayAndDisableOrbwalker(0.55)
                Control.CastSpell(self.wardKey, self.insecPosition)
                DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.18)
                
                DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.38)
            elseif distTriple < 100 then
                Control.CastSpell(HK_R, self.tripleUltTarget)
            end
        end

        if self.Menu.Insec.Enabled:Value() and self.insecPosition and isSpellReady(_R) and (self.flashSlot or self.wardSlot) and not self.tripleUltTarget then 
            -- ward insec    
            local distanceFromPos = myHero.pos:DistanceTo(self.insecPosition)
            if self.Menu.Insec.WardJump:Value() and self.wardSlot and distanceFromPos > 50 and distanceFromPos < 400 then
                self:delayAndDisableOrbwalker(0.55)
                Control.CastSpell(self.wardKey, self.insecPosition)
                DelayAction(function () Control.CastSpell(HK_W, self.insecPosition) end, 0.18)
                
                DelayAction(function () Control.CastSpell(HK_R, self.target) end, 0.38)
                return
            end

            if self.Menu.Insec.Flash:Value() and self.flashSlot and distanceFromPos > 50 and distanceFromPos < 300 then
                self:delayAndDisableOrbwalker(0.55)
                if Control.CastSpell(HK_R, self.target) then
                    DelayAction(function () Control.CastSpell(HK_SUMMONER_1, self.insecPosition) end, 0.24)
                end
                return
            end

            
        end

        if isSpellReady(_Q)  and distance < self.qPrediction.Range + 50 then
            if  string.find(myHero:GetSpellData(_Q).name, 'One')  then
                castSpell(self.qPrediction, HK_Q, self.target)

                _nextSpellCast = Game.Timer() + 0.3
                
                if distance < 400 then
                    self.nextQTimer = Game.Timer() + 1
                end
            elseif Game.Timer() > self.nextQTimer or  distance > 400   then

                Control.CastSpell(HK_Q)
                _nextSpellCast = Game.Timer() + 0.3
            end
            return
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
        [self.ELEMENT.NONE] = { self.ELEMENT.WATER, self.ELEMENT.ROCK, self.ELEMENT.GRASS},
        [self.ELEMENT.ROCK] = { self.ELEMENT.WATER, self.ELEMENT.GRASS, self.ELEMENT.ROCK},
        [self.ELEMENT.WATER] = { self.ELEMENT.ROCK, self.ELEMENT.GRASS, self.ELEMENT.WATER},
        [self.ELEMENT.GRASS] = { self.ELEMENT.ROCK, self.ELEMENT.WATER, self.ELEMENT.GRASS},
    }
    self.BEST_NEXT_ELEMENT_LOW = {
        [self.ELEMENT.NONE] = { self.ELEMENT.WATER, self.ELEMENT.GRASS, self.ELEMENT.ROCK},
        [self.ELEMENT.ROCK] = {  self.ELEMENT.GRASS, self.ELEMENT.WATER,  self.ELEMENT.ROCK},
        [self.ELEMENT.WATER] = {  self.ELEMENT.GRASS, self.ELEMENT.ROCK, self.ELEMENT.GRASS, self.ELEMENT.WATER},
        [self.ELEMENT.GRASS] = { self.ELEMENT.ROCK, self.ELEMENT.WATER, self.ELEMENT.GRASS},
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

    for i, enemy in pairs(getEnemyHeroesWithinDistance(500)) do
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
    if bestETarget then
        print("Gapclose")

        local willUseUltimate = false
    
        local dmgWithoutUlt =  getdmg("Q", target, myHero) * 2 +  getdmg("W", target, myHero) +  getdmg("E", target, myHero) + getdmg("AA", target, myHero)
        local dmgWithUlt = getdmg("R", target, myHero) + dmgWithoutUlt

        if useUlt and target.health < dmgWithUlt and target.health > dmgWithoutUlt then
            willUseUltimate = true
        end
        Control.CastSpell(HK_E, bestETarget)

        if willUseUltimate then
            
            DelayAction(function () Control.CastSpell(HK_R, target) end, 0.25)
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.4)
            DelayAction(function () self:castW(true, target) end, 0.55)
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.65)
            self:delayAndDisableOrbwalker(1.3) 
        
        else
            
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.25)
            DelayAction(function () self:castW(true, target) end, 0.48)
            DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.63)
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
    local dmgWithUlt = getdmg("R", target, myHero) + dmgWithoutUlt

    if useUlt and target.health < dmgWithUlt and target.health > dmgWithoutUlt then
        willUseUltimate = true
    end

    if willUseUltimate then
        Control.CastSpell(HK_R, target)
        DelayAction(function () Control.CastSpell(HK_E, target) end, 0.3)
        DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.45)
        DelayAction(function () self:castW(true, target) end, 0.6)
        DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.75)
        self:delayAndDisableOrbwalker(1.5) 
        
    else
        Control.CastSpell(HK_E, target)
        DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.25)
        DelayAction(function () self:castW(true, target) end, 0.4)
        DelayAction(function () Control.CastSpell(HK_Q, target) end, 0.6)
        self:delayAndDisableOrbwalker(1.3) 
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

        if distance > 600 then
            if self.hasWater and distance < 900 and isSpellReady(_Q) and isSpellReady(_W) and isSpellReady(_E) then
                if self:performGapCloseCombo(canUseUlt, target) then
                    return
                end
                
            end
        else
            if hasElement and isSpellReady(_Q) and isSpellReady(_W) and isSpellReady(_E) then
                if self:performNormalCombo(canUseUlt, target) then
                    return
                end
            end

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
    local target = HealthPrediction:GetJungleTarget()
    if not target then
        target = HealthPrediction:GetLaneClearTarget()
    end
    if target then
        
        local hasElement = self.hasGrass or self.hasRock or self.hasWater
        if not hasElement and isSpellReady(_W) then 
            self:castW()
            
        end

        if isSpellReady(_Q) and (hasElement or myHero:GetSpellData(_W).currentCd > 4) then
            Control.CastSpell(HK_Q, target)
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
----------------------------------------------------
-- Script starts here
---------------------
function onLoadEvent()
    if table.contains(Heroes, myHero.charName) then
		_G[myHero.charName]()
    else
        print ("DevX-AIO does not support " .. myHero.charName)
    end
end


Callback.Add('Load', onLoadEvent)