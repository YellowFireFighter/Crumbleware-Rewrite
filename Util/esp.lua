local esp = { }

local framework = loadstring(request({Url = "https://raw.githubusercontent.com/YellowFireFighter/Crumbleware-Rewrite/refs/heads/main/Util/framework.lua", Method = "Get"}).Body)()({debug = false})
local font = 2
if DrawFont ~= nil and DrawFont.Register ~= nil then 
    pcall(function()
        font = DrawFont.Register(request({Url = "https://github.com/YellowFireFighter/Crumbleware-Rewrite/raw/refs/heads/main/Util/ProggyClean.ttf", Method = "Get"}).Body)
    end)
end

local workspace = framework.services.workspace
local camera = framework.services.camera
local players = framework.services.players
local replicatedstorage = framework.services.replicatedstorage
local runservice = framework.services.runservice
local inputservice = framework.services.inputservice

esp.settings = {
    enabled = false,
    maxdis = 0,
    fade = {
        fadetime = 1,
        fadein = false,
        fadeout = false
    },
    box = {enabled = false, outline = false, mode = "corner", color = Color3.fromRGB(255,255,255)},
    healthbar = {enabled = false, lerp = false, width = 3, full_color = Color3.fromRGB(0,255,0), empty_color = Color3.fromRGB(255,0,0)},
    name = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
    distance = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
    weapon = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,0,0)},
    lookangle = {enabled = false, length = 4, thickness = 1.5, outline = false, color = Color3.fromRGB(255,255,255)},
    headcircle = {enabled = false, radius = 14, outline = false, color = Color3.fromRGB(255,255,255)},
}

local games = {
    [2862098693] = "pd",
    [4712109542] = "ls",
    [4154513353] = "bb",
    [9627238969] = "ar", 
    [9224753153] = "vs"
}

local Game = games[game.GameId] or "uni"

if Game == "pd" then
    esp.settings.pd_settings = {
        npc = {
            enabled = false,
            maxdis = 0,
            box = {enabled = false, outline = false, mode = "corner", color = Color3.fromRGB(255,0,0)},
            healthbar = {enabled = false, lerp = false, width = 3, full_color = Color3.fromRGB(0,255,0), empty_color = Color3.fromRGB(255,0,0)},
            name = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,0,0)},
            distance = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,0,0)},
            lookangle = {enabled = false, length = 4, thickness = 1.5, outline = false, color = Color3.fromRGB(255,0,0)},
            headcircle = {enabled = false, radius = 14, outline = false, color = Color3.fromRGB(255,0,0)},
        },

        item = {
            enabled = false,
            maxdis = 0,
            name = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
            distance = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
            price = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
        },

        corpse = {
            enabled = false,
            maxdis = 0,
            corpse_min = 50000,
            corpse_name = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
            corpse_distance = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
            corpse_value = {enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255)},
        }
    }
end

esp.health_lerp = { }
framework.npcs = { }
framework.items = { }

