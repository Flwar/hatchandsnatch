--!strict
--[[
	ModelKit
	A small toolkit for building clean, low-part-count models out of primitive parts:
	balls, ellipsoids (sphere meshes), blocks, wedges and cylinders.

	Creature and map builders describe shapes in a local frame (+Y up, -Z forward,
	origin on the ground) and ModelKit places them in the world. A Rig adds a uniform
	scale so the same creature code can build a baby and an adult.

	This module only creates Instances. It never touches services, so it also runs in
	the Lune preview tooling (tools/preview) used to render model sheets.
]]

local ModelKit = {}

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge" | "Ellipsoid"
export type Palette = { [string]: Color3 }
export type ColorRef = Color3 | string

export type PartOptions = {
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	castShadow: boolean?,
}

export type EyeStyle = "Bean" | "Googly" | "Sleepy" | "Pixel"
export type MouthStyle = "Open" | "Smile" | "Grin" | "O" | "Fangs" | "Flat"

export type EyeSpec = {
	center: Vector3, -- ellipsoid the eyes sit on, in the rig's local frame
	size: Vector3,
	spread: number, -- sideways component of the eye direction
	height: number, -- vertical component of the eye direction
	radius: number,
	style: EyeStyle,
	embed: number?, -- fraction of the radius sunk into the surface
	look: Vector3?, -- pupil nudge in local space, for goofy looks
	pupilScale: number?,
	color: ColorRef?,
	white: ColorRef?,
	forward: Vector3?,
}

export type EyeOptions = {
	look: Vector3?,
	pupilScale: number?,
	color: ColorRef?, -- pupil / iris color
	white: ColorRef?, -- eyeball color (Googly) or eye color (Pixel)
}

export type MouthSpec = {
	center: Vector3,
	size: Vector3,
	height: number, -- vertical component of the mouth direction
	width: number,
	style: MouthStyle,
	skin: ColorRef?, -- surface color, needed by the Smile style
	forward: Vector3?,
	tilt: number?, -- degrees, rotates the mouth around its facing axis
}

export type CheekSpec = {
	center: Vector3,
	size: Vector3,
	spread: number,
	height: number,
	width: number,
	color: ColorRef?,
	forward: Vector3?,
}

export type Rig = {
	model: Model,
	origin: CFrame,
	scale: number,
	eyeBoost: number,
	palette: Palette,
	parts: { BasePart },
	color: (ref: ColorRef) -> Color3,
	add: (name: string, shape: Shape, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?) -> BasePart,
	ellipsoid: (name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?) -> BasePart,
	ball: (name: string, diameter: number, position: Vector3, color: ColorRef, opts: PartOptions?) -> BasePart,
	block: (name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?) -> BasePart,
	wedge: (name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?) -> BasePart,
	cylinder: (
		name: string,
		length: number,
		diameter: number,
		cf: CFrame,
		color: ColorRef,
		opts: PartOptions?
	) -> BasePart,
	rod: (name: string, a: Vector3, b: Vector3, diameter: number, color: ColorRef, opts: PartOptions?) -> BasePart,
	disc: (
		name: string,
		diameter: number,
		thickness: number,
		position: Vector3,
		color: ColorRef,
		opts: PartOptions?
	) -> BasePart,
	onSurface: (center: Vector3, size: Vector3, direction: Vector3) -> (Vector3, Vector3),
	eye: (name: string, frame: CFrame, radius: number, style: EyeStyle, opts: EyeOptions?) -> (),
	eyes: (spec: EyeSpec) -> (),
	patch: (
		name: string,
		center: Vector3,
		size: Vector3,
		direction: Vector3,
		patchSize: Vector3,
		color: ColorRef,
		opts: PartOptions?,
		sink: number?
	) -> BasePart,
	mouth: (spec: MouthSpec) -> (),
	cheeks: (spec: CheekSpec) -> (),
}

local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local EYE_DARK = Color3.fromRGB(28, 26, 38)
local EYE_WHITE = Color3.fromRGB(250, 250, 252)
local MOUTH_DARK = Color3.fromRGB(70, 26, 40)
local TONGUE = Color3.fromRGB(255, 120, 140)
local BLUSH = Color3.fromRGB(255, 150, 170)
local FORWARD = Vector3.new(0, 0, -1)

---------------------------------------------------------------------------
-- CFrame helpers
---------------------------------------------------------------------------

-- CFrame at (x, y, z) rotated by Euler angles given in degrees.
function ModelKit.at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

-- CFrame at `position` whose LookVector (-Z) points along `forward`. Safe for vertical directions.
function ModelKit.facing(position: Vector3, forward: Vector3, upHint: Vector3?): CFrame
	local look = forward.Unit
	local up = upHint or Vector3.new(0, 1, 0)
	if math.abs(look:Dot(up.Unit)) > 0.999 then
		up = Vector3.new(0, 0, 1)
	end
	local back = -look
	local right = up:Cross(back).Unit
	local trueUp = back:Cross(right).Unit
	return CFrame.fromMatrix(position, right, trueUp, back)
