--[[
    juanita_esp.lua

    A performant, CS:GO-style Drawing ESP designed to bolt onto the juanitahaxx
    Library (Window / Page / Section / Toggle / Slider / Dropdown / Colorpicker).

    Features:
        boxes (full + corner), names, health bar, ammo bar, distance, weapon,
        team check + team colors, head circle, skeleton, look-angle line,
        off-screen arrows, occluded chams, outlines on everything (toggle),
        fade in/out, full positioning control, AI/NPC ESP, loot ESP,
        and inventory value display.

    Usage (see esp_example.lua):
        local ESP = loadstring(game:HttpGet("...juanita_esp.lua"))()
        ESP:Init({ Library = Library, Window = Window })

    Notes:
        - Everything is read live from Library.Flags every frame, matching the
          "minimal callbacks, logic in RenderStepped" pattern.
        - Drawing objects are created ONCE per player and reused. Nothing is
          created or destroyed on the render loop.
        - Dual-outline approach: outer black square + inner black square frame
          the colored box line so outlines never render on top.
]]

--//ANCHOR Services & caching
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local RepStorage   = game:GetService("ReplicatedStorage")

local LocalPlayer  = Players.LocalPlayer
local Camera       = Workspace.CurrentCamera

-- custom font: download 04B_03 pixel font if available
local EspFont = 2 -- default fallback
pcall(function()
    local ttf_path = "alpha/04B_03__.ttf"
    if not isfile(ttf_path) then
        makefolder("alpha")
        writefile(ttf_path, game:HttpGet("https://github.com/YellowFireFighter/Crumbleware-Rewrite/raw/refs/heads/main/Util/04B_03__.TTF"))
    end
    if Drawing and Drawing.Fonts then
        if DrawFont.Register then
            print("registered")
            EspFont = DrawFont.Register(ttf_path)
        elseif Drawing.Fonts.Plex then
            print("failed sir")
            EspFont = Drawing.Fonts.Plex
        end
    end
end)

local floor        = math.floor
local clamp        = math.clamp
local round        = function(n) return floor(n + 0.5) end

local Vector2new   = Vector2.new
local Color3new    = Color3.new
local fromRGB      = Color3.fromRGB

--//ANCHOR Module state
local ESP = {
    Library     = nil,
    Objects     = { },   -- [player] = drawing pool
    Chams       = { },   -- [player] = { Visible = Highlight, Occluded = Highlight }
    NPCObjects  = { },   -- [model]  = drawing pool  (AI/NPC ESP)
    LootPools   = { },   -- [model]  = loot draw pool (Loot ESP)
    Connections = { },
    Loaded      = false,
    Unloaded    = false,
}

--//ANCHOR NPC / Loot runtime state (not in the table to keep it lightweight)
local npc_container    = nil
local npc_rescan_timer = 0
local NPC_RESCAN_INTERVAL = 3

local loot_rescan_timer = 0
local LOOT_RESCAN_INTERVAL = 2

local item_value_cache = {} -- [itemName] -> number or false

--//ANCHOR Skeleton bone maps (part-name pairs)
local R15_BONES = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}

local R6_BONES = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
}

local MAX_BONES = #R15_BONES -- pre-allocate this many skeleton lines per player

--//ANCHOR Flag helpers (read live every frame)
local function FlagBool(name)
    return ESP.Library.Flags[name] == true
end

local function FlagNumber(name, fallback)
    local v = ESP.Library.Flags[name]
    if type(v) == "number" then return v end
    return fallback
end

local function FlagString(name, fallback)
    local v = ESP.Library.Flags[name]
    if type(v) == "string" then return v end
    return fallback
end

local function FlagColor(name, fallback)
    local v = ESP.Library.Flags[name]
    if v and v.Color then return v.Color end
    return fallback
end

--//ANCHOR Drawing helpers
local function NewDrawing(class, props)
    local obj = Drawing.new(class)
    if props then
        for key, value in pairs(props) do
            obj[key] = value
        end
    end
    return obj
end

local function SafeRemove(obj)
    if obj and isrenderobj and isrenderobj(obj) then
        obj:Remove()
    elseif obj and obj.Remove then
        pcall(function() obj:Remove() end)
    end
end

--//ANCHOR Projection
local function WorldToScreen(worldPos)
    local screen, onScreen = Camera:WorldToViewportPoint(worldPos)
    return Vector2new(screen.X, screen.Y), screen.Z, (screen.Z > 0)
end

--//ANCHOR Per-player pool factory
local function MakeText()
    return NewDrawing("Text", {
        Font = EspFont,
        Size = 13,
        Center = true,
        Outline = true,
        Color = Color3new(1, 1, 1),
        Visible = false,
    })
end

local function MakeLine()
    return NewDrawing("Line", { Thickness = 1, Visible = false })
end

local function MakeSquare(filled)
    return NewDrawing("Square", { Thickness = 1, Filled = filled and true or false, Visible = false })
end

local function CreatePool()
    local pool = { }

    --// Box (full) + dual outline (outer black + inner black, colored box between)
    pool.BoxOutline      = MakeSquare(false)
    pool.BoxInnerOutline = MakeSquare(false)
    pool.Box             = MakeSquare(false)

    --// Corner box: 8 colored segments + 16 outline segments (2 per colored, ±1px offset)
    pool.Corners        = { }
    pool.CornerOutlines = { }
    for i = 1, 16 do
        pool.CornerOutlines[i] = MakeLine()
    end
    for i = 1, 8 do
        pool.Corners[i] = MakeLine()
    end

    --// Health bar (bg / fill / outline)
    pool.HealthOutline = MakeSquare(false)
    pool.HealthBg      = MakeSquare(true)
    pool.HealthFill    = MakeSquare(true)

    --// Ammo bar (bg / fill / outline)
    pool.AmmoOutline = MakeSquare(false)
    pool.AmmoBg      = MakeSquare(true)
    pool.AmmoFill    = MakeSquare(true)

    --// Texts
    pool.Name           = MakeText()
    pool.Distance       = MakeText()
    pool.Weapon         = MakeText()
    pool.InventoryValue = MakeText()

    --// Flag texts (right side, one per flag)
    local MAX_FLAGS = 6
    pool.FlagTexts = {}
    for i = 1, MAX_FLAGS do
        pool.FlagTexts[i] = MakeText()
    end
    --// Head circle + outline
    pool.HeadOutline = NewDrawing("Circle", { Thickness = 3, Filled = false, Visible = false })
    pool.Head        = NewDrawing("Circle", { Thickness = 1, Filled = false, Visible = false })

    --// Look-angle line + outline
    pool.LookOutline = NewDrawing("Line", { Thickness = 3, Visible = false })
    pool.Look        = NewDrawing("Line", { Thickness = 1, Visible = false })

    --// Off-screen arrow + outline
    pool.ArrowOutline = NewDrawing("Triangle", { Thickness = 1, Filled = false, Visible = false })
    pool.Arrow        = NewDrawing("Triangle", { Filled = true, Visible = false })

    --// Skeleton lines + outlines
    pool.Skeleton        = { }
    pool.SkeletonOutline = { }
    for i = 1, MAX_BONES do
        pool.SkeletonOutline[i] = NewDrawing("Line", { Thickness = 3, Visible = false })
        pool.Skeleton[i]        = MakeLine()
    end

    --// Per-player runtime state
    pool.Fade = 0 -- current opacity 0..1 (used for fade in/out)
    pool.HealthRatio = 1 -- smoothed health for the tweening health bar

    return pool
end

--//ANCHOR Loot draw pool (lightweight: name + distance only)
local function CreateLootPool()
    return {
        Name     = MakeText(),
        Distance = MakeText(),
    }
end

local function RemoveLootPool(pool)
    if not pool then return end
    SafeRemove(pool.Name)
    SafeRemove(pool.Distance)
end

local function HideLootPool(pool)
    if pool.Name.Visible then pool.Name.Visible = false end
    if pool.Distance.Visible then pool.Distance.Visible = false end
end

--//ANCHOR RemovePool
local function RemovePool(pool)
    if not pool then return end

    SafeRemove(pool.BoxOutline)
    SafeRemove(pool.BoxInnerOutline)
    SafeRemove(pool.Box)

    for i = 1, 16 do
        SafeRemove(pool.CornerOutlines[i])
    end
    for i = 1, 8 do
        SafeRemove(pool.Corners[i])
    end

    SafeRemove(pool.HealthOutline)
    SafeRemove(pool.HealthBg)
    SafeRemove(pool.HealthFill)

    SafeRemove(pool.AmmoOutline)
    SafeRemove(pool.AmmoBg)
    SafeRemove(pool.AmmoFill)

    SafeRemove(pool.Name)
    SafeRemove(pool.Distance)
    SafeRemove(pool.Weapon)
    SafeRemove(pool.InventoryValue)
    for i = 1, #pool.FlagTexts do SafeRemove(pool.FlagTexts[i]) end

    SafeRemove(pool.HeadOutline)
    SafeRemove(pool.Head)

    SafeRemove(pool.LookOutline)
    SafeRemove(pool.Look)

    SafeRemove(pool.ArrowOutline)
    SafeRemove(pool.Arrow)

    for i = 1, MAX_BONES do
        SafeRemove(pool.SkeletonOutline[i])
        SafeRemove(pool.Skeleton[i])
    end
