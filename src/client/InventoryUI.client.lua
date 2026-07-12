--[[
    InventoryUI — панель инвентаря и использование предметов
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local inventoryGui

local function createInventoryGui()
    local existing = playerGui:FindFirstChild("InventoryGui")
    if existing then
        return existing
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "InventoryGui"
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 15
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local panel = Instance.new("Frame")
    panel.Name = "InventoryPanel"
    panel.Size = UDim2.new(0, 220, 0, 72)
    panel.Position = UDim2.new(0.02, 0, 0.08, 0)
    panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    panel.BackgroundTransparency = 0.25
    panel.BorderSizePixel = 0
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 10)
    panelCorner.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -12, 0, 22)
    title.Position = UDim2.new(0, 6, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "Инвентарь"
    title.TextColor3 = Color3.fromRGB(210, 210, 220)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = panel

    local itemsFrame = Instance.new("Frame")
    itemsFrame.Name = "ItemsFrame"
    itemsFrame.Size = UDim2.new(1, -12, 0, 40)
    itemsFrame.Position = UDim2.new(0, 6, 0, 28)
    itemsFrame.BackgroundTransparency = 1
    itemsFrame.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = itemsFrame

    return screenGui
end

local function createItemButton(itemData)
    local button = Instance.new("TextButton")
    button.Name = "Item_" .. itemData.ItemId
    button.Size = UDim2.new(0, 40, 0, 40)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Text = itemData.Icon or "?"
    button.TextSize = 22
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    if itemData.Usable then
        button:SetAttribute("Usable", true)
    end

    if (itemData.Count or 1) > 1 then
        local countLabel = Instance.new("TextLabel")
        countLabel.Name = "Count"
        countLabel.Size = UDim2.new(0, 16, 0, 14)
        countLabel.Position = UDim2.new(1, -14, 1, -12)
        countLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        countLabel.Text = tostring(itemData.Count)
        countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        countLabel.TextSize = 11
        countLabel.Font = Enum.Font.GothamBold
        countLabel.Parent = button

        local countCorner = Instance.new("UICorner")
        countCorner.CornerRadius = UDim.new(0, 4)
        countCorner.Parent = countLabel
    end

    button.MouseButton1Click:Connect(function()
        if itemData.Usable then
            Remotes:GetEvent("UseInventoryItem"):FireServer(itemData.ItemId)
        end
    end)

    return button
end

local function updateInventory(payload)
    inventoryGui = inventoryGui or createInventoryGui()
    local panel = inventoryGui:FindFirstChild("InventoryPanel")
    if not panel then
        return
    end

    local itemsFrame = panel:FindFirstChild("ItemsFrame")
    if not itemsFrame then
        return
    end

    for _, child in ipairs(itemsFrame:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
            child:Destroy()
        end
    end

    local items = payload and payload.Items or {}
    panel.Visible = #items > 0

    local title = panel:FindFirstChild("Title")
    if title then
        title.Text = #items > 0 and "Инвентарь (нажми предмет)" or "Инвентарь"
    end

    for index, itemData in ipairs(items) do
        local button = createItemButton(itemData)
        button.LayoutOrder = index
        button.Parent = itemsFrame
    end
end

Remotes:GetEvent("InventoryUpdated").OnClientEvent:Connect(updateInventory)

return {}
