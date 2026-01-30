Local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SimplePath = require(ReplicatedStorage:WaitForChild("SimplePath")) 

local Climbing = {}

-- == КОНФИГУРАЦИЯ ==
local CONFIG = {
	ClimbSpeed = 14,
	Walk = 16,
	VaultForceForward = 45, 
	VaultForceUp = 45,
	
	SearchRadius = 80,
	TargetSearchRadius = 60, 
	
	VerticalThreshold = 7,   
	JumpThreshold = -12, 
	
	JumpBackForce = 30,  
	JumpUpForce = 40,
	ApproachDistance = 1.5,
	
	-- [[ НОВЫЕ НАСТРОЙКИ EXPECTATION ]] --
	Expectation = false,     -- Включить ли режим "поджидания" (по умолчанию false)
	BailThreshold = 5,       -- Сколько раз игрок должен спрыгнуть, чтобы NPC начал ждать
	BailResetTime = 300,     -- (5 минут) Время, через которое счетчик прыжков сбрасывается
	WaitModeDuration = 300,  -- (5 минут) Сколько времени NPC будет "кемперить" внизу, прежде чем снова начать лезть
}

local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude

-- == ХЕЛПЕРЫ (Без изменений) ==

local function isLadder(part)
	if not part then return false end
	return part:IsA("TrussPart")
		or part.Name:lower():find("ladder")
		or CollectionService:HasTag(part, "ForceClimbable")
end

local function getPartCenter(part)
	if part:IsA("BasePart") then return part.Position end
	if part:IsA("Model") then local cf, _ = part:GetBoundingBox() return cf.Position end
	return part.Position
end

local function getTop(part)
	if part:IsA("TrussPart") then return part.Position.Y + part.Size.Y / 2 end
	local model = part:FindFirstAncestorOfClass("Model")
	if model then local cf, size = model:GetBoundingBox() return cf.Position.Y + size.Y / 2 end
	return part.Position.Y + part.Size.Y / 2
end

local function areLaddersAligned(ladder1, ladder2)
	if not ladder1 or not ladder2 then return false end
	local p1 = ladder1.Position
	local p2 = ladder2.Position
	return math.abs(p1.X - p2.X) < 4 and math.abs(p1.Z - p2.Z) < 4
end

local function findLadderPlayerIsUsing(targetModel)
	local root = targetModel:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = {targetModel}
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local parts = workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(4, 5, 4), overlapParams)
	for _, part in ipairs(parts) do if isLadder(part) then return part end end
	local rayDown = workspace:Raycast(root.Position, Vector3.new(0, -4, 0), RAY_PARAMS)
	if rayDown and isLadder(rayDown.Instance) then return rayDown.Instance end
	return nil
end

local function findNearestLadder(pos)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local parts = workspace:GetPartBoundsInRadius(pos, CONFIG.TargetSearchRadius, overlapParams)
	local best, minDst = nil, math.huge
	for _, part in ipairs(parts) do
		if isLadder(part) then
			local dist = (pos - part.Position).Magnitude
			if dist < minDst then minDst = dist; best = part end
		end
	end
	return best
end

local function checkCeiling(rootPos, ladderNormal)
	local origin = rootPos
	local dir = (Vector3.new(0, 1, 0) - ladderNormal * 0.5).Unit * 3.5
	local ray = workspace:Raycast(origin, dir, RAY_PARAMS)
	return (ray and ray.Instance and not isLadder(ray.Instance) and ray.Instance.CanCollide)
end

local function checkCliffAndJump(root, hum)
	local origin = root.Position + (root.CFrame.LookVector * 4)
	local ray = workspace:Raycast(origin, Vector3.new(0, -15, 0), RAY_PARAMS)
	if not ray then hum.Jump = true end
end

-- == ОСНОВНОЙ МОДУЛЬ ==

