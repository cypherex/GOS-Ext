
local Heroes = {"Swain"}
if not table.contains(Heroes, myHero.charName) then return end

require "DamageLib"
require "GGPrediction"
-------------------------------------------------
-- Variables
------------

-- Spell data for GGPrediction
local qSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.075, Width = 100, Range = 750, Speed = 5000, Collision = false}
local eSpellData = {Type = GGPrediction.SPELLTYPE_LINE, Delay = 0.075, Width = 60, Range = 850, Speed = 935, Collision = false}
local wSpellData = {Type = GGPrediction.SPELLTYPE_CIRCLE, Delay = 1, Radius = 100, Range = 5500, Speed = 935, Collision = false}

-- Reference variables
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

local function doesMyChampionHaveBuff(buffName)
    for i = 0, myHero.buffCount do
        local buff = myHero:GetBuff(i)
        if buff.name == buffName and buff.count > 0 then 
            return true
        end
    end
    return false
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

--------------------------------------------------
-- Swain
--------------
class "Swain"
    function Swain:__init()	     
        print("devSwain Loaded") 
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
        
        -- Auto W if swain rooted
        if self.Menu.Auto.W:Value() or self.Menu.Auto.PullRoot:Value() then
            for i, enemy in pairs(enemies) do
                if isValid(enemy) and not enemy.dead  then
                    local distance = getDistance(myHero.pos, enemy.pos)

                    if doesThisChampionHaveBuff(enemy, "swaineroot") then
                        if isSpellReady(_W) and distance < wSpellData.Range and self.Menu.Auto.W:Value() then
                            Control.CastSpell(HK_W, enemy.pos)
                            _G.SDK.Orbwalker:SetAttack(false)
                            DelayAction(
                                function()
                                    _G.SDK.Orbwalker:SetAttack(true)
                                    if distance < 900 then
                                        local pos = enemy.toScreen
                                        Control.LeftClick(pos.x, pos.y)      
                                    end
                                end,
                                1
                            ) 
                        elseif distance < 900 then
                                local pos = enemy.toScreen
                                Control.LeftClick(pos.x, pos.y)      
                                return
                        end
                        
                    end
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
-- Script starts here
---------------------

    
function onLoadEvent()
    if table.contains(Heroes, myHero.charName) then
		_G[myHero.charName]()
    else
        print ("devSwain does not support " + myHero.charName)
    end
end


Callback.Add('Load', onLoadEvent)