end

-- CFrame centred between a and b whose X axis runs from a to b (cylinder axis), plus the length.
function ModelKit.between(a: Vector3, b: Vector3): (CFrame, number)
	local delta = b - a
	local length = delta.Magnitude
	local axis = delta.Unit
	local upHint = Vector3.new(0, 1, 0)
	if math.abs(axis:Dot(upHint)) > 0.999 then
		upHint = Vector3.new(0, 0, -1)
	end
	local back = axis:Cross(upHint).Unit
	local up = back:Cross(axis).Unit
	return CFrame.fromMatrix((a + b) / 2, axis, up, back), length
end

-- Point on the surface of an ellipsoid (center, full size) along `direction`, plus the surface normal.
function ModelKit.ellipsoidSurface(center: Vector3, size: Vector3, direction: Vector3): (Vector3, Vector3)
	local d = direction.Unit
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local t = 1 / math.sqrt((d.X / a) ^ 2 + (d.Y / b) ^ 2 + (d.Z / c) ^ 2)
	local local_ = d * t
	local normal = Vector3.new(local_.X / (a * a), local_.Y / (b * b), local_.Z / (c * c)).Unit
	return center + local_, normal
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

-- Multiplies brightness: factor < 1 darkens, > 1 lightens towards white.
function ModelKit.shade(color: Color3, factor: number): Color3
	if factor <= 1 then
		return Color3.new(color.R * factor, color.G * factor, color.B * factor)
	end
	local t = math.clamp(factor - 1, 0, 1)
	return color:Lerp(Color3.new(1, 1, 1), t)
end

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------

-- Creates one primitive part. Decorative parts default to no collision, no touch and no queries.
function ModelKit.part(
	name: string,
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance?,
	opts: PartOptions?
): BasePart
	local options: PartOptions = opts or {}
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = options.material or DEFAULT_MATERIAL
	part.Transparency = options.transparency or 0
	part.Reflectance = options.reflectance or 0
	part.Anchored = true
	local collide = options.collide == true
	part.CanCollide = collide
	part.CanTouch = collide
	part.CanQuery = collide
	part.CastShadow = if options.castShadow == nil then true else options.castShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Parent = parent
	return part
end

-- Axis-aligned (in `frame` space) bounding box of parts: returns box CFrame and size.
function ModelKit.bounds(parts: { BasePart }, frame: CFrame): (CFrame, Vector3)
	local inf = math.huge
	local minV = Vector3.new(inf, inf, inf)
	local maxV = Vector3.new(-inf, -inf, -inf)
	local inverse = frame:Inverse()
	for _, part in parts do
		local cf = inverse * part.CFrame
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	if #parts == 0 then
		return frame, Vector3.new(1, 1, 1)
	end
	return frame * CFrame.new((minV + maxV) / 2), maxV - minV
end

-- Adds an invisible, anchored Root part covering `parts`, welds everything to it and makes it
-- the PrimaryPart. The model's pivot is `pivot` (usually the ground point under the model).
function ModelKit.finishModel(model: Model, parts: { BasePart }, pivot: CFrame): BasePart
	local boxCf, boxSize = ModelKit.bounds(parts, pivot)
	local root = ModelKit.part("Root", "Block", boxSize, boxCf, Color3.new(1, 1, 1), model, {
		transparency = 1,
		castShadow = false,
	})
	root.CanQuery = true -- lets prompts and clicks find the creature
	root.Locked = true
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
		part.Massless = true
	end
	model.PrimaryPart = root
	root.PivotOffset = root.CFrame:Inverse() * pivot
	return root
end

---------------------------------------------------------------------------
-- Rig: scaled, palette-aware builder in a creature's local frame
---------------------------------------------------------------------------

