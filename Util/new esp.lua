--[[
    juanita_esp.lua

    A performant, CS:GO-style Drawing ESP designed to bolt onto the juanitahaxx
    Library (Window / Page / Section / Toggle / Slider / Dropdown / Colorpicker).

    Features:
        boxes (full + corner), names, health bar, ammo bar, distance, weapon,
        team check + team colors, head circle, skeleton, look-angle line,
        off-screen arrows, occluded chams, outlines on everything (toggle),
        fade in/out, and full positioning control (move name / health / ammo /
        distance / weapon anywhere around the box).

    Usage (see esp_example.lua):
        local ESP = loadstring(game:HttpGet("...juanita_esp.lua"))()
        ESP:Init({ Library = Library, Window = Window })

    Notes:
        - Everything is read live from Library.Flags every frame, matching the
          "minimal callbacks, logic in RenderStepped" pattern.
        - Drawing objects are created ONCE per player and reused. Nothing is
          created or destroyed on the render loop.
        - Ammo is not standardized in Roblox. The reader below looks for common
          value names on the equipped Tool (Ammo / MaxAmmo, etc). Tweak
          ReadAmmo for your specific game if needed.
]]

--//ANCHOR Services & caching
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")

local LocalPlayer  = Players.LocalPlayer
local Camera       = Workspace.CurrentCamera

local PlexFont     = (Drawing and Drawing.Fonts and Drawing.Fonts.Plex) or 2 -- pixel plex font

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
    Connections = { },
    Loaded      = false,
    Unloaded    = false,
}

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
        Font = PlexFont,
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

    --// Box (full) + outline
    pool.BoxOutline = MakeSquare(false)
    pool.Box        = MakeSquare(false)

    --// Corner box: 8 segments + 8 outline segments
    pool.Corners        = { }
    pool.CornerOutlines = { }
    for i = 1, 8 do
        pool.CornerOutlines[i] = MakeLine()
        pool.Corners[i]        = MakeLine()
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
    pool.Name     = MakeText()
    pool.Distance = MakeText()
    pool.Weapon   = MakeText()

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

local function RemovePool(pool)
    if not pool then return end

    SafeRemove(pool.BoxOutline)
    SafeRemove(pool.Box)

    for i = 1, 8 do
        SafeRemove(pool.CornerOutlines[i])
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
    Hide(pool.BoxOutline) Hide(pool.Box)
    for i = 1, 8 do Hide(pool.CornerOutlines[i]) Hide(pool.Corners[i]) end
    Hide(pool.HealthOutline) Hide(pool.HealthBg) Hide(pool.HealthFill)
    Hide(pool.AmmoOutline) Hide(pool.AmmoBg) Hide(pool.AmmoFill)
    Hide(pool.Name) Hide(pool.Distance) Hide(pool.Weapon)
    Hide(pool.HeadOutline) Hide(pool.Head)
    Hide(pool.LookOutline) Hide(pool.Look)
    Hide(pool.ArrowOutline) Hide(pool.Arrow)
    for i = 1, MAX_BONES do Hide(pool.SkeletonOutline[i]) Hide(pool.Skeleton[i]) end
end

--//ANCHOR Chams (occluded chams via cloned model + dual Highlights)
--// Faithful to the OccludedChams technique: a slightly smaller welded clone
--// carries the AlwaysOnTop (through-wall) highlight, while the real character
--// carries the Occluded (line-of-sight) highlight.
local function BuildChams(player, character)
    --// drop any previous build first
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
        cloned.Transparency = 1 -- only the highlight should show, not duplicate geometry
        if cloned:IsA("MeshPart") then cloned.TextureID = "" end
        cloned.Size   = cloned.Size * 0.99 -- prevents z-fighting with the line-of-sight highlight
        cloned.Parent = model

        local weld = Instance.new("WeldConstraint") -- keep the clone flush with the real part
        weld.Part0  = cloned
        weld.Part1  = child
        weld.Parent = cloned
    end

    model.Parent = Workspace

    --// line-of-sight highlight (real char) -> shown where the player is visible
    local los = Instance.new("Highlight")
    los.DepthMode           = Enum.HighlightDepthMode.Occluded
    los.OutlineTransparency = 1
    los.Adornee             = character
    los.Parent              = character

    --// occlusion highlight (clone) -> shown through walls
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
    --// keep the clone alive (avoid rebuild churn) but disable the fills
    local set = ESP.Chams[player]
    if not set then return end
    if set.Los.Enabled then set.Los.Enabled = false end
    if set.Occ.Enabled then set.Occ.Enabled = false end
