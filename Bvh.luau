--!strict

local Bvh = {}
Bvh.__index = Bvh

const kStackSize = 32

export type BvhNode<T> = {
	userdata: T,

	left: number,
	right: number,
	parent: number,
	height: number,

	min: vector,
	max: vector,
}

export type Bvh<T> = setmetatable<{
	nodes: { BvhNode<T> },
	freelist: { number },
	root: number,
}, typeof(Bvh)>

local function sah(min: vector, max: vector): number
	local delta = max - min
	return delta.x * delta.y + delta.y * delta.z + delta.x * delta.z
end

local function collides(min0: vector, max0: vector, min1: vector, max1: vector): boolean
	return min0.x <= max1.x and max0.x >= min1.x
		and min0.y <= max1.y and max0.y >= min1.y
		and min0.z <= max1.z and max0.z >= min1.z
end

local function rayhit(min: vector, max: vector, origin: vector, direction: vector): boolean
	if collides(min, max, origin, origin) then
		return true
	end

	local invDirection = vector.one / direction
	
	local vMax, vMin = (max - origin) * invDirection, (min - origin) * invDirection
	local rMax, rMin = vector.max(vMax, vMin), vector.min(vMax, vMin)
	local tMin, tMax = math.max(rMin.x, rMin.y, rMin.z), math.min(rMax.x, rMax.y, rMax.z)

	return 0.0 <= math.min(tMax, tMin) and tMin <= 1.0 and tMin <= tMax
end

function Bvh.new()
	return setmetatable({
		freelist = {},
		leaves = {},
		nodes = {},
		root = 0,
	}, Bvh)
end

function Bvh.allocateNode<T>(self: Bvh<T>): number
	local id = table.remove(self.freelist) or #self.nodes + 1
	self.nodes[id] = {
		value = 0,
		left = 0,
		right = 0,
		parent = 0,
		height = 0,
		min = vector.create(0, 0),
		max = vector.create(0, 0),
	} :: BvhNode<T>

	return id
end

function Bvh.freeNode<T>(self: Bvh<T>, node: number)
	table.insert(self.freelist, node)
end

function Bvh.findBestSibling<T>(self: Bvh<T>, box: BvhNode<T>)
	local area = sah(box.min, box.max)

	local nodes = self.nodes
	local rootNode = nodes[self.root]

	local baseArea = sah(rootNode.min, rootNode.max)
	local directCost = sah(vector.min(rootNode.min, box.min), vector.max(rootNode.max, box.max))
	local inheritedCost = 0.0

	local bestSibling = self.root
	local bestCost = directCost

	-- Descend the tree from the root, using a greedy path approach
	-- (could improve w/ a priority queue, but eh.)
	local index = self.root
	while nodes[index].height > 0 do
		local node = nodes[index]
		local left, right = nodes[node.left], nodes[node.right]

		local cost = directCost + inheritedCost
		if cost < bestCost then
			bestSibling = index
			bestCost = cost
		end

		inheritedCost += directCost - baseArea

		local leftLeaf, rightLeaf = left.height == 0, right.height == 0
		
		local leftLowerCost, rightLowerCost = math.huge, math.huge
		local leftArea, rightArea = 0, 0
		local leftDirectCost, rightDirectCost = sah(vector.min(left.min, box.min), vector.max(right.max, box.max)),
			sah(vector.min(right.min, box.min), vector.max(right.max, box.max))

		if leftLeaf then
			-- Left is a leaf node
			local leftCost = leftDirectCost + inheritedCost
			if leftCost < bestCost then
				bestSibling = node.left
				bestCost = leftCost
			end
		else
			-- Internal node
			leftArea = sah(left.min, left.max)
			leftLowerCost = inheritedCost + leftDirectCost + math.min(area - leftArea, 0)
		end

		if rightLeaf then
			-- Right is a leaf node
			local rightCost = rightDirectCost + inheritedCost
			if rightCost < bestCost then
				bestSibling = node.right
				bestCost = rightCost
			end
		else
			-- Internal node
			rightArea = sah(right.min, right.max)
			rightLowerCost = inheritedCost + rightDirectCost + math.min(area - rightArea, 0)
		end

		if bestCost <= leftLowerCost and bestCost <= rightLowerCost then
			-- Can't reduce the cost any further
			break
		elseif leftLowerCost < rightLowerCost and not leftLeaf then
			-- Go left
			index = node.left
			baseArea = leftArea
			directCost = leftDirectCost
		else
			-- Go right
			index = node.right
			baseArea = rightArea
			directCost = rightDirectCost
		end
	end

	return bestSibling
end