end

--//ANCHOR Visibility helpers
local function Hide(obj)
    if obj.Visible then obj.Visible = false end
end

local function HidePool(pool)
    Hide(pool.BoxOutline) Hide(pool.BoxInnerOutline) Hide(pool.Box)
    for i = 1, 16 do Hide(pool.CornerOutlines[i]) end
    for i = 1, 8 do Hide(pool.Corners[i]) end
    Hide(pool.HealthOutline) Hide(pool.HealthBg) Hide(pool.HealthFill)
    Hide(pool.AmmoOutline) Hide(pool.AmmoBg) Hide(pool.AmmoFill)
    Hide(pool.Name) Hide(pool.Distance) Hide(pool.Weapon) Hide(pool.InventoryValue)
    for i = 1, #pool.FlagTexts do Hide(pool.FlagTexts[i]) end
    Hide(pool.HeadOutline) Hide(pool.Head)
    Hide(pool.LookOutline) Hide(pool.Look)
    Hide(pool.ArrowOutline) Hide(pool.Arrow)
    for i = 1, MAX_BONES do Hide(pool.SkeletonOutline[i]) Hide(pool.Skeleton[i]) end
end

--//ANCHOR Chams (occluded chams via cloned model + dual Highlights)
local function BuildChams(player, character)
    local old = ESP.Chams[player]
    if old then
        if old.Los then old.Los:Destroy() end
        if old.Occ then old.Occ:Destroy() end
        if old.Model then old.Model:Destroy() end
        ESP.Chams[player] = nil
    end

    local model = Instance.new("Model")
    model.Name = "ChamsChr"

    for _, child in pairs(character:GetChildren()) do
        if not child:IsA("BasePart") then continue end

        local cloned = child:Clone()
        cloned:ClearAllChildren()
        cloned.CanCollide   = false
        cloned.Anchored     = false
        cloned.CastShadow   = false
        cloned.Transparency = 1
        if cloned:IsA("MeshPart") then cloned.TextureID = "" end
        cloned.Size   = cloned.Size * 0.99
        cloned.Parent = model

        local weld = Instance.new("WeldConstraint")
        weld.Part0  = cloned
        weld.Part1  = child
        weld.Parent = cloned
    end

    model.Parent = Workspace

    local los = Instance.new("Highlight")
    los.DepthMode           = Enum.HighlightDepthMode.Occluded
    los.OutlineTransparency = 1
    los.Adornee             = character
    los.Parent              = character

    local occ = los:Clone()
    occ.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    occ.Adornee   = model
    occ.Parent    = model

    local set = { Los = los, Occ = occ, Model = model, Char = character }
    ESP.Chams[player] = set
    return set
end

local function GetChams(player, character)
    local set = ESP.Chams[player]
    if set and set.Char == character and set.Model and set.Model.Parent then
        return set
    end
    return BuildChams(player, character)
end

local function RemoveChams(player)
    local set = ESP.Chams[player]
    if not set then return end
    if set.Los then set.Los:Destroy() end
    if set.Occ then set.Occ:Destroy() end
    if set.Model then set.Model:Destroy() end
    ESP.Chams[player] = nil
end

local function HideChams(player)
    local set = ESP.Chams[player]
    if not set then return end
    if set.Los.Enabled then set.Los.Enabled = false end
    if set.Occ.Enabled then set.Occ.Enabled = false end
end

--//ANCHOR Ammo reader (best-effort, game-specific values)
local AMMO_NAMES     = { "Ammo", "CurrentAmmo", "Bullets", "Rounds", "Mag", "Magazine", "ammoCurrent" }
local MAX_AMMO_NAMES = { "MaxAmmo", "MaxBullets", "MaxRounds", "Clip", "ClipSize", "Capacity", "ammoSize" }

local function FindValue(parent, names)
    for _, name in ipairs(names) do
        local v = parent:FindFirstChild(name)
        if v and v:IsA("ValueBase") then
            return v.Value
        end
        local attr = parent:GetAttribute(name)
        if type(attr) == "number" then
            return attr
        end
    end
    return nil
end

local function ReadAmmo(character)
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return nil end

    -- Havoc pattern: Tool._data.ammoCurrent / Tool._data.ammoSize
    local data = tool:FindFirstChild("_data")
    if data then
        local curVal = data:FindFirstChild("ammoCurrent")
        local maxVal = data:FindFirstChild("ammoSize")
        if curVal and maxVal and curVal:IsA("ValueBase") and maxVal:IsA("ValueBase") then
            local cur, max = curVal.Value, maxVal.Value
            if max and max > 0 then
                return clamp(cur / max, 0, 1), cur, max
            end
        end
    end

    -- fallback: generic names on the tool itself
    local cur = FindValue(tool, AMMO_NAMES)
    local max = FindValue(tool, MAX_AMMO_NAMES)
    if not cur or not max or max <= 0 then return nil end

    return clamp(cur / max, 0, 1), cur, max
end

local function ReadWeapon(character)
    local tool = character:FindFirstChildOfClass("Tool")
    return tool and tool.Name or nil
end

--//ANCHOR Inventory value reader (Havoc: ReplicatedStorage.__profiles.<Name>)
local function ReadInventoryValue(player)
    local profiles = RepStorage:FindFirstChild("__profiles")
    if not profiles then return nil end
    local profile = profiles:FindFirstChild(player.Name)
    if not profile then return nil end

    -- try direct money / cash value
    for _, child in ipairs(profile:GetChildren()) do
        if child:IsA("ValueBase") then
            local n = child.Name:lower()
            if n == "cash" or n == "money" or n == "coins" or n == "balance" or n == "roubles" then
                return child.Value
            end
        end
    end

    -- try inventory folder and sum item counts
    local inv = profile:FindFirstChild("inventory") or profile:FindFirstChild("Inventory")
    if inv then
        local total = 0
        local found = false
        for _, item in ipairs(inv:GetChildren()) do
            if item:IsA("ValueBase") then
                total = total + (tonumber(item.Value) or 0)
                found = true
            elseif item:IsA("Folder") then
                -- count sub-items
                total = total + #item:GetChildren()
                found = true
            end
        end
        if found then return total end
    end

    -- try attributes
    local cash = profile:GetAttribute("cash") or profile:GetAttribute("money") or profile:GetAttribute("roubles")
    if type(cash) == "number" then return cash end

    return nil
end

--//ANCHOR Loot value reader (best-effort via item modules)
local function GetLootValue(item_name)
    if item_value_cache[item_name] ~= nil then
        local cached = item_value_cache[item_name]
        return cached ~= false and cached or 0
    end

    local storage = RepStorage:FindFirstChild("Storage")
    if not storage then
        item_value_cache[item_name] = false
        return 0
    end
    local modules = storage:FindFirstChild("Modules")
    if not modules then
        item_value_cache[item_name] = false
        return 0
    end

    -- try Items/<name>
    local items = modules:FindFirstChild("Items")
    if items then
        local mod = items:FindFirstChild(item_name)
        if mod and mod:IsA("ModuleScript") then
            local ok, data = pcall(require, mod)
            if ok and type(data) == "table" then
                local val = data.value or data.price or data.worth or data.sellPrice or 0
                item_value_cache[item_name] = val
                return val
            end
        end
    end

    -- try Library.itemData
    local lib = modules:FindFirstChild("Library")
    if lib then
        local itemData = lib:FindFirstChild("itemData")
        if itemData and itemData:IsA("ModuleScript") then
            local ok, data = pcall(require, itemData)
            if ok and type(data) == "table" and data[item_name] then
                local val = data[item_name].value or data[item_name].price or 0
                item_value_cache[item_name] = val
                return val
            end
        end
    end

    item_value_cache[item_name] = false
    return 0
end

--//ANCHOR Bar drawer
local function DrawBar(fill, bg, outline, x, y, w, h, ratio, vertical, color, opacity, outlineOn)
    bg.Position = Vector2new(x, y)
    bg.Size     = Vector2new(w, h)
    bg.Color    = Color3new(0, 0, 0)
    bg.Filled   = true
    bg.Transparency = 0.6 * opacity
    bg.Visible  = true

    if vertical then
        local fh = h * ratio
        fill.Position = Vector2new(x, y + (h - fh))
        fill.Size     = Vector2new(w, fh)
    else
        fill.Position = Vector2new(x, y)
        fill.Size     = Vector2new(w * ratio, h)
    end
    fill.Color   = color
    fill.Filled  = true
    fill.Transparency = opacity
    fill.Visible = true

    if outlineOn then
        outline.Position = Vector2new(x - 1, y - 1)
        outline.Size     = Vector2new(w + 2, h + 2)
        outline.Color    = Color3new(0, 0, 0)
        outline.Filled   = false
        outline.Thickness = 1
        outline.Transparency = opacity
        outline.Visible  = true
    else
        outline.Visible = false
    end
