----Modules.Utilities.ButtonAnimations.lua
local ButtonAnimations = {}
local Tween = require(script.Parent.Tween)
local TweenService = game:GetService("TweenService")

--// Creates the animation of the buttons
ButtonAnimations.Create = function(Frame : Button, Modifier : SizeModifier, Length : TweenLength)
	local BaseSize = {X = Frame.Size.X.Scale, Y = Frame.Size.Y.Scale}

	local HasOverlay = false
	local HasGradientBorder = false

	-- Finds the first ImageLabel anywhere inside the button
	local Icon = Frame:FindFirstChildWhichIsA("ImageLabel", true)
	local BaseIconRotation = Icon and Icon.Rotation or 0

	-- Random hover rotation settings
	local HoverMinRotate = 8
	local HoverMaxRotate = 22
	local CurrentIconTarget = BaseIconRotation

	if Frame:FindFirstChild("Overlay") then
		HasOverlay = {X = Frame.Overlay.Size.X.Scale, Y = Frame.Overlay.Size.Y.Scale}
	end

	if Frame:FindFirstChild("Border") and Frame.Border:FindFirstChild("UIGradient") then
		HasGradientBorder = {X = Frame.Border.UIGradient.Offset.X, Y = Frame.Border.UIGradient.Offset.Y}
	end

	--// Setup
	if not Length then Length = 0.075 end
	if not Modifier then Modifier = 1.05 end

	local function TweenIconRotation(targetRotation, time)
		if not Icon then return end

		local tween = TweenService:Create(
			Icon,
			TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Rotation = targetRotation}
		)

		tween:Play()
	end

	local function GetRandomHoverRotation()
		local direction = (math.random(0, 1) == 0) and -1 or 1
		local amount = math.random(HoverMinRotate, HoverMaxRotate)
		return BaseIconRotation + (direction * amount)
	end

	--// Hover in & out
	Frame.MouseEnter:Connect(function()
		Frame:TweenSize(UDim2.fromScale(BaseSize.X * Modifier, BaseSize.Y * Modifier), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, Length)

		if Icon then
			CurrentIconTarget = GetRandomHoverRotation()
			TweenIconRotation(CurrentIconTarget, Length)
		end

		--// 3D Effect
		if HasOverlay then
			Frame.Overlay:TweenSize(UDim2.fromScale(HasOverlay.X * Modifier, HasOverlay.Y * Modifier), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, Length, true)
		end

		--// Rotate Gradient
		if HasGradientBorder then
			Tween.Tween(Frame.Border.UIGradient, {Speed = Length}, {Offset = Vector2.new(HasGradientBorder.X + 0.5, HasGradientBorder.Y)})
		end
	end)

	Frame.MouseLeave:Connect(function()
		task.wait(Length)

		Frame:TweenSize(UDim2.fromScale(BaseSize.X, BaseSize.Y), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, Length)

		if Icon then
			TweenIconRotation(BaseIconRotation, Length)
		end

		--// Resets overlay
		if HasOverlay then
			Frame.Overlay:TweenSize(UDim2.fromScale(HasOverlay.X, HasOverlay.Y), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, Length, true)
		end

		--// Resets Gradient
		if HasGradientBorder then
			Tween.Tween(Frame.Border.UIGradient, {Speed = Length}, {Offset = Vector2.new(HasGradientBorder.X, HasGradientBorder.Y)})
		end
	end)

	local Button = Frame:FindFirstChildOfClass("TextButton")

	--// Button Presses
	if Button then
		Button.MouseButton1Down:Connect(function()
			Frame:TweenSize(UDim2.fromScale(BaseSize.X / Modifier, BaseSize.Y / Modifier), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, Length / 1.5)
		end)

		Button.MouseButton1Up:Connect(function()
			Frame:TweenSize(UDim2.fromScale(BaseSize.X * Modifier, BaseSize.Y * Modifier), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, Length / 1.5)

			if Icon then
				TweenIconRotation(CurrentIconTarget, Length / 1.5)
			end

			--// Resets overlay
			if HasOverlay then
				Frame.Overlay:TweenSize(UDim2.fromScale(HasOverlay.X, HasOverlay.Y), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, Length / 1.5, true)
			end

			--// Resets Gradient
			if HasGradientBorder then
				Tween.Tween(Frame.Border.UIGradient, {Speed = Length / 1.5}, {Offset = Vector2.new(HasGradientBorder.X, HasGradientBorder.Y)})
			end
		end)
	end
end

return ButtonAnimations
