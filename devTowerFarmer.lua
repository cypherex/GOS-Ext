
local GameTurret = Game.Turret
local GameTurretCount = Game.TurretCount
local GameMinion = Game.Minion
local GameMinionCount = Game.MinionCount
local GameMissile = Game.Missile
local GameMissileCount = Game.MissileCount


local Damage = _G.SDK.Damage
local HealthPrediction = _G.SDK.HealthPrediction
local Attack = _G.SDK.Attack
local Data = _G.SDK.Data
local Orbwalker = _G.SDK.Orbwalker

local SECONDS_PER_ATTACK = 1.2
-------------------------------------------------
-- TowerFarmer  
------------

class "TowerFarmer"

    function TowerFarmer:__init()
        print("DevX TowerFarmer loaded")
        Callback.Add("Tick", function () self:onTick() end )
        Callback.Add("Draw", function () self:onDraw() end )

        self.isEnabled = false
        self:createMenu()
    end

    function TowerFarmer:createMenu()
        self.Menu = MenuElement({type = MENU, id = "devFarmer", name = "DevX TowerFarmer"})
        
        self.Menu:MenuElement({id = "Enabled", name = "Enabled", value = true, toggle=true})
            
        self.Menu:MenuElement({type = MENU, id = "Draw", name = "Draw"})
            self.Menu.Draw:MenuElement({id = "Debug", name = "Debug", value = false})
    end
    -------------------------------------------------
    -- State functions  
    ------------

    function TowerFarmer:onTick()
        self.isEnabled = false
        self.closestTower = self:getClosestTurret()
        if self.closestTower and myHero.pos:DistanceTo(self.closestTower.pos) < 1000 and Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] and self.Menu.Enabled:Value() then
            self.towerTarget = self:getTurretTarget(self.closestTower)
            self.turretMinions = self:getMinionsUnderTurret(self.closestTower)
            if #self.turretMinions > 0 then
                
                self.isEnabled = true
                Orbwalker:SetAttack(false)
                self.minionChecks = self:checkMinions(self.turretMinions)
                if self.minionChecks then
                    self:farmMinions(self.minionChecks)
                end
                Orbwalker:SetAttack(true)
            end
            
        end
    end


    function TowerFarmer:onDraw()
        if self.closestTower and self.closestTower.visible and self.Menu.Draw.Debug:Value() then
            Draw.Circle(self.closestTower.pos, self.closestTower.boundingRadius + 775)
            
            if self.turretMinions and #self.turretMinions > 0  then
                
                Draw.Text(string.format("Speed: %s", self.turretSpeed), 10, self.closestTower.pos2D.x, self.closestTower.pos2D.y+ 15, Draw.Color(150,255,0,0))
                Draw.Text(string.format("Delay: %s", self.turretDelay), 10, self.closestTower.pos2D.x, self.closestTower.pos2D.y+ 25, Draw.Color(150,255,0,0))
                Draw.Text(string.format("Target: %s", self.closestTower.targetID), 10, self.closestTower.pos2D.x, self.closestTower.pos2D.y+ 35, Draw.Color(150,255,0,0))
                Draw.Text(string.format("AtkSpeed: %s", self.closestTower.attackSpeed), 10, self.closestTower.pos2D.x, self.closestTower.pos2D.y+ 45, Draw.Color(150,255,0,0))

                for i, minion in pairs(self.turretMinions) do
                    Draw.Text(string.format("#%s", i), 10, minion.pos2D.x, minion.pos2D.y, Draw.Color(50,255,0,0))
                end
                
                for i, check in pairs(self.minionChecks) do      
                    Draw.Text(string.format("HP: %s", check.remainingHP), 10, check.minion.pos2D.x, check.minion.pos2D.y + 10, Draw.Color(50,255,0,0))
                    Draw.Text(string.format("LH: %s - LH2: %s - RH: %s", check.lastHittable, check.lastHittableTwoShots, check.hitsToPrep), 10, check.minion.pos2D.x, check.minion.pos2D.y + 20, Draw.Color(50,255,0,0))  
                    Draw.Text(string.format("DMG: %s - SPD: %s", check.AADamage, check.secondsPerAttack), 10, check.minion.pos2D.x, check.minion.pos2D.y + 30, Draw.Color(50,255,0,0))
                end
            end

            if self.towerTarget then
                Draw.Circle(self.towerTarget.pos, self.towerTarget.boundingRadius)
            end
            
        end
        if self.heroTargetMinion then
            Draw.Circle(self.heroTargetMinion.pos, self.heroTargetMinion.boundingRadius, Draw.Color(150,0,0,255))
        end
        
        Draw.Text(string.format("DevX-TowerFarmer Active: %s", self.isEnabled), 10, 50, 50, Draw.Color(150,0,255,0))
    end

        
    -------------------------------------------------
    -- Minion management
    ---------------------
    function TowerFarmer:farmMinions(minionChecks)
        if #minionChecks == 0 then return end

        if #minionChecks >= 1 then
             -- Kill last-hittable
            for i, check in pairs(minionChecks) do
                if not check.minion.dead and check.lastHittable then
                    if Orbwalker:CanAttack(check.minion) then
                        self.heroTargetMinion = check.minion
                        Draw.Circle(self.heroTargetMinion.pos, self.heroTargetMinion.boundingRadius, Draw.Color(150,0,0,255))
                        self:attackUnit(check.minion)
                        return
                    end
                end
            end
            -- Try to prep minions of there is  no last hittable minions
            for i, check in pairs(minionChecks) do
                if not check.minion.dead and check.hitsToPrep == 1 then
                    if Orbwalker:CanAttack(check.minion) then
                        self.heroTargetMinion = check.minion
                        Draw.Circle(self.heroTargetMinion.pos, self.heroTargetMinion.boundingRadius, Draw.Color(150,0,0,255))
                        self:attackUnit(check.minion)
                        return
                    end
                end
            end
            
            -- Try to prep minions that need more time if there is reasonably preperabe minion
            for i, check in pairs(minionChecks) do
                if  not check.minion.dead and check.hitsToPrep == 2 and not check.lastHittableTwoShots and i > 2 then
                    if Orbwalker:CanAttack(check.minion) then
                        self.heroTargetMinion = check.minion
                        Draw.Circle(self.heroTargetMinion.pos, self.heroTargetMinion.boundingRadius, Draw.Color(150,0,0,255))
                        self:attackUnit(check.minion)
                        return
                    end
                end
            end            
        end
        
    end

    function TowerFarmer:attackUnit(unit)
        
        Orbwalker:SetAttack(true)
        Orbwalker:Attack(unit)
        Orbwalker:SetAttack(false)
    end

    function TowerFarmer:checkMinions(turretMinions)
        local minionLogic = {}

        local aaSpeed = Attack:GetProjectileSpeed()
        local turretDamage = self:getTowerDamage()

        for i, minion in pairs(turretMinions) do
            local dmg = Damage:GetAutoAttackDamage(myHero, minion)
            local distance = myHero.pos:DistanceTo(minion.pos) 

            local hp = HealthPrediction:GetPrediction(minion,  Attack:GetWindup() - Data:GetLatency() + distance / aaSpeed )
            local hp2 = HealthPrediction:GetPrediction(minion,  (Attack:GetWindup() - Data:GetLatency() + distance / aaSpeed)*2 )

            -- stats
            local lastHittable = false
            local canLastHitWithTwoShots = hp < dmg + turretDamage * 2 and hp > turretDamage * 2
            local hitsToPrep = -1

            if hp < dmg then
                lastHittable = true
                hitsToPrep = 0
            else
                
                if hp - turretDamage < dmg  and hp > turretDamage then
                    hitsToPrep = 0
                elseif hp2 - turretDamage < dmg*2 and hp2 > turretDamage + dmg then
                    hitsToPrep = 1
                elseif hp2 - turretDamage < dmg*3 and hp2 > turretDamage - dmg*2 then
                    hitsToPrep = 2
                end
            end

            
            table.insert(minionLogic, {
                minion =  minion,
                hitsToPrep = hitsToPrep,
                lastHittable = lastHittable,
                lastHittableTwoShots = canLastHitWithTwoShots,
                remainingHP = hp,
                AADamage = dmg,
                secondsPerAttack = Attack:GetWindup() - Data:GetLatency() + distance / aaSpeed 
            })
        end

        return minionLogic
    end

    -------------------------------------------------
    -- Turret targetting  
    ------------

    function TowerFarmer:getClosestTurret()
        local closestTurret
        local closestDistance = 10000

        for i = 1, GameTurretCount() do
            local turret = GameTurret(i)
            if turret.isAlly and not turret.dead and not turret.isImmortal then
                local distance = myHero.pos:DistanceTo(turret.pos)
                if distance < closestDistance then 
                    closestTurret = turret
                    closestDistance = distance
                end
            end
        end
        return closestTurret
    end

    function TowerFarmer:getTurretTarget(turret) 
        local target = nil
        if turret.targetID then
            netId = turret.targetID
            if netId then
                targetObj = Game.GetObjectByNetID(netId)
                if targetObj and not targetObj.dead then
                    target = targetObj
                end
            end
        end
        return target
    end

    function TowerFarmer:getMinionsUnderTurret(turret)
        
        local minions = {}
        
        if not turret then return minions end

        for i = 1, GameMinionCount() do
            local minion = GameMinion(i)
            if minion.pos:To2D().onScreen then 
                
                if minion.isEnemy and not minion.dead then
                    local distance = minion.pos:DistanceTo(turret.pos)
                    if distance < 775 + turret.boundingRadius + minion.boundingRadius / 2  + 85 and not minion.dead then 
                        table.insert(minions, minion)
                    end
                end
            end
        end
        if #minions > 0 then
            table.sort(minions, 
                function (a, b)
                    if self.towerTarget then
                        if a.networkID == self.towerTarget.networkID then 
                            return true 
                        elseif b.networkID == self.towerTarget.networkID then
                            return false
                        end
                    end
                    local prioA, prioB = self.getTurretMinionPriority(a), self.getTurretMinionPriority(b)
                    
                    if prioA == prioB then
                        return a.pos:DistanceTo(turret.pos) < b.pos:DistanceTo(turret.pos)
                    else
                        return prioA > prioB 
                    end
                end
            )
        end
        return minions
    end

    function TowerFarmer:getTurretMinionPriority(minion)
        if not minion then return 0 end

        local types = {"siege","melee","range"}
        for i, typeV in pairs(types) do
            if string.find(minion.charName.toLower(), typeV) then
                return 3-i
            end
        end
        return 0
    end

    -------------------------------------------------
    -- Adhoc  
    ------------
    function TowerFarmer:getTowerDamage()
        minutes = Game.Timer() / 60
        return 9 * math.floor(minutes - 1.5) + 170
    end
    
-------------------------------------------------
-- Script starts here
------------

function onLoad()
    TowerFarmer()
end

Callback.Add("Load",onLoad)