local notifications = {}

local camera = workspace.CurrentCamera
local vp = camera.ViewportSize
local run_service = game:GetService("RunService")

local font = 2
if DrawFont and DrawFont.Register then
    font = DrawFont.Register(request({Url = "https://github.com/YellowFireFighter/Crumbleware-Rewrite/raw/refs/heads/main/Util/ProggyClean.ttf", Method = "Get"}).Body)
end

local alerts = {}
local SLIDE_START, FADE_SPEED, SLIDE_SPEED = -80, 3, 8

local function refresh_positions()
    local y = 60
    for _, e in ipairs(alerts) do
        if e.state ~= "out" then
            e.target_y = y
            y = y + (e.report_text and 52 or 30)
        end
    end
end

run_service.Heartbeat:Connect(function(dt)
    for _, e in ipairs(alerts) do
        e.current_y = e.current_y + (e.target_y - e.current_y) * math.min(dt * SLIDE_SPEED, 1)
        e.name_text.Position = Vector2.new(vp.X / 2, e.current_y)
        if e.report_text then e.report_text.Position = Vector2.new(vp.X / 2, e.current_y + 26) end

        if e.state == "in" then
            e.alpha = math.min(e.alpha + dt * FADE_SPEED, 1)
            e.name_text.Visible = true
            if e.report_text then e.report_text.Visible = true end
            e.name_text.Transparency = 1 - e.alpha
            if e.report_text then e.report_text.Transparency = 1 - e.alpha end
            if e.alpha >= 1 then e.state = "idle" end

        elseif e.state == "idle" then
            local blink = 0.4 + ((math.sin(tick() * 4) + 1) / 2) * 0.6
            e.name_text.Transparency = 1 - blink
            if e.report_text then e.report_text.Transparency = 1 - blink end

        elseif e.state == "out" then
            e.alpha = math.max(e.alpha - dt * FADE_SPEED, 0)
            e.name_text.Transparency = 1 - e.alpha
            if e.report_text then e.report_text.Transparency = 1 - e.alpha end
            if e.alpha <= 0 then
                e.name_text.Visible = false
                if e.report_text then e.report_text.Visible = false end
                e.done = true
            end
        end
    end
end)

local function make_text(size, color)
    local t = Drawing.new("Text")
    t.Font, t.Size, t.Color = font, size, color
    t.Outline, t.OutlineColor = true, Color3.fromRGB(0, 0, 0)
    t.Center, t.Visible, t.Transparency = true, false, 1
    return t
end

function notifications:alert(text, color, reports)
    local e = { state = "in", alpha = 0, current_y = SLIDE_START, target_y = 14, done = false }
    e.name_text = make_text(25, color or Color3.fromRGB(255, 50, 50))
    e.name_text.Text = "⚠ " .. text .. " ⚠"
    if reports then
        e.report_text = make_text(22, Color3.fromRGB(255, 180, 180))
        e.report_text.Text = "Reports: " .. reports
    end
    table.insert(alerts, e)
    refresh_positions()
    return e
end

function notifications:remove(e)
    if e.state == "out" then return end
    e.alpha = 0.4 + ((math.sin(tick() * 4) + 1) / 2) * 0.6
    e.state, e.target_y = "out", SLIDE_START
    task.spawn(function()
        while not e.done do task.wait() end
        e.name_text:Remove()
        if e.report_text then e.report_text:Remove() end
        table.remove(alerts, table.find(alerts, e))
        refresh_positions()
    end)
end

return notifications