end

--//ANCHOR Text placer with side stacking
local function PlaceText(textObj, str, side, layout, color, size, opacity)
    if not str or str == "" then
        textObj.Visible = false
        return
    end

    textObj.Text  = str
    textObj.Size  = size
    textObj.Font  = EspFont
    textObj.Color = color
    textObj.Outline      = FlagBool("esp_outlines")
    textObj.Transparency = opacity

    local bounds  = textObj.TextBounds or Vector2new(#str * size * 0.5, size)
    local centerX = layout.cx

    if side == "Top" then
        textObj.Center   = true
        local y          = layout.topY - size
        textObj.Position = Vector2new(centerX, y)
        layout.topY      = y - 1
    elseif side == "Bottom" then
        textObj.Center   = true
        local y          = layout.botY
        textObj.Position = Vector2new(centerX, y)
        layout.botY      = y + size + 1
    elseif side == "Left" then
        textObj.Center   = false
        textObj.Position = Vector2new(layout.leftX - bounds.X, layout.leftSlot)
        layout.leftSlot  = layout.leftSlot + size + 1
    elseif side == "Right" then
        textObj.Center   = false
        textObj.Position = Vector2new(layout.rightX, layout.rightSlot)
        layout.rightSlot = layout.rightSlot + size + 1
    end

    textObj.Visible = true
end

--//ANCHOR Corner box drawer (8 colored segments, 16 outline segments — dual ±1px offset)
local function DrawCorners(pool, minX, minY, maxX, maxY, color, opacity, outlineOn)
    local w   = maxX - minX
    local h   = maxY - minY
    local len = clamp(math.min(w, h) * 0.28, 3, 14)

    --// seg layout: odd = horizontal, even = vertical
    local pts = {
        -- top-left
        { Vector2new(minX, minY), Vector2new(minX + len, minY) },       -- 1 horiz
        { Vector2new(minX, minY), Vector2new(minX, minY + len) },       -- 2 vert
        -- top-right
        { Vector2new(maxX, minY), Vector2new(maxX - len, minY) },       -- 3 horiz
        { Vector2new(maxX, minY), Vector2new(maxX, minY + len) },       -- 4 vert
        -- bottom-left
        { Vector2new(minX, maxY), Vector2new(minX + len, maxY) },       -- 5 horiz
        { Vector2new(minX, maxY), Vector2new(minX, maxY - len) },       -- 6 vert
        -- bottom-right
        { Vector2new(maxX, maxY), Vector2new(maxX - len, maxY) },       -- 7 horiz
        { Vector2new(maxX, maxY), Vector2new(maxX, maxY - len) },       -- 8 vert
    }

    for i = 1, 8 do
        local seg  = pts[i]
        local line = pool.Corners[i]
        local out1 = pool.CornerOutlines[i * 2 - 1]
        local out2 = pool.CornerOutlines[i * 2]

        if outlineOn then
            local isHoriz = (i % 2 == 1)
            if isHoriz then
                -- offset Y ±1 for horizontal segments
                out1.From = Vector2new(seg[1].X, seg[1].Y - 1)
                out1.To   = Vector2new(seg[2].X, seg[2].Y - 1)
                out2.From = Vector2new(seg[1].X, seg[1].Y + 1)
                out2.To   = Vector2new(seg[2].X, seg[2].Y + 1)
            else
                -- offset X ±1 for vertical segments
                out1.From = Vector2new(seg[1].X - 1, seg[1].Y)
                out1.To   = Vector2new(seg[2].X - 1, seg[2].Y)
                out2.From = Vector2new(seg[1].X + 1, seg[1].Y)
                out2.To   = Vector2new(seg[2].X + 1, seg[2].Y)
            end
            out1.Color     = Color3new(0, 0, 0)
            out1.Thickness = 1
            out1.Transparency = opacity
            out1.Visible   = true
            out2.Color     = Color3new(0, 0, 0)
            out2.Thickness = 1
            out2.Transparency = opacity
            out2.Visible   = true
        else
            out1.Visible = false
            out2.Visible = false
        end

        line.From      = seg[1]
        line.To        = seg[2]
        line.Color     = color
        line.Thickness = 1
        line.Transparency = opacity
        line.Visible   = true
    end
end

--//ANCHOR Off-screen arrow drawer
local function DrawArrow(pool, screenPos, depth, color, opacity, outlineOn)
    local viewport = Camera.ViewportSize
    local center   = Vector2new(viewport.X / 2, viewport.Y / 2)
    local radius   = clamp(FlagNumber("esp_arrow_radius", 150), 50, 400)
    local size     = clamp(FlagNumber("esp_arrow_size", 18), 8, 40)

    local dir = Vector2new(screenPos.X, screenPos.Y) - center
    if depth < 0 then
        dir = dir * -1
    end
    if dir.Magnitude < 1 then
        pool.Arrow.Visible = false
        pool.ArrowOutline.Visible = false
        return
    end
    dir = dir.Unit

    local perp = Vector2new(-dir.Y, dir.X)
    local tip  = center + dir * radius
    local b1   = tip - dir * size + perp * (size * 0.5)
    local b2   = tip - dir * size - perp * (size * 0.5)

    pool.Arrow.PointA  = tip
    pool.Arrow.PointB  = b1
    pool.Arrow.PointC  = b2
    pool.Arrow.Color   = color
    pool.Arrow.Filled  = true
    pool.Arrow.Transparency = opacity
    pool.Arrow.Visible = true

    if outlineOn then
        pool.ArrowOutline.PointA  = tip
        pool.ArrowOutline.PointB  = b1
        pool.ArrowOutline.PointC  = b2
        pool.ArrowOutline.Color   = Color3new(0, 0, 0)
        pool.ArrowOutline.Filled  = false
        pool.ArrowOutline.Thickness = 1
        pool.ArrowOutline.Transparency = opacity
        pool.ArrowOutline.Visible = true
    else
        pool.ArrowOutline.Visible = false
    end
end

--//ANCHOR Skeleton drawer
local function DrawSkeleton(pool, character, color, opacity, outlineOn)
    local bones = character:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
    local used  = 0

    for i = 1, #bones do
        local pair = bones[i]
        local p0   = character:FindFirstChild(pair[1])
        local p1   = character:FindFirstChild(pair[2])

        local line = pool.Skeleton[i]
        local out  = pool.SkeletonOutline[i]

        if p0 and p1 then
            local a, aDepth, aOn = WorldToScreen(p0.Position)
            local b, bDepth, bOn = WorldToScreen(p1.Position)

            if aOn and bOn then
                if outlineOn then
                    out.From      = a
                    out.To        = b
                    out.Color     = Color3new(0, 0, 0)
                    out.Thickness = 3
                    out.Transparency = opacity
                    out.Visible   = true
                else
                    out.Visible = false
                end

                line.From      = a
                line.To        = b
                line.Color     = color
                line.Thickness = 1
                line.Transparency = opacity
                line.Visible   = true
                used = used + 1
            else
                line.Visible = false
                out.Visible  = false
            end
        else
            line.Visible = false
            out.Visible  = false
        end
    end

    for i = #bones + 1, MAX_BONES do
        pool.Skeleton[i].Visible        = false
        pool.SkeletonOutline[i].Visible = false
    end
end

--//ANCHOR NPC container finder
local function FindNPCContainer()
    for _, child in ipairs(Workspace:GetChildren()) do
        if not child:IsA("Model") then continue end
        if child:FindFirstChild("NPCs") then return child end
        for _, sub in ipairs(child:GetChildren()) do
            if sub:IsA("Model") and sub:FindFirstChild("Humanoid") and sub:FindFirstChild("HumanoidRootPart") then
                return child
            end
        end
    end
    return nil
end

local function GetNPCModels()
    if not npc_container or not npc_container.Parent then
        npc_container = FindNPCContainer()
    end
    if not npc_container then return {} end

    local models = {}
    local function scan(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("Model") and child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
                -- skip player characters (players have MovementAnticheat, AI don't)
                if Players:GetPlayerFromCharacter(child) then continue end
                if child:FindFirstChild("MovementAnticheat") then continue end
                table.insert(models, child)
            elseif child:IsA("Folder") or (child:IsA("Model") and not child:FindFirstChild("Humanoid")) then
                scan(child)
            end
        end
    end
    scan(npc_container)
    return models
end

--//ANCHOR Loot scanner (no GetDescendants — walk known folders)
local function ScanLoots()
    local buildings = Workspace:FindFirstChild("Buildings")
    if not buildings then return {} end
    local loots = buildings:FindFirstChild("Loots")
    if not loots then return {} end

    local results = {}

    -- ground items: Loots.Items
    local items_folder = loots:FindFirstChild("Items")
    if items_folder then
        for _, item in ipairs(items_folder:GetChildren()) do
            if item:IsA("Model") then
                local main = item:FindFirstChild("Main")
                if main and main:IsA("BasePart") then
                    table.insert(results, item)
                end
            end
        end
    end

    -- crates: Loots.Loots.Crates
    local loots2 = loots:FindFirstChild("Loots")
    if loots2 then
        local crates = loots2:FindFirstChild("Crates")
        if crates then
            for _, crate in ipairs(crates:GetChildren()) do
                if crate:IsA("Model") and crate:FindFirstChild("PromptData", true) then
                    table.insert(results, crate)
                end
            end
        end
    end

    return results
end

--//ANCHOR Per-player update (the heavy lifter)
local function UpdatePlayer(player, pool, deltaTime)
    -- skip local player
    if player == LocalPlayer then pool.Fade = 0 HidePool(pool) HideChams(player) return end

    local character = player.Character
    if not character then pool.Fade = 0 HidePool(pool) HideChams(player) return end
    -- skip fake/unspawned characters not in workspace (e.g. stored in ReplicatedStorage)
    if not character:IsDescendantOf(Workspace) then pool.Fade = 0 HidePool(pool) HideChams(player) return end

    local hrp      = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or humanoid.Health <= 0 then
        pool.Fade = 0 HidePool(pool) HideChams(player) return
    end

    --// Team check + distance decide validity
    local enemy = true
    if LocalPlayer.Team and player.Team then
        enemy = (player.Team ~= LocalPlayer.Team)
    end

    local camPos   = Camera.CFrame.Position
    local distance = (hrp.Position - camPos).Magnitude
    local maxDist  = FlagNumber("esp_maxdist", 1000)

    local valid = true
    if FlagBool("esp_teamcheck") and not enemy then valid = false end
    if distance > maxDist then valid = false end

    --//ANCHOR Fade
    local target = valid and 1 or 0
    if FlagBool("esp_fade") then
        local speed = clamp(FlagNumber("esp_fade_speed", 8), 1, 30)
        pool.Fade = pool.Fade + (target - pool.Fade) * clamp(deltaTime * speed, 0, 1)
        if pool.Fade ~= pool.Fade then pool.Fade = target end
    else
        pool.Fade = target
    end

    if pool.Fade <= 0.02 then
        if target == 0 then pool.Fade = 0 end
        HidePool(pool)
        HideChams(player)
        return
    end

    local alpha     = pool.Fade
    local outlineOn = FlagBool("esp_outlines")

    --// Colors
    local boxColor = FlagColor("esp_box_color", fromRGB(255, 255, 255))
    if FlagBool("esp_team_color") then
        boxColor = enemy and FlagColor("esp_enemy_color", fromRGB(255, 80, 80))
                          or  FlagColor("esp_friend_color", fromRGB(80, 160, 255))
    end

    --//ANCHOR Chams
    if FlagBool("esp_chams") and valid then
        local set   = GetChams(player, character)
        local vis   = FlagColor("esp_chams_visible", fromRGB(0, 200, 255))
        local occ   = FlagColor("esp_chams_occluded", fromRGB(255, 40, 40))
        local fillT = clamp(FlagNumber("esp_chams_fill", 0.5), 0, 1)

        set.Los.Enabled          = true
        set.Los.FillColor        = vis
        set.Los.FillTransparency = fillT
        set.Occ.Enabled          = true
        set.Occ.FillColor        = occ
        set.Occ.FillTransparency = fillT
    else
        RemoveChams(player)
    end

    --// Bounding box from R6 body parts only (GetBoundingBox is broken in some games)
    local BODY_PARTS = {"Head", "HumanoidRootPart", "Left Arm", "Left Leg", "Right Arm", "Right Leg", "Torso"}
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOn      = false

    for _, partName in ipairs(BODY_PARTS) do
        local part = character:FindFirstChild(partName)
        if not part or not part:IsA("BasePart") then continue end
        local cf, sz = part.CFrame, part.Size
        local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local corner = (cf * CFrame.new(hx * x, hy * y, hz * z)).Position
                    local screen, depth, on = WorldToScreen(corner)
                    if on then anyOn = true end
                    if screen.X < minX then minX = screen.X end
                    if screen.Y < minY then minY = screen.Y end
                    if screen.X > maxX then maxX = screen.X end
                    if screen.Y > maxY then maxY = screen.Y end
                end
            end
        end
    end

    --// Off-screen: only the arrow applies
    if not anyOn then
        HidePool(pool)
        if FlagBool("esp_arrows") then
            local sp, depth = WorldToScreen(hrp.Position)
            DrawArrow(pool, sp, depth,
                FlagColor("esp_arrow_color", boxColor), alpha, outlineOn)
        end
        return
    end

    local w = maxX - minX
    local h = maxY - minY
    local textSize = clamp(FlagNumber("esp_text_size", 13), 8, 24)

    --//ANCHOR Box (Full or Corner — dual-outline approach)
    local boxType   = FlagString("esp_box_type", "Full")
    local boxOn     = FlagBool("esp_box")
    local fullBox   = boxOn and boxType == "Full"
    local cornerBox = boxOn and boxType == "Corner"

    if fullBox then
        if outlineOn then
            --// outer outline (1px outside the colored box)
            pool.BoxOutline.Position  = Vector2new(minX - 1, minY - 1)
            pool.BoxOutline.Size      = Vector2new(w + 2, h + 2)
            pool.BoxOutline.Color     = Color3new(0, 0, 0)
            pool.BoxOutline.Thickness = 1
            pool.BoxOutline.Transparency = alpha
            pool.BoxOutline.Filled    = false
            pool.BoxOutline.Visible   = true

            --// inner outline (1px inside the colored box)
            if w > 2 and h > 2 then
                pool.BoxInnerOutline.Position  = Vector2new(minX + 1, minY + 1)
                pool.BoxInnerOutline.Size      = Vector2new(w - 2, h - 2)
                pool.BoxInnerOutline.Color     = Color3new(0, 0, 0)
                pool.BoxInnerOutline.Thickness = 1
                pool.BoxInnerOutline.Transparency = alpha
                pool.BoxInnerOutline.Filled    = false
                pool.BoxInnerOutline.Visible   = true
            else
                pool.BoxInnerOutline.Visible = false
            end
        else
            pool.BoxOutline.Visible      = false
            pool.BoxInnerOutline.Visible = false
        end

        pool.Box.Position  = Vector2new(minX, minY)
        pool.Box.Size      = Vector2new(w, h)
        pool.Box.Color     = boxColor
        pool.Box.Thickness = 1
        pool.Box.Transparency = alpha
        pool.Box.Filled    = false
        pool.Box.Visible   = true
    else
        pool.Box.Visible             = false
        pool.BoxOutline.Visible      = false
        pool.BoxInnerOutline.Visible = false
    end

    if cornerBox then
        DrawCorners(pool, minX, minY, maxX, maxY, boxColor, alpha, outlineOn)
    else
        for i = 1, 8 do
            pool.Corners[i].Visible = false
        end
        for i = 1, 16 do
            pool.CornerOutlines[i].Visible = false
        end
    end

    --// Layout accumulators
    local layout = {
        cx        = (minX + maxX) / 2,
        cy        = (minY + maxY) / 2,
        topY      = minY - 2,
        botY      = maxY + 2,
        leftX     = minX - 4,
        rightX    = maxX + 4,
        leftSlot  = minY,
        rightSlot = minY,
    }

    --//ANCHOR Health bar
    if FlagBool("esp_health") then
        local realRatio = clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

        local hspeed = clamp(FlagNumber("esp_health_speed", 10), 1, 30)
        pool.HealthRatio = pool.HealthRatio + (realRatio - pool.HealthRatio) * clamp(deltaTime * hspeed, 0, 1)
        if pool.HealthRatio ~= pool.HealthRatio then pool.HealthRatio = realRatio end
        local ratio = pool.HealthRatio

        local low   = FlagColor("esp_health_low", fromRGB(255, 40, 40))
        local high  = FlagColor("esp_health_high", fromRGB(60, 255, 80))
        local hcol  = low:Lerp(high, ratio)
        local side  = FlagString("esp_health_pos", "Left")
        local bw    = clamp(FlagNumber("esp_health_width", 3), 1, 12)

        if side == "Left" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX - (bw + 3), minY, bw, h, ratio, true, hcol, alpha, outlineOn)
            layout.leftX = layout.leftX - (bw + 5)
        elseif side == "Right" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                maxX + 3, minY, bw, h, ratio, true, hcol, alpha, outlineOn)
            layout.rightX = layout.rightX + (bw + 5)
        elseif side == "Top" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX, minY - (bw + 3), w, bw, ratio, false, hcol, alpha, outlineOn)
            layout.topY = layout.topY - (bw + 5)
        else -- Bottom
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX, maxY + 3, w, bw, ratio, false, hcol, alpha, outlineOn)
            layout.botY = layout.botY + (bw + 5)
        end
    else
        pool.HealthFill.Visible = false
        pool.HealthBg.Visible = false
        pool.HealthOutline.Visible = false
    end

    --//ANCHOR Ammo bar
    local ammoRatio = FlagBool("esp_ammo") and ReadAmmo(character) or nil
    if ammoRatio then
        local acol = FlagColor("esp_ammo_color", fromRGB(255, 200, 60))
        local side = FlagString("esp_ammo_pos", "Bottom")
        local abw = bw -- ammo bar width matches health bar width

        if side == "Top" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                minX, layout.topY - (abw + 3), w, abw, ammoRatio, false, acol, alpha, outlineOn)
            layout.topY = layout.topY - (abw + 5)
        elseif side == "Left" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                layout.leftX - (abw + 3), minY, abw, h, ammoRatio, true, acol, alpha, outlineOn)
            layout.leftX = layout.leftX - (abw + 5)
        elseif side == "Right" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                layout.rightX + 3, minY, abw, h, ammoRatio, true, acol, alpha, outlineOn)
            layout.rightX = layout.rightX + (abw + 5)
        else -- Bottom
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                minX, layout.botY + 3, w, abw, ammoRatio, false, acol, alpha, outlineOn)
            layout.botY = layout.botY + (abw + 5)
        end
    else
        pool.AmmoFill.Visible = false
        pool.AmmoBg.Visible = false
        pool.AmmoOutline.Visible = false
    end

    --//ANCHOR Texts (name / distance / weapon / inventory value)
    if FlagBool("esp_name") then
        PlaceText(pool.Name, player.Name, FlagString("esp_name_pos", "Top"),
            layout, FlagColor("esp_name_color", fromRGB(255, 255, 255)), textSize, alpha)
    else
        pool.Name.Visible = false
    end

    if FlagBool("esp_distance") then
        PlaceText(pool.Distance, ("%dm"):format(round(distance)),
            FlagString("esp_dist_pos", "Bottom"),
            layout, FlagColor("esp_dist_color", fromRGB(200, 200, 200)), textSize, alpha)
    else
        pool.Distance.Visible = false
    end

    if FlagBool("esp_weapon") then
        local weapon = ReadWeapon(character)
        PlaceText(pool.Weapon, weapon, FlagString("esp_weapon_pos", "Bottom"),
            layout, FlagColor("esp_weapon_color", fromRGB(180, 180, 255)), textSize, alpha)
    else
        pool.Weapon.Visible = false
    end

    --//ANCHOR Player flags (right side of box, stacking downward, scaled to box)
    local flag_idx = 0
    -- scale flag text: readable minimum, scale with box but don't let it get tiny
    local flag_size = clamp(math.min(textSize, h / 4), 9, 20)

    if FlagBool("esp_flags") then
        -- level
        if FlagBool("esp_flag_level") then
            local lv_str = nil
            pcall(function()
                local pd = player:FindFirstChild("playerData")
                if pd then local lv = pd:FindFirstChild("level"); if lv then lv_str = "Lv" .. tostring(lv.Value) end end
            end)
            if lv_str then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], lv_str, "Right", layout, FlagColor("esp_flag_level_color", fromRGB(200, 200, 100)), flag_size, alpha)
                end
            end
        end

        -- reloading
        if FlagBool("esp_flag_reload") then
            local is_reloading = false
            pcall(function()
                local tool = character:FindFirstChildOfClass("Tool")
                if tool then local d = tool:FindFirstChild("_data"); if d then local r = d:FindFirstChild("reload"); if r and r.Value then is_reloading = true end end end
            end)
            if is_reloading then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], "RELOAD", "Right", layout, FlagColor("esp_flag_reload_color", fromRGB(255, 100, 100)), flag_size, alpha)
                end
            end
        end

        -- k/d
        if FlagBool("esp_flag_kd") then
            local kd_str = nil
            pcall(function()
                local ls = player:FindFirstChild("leaderstats")
                if ls then
                    local k = ls:FindFirstChild("operator_kills"); local d = ls:FindFirstChild("death")
                    if k and d then kd_str = "KD:" .. tostring(d.Value > 0 and math.floor(k.Value / d.Value * 10) / 10 or k.Value) end
                end
            end)
            if kd_str then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], kd_str, "Right", layout, FlagColor("esp_flag_kd_color", fromRGB(200, 200, 100)), flag_size, alpha)
                end
            end
        end

        -- hit rate (current raid)
        if FlagBool("esp_flag_hitrate") then
            local hr_str = nil
            pcall(function()
                local pd = player:FindFirstChild("playerData")
                if pd then local acc = pd:FindFirstChild("accuracy"); if acc then
                    local h = acc:FindFirstChild("hits"); local s = acc:FindFirstChild("shots")
                    if h and s and s.Value > 0 then hr_str = math.floor(h.Value / s.Value * 100) .. "%" end
                end end
            end)
            if hr_str then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], hr_str, "Right", layout, FlagColor("esp_flag_hitrate_color", fromRGB(200, 200, 100)), flag_size, alpha)
                end
            end
        end

        -- headshot %
        if FlagBool("esp_flag_hsrate") then
            local hs_str = nil
            pcall(function()
                local ls = player:FindFirstChild("leaderstats")
                if ls then local hs = ls:FindFirstChild("headshots"); local hc = ls:FindFirstChild("hitCount")
                    if hs and hc and hc.Value > 0 then hs_str = "HS:" .. math.floor(hs.Value / hc.Value * 100) .. "%" end
                end
            end)
            if hs_str then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], hs_str, "Right", layout, FlagColor("esp_flag_hsrate_color", fromRGB(200, 200, 100)), flag_size, alpha)
                end
            end
        end

        -- inventory value (sum prices from Backpack slots 1-4)
        if FlagBool("esp_flag_invvalue") then
            local val_str = nil
            pcall(function()
                local bp = player:FindFirstChild("Backpack")
                if not bp then return end
                local total = 0
                for slot = 1, 4 do
                    local sv = bp:FindFirstChild(tostring(slot))
                    if sv and sv:IsA("ObjectValue") and sv.Value then
                        total = total + 1 -- count equipped items at minimum
                    end
                end
                local eq = bp:FindFirstChild("equipment")
                if eq then
                    for _, v in ipairs(eq:GetChildren()) do
                        if v:IsA("ObjectValue") and v.Value then total = total + 1 end
                    end
                end
                if total > 0 then val_str = total .. " items" end
            end)
            if val_str then
                flag_idx = flag_idx + 1
                if flag_idx <= #pool.FlagTexts then
                    PlaceText(pool.FlagTexts[flag_idx], val_str, "Right", layout, FlagColor("esp_flag_invvalue_color", fromRGB(100, 255, 100)), flag_size, alpha)
                end
            end
        end
    end

    -- hide unused flag slots
    for i = flag_idx + 1, #pool.FlagTexts do
        pool.FlagTexts[i].Visible = false
    end

    --// Inventory total value (bottom, uses getTotalPrice if available)
    if FlagBool("esp_inventory_value") then
        local val_str = nil
        pcall(function()
            local bp = player:FindFirstChild("Backpack")
            if not bp then return end
            local get_price = nil
            pcall(function() get_price = require(storage.Modules.Helper.getTotalPrice) end)
            if get_price and type(get_price) == "function" then
                local total = 0
                for slot = 1, 4 do
                    local sv = bp:FindFirstChild(tostring(slot))
                    if sv and sv:IsA("ObjectValue") and sv.Value then
                        pcall(function() total = total + get_price(sv.Value.Name) end)
                    end
                end
                if total > 0 then val_str = "$" .. tostring(total) end
            end
        end)
        PlaceText(pool.InventoryValue, val_str, "Bottom",
            layout, FlagColor("esp_dist_color", fromRGB(200, 200, 200)), textSize, alpha)
    else
        pool.InventoryValue.Visible = false
    end

    --//ANCHOR Head circle
    if FlagBool("esp_headcircle") then
        local head = character:FindFirstChild("Head")
        if head then
            local hs, hd, hon = WorldToScreen(head.Position)
            if hon then
                local radius = clamp(w * 0.18, 3, 30)
                local col    = FlagColor("esp_head_color", boxColor)

                if outlineOn then
                    pool.HeadOutline.Position  = hs
                    pool.HeadOutline.Radius    = radius
                    pool.HeadOutline.Color     = Color3new(0, 0, 0)
                    pool.HeadOutline.Thickness = 3
                    pool.HeadOutline.Filled    = false
                    pool.HeadOutline.Transparency = alpha
                    pool.HeadOutline.Visible   = true
                else
                    pool.HeadOutline.Visible = false
                end

                pool.Head.Position  = hs
                pool.Head.Radius    = radius
                pool.Head.Color     = col
                pool.Head.Thickness = 1
                pool.Head.Filled    = false
                pool.Head.Transparency = alpha
                pool.Head.Visible   = true
            else
                pool.Head.Visible = false
                pool.HeadOutline.Visible = false
            end
        end
    else
        pool.Head.Visible = false
        pool.HeadOutline.Visible = false
    end

    --//ANCHOR Look-angle line
    if FlagBool("esp_lookangle") then
        local head = character:FindFirstChild("Head") or hrp
        local len  = clamp(FlagNumber("esp_look_length", 3), 1, 20)
        local from = head.Position
        local to   = from + head.CFrame.LookVector * len

        local a, ad, aon = WorldToScreen(from)
        local b, bd, bon = WorldToScreen(to)

        if aon and bon then
            local col = FlagColor("esp_look_color", fromRGB(255, 255, 255))
            if outlineOn then
                pool.LookOutline.From      = a
                pool.LookOutline.To        = b
                pool.LookOutline.Color     = Color3new(0, 0, 0)
                pool.LookOutline.Thickness = 3
                pool.LookOutline.Transparency = alpha
                pool.LookOutline.Visible   = true
            else
                pool.LookOutline.Visible = false
            end

            pool.Look.From      = a
            pool.Look.To        = b
            pool.Look.Color     = col
            pool.Look.Thickness = 1
            pool.Look.Transparency = alpha
            pool.Look.Visible   = true
        else
            pool.Look.Visible = false
            pool.LookOutline.Visible = false
        end
    else
        pool.Look.Visible = false
        pool.LookOutline.Visible = false
    end

    --//ANCHOR Skeleton
    if FlagBool("esp_skeleton") then
        DrawSkeleton(pool, character,
            FlagColor("esp_skeleton_color", fromRGB(255, 255, 255)), alpha, outlineOn)
    else
        for i = 1, MAX_BONES do
            pool.Skeleton[i].Visible = false
            pool.SkeletonOutline[i].Visible = false
        end
    end

    --// on-screen, so no arrow
    pool.Arrow.Visible = false
    pool.ArrowOutline.Visible = false
