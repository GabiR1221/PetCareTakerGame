----------CLIENT-----------
--// Frames
local BaseSize = {}
for _,Frame in Frames:GetChildren() do
	if not Frame:IsA("Frame") then continue end

	BaseSize[Frame.Name] = Frame.Size

	if Frame:FindFirstChild("Close") then
		Utilities.ButtonAnimations.Create(Frame.Close)
		Frame.Close.Click.MouseButton1Click:Connect(function()
			Utilities.ButtonHandler.OnClick(Frame, UDim2.new(0,0,0,0))
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

--// Buttons
local ButtonSide = UI[GameSettings.ButtonSide.Value]
for _,Button in ButtonSide.Buttons:GetChildren() do
	if not Button:IsA("Frame") then continue end
	Utilities.ButtonAnimations.Create(Button)
	Button.Click.MouseButton1Click:Connect(function()
		Utilities.ButtonHandler.OnClick(UI.Frames[Button.Name], BaseSize[Button.Name])
		Utilities.Audio.PlayAudio("Click")
	end)
end
----------BUTTONHANDLER---------
--// Function for handling buttons

local ButtonHandler = {}

local LocalPlayer = game.Players.LocalPlayer

local Tween = require(script.Parent.Tween)

local function BlurAnimation(Transparency)
	Tween.Tween(LocalPlayer.PlayerGui.GameUI.Blur, {Speed = 0.25}, {BackgroundTransparency=Transparency})
end

ButtonHandler.OnClick = function(Frame,Size)	
	if not Frame.Visible then
		--// Close other frames
		for _,OtherFrame in Frame.Parent:GetChildren() do
			if OtherFrame:IsA("Frame") and OtherFrame.Visible then
				OtherFrame:TweenSize(Size - UDim2.fromScale(0.15,0.15), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
				task.wait(0.04)
				OtherFrame.Visible = false
			end
		end

		--// Open frame

		Frame.Size = Size - UDim2.fromScale(0.1,0.1)
		Frame.Visible = true
		Frame:TweenSize(Size, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.25, true)
		BlurAnimation(0.4)
	else
		--// Close the frame

		BlurAnimation(1)
		Frame:TweenSize(Size - UDim2.fromScale(0.15,0.15), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.25, true)
		task.wait(0.1)
		Frame.Visible = false
	end
end

return ButtonHandler
