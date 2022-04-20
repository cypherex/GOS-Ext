
MODE = {
    INITIATING = "initiating",
    MANUALLY_SELECT = "manually select",
    IDLE = "idle",
    RECALL = "recalling",
    FOLLOW = "following",
    CLEAR_VISION = "clearing vision"
}


------------- Adhoc functions
function getClosestTurret()
    local closestTurret
    local closestDistance = 10000

    for i = 1, Game.TurretCount() do
        local turret = Game.Turret(i)
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

local function isSpellReady(spell)
    return  myHero:GetSpellData(spell).currentCd == 0 and myHero:GetSpellData(spell).level > 0 and Game.CanUseSpell(spell) == 0
end



class "RakaBot"
    function RakaBot:__init()	    
        self.currentMode = MODE.INITIATING;

        Callback.Add("Draw", function() self:onDrawEvent() end);          
        Callback.Add("Tick", function() self:onTickEvent() end);
        Callback.Add('WndMsg', function(msg, wParam) self:onWndMsg(msg, wParam) end);
        Callback.Add('ProcessRecall', function(unit, proc) self:onProcessRecall(unit, proc) end)

        self.skipTimer = Game.Timer()

        self:updateAllyBasePosition()
        self:determineInitialFollowPriority()
        
        print("devX-Soraka Loaded");
    end
    

    ---------------------
    -- Events
    ---------------------
    function RakaBot:onTickEvent()
        if self.skipTimer > Game.Timer() then return end
        
        if _G.JustEvade and _G.JustEvade:Evading() or (_G.ExtLibEvade and _G.ExtLibEvade.Evading) or Game.IsChatOpen() or myHero.dead then return end

        if self.forceExitMode then
            self.currentMode = MODE.MANUALLY_SELECT;
            self.followTarget = nil
            self.initialFollowTarget = nil;
            self.forceExitMode = false;
            return
        end

        if self.currentMode == MODE.INITIATING then

            if self.followTarget then
                self.currentMode = MODE.FOLLOW;
                self.initialFollowTarget = self.followTarget;
            else
                self.currentMode = MODE.MANUALLY_SELECT;
            end
            return;
        end

        if self.currentMode == MODE.MANUALLY_SELECT then
            if self.followTarget then
                self.currentMode = MODE.FOLLOW;
                self.initialFollowTarget = self.followTarget;
            end
        end

        if self.currentMode == MODE.FOLLOW then
            self:followMode();
        end
        if self.currentMode == MODE.RECALL then
            self:recallMode();
        end
    end

    function RakaBot:onProcessRecall(unit, proc) 
        if not myHero.dead and self.followTarget and unit.handle == self.followTarget.handle then
            self.currentMode = MODE.RECALL;
        end
    end

    function RakaBot:onDrawEvent()
        Draw.Text("CurrentMode: " .. self.currentMode, 15, 50, 100, Draw.Color(50, 0, 255, 0))
        if self.followTarget then
            Draw.Text("Follow Target: " .. self.followTarget.charName, 15, 50, 120, Draw.Color(50, 0, 255, 0))
        end
    end 
    
    function RakaBot:onWndMsg(msg, wParam)
        
        if self.currentMode == MODE.MANUALLY_SELECT then
            if msg == WM_LBUTTONDOWN then
                self:selectFollowTargetFromMouseClick()
            end
        end
        -- Escape
        if wParam == 27 then
            self.forceExitMode = true;
        end
    end

    ---------------------
    -- Modes
    ---------------------
    function RakaBot:recallMode()
        local recallBuff = _G.SDK.BuffManager:GetBuff(myHero, "recall");
        if recallBuff and recallBuff.duration > 0 then return end
        
        local closestTurret = getClosestTurret()
        if closestTurret and myHero.pos:DistanceTo(closestTurret.pos) < myHero.pos:DistanceTo(self.basePosition) then

            -- If we are close to our follow target, let's back near the same position
            if myHero.pos:DistanceTo(self.followTarget.pos) < myHero.pos:DistanceTo(closestTurret.pos) and myHero.pos:DistanceTo(self.followTarget.pos) > 350 then
                self:moveUsingMinimap(self.followTarget.pos, 150, 2.5)

            -- Otherwise let's base at the tower
            elseif myHero.pos:DistanceTo(closestTurret.pos) > 250 then
                self:moveUsingMinimap(closestTurret.pos, 150, 2.5)

            -- If we are at the tower, we can now base
            elseif myHero.pos:DistanceTo(self.basePosition)  > 500 then
                Control.KeyDown(string.byte("B"))
                Control.KeyUp(string.byte("B"))
                self.skipTimer = Game.Timer() + 10
            end

        -- we are currently at the base, so let's resume following 
        elseif myHero.pos:DistanceTo(self.basePosition) < 500 then
            if not self.followTarget.dead then
                self.currentMode = MODE.FOLLOW;
            end
        end
    end 

    function RakaBot:followMode()
        if self.followTarget and not self.followTarget.dead then
            
            if _G.SDK.Attack:IsActive() then return end
            if not _G.SDK.Attack:IsReady() then return end 

            if self:moveTowardsFollowTarget() then return end
            if self:healAllies() then return end
            if self:attackEnemies() then return end

            if myHero.pos:DistanceTo(self.followTarget.pos) < 400 then
                self:moveRandomly()
            end
            
        else
            self:grabNewFollowTarget()
        end
    end


    ---------------------
    -- Tasks
    ---------------------
    
    function RakaBot:healAllies()
        
        local allies = _G.SDK.ObjectManager:GetAllyHeroes()
        for i, ally in pairs(allies) do
            if not ally.dead then
                if isSpellReady(_R) and ally.health / ally.maxHealth < 0.3 then
                    Control.CastSpell(HK_R)
                    return true
                end
                if isSpellReady(_W) and not ally.isMe and ally.health / ally.maxHealth < 0.65 and myHero.pos:DistanceTo(ally.pos) < 550 then
                    Control.CastSpell(HK_W, ally)
                    return true
                end
            end
        end
        return false
    end

    function RakaBot:attackEnemies()
        
        local enemies = _G.SDK.ObjectManager:GetEnemyHeroes()
        if #enemies > 0 then
            for i, target in pairs(enemies) do
                if isSpellReady(_Q) and myHero.pos:DistanceTo(target.pos) < 800 then
                    Control.CastSpell(HK_Q, target.pos)
                    self.skipTimer = Game.Timer() + 0.2
                    return true
                end

                if isSpellReady(_E) and myHero.pos:DistanceTo(target.pos) < 925 then
                    Control.CastSpell(HK_E, target.pos)
                    self.skipTimer = Game.Timer() + 0.2
                    return true
                end

                if myHero.pos:DistanceTo(target.pos) <= 550 then
                    if _G.SDK.Orbwalker:CanAttack(target) then
                        _G.SDK.Orbwalker:Attack(target)
                        self.skipTimer = Game.Timer() + 0.2
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Follow target selection

    function RakaBot:determineInitialFollowPriority()
        local priorityList = {"Aphelios","Ashe","Caitlyn","Corki","Draven","Ezreal","Jhin","Jinx","Kaisa","Kalista","KogMaw","Lucian","MissFortune","Samira","Senna","Quinn","Sivir","Tristana","Twitch","Varus","Vayne","Xayah","Graves","Kindred"}
        local matched = true
        
        local allies = _G.SDK.ObjectManager:GetAllyHeroes()
        for i, ally in pairs(allies) do

            for i, champ in pairs(priorityList) do
                if ally.charName == champ then
                    self.followTarget = ally
                    return
                end
            end
        end
    end

    function RakaBot:selectFollowTargetFromMouseClick()
        
        local closestDistance = math.huge
        local closestAlly = nil
        local pos = Vector(mousePos)
        local allies = _G.SDK.ObjectManager:GetAllyHeroes()
        for i, ally in pairs(allies) do
            if ally.pos:ToScreen().onScreen then
                local distance = pos:DistanceTo(ally.pos)
                if distance < 150 and distance < closestDistance then
                    closestDistance = distance
                    closestAlly = ally
                end
            end
        end
        self.followTarget = closestAlly
        print(closestAlly)
    end

    function RakaBot:grabNewFollowTarget()
        
        if not self.initialFollowTarget.dead and self.initialFollowTarget.pos:DistanceTo(myHero.pos) < 1500 then
            self.followTarget = self.initialFollowTarget;
            return
        end

        local nearbyAllies = _G.SDK.ObjectManager:GetAllyHeroes(1500)
        if #nearbyAllies > 0 then
            table.sort(nearbyAllies, function (a, b) return a.maxHealth < b.maxHealth end)
            self.followTarget = nearbyAllies[0];
        else
            self.currentMode = MODE.RECALL;
        end
    end

    function RakaBot:tryResetBackToPrimaryFollow()
        if  self.followTarget and 
            self.initialFollowTarget and
            self.followTarget.handle ~= self.initialFollowTarget.handle and 
            self.initalTarget.alive and
            myHero.pos:DistanceTo(self.initalTarget.pos) < 1000 
        then
            self.followTarget = self.initialFollowTarget -- Lets follow our main target again since they are not dead
        end
        
    end

    -- Movement functions

    function RakaBot:moveTowardsFollowTarget()
        
        local maxDistance = 400 + math.random(-50, 50)

        if myHero.pos:DistanceTo(self.followTarget.pos) > maxDistance then
            if myHero.health / myHero.maxHealth < 0.2 or myHero.mana < 35 then
                self.currentMode = MODE.RECALL;
                return true
            else
                self:moveUsingMinimap(self.followTarget.pos, 150, 0.15)
            end
        end
        return false
    end

    function RakaBot:moveRandomly()
        self:moveUsingMinimap(myHero.pos, 150, 0.5)       
    end

    function RakaBot:moveUsingMinimap(position, randomOffset, delay)
        local mmCoords = (Vector(position) + Vector(math.random(-randomOffset, randomOffset), math.random(-randomOffset, randomOffset),0)):ToMM()
                
        local x = mmCoords.x 
        local y = mmCoords.y 

        Control.LeftClick(x, y)
        Control.RightClick(x, y)
        self.skipTimer = Game.Timer() + delay
    end
    
    ---------------------
    -- Adhoc
    ---------------------

    function RakaBot:updateAllyBasePosition()
        for i = 1, Game.ObjectCount() do
            local base = Game.Object(i)
            if base.isAlly and base.type == Obj_AI_SpawnPoint then
                self.basePosition = base.pos
                return
            end
        end
    end

---------------------
-- Application starts here
---------------------
Callback.Add('Load', function() RakaBot() end)