end

--//ANCHOR Per-NPC update (simplified UpdatePlayer for AI entities)
local function UpdateNPC(model, pool, deltaTime)
    local hrp      = model:FindFirstChild("HumanoidRootPart")
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or humanoid.Health <= 0 then
        pool.Fade = 0 HidePool(pool) return
    end

    local camPos   = Camera.CFrame.Position
    local distance = (hrp.Position - camPos).Magnitude
    local maxDist  = FlagNumber("esp_maxdist", 1000)

    local valid = distance <= maxDist

    --// Fade
    local target = valid and 1 or 0
    if FlagBool("esp_fade") then
        local speed = clamp(FlagNumber("esp_fade_speed", 8), 1, 30)
        pool.Fade = pool.Fade + (target - pool.Fade) * clamp(deltaTime * speed, 0, 1)
        if pool.Fade ~= pool.Fade then pool.Fade = target end
    else
        pool.Fade = target
    end

    if pool.Fade <= 0.02 then
        if target == 0 then pool.Fade = 0 end
        HidePool(pool)
        return
    end

    local alpha     = pool.Fade
    local outlineOn = FlagBool("esp_outlines")
    local boxColor  = FlagColor("esp_ai_color", fromRGB(255, 150, 50))

    --// Bounding box from R6 body parts only
    local BODY_PARTS = {"Head", "HumanoidRootPart", "Left Arm", "Left Leg", "Right Arm", "Right Leg", "Torso"}
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOn      = false

    for _, partName in ipairs(BODY_PARTS) do
        local part = model:FindFirstChild(partName)
        if not part or not part:IsA("BasePart") then continue end
        local cf, sz = part.CFrame, part.Size
        local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local corner = (cf * CFrame.new(hx * x, hy * y, hz * z)).Position
                    local screen, depth, on = WorldToScreen(corner)
                    if on then anyOn = true end
                    if screen.X < minX then minX = screen.X end
                    if screen.Y < minY then minY = screen.Y end
                    if screen.X > maxX then maxX = screen.X end
                    if screen.Y > maxY then maxY = screen.Y end
                end
            end
        end
    end

    if not anyOn then
        HidePool(pool)
        return
    end

    local w = maxX - minX
    local h = maxY - minY
    local textSize = clamp(FlagNumber("esp_text_size", 13), 8, 24)

    --// Box (uses AI-specific flags)
    local boxType   = FlagString("esp_ai_box_type", "Full")
    local boxOn     = FlagBool("esp_ai_box")
    local fullBox   = boxOn and boxType == "Full"
    local cornerBox = boxOn and boxType == "Corner"

    if fullBox then
        if outlineOn then
            pool.BoxOutline.Position  = Vector2new(minX - 1, minY - 1)
            pool.BoxOutline.Size      = Vector2new(w + 2, h + 2)
            pool.BoxOutline.Color     = Color3new(0, 0, 0)
            pool.BoxOutline.Thickness = 1
            pool.BoxOutline.Transparency = alpha
            pool.BoxOutline.Filled    = false
            pool.BoxOutline.Visible   = true

            if w > 2 and h > 2 then
                pool.BoxInnerOutline.Position  = Vector2new(minX + 1, minY + 1)
                pool.BoxInnerOutline.Size      = Vector2new(w - 2, h - 2)
                pool.BoxInnerOutline.Color     = Color3new(0, 0, 0)
                pool.BoxInnerOutline.Thickness = 1
                pool.BoxInnerOutline.Transparency = alpha
                pool.BoxInnerOutline.Filled    = false
                pool.BoxInnerOutline.Visible   = true
            else
                pool.BoxInnerOutline.Visible = false
            end
        else
            pool.BoxOutline.Visible      = false
            pool.BoxInnerOutline.Visible = false
        end

        pool.Box.Position  = Vector2new(minX, minY)
        pool.Box.Size      = Vector2new(w, h)
        pool.Box.Color     = boxColor
        pool.Box.Thickness = 1
        pool.Box.Transparency = alpha
        pool.Box.Filled    = false
        pool.Box.Visible   = true
    else
        pool.Box.Visible             = false
        pool.BoxOutline.Visible      = false
        pool.BoxInnerOutline.Visible = false
    end

    if cornerBox then
        DrawCorners(pool, minX, minY, maxX, maxY, boxColor, alpha, outlineOn)
    else
        for i = 1, 8 do pool.Corners[i].Visible = false end
        for i = 1, 16 do pool.CornerOutlines[i].Visible = false end
    end

    --// Layout
    local layout = {
        cx        = (minX + maxX) / 2,
        cy        = (minY + maxY) / 2,
        topY      = minY - 2,
        botY      = maxY + 2,
        leftX     = minX - 4,
        rightX    = maxX + 4,
        leftSlot  = minY,
        rightSlot = minY,
    }

    --// Health bar (AI-specific flags)
    if FlagBool("esp_ai_health") then
        local realRatio = clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        local hspeed = clamp(FlagNumber("esp_health_speed", 10), 1, 30)
        pool.HealthRatio = pool.HealthRatio + (realRatio - pool.HealthRatio) * clamp(deltaTime * hspeed, 0, 1)
        if pool.HealthRatio ~= pool.HealthRatio then pool.HealthRatio = realRatio end
        local ratio = pool.HealthRatio
        local low   = FlagColor("esp_ai_health_low", fromRGB(255, 40, 40))
        local high  = FlagColor("esp_ai_health_high", fromRGB(60, 255, 80))
        local hcol  = low:Lerp(high, ratio)
        local side  = FlagString("esp_health_pos", "Left")
        local bw    = clamp(FlagNumber("esp_health_width", 3), 1, 12)

        if side == "Left" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX - (bw + 3), minY, bw, h, ratio, true, hcol, alpha, outlineOn)
            layout.leftX = layout.leftX - (bw + 5)
        elseif side == "Right" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                maxX + 3, minY, bw, h, ratio, true, hcol, alpha, outlineOn)
            layout.rightX = layout.rightX + (bw + 5)
        elseif side == "Top" then
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX, minY - (bw + 3), w, bw, ratio, false, hcol, alpha, outlineOn)
            layout.topY = layout.topY - (bw + 5)
        else
            DrawBar(pool.HealthFill, pool.HealthBg, pool.HealthOutline,
                minX, maxY + 3, w, bw, ratio, false, hcol, alpha, outlineOn)
            layout.botY = layout.botY + (bw + 5)
        end
    else
        pool.HealthFill.Visible    = false
        pool.HealthBg.Visible      = false
        pool.HealthOutline.Visible = false
    end

    --// Ammo bar (NPCs can hold tools too)
    local ammoRatio = FlagBool("esp_ammo") and ReadAmmo(model) or nil
    if ammoRatio then
        local acol = FlagColor("esp_ammo_color", fromRGB(255, 200, 60))
        DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
            minX, layout.botY, w, 3, ammoRatio, false, acol, alpha, outlineOn)
        layout.botY = layout.botY + 6
    else
        pool.AmmoFill.Visible    = false
        pool.AmmoBg.Visible      = false
        pool.AmmoOutline.Visible = false
    end

    --// Name (AI-specific)
    if FlagBool("esp_ai_name") then
        PlaceText(pool.Name, model.Name, "Top",
            layout, FlagColor("esp_ai_name_color", fromRGB(255, 150, 50)), textSize, alpha)
    else
        pool.Name.Visible = false
    end

    --// Distance
    if FlagBool("esp_ai_distance") then
        PlaceText(pool.Distance, ("%dm"):format(round(distance)), "Bottom",
            layout, FlagColor("esp_ai_dist_color", fromRGB(200, 200, 200)), textSize, alpha)
    else
        pool.Distance.Visible = false
    end

    --// Weapon
    if FlagBool("esp_ai_weapon") then
        local weapon = ReadWeapon(model)
        PlaceText(pool.Weapon, weapon, "Bottom",
            layout, FlagColor("esp_ai_weapon_color", fromRGB(180, 180, 255)), textSize, alpha)
    else
        pool.Weapon.Visible = false
    end

    --// NPC has no inventory value
    pool.InventoryValue.Visible = false

    --// Head circle
    if FlagBool("esp_headcircle") then
        local head = model:FindFirstChild("Head")
        if head then
            local hs, hd, hon = WorldToScreen(head.Position)
            if hon then
                local radius = clamp(w * 0.18, 3, 30)
                if outlineOn then
                    pool.HeadOutline.Position  = hs
                    pool.HeadOutline.Radius    = radius
                    pool.HeadOutline.Color     = Color3new(0, 0, 0)
                    pool.HeadOutline.Thickness = 3
                    pool.HeadOutline.Filled    = false
                    pool.HeadOutline.Transparency = alpha
                    pool.HeadOutline.Visible   = true
                else
                    pool.HeadOutline.Visible = false
                end
                pool.Head.Position  = hs
                pool.Head.Radius    = radius
                pool.Head.Color     = boxColor
                pool.Head.Thickness = 1
                pool.Head.Filled    = false
                pool.Head.Transparency = alpha
                pool.Head.Visible   = true
            else
                pool.Head.Visible = false
                pool.HeadOutline.Visible = false
            end
        end
    else
        pool.Head.Visible = false
        pool.HeadOutline.Visible = false
    end

    --// Skeleton
    if FlagBool("esp_skeleton") then
        DrawSkeleton(pool, model,
            FlagColor("esp_skeleton_color", fromRGB(255, 255, 255)), alpha, outlineOn)
    else
        for i = 1, MAX_BONES do
            pool.Skeleton[i].Visible = false
            pool.SkeletonOutline[i].Visible = false
        end
    end

    --// no arrows for NPCs
    pool.Arrow.Visible = false
    pool.ArrowOutline.Visible = false
    pool.Look.Visible = false
    pool.LookOutline.Visible = false