end

--//ANCHOR Ammo reader (best-effort, game-specific values)
local AMMO_NAMES     = { "Ammo", "CurrentAmmo", "Bullets", "Rounds", "Mag", "Magazine" }
local MAX_AMMO_NAMES = { "MaxAmmo", "MaxBullets", "MaxRounds", "Clip", "ClipSize", "Capacity" }

local function FindValue(tool, names)
    for _, name in ipairs(names) do
        local v = tool:FindFirstChild(name)
        if v and v:IsA("ValueBase") then
            return v.Value
        end
        local attr = tool:GetAttribute(name)
        if type(attr) == "number" then
            return attr
        end
    end
    return nil
end

local function ReadAmmo(character)
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return nil end

    local cur = FindValue(tool, AMMO_NAMES)
    local max = FindValue(tool, MAX_AMMO_NAMES)
    if not cur or not max or max <= 0 then return nil end

    return clamp(cur / max, 0, 1), cur, max
end

local function ReadWeapon(character)
    local tool = character:FindFirstChildOfClass("Tool")
    return tool and tool.Name or nil
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
    textObj.Font  = PlexFont
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

--//ANCHOR Corner box drawer (8 segments)
local function DrawCorners(pool, minX, minY, maxX, maxY, color, opacity, outlineOn)
    local w   = maxX - minX
    local h   = maxY - minY
    local len = clamp(math.min(w, h) * 0.28, 3, 14)

    local pts = {
        -- top-left
        { Vector2new(minX, minY), Vector2new(minX + len, minY) },
        { Vector2new(minX, minY), Vector2new(minX, minY + len) },
        -- top-right
        { Vector2new(maxX, minY), Vector2new(maxX - len, minY) },
        { Vector2new(maxX, minY), Vector2new(maxX, minY + len) },
        -- bottom-left
        { Vector2new(minX, maxY), Vector2new(minX + len, maxY) },
        { Vector2new(minX, maxY), Vector2new(minX, maxY - len) },
        -- bottom-right
        { Vector2new(maxX, maxY), Vector2new(maxX - len, maxY) },
        { Vector2new(maxX, maxY), Vector2new(maxX, maxY - len) },
    }

    for i = 1, 8 do
        local seg  = pts[i]
        local line = pool.Corners[i]
        local out  = pool.CornerOutlines[i]

        if outlineOn then
            out.From      = seg[1]
            out.To        = seg[2]
            out.Color     = Color3new(0, 0, 0)
            out.Thickness = 3
            out.Transparency = opacity
            out.Visible   = true
        else
            out.Visible = false
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

    --// hide any leftover lines from a previous (longer) rig
    for i = #bones + 1, MAX_BONES do
        pool.Skeleton[i].Visible        = false
        pool.SkeletonOutline[i].Visible = false
    end
end