function Climbing.Start(npc, _, target)
	local hum = npc:FindFirstChild("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	RAY_PARAMS.FilterDescendantsInstances = {npc}
	root:SetNetworkOwner(nil)

	local att = Instance.new("Attachment", root)
	local align = Instance.new("AlignOrientation", root)
	align.Attachment0 = att
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 200 
	align.RigidityEnabled = true
	align.Enabled = false

	local path = SimplePath.new(npc)
	path.Visualize = false 

	local state = "Walking"
	
	local currentClimbLadder = nil   
	local targetPlayerLadder = nil   
	
	local ladderNormal = Vector3.new(0, 0, 1) 
	local ladderCenter = Vector3.new(0,0,0)  
	local ladderTopY = 0
	
	local climbCooldown = 0
	local lastLadderSearch = 0
	local jumpOffTimer = 0 

	-- [[ ПЕРЕМЕННЫЕ EXPECTATION ]] --
	local playerBailCount = 0      -- Сколько раз игрок спрыгнул
	local lastBailTime = 0         -- Когда последний раз спрыгнул
	local isWaitingMode = false    -- Активен ли режим "Засада"
	local waitingStartTime = 0     -- Когда началась засада

	local function resetPhysics()
		align.Enabled = false
		hum.PlatformStand = false
		hum.AutoRotate = true
		root.CanCollide = true
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local function stopClimbing(forceJumpBack)
		path:Stop() 
		climbCooldown = os.clock() + 1.5 
		
		if forceJumpBack then
			state = "JumpingOff"
			jumpOffTimer = os.clock() + 0.3 
			align.Enabled = false 
			hum.PlatformStand = false
			hum.AutoRotate = false 
			
			local jumpDir = (-ladderNormal * CONFIG.JumpBackForce) + Vector3.new(0, CONFIG.JumpUpForce, 0)
			root.AssemblyLinearVelocity = jumpDir
			root.AssemblyAngularVelocity = Vector3.zero 
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
			root.CanCollide = false
			task.delay(0.15, function() if npc and root then root.CanCollide = true end end)

			-- [[ ЛОГИКА СЧЕТЧИКА ПРЫЖКОВ ]] --
			if CONFIG.Expectation then
				local now = os.clock()
				
				-- Если прошло много времени с последнего прыжка, сбрасываем счетчик
				if (now - lastBailTime) > CONFIG.BailResetTime then
					playerBailCount = 0
				end

				playerBailCount += 1
				lastBailTime = now
				
				-- Если прыжков слишком много, включаем режим ЖДУНА
				if playerBailCount >= CONFIG.BailThreshold then
					isWaitingMode = true
					waitingStartTime = now
					print("NPC: Надоело бегать, подожду тебя внизу.")
				end
			end
		else
			resetPhysics()
			state = "Walking"
			root.AssemblyLinearVelocity = root.CFrame.LookVector * 15
		end
	end

	local function vault()
		stopClimbing(false) 
		state = "Walking"
		root.AssemblyLinearVelocity = (root.CFrame.LookVector * CONFIG.VaultForceForward) + Vector3.new(0, CONFIG.VaultForceUp, 0)
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	local connection
	connection = hum.Died:Connect(function()
		connection:Disconnect()
		path:Stop()
		if align then align:Destroy() end
		if att then att:Destroy() end
	end)

	task.spawn(function()
		while npc.Parent and hum.Health > 0 do
			local dt = RunService.Heartbeat:Wait()
			local pos = root.Position
			
			if not target or not target:FindFirstChild("HumanoidRootPart") then
				path:Stop()
				continue 
			end
			
			local tPos = target.HumanoidRootPart.Position
			local yDiff = tPos.Y - pos.Y 

			-- [[ СБРОС РЕЖИМА ОЖИДАНИЯ ПО ТАЙМЕРУ ]] --
			if isWaitingMode and (os.clock() - waitingStartTime > CONFIG.WaitModeDuration) then
				isWaitingMode = false
				playerBailCount = 0 -- Сбрасываем счетчик, чтобы дать игроку шанс
				print("NPC: Ладно, хватит ждать, иду искать.")
			end

			-- Состояние: Спрыгивание
			if state == "JumpingOff" then
				if os.clock() > jumpOffTimer then
					local landed = false
					local hState = hum:GetState()
					if hState == Enum.HumanoidStateType.Landed or hState == Enum.HumanoidStateType.Running then
						landed = true
					end
					if landed or workspace:Raycast(pos, Vector3.new(0, -3.5, 0), RAY_PARAMS) then
						state = "Walking"
						hum.AutoRotate = true
						root.AssemblyLinearVelocity = Vector3.zero 
					end
				end
				continue 
			end

			-- Состояние: Ходьба
			if state == "Walking" then
				
				-- 1. Если игрок внизу (или спустился сам) - преследуем нормально
				if yDiff < CONFIG.VerticalThreshold then
					targetPlayerLadder = nil 
					hum.WalkSpeed = CONFIG.Walk
					path:Run(tPos)
					if yDiff < CONFIG.JumpThreshold then checkCliffAndJump(root, hum) end

				-- 2. Если игрок ВЫСОКО
				else
					if os.clock() - lastLadderSearch > 0.5 then
						lastLadderSearch = os.clock()
						targetPlayerLadder = findLadderPlayerIsUsing(target) or findNearestLadder(tPos)
					end

					-- [[ ПРОВЕРКА НА EXPECTATION ]] --
					-- Если включен режим ожидания и мы знаем где лестница -> НЕ лезем, просто стоим внизу
					local skipClimbing = false
					if isWaitingMode and targetPlayerLadder then
						skipClimbing = true
						-- Смотрим на игрока снизу вверх (опционально можно добавить AlignOrientation для головы)
						local lookAt = Vector3.new(tPos.X, pos.Y, tPos.Z)
						hum:MoveTo(pos) -- Стоим на месте
						root.CFrame = root.CFrame:Lerp(CFrame.lookAt(pos, lookAt), 0.1) -- Поворачиваемся к игроку
					end

					-- Начинаем лезть только если НЕ ждем
					if not skipClimbing and os.clock() > climbCooldown then
						local hitRay = workspace:Raycast(pos, root.CFrame.LookVector * 2.5, RAY_PARAMS)
						
						if hitRay and isLadder(hitRay.Instance) then
							local hitLadder = hitRay.Instance
							local shouldClimb = false
							
							if targetPlayerLadder then
								if areLaddersAligned(hitLadder, targetPlayerLadder) then shouldClimb = true end
							else
								shouldClimb = true 
							end
							
							if shouldClimb then
								state = "Climbing"
								currentClimbLadder = hitLadder
								ladderNormal = hitRay.Normal
								ladderCenter = getPartCenter(hitLadder)
								ladderTopY = getTop(hitLadder)
								
								path:Stop() 
								hum.PlatformStand = true 
								hum.AutoRotate = false
								root.CanCollide = false 
								align.Enabled = true
								continue
							end
						end
					end

					-- Идем к основанию лестницы (даже если ждем - подходим к ней, но не лезем)
					if targetPlayerLadder then
						local lPos = targetPlayerLadder.Position
						local ladderBaseTarget = Vector3.new(lPos.X, pos.Y, lPos.Z)
						local distToLadder = (pos - ladderBaseTarget).Magnitude
						
						-- Если режим ожидания - стоим чуть дальше, чтобы видеть игрока
						local stopDist = isWaitingMode and 5 or 1 

						if distToLadder > stopDist then
							path:Run(ladderBaseTarget)
						elseif not isWaitingMode then
							hum:MoveTo(ladderBaseTarget) 
						end
					else
						path:Run(Vector3.new(tPos.X, pos.Y, tPos.Z))
					end
				end
			end

			-- Состояние: Лазание
			if state == "Climbing" then
				local lookTarget = Vector3.new(ladderCenter.X, pos.Y, ladderCenter.Z)
				align.CFrame = CFrame.lookAt(pos, lookTarget)

				local checkWallRay = workspace:Raycast(pos, (lookTarget - pos).Unit * 5, RAY_PARAMS)

				if not checkWallRay or (not isLadder(checkWallRay.Instance) and checkWallRay.Instance ~= currentClimbLadder) then
					stopClimbing(false) 
					continue
				elseif isLadder(checkWallRay.Instance) and checkWallRay.Instance ~= currentClimbLadder then
					currentClimbLadder = checkWallRay.Instance
					ladderCenter = getPartCenter(currentClimbLadder)
					ladderTopY = getTop(currentClimbLadder)
					ladderNormal = checkWallRay.Normal 
				end

				-- Игрок спрыгнул вниз?
				if tPos.Y < (pos.Y - 5) then
					stopClimbing(true) -- Это засчитается в счетчик бейлов!
					continue
				end

				local desiredVelocityY = checkCeiling(pos, ladderNormal) and 0 or CONFIG.ClimbSpeed

				if pos.Y >= (ladderTopY - 0.5) then
					local upRay = workspace:Raycast(pos + Vector3.new(0,2.5,0), (lookTarget - pos).Unit * 5, RAY_PARAMS)
					if not upRay or not isLadder(upRay.Instance) then
						vault() 
						continue
					else
						ladderTopY = getTop(upRay.Instance)
					end
				end

				local pushDir = (lookTarget - pos).Unit
				root.AssemblyLinearVelocity = Vector3.new(pushDir.X * 5, desiredVelocityY, pushDir.Z * 5)
			end
		end
	end)
end

return Climbing