function Bvh.rotateNode<T>(self: Bvh<T>, iA: number)
	local nodes = self.nodes

	local A = nodes[iA]
	if A.height < 2 then
		return
	end

	local iB, iC = A.left, A.right
	local B, C = nodes[iB], nodes[iC]
	if B.height == 0 then
		-- B is a leaf and C is internal
		local iF, iG = C.left, C.right
		local F, G = nodes[iF], nodes[iG]
		local costBase = sah(C.min, C.max)

		local costBF = sah(vector.min(B.min, F.min), vector.max(B.max, F.max))
		local costBG = sah(vector.min(B.min, G.min), vector.max(B.max, G.max))

		if costBase < costBF and costBase < costBG then
			-- Rotation doesn't improve cost
			return
		elseif costBF < costBG then
			-- Swap BF
			A.left, C.left = iF, iB
			B.parent, F.parent = iC, iA
			C.min, C.max = vector.min(B.min, G.min), vector.max(B.max, G.max)
			C.height, A.height = 1 + math.max(B.height, G.height), 1 + math.max(C.height, F.height)
		else
			-- Swap BG
			A.left, C.right = iG, iB
			B.parent, G.parent = iC, iA
			C.min, C.max = vector.min(B.min, F.min), vector.max(B.max, F.max)
			C.height, A.height = 1 + math.max(B.height, F.height), 1 + math.max(C.height, G.height)
		end
	elseif C.height == 0 then
		-- C is a leaf and B is internal
		local iD, iE = B.left, B.right
		local D, E = nodes[iD], nodes[iE]

		local costBase = sah(B.min, B.max)

		local costCD = sah(vector.min(C.min, E.min), vector.max(C.max, E.max))
		local costCE = sah(vector.min(C.min, D.min), vector.max(C.max, D.max))

		if costBase < costCD and costBase < costCE then
			-- Rotation doens't improve cost
			return
		elseif costCD < costCE then
			-- Swap C and D
			A.right, B.left = iD, iC
			C.parent,  D.parent = iB, iA
			B.min, B.max = vector.min(C.min, E.min), vector.max(C.max, E.max)
			B.height, A.height = 1 + math.max(C.height, E.height), 1 + math.max(B.height, D.height)
		else
			-- Swap C and E
			A.right, B.right = iE, iC
			C.parent, E.parent = iB, iA
			B.min, B.max = vector.min(C.min, D.min), vector.max(C.max, D.max)
			B.height, A.height = 1 + math.max(C.height, D.height), 1 + math.max(B.height, E.height)
		end
	else
		local iD, iE, iF, iG = B.left, B.right, C.left, C.right
		local D, E, F, G = nodes[iD], nodes[iE], nodes[iF], nodes[iG]

		local areaB = sah(B.min, B.max)
		local areaC = sah(C.min, C.max)

		local costBase = areaB + areaC

		local bestRotation = 0
		local bestCost = costBase

		-- Cost of swapping B and F
		local costBF = areaB + sah(vector.min(B.min, G.min), vector.max(B.max, G.max))
		local costBG = areaB + sah(vector.min(B.min, F.min), vector.max(B.max, F.max))
		local costCD = areaB + sah(vector.min(C.min, E.min), vector.max(C.max, E.max))
		local costCE = areaB + sah(vector.min(C.min, D.min), vector.max(C.max, D.max))

		if costBF < bestCost then
			bestRotation = 1
			bestCost = costBF
		end
		
		if costBG < bestCost then
			bestRotation = 2
			bestCost = costBG
		end
		
		if costCD < bestCost then
			bestRotation = 3
			bestCost = costCD
		end
		
		if costCE < bestCost then
			bestRotation = 4
			bestCost = costCE
		end

		if bestRotation == 0 then
			return
		elseif bestRotation == 1 then
			-- BF rotation
			A.left, C.left = iF, iB
			B.parent, F.parent = iC, iA
			C.min, C.max = vector.min(B.min, G.min), vector.max(B.max, G.max)
			C.height, A.height = 1 + math.max(B.height, G.height), 1 + math.max(C.height, F.height)
		elseif bestRotation == 2 then
			-- BG rotation
			A.left, C.right = iG, iB
			B.parent, G.parent = iC, iA
			C.min, C.max = vector.min(B.min, F.min), vector.max(B.max, F.max)
			C.height, A.height = 1 + math.max(B.height, F.height), 1 + math.max(C.height, G.height)
		elseif bestRotation == 3 then
			-- CD rotation
			A.right, B.left = iD, iC
			C.parent, D.parent = iB, iA
			B.min, B.max = vector.min(C.min, E.min), vector.max(C.max, E.max)
			B.height, A.height = 1 + math.max(C.height, E.height), 1 + math.max(B.height, D.height)
		elseif bestRotation == 4 then
			-- BG rotation
			A.right, B.left = iE, iC
			C.parent, E.parent = iB, iA
			B.min, B.max = vector.min(C.min, D.min), vector.max(C.max, D.max)
			B.height, A.height = 1 + math.max(C.height, D.height), 1 + math.max(B.height, E.height)
		end
	end