end

--//ANCHOR Per-loot update
local function UpdateLoot(model, pool)
    local main = model:FindFirstChild("Main")
    if not main or not main:IsA("BasePart") then
        HideLootPool(pool)
        return
    end

    local pos     = main.Position
    local camPos  = Camera.CFrame.Position
    local dist    = (pos - camPos).Magnitude
    local maxDist = FlagNumber("esp_loot_maxdist", 200)

    if dist > maxDist then
        HideLootPool(pool)
        return
    end

    --// value filter
    local minVal = FlagNumber("esp_loot_min_value", 0)
    if minVal > 0 then
        local val = GetLootValue(model.Name)
        if val < minVal then
            HideLootPool(pool)
            return
        end
    end

    local screen, depth, onScreen = WorldToScreen(pos)
    if not onScreen then
        HideLootPool(pool)
        return
    end

    local color    = FlagColor("esp_loot_color", fromRGB(255, 200, 50))
    local textSize = clamp(FlagNumber("esp_text_size", 13), 8, 24)
    local outlines = FlagBool("esp_outlines")

    pool.Name.Text         = model.Name
    pool.Name.Size         = textSize
    pool.Name.Font         = EspFont
    pool.Name.Color        = color
    pool.Name.Outline      = outlines
    pool.Name.Center       = true
    pool.Name.Transparency = 1
    pool.Name.Position     = screen
    pool.Name.Visible      = true

    pool.Distance.Text         = ("%dm"):format(round(dist))
    pool.Distance.Size         = textSize
    pool.Distance.Font         = EspFont
    pool.Distance.Color        = color
    pool.Distance.Outline      = outlines
    pool.Distance.Center       = true
    pool.Distance.Transparency = 1
    pool.Distance.Position     = Vector2new(screen.X, screen.Y + textSize + 1)
    pool.Distance.Visible      = true
