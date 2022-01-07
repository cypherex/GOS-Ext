
local menu
local function onDraw()
    if menu.Enabled:Value() then
        for i = 1, Game.TurretCount() do
            local tower = Game.Turret(i)
            if tower.pos2D.onScreen then
                Draw.Circle(tower.pos, 775 + tower.boundingRadius, Draw.Color(255, 255,0,0))
            end
        end
    end
end

local function onLoad()
    Callback.Add("Draw", function () onDraw() end )

    menu = MenuElement({type = MENU, id = "tower_range", name = "TowerRangeScript"})
    menu:MenuElement({id = "Enabled", name = "Enabled", value = true, toggle=true})
end

Callback.Add("Load",onLoad)