function ModelKit.newRig(model: Model, origin: CFrame, scale: number, palette: Palette, eyeBoost: number?): Rig
	local rig = {} :: Rig
	rig.model = model
	rig.origin = origin
	rig.scale = scale
	rig.eyeBoost = eyeBoost or 1
	rig.palette = palette
	rig.parts = {}

	function rig.color(ref: ColorRef): Color3
		if typeof(ref) == "Color3" then
			return ref
		end
		local key = ref :: string
		local found = palette[key]
		assert(found, `Palette has no color "{key}"`)
		return found
	end

	local function toWorld(cf: CFrame): CFrame
		return origin * CFrame.new(cf.Position * scale) * cf.Rotation
	end

	function rig.add(
		name: string,
		shape: Shape,
		size: Vector3,
		cf: CFrame,
		color: ColorRef,
		opts: PartOptions?
	): BasePart
		local part = ModelKit.part(name, shape, size * scale, toWorld(cf), rig.color(color), model, opts)
		table.insert(rig.parts, part)
		return part
	end

	function rig.ellipsoid(name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?): BasePart
		return rig.add(name, "Ellipsoid", size, cf, color, opts)
	end

	function rig.ball(name: string, diameter: number, position: Vector3, color: ColorRef, opts: PartOptions?): BasePart
		return rig.add(name, "Ball", Vector3.new(diameter, diameter, diameter), CFrame.new(position), color, opts)
	end

	function rig.block(name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?): BasePart
		return rig.add(name, "Block", size, cf, color, opts)
	end

	function rig.wedge(name: string, size: Vector3, cf: CFrame, color: ColorRef, opts: PartOptions?): BasePart
		return rig.add(name, "Wedge", size, cf, color, opts)
	end

	function rig.cylinder(
		name: string,
		length: number,
		diameter: number,
		cf: CFrame,
		color: ColorRef,
		opts: PartOptions?
	): BasePart
		return rig.add(name, "Cylinder", Vector3.new(length, diameter, diameter), cf, color, opts)
	end

	function rig.rod(
		name: string,
		a: Vector3,
		b: Vector3,
		diameter: number,
		color: ColorRef,
		opts: PartOptions?
	): BasePart
		local cf, length = ModelKit.between(a, b)
		return rig.cylinder(name, length, diameter, cf, color, opts)
	end

	-- Flat vertical-axis cylinder (a coin / plate / pad) centred at `position`.
	function rig.disc(
		name: string,
		diameter: number,
		thickness: number,
		position: Vector3,
		color: ColorRef,
		opts: PartOptions?
	): BasePart
		return rig.cylinder(
			name,
			thickness,
			diameter,
			CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			opts
		)
	end

	rig.onSurface = ModelKit.ellipsoidSurface

	-- One eye whose front faces along frame.LookVector. `frame` is in the rig's local space.
	function rig.eye(name: string, frame: CFrame, radius: number, style: EyeStyle, opts: EyeOptions?)
		local options: EyeOptions = opts or {}
		local look = options.look or Vector3.zero
		local pupilScale = options.pupilScale or 1
		local iris = if options.color then rig.color(options.color) else EYE_DARK
		local white = if options.white then rig.color(options.white) else EYE_WHITE
		if style == "Googly" then
			rig.ball(`Eye{name}`, radius * 2, frame.Position, white)
			local pupilCenter = frame * Vector3.new(look.X * radius, look.Y * radius, -radius * 0.55)
			rig.ball(`Pupil{name}`, radius * 1.1 * pupilScale, pupilCenter, iris)
			rig.ball(
				`Shine{name}`,
				radius * 0.32 * pupilScale,
				(frame - frame.Position + pupilCenter)
					* Vector3.new(radius * 0.18, radius * 0.2, -radius * 0.5 * pupilScale),
				EYE_WHITE
			)
		elseif style == "Bean" then
			rig.ellipsoid(
				`Eye{name}`,
				Vector3.new(radius * 1.5, radius * 2, radius * 1.2),
				frame,
				iris,
				{ reflectance = 0.05 }
			)
			rig.ball(
				`Shine{name}`,
				radius * 0.62,
				frame * Vector3.new(radius * 0.22, radius * 0.42, -radius * 0.5),
				EYE_WHITE
			)
			rig.ball(
				`Sparkle{name}`,
				radius * 0.26,
				frame * Vector3.new(-radius * 0.22, -radius * 0.45, -radius * 0.5),
				EYE_WHITE
			)
		elseif style == "Sleepy" then
			rig.ellipsoid(`Eye{name}`, Vector3.new(radius * 1.8, radius * 0.9, radius * 1.0), frame, iris)
			rig.ball(
				`Shine{name}`,
				radius * 0.3,
				frame * Vector3.new(radius * 0.32, radius * 0.05, -radius * 0.45),
				EYE_WHITE
			)
		elseif style == "Pixel" then
			rig.block(`Eye{name}`, Vector3.new(radius * 1.8, radius * 2, radius * 0.5), frame, white)
			rig.block(
				`Pupil{name}`,
				Vector3.new(radius * 0.9, radius * 1.1, radius * 0.5),
				frame * CFrame.new(look.X * radius * 0.45, -radius * 0.25, -radius * 0.08),
				iris
			)
		end
	end

	-- A symmetric pair of eyes on the surface of an ellipsoid.
	function rig.eyes(spec: EyeSpec)
		local forward = spec.forward or FORWARD
		local radius = spec.radius * rig.eyeBoost
		local embed = spec.embed or 0.35
		local look = spec.look or Vector3.zero
		local right = Vector3.new(-forward.Z, 0, forward.X)
		for side = -1, 1, 2 do
			local dir = forward + right * (spec.spread * side) + Vector3.new(0, spec.height, 0)
			local surface, normal = ModelKit.ellipsoidSurface(spec.center, spec.size, dir)
			local facingDir = (normal + forward).Unit
			local frame = ModelKit.facing(surface - normal * (radius * embed), facingDir)
			rig.eye(if side < 0 then "L" else "R", frame, radius, spec.style, {
				look = Vector3.new(look.X * side, look.Y, look.Z),
				pupilScale = spec.pupilScale,
				color = spec.color,
				white = spec.white,
			})
		end
	end

	-- A flattened ellipsoid sitting on another ellipsoid's surface (spots, patches, plates).
	function rig.patch(
		name: string,
		center: Vector3,
		size: Vector3,
		direction: Vector3,
		patchSize: Vector3,
		color: ColorRef,
		opts: PartOptions?,
		sink: number?
	): BasePart
		local surface, normal = ModelKit.ellipsoidSurface(center, size, direction)
		local frame = ModelKit.facing(surface - normal * (patchSize.Z * (sink or 0.25)), normal)
		return rig.ellipsoid(name, patchSize, frame, color, opts)
	end

	function rig.mouth(spec: MouthSpec)
		local forward = spec.forward or FORWARD
		local dir = forward + Vector3.new(0, spec.height, 0)
		local surface, normal = ModelKit.ellipsoidSurface(spec.center, spec.size, dir)
		local facingDir = (normal + forward * 0.5).Unit
		local w = spec.width
		local frame = ModelKit.facing(surface, facingDir) * CFrame.Angles(0, 0, math.rad(spec.tilt or 0))
		if spec.style == "Open" or spec.style == "Fangs" or spec.style == "Grin" then
			rig.ellipsoid("Mouth", Vector3.new(w, w * 0.62, w * 0.5), frame * CFrame.new(0, 0, w * 0.12), MOUTH_DARK)
			rig.ellipsoid(
				"Tongue",
				Vector3.new(w * 0.56, w * 0.3, w * 0.36),
				frame * CFrame.new(0, -w * 0.13, -w * 0.02),
				TONGUE
			)
			if spec.style == "Fangs" then
				for side = -1, 1, 2 do
					rig.wedge(
						if side < 0 then "FangL" else "FangR",
						Vector3.new(w * 0.07, w * 0.2, w * 0.12),
						frame * CFrame.new(side * w * 0.22, w * 0.13, -w * 0.11) * CFrame.Angles(math.rad(180), 0, 0),
						EYE_WHITE
					)
				end
			elseif spec.style == "Grin" then
				rig.block(
					"Teeth",
					Vector3.new(w * 0.62, w * 0.12, w * 0.12),
					frame * CFrame.new(0, w * 0.16, -w * 0.08),
					EYE_WHITE
				)
			end
		elseif spec.style == "Smile" then
			-- A dark ellipsoid whose top half is hidden by a skin-coloured cap: leaves a crescent smile.
			local skin = if spec.skin then rig.color(spec.skin) else Color3.new(1, 1, 1)
			rig.ellipsoid("Mouth", Vector3.new(w, w * 0.5, w * 0.3), frame * CFrame.new(0, 0, w * 0.05), MOUTH_DARK)
			rig.ellipsoid(
				"Lip",
				Vector3.new(w * 1.04, w * 0.42, w * 0.3),
				frame * CFrame.new(0, w * 0.1, -w * 0.02),
				skin
			)
		elseif spec.style == "O" then
			rig.ellipsoid(
				"Mouth",
				Vector3.new(w * 0.6, w * 0.7, w * 0.4),
				frame * CFrame.new(0, 0, w * 0.1),
				MOUTH_DARK
			)
		elseif spec.style == "Flat" then
			rig.ellipsoid("Mouth", Vector3.new(w, w * 0.16, w * 0.2), frame * CFrame.new(0, 0, w * 0.04), MOUTH_DARK)
		end
	end

	function rig.cheeks(spec: CheekSpec)
		local forward = spec.forward or FORWARD
		local color = if spec.color then rig.color(spec.color) else BLUSH
		for side = -1, 1, 2 do
			local right = Vector3.new(-forward.Z, 0, forward.X)
			local dir = forward + right * (spec.spread * side) + Vector3.new(0, spec.height, 0)
			local surface, normal = ModelKit.ellipsoidSurface(spec.center, spec.size, dir)
			local frame = ModelKit.facing(surface - normal * 0.02, normal)
			rig.ellipsoid(
				if side < 0 then "CheekL" else "CheekR",
				Vector3.new(spec.width, spec.width * 0.6, 0.12),
				frame,
				color
			)
		end
	end

	return rig
end

return table.freeze(ModelKit)