end

--//ANCHOR Render loop
local function OnRender(deltaTime)
    if ESP.Unloaded then return end

    Camera = Workspace.CurrentCamera
    if not Camera then return end

    local masterOn = FlagBool("esp_enabled")

    --// Players
    for player, pool in pairs(ESP.Objects) do
        if not masterOn then
            HidePool(pool)
            HideChams(player)
        else
            local ok, err = pcall(UpdatePlayer, player, pool, deltaTime)
            if not ok then
                HidePool(pool)
            end
        end
    end

    --// NPCs
    local aiOn = masterOn and FlagBool("esp_ai_enabled")
    if aiOn then
        npc_rescan_timer = npc_rescan_timer + deltaTime
        if npc_rescan_timer >= NPC_RESCAN_INTERVAL then
            npc_rescan_timer = 0
            -- refresh NPC list
            local current = GetNPCModels()
            local alive = {}
            for _, m in ipairs(current) do
                alive[m] = true
                if not ESP.NPCObjects[m] then
                    ESP.NPCObjects[m] = CreatePool()
                end
            end
            -- remove dead NPCs
            for m, pool in pairs(ESP.NPCObjects) do
                if not alive[m] then
                    RemovePool(pool)
                    ESP.NPCObjects[m] = nil
                end
            end
        end

        for model, pool in pairs(ESP.NPCObjects) do
            if not model or not model.Parent then
                RemovePool(pool)
                ESP.NPCObjects[model] = nil
            else
                local ok = pcall(UpdateNPC, model, pool, deltaTime)
                if not ok then HidePool(pool) end
            end
        end
    else
        for _, pool in pairs(ESP.NPCObjects) do
            HidePool(pool)
        end
    end

    --// Loot
    local lootOn = masterOn and FlagBool("esp_loot_enabled")
    if lootOn then
        loot_rescan_timer = loot_rescan_timer + deltaTime
        if loot_rescan_timer >= LOOT_RESCAN_INTERVAL then
            loot_rescan_timer = 0
            local current = ScanLoots()
            local alive = {}
            for _, m in ipairs(current) do
                alive[m] = true
                if not ESP.LootPools[m] then
                    ESP.LootPools[m] = CreateLootPool()
                end
            end
            for m, pool in pairs(ESP.LootPools) do
                if not alive[m] then
                    RemoveLootPool(pool)
                    ESP.LootPools[m] = nil
                end
            end
        end

        for model, pool in pairs(ESP.LootPools) do
            if not model or not model.Parent then
                RemoveLootPool(pool)
                ESP.LootPools[model] = nil
            else
                local ok = pcall(UpdateLoot, model, pool)
                if not ok then HideLootPool(pool) end
            end
        end
    else
        for _, pool in pairs(ESP.LootPools) do
            HideLootPool(pool)
        end
    end
