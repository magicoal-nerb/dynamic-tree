# dynamic-tree
based off of erin catto's dynamic tree. assumes a vector library is used

## features
* supports deletion, insertion, query, raycast, update

## usage
```luau
local function createBroadphase(scene: Instance): Bvh.Bvh<BasePart>
	local broadphase = Bvh.new() :: Bvh.Bvh<BasePart>

	for i, object in scene:GetDescendants() do
		if object:IsA("BasePart") then
			local cframe = object.CFrame
			local halfSize = object.Size / 2

			local absSize = cframe.XVector:Abs() * halfSize.X
				+ cframe.YVector:Abs() * halfSize.Y
				+ cframe.ZVector:Abs() * halfSize.Z

			local position = cframe.Position
			broadphase:insert(object, position - absSize, position + absSize)
		end
	end
	
	return broadphase
end

local Tree = createBroadphase(workspace.Scene)

-- Basic tree query
local A, B = workspace.A.Position, workspace.B.Position
local min, max = A:Min(B), A:Max(B)

for i, id in Tree:query(min, max) do
	local part = Tree:getUserdata(id)
	part.Color = Color3.fromRGB(255, 0, 0)
end

-- Basic tree raycast
for i, id in Tree:raycast(min, max - min) do
	local part = Tree:getUserdata(id)
	part.Color = Color3.fromRGB(0, 255, 0)
end
```

<img width="2291" height="936" alt="{E4EA78C0-9C58-4298-8983-5330CC1B3E4A}" src="https://github.com/user-attachments/assets/21ab03f1-a6f7-4dad-b3d9-5fddef9507c3" />
