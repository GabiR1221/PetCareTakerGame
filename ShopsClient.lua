local function BankRing()
	while task.wait(0.1) do
		if (Player.Character.HumanoidRootPart.Position - workspace.Map.Rings.Bank.MainPart.Position).Magnitude < 10 then
			if not Frames.Bank.Visible then
				Utilities.ButtonHandler.OnClick(Frames.Bank, UDim2.new(0.359,0,0.414,0))
			end
		end
	end
end

coroutine.wrap(BankRing)()