--//ANCHOR Per-player update (the heavy lifter)
local function UpdatePlayer(player, pool, deltaTime)
    local character = player.Character
    if not character then pool.Fade = 0 HidePool(pool) HideChams(player) return end

    local hrp      = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or humanoid.Health <= 0 then
        pool.Fade = 0 HidePool(pool) HideChams(player) return
    end

    --// Team check + distance decide validity (these fade out, they don't snap)
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

    --//ANCHOR Fade (alpha = visible amount, 1 = fully visible)
    --// This runtime treats Drawing.Transparency as OPACITY (1 = visible), so we
    --// feed alpha straight into Transparency. Target is "is this a valid target",
    --// NOT "is it on screen" - otherwise off-screen arrows would fade out.
    local target = valid and 1 or 0
    if FlagBool("esp_fade") then
        local speed = clamp(FlagNumber("esp_fade_speed", 8), 1, 30)
        pool.Fade = pool.Fade + (target - pool.Fade) * clamp(deltaTime * speed, 0, 1)
        if pool.Fade ~= pool.Fade then pool.Fade = target end -- NaN guard
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

    --// Colors (team color override)
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

    --// Bounding box -> screen min/max
    local cf, size = character:GetBoundingBox()
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOn      = false
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2

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

    --// Off-screen: only the arrow applies, at full alpha (the target is valid)
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

    --//ANCHOR Box (Full or Corner via dropdown, only one at a time)
    local boxType   = FlagString("esp_box_type", "Full")
    local boxOn     = FlagBool("esp_box")
    local fullBox   = boxOn and boxType == "Full"
    local cornerBox = boxOn and boxType == "Corner"

    if fullBox then
        if outlineOn then
            pool.BoxOutline.Position  = Vector2new(minX - 1, minY - 1)
            pool.BoxOutline.Size      = Vector2new(w + 2, h + 2)
            pool.BoxOutline.Color     = Color3new(0, 0, 0)
            pool.BoxOutline.Thickness = 3
            pool.BoxOutline.Transparency = alpha
            pool.BoxOutline.Filled    = false
            pool.BoxOutline.Visible   = true
        else
            pool.BoxOutline.Visible = false
        end

        pool.Box.Position  = Vector2new(minX, minY)
        pool.Box.Size      = Vector2new(w, h)
        pool.Box.Color     = boxColor
        pool.Box.Thickness = 1
        pool.Box.Transparency = alpha
        pool.Box.Filled    = false
        pool.Box.Visible   = true
    else
        pool.Box.Visible = false
        pool.BoxOutline.Visible = false
    end

    if cornerBox then
        DrawCorners(pool, minX, minY, maxX, maxY, boxColor, alpha, outlineOn)
    else
        for i = 1, 8 do
            pool.Corners[i].Visible = false
            pool.CornerOutlines[i].Visible = false
        end
    end

    --// Layout accumulators (edges move outward as bars are placed)
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

    --//ANCHOR Health bar (Left / Right / Top / Bottom)
    if FlagBool("esp_health") then
        local realRatio = clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

        --// tween the bar toward the real health so it slides on damage/heal
        local hspeed = clamp(FlagNumber("esp_health_speed", 10), 1, 30)
        pool.HealthRatio = pool.HealthRatio + (realRatio - pool.HealthRatio) * clamp(deltaTime * hspeed, 0, 1)
        if pool.HealthRatio ~= pool.HealthRatio then pool.HealthRatio = realRatio end
        local ratio = pool.HealthRatio

        local low   = FlagColor("esp_health_low", fromRGB(255, 40, 40))
        local high  = FlagColor("esp_health_high", fromRGB(60, 255, 80))
        local hcol  = low:Lerp(high, ratio) -- color lerps with the smoothed value
        local side  = FlagString("esp_health_pos", "Left")
        local bw     = clamp(FlagNumber("esp_health_width", 3), 1, 12) -- bar thickness

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

    --//ANCHOR Ammo bar (Bottom default; Top / Left / Right supported)
    local ammoRatio = FlagBool("esp_ammo") and ReadAmmo(character) or nil
    if ammoRatio then
        local acol = FlagColor("esp_ammo_color", fromRGB(255, 200, 60))
        local side = FlagString("esp_ammo_pos", "Bottom")

        if side == "Top" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                minX, layout.topY - 4, w, 3, ammoRatio, false, acol, alpha, outlineOn)
            layout.topY = layout.topY - 6
        elseif side == "Left" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                layout.leftX - 3, minY, 3, h, ammoRatio, true, acol, alpha, outlineOn)
            layout.leftX = layout.leftX - 8
        elseif side == "Right" then
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                layout.rightX, minY, 3, h, ammoRatio, true, acol, alpha, outlineOn)
            layout.rightX = layout.rightX + 8
        else -- Bottom
            DrawBar(pool.AmmoFill, pool.AmmoBg, pool.AmmoOutline,
                minX, layout.botY, w, 3, ammoRatio, false, acol, alpha, outlineOn)
            layout.botY = layout.botY + 6
        end
    else
        pool.AmmoFill.Visible = false
        pool.AmmoBg.Visible = false
        pool.AmmoOutline.Visible = false
    end

    --//ANCHOR Texts (name / distance / weapon -> any side)
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

