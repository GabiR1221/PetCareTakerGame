--// Function for handling buttons

local ButtonHandler = {}

local LocalPlayer = game.Players.LocalPlayer

local Tween = require(script.Parent.Tween)

local function BlurAnimation(Transparency)
	Tween.Tween(LocalPlayer.PlayerGui.GameUI.Blur, {Speed = 0.25}, {BackgroundTransparency=Transparency})
end

local originalSizes = {}

local function getTargetSize(frame, requestedSize)
	if requestedSize and (requestedSize.X.Scale ~= 0 or requestedSize.X.Offset ~= 0 or requestedSize.Y.Scale ~= 0 or requestedSize.Y.Offset ~= 0) then
		return requestedSize
	end
	local saved = originalSizes[frame]
	if saved then
		return saved
	end
	return frame.Size
end

local function scaledSize(size, factor)
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

ButtonHandler.OnClick = function(Frame,Size)
	if not Frame then return end
	local targetSize = getTargetSize(Frame, Size)
	if not originalSizes[Frame] then
		originalSizes[Frame] = targetSize
	end
	if not Frame.Visible then
		--// Close other frames
		for _,OtherFrame in Frame.Parent:GetChildren() do
			if OtherFrame:IsA("Frame") and OtherFrame.Visible then
				local otherTarget = getTargetSize(OtherFrame, nil)
				OtherFrame:TweenSize(scaledSize(otherTarget, 0.85), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
				task.wait(0.04)
				OtherFrame.Visible = false
			end
		end

		--// Open frame

		Frame.Size = scaledSize(targetSize, 0.9)
		Frame.Visible = true
		Frame:TweenSize(targetSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.25, true)
		BlurAnimation(0.4)
	else
		--// Close the frame

		BlurAnimation(1)
		Frame:TweenSize(scaledSize(targetSize, 0.85), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.25, true)
		task.wait(0.1)
		Frame.Visible = false
	end
end

return ButtonHandler