function esp:initplayer(player)
    if player and player ~= framework.player then
        framework.players[player].drawings = { }
        framework.players[player].faded = true

        framework.players[player].drawings.name = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.players[player].drawings.distance = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.players[player].drawings.weapon = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.players[player].drawings.box_outline = framework:draw("Quad", {PointA = Vector2.new(0,0,0), PointB = Vector2.new(0,0,0), PointC = Vector2.new(0,0,0), PointD = Vector2.new(0,0,0), Thickness = 2, Filled = false, Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.full_box = framework:draw("Quad", {PointA = Vector2.new(0,0,0), PointB = Vector2.new(0,0,0), PointC = Vector2.new(0,0,0), PointD = Vector2.new(0,0,0), Thickness = 1.5, Filled = false})
        framework.players[player].drawings.healthbar_b = framework:draw("Quad", {Filled = true})
        framework.players[player].drawings.healthbar_f = framework:draw("Quad", {Filled = true})
        framework.players[player].drawings.lookangle_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.lookangle = framework:draw("Line", {})
        framework.players[player].drawings.headcircle_outline = framework:draw("Circle", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.headcircle = framework:draw("Circle", {})

        framework.players[player].drawings.corner_box = {
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
        }

        task.spawn(function()
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local isR15 = player.Character:FindFirstChild("RightLowerArm") ~= nil
                framework.players[player].isR15 = isR15
            else
                repeat wait() until player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local isR15 = player.Character:FindFirstChild("RightLowerArm") ~= nil
                framework.players[player].isR15 = isR15
            end
        end)
    else
        framework:info("invalid player " .. tostring(player))
    end
end

function esp:calcbounds(character, isR15)
    local head = character:FindFirstChild("Head")
    local camera = framework.services.camera
    local padding = Vector3.new(0.5, 0, 1)

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local onscreen = false

    local headScreen, headOnScreen = camera:WorldToViewportPoint(head.Position)
    if headOnScreen and headScreen.Z > 0 then
        onscreen = true
        local headTop = camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y / 2, 0))
        minY = headTop.Y
        minX = math.min(minX, headScreen.X)
        maxX = math.max(maxX, headScreen.X)
    end

    local arms = isR15
        and {"Right Arm", "Left Arm", "RightLowerArm", "LeftLowerArm"}
        or  {"Right Arm", "Left Arm"}

    local legs = isR15
        and {"RightFoot", "LeftFoot"}
        or  {"Right Leg", "Left Leg"}

    for _, name in pairs(arms) do
        local part = character:FindFirstChild(name)
        if part then
            local s, on = camera:WorldToViewportPoint(part.Position)
            if on then
                local sideX = camera:WorldToViewportPoint(part.Position + Vector3.new(padding.X, 0, 0))
                local sideZ = camera:WorldToViewportPoint(part.Position + Vector3.new(0, 0, padding.Z))
                local screenPad = math.max(math.abs(sideX.X - s.X), math.abs(sideZ.X - s.X))
                minX = math.min(minX, s.X - screenPad)
                maxX = math.max(maxX, s.X + screenPad)
            end
        end
    end

    for _, name in pairs(legs) do
        local part = character:FindFirstChild(name)
        if part then
            local s, on = camera:WorldToViewportPoint(part.Position)
            if on then
                local bot = camera:WorldToViewportPoint(part.Position - Vector3.new(0, part.Size.Y / 2, 0))
                maxY = math.max(maxY, bot.Y)
            end
        end
    end

    if minX == math.huge or maxX == -math.huge or minY == math.huge or maxY == -math.huge then
        onscreen = false
    end

    local topleft     = Vector2.new(math.floor(minX), math.floor(minY))
    local bottomright = Vector2.new(math.floor(maxX), math.floor(maxY))
    local centerX     = math.floor(topleft.X + bottomright.X) / 2
    local boxheight   = math.floor(bottomright.Y - topleft.Y)

    return onscreen, topleft, bottomright, centerX, boxheight
end

function esp:getdata(entity)
    if framework.players[entity] then
        return framework.players[entity]
    elseif framework.npcs[entity] then
        return framework.npcs[entity]
    end
    return nil
end

function esp:setvis(entity, vis)
    local data = esp:getdata(entity)
    if not data or not data.drawings then return end

    for _, drawing in pairs(data.drawings) do
        if typeof(drawing) ~= "table" then
            drawing.Visible = vis
        end
    end
    if data.drawings.corner_box then
        for _, line in pairs(data.drawings.corner_box) do
            line.Visible = vis
        end
    end
end

function esp:fadeplayer(entity, transparency)
    local data = esp:getdata(entity)
    if not data or not data.drawings then return end

    local fadingIn = transparency == 0

    if not fadingIn then
        if data._hiding then return end
        data._hiding = true
    else
        data._hiding = false
    end

    local token = {}
    data._fadetoken = token

    local cache = {}
    for _, drawing in pairs(data.drawings) do
        if typeof(drawing) ~= "table" then
            cache[#cache + 1] = {drawing = drawing, start = drawing.Transparency}
            if fadingIn then drawing.Visible = true end
        end
    end
    if data.drawings.corner_box then
        for _, drawing in pairs(data.drawings.corner_box) do
            cache[#cache + 1] = {drawing = drawing, start = drawing.Transparency}
            if fadingIn then drawing.Visible = true end
        end
    end

    local start = os.clock()
    task.spawn(function()
        while task.wait() do
            if data._fadetoken ~= token then break end

            local t = math.clamp((os.clock() - start) / self.settings.fade.fadetime, 0, 1)
            for _, d in pairs(cache) do
                d.drawing.Transparency = d.start + (transparency - d.start) * t
            end

            if t >= 1 then
                cache = nil
                if data._fadetoken == token then
                    esp:setvis(entity, fadingIn)
                end
                break
            end
        end
    end)
end

function esp:checkvis(entity)
    local data = esp:getdata(entity)
    if not data or not data.drawings then return false end

    if data.drawings.name and data.drawings.name.Visible then return true end
    if data.drawings.full_box and data.drawings.full_box.Visible then return true end
    if data.drawings.healthbar_f and data.drawings.healthbar_f.Visible then return true end
    if data.drawings.corner_box and data.drawings.corner_box[9] and data.drawings.corner_box[9].Visible then return true end

    return false
end

function esp:gettool(player)
    player = player or framework.player

    if Game == "vs" or Game == "bb" then
        if player and player.Character then
            return player.Character:FindFirstChildWhichIsA("Tool")
        end
    elseif Game == "pd" then
        if player and player.Character then
            for i,v in pairs(player.Character:GetChildren()) do
                if v:FindFirstChild("ItemRoot") then
                    return v
                end
            end
        end
    end

    return false
end

function esp:addnpc(npc)
    if npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
        framework.npcs[npc] = {drawings = { }}
        framework.npcs[npc].faded = true

        framework.npcs[npc].drawings.name = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.npcs[npc].drawings.distance = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.npcs[npc].drawings.weapon = framework:draw("Text", {Color = Color3.fromRGB(255, 255, 255), Outline = false, Center = true, Size = 14, Font = font})
        framework.npcs[npc].drawings.box_outline = framework:draw("Quad", {PointA = Vector2.new(0,0,0), PointB = Vector2.new(0,0,0), PointC = Vector2.new(0,0,0), PointD = Vector2.new(0,0,0), Thickness = 2, Filled = false, Color = Color3.fromRGB(0,0,0)})
        framework.npcs[npc].drawings.full_box = framework:draw("Quad", {PointA = Vector2.new(0,0,0), PointB = Vector2.new(0,0,0), PointC = Vector2.new(0,0,0), PointD = Vector2.new(0,0,0), Thickness = 1.5, Filled = false})
        framework.npcs[npc].drawings.healthbar_b = framework:draw("Quad", {Filled = true})
        framework.npcs[npc].drawings.healthbar_f = framework:draw("Quad", {Filled = true})
        framework.npcs[npc].drawings.lookangle_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.npcs[npc].drawings.lookangle = framework:draw("Line", {})
        framework.npcs[npc].drawings.headcircle_outline = framework:draw("Circle", {Color = Color3.fromRGB(0,0,0)})
        framework.npcs[npc].drawings.headcircle = framework:draw("Circle", {})

        framework.npcs[npc].drawings.corner_box = {
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {Color = Color3.fromRGB(0,0,0)}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
            framework:draw("Line", {}),
        }

        npc.AncestryChanged:Connect(function(_, parent)
            if not parent or parent == nil then
                framework:_cleanupDrawings(framework.npcs[npc].drawings)
                framework.npcs[npc] = nil
            end
        end)
    end
end

function esp:additem(item) -- workspace.DroppedItems -- workspace.Containers

end

runservice.RenderStepped:Connect(function()
    for player,data in pairs(framework.players) do
        if esp.settings.enabled and not data.client and framework.player.Character and framework.player.Character:FindFirstChild("HumanoidRootPart") then
            if data.spawned and data.character:FindFirstChild("HumanoidRootPart") and data.character:FindFirstChild("Humanoid") and data.character:FindFirstChild("Head") then
                local character = data.character
                local root = data.root
                local head = character.Head
                local headpos = head.Position
                local humanoid = character.Humanoid
                local drawings = data.drawings

                local distance = framework.player.Character and framework.player.Character.HumanoidRootPart
                    and (root.Position - framework.player.Character.HumanoidRootPart.Position).Magnitude 
                    or 0

                if Game == "pd" then
                    distance = distance / 3
                end

                if esp.settings.maxdis ~= 0 and distance > esp.settings.maxdis then esp:setvis(player, false) continue end

                if humanoid.Health > 0 and esp.settings.fade.fadein and data.faded then
                    data.faded = false
                    esp:fadeplayer(player, 1)
                elseif humanoid.Health > 0 and not esp.settings.fade.fadein and data.faded then
                    data.faded = false
                elseif humanoid.Health <= 0 and not data.faded then
                    if esp.settings.fade.fadeout then
                        data.faded = true
                        esp:fadeplayer(player, 0)
                    else
                        esp:setvis(player, false)
                        data.faded = true
                    end
                end

                local onscreen, topleft, bottomright, centerX, boxheight = esp:calcbounds(character, data.isR15)
                local screenstart, onscreenstart = camera:WorldToViewportPoint(head.Position)

                local tl = topleft
                local tr = Vector2.new(bottomright.X, topleft.Y)
                local bl = Vector2.new(topleft.X, bottomright.Y)
                local br = bottomright

                if onscreen then
                    data._hiding = false
                    if esp.settings.name.enabled then
                        drawings.name.Position = Vector2.new(centerX, topleft.Y - drawings.name.TextBounds.Y - 4)
                        drawings.name.Text = player.Name
                        if drawings.name.Color ~= esp.settings.name.color then
                            drawings.name.Color = esp.settings.name.color
                        end
                        drawings.name.Outline = esp.settings.name.outline
                        drawings.name.Size = esp.settings.name.size
                        drawings.name.Visible = true
                    else
                        drawings.name.Visible = false
                    end

                    if esp.settings.distance.enabled then
                        drawings.distance.Text = tostring(math.round(distance)) .. "m"
                        if drawings.distance.Color ~= esp.settings.distance.color then
                            drawings.distance.Color = esp.settings.distance.color
                        end
                        drawings.distance.Outline = esp.settings.distance.outline
                        drawings.distance.Size = esp.settings.distance.size

                        local bounds = drawings.distance.TextBounds

                        if distance >= 150 then
                            drawings.distance.Position = Vector2.new(bottomright.X + (bounds.X / 2) + 4, ((topleft.Y + bottomright.Y) / 2) - (bounds.Y / 2))
                        else
                            drawings.distance.Position = Vector2.new(bottomright.X + (drawings.distance.TextBounds.X / 2) + 6, topleft.Y)
                        end
                        drawings.distance.Visible = true
                    else
                        drawings.distance.Visible = false
                    end

                    if esp.settings.weapon.enabled then
                        drawings.weapon.Position = Vector2.new(centerX, bottomright.Y + (boxheight * 0.005))
                        local tool = esp:gettool(player)
                        drawings.weapon.Text = tool and "[" .. tool.Name .. "]" or "[none]"
                        if drawings.weapon.Color ~= esp.settings.weapon.color then
                            drawings.weapon.Color = esp.settings.weapon.color
                        end
                        drawings.weapon.Outline = esp.settings.weapon.outline
                        drawings.weapon.Size = esp.settings.weapon.size
                        drawings.weapon.Visible = true
                    else
                        drawings.weapon.Visible = false
                    end

                    if esp.settings.healthbar.enabled then
                        local barwidth = esp.settings.healthbar.width
                        local xoffset = 3

                        local health = math.clamp(humanoid.Health, 0, 100)
                        local healthpercent = health / humanoid.MaxHealth

                        esp.health_lerp[player] = esp.health_lerp[player] or healthpercent

                        local target = healthpercent
                        local current = esp.health_lerp[player] or healthpercent

                        if math.abs(target - current) > 0.001 then
                            current = current + (target - current) * 0.015
                            esp.health_lerp[player] = current
                        end

                        drawings.healthbar_b.PointA = Vector2.new(topleft.X - xoffset - barwidth, topleft.Y - 1)
                        drawings.healthbar_b.PointB = Vector2.new(topleft.X - xoffset, topleft.Y - 1)
                        drawings.healthbar_b.PointC = Vector2.new(topleft.X - xoffset, bottomright.Y + 2)
                        drawings.healthbar_b.PointD = Vector2.new(topleft.X - xoffset - barwidth, bottomright.Y + 2)
                        drawings.healthbar_b.Color = Color3.fromRGB(0,0,0)
                        drawings.healthbar_b.Visible = true

                        local filledHeight = boxheight * current
                        drawings.healthbar_f.PointA = Vector2.new(topleft.X - xoffset - barwidth + 1, bottomright.Y - filledHeight)
                        drawings.healthbar_f.PointB = Vector2.new(topleft.X - xoffset - 1, bottomright.Y - filledHeight)
                        drawings.healthbar_f.PointC = Vector2.new(topleft.X - xoffset - 1, bottomright.Y + 1)
                        drawings.healthbar_f.PointD = Vector2.new(topleft.X - xoffset - barwidth + 1, bottomright.Y + 1)
                        if not esp.settings.healthbar.lerp then
                            drawings.healthbar_f.Color = esp.settings.healthbar.full_color
                        else
                            drawings.healthbar_f.Color = Color3.new(math.clamp(1 - math.clamp(current, 0, 1), 0, 1), math.clamp(current, 0, 1), 0)
                        end
                        drawings.healthbar_f.Visible = true
                    else
                        drawings.healthbar_b.Visible = false
                        drawings.healthbar_f.Visible = false
                    end

                    if esp.settings.headcircle.enabled then
                        if onscreenstart then
                            drawings.headcircle.Position = Vector2.new(screenstart.X, screenstart.Y)
                            drawings.headcircle.Radius = boxheight * 0.15
                            drawings.headcircle.Thickness = 1.5
                            if drawings.headcircle.Color ~= esp.settings.headcircle.color then
                                drawings.headcircle.Color = esp.settings.headcircle.color
                            end
                            drawings.headcircle.Visible = true

                            if esp.settings.headcircle.outline then
                                drawings.headcircle_outline.Position = Vector2.new(screenstart.X, screenstart.Y)
                                drawings.headcircle_outline.Radius = drawings.headcircle.Radius
                                drawings.headcircle_outline.Thickness = drawings.headcircle.Thickness * 2.5
                                drawings.headcircle_outline.Visible = true
                            else
                                drawings.headcircle_outline.Visible = false
                            end
                        else
                            drawings.headcircle.Visible = false
                            drawings.headcircle_outline.Visible = false
                        end
                    else
                        drawings.headcircle.Visible = false
                        drawings.headcircle_outline.Visible = false
                    end

                    if esp.settings.box.enabled then
                        if esp.settings.box.mode == "full" and drawings.full_box then
                            for _, line in pairs(drawings.corner_box) do
                                line.Visible = false
                            end

                            drawings.full_box.PointA = topleft
                            drawings.full_box.PointB = Vector2.new(bottomright.X, topleft.Y)
                            drawings.full_box.PointC = bottomright
                            drawings.full_box.PointD = Vector2.new(topleft.X, bottomright.Y)

                            if drawings.full_box.Color ~= esp.settings.box.color then
                                drawings.full_box.Color = esp.settings.box.color
                            end
                            drawings.full_box.Visible = true

                            if esp.settings.box.outline then
                                drawings.box_outline.PointA = topleft
                                drawings.box_outline.PointB = Vector2.new(bottomright.X, topleft.Y)
                                drawings.box_outline.PointC = bottomright
                                drawings.box_outline.PointD = Vector2.new(topleft.X, bottomright.Y)

                                drawings.box_outline.Thickness = drawings.full_box.Thickness * 2.5
                                drawings.box_outline.Visible = true
                            else
                                drawings.box_outline.Visible = false
                            end
                        elseif esp.settings.box.mode == "corner" and drawings.corner_box then
                            drawings.full_box.Visible = false
                            drawings.box_outline.Visible = false
                            local cb = drawings.corner_box

                            local line_size = math.min((br.X - tl.X) / 4, (br.Y - tl.Y) / 4)

                            cb[9].From = tl;          cb[9].To = tl + Vector2.new(line_size, 0)
                            cb[10].From = tl;         cb[10].To = tl + Vector2.new(0, line_size)
                            cb[11].From = tr;         cb[11].To = tr - Vector2.new(line_size, 0)
                            cb[12].From = tr;         cb[12].To = tr + Vector2.new(0, line_size)
                            cb[13].From = bl;         cb[13].To = bl + Vector2.new(line_size, 0)
                            cb[14].From = bl;         cb[14].To = bl - Vector2.new(0, line_size)
                            cb[15].From = br + Vector2.new(1, 0);  cb[15].To = br - Vector2.new(line_size, 0)
                            cb[16].From = br + Vector2.new(0, 1);  cb[16].To = br - Vector2.new(0, line_size)

                            if esp.settings.box.outline then
                                local ot = cb[9].Thickness * 3
                                cb[1].From = tl - Vector2.new(1, 0);   cb[1].To = tl + Vector2.new(line_size + 1, 0);  cb[1].Thickness = ot
                                cb[2].From = tl - Vector2.new(0, 1);   cb[2].To = tl + Vector2.new(0, line_size + 1);  cb[2].Thickness = ot
                                cb[3].From = tr + Vector2.new(1, 0);   cb[3].To = tr - Vector2.new(line_size + 1, 0);  cb[3].Thickness = ot
                                cb[4].From = tr - Vector2.new(0, 1);   cb[4].To = tr + Vector2.new(0, line_size + 1);  cb[4].Thickness = ot
                                cb[5].From = bl - Vector2.new(1, 0);   cb[5].To = bl + Vector2.new(line_size + 1, 0);  cb[5].Thickness = ot
                                cb[6].From = bl - Vector2.new(0, 1);   cb[6].To = bl - Vector2.new(0, line_size + 1);  cb[6].Thickness = ot
                                cb[7].From = br + Vector2.new(2, 0);   cb[7].To = br - Vector2.new(line_size + 1, 0);  cb[7].Thickness = ot
                                cb[8].From = br + Vector2.new(0, 2);   cb[8].To = br - Vector2.new(0, line_size + 1);  cb[8].Thickness = ot
                            end

                            for i = 1, 8 do
                                drawings.corner_box[i].Visible = esp.settings.box.outline
                            end
                            if drawings.corner_box[9].Color ~= esp.settings.box.color then
                                for i = 9, 16 do
                                    drawings.corner_box[i].Color = esp.settings.box.color
                                    drawings.corner_box[i].Visible = true
                                end
                            else
                                for i = 9, 16 do
                                    drawings.corner_box[i].Visible = true
                                end
                            end
                        end
                    else
                        drawings.full_box.Visible = false
                        drawings.box_outline.Visible = false

                        for _, line in pairs(drawings.corner_box) do
                            line.Visible = false
                        end
                    end

                    if esp.settings.lookangle.enabled then
                        local lookdir = head.CFrame.LookVector * esp.settings.lookangle.length

                        local endpos = headpos + lookdir

                        local screenend, onScreenend = camera:WorldToViewportPoint(endpos)

                        if onscreenstart and onScreenend then
                            drawings.lookangle.From = Vector2.new(screenstart.X, screenstart.Y)
                            drawings.lookangle.To = Vector2.new(screenend.X, screenend.Y)
                            if drawings.lookangle.Color ~= esp.settings.lookangle.color then
                                drawings.lookangle.Color = esp.settings.lookangle.color
                            end
                            drawings.lookangle.Thickness = esp.settings.lookangle.thickness
                            drawings.lookangle.Visible = true

                            if esp.settings.lookangle.outline then
                                drawings.lookangle_outline.From = Vector2.new(screenstart.X, screenstart.Y)
                                drawings.lookangle_outline.To = Vector2.new(screenend.X, screenend.Y)
                                drawings.lookangle_outline.Thickness = esp.settings.lookangle.thickness * 2.5
                                drawings.lookangle_outline.Visible = true
                            else
                                drawings.lookangle_outline.Visible = false
                            end
                        else
                            drawings.lookangle.Visible = false
                            drawings.lookangle_outline.Visible = false
                        end
                    else
                        drawings.lookangle.Visible = false
                        drawings.lookangle_outline.Visible = false
                    end
                else
                    if not data._hiding then
                        data._hiding = true
                        data.faded = true
                        esp:setvis(player, false)
                    end
                end
            else
                if not data._hiding then
                    data._hiding = true
                    data.faded = true
                    if esp.settings.fade.fadeout then
                        esp:fadeplayer(player, 1)
                    else
                        esp:setvis(player, false)
                    end
                end
            end
        else
            if esp:checkvis(player) then
                data.faded = true
                esp:setvis(player, false)
            end
        end
    end

    for npc, data in pairs(framework.npcs) do
        local ns;
        if Game == "pd" then
            ns = esp.settings.pd_settings.npc
        else
            ns = esp.settings.npc
        end

        if ns.enabled and framework.player.Character then
            if ns and not ns.enabled then
                esp:setvis(npc, false)
                continue
            end

            if npc and npc.Parent and npc:FindFirstChild("HumanoidRootPart") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("Head") then
                local head = npc.Head
                local root = npc.HumanoidRootPart
                local humanoid = npc.Humanoid
                local drawings = data.drawings

                local distance = (root.Position - framework.player.Character.HumanoidRootPart.Position).Magnitude
                if Game == "pd" then distance = distance / 3 end

                if ns.maxdis ~= 0 and distance > ns.maxdis then
                    esp:setvis(npc, false)
                    continue
                end

                if humanoid.Health > 0 and esp.settings.fade.fadein and data.faded then
                    data.faded = false
                    esp:fadeplayer(npc, 1)
                elseif humanoid.Health > 0 and not esp.settings.fade.fadein and data.faded then
                    data.faded = false
                elseif humanoid.Health <= 0 and not data.faded then
                    data.faded = true
                    if esp.settings.fade.fadeout then
                        esp:fadeplayer(npc, 0)
                    else
                        esp:setvis(npc, false)
                    end
                end

                local onscreen, topleft, bottomright, centerX, boxheight = esp:calcbounds(npc, true)
                local screenstart, onscreenstart = camera:WorldToViewportPoint(head.Position)

                local tl = topleft
                local tr = Vector2.new(bottomright.X, topleft.Y)
                local bl = Vector2.new(topleft.X, bottomright.Y)
                local br = bottomright

                if onscreen then
                    data._hiding = false
                    if ns.name.enabled then
                        drawings.name.Position = Vector2.new(centerX, topleft.Y - drawings.name.TextBounds.Y - 4)
                        drawings.name.Text = npc.Name
                        drawings.name.Color = ns.name.color
                        drawings.name.Outline = ns.name.outline
                        drawings.name.Size = ns.name.size
                        drawings.name.Visible = true
                    else drawings.name.Visible = false end

                    if ns.distance.enabled then
                        drawings.distance.Text = tostring(math.round(distance)) .. "m"
                        drawings.distance.Color = ns.distance.color
                        drawings.distance.Outline = ns.distance.outline
                        drawings.distance.Size = ns.distance.size
                        local bounds = drawings.distance.TextBounds
                        if distance >= 150 then
                            drawings.distance.Position = Vector2.new(bottomright.X + (bounds.X / 2) + 4, ((topleft.Y + bottomright.Y) / 2) - (bounds.Y / 2))
                        else
                            drawings.distance.Position = Vector2.new(bottomright.X + (bounds.X / 2) + 6, topleft.Y)
                        end
                        drawings.distance.Visible = true
                    else drawings.distance.Visible = false end

                    drawings.weapon.Visible = false

                    if ns.healthbar.enabled then
                        local barwidth = ns.healthbar.width
                        local xoffset = 3
                        local healthpercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

                        drawings.healthbar_b.PointA = Vector2.new(topleft.X - xoffset - barwidth, topleft.Y - 1)
                        drawings.healthbar_b.PointB = Vector2.new(topleft.X - xoffset, topleft.Y - 1)
                        drawings.healthbar_b.PointC = Vector2.new(topleft.X - xoffset, bottomright.Y + 2)
                        drawings.healthbar_b.PointD = Vector2.new(topleft.X - xoffset - barwidth, bottomright.Y + 2)
                        drawings.healthbar_b.Color = Color3.fromRGB(0, 0, 0)
                        drawings.healthbar_b.Visible = true

                        local filledHeight = boxheight * healthpercent
                        drawings.healthbar_f.PointA = Vector2.new(topleft.X - xoffset - barwidth + 1, bottomright.Y - filledHeight)
                        drawings.healthbar_f.PointB = Vector2.new(topleft.X - xoffset - 1, bottomright.Y - filledHeight)
                        drawings.healthbar_f.PointC = Vector2.new(topleft.X - xoffset - 1, bottomright.Y + 1)
                        drawings.healthbar_f.PointD = Vector2.new(topleft.X - xoffset - barwidth + 1, bottomright.Y + 1)
                        drawings.healthbar_f.Color = ns.healthbar.lerp
                            and Color3.new(math.clamp(1 - healthpercent, 0, 1), math.clamp(healthpercent, 0, 1), 0)
                            or ns.healthbar.full_color
                        drawings.healthbar_f.Visible = true
                    else
                        drawings.healthbar_b.Visible = false
                        drawings.healthbar_f.Visible = false
                    end

                    if ns.headcircle.enabled and onscreenstart then
                        drawings.headcircle.Position = Vector2.new(screenstart.X, screenstart.Y)
                        drawings.headcircle.Radius = boxheight * 0.15
                        drawings.headcircle.Thickness = 1.5
                        drawings.headcircle.Color = ns.headcircle.color
                        drawings.headcircle.Visible = true
                        if ns.headcircle.outline then
                            drawings.headcircle_outline.Position = Vector2.new(screenstart.X, screenstart.Y)
                            drawings.headcircle_outline.Radius = drawings.headcircle.Radius
                            drawings.headcircle_outline.Thickness = drawings.headcircle.Thickness * 2.5
                            drawings.headcircle_outline.Visible = true
                        else drawings.headcircle_outline.Visible = false end
                    else
                        drawings.headcircle.Visible = false
                        drawings.headcircle_outline.Visible = false
                    end

                    if ns.box.enabled then
                        if ns.box.mode == "full" then
                            for _, line in pairs(drawings.corner_box) do line.Visible = false end
                            drawings.full_box.PointA = topleft
                            drawings.full_box.PointB = Vector2.new(bottomright.X, topleft.Y)
                            drawings.full_box.PointC = bottomright
                            drawings.full_box.PointD = Vector2.new(topleft.X, bottomright.Y)
                            drawings.full_box.Color = ns.box.color
                            drawings.full_box.Visible = true
                            if ns.box.outline then
                                drawings.box_outline.PointA = topleft
                                drawings.box_outline.PointB = Vector2.new(bottomright.X, topleft.Y)
                                drawings.box_outline.PointC = bottomright
                                drawings.box_outline.PointD = Vector2.new(topleft.X, bottomright.Y)
                                drawings.box_outline.Thickness = drawings.full_box.Thickness * 2.5
                                drawings.box_outline.Visible = true
                            else drawings.box_outline.Visible = false end

                        elseif ns.box.mode == "corner" then
                            drawings.full_box.Visible = false
                            drawings.box_outline.Visible = false
                            local cb = drawings.corner_box
                            local line_size = math.min((br.X - tl.X) / 4, (br.Y - tl.Y) / 4)

                            cb[9].From  = tl;                      cb[9].To  = tl + Vector2.new(line_size, 0)
                            cb[10].From = tl;                      cb[10].To = tl + Vector2.new(0, line_size)
                            cb[11].From = tr;                      cb[11].To = tr - Vector2.new(line_size, 0)
                            cb[12].From = tr;                      cb[12].To = tr + Vector2.new(0, line_size)
                            cb[13].From = bl;                      cb[13].To = bl + Vector2.new(line_size, 0)
                            cb[14].From = bl;                      cb[14].To = bl - Vector2.new(0, line_size)
                            cb[15].From = br + Vector2.new(1, 0); cb[15].To = br - Vector2.new(line_size, 0)
                            cb[16].From = br + Vector2.new(0, 1); cb[16].To = br - Vector2.new(0, line_size)

                            for i = 9, 16 do
                                cb[i].Color = ns.box.color
                                cb[i].Visible = true
                            end

                            if ns.box.outline then
                                local ot = cb[9].Thickness * 3
                                cb[1].From = tl - Vector2.new(1,0);  cb[1].To = tl + Vector2.new(line_size+1,0); cb[1].Thickness = ot
                                cb[2].From = tl - Vector2.new(0,1);  cb[2].To = tl + Vector2.new(0,line_size+1); cb[2].Thickness = ot
                                cb[3].From = tr + Vector2.new(1,0);  cb[3].To = tr - Vector2.new(line_size+1,0); cb[3].Thickness = ot
                                cb[4].From = tr - Vector2.new(0,1);  cb[4].To = tr + Vector2.new(0,line_size+1); cb[4].Thickness = ot
                                cb[5].From = bl - Vector2.new(1,0);  cb[5].To = bl + Vector2.new(line_size+1,0); cb[5].Thickness = ot
                                cb[6].From = bl - Vector2.new(0,1);  cb[6].To = bl - Vector2.new(0,line_size+1); cb[6].Thickness = ot
                                cb[7].From = br + Vector2.new(2,0);  cb[7].To = br - Vector2.new(line_size+1,0); cb[7].Thickness = ot
                                cb[8].From = br + Vector2.new(0,2);  cb[8].To = br - Vector2.new(0,line_size+1); cb[8].Thickness = ot
                            end
                            for i = 1, 8 do cb[i].Visible = ns.box.outline end
                        end
                    else
                        drawings.full_box.Visible = false
                        drawings.box_outline.Visible = false
                        for _, line in pairs(drawings.corner_box) do line.Visible = false end
                    end

                    if ns.lookangle.enabled then
                        local screenend, onScreenend = camera:WorldToViewportPoint(head.Position + head.CFrame.LookVector * ns.lookangle.length)
                        if onscreenstart and onScreenend then
                            drawings.lookangle.From = Vector2.new(screenstart.X, screenstart.Y)
                            drawings.lookangle.To = Vector2.new(screenend.X, screenend.Y)
                            drawings.lookangle.Color = ns.lookangle.color
                            drawings.lookangle.Thickness = ns.lookangle.thickness
                            drawings.lookangle.Visible = true
                            if ns.lookangle.outline then
                                drawings.lookangle_outline.From = Vector2.new(screenstart.X, screenstart.Y)
                                drawings.lookangle_outline.To = Vector2.new(screenend.X, screenend.Y)
                                drawings.lookangle_outline.Thickness = ns.lookangle.thickness * 2.5
                                drawings.lookangle_outline.Visible = true
                            else drawings.lookangle_outline.Visible = false end
                        else
                            drawings.lookangle.Visible = false
                            drawings.lookangle_outline.Visible = false
                        end
                    else
                        drawings.lookangle.Visible = false
                        drawings.lookangle_outline.Visible = false
                    end
                else
                    if not data._hiding then
                        data._hiding = true
                        data.faded = true
                        esp:setvis(npc, false)
                    end
                end
            else
                if not data._hiding then
                    data._hiding = true
                    data.faded = true
                    if esp.settings.fade.fadeout then
                        esp:fadeplayer(player, 1)
                    else
                        esp:setvis(player, false)
                    end
                end
            end
        else
            if esp:checkvis(npc) then
                esp:setvis(npc, false)
            end
        end
    end
end)

table.insert(framework.connec_funcs["playeradded"], function(player)
    esp:initplayer(player)
end)

table.insert(framework.connec_funcs["playerremoving"], function(player)
    if framework.players[player] then
        if esp.settings.fade.fadeout then
            esp:fadeplayer(player, 0)
        else
            esp:setvis(player, false)
        end
    end
end)

for _,player in pairs(players:GetChildren()) do
    esp:initplayer(player)
end

if Game == "pd" then
    workspace.AiZones.DescendantAdded:Connect(function(child)
        if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") and child:FindFirstChild("Humanoid") and child:FindFirstChild("Head") then
            esp:addnpc(child)
        end
    end)

    for i,v in pairs(workspace.AiZones:GetDescendants()) do
        if v:IsA("Model") and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v:FindFirstChild("Head") then
            esp:addnpc(v)
        end
    end
end

return esp, framework
