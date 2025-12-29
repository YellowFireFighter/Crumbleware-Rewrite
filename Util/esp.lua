local esp = { }

local framework = loadstring(request({Url = "https://raw.githubusercontent.com/YellowFireFighter/Crumbleware-Rewrite/refs/heads/main/Util/framework.lua", Method = "Get"}).Body)()
local font = Drawing.Fonts.new(request({Url = "https://github.com/YellowFireFighter/Crumbleware-Rewrite/raw/refs/heads/main/Util/font.ttf", Method = "Get"}).Body)

local workspace = framework.services.workspace
local camera = framework.services.camera
local players = framework.services.players
local replicatedstorage = framework.services.replicatedstorage
local runservice = framework.services.runservice
local inputservice = framework.services.inputservice

esp.settings = {
    enabled = false,
    maxdis = 0,
    includeai = false, -- not added
    fade = {
        fadetime = 1,
        fadein = false,
        fadeout = false
    },
    box = {enabled = false, outline = false, mode = "full", color = Color3.fromRGB(255,255,255)},
    healthbar = {enabled = false, lerp = false, width = 3, full_color = Color3.fromRGB(0,255,0), empty_color = Color3.fromRGB(255,0,0)},
    name = {enabled = false, size = 12, outline = false, color = Color3.fromRGB(255,255,255)},
    distance = {enabled = false, size = 12, outline = false, color = Color3.fromRGB(255,255,255)},
    weapon = {enabled = false, size = 12, outline = false, color = Color3.fromRGB(255,0,0)},
    lookangle = {enabled = false, length = 4, thickness = 1.5, outline = false, color = Color3.fromRGB(255,255,255)},
    headcircle = {enabled = false, radius = 14, outline = false, color = Color3.fromRGB(255,255,255)}
}

esp.health_lerp = { }

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

        framework.players[player].drawings.corner_box = { }

        framework.players[player].drawings.corner_box.tl1_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.corner_box.tl2_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})

        framework.players[player].drawings.corner_box.tr1_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.corner_box.tr2_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})

        framework.players[player].drawings.corner_box.bl1_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.corner_box.bl2_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})

        framework.players[player].drawings.corner_box.br1_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})
        framework.players[player].drawings.corner_box.br2_outline = framework:draw("Line", {Color = Color3.fromRGB(0,0,0)})

        framework.players[player].drawings.corner_box.tl1 = framework:draw("Line", {})
        framework.players[player].drawings.corner_box.tl2 = framework:draw("Line", {})

        framework.players[player].drawings.corner_box.tr1 = framework:draw("Line", {})
        framework.players[player].drawings.corner_box.tr2 = framework:draw("Line", {})

        framework.players[player].drawings.corner_box.bl1 = framework:draw("Line", {})
        framework.players[player].drawings.corner_box.bl2 = framework:draw("Line", {})

        framework.players[player].drawings.corner_box.br1 = framework:draw("Line", {})
        framework.players[player].drawings.corner_box.br2 = framework:draw("Line", {})
    else
        framework:info("invalid player " .. tostring(player))
    end
end