end

--//ANCHOR Player tracking
local function AddPlayer(player)
    if player == LocalPlayer then return end
    if ESP.Objects[player] then return end
    ESP.Objects[player] = CreatePool()
end

local function RemovePlayer(player)
    RemovePool(ESP.Objects[player])
    ESP.Objects[player] = nil
    RemoveChams(player)
end

--//ANCHOR Menu builder
local POS_4    = { "Top", "Bottom", "Left", "Right" }
local POS_BAR  = { "Left", "Right", "Top", "Bottom" }
local POS_AMMO = { "Bottom", "Top", "Left", "Right" }

function ESP:BuildMenu(window)
    local Library = self.Library
    local page    = window:Page({ Name = "esp" })

    --//ANCHOR Toggles (left)
    local main = page:Section({ Name = "Player ESP", Side = 1 })

    local function toggle(section, name, flag, default)
        return section:Toggle({ Name = name, Flag = flag, Default = default or false, Callback = function() end })
    end

    local function addColor(tog, flag, default)
        tog:Colorpicker({ Flag = flag, Default = default, Alpha = 1, Callback = function() end })
        return tog
    end

    toggle(main, "Enabled", "esp_enabled", true)
    addColor(toggle(main, "Box", "esp_box", true), "esp_box_color", fromRGB(255, 255, 255))
    main:Dropdown({ Name = "Box Type", Flag = "esp_box_type", Items = { "Full", "Corner" }, Default = "Full", Multi = false, Callback = function() end })
    addColor(toggle(main, "Name ", "esp_name", true), "esp_name_color", fromRGB(255, 255, 255))

    local health_tog = toggle(main, "Health Bar", "esp_health", true)
    addColor(health_tog, "esp_health_high", fromRGB(60, 255, 80))
    addColor(health_tog, "esp_health_low", fromRGB(255, 40, 40))

    addColor(toggle(main, "Ammo Bar", "esp_ammo", false), "esp_ammo_color", fromRGB(255, 200, 60))
    addColor(toggle(main, "Distance", "esp_distance", true), "esp_dist_color", fromRGB(200, 200, 200))
    addColor(toggle(main, "Weapon", "esp_weapon", false), "esp_weapon_color", fromRGB(180, 180, 255))
    addColor(toggle(main, "Head Circle", "esp_headcircle", false), "esp_head_color", fromRGB(255, 255, 255))
    addColor(toggle(main, "Skeleton", "esp_skeleton", false), "esp_skeleton_color", fromRGB(255, 255, 255))
    addColor(toggle(main, "Look Angle", "esp_lookangle", false), "esp_look_color", fromRGB(255, 255, 255))
    addColor(toggle(main, "Off Arrows", "esp_arrows", false), "esp_arrow_color", fromRGB(255, 80, 80))

    local chams_tog = toggle(main, "Chams", "esp_chams", false)
    addColor(chams_tog, "esp_chams_visible", fromRGB(0, 200, 255))
    addColor(chams_tog, "esp_chams_occluded", fromRGB(255, 40, 40))

    toggle(main, "Outlines", "esp_outlines", true)
    toggle(main, "Team Check", "esp_teamcheck", true)

    local team_tog = toggle(main, "Team Color", "esp_team_color", false)
    addColor(team_tog, "esp_enemy_color", fromRGB(255, 80, 80))
    addColor(team_tog, "esp_friend_color", fromRGB(80, 160, 255))

    toggle(main, "Fade In/Out", "esp_fade", true)
    toggle(main, "Inventory Value", "esp_inventory_value", false)

    --//ANCHOR Flags (left, under player ESP)
    local flags = page:Section({ Name = "Flags", Side = 1 })
    toggle(flags, "Enabled", "esp_flags", false)
    addColor(toggle(flags, "Level", "esp_flag_level", true), "esp_flag_level_color", fromRGB(200, 200, 100))
    addColor(toggle(flags, "Reloading", "esp_flag_reload", true), "esp_flag_reload_color", fromRGB(255, 100, 100))
    addColor(toggle(flags, "K/D", "esp_flag_kd", false), "esp_flag_kd_color", fromRGB(200, 200, 100))
    addColor(toggle(flags, "Hit Rate", "esp_flag_hitrate", false), "esp_flag_hitrate_color", fromRGB(200, 200, 100))
    addColor(toggle(flags, "Headshot %", "esp_flag_hsrate", false), "esp_flag_hsrate_color", fromRGB(200, 200, 100))
    addColor(toggle(flags, "Inventory", "esp_flag_invvalue", false), "esp_flag_invvalue_color", fromRGB(100, 255, 100))

    --//ANCHOR AI / NPC ESP (right)
    local ai = page:Section({ Name = "AI / NPC", Side = 2 })
    toggle(ai, "Enabled", "esp_ai_enabled", false)
    addColor(toggle(ai, "Box", "esp_ai_box", true), "esp_ai_color", fromRGB(255, 150, 50))
    ai:Dropdown({ Name = "Box Type", Flag = "esp_ai_box_type", Items = { "Full", "Corner" }, Default = "Full", Multi = false, Callback = function() end })
    addColor(toggle(ai, "Name ", "esp_ai_name", true), "esp_ai_name_color", fromRGB(255, 150, 50))
    local ai_health = toggle(ai, "Health Bar", "esp_ai_health", true)
    addColor(ai_health, "esp_ai_health_high", fromRGB(60, 255, 80))
    addColor(ai_health, "esp_ai_health_low", fromRGB(255, 40, 40))
    addColor(toggle(ai, "Distance", "esp_ai_distance", true), "esp_ai_dist_color", fromRGB(200, 200, 200))
    addColor(toggle(ai, "Weapon", "esp_ai_weapon", false), "esp_ai_weapon_color", fromRGB(180, 180, 255))

    --//ANCHOR Loot ESP (right)
    local loot = page:Section({ Name = "Loot", Side = 2 })
    addColor(toggle(loot, "Enabled", "esp_loot_enabled", false), "esp_loot_color", fromRGB(255, 200, 50))
    loot:Slider({ Name = "Max Distance", Flag = "esp_loot_maxdist", Min = 10, Max = 500, Default = 200, Decimals = 1, Suffix = "m", Callback = function() end })
    loot:Slider({ Name = "Min Value", Flag = "esp_loot_min_value", Min = 0, Max = 100000, Default = 0, Decimals = 1, Callback = function() end })

    --//ANCHOR Settings (right)
    local settings = page:Section({ Name = "Settings", Side = 2 })
    settings:Slider({ Name = "Max Distance", Flag = "esp_maxdist", Min = 50, Max = 5000, Default = 1000, Decimals = 1, Suffix = "m", Callback = function() end })
    settings:Slider({ Name = "Text Size", Flag = "esp_text_size", Min = 8, Max = 24, Default = 13, Decimals = 1, Callback = function() end })
    settings:Slider({ Name = "Fade Speed", Flag = "esp_fade_speed", Min = 1, Max = 30, Default = 8, Decimals = 1, Callback = function() end })
    settings:Slider({ Name = "Health Width", Flag = "esp_health_width", Min = 1, Max = 12, Default = 3, Decimals = 1, Callback = function() end })
    settings:Slider({ Name = "Health Speed", Flag = "esp_health_speed", Min = 1, Max = 30, Default = 10, Decimals = 1, Callback = function() end })

    --//ANCHOR Positions (right)
    local pos = page:Section({ Name = "Positions", Side = 2 })

    local function dropdown(section, name, flag, items, default)
        section:Dropdown({ Name = name, Flag = flag, Items = items, Default = default, Multi = false, Callback = function() end })
    end

    dropdown(pos, "Name Pos", "esp_name_pos", POS_4, "Top")
    dropdown(pos, "Distance Pos", "esp_dist_pos", POS_4, "Bottom")
    dropdown(pos, "Weapon Pos", "esp_weapon_pos", POS_4, "Bottom")
    dropdown(pos, "Health Pos", "esp_health_pos", POS_BAR, "Left")
    dropdown(pos, "Ammo Pos", "esp_ammo_pos", POS_AMMO, "Bottom")

    pos:Slider({ Name = "Look Length", Flag = "esp_look_length", Min = 1, Max = 20, Default = 3, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Arrow Radius", Flag = "esp_arrow_radius", Min = 50, Max = 400, Default = 150, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Arrow Size", Flag = "esp_arrow_size", Min = 8, Max = 40, Default = 18, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Chams Fill", Flag = "esp_chams_fill", Min = 0, Max = 1, Default = 0.5, Decimals = 0.01, Callback = function() end })

    return page
end

--//ANCHOR Init / Cleanup
function ESP:Init(config)
    assert(config and config.Library, "ESP:Init requires { Library = Library, Window = Window }")

    self.Library  = config.Library
    self.Unloaded = false

    if config.Window then
        self:BuildMenu(config.Window)
    end

    --// existing players
    for _, player in ipairs(Players:GetPlayers()) do
        AddPlayer(player)
    end

    --// track joins / leaves (registered with the Library so Exit cleans them)
    self.Library:Connect(Players.PlayerAdded, AddPlayer)
    self.Library:Connect(Players.PlayerRemoving, RemovePlayer)
    self.Library:Connect(RunService.RenderStepped, OnRender)

    --// initial NPC scan
    npc_container = FindNPCContainer()

    self.Loaded = true
    return self
end

function ESP:Unload()
    self.Unloaded = true

    for player in pairs(self.Objects) do
        RemovePool(self.Objects[player])
        self.Objects[player] = nil
    end
    for player in pairs(self.Chams) do
        RemoveChams(player)
    end
    for model in pairs(self.NPCObjects) do
        RemovePool(self.NPCObjects[model])
        self.NPCObjects[model] = nil
    end
    for model in pairs(self.LootPools) do
        RemoveLootPool(self.LootPools[model])
        self.LootPools[model] = nil
    end

    npc_container = nil
    item_value_cache = {}

    self.Loaded = false
end

return ESP
