local gethui = gethui or function() return game.CoreGui end

local CircleProgression = {}
CircleProgression.Progress = 0
CircleProgression.Radius = 200
CircleProgression.Position = UDim2.new(0.5, 0, 0.5, 0)
CircleProgression.Color = Color3.fromRGB(25, 255, 25)
CircleProgression.BackgroundColor = Color3.fromRGB(100, 100, 100)
CircleProgression.Transparency = 0.5

CircleProgression.p_Objects = {}

do
    local ScreenGui = Instance.new("ScreenGui", gethui())
    ScreenGui.IgnoreGuiInset = true
    local Container = Instance.new("Frame", ScreenGui)
    Container.BackgroundTransparency = 1
    Container.Size = UDim2.fromOffset(CircleProgression.Radius, CircleProgression.Radius)
    Container.Position = CircleProgression.Position
    Container.AnchorPoint = Vector2.new(0.5, 0.5)

    local Background = Instance.new("ImageLabel", Container)
    Background.BackgroundTransparency = 1
    Background.Size = UDim2.new(1, 0, 1, 0)
    Background.Image = "rbxassetid://78253728908199"
    Background.ImageColor3 = CircleProgression.BackgroundColor
    Background.ImageTransparency = CircleProgression.Transparency
    Background.ZIndex = 1

    local LeftContainer = Instance.new("Frame", Container)
    LeftContainer.BackgroundTransparency = 1
    LeftContainer.Size = UDim2.new(0.5, 0, 1, 0)
    LeftContainer.ClipsDescendants = true

    local LeftImage = Instance.new("ImageLabel", LeftContainer)
    LeftImage.BackgroundTransparency = 1
    LeftImage.Size = UDim2.new(2, 0, 1, 0)
    LeftImage.Position = UDim2.new(0, 0, 0, 0)
    LeftImage.Image = "rbxassetid://78253728908199"
    LeftImage.ImageColor3 = CircleProgression.Color
    LeftImage.ImageTransparency = CircleProgression.Transparency
    LeftImage.ZIndex = 2

    local LeftGradient = Instance.new("UIGradient", LeftImage)
    LeftGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.501, 1),
        NumberSequenceKeypoint.new(1, 1)
    })
    LeftGradient.Rotation = 0

    local RightContainer = Instance.new("Frame", Container)
    RightContainer.BackgroundTransparency = 1
    RightContainer.Size = UDim2.new(0.5, 0, 1, 0)
    RightContainer.Position = UDim2.new(1, 0, 0, 0)
    RightContainer.AnchorPoint = Vector2.new(1, 0)
    RightContainer.ClipsDescendants = true

    local RightImage = Instance.new("ImageLabel", RightContainer)
    RightImage.BackgroundTransparency = 1
    RightImage.Size = UDim2.new(2, 0, 1, 0)
    RightImage.Position = UDim2.new(-1, 0, 0, 0)
    RightImage.Image = "rbxassetid://78253728908199"
    RightImage.ImageColor3 = CircleProgression.Color
    RightImage.ImageTransparency = CircleProgression.Transparency
    RightImage.ZIndex = 2

    local RightGradient = Instance.new("UIGradient", RightImage)
    RightGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.501, 1),
        NumberSequenceKeypoint.new(1, 1)
    })
    RightGradient.Rotation = 0

    CircleProgression.p_Objects.ScreenGui = ScreenGui
    CircleProgression.p_Objects.Container = Container
    CircleProgression.p_Objects.Background = Background
    CircleProgression.p_Objects.LeftContainer = LeftContainer
    CircleProgression.p_Objects.LeftImage = LeftImage
    CircleProgression.p_Objects.LeftGradient = LeftGradient
    CircleProgression.p_Objects.RightContainer = RightContainer
    CircleProgression.p_Objects.RightImage = RightImage
    CircleProgression.p_Objects.RightGradient = RightGradient
end

-- Update function
function CircleProgression:Update()
    local PercentRotation = 360 - math.clamp(self.Progress * 3.6, 0, 360)
    local LeftRotation = math.clamp(PercentRotation, 0, 180)
    local RightRotation = math.clamp(PercentRotation, 180, 360)

    self.p_Objects.LeftGradient.Rotation = LeftRotation
    self.p_Objects.RightGradient.Rotation = RightRotation
end

function CircleProgression:SetProgress(Progress)
    self.Progress = Progress
    self:Update()
end

return CircleProgression
