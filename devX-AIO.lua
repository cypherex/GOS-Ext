
local Heroes = {"Swain","RekSai","Elise"}
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
local TableInsert       = _G.table.insert

local orbwalker         = _G.SDK.Orbwalker



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
        if Hero.isEnemy then
            table.insert(EnemyHeroes, Hero)
        end
    end
    return EnemyHeroes
end

local function getEnemyHeroesWithinDistance(distance)
    local EnemyHeroes = {}
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy and not Hero.dead and myHero.pos:DistanceTo(Hero) < distance then
            table.insert(EnemyHeroes, Hero)
        end
    end
    return EnemyHeroes
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

local function isValid(unit)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        return true;
    end
    return false;
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

        self.Menu:MenuElement({id = "Clear", name = "Lane / JG Clear - Use Abilities", value = true, toggle = true, key = string.byte("T")})
    end

    function Elise:Draw()
        if myHero.dead then return end
    end


    --------------------------------------------------
    -- Callbacks
    ------------

    function Elise:onPostAttack(args)
        local target = orbwalker:GetTarget();
        if target and isSpellReady(_Q) and self.isInSpiderForm then
            Control.CastSpell(HK_Q, target)
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
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 625 then
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
                if isSpellReady(_W) and myHero.pos:DistanceTo(target.pos) <= 700 then
                    Control.CastSpell(HK_W, target)
                end
            end
        end
    end


    function Elise:Clear()
        local target = orbwalker:GetTarget()
        if target then
            if not self.isInSpiderForm then
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 625 then
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
                if isSpellReady(_W) and myHero.pos:DistanceTo(target.pos) <= 700 then
                    Control.CastSpell(HK_W, target)
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
        print ("DevX-AIO does not support " + myHero.charName)
    end
end


Callback.Add('Load', onLoadEvent)