function esp:fadeplayer(player, transparency)
    if player and framework.players[player].drawings then
        local cache = { }
        for _,drawing in pairs(framework.players[player].drawings) do
            if typeof(drawing) ~= "table" then
                cache[#cache + 1] = {drawing = drawing, start = 1 - transparency}
            end
        end

        if framework.players[player].drawings.corner_box then
            for _,drawing in pairs(framework.players[player].drawings.corner_box) do
                cache[#cache + 1] = {drawing = drawing, start = 1 - transparency}
            end
        end

        local start = os.clock()
        task.spawn(function()
            for _,data in pairs(cache) do
                local drawing = data.drawing
                drawing.Transparency = 1 - transparency
            end

            while task.wait() do
                local t = (os.clock() - start) / self.settings.fade.fadetime
                t = math.clamp(t, 0, 1)
                
                for _,data in pairs(cache) do
                    local drawing = data.drawing
                    drawing.Transparency = data.start + (transparency - data.start) * t
                end

                if t >= self.settings.fade.fadetime then
                    cache = nil
                    esp:setvis(player, transparency == 1)
                    break
                end
            end
        end)
    else
        framework:info("invalid player " .. player)
    end
end

function esp:setvis(player, vis)
    if player and framework.players[player] then
        local cache = { }
        for _,drawing in pairs(framework.players[player].drawings) do
            if typeof(drawing) ~= "table" then
                cache[#cache + 1] = drawing
            end
        end

        if framework.players[player].drawings.corner_box then
            for _,drawing in pairs(framework.players[player].drawings.corner_box) do
                cache[#cache + 1] = drawing
            end
        end

        for i,v in pairs(cache) do
            v.Visible = vis
        end

        cache = nil
    end
end

runservice.RenderStepped:Connect(function()
    for player,data in pairs(framework.players) do
        if esp.settings.enabled and not data.client then
            if data.spawned and data.character:FindFirstChild("Humanoid") and data.character:FindFirstChild("Head") then
                local character = data.character
                local root = data.root
                local head = character.Head
                local headpos = head.Position
                local humanoid = character.Humanoid
                local drawings = data.drawings

                local distance = framework.player.Character and framework.player.Character:FindFirstChild("HumanoidRootPart") 
                    and (root.Position - framework.player.Character.HumanoidRootPart.Position).Magnitude 
                    or 0
                distance = distance / 3

                if humanoid.Health > 0 and esp.settings.fade.fadein and data.faded then
                    data.faded = false
                    esp:fadeplayer(player, 1)
                elseif humanoid.Health <= 0 and esp.settings.fade.fadeout and not data.faded then
                    data.faded = true
                    esp:fadeplayer(player, 0)
                end

                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                local onscreen = false

                local padding = Vector3.new(0.5, 0, 1)

                for _, part in pairs(character:GetChildren()) do
                    if part.Name == "Head" or part.Name == "RightFoot" or part.Name == "LeftFoot" or part.Name == "RightLeg" or part.Name == "LeftLeg" then
                        local corners = {
                            part.Position + Vector3.new(padding.X, 0, padding.Z),
                            part.Position + Vector3.new(-padding.X, 0, padding.Z),
                            part.Position + Vector3.new(padding.X, 0, -padding.Z),
                            part.Position + Vector3.new(-padding.X, 0, -padding.Z),
                            part.Position + Vector3.new(padding.X, part.Size.Y, padding.Z),
                            part.Position + Vector3.new(-padding.X, part.Size.Y, padding.Z),
                            part.Position + Vector3.new(padding.X, part.Size.Y, -padding.Z),
                            part.Position + Vector3.new(-padding.X, part.Size.Y, -padding.Z),
                        }

                        for _, corner in pairs(corners) do
                            local screenPos, onScreen = camera:WorldToViewportPoint(corner)
                            if onScreen then
                                onscreen = true
                                minX = math.min(minX, screenPos.X)
                                minY = math.min(minY, screenPos.Y)
                                maxX = math.max(maxX, screenPos.X)
                                maxY = math.max(maxY, screenPos.Y)
                            end
                        end
                    end
                end

                local topleft = Vector2.new(math.floor(minX), math.floor(minY))
                local bottomright = Vector2.new(math.floor(maxX), math.floor(maxY))
                local centerX = math.floor(topleft.X + bottomright.X) / 2
                local boxheight = math.floor(bottomright.Y - topleft.Y)

                local screenstart, onscreenstart = camera:WorldToViewportPoint(headpos)

                if onscreen and (esp.settings.maxdis == 0 or distance <= esp.settings.maxdis) then
                    if esp.settings.name.enabled then
                        drawings.name.Position = Vector2.new(centerX, topleft.Y - drawings.name.TextBounds.Y - 4)
                        drawings.name.Text = player.Name
                        drawings.name.Color = esp.settings.name.color
                        drawings.name.Outline = esp.settings.name.outline
                        drawings.name.Size = esp.settings.name.size
                        drawings.name.Visible = true
                    else
                        drawings.name.Visible = false
                    end

                    if esp.settings.distance.enabled then
                        drawings.distance.Text = tostring(math.round(distance)) .. "m"
                        drawings.distance.Color = esp.settings.distance.color
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
                        drawings.weapon.Text = "[none]"
                        drawings.weapon.Color = esp.settings.weapon.color
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
                        local current = esp.health_lerp[player]

                        current = current + (target - current) * 0.015

                        esp.health_lerp[player] = current

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
                            drawings.headcircle.Color = esp.settings.headcircle.color
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

                            drawings.full_box.Color = esp.settings.box.color
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

                            local tl = Vector2.new(math.floor(minX), math.floor(minY))
                            local tr = Vector2.new(math.floor(maxX), math.floor(minY))
                            local bl = Vector2.new(math.floor(minX), math.floor(maxY))
                            local br = Vector2.new(math.floor(maxX), math.floor(maxY))

                            local line_size = math.min((br.X - tl.X) / 4, (br.Y - tl.Y) / 4)

                            drawings.corner_box.tl1.From = tl
                            drawings.corner_box.tl1.To = tl + Vector2.new(line_size, 0)
                            drawings.corner_box.tl2.From = tl
                            drawings.corner_box.tl2.To = tl + Vector2.new(0, line_size)

                            drawings.corner_box.tr1.From = tr
                            drawings.corner_box.tr1.To = tr - Vector2.new(line_size, 0)
                            drawings.corner_box.tr2.From = tr
                            drawings.corner_box.tr2.To = tr + Vector2.new(0, line_size)

                            drawings.corner_box.bl1.From = bl
                            drawings.corner_box.bl1.To = bl + Vector2.new(line_size, 0)
                            drawings.corner_box.bl2.From = bl
                            drawings.corner_box.bl2.To = bl - Vector2.new(0, line_size)

                            drawings.corner_box.br1.From = br + Vector2.new(1, 0)
                            drawings.corner_box.br1.To = br - Vector2.new(line_size, 0)
                            drawings.corner_box.br2.From = br + Vector2.new(0, 1)
                            drawings.corner_box.br2.To = br - Vector2.new(0, line_size)

                            if esp.settings.box.outline then
                                drawings.corner_box.tl1_outline.From = tl - Vector2.new(1, 0)
                                drawings.corner_box.tl1_outline.To = tl + Vector2.new(line_size + 1, 0)
                                drawings.corner_box.tl1_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                                drawings.corner_box.tl2_outline.From = tl - Vector2.new(0, 1)
                                drawings.corner_box.tl2_outline.To = tl + Vector2.new(0, line_size + 1)
                                drawings.corner_box.tl2_outline.Thickness = drawings.corner_box.br2.Thickness * 3

                                drawings.corner_box.tr1_outline.From = tr + Vector2.new(1, 0)
                                drawings.corner_box.tr1_outline.To = tr - Vector2.new(line_size + 1, 0)
                                drawings.corner_box.tr1_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                                drawings.corner_box.tr2_outline.From = tr - Vector2.new(0, 1)
                                drawings.corner_box.tr2_outline.To = tr + Vector2.new(0, line_size + 1)
                                drawings.corner_box.tr2_outline.Thickness = drawings.corner_box.br2.Thickness * 3

                                drawings.corner_box.bl1_outline.From = bl - Vector2.new(1, 0)
                                drawings.corner_box.bl1_outline.To = bl + Vector2.new(line_size + 1, 0)
                                drawings.corner_box.bl1_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                                drawings.corner_box.bl2_outline.From = bl - Vector2.new(0, 1)
                                drawings.corner_box.bl2_outline.To = bl - Vector2.new(0, line_size + 1)
                                drawings.corner_box.bl2_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                                
                                drawings.corner_box.br1_outline.From = br + Vector2.new(2, 0)
                                drawings.corner_box.br1_outline.To = br - Vector2.new(line_size + 1, 0)
                                drawings.corner_box.br1_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                                drawings.corner_box.br2_outline.From = br + Vector2.new(0, 2)
                                drawings.corner_box.br2_outline.To = br - Vector2.new(0, line_size + 1)
                                drawings.corner_box.br2_outline.Thickness = drawings.corner_box.br2.Thickness * 3
                            end

                            for name, line in pairs(drawings.corner_box) do
                                if not string.find(name, "_outline") then
                                    line.Color = esp.settings.box.color
                                    line.Visible = true
                                else
                                    line.Visible = esp.settings.box.outline
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
                        local lookdir = root.CFrame.LookVector * esp.settings.lookangle.length

                        local endpos = headpos + lookdir

                        local screenend, onScreenend = camera:WorldToViewportPoint(endpos)

                        if onscreenstart and onScreenend then
                            drawings.lookangle.From = Vector2.new(screenstart.X, screenstart.Y)
                            drawings.lookangle.To = Vector2.new(screenend.X, screenend.Y)
                            drawings.lookangle.Color = esp.settings.lookangle.color
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
                    esp:setvis(player, false)
                end
            else
                if esp.settings.fade.fadeout and not data.faded then
                    data.faded = true
                    esp:fadeplayer(player, 0)
                end
            end
        else
            esp:setvis(player, false)
        end
    end
end)

table.insert(framework.connec_funcs["playeradded"], function(player)
    esp:initplayer(player)
end)

for _,player in pairs(players:GetChildren()) do
    esp:initplayer(player)
end

return esp, framework