--//ANCHOR Render loop
local function OnRender(deltaTime)
    if ESP.Unloaded then return end

    Camera = Workspace.CurrentCamera
    if not Camera then return end

    local masterOn = FlagBool("esp_enabled")

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

    --//ANCHOR Toggles (left) - colorpickers attach straight onto the toggles
    local main = page:Section({ Name = "Toggles", Side = 1 })

    local function toggle(name, flag, default)
        return main:Toggle({ Name = name, Flag = flag, Default = default, Callback = function() end })
    end

    local function addColor(tog, flag, default)
        tog:Colorpicker({ Flag = flag, Default = default, Alpha = 1, Callback = function() end })
        return tog
    end

    toggle("Enabled", "esp_enabled", true)

    addColor(toggle("Box", "esp_box", true), "esp_box_color", fromRGB(255, 255, 255))
    main:Dropdown({ Name = "Box Type", Flag = "esp_box_type", Items = { "Full", "Corner" }, Default = "Full", Multi = false, Callback = function() end })

    addColor(toggle("Name ", "esp_name", true), "esp_name_color", fromRGB(255, 255, 255))

    --// health carries two colors (high + low), they stack on the toggle
    local healthTog = toggle("Health Bar", "esp_health", true)
    addColor(healthTog, "esp_health_high", fromRGB(60, 255, 80))
    addColor(healthTog, "esp_health_low", fromRGB(255, 40, 40))

    addColor(toggle("Ammo Bar", "esp_ammo", false), "esp_ammo_color", fromRGB(255, 200, 60))
    addColor(toggle("Distance", "esp_distance", true), "esp_dist_color", fromRGB(200, 200, 200))
    addColor(toggle("Weapon", "esp_weapon", false), "esp_weapon_color", fromRGB(180, 180, 255))
    addColor(toggle("Head Circle", "esp_headcircle", false), "esp_head_color", fromRGB(255, 255, 255))
    addColor(toggle("Skeleton", "esp_skeleton", false), "esp_skeleton_color", fromRGB(255, 255, 255))
    addColor(toggle("Look Angle", "esp_lookangle", false), "esp_look_color", fromRGB(255, 255, 255))
    addColor(toggle("Off Arrows", "esp_arrows", false), "esp_arrow_color", fromRGB(255, 80, 80))

    --// chams carries visible + occluded colors
    local chamsTog = toggle("Chams", "esp_chams", false)
    addColor(chamsTog, "esp_chams_visible", fromRGB(0, 200, 255))
    addColor(chamsTog, "esp_chams_occluded", fromRGB(255, 40, 40))

    toggle("Outlines", "esp_outlines", true)
    toggle("Team Check", "esp_teamcheck", true)

    --// team color carries enemy + friend colors
    local teamTog = toggle("Team Color", "esp_team_color", false)
    addColor(teamTog, "esp_enemy_color", fromRGB(255, 80, 80))
    addColor(teamTog, "esp_friend_color", fromRGB(80, 160, 255))

    toggle("Fade In/Out", "esp_fade", true)

    main:Slider({ Name = "Max Distance",  Flag = "esp_maxdist", Min = 50, Max = 5000, Default = 1000, Decimals = 1, Suffix = "m", Callback = function() end })
    main:Slider({ Name = "Text Size",     Flag = "esp_text_size", Min = 8, Max = 24, Default = 13, Decimals = 1, Callback = function() end })
    main:Slider({ Name = "Fade Speed",    Flag = "esp_fade_speed", Min = 1, Max = 30, Default = 8, Decimals = 1, Callback = function() end })
    main:Slider({ Name = "Health Width",  Flag = "esp_health_width", Min = 1, Max = 12, Default = 3, Decimals = 1, Callback = function() end })
    main:Slider({ Name = "Health Speed",  Flag = "esp_health_speed", Min = 1, Max = 30, Default = 10, Decimals = 1, Callback = function() end })

    --//ANCHOR Positions (right)
    local pos = page:Section({ Name = "Positions", Side = 2 })

    local function dropdown(section, name, flag, items, default)
        section:Dropdown({ Name = name, Flag = flag, Items = items, Default = default, Multi = false, Callback = function() end })
    end

    dropdown(pos, "Name Pos",     "esp_name_pos",   POS_4,    "Top")
    dropdown(pos, "Distance Pos", "esp_dist_pos",   POS_4,    "Bottom")
    dropdown(pos, "Weapon Pos",   "esp_weapon_pos", POS_4,    "Bottom")
    dropdown(pos, "Health Pos",   "esp_health_pos", POS_BAR,  "Left")
    dropdown(pos, "Ammo Pos",     "esp_ammo_pos",   POS_AMMO, "Bottom")

    pos:Slider({ Name = "Look Length", Flag = "esp_look_length", Min = 1, Max = 20, Default = 3, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Arrow Radius", Flag = "esp_arrow_radius", Min = 50, Max = 400, Default = 150, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Arrow Size",   Flag = "esp_arrow_size", Min = 8, Max = 40, Default = 18, Decimals = 1, Callback = function() end })
    pos:Slider({ Name = "Chams Fill",   Flag = "esp_chams_fill", Min = 0, Max = 1, Default = 0.5, Decimals = 0.01, Callback = function() end })

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

    self.Loaded = false
end

return ESP
