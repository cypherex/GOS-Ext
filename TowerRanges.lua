
local function isTowerOnScreen()
    for i = 1, GameTurretCount() do
        local tower = GameTurret(i)
        if tower.pos2D.onScreen then
            return true, tower
        end
    end
    return false, nil
end

local function onDraw()
    local onScreen, tower = isTowerOnScreen()
    if onScreen then
        Draw.Circle(tower.pos, 775 + tower.boundingRadius, Draw.Color(255, 255,0,0))
    end
end

local function onLoad()
    Callback.Add("Draw", function () onDraw() end )
end

Callback.Add("Load",onLoad)