--[[
    CameraAntiPeek — 3rd-person камера без прохождения сквозь стены
    ═══════════════════════════════════════════════════════════

    Стандартная Roblox-камера в узких коридорах может оказаться за стеной
    или внутри стены. Тогда игрок видит соседний коридор.

    Здесь мы НЕ запрещаем third-person. Вместо этого каждый кадр:
    1) даём стандартной камере Roblox посчитать обычный поворот от мыши;
    2) сразу после Camera-priority проверяем путь от персонажа к камере;
    3) если между ними есть стена, ставим камеру перед стеной.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CAMERA_DISTANCE = 10
local CAMERA_NEAR_DISTANCE = 0.65
local CAMERA_PADDING = 0.75
local CAMERA_RADIUS = 0.9
local TARGET_HEIGHT = 2.2

local function enforce()
    -- Classic сохраняет third-person. Zoom-окклюзия отключает Invisicam-прозрачность.
    if player.CameraMode ~= Enum.CameraMode.Classic then
        player.CameraMode = Enum.CameraMode.Classic
    end
    player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom

    -- Фиксируем дистанцию, чтобы игрок не увеличивал "рычаг" для подглядывания.
    if player.CameraMinZoomDistance ~= CAMERA_DISTANCE then
        player.CameraMinZoomDistance = CAMERA_DISTANCE
    end
    if player.CameraMaxZoomDistance ~= CAMERA_DISTANCE then
        player.CameraMaxZoomDistance = CAMERA_DISTANCE
    end
end

local function getCharacterRoot()
    local character = player.Character
    if not character then
        return nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not rootPart then
        return nil, nil
    end

    return character, rootPart
end

local function buildRaycastParams(character)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.IgnoreWater = true
    return params
end

local function castCameraBlocker(origin, displacement, params)
    local ok, result = pcall(function()
        return Workspace:Spherecast(origin, CAMERA_RADIUS, displacement, params)
    end)

    if ok then
        return result
    end

    return Workspace:Raycast(origin, displacement, params)
end

local function clampCamera()
    camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local character, rootPart = getCharacterRoot()
    if not character then
        return
    end

    local target = rootPart.Position + Vector3.new(0, TARGET_HEIGHT, 0)
    local lookVector = camera.CFrame.LookVector
    local desiredPosition = target - lookVector * CAMERA_DISTANCE
    local displacement = desiredPosition - target

    if displacement.Magnitude <= 0.01 then
        return
    end

    local params = buildRaycastParams(character)
    local hit = castCameraBlocker(target, displacement, params)
    local finalPosition = desiredPosition

    if hit then
        local hitDistance = math.max(hit.Distance - CAMERA_PADDING, CAMERA_NEAR_DISTANCE)
        finalPosition = target + displacement.Unit * hitDistance
    end

    camera.CFrame = CFrame.lookAt(finalPosition, target)
    camera.Focus = CFrame.new(target)
end

enforce()

task.spawn(function()
    while true do
        enforce()
        task.wait(0.5)
    end
end)

RunService:BindToRenderStep(
    "CameraAntiPeekThirdPerson",
    Enum.RenderPriority.Camera.Value + 1,
    clampCamera
)
