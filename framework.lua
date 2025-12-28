local framework = {}

framework.debug = true

framework.player = nil
framework.players = {}
framework.instances = {}
framework.connections = {}
framework.connec_funcs = {}
framework.services = {}
framework.gc = {}

local workspace = cloneref(game:GetService("Workspace"))
local players = cloneref(game:GetService("Players"))
local replicatedstorage = cloneref(game:GetService("ReplicatedStorage"))
local runservice = cloneref(game:GetService("RunService"))
local inputservice = cloneref(game:GetService("UserInputService"))
local camera = workspace.CurrentCamera

framework.services.workspace = workspace
framework.services.players = players
framework.services.replicatedstorage = replicatedstorage
framework.services.runservice = runservice
framework.services.inputservice = inputservice
framework.services.camera = camera

function framework:info(info)
    if self.debug then
        warn([[debug ->]], tostring(info))
    end
end

function framework:draw(type, props)
    local drawing = nil
    local suc, err = pcall(function()
        drawing = Drawing.new(type)
    end)

    if suc then
        for prop,val in pairs(props) do
            local suc, err = pcall(function()
                drawing[prop] = val
            end)

            if not suc then
                self:info("draw prop failed " .. err)
            end
        end

    else
        self:info("draw failed " .. err)
    end

    return drawing
end

function framework:instance(type, props)
    local instance = nil
    local suc, err = pcall(function()
        instance = Instance.new(type)
    end)

    if suc then
        for prop,val in pairs(props) do
            local suc, err = pcall(function()
                instance[prop] = val
            end)

            if not suc then
                self:info("instance prop failed " .. err)
            end
        end

        self.instances[#self.instances + 1] = instance
    else
        self:info("instance failed " .. err)
    end

    return instance
end

function framework:addplayer(player)
    if not self.players[player] then
        self.players[player] = {
            name = player.Name,
            character = nil,
            root = nil,
            spawned = false,
            client = player == self.player,
            drawings = { },
            faded = false
        }

        self.connections[player.Name .. "a"] = player.CharacterAdded:Connect(function()
            self:updateplayer(player)

            repeat wait() until not player.Character or player.Character and not player.Character:FindFirstChild("Head")

            self:updateplayer(player)
        end)

        self.connections[player.Name .. "r"] = player.CharacterRemoving:Connect(function()
            task.wait(1)
            self:updateplayer(player)
        end)

        self:info("add player " .. player.Name)

        task.spawn(function()
            repeat wait() until player.Character and player.Character:FindFirstChild("Humanoid") and player.Character:FindFirstChild("HumanoidRootPart")
            self:updateplayer(player)
        end)
    else
        self:info("add player failed " .. player.Name)
    end
end

function framework:_cleanupDrawings(tbl)
    for k, v in pairs(tbl) do
        if typeof(v) == "table" then
            self:_cleanupDrawings(v)
            tbl[k] = nil
        elseif typeof(v) == "userdata" then
            pcall(function()
                v:Remove()
            end)
            tbl[k] = nil
        end
    end
end

function framework:removeplayer(player)
    if self.players[player] then
        if self.connections[player.Name .. "a"] then
            self.connections[player.Name .. "a"]:Disconnect()
            self.connections[player.Name .. "a"] = nil
        end

        if self.connections[player.Name .. "r"] then
            self.connections[player.Name .. "r"]:Disconnect()
            self.connections[player.Name .. "r"] = nil
        end

        self:_cleanupDrawings(self.players[player].drawings)

        self.players[player] = nil

        self:info("remove player " .. player.Name)
    else
        self:info("remove player failed " .. player.Name)
    end
end

function framework:updateplayer(player)
    if self.players[player] then
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            self.players[player].character = player.Character
            self.players[player].root = player.Character.HumanoidRootPart
            self.players[player].spawned = true
        else
            self.players[player].character = nil
            self.players[player].root = nil
            self.players[player].spawned = false
        end

        self:info("update player " .. player.Name)
    else
        self:info("update player failed " .. player.Name)
    end
end

function framework:gcfinder(type, data)
    for i,v in pairs(getgc(true)) do
        if typeof(v) == type then
            if type == "function" then
                local func_name = debug.info(v, "n")

                if func_name == data then
                    framework.gc[func_name] = v
                    return framework.gc[func_name]
                end
            elseif type == "table" then
                local raw = rawget(v, data)

                if raw then
                    framework.gc[data] = v
                    return framework.gc[data]
                end
            end
        end
    end
end

function framework:init()
    for _,player in pairs(players:GetChildren()) do
        self:addplayer(player)
    end
end

function framework:unload()
    for index,connection in pairs(self.connections) do
        connection:Disconnect()
        self.connections[index] = nil
    end

    for index,instance in pairs(self.instances) do
        local suc, err = pcall(function()
            instance:Destroy()
        end)

        if not suc then
            self:info("failed remove instance " .. instance)
        end
    end

    self:info("unloaded framework")
end

framework.player = players.LocalPlayer

framework.connec_funcs["playeradded"] = { }
framework.connections["playeradded"] = players.PlayerAdded:Connect(function(player)
    framework:addplayer(player)

    for index,func in pairs(framework.connec_funcs["playeradded"]) do
        if typeof(func) == "function" then
            func(player)
        end
    end
end)

framework.connec_funcs["playerremoving"] = { }
framework.connections["playerremoving"] = players.PlayerRemoving:Connect(function(player)
    framework:removeplayer(player)

    for index,func in pairs(framework.connec_funcs["playerremoving"]) do
        if typeof(func) == "function" then
            func(player)
        end
    end
end)

framework:init()

return framework