end

function Bvh.insert<T>(self: Bvh<T>, userdata: T, min: vector, max: vector)
	local nodes = self.nodes
	local leaf = self:allocateNode()
	nodes[leaf].userdata = userdata
	nodes[leaf].min = min
	nodes[leaf].max = max

	if self.root == 0 then
		-- Root node
		self.root = leaf
		return
	end

	-- Find the best sibling for this node
	local leafNode = nodes[leaf]
	local sibling = self:findBestSibling(leafNode)
	
	local oldParent = nodes[sibling].parent
	local newParent = self:allocateNode()

	local siblingNode = nodes[sibling]
	local parentNode = nodes[newParent]
	parentNode.min, parentNode.max = vector.min(leafNode.min, siblingNode.min), vector.max(leafNode.max, siblingNode.max)
	parentNode.parent = oldParent
	parentNode.height = siblingNode.height + 1

	nodes[newParent] = parentNode

	if oldParent ~= 0 then
		-- Sibling is not the root
		if nodes[oldParent].left == sibling then
			nodes[oldParent].left = newParent
		else
			nodes[oldParent].right = newParent
		end

		parentNode.left = sibling
		parentNode.right = leaf
	else
		-- Sibling was the root
		parentNode.left = sibling
		parentNode.right = leaf
		self.root = newParent
	end
	
	siblingNode.parent = newParent
	leafNode.parent = newParent

	-- Walk back up the tree and fix heights and AABBs
	local index = nodes[leaf].parent
	while index ~= 0 do
		local node = nodes[index]
		local left = nodes[node.left]
		local right = nodes[node.right]

		node.min = vector.min(left.min, right.min)
		node.max = vector.max(left.max, right.max)
		node.height = 1 + math.max(left.height, right.height)

		self:rotateNode(index)
		index = nodes[index].parent
	end
end

function Bvh.delete<T>(self: Bvh<T>, leaf: number)
	if leaf == self.root then
		self.root = 0
		return
	end

	local nodes = self.nodes
	local parent = nodes[leaf].parent
	local grandParent = nodes[parent].parent
	local sibling = if nodes[parent].left == leaf
		then nodes[parent].right
		else nodes[parent].left

	if grandParent ~= 0 then
		-- Destroy parent and connect sibling to grandparent
		if nodes[grandParent].left == parent then
			nodes[parent].left = sibling
		else
			nodes[parent].right = sibling
		end

		nodes[sibling].parent = grandParent
		self:freeNode(leaf)

		-- Adjust ancestor bounds
		local index = grandParent
		while index ~= 0 do
			local node = nodes[index]
			local left = nodes[node.left]
			local right = nodes[node.right]
			
			node.min, node.max = vector.min(left.min, right.min), vector.max(left.max, right.max)
			node.height = 1 + math.max(left.height, right.height)
			index = node.parent
		end
	else
		-- Then just set the root to the sibling
		self.root = sibling
		self.nodes[sibling].parent = 0
		self:freeNode(leaf)
	end
end

function Bvh.getUserdata<T>(self: Bvh<T>, id: number): T
	return self.nodes[id].userdata
end

function Bvh.raycast<T>(self: Bvh<T>, origin: vector, direction: vector): { number }
	local nodes = self.nodes
	local output = {}

	local stack = table.create(kStackSize, self.root)
	local cursor = 1

	while cursor ~= 0 do
		local iA = assert(table.remove(stack), "Luau")
		local A = nodes[iA]
		cursor -= 1

		if rayhit(A.min, A.max, origin, direction) then
			if A.userdata then
				table.insert(output, iA)
			else
				stack[cursor + 1] = A.left
				stack[cursor + 2] = A.right
				cursor += 2
			end
		end
	end

	return output
end

function Bvh.query<T>(self: Bvh<T>, min: vector, max: vector): { number }
	local nodes = self.nodes
	local output = {}

	local stack = table.create(kStackSize, self.root)
	local cursor = 1
	
	while cursor ~= 0 do
		local iA = assert(table.remove(stack), "Luau")
		local A = nodes[iA]
		cursor -= 1

		if collides(A.min, A.max, min, max) then
			if A.userdata then
				table.insert(output, iA)
			else
				stack[cursor + 1] = A.left
				stack[cursor + 2] = A.right
				cursor += 2
			end
		end
	end

	return output
end

return Bvh
