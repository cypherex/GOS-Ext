
local Heroes = {"Swain","RekSai","Elise","Syndra","Gangplank","Gnar","Zeri"}

if not table.contains(Heroes, myHero.charName) then return end

require "DamageLib"
require "GGPrediction"
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
    if pred:CanHit(GGPrediction.COLLISION_NORMAL) then
        Control.CastSpell(hotkey, pred.CastPosition)	
    end
end

local function castSpellExtended(spellData, hotkey, target, extendAmount)
    local pred = GGPrediction:SpellPrediction(spellData)
    pred:GetPrediction(target, myHero)
    if pred:CanHit(GGPrediction.COLLISION_NORMAL) then
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
            
            if isSpellReady(_E) and target and self.Menu.Combo.UseE:Value() then
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
             
            if isSpellReady(_E) and target and self.Menu.Combo.UseE:Value() then
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
        local castPosition = myHero.pos + (target.pos - myHero.pos):Normalized() * math.min(distance*3/4, 750)
        Control.CastSpell(HK_Q, castPosition) 
        orbwalker:SetMovement(false)
        self.isInEQ = true
        DelayAction(function()
            Control.CastSpell(HK_E, target.pos)
            self.isInEQ = false
            orbwalker:SetMovement(true)
        end,0.12)	
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
        local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
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
                if distance < 650 then
                    self:castQE(target)
                elseif distance < 1200 then
                    self:castEQ(target, distance)
                end
            end
            
            if self.isInEQ then return end

            if distance < 850 and isSpellReady(_Q) then
                castSpell(self.qSpellData, HK_Q, target)
            end

            if isSpellReady(_W) and distance < 850 then
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
            if distance < 850 and isSpellReady(_Q) then
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

        local target = _G.SDK.TargetSelector:GetTarget(850, _G.SDK.DAMAGE_TYPE_MAGICAL);
        
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
                print("Anti-Melee")
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

    self.Menu:MenuElement({type = MENU, id = "Empty", name = "Empty"})
end

function Gangplank:Draw()
    
end


--------------------------------------------------
-- Callbacks
------------
function Gangplank:onTickEvent()

end
----------------------------------------------------
-- Combat Functions
---------------------

----------------------------------------------------
-- Other Functions
---------------------



----------------------------------------------------
-- Combat Modes
---------------------

function Gangplank:AutoUlt()
end

function Gangplank:Combo()
    local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
  
end

function Gangplank:Harass()
    local target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    
   
end

function Gangplank:LaneClear()
    
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
    self.Menu.Combo:MenuElement({name = "[E] Logic", id = "ETransform", value = 1, drop = {"None", "Always", "When about to transform", "Gapcloser"}})
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
    local wallLocation = FindClosestWall()

    if wallLocation and myHero.pos:DistanceTo(wallLocation) < 400 then
        local enemiesInRange = getEnemyHeroesWithinDistanceOfUnit(wallLocation, 550)

        if #enemiesInRange > self.Menu.Combo.UltHeroes:Value() then
            Control.CastSpell(HK_R, wallPosition)
        elseif #enemiesInRange > 0 then
            for i, hero in pairs(enemiesInRange) do
                if hero.health < self.Menu.Combo.UltHP:Value() then
                    Control.CastSpell(HK_R, wallPosition)
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
            if transformCondition == 2 then
                Control.CastSpell(HK_E, target)
            elseif transformCondition == 3 and self.transformingSoon  then
                Control.CastSpell(HK_E, target)
            elseif transformCondition == 4 and myHero.pos:DistanceTo(target.pos) > 350 then 
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
-- Gnar
--------------
class "Zeri"
        
function Zeri:__init()	     
    print("devX-Zeri Loaded") 
    self:LoadMenu()   
    
    Callback.Add("Tick", function() self:onTickEvent() end)    

    orbwalker:OnPostAttack(function(...) self:onPostAttack(...) end )
end

--
-- Menu 
function Zeri:LoadMenu() --MainMenu
    self.Menu = MenuElement({type = MENU, id = "devZeri", name = "DevX Zeri v1.0"})
    -- ComboMenu  

    self.Menu:MenuElement({type = MENU, id = "Combo", name = "Combo"})
    
end



--------------------------------------------------
-- Callbacks
------------

function Zeri:onPostAttack()
    
    local target = orbwalker:GetTarget()
    
    if target then
        if myHero.pos:DistanceTo(target.pos) < 800 and isSpellReady(_Q) then
            Control.CastSpell(HK_Q, target)
        end
    end

end
function Zeri:onTickEvent()
    
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
-- Other Functions
---------------------


----------------------------------------------------
-- Combat Modes
---------------------

function Zeri:Combo()
    local target = orbwalker:GetTarget()
    if not target then
        target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    end
    if target then
        
        if myHero.pos:DistanceTo(target.pos) < 800 and isSpellReady(_Q) then
            Control.CastSpell(HK_Q, target)
        end

    end
end

function Zeri:LaneClear()
    local target = HealthPrediction:GetLaneClearTarget()
    if not target then
        target = HealthPrediction:GetJungleTarget()
    end
    
    if target then
        
        if myHero.pos:DistanceTo(target.pos) < 800 and isSpellReady(_Q) then
            Control.CastSpell(HK_Q, target)
        end

    end
end
function Zeri:Harass()
    local target = orbwalker:GetTarget()
    if not target then
        target = _G.SDK.TargetSelector:GetTarget(1000, _G.SDK.DAMAGE_TYPE_MAGICAL);
    end
    if target then
        
        if myHero.pos:DistanceTo(target.pos) < 800 and isSpellReady(_Q) then
            Control.CastSpell(HK_Q, target)
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
        print ("DevX-AIO does not support " + myHero.charName)
    end
end


Callback.Add('Load', onLoadEvent)