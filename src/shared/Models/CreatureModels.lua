--!strict
--[[
	CreatureModels
	Procedural models for every creature at every growth stage (Egg, Baby, Adult),
	built from primitive parts with ModelKit. Each creature has a palette and a build
	function written in "adult units": +Y up, -Z forward, origin on the ground.

	  CreatureModels.build(creatureId, { stage = "Adult", origin = CFrame.new(...) })

	Returns a Model whose PrimaryPart is an invisible "Root" and whose pivot sits on
	the ground under the creature, facing -Z. All visual parts are welded to Root, so
	the model can be anchored on a pedestal or welded to a player when carried.
	Every model the game shows goes through build(), so swapping in artist-made
	models later only needs a change here.
]]

local ModelKit = require(script.Parent.ModelKit)
local CreatureData = require(script.Parent.Parent.CreatureData)
local Rarity = require(script.Parent.Parent.Rarity)
local Types = require(script.Parent.Parent.Types)

type Rig = ModelKit.Rig
type Palette = ModelKit.Palette

export type Stage = "Egg" | "Baby" | "Adult"

export type BuildOptions = {
	stage: Stage?,
	origin: CFrame?,
	mutation: Types.Mutation?, -- weather mutation; changes the creature's colors and materials
	scale: number?, -- uniform size multiplier (the Fusion Machine shows small versions)
}

-- Where one creature's signature piece can go on another creature (see Hybrids below).
export type Slot = "Head" | "Back" | "Face"

-- Slots that will receive another creature's piece; builders skip whatever sits there.
type Omit = { [string]: boolean }

-- A spot on a creature, in its adult units: the frame's Y axis points out of the body and
-- -Z points forward. `size` is the width there (head, back) or the eye spacing (face).
type Anchor = { at: CFrame, size: number }

-- A creature's signature piece, as given to hybrids. `build` uses the creature's own
-- coordinates; `at` and `size` say where the piece sits on its original owner.
type Trait = { slot: Slot, at: CFrame, size: number, build: (rig: Rig) -> () }

type Art = {
	palette: Palette,
	build: (rig: Rig, omit: Omit) -> (),
	babyLift: number?, -- how high the baby sits inside its eggshell
	trait: Trait?, -- every original creature has one; fusion-only creatures don't need it
	anchors: { [string]: Anchor }?, -- Head, Back and Face, for receiving traits
}

local CreatureModels = {}

local at = ModelKit.at
local v3 = Vector3.new

local BABY_SCALE = 0.55
local BABY_EYE_BOOST = 1.22
local EGG_SIZE = v3(2.6, 3.4, 2.6)

local ART: { [string]: Art } = {}
local NO_OMIT: Omit = table.freeze({})

---------------------------------------------------------------------------
-- Anchor helpers
---------------------------------------------------------------------------

-- A spot on top of an ellipsoid (optionally leaning toward `lean`), sunk in slightly.
local function topAnchor(center: Vector3, size: Vector3, width: number?, lean: Vector3?): Anchor
	local point = ModelKit.ellipsoidSurface(center, size, v3(0, 1, 0) + (lean or Vector3.zero))
	return { at = CFrame.new(point - v3(0, 0.06, 0)), size = width or math.min(size.X, size.Z) }
end

-- A spot on the upper back of an ellipsoid body.
local function backAnchor(center: Vector3, size: Vector3, width: number?): Anchor
	return topAnchor(center, size, width or math.min(size.X, size.Z) * 0.85, v3(0, 0, 0.9))
end

-- A spot just in front of a pair of eyes placed by rig.eyes (same direction math).
local function faceAnchor(
	center: Vector3,
	size: Vector3,
	spread: number,
	height: number,
	radius: number,
	forward: Vector3?
): Anchor
	local look = forward or v3(0, 0, -1)
	local right = v3(-look.Z, 0, look.X)
	local left = ModelKit.ellipsoidSurface(center, size, look - right * spread + v3(0, height, 0))
	local rightEye = ModelKit.ellipsoidSurface(center, size, look + right * spread + v3(0, height, 0))
	local middle = (left + rightEye) / 2
	return { at = ModelKit.facing(middle + look * (radius * 0.7), look), size = (rightEye - left).Magnitude }
end

-- A face spot for hand-placed eyes at +-x (eyes at `center` +- x), looking along `forward`.
local function eyeLineAnchor(center: Vector3, x: number, radius: number, forward: Vector3?): Anchor
	local look = (forward or v3(0, 0, -1)).Unit
	return { at = ModelKit.facing(center + look * (radius * 0.7), look), size = x * 2 }
end

---------------------------------------------------------------------------
-- Common
---------------------------------------------------------------------------

local BLOBBIT_BODY, BLOBBIT_SIZE = v3(0, 1.75, 0), v3(4, 3.4, 3.8)

-- Ears: the right one flops for a goofy look.
local function blobbitEars(r: Rig)
	local earL = at(-0.78, 3.7, 0.25, 10, 0, 14)
	local earR = at(0.95, 3.45, 0.25, 10, 0, -38)
	r.ellipsoid("EarL", v3(0.95, 2.6, 0.7), earL, "Primary")
	r.ellipsoid("EarInnerL", v3(0.5, 1.9, 0.3), earL * CFrame.new(0, 0.05, -0.26), "Inner")
	r.ellipsoid("EarR", v3(0.95, 2.4, 0.7), earR, "Primary")
	r.ellipsoid("EarInnerR", v3(0.5, 1.7, 0.3), earR * CFrame.new(0, 0.05, -0.26), "Inner")
end

ART.Blobbit = {
	palette = {
		Primary = Color3.fromRGB(122, 196, 255),
		Secondary = Color3.fromRGB(84, 156, 236),
		Belly = Color3.fromRGB(198, 236, 255),
		Inner = Color3.fromRGB(255, 176, 206),
		Accent = Color3.fromRGB(84, 156, 236),
		Egg = Color3.fromRGB(172, 220, 255),
	},
	trait = { slot = "Head", at = CFrame.new(0, 3.38, 0.25), size = 3.6, build = blobbitEars },
	anchors = {
		Head = { at = CFrame.new(0, 3.38, 0.25), size = 3.6 },
		Back = backAnchor(BLOBBIT_BODY, BLOBBIT_SIZE, 3.0),
		Face = faceAnchor(BLOBBIT_BODY, BLOBBIT_SIZE, 0.36, 0.2, 0.42),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = BLOBBIT_BODY, BLOBBIT_SIZE
		r.ellipsoid("Puddle", v3(4.7, 0.45, 4.5), at(0, 0.2, 0.1), "Secondary", { reflectance = 0.1 })
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Primary", { reflectance = 0.06 })
		r.ellipsoid("Belly", v3(2.7, 1.8, 3.1), at(0, 1.08, -0.42), "Belly")
		r.patch(
			"Shine",
			body,
			bodySize,
			v3(-0.55, 0.8, -0.4),
			v3(0.75, 0.42, 0.14),
			Color3.fromRGB(240, 250, 255),
			{ transparency = 0.35 }
		)
		if not omit.Head then
			blobbitEars(r)
		end
		r.eyes({ center = body, size = bodySize, spread = 0.36, height = 0.2, radius = 0.42, style = "Bean" })
		r.mouth({ center = body, size = bodySize, height = -0.04, width = 0.62, style = "Smile", skin = "Primary" })
		r.cheeks({ center = body, size = bodySize, spread = 0.62, height = 0.02, width = 0.55 })
		r.ball("Tail", 0.95, v3(0, 1.25, 1.95), "Belly")
		r.ball("DripL", 0.55, v3(-1.75, 0.62, -0.7), "Primary", { reflectance = 0.06 })
		r.ball("DripR", 0.42, v3(1.55, 0.5, 1.15), "Primary", { reflectance = 0.06 })
	end,
}

local PEBBLE_HEAD = at(0, 3.3, -1.15, 0, 0, 7)
local PEBBLE_HEAD_SIZE = v3(3.0, 2.7, 2.6)
local PEBBLE_BODY, PEBBLE_BODY_SIZE = v3(0, 1.75, 0.55), v3(2.9, 2.3, 3.7)

-- Droopy stone ears.
local function pebbleEars(r: Rig)
	local head = PEBBLE_HEAD
	r.ellipsoid(
		"EarL",
		v3(0.62, 1.8, 1.15),
		head * CFrame.new(-1.48, -0.35, 0.15) * CFrame.Angles(0, 0, math.rad(-18)),
		"Secondary"
	)
	r.ellipsoid(
		"EarR",
		v3(0.62, 1.8, 1.15),
		head * CFrame.new(1.48, -0.35, 0.15) * CFrame.Angles(0, 0, math.rad(18)),
		"Secondary"
	)
end

-- A moss cap with a little yellow flower.
local function pebbleMoss(r: Rig)
	local headLocal = PEBBLE_HEAD.Position
	r.patch(
		"MossHead",
		headLocal,
		PEBBLE_HEAD_SIZE,
		PEBBLE_HEAD.Rotation * v3(-0.35, 1, 0.15),
		v3(1.3, 0.9, 0.3),
		"Moss"
	)
	local flowerPos = ModelKit.ellipsoidSurface(headLocal, PEBBLE_HEAD_SIZE, PEBBLE_HEAD.Rotation * v3(-0.42, 1, 0.1))
	r.ball("Flower", 0.5, flowerPos + v3(0, 0.12, 0), "Flower")
end

-- What Pebblepup gives a hybrid, built around the top of the head: floppy stone ears
-- rooted on top (so they stay attached to any head shape) and a mossy tuft with a flower.
local function pebbleTuft(r: Rig)
	r.ellipsoid("EarL", v3(0.62, 1.7, 1.05), at(-1.0, -0.42, 0.1, 0, 0, -38), "Secondary")
	r.ellipsoid("EarR", v3(0.62, 1.7, 1.05), at(1.0, -0.42, 0.1, 0, 0, 38), "Secondary")
	r.ellipsoid("Moss", v3(1.35, 0.5, 1.15), at(0, 0.02, 0.05), "Moss")
	r.ball("Flower", 0.5, v3(-0.3, 0.3, -0.12), "Flower")
end

ART.Pebblepup = {
	palette = {
		Primary = Color3.fromRGB(160, 166, 180),
		Secondary = Color3.fromRGB(122, 128, 144),
		Muzzle = Color3.fromRGB(212, 216, 226),
		Moss = Color3.fromRGB(112, 190, 92),
		Nose = Color3.fromRGB(44, 42, 52),
		Flower = Color3.fromRGB(255, 214, 72),
		Tongue = Color3.fromRGB(255, 122, 140),
		Accent = Color3.fromRGB(112, 190, 92),
		Egg = Color3.fromRGB(196, 200, 212),
	},
	trait = {
		slot = "Head",
		at = CFrame.identity,
		size = 2.8,
		build = pebbleTuft,
	},
	anchors = {
		Head = topAnchor(PEBBLE_HEAD.Position, PEBBLE_HEAD_SIZE, 2.8),
		Back = backAnchor(PEBBLE_BODY, PEBBLE_BODY_SIZE, 2.6),
		Face = faceAnchor(PEBBLE_HEAD.Position, PEBBLE_HEAD_SIZE, 0.36, 0.3, 0.38, PEBBLE_HEAD.LookVector),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = PEBBLE_BODY, PEBBLE_BODY_SIZE
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Primary")
		r.patch("SpotA", body, bodySize, v3(0.7, 0.6, 0.3), v3(1.2, 0.9, 0.3), "Secondary")
		r.patch("SpotB", body, bodySize, v3(-0.5, 0.7, 0.8), v3(0.9, 0.7, 0.3), "Secondary")
		if not omit.Back then
			r.patch("MossBack", body, bodySize, v3(0.1, 1, 0.35), v3(1.5, 1.2, 0.35), "Moss")
		end
		for _, leg in { v3(-0.85, 0.55, -0.45), v3(0.85, 0.55, -0.45), v3(-0.85, 0.55, 1.6), v3(0.85, 0.55, 1.6) } do
			r.ellipsoid("Leg", v3(0.95, 1.2, 1.05), CFrame.new(leg), "Secondary")
		end
		r.ellipsoid("Tail", v3(0.55, 1.4, 0.55), at(0, 2.8, 2.35, -38, 0, 0), "Secondary")
		local head = PEBBLE_HEAD
		local headSize = PEBBLE_HEAD_SIZE
		r.ellipsoid("Head", headSize, head, "Primary")
		local muzzle = head * CFrame.new(0, -0.62, -1.05)
		r.ellipsoid("Muzzle", v3(1.75, 1.15, 1.35), muzzle, "Muzzle")
		r.ellipsoid("Nose", v3(0.72, 0.5, 0.5), muzzle * CFrame.new(0, 0.32, -0.6), "Nose", { reflectance = 0.1 })
		r.ellipsoid(
			"Tongue",
			v3(0.5, 0.18, 0.75),
			muzzle * CFrame.new(0.28, -0.52, -0.42) * CFrame.Angles(math.rad(28), 0, 0),
			"Tongue"
		)
		pebbleEars(r)
		local headLocal = head.Position
		if not omit.Head then
			pebbleMoss(r)
		end
		r.eyes({
			center = headLocal,
			size = headSize,
			spread = 0.36,
			height = 0.3,
			radius = 0.38,
			style = "Googly",
			look = v3(0.15, 0.05, 0),
			forward = head.LookVector,
		})
	end,
}

local SPROUTLE_HEAD, SPROUTLE_HEAD_SIZE = v3(0, 1.75, -2.45), v3(1.95, 1.85, 1.95)

local function sproutleSprout(r: Rig)
	r.rod("Stem", v3(0, 2.8, 0.35), v3(0.12, 3.95, 0.25), 0.22, "Stem")
	r.ellipsoid("LeafL", v3(1.15, 0.18, 0.62), at(-0.5, 4.0, 0.25, 0, 20, -24), "Leaf")
	r.ellipsoid("LeafR", v3(1.15, 0.18, 0.62), at(0.72, 4.02, 0.25, 0, -20, 24), "Leaf")
end

ART.Sproutle = {
	palette = {
		Shell = Color3.fromRGB(156, 104, 66),
		ShellRim = Color3.fromRGB(214, 176, 112),
		Plate = Color3.fromRGB(186, 132, 82),
		Skin = Color3.fromRGB(134, 208, 112),
		Leaf = Color3.fromRGB(88, 196, 80),
		Stem = Color3.fromRGB(112, 168, 70),
		Accent = Color3.fromRGB(156, 104, 66),
		Egg = Color3.fromRGB(176, 226, 150),
	},
	trait = { slot = "Head", at = CFrame.new(0, 2.85, 0.35), size = 2.6, build = sproutleSprout },
	anchors = {
		Head = topAnchor(SPROUTLE_HEAD, SPROUTLE_HEAD_SIZE, 1.95),
		Back = { at = CFrame.new(0, 2.85, 0.35), size = 3.2 },
		Face = faceAnchor(SPROUTLE_HEAD, SPROUTLE_HEAD_SIZE, 0.45, 0.25, 0.27),
	},
	build = function(r: Rig, omit: Omit)
		local shell, shellSize = v3(0, 1.5, 0.35), v3(3.8, 2.8, 4.2)
		r.ellipsoid("Shell", shellSize, CFrame.new(shell), "Shell")
		r.ellipsoid("Rim", v3(4.3, 0.55, 4.7), at(0, 1.05, 0.35), "ShellRim")
		for i, dir in { v3(0, 1, 0.1), v3(0.85, 0.55, -0.1), v3(-0.85, 0.55, 0.35), v3(0.1, 0.5, 0.9) } do
			r.patch(`Plate{i}`, shell, shellSize, dir, v3(1.3, 1.15, 0.3), "Plate")
		end
		local head, headSize = SPROUTLE_HEAD, SPROUTLE_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Skin")
		for _, leg in { v3(-1.5, 0.45, -1.1), v3(1.5, 0.45, -1.1), v3(-1.5, 0.45, 1.65), v3(1.5, 0.45, 1.65) } do
			r.ellipsoid("Leg", v3(1.0, 0.9, 1.1), CFrame.new(leg), "Skin")
		end
		r.ellipsoid("Tail", v3(0.45, 0.4, 0.85), at(0, 0.62, 2.6, 15, 0, 0), "Skin")
		if not omit.Back then
			sproutleSprout(r)
		end
		r.eyes({ center = head, size = headSize, spread = 0.45, height = 0.25, radius = 0.27, style = "Bean" })
		r.mouth({ center = head, size = headSize, height = -0.18, width = 0.42, style = "Smile", skin = "Skin" })
		r.cheeks({ center = head, size = headSize, spread = 0.75, height = -0.05, width = 0.32 })
	end,
}

---------------------------------------------------------------------------
-- Uncommon
---------------------------------------------------------------------------

local BUMBLE_HEAD, BUMBLE_HEAD_SIZE = v3(0, 2.35, -0.85), v3(2.9, 2.7, 2.6)

local function bumbleWings(r: Rig)
	local glass = { material = Enum.Material.Glass, transparency = 0.3 }
	r.ellipsoid("WingL", v3(0.12, 1.7, 2.4), at(-1.25, 3.5, 0.95, 0, 0, 32), "Wing", glass)
	r.ellipsoid("WingR", v3(0.12, 1.7, 2.4), at(1.25, 3.5, 0.95, 0, 0, -32), "Wing", glass)
end

ART.Bumblebun = {
	palette = {
		Primary = Color3.fromRGB(255, 210, 64),
		Stripe = Color3.fromRGB(72, 50, 38),
		Fluff = Color3.fromRGB(255, 244, 214),
		Inner = Color3.fromRGB(255, 168, 190),
		Wing = Color3.fromRGB(214, 240, 255),
		Feet = Color3.fromRGB(255, 158, 62),
		Accent = Color3.fromRGB(72, 50, 38),
		Egg = Color3.fromRGB(255, 224, 116),
	},
	babyLift = 0.25,
	trait = { slot = "Back", at = CFrame.new(0, 3.3, 0.95), size = 3.0, build = bumbleWings },
	anchors = {
		Head = topAnchor(BUMBLE_HEAD, BUMBLE_HEAD_SIZE, 2.6),
		Back = { at = CFrame.new(0, 3.3, 0.95), size = 3.0 },
		Face = faceAnchor(BUMBLE_HEAD, BUMBLE_HEAD_SIZE, 0.38, 0.12, 0.36),
	},
	build = function(r: Rig, omit: Omit)
		local head, headSize = BUMBLE_HEAD, BUMBLE_HEAD_SIZE
		local abdomen, abdomenSize = v3(0, 2.05, 1.05), v3(3.0, 2.8, 3.4)
		r.ellipsoid("Abdomen", abdomenSize, CFrame.new(abdomen), "Primary")
		r.ellipsoid("StripeA", v3(3.2, 3.0, 0.7), at(0, 2.05, 1.2), "Stripe")
		r.ellipsoid("StripeB", v3(2.62, 2.45, 0.6), at(0, 2.05, 2.05), "Stripe")
		r.ball("Stinger", 0.5, v3(0, 2.0, 2.78), "Stripe")
		r.ellipsoid("Fluff", v3(2.75, 2.55, 0.85), at(0, 2.2, 0.2), "Fluff")
		r.ellipsoid("Head", headSize, CFrame.new(head), "Primary")
		if not omit.Head then
			local earL = at(-0.62, 4.05, -0.7, 8, 0, 14)
			local earR = at(0.62, 4.05, -0.7, 8, 0, -14)
			r.ellipsoid("EarL", v3(0.78, 2.0, 0.52), earL, "Primary")
			r.ellipsoid("EarInnerL", v3(0.4, 1.4, 0.22), earL * CFrame.new(0, 0.02, -0.2), "Inner")
			r.ellipsoid("EarR", v3(0.78, 2.0, 0.52), earR, "Primary")
			r.ellipsoid("EarInnerR", v3(0.4, 1.4, 0.22), earR * CFrame.new(0, 0.02, -0.2), "Inner")
		end
		if not omit.Back then
			bumbleWings(r)
		end
		for _, foot in { v3(-0.55, 0.62, -0.95), v3(0.55, 0.62, -0.95), v3(-0.62, 0.75, 1.35), v3(0.62, 0.75, 1.35) } do
			r.ellipsoid("Foot", v3(0.62, 0.48, 0.82), CFrame.new(foot), "Feet")
		end
		r.eyes({ center = head, size = headSize, spread = 0.38, height = 0.12, radius = 0.36, style = "Bean" })
		r.mouth({ center = head, size = headSize, height = -0.22, width = 0.5, style = "Smile", skin = "Primary" })
		r.cheeks({ center = head, size = headSize, spread = 0.62, height = -0.08, width = 0.5 })
	end,
}

local WADDLE_BELLY, WADDLE_BELLY_SIZE = v3(0, 2.4, -0.42), v3(2.5, 2.6, 2.6)
local WADDLE_TIER, WADDLE_TIER_SIZE = v3(0, 3.95, 0.05), v3(3.6, 1.3, 3.4)

local function waddleSwirl(r: Rig)
	r.ellipsoid("FrostingB", v3(2.7, 1.1, 2.5), at(0, 4.5, 0.08), "Frosting")
	r.ellipsoid("FrostingC", v3(1.6, 0.9, 1.5), at(0, 5.0, 0.12), "Frosting")
end

local function waddleCherry(r: Rig)
	r.ball("Cherry", 0.85, v3(0.08, 5.65, 0.12), "Cherry", { reflectance = 0.12 })
	r.rod("CherryStem", v3(0.08, 5.95, 0.12), v3(0.35, 6.45, 0.3), 0.1, "Stem")
end

ART.Waddlecake = {
	palette = {
		Wrapper = Color3.fromRGB(255, 138, 172),
		WrapperDark = Color3.fromRGB(226, 98, 140),
		Choco = Color3.fromRGB(98, 62, 54),
		Vanilla = Color3.fromRGB(255, 242, 224),
		Frosting = Color3.fromRGB(255, 194, 222),
		Cherry = Color3.fromRGB(226, 36, 58),
		Stem = Color3.fromRGB(90, 150, 60),
		Beak = Color3.fromRGB(255, 166, 48),
		SprinkleA = Color3.fromRGB(90, 200, 255),
		SprinkleB = Color3.fromRGB(255, 230, 80),
		SprinkleC = Color3.fromRGB(130, 230, 120),
		Accent = Color3.fromRGB(98, 62, 54),
		Egg = Color3.fromRGB(255, 200, 224),
	},
	trait = {
		slot = "Head",
		at = CFrame.new(0, 4.1, 0.08),
		size = 3.2,
		build = function(r: Rig)
			waddleSwirl(r)
			waddleCherry(r)
		end,
	},
	anchors = {
		Head = { at = CFrame.new(0, 5.36, 0.12), size = 2.2 },
		Back = topAnchor(WADDLE_TIER, WADDLE_TIER_SIZE, 2.4, v3(0, 0, 1.4)),
		Face = faceAnchor(WADDLE_BELLY, WADDLE_BELLY_SIZE, 0.36, 0.52, 0.3),
	},
	build = function(r: Rig, omit: Omit)
		r.disc("Wrapper", 3.4, 1.5, v3(0, 0.75, 0), "Wrapper")
		for i = 0, 5 do
			local angle = math.rad(i * 60 + 30)
			r.block(
				"Ridge",
				v3(0.32, 1.5, 0.3),
				CFrame.new(math.cos(angle) * 1.68, 0.75, math.sin(angle) * 1.68) * CFrame.Angles(0, -angle, 0),
				"WrapperDark"
			)
		end
		local body, bodySize = v3(0, 2.55, 0), v3(3.3, 3.3, 3.1)
		local belly, bellySize = WADDLE_BELLY, WADDLE_BELLY_SIZE
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Choco")
		r.ellipsoid("Belly", bellySize, CFrame.new(belly), "Vanilla")
		local tier1, tier1Size = WADDLE_TIER, WADDLE_TIER_SIZE
		r.ellipsoid("FrostingA", tier1Size, CFrame.new(tier1), "Frosting")
		waddleSwirl(r)
		if not omit.Head then
			waddleCherry(r)
		end
		local sprinkles = {
			{ dir = v3(0.6, 0.6, -0.5), color = "SprinkleA", spin = 30 },
			{ dir = v3(-0.7, 0.5, -0.3), color = "SprinkleB", spin = -40 },
			{ dir = v3(0.5, 0.5, 0.7), color = "SprinkleC", spin = 70 },
			{ dir = v3(-0.45, 0.6, 0.7), color = "SprinkleA", spin = 10 },
		}
		for i, sprinkle in sprinkles do
			local surface, normal = ModelKit.ellipsoidSurface(tier1, tier1Size, sprinkle.dir)
			r.block(
				`Sprinkle{i}`,
				v3(0.42, 0.13, 0.13),
				ModelKit.facing(surface, normal) * CFrame.Angles(0, 0, math.rad(sprinkle.spin)),
				sprinkle.color
			)
		end
		local beakPos, beakNormal = ModelKit.ellipsoidSurface(belly, bellySize, v3(0, 0.22, -1))
		r.ellipsoid("Beak", v3(0.78, 0.44, 0.8), ModelKit.facing(beakPos, beakNormal), "Beak")
		r.eyes({ center = belly, size = bellySize, spread = 0.36, height = 0.52, radius = 0.3, style = "Bean" })
		r.cheeks({ center = belly, size = bellySize, spread = 0.62, height = 0.28, width = 0.38 })
		r.ellipsoid("FlipperL", v3(0.45, 1.6, 0.95), at(-1.72, 2.35, 0.05, 0, 0, -20), "Choco")
		r.ellipsoid("FlipperR", v3(0.45, 1.6, 0.95), at(1.72, 2.35, 0.05, 0, 0, 20), "Choco")
		r.ellipsoid("FootL", v3(0.92, 0.35, 1.2), at(-0.7, 0.16, -1.55, 0, 12, 0), "Beak")
		r.ellipsoid("FootR", v3(0.92, 0.35, 1.2), at(0.7, 0.16, -1.55, 0, -12, 0), "Beak")
	end,
}

local FIZZ_BODY, FIZZ_BODY_SIZE = v3(0, 1.35, 0.2), v3(3.8, 2.5, 3.4)

-- A soda bottle cap worn like a hat, with bubbles rising off it.
local function fizzCap(r: Rig)
	local cap = at(0.15, 2.72, 0.4, 0, 0, 78)
	r.cylinder("Cap", 0.38, 1.6, cap, "Cap")
	r.cylinder("CapTop", 0.06, 1.15, cap * CFrame.new(0.2, 0, 0), "CapTop")
	local glass = { material = Enum.Material.Glass, transparency = 0.35 }
	r.ball("BubbleA", 0.5, v3(0.55, 3.45, 0.45), "Bubble", glass)
	r.ball("BubbleB", 0.38, v3(0.25, 4.0, 0.55), "Bubble", glass)
	r.ball("BubbleC", 0.28, v3(0.6, 4.5, 0.4), "Bubble", glass)
end

-- Eyes sit on two bumps; this is where each eye ends up (see the build below).
local FIZZ_EYE_DIR = v3(0.22, 0.4, -0.9).Unit
local FIZZ_EYE = v3(0.85, 2.5, -0.62) + FIZZ_EYE_DIR * 0.42

ART.Fizzhopper = {
	palette = {
		Primary = Color3.fromRGB(122, 216, 92),
		Belly = Color3.fromRGB(222, 250, 178),
		Spot = Color3.fromRGB(78, 174, 72),
		Cap = Color3.fromRGB(226, 52, 62),
		CapTop = Color3.fromRGB(246, 246, 246),
		Bubble = Color3.fromRGB(178, 232, 255),
		Accent = Color3.fromRGB(226, 52, 62),
		Egg = Color3.fromRGB(168, 234, 140),
	},
	trait = { slot = "Head", at = CFrame.new(0.15, 2.58, 0.4), size = 3.0, build = fizzCap },
	anchors = {
		Head = topAnchor(FIZZ_BODY, FIZZ_BODY_SIZE, 3.0, v3(0, 0, 0.12)),
		Back = backAnchor(FIZZ_BODY, FIZZ_BODY_SIZE, 3.0),
		Face = eyeLineAnchor(v3(0, FIZZ_EYE.Y, FIZZ_EYE.Z), FIZZ_EYE.X, 0.5, v3(0, 0.3, -1)),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = FIZZ_BODY, FIZZ_BODY_SIZE
		local belly, bellySize = v3(0, 1.05, -0.3), v3(3.0, 1.8, 2.8)
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Primary")
		r.ellipsoid("Belly", bellySize, CFrame.new(belly), "Belly")
		for i, dir in { v3(0.5, 0.8, 0.55), v3(-0.6, 0.75, 0.35), v3(0.05, 0.9, 0.95) } do
			r.patch(`Spot{i}`, body, bodySize, dir, v3(0.85, 0.65, 0.25), "Spot")
		end
		local eyeRadius = 0.5 * r.eyeBoost
		for side = -1, 1, 2 do
			local bump = v3(0.85 * side, 2.5, -0.62)
			r.ball("EyeBump", 1.5, bump, "Primary")
			local dir = v3(0.22 * side, 0.4, -0.9).Unit
			r.eye(
				if side < 0 then "L" else "R",
				ModelKit.facing(bump + dir * 0.42, dir),
				eyeRadius,
				"Googly",
				{ look = v3(if side < 0 then 0.25 else -0.05, 0.12, 0) }
			)
		end
		r.mouth({ center = belly, size = bellySize, height = 0.62, width = 1.9, style = "Smile", skin = "Primary" })
		r.cheeks({ center = body, size = bodySize, spread = 0.72, height = 0.12, width = 0.5 })
		r.ellipsoid("LegL", v3(1.1, 1.0, 2.1), at(-1.75, 0.65, 0.95, 0, 10, 0), "Primary")
		r.ellipsoid("LegR", v3(1.1, 1.0, 2.1), at(1.75, 0.65, 0.95, 0, -10, 0), "Primary")
		r.ellipsoid("FootBL", v3(1.05, 0.25, 1.15), at(-1.95, 0.13, -0.2), "Spot")
		r.ellipsoid("FootBR", v3(1.05, 0.25, 1.15), at(1.95, 0.13, -0.2), "Spot")
		r.ellipsoid("FootFL", v3(0.85, 0.25, 0.95), at(-0.95, 0.13, -1.45), "Spot")
		r.ellipsoid("FootFR", v3(0.85, 0.25, 0.95), at(0.95, 0.13, -1.45), "Spot")
		if not omit.Head then
			fizzCap(r)
		end
	end,
}

---------------------------------------------------------------------------
-- Rare
---------------------------------------------------------------------------

local SNAIL_HEAD, SNAIL_HEAD_SIZE = v3(0, 1.6, -1.85), v3(1.9, 2.7, 1.9)

-- The envelope shell, sealed with wax and stamped.
local function snailEnvelope(r: Rig)
	local envelope = at(0, 2.45, 0.95, 0, 0, 3)
	r.block("Envelope", v3(0.85, 3.0, 3.7), envelope, "Paper")
	for side = -1, 1, 2 do
		local x = side * 0.46
		r.wedge(
			"FlapFront",
			v3(0.06, 1.5, 1.85),
			envelope * CFrame.new(x, 0.75, -0.925) * CFrame.Angles(0, 0, math.pi),
			"Flap"
		)
		r.wedge(
			"FlapBack",
			v3(0.06, 1.5, 1.85),
			envelope * CFrame.new(x, 0.75, 0.925) * CFrame.Angles(math.pi, 0, 0),
			"Flap"
		)
		r.cylinder("Seal", 0.16, 0.78, envelope * CFrame.new(side * 0.47, 0.02, 0), "Seal")
	end
	r.block("Stamp", v3(0.06, 0.78, 0.64), envelope * CFrame.new(0.46, 0.95, 1.35), "Stamp")
	r.block("StampInner", v3(0.08, 0.4, 0.32), envelope * CFrame.new(0.47, 0.95, 1.35), "StampInner")
end

-- Eyes sit on stalk tips at +-x (see the build below).
local SNAIL_EYE = v3(0.82, 4.13, -2.35)

ART.Snailmail = {
	palette = {
		Body = Color3.fromRGB(150, 222, 196),
		Paper = Color3.fromRGB(252, 246, 232),
		Flap = Color3.fromRGB(232, 222, 198),
		Seal = Color3.fromRGB(206, 40, 52),
		Stamp = Color3.fromRGB(86, 140, 232),
		StampInner = Color3.fromRGB(255, 222, 96),
		Accent = Color3.fromRGB(206, 40, 52),
		Egg = Color3.fromRGB(196, 238, 222),
	},
	-- The envelope is the snail's shell, so it stays; pieces from others sit on top of it.
	-- On others the envelope leans back, so it clears hats and clouds.
	trait = {
		slot = "Back",
		at = CFrame.new(0, 1.4, 0.95) * CFrame.Angles(math.rad(-28), 0, 0),
		size = 4.6,
		build = snailEnvelope,
	},
	anchors = {
		Head = topAnchor(SNAIL_HEAD, SNAIL_HEAD_SIZE, 1.9),
		Back = { at = CFrame.new(0, 3.88, 0.95), size = 2.4 },
		Face = eyeLineAnchor(v3(0, SNAIL_EYE.Y, SNAIL_EYE.Z), SNAIL_EYE.X, 0.42),
	},
	build = function(r: Rig, _omit: Omit)
		r.ellipsoid("Foot", v3(2.1, 1.2, 5.2), at(0, 0.55, 0.3), "Body")
		local head, headSize = SNAIL_HEAD, SNAIL_HEAD_SIZE
		r.ellipsoid("Head", headSize, at(0, 1.6, -1.85, -10, 0, 0), "Body")
		local eyeRadius = 0.42 * r.eyeBoost
		for side = -1, 1, 2 do
			local tip = v3(0.78 * side, 3.95, -2.3)
			r.rod("Stalk", v3(0.35 * side, 2.6, -2.0), tip, 0.24, "Body")
			r.eye(
				if side < 0 then "L" else "R",
				ModelKit.facing(tip + v3(0.04 * side, 0.18, -0.05), v3(0.12 * side, 0.1, -1)),
				eyeRadius,
				"Googly",
				{ look = if side < 0 then v3(0.2, 0.1, 0) else v3(0.05, 0.3, 0) }
			)
		end
		r.mouth({ center = head, size = headSize, height = -0.1, width = 0.6, style = "Smile", skin = "Body" })
		r.cheeks({ center = head, size = headSize, spread = 0.58, height = 0.05, width = 0.34 })
		snailEnvelope(r)
	end,
}

local CACTO_HEAD, CACTO_HEAD_SIZE = v3(0, 3.25, 0.1), v3(3.2, 3.8, 3.2)

local function cactoFlower(r: Rig)
	local flower = v3(0, 5.18, 0.1)
	for i = 0, 4 do
		local a = math.rad(i * 72 + 18)
		r.ellipsoid(
			"Petal",
			v3(1.0, 0.26, 0.64),
			CFrame.new(flower + v3(math.cos(a) * 0.55, 0, math.sin(a) * 0.55))
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, math.rad(18)),
			"Flower"
		)
	end
	r.ball("FlowerCenter", 0.62, flower + v3(0, 0.12, 0), "FlowerCenter")
end

ART.Cactopus = {
	palette = {
		Primary = Color3.fromRGB(92, 186, 98),
		Rib = Color3.fromRGB(128, 216, 120),
		Flower = Color3.fromRGB(255, 104, 172),
		FlowerCenter = Color3.fromRGB(255, 218, 72),
		Tentacle = Color3.fromRGB(80, 166, 92),
		Accent = Color3.fromRGB(255, 104, 172),
		Egg = Color3.fromRGB(150, 214, 130),
	},
	trait = { slot = "Head", at = CFrame.new(0, 5.1, 0.1), size = 2.3, build = cactoFlower },
	anchors = {
		Head = { at = CFrame.new(0, 5.1, 0.1), size = 3.0 },
		Back = backAnchor(CACTO_HEAD, CACTO_HEAD_SIZE, 2.6),
		Face = faceAnchor(CACTO_HEAD, CACTO_HEAD_SIZE, 0.3, 0.1, 0.5),
	},
	build = function(r: Rig, omit: Omit)
		local head, headSize = CACTO_HEAD, CACTO_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Primary")
		for _, deg in { 62, 118, 180, 242, 298 } do
			local a = math.rad(deg)
			local surface, normal = ModelKit.ellipsoidSurface(head, headSize, v3(math.sin(a), 0, -math.cos(a)))
			r.ellipsoid("Rib", v3(0.55, 3.1, 0.42), ModelKit.facing(surface - normal * 0.1, normal), "Rib")
		end
		if not omit.Head then
			cactoFlower(r)
		end
		for _, deg in { 35, -35, 95, -95, 150, -150 } do
			local a = math.rad(deg)
			local d = v3(math.sin(a), 0, -math.cos(a))
			local base = v3(0, 1.75, 0.1) + d * 0.85
			local mid = v3(0, 0.45, 0.1) + d * 2.05
			local tip = v3(0, 0.95, 0.1) + d * 2.75
			local cfA, lenA = ModelKit.between(base, mid)
			r.ellipsoid("Tentacle", v3(lenA + 0.6, 0.95, 0.95), cfA, "Tentacle")
			local cfB, lenB = ModelKit.between(mid, tip)
			r.ellipsoid("TentacleTip", v3(lenB + 0.45, 0.62, 0.62), cfB, "Tentacle")
		end
		r.eyes({
			center = head,
			size = headSize,
			spread = 0.3,
			height = 0.1,
			radius = 0.5,
			style = "Googly",
			look = v3(0.14, 0.05, 0),
		})
		r.mouth({ center = head, size = headSize, height = -0.22, width = 0.72, style = "O" })
		r.cheeks({ center = head, size = headSize, spread = 0.62, height = -0.18, width = 0.45 })
	end,
}

local GLOOM_STEM, GLOOM_STEM_SIZE = v3(0, 1.65, 0), v3(2.6, 3.3, 2.4)
local GLOOM_CAP, GLOOM_CAP_SIZE = v3(0, 3.85, 0.15), v3(4.7, 2.4, 4.5)

-- The glowing cap: on Gloomshroom it is the head; on hybrids it becomes a big mushroom hat.
local function gloomCap(r: Rig)
	r.ellipsoid("Gills", v3(4.3, 0.8, 4.1), at(0, 3.3, 0.15), "Gills")
	r.ellipsoid("Cap", GLOOM_CAP_SIZE, CFrame.new(GLOOM_CAP), "Cap")
	local neon = { material = Enum.Material.Neon }
	local spots = {
		v3(0.2, 1, -0.15),
		v3(-0.8, 0.55, -0.55),
		v3(0.85, 0.5, 0.35),
		v3(-0.55, 0.5, 0.8),
		v3(0.65, 0.45, -0.75),
	}
	for i, dir in spots do
		local size = if i % 2 == 0 then v3(0.75, 0.68, 0.24) else v3(1.0, 0.9, 0.28)
		r.patch(`Spot{i}`, GLOOM_CAP, GLOOM_CAP_SIZE, dir, size, "Spot", neon)
	end
end

ART.Gloomshroom = {
	palette = {
		Cap = Color3.fromRGB(132, 72, 206),
		Gills = Color3.fromRGB(214, 176, 244),
		Stem = Color3.fromRGB(250, 238, 216),
		Spot = Color3.fromRGB(110, 255, 236),
		Feet = Color3.fromRGB(232, 214, 190),
		Accent = Color3.fromRGB(110, 255, 236),
		Egg = Color3.fromRGB(196, 164, 240),
	},
	-- The cap is the head, so it always stays; pieces from others sit on top of it.
	trait = { slot = "Head", at = CFrame.new(0, 3.05, 0.15), size = 4.0, build = gloomCap },
	anchors = {
		Head = topAnchor(GLOOM_CAP, GLOOM_CAP_SIZE, 3.0),
		Back = topAnchor(GLOOM_CAP, GLOOM_CAP_SIZE, 2.8, v3(0, 0, 0.9)),
		Face = faceAnchor(GLOOM_STEM, GLOOM_STEM_SIZE, 0.36, 0.06, 0.36),
	},
	build = function(r: Rig, _omit: Omit)
		local stem, stemSize = GLOOM_STEM, GLOOM_STEM_SIZE
		r.ellipsoid("Stem", stemSize, CFrame.new(stem), "Stem")
		r.ellipsoid("FootL", v3(1.0, 0.5, 1.3), at(-0.7, 0.22, -0.55, 0, 10, 0), "Feet")
		r.ellipsoid("FootR", v3(1.0, 0.5, 1.3), at(0.7, 0.22, -0.55, 0, -10, 0), "Feet")
		gloomCap(r)
		r.eyes({ center = stem, size = stemSize, spread = 0.36, height = 0.06, radius = 0.36, style = "Sleepy" })
		r.mouth({ center = stem, size = stemSize, height = -0.24, width = 0.5, style = "Flat", tilt = 8 })
		r.cheeks({ center = stem, size = stemSize, spread = 0.66, height = -0.1, width = 0.42 })
		r.ellipsoid("BuddyStemA", v3(0.45, 0.8, 0.45), at(1.9, 0.4, 0.9), "Stem")
		r.ellipsoid("BuddyCapA", v3(1.0, 0.55, 1.0), at(1.9, 0.86, 0.9, 0, 0, -10), "Cap")
		r.ellipsoid("BuddyStemB", v3(0.35, 0.6, 0.35), at(-1.8, 0.3, 1.25), "Stem")
		r.ellipsoid("BuddyCapB", v3(0.8, 0.45, 0.8), at(-1.8, 0.66, 1.25, 0, 0, 12), "Cap")
	end,
}

---------------------------------------------------------------------------
-- Epic
---------------------------------------------------------------------------

local THUNDER_BODY, THUNDER_BODY_SIZE = v3(0, 1.4, 0), v3(4.2, 2.8, 3.8)

-- A personal storm cloud with a lightning bolt, floating above the head.
local function thunderCloud(r: Rig)
	r.ball("CloudA", 1.8, v3(0, 5.35, 0.45), "Cloud")
	r.ball("CloudB", 1.35, v3(-1.0, 5.1, 0.45), "Cloud")
	r.ball("CloudC", 1.35, v3(1.0, 5.1, 0.55), "Cloud")
	r.ball("CloudD", 1.3, v3(0.35, 5.8, 0.65), "Cloud")
	r.ellipsoid("CloudBase", v3(3.0, 0.65, 1.5), at(0, 4.6, 0.5), "CloudDark")
	local neon = { material = Enum.Material.Neon }
	local p1, p2, p3, p4 = v3(0.85, 4.45, 0.15), v3(1.35, 3.85, 0.1), v3(0.95, 3.75, 0.1), v3(1.45, 3.05, 0.05)
	r.rod("BoltA", p1, p2, 0.24, "Bolt", neon)
	r.rod("BoltB", p2, p3, 0.24, "Bolt", neon)
	r.rod("BoltC", p3, p4, 0.24, "Bolt", neon)
	r.ball("BoltJointA", 0.24, p2, "Bolt", neon)
	r.ball("BoltJointB", 0.24, p3, "Bolt", neon)
end

ART.Thunderdumpling = {
	palette = {
		Dough = Color3.fromRGB(250, 242, 228),
		Pleat = Color3.fromRGB(234, 218, 196),
		Cloud = Color3.fromRGB(128, 138, 170),
		CloudDark = Color3.fromRGB(94, 102, 134),
		Bolt = Color3.fromRGB(255, 226, 60),
		Accent = Color3.fromRGB(128, 138, 170),
		Egg = Color3.fromRGB(246, 238, 222),
	},
	trait = { slot = "Head", at = CFrame.new(0, 2.8, 0.45), size = 3.4, build = thunderCloud },
	anchors = {
		Head = { at = CFrame.new(0, 3.02, 0.25), size = 3.0 },
		Back = backAnchor(THUNDER_BODY, THUNDER_BODY_SIZE, 3.2),
		Face = faceAnchor(THUNDER_BODY, THUNDER_BODY_SIZE, 0.34, 0.12, 0.34),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = THUNDER_BODY, THUNDER_BODY_SIZE
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Dough")
		local top = v3(0, 2.72, 0.25)
		r.ellipsoid("Knot", v3(1.1, 0.75, 1.1), CFrame.new(top + v3(0, 0.12, 0)), "Pleat")
		for _, deg in { 306, 18, 90, 162, 234 } do
			local a = math.rad(deg)
			r.ellipsoid(
				"Pleat",
				v3(1.45, 0.34, 0.48),
				CFrame.new(top + v3(math.cos(a) * 0.78, -0.12, math.sin(a) * 0.78))
					* CFrame.Angles(0, -a, 0)
					* CFrame.Angles(0, 0, math.rad(-18)),
				"Pleat"
			)
		end
		r.eyes({ center = body, size = bodySize, spread = 0.34, height = 0.12, radius = 0.34, style = "Bean" })
		r.mouth({ center = body, size = bodySize, height = -0.2, width = 0.62, style = "Open" })
		r.cheeks({ center = body, size = bodySize, spread = 0.62, height = -0.04, width = 0.55 })
		if not omit.Head then
			thunderCloud(r)
		end
	end,
}

local JELLY_BELL, JELLY_BELL_SIZE = v3(0, 3.7, 0), v3(3.8, 3.0, 3.8)

local function jellyHelmet(r: Rig)
	local metal = { material = Enum.Material.Metal }
	r.ellipsoid("Helmet", v3(2.7, 1.7, 2.7), at(0, 5.0, 0.05), "Helmet", metal)
	r.ellipsoid("Visor", v3(2.2, 0.38, 0.55), at(0, 4.78, -1.18), "HelmetDark", metal)
	r.ellipsoid("PlumeA", v3(0.55, 1.2, 0.55), at(0, 6.05, 0.1, 15, 0, 0), "Plume")
	r.ellipsoid("PlumeB", v3(0.5, 1.0, 0.5), at(0, 6.3, 0.75, 55, 0, 0), "Plume")
	r.ellipsoid("PlumeC", v3(0.42, 0.8, 0.42), at(0, 6.0, 1.3, 105, 0, 0), "Plume")
end

ART.Jellyknight = {
	palette = {
		Bell = Color3.fromRGB(255, 136, 198),
		Glow = Color3.fromRGB(255, 214, 236),
		Rim = Color3.fromRGB(238, 102, 174),
		Tentacle = Color3.fromRGB(255, 166, 214),
		Helmet = Color3.fromRGB(198, 204, 218),
		HelmetDark = Color3.fromRGB(110, 116, 134),
		Plume = Color3.fromRGB(232, 48, 68),
		Blade = Color3.fromRGB(226, 232, 242),
		Hilt = Color3.fromRGB(150, 96, 54),
		Gold = Color3.fromRGB(255, 200, 64),
		Accent = Color3.fromRGB(232, 48, 68),
		Egg = Color3.fromRGB(255, 186, 222),
	},
	babyLift = 0.2,
	trait = { slot = "Head", at = CFrame.new(0, 5.12, 0.05), size = 3.6, build = jellyHelmet },
	anchors = {
		Head = { at = CFrame.new(0, 5.12, 0), size = 3.4 },
		Back = backAnchor(JELLY_BELL, JELLY_BELL_SIZE, 3.0),
		Face = faceAnchor(JELLY_BELL, JELLY_BELL_SIZE, 0.34, 0.04, 0.38),
	},
	build = function(r: Rig, omit: Omit)
		local bell, bellSize = JELLY_BELL, JELLY_BELL_SIZE
		r.ellipsoid("Bell", bellSize, CFrame.new(bell), "Bell", { reflectance = 0.08 })
		r.patch("BellGlow", bell, bellSize, v3(0.5, 0.6, -0.35), v3(0.9, 0.55, 0.16), "Glow", { transparency = 0.25 })
		r.ellipsoid("Rim", v3(4.1, 0.6, 4.1), at(0, 2.35, 0), "Rim")
		local metal = { material = Enum.Material.Metal }
		if not omit.Head then
			jellyHelmet(r)
		end
		r.eyes({ center = bell, size = bellSize, spread = 0.34, height = 0.04, radius = 0.38, style = "Bean" })
		r.mouth({ center = bell, size = bellSize, height = -0.3, width = 0.55, style = "Smile", skin = "Bell" })
		r.cheeks({ center = bell, size = bellSize, spread = 0.62, height = -0.12, width = 0.5 })
		for i = 0, 4 do
			local a = math.rad(i * 72 + 54)
			local dir = v3(math.cos(a), 0, math.sin(a))
			local base = v3(0, 2.3, 0) + dir * 1.45
			local mid = v3(0, 1.35, 0) + dir * 1.7
			local tip = v3(0, 0.4, 0) + dir * 1.4
			local cfA, lenA = ModelKit.between(base, mid)
			r.ellipsoid("Tentacle", v3(lenA + 0.35, 0.34, 0.34), cfA, "Tentacle")
			local cfB, lenB = ModelKit.between(mid, tip)
			r.ellipsoid("TentacleTip", v3(lenB + 0.3, 0.28, 0.28), cfB, "Tentacle")
		end
		local sword = at(2.3, 2.0, -0.6, 0, 0, -8)
		r.block("Blade", v3(0.14, 2.3, 0.42), sword * CFrame.new(0, 1.25, 0), "Blade", metal)
		r.block("Guard", v3(0.9, 0.18, 0.3), sword * CFrame.new(0, 0.05, 0), "Gold", metal)
		r.rod(
			"Grip",
			(sword * CFrame.new(0, -0.02, 0)).Position,
			(sword * CFrame.new(0, -0.68, 0)).Position,
			0.2,
			"Hilt"
		)
		r.ball("Pommel", 0.32, (sword * CFrame.new(0, -0.78, 0)).Position, "Gold", metal)
	end,
}

local DODO_HEAD, DODO_HEAD_SIZE = v3(0, 4.75, -1.2), v3(2.4, 2.4, 2.4)
local DODO_BODY, DODO_BODY_SIZE = v3(0, 2.6, 0.35), v3(3.8, 3.6, 4.2)

-- Neon shades. On the Disco Dodo they are its eyes; on hybrids they go over the eyes.
local function dodoShades(r: Rig)
	local neon = { material = Enum.Material.Neon }
	for side = -1, 1, 2 do
		local lens = at(0.5 * side, 5.0, -2.28, 0, 90 - 14 * side, 0)
		r.cylinder("Frame", 0.12, 0.98, lens, "Frame")
		r.cylinder("Lens", 0.14, 0.8, lens * CFrame.new(0.04, 0, 0), "Lens", neon)
	end
	r.block("Bridge", v3(0.32, 0.1, 0.1), at(0, 5.05, -2.42), "Frame")
end

ART.DiscoDodo = {
	palette = {
		Primary = Color3.fromRGB(156, 122, 226),
		Belly = Color3.fromRGB(226, 206, 255),
		Beak = Color3.fromRGB(255, 204, 86),
		BeakTip = Color3.fromRGB(240, 140, 52),
		Tail = Color3.fromRGB(255, 255, 255),
		Frame = Color3.fromRGB(34, 32, 44),
		Lens = Color3.fromRGB(255, 64, 186),
		Shoe = Color3.fromRGB(255, 84, 168),
		Sole = Color3.fromRGB(250, 250, 255),
		Gold = Color3.fromRGB(255, 204, 60),
		Leg = Color3.fromRGB(255, 170, 80),
		Accent = Color3.fromRGB(255, 64, 186),
		Egg = Color3.fromRGB(200, 176, 250),
	},
	trait = { slot = "Face", at = CFrame.new(0, 5.02, -2.36), size = 1.0, build = dodoShades },
	anchors = {
		Head = topAnchor(DODO_HEAD, DODO_HEAD_SIZE, 2.2),
		Back = backAnchor(DODO_BODY, DODO_BODY_SIZE, 3.0),
		Face = { at = CFrame.new(0, 5.02, -2.36), size = 1.0 },
	},
	build = function(r: Rig, _omit: Omit)
		local belly, bellySize = v3(0, 2.35, -0.2), v3(3.0, 2.9, 3.3)
		r.ellipsoid("Body", DODO_BODY_SIZE, CFrame.new(DODO_BODY), "Primary", { reflectance = 0.08 })
		r.ellipsoid("Belly", bellySize, CFrame.new(belly), "Belly")
		r.ellipsoid("Neck", v3(1.9, 2.0, 1.9), at(0, 3.95, -0.85), "Primary")
		local head, headSize = DODO_HEAD, DODO_HEAD_SIZE
		r.ball("Head", 2.4, head, "Primary")
		r.ellipsoid("Beak", v3(1.0, 0.95, 2.0), at(0, 4.45, -2.6, 15, 0, 0), "Beak")
		r.ellipsoid("BeakTip", v3(0.75, 0.7, 0.65), at(0, 4.05, -3.42), "BeakTip")
		dodoShades(r)
		for i, rz in { -28, 0, 28 } do
			r.ellipsoid(`Tail{i}`, v3(0.5, 1.5, 0.4), at(rz * -0.012, 3.65, 2.35, -45, 0, rz), "Tail")
		end
		r.ellipsoid("WingL", v3(0.5, 1.7, 2.1), at(-1.85, 2.9, 0.4, 0, 0, -12), "Primary")
		r.ellipsoid("WingR", v3(0.5, 1.7, 2.1), at(1.85, 2.9, 0.4, 0, 0, 12), "Primary")
		for side = -1, 1, 2 do
			r.rod("Leg", v3(0.7 * side, 1.1, 0.3), v3(0.78 * side, 0.55, 0.15), 0.35, "Leg")
			r.block("Shoe", v3(1.05, 0.55, 1.45), at(0.8 * side, 0.4, -0.05), "Shoe")
			r.block("Sole", v3(1.1, 0.16, 1.5), at(0.8 * side, 0.08, -0.05), "Sole")
		end
		r.ellipsoid("Chain", v3(2.25, 0.18, 2.25), at(0, 3.3, -0.75), "Gold", { reflectance = 0.25 })
		local medal, medalNormal = ModelKit.ellipsoidSurface(belly, bellySize, v3(0, 0.38, -1))
		r.cylinder(
			"Medallion",
			0.14,
			0.72,
			ModelKit.facing(medal, medalNormal) * CFrame.Angles(0, math.rad(90), 0),
			"Gold",
			{
				reflectance = 0.25,
			}
		)
		r.cheeks({ center = head, size = headSize, spread = 0.72, height = -0.18, width = 0.42 })
	end,
}

---------------------------------------------------------------------------
-- Legendary
---------------------------------------------------------------------------

local VOLC_BODY, VOLC_BODY_SIZE = v3(0, 2.4, 0.1), v3(3.8, 4.4, 3.6)

local function volcCrater(r: Rig)
	r.ellipsoid("Crater", v3(2.1, 0.75, 2.1), at(0, 4.55, 0.2), "Rim")
	r.ellipsoid("LavaPool", v3(1.45, 0.3, 1.45), at(0, 4.84, 0.2), "Lava", { material = Enum.Material.Neon })
end

local function volcSmoke(r: Rig)
	local smoke = { transparency = 0.15 }
	r.ball("SmokeA", 0.9, v3(0.15, 5.45, 0.35), "Smoke", smoke)
	r.ball("SmokeB", 0.7, v3(-0.25, 6.1, 0.55), "Smoke", smoke)
	r.ball("SmokeC", 0.5, v3(0.15, 6.65, 0.75), "Smoke", smoke)
end

ART.Volcanowl = {
	palette = {
		Primary = Color3.fromRGB(80, 70, 76),
		Belly = Color3.fromRGB(136, 106, 94),
		Disc = Color3.fromRGB(168, 138, 120),
		Lava = Color3.fromRGB(255, 112, 30),
		Iris = Color3.fromRGB(255, 196, 48),
		Beak = Color3.fromRGB(255, 172, 64),
		Smoke = Color3.fromRGB(150, 150, 158),
		Rim = Color3.fromRGB(58, 50, 56),
		Wing = Color3.fromRGB(104, 90, 96),
		Accent = Color3.fromRGB(255, 112, 30),
		Egg = Color3.fromRGB(110, 96, 102),
	},
	-- The crater stays on the owl; pieces from others rise out of the lava instead of the smoke.
	trait = {
		slot = "Head",
		at = CFrame.new(0, 4.45, 0.2),
		size = 3.0,
		build = function(r: Rig)
			volcCrater(r)
			volcSmoke(r)
		end,
	},
	anchors = {
		Head = { at = CFrame.new(0, 4.92, 0.2), size = 2.2 },
		Back = backAnchor(VOLC_BODY, VOLC_BODY_SIZE, 3.0),
		Face = faceAnchor(VOLC_BODY, VOLC_BODY_SIZE, 0.38, 0.45, 0.5),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = VOLC_BODY, VOLC_BODY_SIZE
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Primary")
		r.ellipsoid("Belly", v3(2.8, 2.9, 3.0), at(0, 1.95, -0.38), "Belly")
		for side = -1, 1, 2 do
			r.patch("Disc", body, bodySize, v3(0.38 * side, 0.45, -1), v3(1.75, 1.75, 0.5), "Disc")
		end
		r.eyes({
			center = body,
			size = bodySize,
			spread = 0.38,
			height = 0.45,
			radius = 0.5,
			style = "Googly",
			white = "Iris",
			embed = 0.05,
			look = v3(0, -0.05, 0),
		})
		local beakPos, beakNormal = ModelKit.ellipsoidSurface(body, bodySize, v3(0, 0.22, -1))
		r.ellipsoid(
			"Beak",
			v3(0.55, 0.85, 0.55),
			ModelKit.facing(beakPos, beakNormal) * CFrame.Angles(math.rad(-12), 0, 0),
			"Beak"
		)
		r.ellipsoid("TuftL", v3(0.6, 1.6, 0.6), at(-1.15, 4.6, 0, 0, 0, 25), "Primary")
		r.ellipsoid("TuftR", v3(0.6, 1.6, 0.6), at(1.15, 4.6, 0, 0, 0, -25), "Primary")
		volcCrater(r)
		if not omit.Head then
			volcSmoke(r)
		end
		local neon = { material = Enum.Material.Neon }
		for side = -1, 1, 2 do
			local a = ModelKit.ellipsoidSurface(body, bodySize, v3(0.35 * side, 0.55, 1))
			local b = ModelKit.ellipsoidSurface(body, bodySize, v3(0.15 * side, 0.2, 1))
			local c = ModelKit.ellipsoidSurface(body, bodySize, v3(0.4 * side, -0.15, 1))
			r.rod("CrackA", a, b, 0.16, "Lava", neon)
			r.rod("CrackB", b, c, 0.16, "Lava", neon)
		end
		r.ellipsoid("WingL", v3(0.55, 2.9, 2.3), at(-1.72, 2.3, 0.45, 0, 12, -5), "Wing")
		r.ellipsoid("WingR", v3(0.55, 2.9, 2.3), at(1.72, 2.3, 0.45, 0, -12, 5), "Wing")
		r.ellipsoid("WingTipL", v3(0.5, 1.0, 1.0), at(-1.75, 1.15, 0.85, 0, 12, -5), "Lava", neon)
		r.ellipsoid("WingTipR", v3(0.5, 1.0, 1.0), at(1.75, 1.15, 0.85, 0, -12, 5), "Lava", neon)
		r.ellipsoid("FootL", v3(0.95, 0.4, 1.0), at(-0.7, 0.2, -0.75), "Beak")
		r.ellipsoid("FootR", v3(0.95, 0.4, 1.0), at(0.7, 0.2, -0.75), "Beak")
	end,
}

local CROISS_HEAD, CROISS_HEAD_SIZE = v3(0, 5.1, -2.0), v3(2.4, 2.0, 2.8)

local function croissCrown(r: Rig)
	local crown = at(0.15, 6.3, -1.75, 0, 0, 100)
	local metal = { material = Enum.Material.Metal, reflectance = 0.1 }
	r.cylinder("Crown", 0.6, 1.35, crown, "Gold", metal)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		r.ball(
			"CrownPoint",
			0.3,
			(crown * CFrame.new(0.38, math.cos(a) * 0.6, math.sin(a) * 0.6)).Position,
			"Gold",
			metal
		)
	end
	r.ball("Gem", 0.36, (crown * CFrame.new(0, 0, -0.66)).Position, "Gem", { reflectance = 0.2 })
end

ART.Croissaur = {
	palette = {
		Crust = Color3.fromRGB(222, 146, 58),
		CrustLight = Color3.fromRGB(246, 196, 112),
		Mouth = Color3.fromRGB(110, 40, 44),
		Teeth = Color3.fromRGB(255, 255, 250),
		Gold = Color3.fromRGB(255, 206, 52),
		Gem = Color3.fromRGB(226, 40, 86),
		Accent = Color3.fromRGB(222, 146, 58),
		Egg = Color3.fromRGB(246, 212, 146),
	},
	trait = { slot = "Head", at = CFrame.new(0.1, 6.0, -1.8), size = 2.4, build = croissCrown },
	anchors = {
		Head = topAnchor(CROISS_HEAD, CROISS_HEAD_SIZE, 2.4),
		Back = topAnchor(v3(0, 3.0, 0.5), v3(3.4, 3.2, 2.2), 2.6, v3(0, 0, 0.6)),
		Face = faceAnchor(CROISS_HEAD, CROISS_HEAD_SIZE, 0.55, 0.45, 0.3),
	},
	build = function(r: Rig, omit: Omit)
		r.ellipsoid("Chest", v3(3.0, 3.0, 2.0), at(0, 3.3, -0.75, -15, 0, 0), "CrustLight")
		r.ellipsoid("Belly", v3(3.4, 3.2, 2.2), at(0, 3.0, 0.5), "Crust")
		r.ellipsoid("Hip", v3(3.0, 2.7, 1.9), at(0, 3.0, 1.7, 15, 0, 0), "CrustLight")
		r.ellipsoid("TailA", v3(2.2, 2.0, 1.7), at(0, 2.55, 2.7, 30, 0, 0), "Crust")
		r.ellipsoid("TailB", v3(1.4, 1.3, 1.5), at(0, 2.0, 3.4, 45, 0, 0), "CrustLight")
		r.ellipsoid("TailC", v3(0.8, 0.8, 1.2), at(0, 1.45, 3.9, 55, 0, 0), "Crust")
		local head, headSize = CROISS_HEAD, CROISS_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Crust")
		r.ellipsoid("Mouth", v3(1.9, 0.7, 2.1), at(0, 4.6, -2.35), "Mouth")
		r.ellipsoid("Jaw", v3(2.0, 0.75, 2.3), at(0, 4.25, -2.25, 12, 0, 0), "CrustLight")
		for _, x in { -0.75, -0.3, 0.3, 0.75 } do
			local z = -3.2 + math.abs(x) * 0.42
			r.wedge("Tooth", v3(0.2, 0.32, 0.22), at(x, 4.62, z, 180, 0, 0), "Teeth")
		end
		r.eyes({ center = head, size = headSize, spread = 0.55, height = 0.45, radius = 0.3, style = "Bean" })
		if not omit.Head then
			croissCrown(r)
		end
		r.ellipsoid("ArmL", v3(0.35, 0.35, 0.95), at(-1.25, 3.55, -1.55, 30, 0, 0), "Crust")
		r.ellipsoid("ArmR", v3(0.35, 0.35, 0.95), at(1.25, 3.55, -1.55, 30, 0, 0), "Crust")
		r.ellipsoid("LegL", v3(1.25, 2.2, 1.5), at(-1.15, 1.4, 0.75), "Crust")
		r.ellipsoid("LegR", v3(1.25, 2.2, 1.5), at(1.15, 1.4, 0.75), "Crust")
		r.ellipsoid("FootL", v3(1.25, 0.5, 1.75), at(-1.2, 0.25, 0.25), "CrustLight")
		r.ellipsoid("FootR", v3(1.25, 0.5, 1.75), at(1.2, 0.25, 0.25), "CrustLight")
	end,
}

local MOTH_HEAD, MOTH_HEAD_SIZE = v3(0, 4.55, -0.25), v3(2.3, 2.1, 2.2)
local MOTH_BODY, MOTH_BODY_SIZE = v3(0, 2.95, 0.25), v3(2.4, 3.2, 2.4)

-- Feathery antennae.
local function mothAntennae(r: Rig)
	for side = -1, 1, 2 do
		local a, b = v3(0.35 * side, 5.45, -0.3), v3(1.15 * side, 6.55, -0.1)
		r.rod("Antenna", a, b, 0.12, "Antenna")
		local cf, len = ModelKit.between(a, b)
		r.ellipsoid("Feather", v3(len * 0.85, 0.55, 0.1), cf * CFrame.new(len * 0.1, 0, 0), "Wing")
	end
end

ART.Moonmoth = {
	palette = {
		Primary = Color3.fromRGB(244, 238, 255),
		Fluff = Color3.fromRGB(255, 255, 255),
		Wing = Color3.fromRGB(152, 172, 255),
		Moon = Color3.fromRGB(255, 238, 150),
		Antenna = Color3.fromRGB(96, 92, 128),
		Accent = Color3.fromRGB(152, 172, 255),
		Egg = Color3.fromRGB(214, 222, 255),
	},
	babyLift = 0.2,
	trait = { slot = "Head", at = CFrame.new(0, 5.45, -0.28), size = 2.3, build = mothAntennae },
	anchors = {
		Head = topAnchor(MOTH_HEAD, MOTH_HEAD_SIZE, 2.2),
		Back = { at = CFrame.new(0, 4.05, 1.05), size = 2.2 },
		Face = faceAnchor(MOTH_HEAD, MOTH_HEAD_SIZE, 0.5, 0.08, 0.46),
	},
	build = function(r: Rig, omit: Omit)
		r.ellipsoid("Body", MOTH_BODY_SIZE, CFrame.new(MOTH_BODY), "Primary")
		r.ball("Fluff", 1.5, v3(0, 1.55, 0.4), "Fluff")
		r.ellipsoid("Collar", v3(2.95, 1.0, 2.95), at(0, 3.75, 0.05), "Fluff")
		local head, headSize = MOTH_HEAD, MOTH_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Primary")
		r.eyes({ center = head, size = headSize, spread = 0.5, height = 0.08, radius = 0.46, style = "Bean" })
		r.mouth({ center = head, size = headSize, height = -0.42, width = 0.4, style = "Smile", skin = "Primary" })
		r.cheeks({ center = head, size = headSize, spread = 0.78, height = -0.22, width = 0.38 })
		if not omit.Head then
			mothAntennae(r)
		end
		local neon = { material = Enum.Material.Neon }
		for side = -1, 1, 2 do
			local upper = at(2.05 * side, 3.75, 0.85, 0, -18 * side, 15 * side)
			r.ellipsoid("WingUpper", v3(4.0, 3.0, 0.16), upper, "Wing")
			r.ellipsoid("Moon", v3(1.3, 1.3, 0.2), upper * CFrame.new(0.55 * side, 0.15, 0), "Moon", neon)
			r.ellipsoid("MoonShadow", v3(1.1, 1.1, 0.24), upper * CFrame.new(0.82 * side, 0.32, 0), "Wing")
			local lower = at(1.6 * side, 2.2, 0.95, 0, -25 * side, -20 * side)
			r.ellipsoid("WingLower", v3(2.9, 2.2, 0.16), lower, "Wing")
			r.ellipsoid("Dot", v3(0.6, 0.6, 0.2), lower * CFrame.new(0.4 * side, -0.1, 0), "Moon", neon)
		end
	end,
}

---------------------------------------------------------------------------
-- Mythic
---------------------------------------------------------------------------

local TOAST_BODY, TOAST_BODY_SIZE = v3(0, 2.7, 0.2), v3(2.2, 2.9, 5.9)

local function toastFin(r: Rig)
	r.wedge("Dorsal", v3(0.4, 1.7, 1.7), at(0, 4.65, 0.75), "Crust")
end

ART.Toastshark = {
	palette = {
		Crust = Color3.fromRGB(176, 108, 48),
		Bread = Color3.fromRGB(244, 210, 148),
		Belly = Color3.fromRGB(252, 232, 186),
		Butter = Color3.fromRGB(255, 230, 108),
		Mouth = Color3.fromRGB(92, 32, 40),
		Teeth = Color3.fromRGB(255, 255, 250),
		Accent = Color3.fromRGB(176, 108, 48),
		Egg = Color3.fromRGB(240, 208, 150),
	},
	babyLift = 0.1,
	trait = { slot = "Back", at = CFrame.new(0, 3.95, 0.75), size = 2.2, build = toastFin },
	anchors = {
		Head = { at = CFrame.new(0, 3.98, -1.0), size = 2.2 },
		Back = { at = CFrame.new(0, 3.98, 0.75), size = 2.2 },
		Face = faceAnchor(TOAST_BODY, TOAST_BODY_SIZE, 0.42, 0.28, 0.4),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = TOAST_BODY, TOAST_BODY_SIZE
		r.ellipsoid("Crust", bodySize, CFrame.new(body), "Crust")
		r.ellipsoid("Bread", v3(2.45, 2.5, 5.4), at(0, 2.68, 0.25), "Bread")
		if not omit.Back then
			toastFin(r)
		end
		r.wedge("TailTop", v3(0.36, 1.9, 1.3), at(0, 3.55, 3.45, -15, 0, 0), "Crust")
		r.wedge("TailBottom", v3(0.36, 1.2, 1.0), at(0, 2.15, 3.35, 0, 0, 180), "Crust")
		r.ellipsoid("FinL", v3(1.6, 0.25, 0.95), at(-1.45, 1.95, -0.55, 0, 0, 28), "Crust")
		r.ellipsoid("FinR", v3(1.6, 0.25, 0.95), at(1.45, 1.95, -0.55, 0, 0, -28), "Crust")
		r.eyes({
			center = body,
			size = bodySize,
			spread = 0.42,
			height = 0.28,
			radius = 0.4,
			style = "Googly",
			look = v3(0.1, 0.05, 0),
		})
		local mouthPos, mouthNormal = ModelKit.ellipsoidSurface(body, bodySize, v3(0, -0.22, -1))
		local mouth = ModelKit.facing(mouthPos - mouthNormal * 0.25, mouthNormal)
		r.ellipsoid("Mouth", v3(1.7, 0.8, 0.9), mouth, "Mouth")
		for _, x in { -0.5, -0.25, 0, 0.25, 0.5 } do
			r.wedge(
				"Tooth",
				v3(0.2, 0.3, 0.2),
				mouth * CFrame.new(x, 0.2, -0.34 + math.abs(x) * 0.12) * CFrame.Angles(math.pi, 0, 0),
				"Teeth"
			)
		end
		if not omit.Head then
			r.block("Butter", v3(0.95, 0.26, 0.95), at(0, 4.15, -0.9, -8, 18, 0), "Butter")
			r.ellipsoid("ButterDrip", v3(0.4, 0.7, 0.3), at(0.4, 3.85, -1.4), "Butter")
		end
		r.cheeks({ center = body, size = bodySize, spread = 0.6, height = 0.02, width = 0.45 })
	end,
}

local GOOSE_BODY, GOOSE_BODY_SIZE = v3(0, 2.2, 0.55), v3(3.4, 3.0, 4.4)
local GOOSE_HEAD, GOOSE_HEAD_SIZE = v3(0, 6.0, -1.45), v3(1.55, 1.45, 1.95)

-- A tiny ringed planet orbiting the head.
local function goosePlanet(r: Rig)
	r.ball("Planet", 0.85, v3(1.0, 7.25, -1.2), "Planet")
	r.cylinder("PlanetRing", 0.07, 1.6, at(1.0, 7.25, -1.2, 20, 0, 110), "Ring")
end

ART.Cosmigoose = {
	palette = {
		Primary = Color3.fromRGB(46, 36, 100),
		Nebula = Color3.fromRGB(152, 76, 226),
		NebulaPink = Color3.fromRGB(236, 96, 196),
		Star = Color3.fromRGB(255, 255, 236),
		Beak = Color3.fromRGB(255, 160, 52),
		Knob = Color3.fromRGB(40, 30, 60),
		Feet = Color3.fromRGB(255, 146, 44),
		Planet = Color3.fromRGB(120, 220, 255),
		Ring = Color3.fromRGB(255, 204, 120),
		Accent = Color3.fromRGB(236, 96, 196),
		Egg = Color3.fromRGB(88, 70, 170),
	},
	trait = { slot = "Head", at = CFrame.new(0, 6.66, -1.45), size = 1.8, build = goosePlanet },
	anchors = {
		Head = topAnchor(GOOSE_HEAD, GOOSE_HEAD_SIZE, 1.7),
		Back = backAnchor(GOOSE_BODY, GOOSE_BODY_SIZE, 2.8),
		Face = faceAnchor(GOOSE_HEAD, GOOSE_HEAD_SIZE, 0.7, 0.22, 0.26),
	},
	build = function(r: Rig, omit: Omit)
		local body, bodySize = GOOSE_BODY, GOOSE_BODY_SIZE
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Primary", { reflectance = 0.08 })
		r.patch("NebulaL", body, bodySize, v3(-1, 0.3, 0.1), v3(2.3, 1.6, 0.35), "Nebula")
		r.patch("NebulaR", body, bodySize, v3(1, 0.3, 0.1), v3(2.3, 1.6, 0.35), "Nebula")
		r.patch("NebulaTop", body, bodySize, v3(0.35, 1, 0.75), v3(1.0, 0.75, 0.24), "NebulaPink")
		local neon = { material = Enum.Material.Neon }
		local stars = {
			v3(0.8, 0.6, -0.2),
			v3(-0.7, 0.7, 0.4),
			v3(0.3, 0.9, 0.9),
			v3(-0.9, 0.2, -0.4),
			v3(0.95, 0.1, 0.6),
			v3(-0.2, 0.95, -0.3),
		}
		for i, dir in stars do
			local p = ModelKit.ellipsoidSurface(body, bodySize, dir)
			r.ball(`Star{i}`, if i % 2 == 0 then 0.2 else 0.15, p, "Star", neon)
		end
		local cfA, lenA = ModelKit.between(v3(0, 3.0, -0.95), v3(0, 4.7, -1.3))
		r.ellipsoid("NeckA", v3(lenA + 0.9, 1.15, 1.15), cfA, "Primary")
		local cfB, lenB = ModelKit.between(v3(0, 4.6, -1.3), v3(0, 5.6, -1.15))
		r.ellipsoid("NeckB", v3(lenB + 0.8, 1.05, 1.05), cfB, "Primary")
		local head, headSize = GOOSE_HEAD, GOOSE_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Primary")
		r.ellipsoid("Beak", v3(0.8, 0.52, 1.35), at(0, 5.82, -2.6, -5, 0, 0), "Beak")
		r.ball("Knob", 0.5, v3(0, 6.12, -2.2), "Knob")
		r.eyes({
			center = head,
			size = headSize,
			spread = 0.7,
			height = 0.22,
			radius = 0.26,
			style = "Googly",
			look = v3(0.2, 0.1, 0),
		})
		r.cheeks({ center = head, size = headSize, spread = 0.82, height = -0.1, width = 0.3 })
		r.ellipsoid("WingL", v3(0.6, 2.0, 3.4), at(-1.75, 2.6, 0.75, 0, 0, -10), "Nebula")
		r.ellipsoid("WingR", v3(0.6, 2.0, 3.4), at(1.75, 2.6, 0.75, 0, 0, 10), "Nebula")
		r.ellipsoid("Tail", v3(1.0, 0.85, 1.4), at(0, 2.95, 2.9, -32, 0, 0), "Primary")
		for side = -1, 1, 2 do
			r.rod("Leg", v3(0.6 * side, 1.0, 0.4), v3(0.7 * side, 0.25, 0.15), 0.28, "Feet")
			r.ellipsoid("Foot", v3(1.0, 0.28, 1.35), at(0.72 * side, 0.14, -0.15), "Feet")
		end
		if not omit.Head then
			goosePlanet(r)
		end
	end,
}

local DRAGON_HEAD, DRAGON_HEAD_SIZE = v3(0, 3.4, -1.55), v3(2.2, 1.85, 2.6)

local function dragonHorns(r: Rig)
	r.ellipsoid("HornL", v3(0.38, 1.3, 0.38), at(-0.55, 4.45, -1.2, -35, 0, 12), "Horn")
	r.ellipsoid("HornR", v3(0.38, 1.3, 0.38), at(0.55, 4.45, -1.2, -35, 0, -12), "Horn")
	r.ellipsoid("Wasabi", v3(0.85, 0.55, 0.85), at(0, 4.3, -1.85), "Wasabi")
	r.ball("WasabiTip", 0.4, v3(0.05, 4.6, -1.85), "Wasabi")
end

ART.Dragonroll = {
	palette = {
		Nori = Color3.fromRGB(36, 52, 44),
		Rice = Color3.fromRGB(250, 250, 244),
		Salmon = Color3.fromRGB(255, 138, 98),
		SalmonStripe = Color3.fromRGB(255, 214, 196),
		Cucumber = Color3.fromRGB(110, 200, 90),
		Horn = Color3.fromRGB(252, 238, 200),
		Whisker = Color3.fromRGB(60, 40, 40),
		Wasabi = Color3.fromRGB(146, 210, 82),
		Ginger = Color3.fromRGB(255, 176, 176),
		Accent = Color3.fromRGB(36, 52, 44),
		Egg = Color3.fromRGB(250, 248, 240),
	},
	trait = { slot = "Head", at = CFrame.new(0, 4.25, -1.55), size = 2.2, build = dragonHorns },
	anchors = {
		Head = { at = CFrame.new(0, 4.25, -1.55), size = 2.2 },
		Back = { at = CFrame.new(0.55, 1.8, 0.95), size = 1.9 },
		Face = faceAnchor(DRAGON_HEAD, DRAGON_HEAD_SIZE, 0.55, 0.3, 0.3),
	},
	build = function(r: Rig, omit: Omit)
		local function roll(center: Vector3, axis: Vector3, diameter: number, length: number, filling: string)
			local unit = axis.Unit
			local cf = ModelKit.between(center - unit * (length / 2), center + unit * (length / 2))
			r.cylinder("Nori", length, diameter, cf, "Nori")
			r.cylinder("Rice", length + 0.12, diameter * 0.88, cf, "Rice")
			r.cylinder("Filling", length + 0.16, diameter * 0.36, cf, filling)
		end
		roll(v3(0, 2.1, -0.45), v3(0, 0.62, -0.78), 1.8, 1.05, "Salmon")
		roll(v3(0.55, 0.95, 0.95), v3(0.55, 0, 0.83), 1.9, 1.1, "Cucumber")
		roll(v3(0.05, 0.92, 2.25), v3(-0.6, 0, 0.8), 1.8, 1.05, "Salmon")
		roll(v3(-0.6, 0.75, 3.25), v3(-0.5, 0, 0.87), 1.45, 0.9, "Cucumber")
		r.ellipsoid("GingerA", v3(0.9, 0.12, 0.7), at(-0.95, 1.1, 3.85, 0, 25, 30), "Ginger")
		r.ellipsoid("GingerB", v3(0.8, 0.12, 0.6), at(-1.1, 1.35, 3.7, 0, -10, 60), "Ginger")
		local head, headSize = DRAGON_HEAD, DRAGON_HEAD_SIZE
		r.ellipsoid("Head", headSize, CFrame.new(head), "Salmon")
		r.patch("StripeA", head, headSize, v3(0, 1, 0.3), v3(2.0, 0.28, 0.14), "SalmonStripe")
		r.patch("StripeB", head, headSize, v3(0, 0.75, 0.8), v3(1.9, 0.26, 0.14), "SalmonStripe")
		local snout, snoutSize = v3(0, 3.1, -2.75), v3(1.6, 1.15, 1.5)
		r.ellipsoid("Snout", snoutSize, CFrame.new(snout), "Salmon")
		r.ball("NostrilL", 0.22, v3(-0.32, 3.42, -3.38), "Whisker")
		r.ball("NostrilR", 0.22, v3(0.32, 3.42, -3.38), "Whisker")
		if not omit.Head then
			dragonHorns(r)
		end
		r.rod("WhiskerL", v3(-0.65, 3.05, -3.1), v3(-1.35, 3.4, -3.05), 0.09, "Whisker")
		r.rod("WhiskerR", v3(0.65, 3.05, -3.1), v3(1.35, 3.4, -3.05), 0.09, "Whisker")
		r.eyes({ center = head, size = headSize, spread = 0.55, height = 0.3, radius = 0.3, style = "Bean" })
		r.mouth({ center = snout, size = snoutSize, height = -0.35, width = 0.6, style = "Smile", skin = "Salmon" })
	end,
}

---------------------------------------------------------------------------
-- Secret
---------------------------------------------------------------------------

-- A little burrito worn like a backpack, open end showing the filling (hybrids only).
local function burritoPack(r: Rig)
	r.cylinder("PackWrap", 2.1, 1.3, at(0, 0.6, 0), "Tortilla")
	r.ellipsoid("PackEnd", v3(0.8, 1.3, 1.3), at(-1.05, 0.6, 0), "Tortilla")
	r.ellipsoid("PackLettuce", v3(0.42, 1.42, 1.42), at(1.08, 0.6, 0), "Lettuce")
	r.cylinder("PackTomato", 0.16, 0.55, at(1.24, 0.82, 0.18), "Tomato")
	r.wedge("PackCheese", v3(0.5, 0.45, 0.14), at(1.26, 0.38, -0.22, 0, 0, 0), "Cheese")
	for i, x in { -0.55, 0.05, 0.65 } do
		r.block(`PackGrill{i}`, v3(0.12, 0.08, 0.95), at(x, 1.24, 0, 0, 40, 0), "Grill")
	end
end

-- Eyes sit on two bumps; this is where each eye ends up (see the build below).
local TOAD_EYE_DIR = v3(0.2, 0.35, -0.92).Unit
local TOAD_EYE = v3(0.75, 3.1, -1.85) + TOAD_EYE_DIR * 0.32

ART.Burritoad = {
	palette = {
		Tortilla = Color3.fromRGB(240, 208, 146),
		Grill = Color3.fromRGB(170, 112, 56),
		Toad = Color3.fromRGB(112, 192, 92),
		Chin = Color3.fromRGB(222, 242, 172),
		Lettuce = Color3.fromRGB(126, 222, 92),
		Tomato = Color3.fromRGB(230, 62, 52),
		Cheese = Color3.fromRGB(255, 206, 62),
		Accent = Color3.fromRGB(170, 112, 56),
		Egg = Color3.fromRGB(240, 214, 160),
	},
	-- The tortilla is the body, so it stays; pieces from others sit on the wrap.
	trait = { slot = "Back", at = CFrame.identity, size = 3.0, build = burritoPack },
	anchors = {
		Head = { at = CFrame.new(0, 3.2, -1.65), size = 2.2 },
		Back = { at = CFrame.new(0, 3.02, 0.7), size = 3.0 },
		Face = eyeLineAnchor(v3(0, TOAD_EYE.Y, TOAD_EYE.Z), TOAD_EYE.X, 0.42, v3(0, 0.3, -1)),
	},
	build = function(r: Rig, omit: Omit)
		r.cylinder("Wrap", 4.2, 3.1, at(0, 1.55, 0.7, 0, 90, 0), "Tortilla")
		r.ellipsoid("WrapEnd", v3(3.1, 3.1, 1.8), at(0, 1.55, 2.8), "Tortilla")
		if not omit.Back then
			for i, z in { -0.5, 0.5, 1.5 } do
				r.block(`Grill{i}`, v3(0.16, 0.1, 1.3), at(0, 3.07, z, 0, 50, 0), "Grill")
			end
		end
		local head, headSize = v3(0, 2.15, -1.75), v3(2.7, 2.2, 2.4)
		r.ellipsoid("Head", headSize, CFrame.new(head), "Toad")
		r.ellipsoid("Chin", v3(2.1, 1.2, 1.9), at(0, 1.55, -2.05), "Chin")
		local eyeRadius = 0.42 * r.eyeBoost
		for side = -1, 1, 2 do
			local bump = v3(0.75 * side, 3.1, -1.85)
			r.ball("EyeBump", 1.15, bump, "Toad")
			local dir = v3(0.2 * side, 0.35, -0.92).Unit
			r.eye(if side < 0 then "L" else "R", ModelKit.facing(bump + dir * 0.32, dir), eyeRadius, "Googly", {
				look = if side < 0 then v3(-0.15, 0.2, 0) else v3(0.25, -0.1, 0),
			})
		end
		r.mouth({ center = head, size = headSize, height = -0.12, width = 1.6, style = "Smile", skin = "Toad" })
		r.cheeks({ center = head, size = headSize, spread = 0.7, height = 0, width = 0.45 })
		r.ellipsoid("LettuceL", v3(1.3, 0.55, 0.7), at(-1.15, 2.55, -1.35, 0, 0, 40), "Lettuce")
		r.ellipsoid("LettuceR", v3(1.2, 0.5, 0.7), at(1.2, 2.6, -1.35, 0, 0, -35), "Lettuce")
		r.cylinder("Tomato", 0.2, 0.85, at(1.3, 1.2, -1.4, 0, 90, 0), "Tomato")
		r.wedge("Cheese", v3(0.16, 0.7, 0.9), at(-1.35, 1.05, -1.42, 0, 90, 20), "Cheese")
		r.ellipsoid("HandL", v3(0.7, 0.45, 0.6), at(-1.28, 2.0, -1.62), "Toad")
		r.ellipsoid("HandR", v3(0.7, 0.45, 0.6), at(1.28, 2.0, -1.62), "Toad")
		r.ellipsoid("FootL", v3(0.9, 0.3, 1.0), at(-0.75, 0.15, -1.5, 0, 15, 0), "Toad")
		r.ellipsoid("FootR", v3(0.9, 0.3, 1.0), at(0.75, 0.15, -1.5, 0, -15, 0), "Toad")
	end,
}

local function glitchAlert(r: Rig)
	local neon = { material = Enum.Material.Neon }
	r.block("Alert", v3(0.28, 0.85, 0.28), at(0, 4.75, 0), "Yellow", neon)
	r.block("AlertDot", v3(0.28, 0.28, 0.28), at(0, 4.05, 0), "Yellow", neon)
end

ART.Glitchling = {
	palette = {
		Primary = Color3.fromRGB(226, 52, 226),
		Cyan = Color3.fromRGB(0, 255, 255),
		Red = Color3.fromRGB(255, 46, 90),
		Lime = Color3.fromRGB(96, 255, 96),
		Black = Color3.fromRGB(16, 14, 24),
		Yellow = Color3.fromRGB(255, 230, 40),
		White = Color3.fromRGB(250, 250, 255),
		Accent = Color3.fromRGB(0, 255, 255),
		Egg = Color3.fromRGB(70, 28, 86),
	},
	babyLift = 0.2,
	trait = {
		slot = "Head",
		at = CFrame.new(0, 3.6, 0),
		size = 3.0,
		-- The floating "!" plus two stray pixels.
		build = function(r: Rig)
			glitchAlert(r)
			local neon = { material = Enum.Material.Neon }
			r.block("BitA", v3(0.45, 0.45, 0.45), at(1.7, 3.6, 0.3, 20, 30, 0), "Cyan", neon)
			r.block("BitD", v3(0.4, 0.4, 0.4), at(-1.5, 3.9, -0.4, 10, 40, 0), "Red", neon)
		end,
	},
	anchors = {
		Head = { at = CFrame.new(0, 3.6, 0), size = 3.0 },
		Back = { at = CFrame.new(0, 3.6, 0.85), size = 3.0 },
		Face = eyeLineAnchor(v3(0, 2.45, -1.55), 0.65, 0.42),
	},
	build = function(r: Rig, omit: Omit)
		r.block("Cube", v3(3.0, 3.0, 3.0), at(0, 2.1, 0), "Primary")
		local ghost = { material = Enum.Material.Neon, transparency = 0.72, castShadow = false }
		r.block("GhostCyan", v3(3.0, 3.0, 3.0), at(0.22, 2.16, 0.05), "Cyan", ghost)
		r.block("GhostRed", v3(3.0, 3.0, 3.0), at(-0.22, 2.04, -0.05), "Red", ghost)
		r.block("SliceA", v3(3.0, 0.5, 3.04), at(0.5, 2.75, 0), "Primary")
		r.block("SliceB", v3(3.0, 0.32, 3.04), at(-0.42, 1.35, 0), "Primary")
		r.block("CheckerA", v3(1.5, 0.06, 1.5), at(-0.75, 3.62, -0.75), "Black")
		r.block("CheckerB", v3(1.5, 0.06, 1.5), at(0.75, 3.62, 0.75), "Black")
		local eyeRadius = 0.42 * r.eyeBoost
		r.eye("L", ModelKit.facing(v3(-0.65, 2.45, -1.55), v3(0, 0, -1)), eyeRadius, "Pixel", {
			white = "White",
			color = "Black",
			look = v3(0.35, 0, 0),
		})
		r.eye("R", ModelKit.facing(v3(0.65, 2.45, -1.55), v3(0, 0, -1)), eyeRadius, "Pixel", {
			white = "White",
			color = "Black",
			look = v3(-0.1, 0, 0),
		})
		for i, pos in { v3(-0.78, 1.55, -1.55), v3(-0.32, 1.32, -1.55), v3(0.14, 1.32, -1.55), v3(0.6, 1.55, -1.55) } do
			r.block(`Mouth{i}`, v3(0.44, 0.28, 0.2), CFrame.new(pos), "Black")
		end
		local neon = { material = Enum.Material.Neon }
		r.block("BitA", v3(0.45, 0.45, 0.45), at(2.1, 3.3, 0.4, 20, 30, 0), "Cyan", neon)
		r.block("BitB", v3(0.4, 0.4, 0.4), at(-2.05, 1.3, 0.5, 0, 25, 15), "Lime", neon)
		r.block("BitC", v3(0.35, 0.35, 0.35), at(1.8, 0.9, -0.9, 30, 0, 20), "Yellow", neon)
		r.block("BitD", v3(0.4, 0.4, 0.4), at(-1.5, 3.9, -0.4, 10, 40, 0), "Red", neon)
		if not omit.Head then
			glitchAlert(r)
		end
	end,
}

local SOFA_HEAD = at(-1.6, 5.75, -2.5, 0, -12, 0)
local SOFA_HEAD_SIZE = v3(2.0, 1.6, 2.6)

-- Stegosaurus plates made of cushions.
local function sofaPlates(r: Rig)
	local fabric = { material = Enum.Material.Fabric }
	for i, x in { -1.35, 0, 1.35 } do
		r.ellipsoid(`Plate{i}`, v3(0.85, 1.0, 0.22), at(x, 4.0 + (if x == 0 then 0.1 else 0), 1.05), "Cushion", fabric)
	end
end

ART.Sofasaurus = {
	palette = {
		Fabric = Color3.fromRGB(206, 62, 74),
		FabricDark = Color3.fromRGB(164, 42, 58),
		Cushion = Color3.fromRGB(226, 92, 98),
		Wood = Color3.fromRGB(110, 72, 42),
		Button = Color3.fromRGB(120, 26, 40),
		Pillow = Color3.fromRGB(255, 210, 80),
		Accent = Color3.fromRGB(110, 72, 42),
		Egg = Color3.fromRGB(232, 112, 122),
	},
	trait = { slot = "Back", at = CFrame.new(0, 3.82, 1.05), size = 3.6, build = sofaPlates },
	anchors = {
		Head = { at = SOFA_HEAD * CFrame.new(0, 0.74, 0), size = 2.0 },
		Back = { at = CFrame.new(0, 3.85, 1.05), size = 3.6 },
		Face = faceAnchor(SOFA_HEAD.Position, SOFA_HEAD_SIZE, 0.5, 0.32, 0.3, SOFA_HEAD.LookVector),
	},
	build = function(r: Rig, omit: Omit)
		local fabric = { material = Enum.Material.Fabric }
		r.block("Seat", v3(4.6, 1.2, 2.7), at(0, 1.15, 0.1), "FabricDark", fabric)
		r.block("CushionL", v3(2.12, 0.6, 2.35), at(-1.1, 2.05, -0.05), "Cushion", fabric)
		r.block("CushionR", v3(2.12, 0.6, 2.35), at(1.1, 2.05, -0.05), "Cushion", fabric)
		r.block("Back", v3(4.6, 2.3, 0.85), at(0, 2.75, 1.05), "Fabric", fabric)
		r.ball("ButtonL", 0.22, v3(-0.95, 2.95, 0.6), "Button")
		r.ball("ButtonR", 0.22, v3(0.95, 2.95, 0.6), "Button")
		for side = -1, 1, 2 do
			r.block("Arm", v3(0.85, 1.6, 2.7), at(2.65 * side, 1.6, 0.1), "Fabric", fabric)
			r.cylinder("ArmTop", 2.7, 0.95, at(2.65 * side, 2.42, 0.1, 0, 90, 0), "Fabric", fabric)
			r.block("LegFront", v3(0.4, 0.55, 0.4), at(2.55 * side, 0.28, -1.0), "Wood")
			r.block("LegBack", v3(0.4, 0.55, 0.4), at(2.55 * side, 0.28, 1.2), "Wood")
		end
		r.rod("NeckA", v3(-2.55, 2.75, -0.7), v3(-2.2, 4.45, -1.35), 1.05, "Fabric", fabric)
		r.ball("NeckJoint", 1.05, v3(-2.2, 4.45, -1.35), "Fabric", fabric)
		r.rod("NeckB", v3(-2.2, 4.45, -1.35), v3(-1.75, 5.35, -1.95), 0.95, "Fabric", fabric)
		local head = SOFA_HEAD
		local headSize = SOFA_HEAD_SIZE
		r.ellipsoid("Head", headSize, head, "Fabric", fabric)
		r.eyes({
			center = head.Position,
			size = headSize,
			spread = 0.5,
			height = 0.32,
			radius = 0.3,
			style = "Bean",
			forward = head.LookVector,
		})
		r.mouth({
			center = head.Position,
			size = headSize,
			height = -0.25,
			width = 0.55,
			style = "Smile",
			skin = "Fabric",
			forward = head.LookVector,
		})
		r.rod("TailA", v3(0.4, 1.6, 1.45), v3(1.5, 1.0, 2.25), 0.8, "Fabric", fabric)
		r.ball("TailJoint", 0.8, v3(1.5, 1.0, 2.25), "Fabric", fabric)
		r.rod("TailB", v3(1.5, 1.0, 2.25), v3(2.5, 0.55, 2.2), 0.55, "Fabric", fabric)
		if not omit.Back then
			sofaPlates(r)
		end
		r.ellipsoid("Pillow", v3(1.25, 1.05, 0.5), at(1.35, 2.85, 0.45, -15, 0, 8), "Pillow", fabric)
	end,
}

---------------------------------------------------------------------------
-- Named fusion recipes (see FusionRecipes). Hand-made hybrids that borrow from both
-- parents. They are never fused again, so they need no trait or anchors.
---------------------------------------------------------------------------

-- Blobbit + Waddlecake: a sugar-dusted filled donut with a jelly bunny bursting out.
ART.JellyDonut = {
	palette = {
		Dough = Color3.fromRGB(222, 156, 84),
		DoughLight = Color3.fromRGB(250, 224, 172),
		Sugar = Color3.fromRGB(255, 255, 255),
		Jelly = Color3.fromRGB(122, 196, 255),
		Inner = Color3.fromRGB(255, 176, 206),
		Feet = Color3.fromRGB(255, 166, 48),
		SprinkleA = Color3.fromRGB(255, 120, 180),
		SprinkleB = Color3.fromRGB(255, 230, 80),
		SprinkleC = Color3.fromRGB(130, 230, 120),
		Accent = Color3.fromRGB(122, 196, 255),
		Egg = Color3.fromRGB(246, 214, 160),
	},
	build = function(r: Rig, _omit: Omit)
		local donut, donutSize = v3(0, 1.7, 0.2), v3(4.4, 3.1, 4.2)
		r.ellipsoid("Donut", donutSize, CFrame.new(donut), "Dough")
		r.ellipsoid("Ring", v3(4.52, 0.8, 4.32), at(0, 1.5, 0.2), "DoughLight")
		for i, dir in { v3(0.75, 1, 0.55), v3(-0.8, 1, 0.45), v3(0.05, 1, 1.05), v3(0.95, 0.55, -0.35) } do
			r.patch(`Sugar{i}`, donut, donutSize, dir, v3(1.25, 0.95, 0.2), "Sugar")
		end
		local sprinkles = {
			{ dir = v3(0.35, 1, 0.75), color = "SprinkleA", spin = 30 },
			{ dir = v3(-0.45, 1, 0.95), color = "SprinkleB", spin = -50 },
			{ dir = v3(-1, 0.7, 0.05), color = "SprinkleC", spin = 70 },
			{ dir = v3(0.6, 0.85, 0.15), color = "SprinkleB", spin = 10 },
			{ dir = v3(-0.2, 0.8, 1.3), color = "SprinkleA", spin = -20 },
		}
		for i, sprinkle in sprinkles do
			local surface, normal = ModelKit.ellipsoidSurface(donut, donutSize, sprinkle.dir)
			r.block(
				`Sprinkle{i}`,
				v3(0.45, 0.14, 0.14),
				ModelKit.facing(surface, normal) * CFrame.Angles(0, 0, math.rad(sprinkle.spin)),
				sprinkle.color
			)
		end
		-- The jelly bunny bursting out of the filling hole.
		local jelly, jellySize = v3(0, 3.4, -0.45), v3(2.7, 2.3, 2.5)
		local shiny = { reflectance = 0.1 }
		r.ellipsoid("Jelly", jellySize, CFrame.new(jelly), "Jelly", shiny)
		r.ellipsoid("DripL", v3(0.55, 1.05, 0.45), at(-0.85, 2.45, -1.68, -12, 0, 6), "Jelly", shiny)
		r.ball("DropL", 0.42, v3(-0.9, 1.88, -1.82), "Jelly", shiny)
		r.ellipsoid("DripR", v3(0.45, 0.8, 0.4), at(0.75, 2.3, -1.74, -12, 0, -6), "Jelly", shiny)
		local earL = at(-0.62, 4.85, -0.3, 10, 0, 14)
		local earR = at(0.85, 4.62, -0.3, 10, 0, -40)
		r.ellipsoid("EarL", v3(0.8, 2.1, 0.6), earL, "Jelly", shiny)
		r.ellipsoid("EarInnerL", v3(0.42, 1.5, 0.26), earL * CFrame.new(0, 0.05, -0.22), "Inner")
		r.ellipsoid("EarR", v3(0.8, 1.9, 0.6), earR, "Jelly", shiny)
		r.ellipsoid("EarInnerR", v3(0.42, 1.35, 0.26), earR * CFrame.new(0, 0.05, -0.22), "Inner")
		r.eyes({ center = jelly, size = jellySize, spread = 0.38, height = 0.12, radius = 0.36, style = "Bean" })
		r.mouth({ center = jelly, size = jellySize, height = -0.12, width = 0.55, style = "Smile", skin = "Jelly" })
		r.cheeks({ center = jelly, size = jellySize, spread = 0.66, height = -0.04, width = 0.42 })
		r.ellipsoid("FootL", v3(0.95, 0.35, 1.25), at(-0.8, 0.16, -1.15, 0, 12, 0), "Feet")
		r.ellipsoid("FootR", v3(0.95, 0.35, 1.25), at(0.8, 0.16, -1.15, 0, -12, 0), "Feet")
	end,
}

-- Sproutle + Cactopus: a tortoise whose shell is a terracotta pot full of cacti.
ART.Cactortoise = {
	palette = {
		Pot = Color3.fromRGB(204, 112, 70),
		PotRim = Color3.fromRGB(234, 152, 102),
		Soil = Color3.fromRGB(96, 66, 48),
		Cactus = Color3.fromRGB(92, 186, 98),
		Rib = Color3.fromRGB(128, 216, 120),
		Skin = Color3.fromRGB(150, 212, 112),
		Flower = Color3.fromRGB(255, 104, 172),
		FlowerCenter = Color3.fromRGB(255, 218, 72),
		Spine = Color3.fromRGB(255, 248, 214),
		Accent = Color3.fromRGB(255, 104, 172),
		Egg = Color3.fromRGB(214, 150, 110),
	},
	build = function(r: Rig, _omit: Omit)
		local shell, shellSize = v3(0, 1.45, 0.35), v3(4.0, 2.5, 4.4)
		r.ellipsoid("Shell", shellSize, CFrame.new(shell), "Pot")
		r.ellipsoid("Rim", v3(4.5, 0.55, 4.9), at(0, 1.0, 0.35), "PotRim")
		r.ellipsoid("Band", v3(4.02, 0.34, 4.42), at(0, 1.62, 0.35), "PotRim")
		r.ellipsoid("Soil", v3(2.9, 0.4, 3.1), at(0, 2.6, 0.35), "Soil")
		-- A saguaro with one arm, a round barrel cactus and a flower on top.
		local main = v3(0.25, 3.7, 0.55)
		r.ellipsoid("Cactus", v3(1.15, 2.5, 1.15), CFrame.new(main), "Cactus")
		r.ellipsoid("RibA", v3(0.28, 2.2, 0.3), at(0.05, 3.7, -0.02), "Rib")
		r.ellipsoid("RibB", v3(0.28, 2.1, 0.3), at(0.72, 3.7, 0.25, 0, 40, 0), "Rib")
		r.rod("ArmA", v3(0.6, 3.25, 0.55), v3(1.25, 3.25, 0.55), 0.45, "Cactus")
		r.ellipsoid("ArmB", v3(0.48, 1.25, 0.48), at(1.28, 3.7, 0.55), "Cactus")
		r.ball("Barrel", 1.15, v3(-0.95, 3.0, 0.9), "Cactus")
		r.ellipsoid("BarrelRib", v3(0.25, 1.05, 0.3), at(-0.95, 3.0, 0.35), "Rib")
		local flower = v3(0.25, 4.95, 0.55)
		for i = 0, 4 do
			local a = math.rad(i * 72 + 18)
			r.ellipsoid(
				"Petal",
				v3(0.75, 0.2, 0.48),
				CFrame.new(flower + v3(math.cos(a) * 0.4, 0, math.sin(a) * 0.4))
					* CFrame.Angles(0, -a, 0)
					* CFrame.Angles(0, 0, math.rad(20)),
				"Flower"
			)
		end
		r.ball("FlowerCenter", 0.45, flower + v3(0, 0.1, 0), "FlowerCenter")
		r.ball("BarrelFlower", 0.42, v3(-0.95, 3.6, 0.9), "Flower")
		for i, spine in
			{
				{ v3(-0.32, 3.35, 0.4), v3(-0.62, 3.45, 0.3) },
				{ v3(0.55, 4.3, 0.2), v3(0.8, 4.5, 0.05) },
				{ v3(-1.45, 3.1, 0.75), v3(-1.72, 3.2, 0.68) },
			}
		do
			r.rod(`Spine{i}`, spine[1], spine[2], 0.07, "Spine")
		end
		local head, headSize = v3(0, 1.8, -2.5), v3(2.05, 1.95, 2.05)
		r.ellipsoid("Head", headSize, CFrame.new(head), "Skin")
		r.eyes({
			center = head,
			size = headSize,
			spread = 0.42,
			height = 0.22,
			radius = 0.32,
			style = "Googly",
			look = v3(0.12, 0.05, 0),
		})
		r.mouth({ center = head, size = headSize, height = -0.2, width = 0.45, style = "Smile", skin = "Skin" })
		r.cheeks({ center = head, size = headSize, spread = 0.74, height = -0.06, width = 0.34 })
		r.ball("HeadFlower", 0.48, v3(0.55, 2.75, -2.3), "Flower")
		for _, leg in { v3(-1.5, 0.45, -1.1), v3(1.5, 0.45, -1.1), v3(-1.5, 0.45, 1.65), v3(1.5, 0.45, 1.65) } do
			r.ellipsoid("Leg", v3(1.0, 0.9, 1.1), CFrame.new(leg), "Skin")
		end
	end,
}

-- Jellyknight + Disco Dodo: a jellyfish knight with a disco-ball helmet and neon shades.
ART.BoogieKnight = {
	palette = {
		Bell = Color3.fromRGB(190, 122, 242),
		Glow = Color3.fromRGB(238, 214, 255),
		Rim = Color3.fromRGB(150, 86, 216),
		Tentacle = Color3.fromRGB(214, 164, 250),
		Mirror = Color3.fromRGB(214, 220, 232),
		TileA = Color3.fromRGB(110, 230, 255),
		TileB = Color3.fromRGB(255, 110, 220),
		Plume = Color3.fromRGB(255, 64, 186),
		Frame = Color3.fromRGB(34, 32, 44),
		Lens = Color3.fromRGB(255, 64, 186),
		Shoe = Color3.fromRGB(255, 84, 168),
		Sole = Color3.fromRGB(250, 250, 255),
		Gold = Color3.fromRGB(255, 204, 60),
		Blade = Color3.fromRGB(110, 240, 255),
		Hilt = Color3.fromRGB(60, 50, 80),
		Accent = Color3.fromRGB(255, 64, 186),
		Egg = Color3.fromRGB(214, 178, 250),
	},
	babyLift = 0.2,
	build = function(r: Rig, _omit: Omit)
		local neon = { material = Enum.Material.Neon }
		local metal = { material = Enum.Material.Metal, reflectance = 0.3 }
		local bell, bellSize = v3(0, 3.7, 0), v3(3.8, 3.0, 3.8)
		r.ellipsoid("Bell", bellSize, CFrame.new(bell), "Bell", { reflectance = 0.08 })
		r.patch("BellGlow", bell, bellSize, v3(0.5, 0.6, -0.35), v3(0.9, 0.55, 0.16), "Glow", { transparency = 0.25 })
		r.ellipsoid("Rim", v3(4.1, 0.6, 4.1), at(0, 2.35, 0), "Rim")
		-- The helmet is a mirror ball.
		local ball, ballSize = v3(0, 5.15, 0.05), v3(2.6, 2.6, 2.6)
		r.ball("DiscoBall", 2.6, ball, "Mirror", metal)
		local tiles = {
			v3(-0.45, 0.3, -1),
			v3(0.45, 0.3, -1),
			v3(0, 0.85, -0.75),
			v3(-0.95, 0.45, -0.35),
			v3(0.95, 0.45, -0.35),
			v3(-0.55, 0.95, 0.35),
			v3(0.6, 0.9, 0.3),
		}
		for i, dir in tiles do
			local surface, normal = ModelKit.ellipsoidSurface(ball, ballSize, dir)
			r.block(
				`Tile{i}`,
				v3(0.5, 0.5, 0.1),
				ModelKit.facing(surface, normal),
				if i % 2 == 0 then "TileA" else "TileB",
				neon
			)
		end
		r.ellipsoid("PlumeA", v3(0.55, 1.2, 0.55), at(0, 6.55, 0.15, 15, 0, 0), "Plume", neon)
		r.ellipsoid("PlumeB", v3(0.48, 0.95, 0.48), at(0, 6.75, 0.8, 60, 0, 0), "Plume", neon)
		-- Neon shades instead of eyes.
		local face = faceAnchor(bell, bellSize, 0.34, 0.06, 0.38)
		for side = -1, 1, 2 do
			local lens = face.at
				* CFrame.new(side * face.size / 2, 0, 0.05)
				* CFrame.Angles(0, math.rad(90 - 12 * side), 0)
			r.cylinder("Frame", 0.12, 1.12, lens, "Frame")
			r.cylinder("Lens", 0.14, 0.92, lens * CFrame.new(0.04, 0, 0), "Lens", neon)
		end
		r.block("Bridge", v3(math.max(face.size - 0.9, 0.3), 0.12, 0.12), face.at * CFrame.new(0, 0.08, 0), "Frame")
		r.mouth({ center = bell, size = bellSize, height = -0.3, width = 0.6, style = "Grin", skin = "Bell" })
		r.cheeks({ center = bell, size = bellSize, spread = 0.66, height = -0.16, width = 0.45 })
		-- Tentacles; the two front ones wear platform shoes.
		for i = 0, 4 do
			local a = math.rad(i * 72 + 54)
			local dir = v3(math.cos(a), 0, math.sin(a))
			local base = v3(0, 2.3, 0) + dir * 1.45
			local mid = v3(0, 1.35, 0) + dir * 1.7
			local tip = v3(0, 0.55, 0) + dir * 1.45
			local cfA, lenA = ModelKit.between(base, mid)
			r.ellipsoid("Tentacle", v3(lenA + 0.35, 0.36, 0.36), cfA, "Tentacle")
			local cfB, lenB = ModelKit.between(mid, tip)
			r.ellipsoid("TentacleTip", v3(lenB + 0.3, 0.3, 0.3), cfB, "Tentacle")
			if i == 2 or i == 4 then
				local shoe = CFrame.new(tip.X, 0.3, tip.Z - 0.15)
				r.block("Shoe", v3(0.75, 0.42, 1.0), shoe, "Shoe")
				r.block("Sole", v3(0.8, 0.14, 1.05), shoe * CFrame.new(0, -0.24, 0), "Sole")
			end
		end
		-- A neon sword.
		local sword = at(2.35, 2.0, -0.6, 0, 0, -8)
		r.block("Blade", v3(0.16, 2.3, 0.42), sword * CFrame.new(0, 1.25, 0), "Blade", neon)
		r.block("Guard", v3(0.9, 0.18, 0.3), sword * CFrame.new(0, 0.05, 0), "Gold", metal)
		r.rod(
			"Grip",
			(sword * CFrame.new(0, -0.02, 0)).Position,
			(sword * CFrame.new(0, -0.68, 0)).Position,
			0.2,
			"Hilt"
		)
	end,
}

-- Blobbit + Moonmoth: a perfectly round, extremely fluffy moth on a little jelly puddle.
ART.Mothball = {
	palette = {
		Fluff = Color3.fromRGB(248, 244, 255),
		Shade = Color3.fromRGB(228, 222, 248),
		Wing = Color3.fromRGB(152, 172, 255),
		Moon = Color3.fromRGB(255, 238, 150),
		Antenna = Color3.fromRGB(96, 92, 128),
		Jelly = Color3.fromRGB(122, 196, 255),
		Accent = Color3.fromRGB(152, 172, 255),
		Egg = Color3.fromRGB(226, 230, 255),
	},
	babyLift = 0.2,
	build = function(r: Rig, _omit: Omit)
		local body, bodySize = v3(0, 2.25, 0), v3(4.0, 4.0, 4.0)
		r.ellipsoid("Puddle", v3(3.6, 0.32, 3.4), at(0, 0.14, 0.1), "Jelly", { reflectance = 0.1 })
		r.ball("Body", 4.0, body, "Fluff")
		local tufts = {
			v3(0, 1, 0.15),
			v3(0.8, 0.65, 0.25),
			v3(-0.8, 0.65, 0.25),
			v3(1, 0.05, 0.4),
			v3(-1, 0.05, 0.4),
			v3(0.5, 0.3, 0.95),
			v3(-0.5, 0.3, 0.95),
		}
		for i, dir in tufts do
			r.ball(`Tuft{i}`, 1.15, body + dir.Unit * 1.72, if i % 2 == 0 then "Shade" else "Fluff")
		end
		r.eyes({ center = body, size = bodySize, spread = 0.36, height = 0.16, radius = 0.5, style = "Bean" })
		r.mouth({ center = body, size = bodySize, height = -0.08, width = 0.42, style = "Smile", skin = "Fluff" })
		r.cheeks({ center = body, size = bodySize, spread = 0.62, height = -0.02, width = 0.55 })
		for side = -1, 1, 2 do
			local a, b = v3(0.45 * side, 4.05, -0.35), v3(1.3 * side, 5.2, -0.15)
			r.rod("Antenna", a, b, 0.12, "Antenna")
			local cf, len = ModelKit.between(a, b)
			r.ellipsoid("Feather", v3(len * 0.85, 0.55, 0.1), cf * CFrame.new(len * 0.1, 0, 0), "Wing")
		end
		local neon = { material = Enum.Material.Neon }
		for side = -1, 1, 2 do
			local upper = at(1.65 * side, 3.05, 1.45, 0, -28 * side, 18 * side)
			r.ellipsoid("WingUpper", v3(2.7, 2.0, 0.14), upper, "Wing")
			r.ellipsoid("Moon", v3(0.85, 0.85, 0.18), upper * CFrame.new(0.4 * side, 0.12, 0), "Moon", neon)
			local lower = at(1.4 * side, 1.8, 1.55, 0, -32 * side, -18 * side)
			r.ellipsoid("WingLower", v3(1.9, 1.4, 0.14), lower, "Wing")
		end
	end,
}

-- Pebblepup + Volcanowl: a dog of cooling lava with glowing cracks and a smoking back.
ART.Magmutt = {
	palette = {
		Rock = Color3.fromRGB(78, 68, 74),
		RockLight = Color3.fromRGB(108, 96, 102),
		Muzzle = Color3.fromRGB(140, 122, 118),
		Lava = Color3.fromRGB(255, 112, 30),
		Iris = Color3.fromRGB(255, 196, 48),
		Nose = Color3.fromRGB(36, 30, 36),
		Tongue = Color3.fromRGB(255, 140, 80),
		Smoke = Color3.fromRGB(150, 150, 158),
		Rim = Color3.fromRGB(56, 48, 54),
		Accent = Color3.fromRGB(255, 112, 30),
		Egg = Color3.fromRGB(96, 84, 90),
	},
	build = function(r: Rig, _omit: Omit)
		local neon = { material = Enum.Material.Neon }
		local body, bodySize = v3(0, 1.75, 0.55), v3(2.9, 2.3, 3.7)
		r.ellipsoid("Body", bodySize, CFrame.new(body), "Rock")
		r.patch("SpotA", body, bodySize, v3(0.75, 0.55, 0.35), v3(1.2, 0.9, 0.3), "RockLight")
		r.patch("SpotB", body, bodySize, v3(-0.6, 0.6, 0.85), v3(0.9, 0.7, 0.3), "RockLight")
		for side = -1, 1, 2 do
			local a = ModelKit.ellipsoidSurface(body, bodySize, v3(side, 0.55, -0.45))
			local b = ModelKit.ellipsoidSurface(body, bodySize, v3(side, 0.15, 0.1))
			local c = ModelKit.ellipsoidSurface(body, bodySize, v3(side, 0.35, 0.7))
			r.rod("CrackA", a, b, 0.15, "Lava", neon)
			r.rod("CrackB", b, c, 0.15, "Lava", neon)
		end
		-- A little volcano on its back.
		local crater = ModelKit.ellipsoidSurface(body, bodySize, v3(0, 1, 0.25))
		r.ellipsoid("Crater", v3(1.45, 0.55, 1.45), CFrame.new(crater + v3(0, 0.05, 0)), "Rim")
		r.ellipsoid("LavaPool", v3(1.0, 0.22, 1.0), CFrame.new(crater + v3(0, 0.27, 0)), "Lava", neon)
		local smoke = { transparency = 0.15 }
		r.ball("SmokeA", 0.7, crater + v3(0.1, 0.85, 0.1), "Smoke", smoke)
		r.ball("SmokeB", 0.5, crater + v3(-0.15, 1.4, 0.25), "Smoke", smoke)
		for _, leg in { v3(-0.85, 0.55, -0.45), v3(0.85, 0.55, -0.45), v3(-0.85, 0.55, 1.6), v3(0.85, 0.55, 1.6) } do
			r.ellipsoid("Leg", v3(0.95, 1.2, 1.05), CFrame.new(leg), "RockLight")
		end
		local tail = at(0, 2.8, 2.35, -38, 0, 0)
		r.ellipsoid("Tail", v3(0.55, 1.4, 0.55), tail, "Rock")
		r.ball("Ember", 0.5, (tail * CFrame.new(0, 0.72, 0)).Position, "Lava", neon)
		local head = at(0, 3.3, -1.15, 0, 0, 7)
		local headSize = v3(3.0, 2.7, 2.6)
		r.ellipsoid("Head", headSize, head, "Rock")
		local muzzle = head * CFrame.new(0, -0.62, -1.05)
		r.ellipsoid("Muzzle", v3(1.75, 1.15, 1.35), muzzle, "Muzzle")
		r.ellipsoid("Nose", v3(0.72, 0.5, 0.5), muzzle * CFrame.new(0, 0.32, -0.6), "Nose", { reflectance = 0.1 })
		r.ellipsoid(
			"Tongue",
			v3(0.5, 0.18, 0.75),
			muzzle * CFrame.new(0.28, -0.52, -0.42) * CFrame.Angles(math.rad(28), 0, 0),
			"Tongue"
		)
		for side = -1, 1, 2 do
			local ear = head * CFrame.new(1.48 * side, -0.35, 0.15) * CFrame.Angles(0, 0, math.rad(18 * side))
			r.ellipsoid("Ear", v3(0.62, 1.8, 1.15), ear, "RockLight")
			r.ellipsoid("EarGlow", v3(0.14, 1.0, 0.36), ear * CFrame.new(0.27 * side, -0.05, 0), "Lava", neon)
		end
		local headLocal = head.Position
		local brow = ModelKit.ellipsoidSurface(headLocal, headSize, head.Rotation * v3(0.25, 1, -0.35))
		local browEnd = ModelKit.ellipsoidSurface(headLocal, headSize, head.Rotation * v3(-0.15, 1, 0.2))
		r.rod("HeadCrack", brow, browEnd, 0.13, "Lava", neon)
		r.eyes({
			center = headLocal,
			size = headSize,
			spread = 0.36,
			height = 0.3,
			radius = 0.4,
			style = "Googly",
			white = "Iris",
			look = v3(0.1, 0.05, 0),
			forward = head.LookVector,
		})
	end,
}

-- Toastshark + Croissaur: a croissant dinosaur with toast back plates and a fried egg hat.
ART.Brunchasaurus = {
	palette = {
		Crust = Color3.fromRGB(222, 146, 58),
		CrustLight = Color3.fromRGB(246, 196, 112),
		Toast = Color3.fromRGB(244, 210, 148),
		ToastCrust = Color3.fromRGB(176, 108, 48),
		Mouth = Color3.fromRGB(110, 40, 44),
		Teeth = Color3.fromRGB(255, 255, 250),
		EggWhite = Color3.fromRGB(255, 252, 244),
		Yolk = Color3.fromRGB(255, 190, 40),
		Accent = Color3.fromRGB(176, 108, 48),
		Egg = Color3.fromRGB(246, 212, 146),
	},
	build = function(r: Rig, _omit: Omit)
		r.ellipsoid("Chest", v3(3.0, 3.0, 2.0), at(0, 3.3, -0.75, -15, 0, 0), "CrustLight")
		r.ellipsoid("Belly", v3(3.4, 3.2, 2.2), at(0, 3.0, 0.5), "Crust")
		r.ellipsoid("Hip", v3(3.0, 2.7, 1.9), at(0, 3.0, 1.7, 15, 0, 0), "CrustLight")
		r.ellipsoid("TailA", v3(2.2, 2.0, 1.7), at(0, 2.55, 2.7, 30, 0, 0), "Crust")
		r.ellipsoid("TailB", v3(1.4, 1.3, 1.5), at(0, 2.0, 3.4, 45, 0, 0), "CrustLight")
		r.ellipsoid("TailC", v3(0.8, 0.8, 1.2), at(0, 1.45, 3.9, 55, 0, 0), "Crust")
		-- Slices of toast standing up along the spine like stegosaurus plates.
		local plates = {
			{ z = -0.15, y = 5.0, s = 1.25, tilt = 10 },
			{ z = 1.05, y = 5.05, s = 1.35, tilt = -5 },
			{ z = 2.2, y = 4.35, s = 1.05, tilt = -20 },
		}
		for i, plate in plates do
			local cf = at(0, plate.y, plate.z, plate.tilt, 0, 0)
			local s2 = plate.s
			r.block(`Plate{i}`, v3(0.3, 1.25 * s2, 1.3 * s2), cf, "ToastCrust")
			r.ellipsoid(`PlateTop{i}`, v3(0.3, 0.75 * s2, 1.55 * s2), cf * CFrame.new(0, 0.62 * s2, 0), "ToastCrust")
			r.block(`Bread{i}`, v3(0.34, 1.1 * s2, 1.08 * s2), cf * CFrame.new(0, 0.02, 0), "Toast")
			r.ellipsoid(`BreadTop{i}`, v3(0.34, 0.6 * s2, 1.3 * s2), cf * CFrame.new(0, 0.58 * s2, 0), "Toast")
		end
		local head, headSize = v3(0, 5.1, -2.0), v3(2.4, 2.0, 2.8)
		r.ellipsoid("Head", headSize, CFrame.new(head), "Crust")
		r.ellipsoid("Mouth", v3(1.9, 0.7, 2.1), at(0, 4.6, -2.35), "Mouth")
		r.ellipsoid("Jaw", v3(2.0, 0.75, 2.3), at(0, 4.25, -2.25, 12, 0, 0), "CrustLight")
		for _, x in { -0.75, -0.38, 0, 0.38, 0.75 } do
			local z = -3.22 + math.abs(x) * 0.45
			r.wedge("Tooth", v3(0.22, 0.34, 0.22), at(x, 4.62, z, 180, 0, 0), "Teeth")
		end
		r.eyes({
			center = head,
			size = headSize,
			spread = 0.55,
			height = 0.45,
			radius = 0.32,
			style = "Googly",
			look = v3(0.1, 0.05, 0),
		})
		-- A fried egg worn like a hat.
		r.ellipsoid("EggWhite", v3(1.9, 0.22, 1.75), at(0.1, 6.1, -1.85, 0, 0, -6), "EggWhite")
		r.ellipsoid("Yolk", v3(0.8, 0.45, 0.8), at(0.12, 6.28, -1.95), "Yolk", { reflectance = 0.1 })
		r.ellipsoid("ArmL", v3(0.35, 0.35, 0.95), at(-1.25, 3.55, -1.55, 30, 0, 0), "Crust")
		r.ellipsoid("ArmR", v3(0.35, 0.35, 0.95), at(1.25, 3.55, -1.55, 30, 0, 0), "Crust")
		r.ellipsoid("LegL", v3(1.25, 2.2, 1.5), at(-1.15, 1.4, 0.75), "Crust")
		r.ellipsoid("LegR", v3(1.25, 2.2, 1.5), at(1.15, 1.4, 0.75), "Crust")
		r.ellipsoid("FootL", v3(1.25, 0.5, 1.75), at(-1.2, 0.25, 0.25), "CrustLight")
		r.ellipsoid("FootR", v3(1.25, 0.5, 1.75), at(1.2, 0.25, 0.25), "CrustLight")
	end,
}

-- Cosmigoose + Glitchling: a voxel space goose that clipped through reality.
ART.GooseExe = {
	palette = {
		Primary = Color3.fromRGB(56, 40, 120),
		Nebula = Color3.fromRGB(152, 76, 226),
		Pink = Color3.fromRGB(236, 96, 196),
		Cyan = Color3.fromRGB(0, 255, 255),
		Red = Color3.fromRGB(255, 46, 90),
		Beak = Color3.fromRGB(255, 160, 52),
		Feet = Color3.fromRGB(255, 146, 44),
		Black = Color3.fromRGB(16, 14, 24),
		White = Color3.fromRGB(250, 250, 255),
		Star = Color3.fromRGB(255, 255, 236),
		Planet = Color3.fromRGB(120, 220, 255),
		Ring = Color3.fromRGB(255, 204, 120),
		Yellow = Color3.fromRGB(255, 230, 40),
		Accent = Color3.fromRGB(0, 255, 255),
		Egg = Color3.fromRGB(70, 40, 140),
	},
	build = function(r: Rig, _omit: Omit)
		local neon = { material = Enum.Material.Neon }
		local ghost = { material = Enum.Material.Neon, transparency = 0.72, castShadow = false }
		r.block("Body", v3(3.2, 2.4, 3.8), at(0, 2.05, 0.6), "Primary")
		r.block("Back", v3(2.6, 0.6, 3.0), at(0, 3.5, 0.75), "Primary")
		r.block("GhostCyan", v3(3.2, 2.4, 3.8), at(0.22, 2.11, 0.65), "Cyan", ghost)
		r.block("GhostRed", v3(3.2, 2.4, 3.8), at(-0.22, 1.99, 0.55), "Red", ghost)
		r.block("NebulaL", v3(0.08, 1.2, 2.4), at(-1.62, 2.25, 0.75), "Nebula")
		r.block("NebulaR", v3(0.08, 1.2, 2.4), at(1.62, 2.25, 0.75), "Nebula")
		r.block("Stripe", v3(1.8, 0.08, 0.9), at(0.3, 3.82, 1.1), "Pink")
		r.block("Tail", v3(1.5, 0.9, 1.1), at(0, 3.05, 2.85, -25, 0, 0), "Primary")
		r.block("WingL", v3(0.5, 1.5, 2.8), at(-1.85, 2.45, 0.85), "Nebula")
		r.block("WingR", v3(0.5, 1.5, 2.8), at(1.85, 2.45, 0.85), "Nebula")
		-- The neck didn't load properly.
		r.block("NeckA", v3(1.15, 1.15, 1.15), at(0.14, 3.95, -0.95), "Primary")
		r.block("NeckB", v3(1.05, 1.05, 1.05), at(-0.24, 4.9, -1.2), "Primary")
		r.block("NeckC", v3(1.0, 1.0, 1.0), at(0.12, 5.8, -1.3), "Primary")
		r.block("Head", v3(1.6, 1.4, 2.0), at(0, 6.65, -1.55), "Primary")
		r.block("Beak", v3(0.9, 0.5, 1.2), at(0, 6.4, -3.1), "Beak")
		r.block("Knob", v3(0.5, 0.5, 0.45), at(0, 6.8, -2.68), "Black")
		local eyeRadius = 0.3 * r.eyeBoost
		r.eye("L", ModelKit.facing(v3(-0.48, 6.95, -2.56), v3(0, 0, -1)), eyeRadius, "Pixel", {
			white = "White",
			color = "Black",
			look = v3(0.35, 0, 0),
		})
		r.eye("R", ModelKit.facing(v3(0.48, 6.95, -2.56), v3(0, 0, -1)), eyeRadius, "Pixel", {
			white = "White",
			color = "Black",
			look = v3(-0.2, 0, 0),
		})
		for side = -1, 1, 2 do
			r.block("Leg", v3(0.3, 0.7, 0.3), at(0.7 * side, 0.55, 0.3), "Feet")
			r.block("Foot", v3(0.95, 0.3, 1.25), at(0.72 * side, 0.15, -0.15), "Feet")
		end
		r.block("Planet", v3(0.8, 0.8, 0.8), at(1.35, 7.75, -1.2, 20, 30, 10), "Planet")
		r.cylinder("PlanetRing", 0.07, 1.6, at(1.35, 7.75, -1.2, 20, 0, 110), "Ring")
		r.block("Alert", v3(0.26, 0.75, 0.26), at(-1.0, 8.05, -1.3), "Yellow", neon)
		r.block("AlertDot", v3(0.26, 0.26, 0.26), at(-1.0, 7.42, -1.3), "Yellow", neon)
		r.block("BitA", v3(0.45, 0.45, 0.45), at(2.25, 4.3, 0.4, 20, 30, 0), "Cyan", neon)
		r.block("BitB", v3(0.35, 0.35, 0.35), at(-2.2, 3.4, -0.7, 0, 25, 15), "Pink", neon)
		r.block("StarA", v3(0.22, 0.22, 0.22), at(1.66, 2.9, 0.1), "Star", neon)
		r.block("StarB", v3(0.18, 0.18, 0.18), at(-1.66, 1.6, 1.5), "Star", neon)
	end,
}

-- Dragonroll + Burritoad: a toad peeking out of a sushi burrito, with dragon horns.
ART.Sushirrito = {
	palette = {
		Nori = Color3.fromRGB(36, 52, 44),
		Rice = Color3.fromRGB(250, 250, 244),
		Salmon = Color3.fromRGB(255, 138, 98),
		SalmonStripe = Color3.fromRGB(255, 214, 196),
		Cucumber = Color3.fromRGB(110, 200, 90),
		Avocado = Color3.fromRGB(204, 226, 118),
		Toad = Color3.fromRGB(112, 192, 92),
		Chin = Color3.fromRGB(222, 242, 172),
		Horn = Color3.fromRGB(252, 238, 200),
		Whisker = Color3.fromRGB(60, 40, 40),
		Wasabi = Color3.fromRGB(146, 210, 82),
		Ginger = Color3.fromRGB(255, 176, 176),
		Lettuce = Color3.fromRGB(126, 222, 92),
		Accent = Color3.fromRGB(255, 138, 98),
		Egg = Color3.fromRGB(70, 90, 78),
	},
	build = function(r: Rig, _omit: Omit)
		r.cylinder("Wrap", 4.0, 3.1, at(0, 1.6, 0.95, 0, 90, 0), "Nori")
		r.cylinder("RiceCollar", 0.45, 3.24, at(0, 1.6, -1.0, 0, 90, 0), "Rice")
		-- The cut end at the back shows rice and fillings.
		r.cylinder("RiceEnd", 0.12, 2.8, at(0, 1.6, 2.97, 0, 90, 0), "Rice")
		r.cylinder("SalmonEnd", 0.16, 1.0, at(-0.45, 1.85, 2.99, 0, 90, 0), "Salmon")
		r.cylinder("CucumberEnd", 0.16, 0.7, at(0.55, 1.95, 2.99, 0, 90, 0), "Cucumber")
		r.cylinder("AvocadoEnd", 0.16, 0.75, at(0.15, 1.1, 2.99, 0, 90, 0), "Avocado")
		-- A blanket of salmon over the top, nigiri style.
		r.ellipsoid("SalmonTop", v3(2.1, 0.45, 3.3), at(0, 3.12, 1.05), "Salmon")
		r.ellipsoid("StripeA", v3(2.05, 0.2, 0.22), at(0, 3.3, 0.55), "SalmonStripe")
		r.ellipsoid("StripeB", v3(2.05, 0.2, 0.22), at(0, 3.3, 1.45), "SalmonStripe")
		r.ellipsoid("Wasabi", v3(0.75, 0.5, 0.75), at(0.55, 3.45, 2.2), "Wasabi")
		r.ball("WasabiTip", 0.36, v3(0.58, 3.72, 2.2), "Wasabi")
		r.ellipsoid("Ginger", v3(0.9, 0.12, 0.7), at(-0.55, 3.45, 2.3, 0, 25, 20), "Ginger")
		-- The toad pokes out of the front.
		local head, headSize = v3(0, 2.05, -1.8), v3(2.6, 2.1, 2.3)
		r.ellipsoid("Head", headSize, CFrame.new(head), "Toad")
		r.ellipsoid("Chin", v3(2.0, 1.1, 1.8), at(0, 1.5, -2.1), "Chin")
		local eyeRadius = 0.42 * r.eyeBoost
		for side = -1, 1, 2 do
			local bump = v3(0.72 * side, 3.0, -1.9)
			r.ball("EyeBump", 1.1, bump, "Toad")
			local dir = v3(0.2 * side, 0.35, -0.92).Unit
			r.eye(if side < 0 then "L" else "R", ModelKit.facing(bump + dir * 0.3, dir), eyeRadius, "Googly", {
				look = if side < 0 then v3(0.2, 0.1, 0) else v3(0.1, 0.25, 0),
			})
			r.ellipsoid("Horn", v3(0.34, 1.15, 0.34), at(0.42 * side, 3.4, -1.35, -35, 0, -12 * side), "Horn")
			r.rod("Whisker", v3(0.95 * side, 1.85, -2.6), v3(1.65 * side, 2.2, -2.55), 0.09, "Whisker")
			r.ellipsoid("Lettuce", v3(1.2, 0.5, 0.65), at(1.2 * side, 2.55, -1.3, 0, 0, -38 * side), "Lettuce")
			r.ellipsoid("Hand", v3(0.68, 0.42, 0.58), at(1.25 * side, 1.95, -1.65), "Toad")
		end
		r.mouth({ center = head, size = headSize, height = -0.12, width = 1.5, style = "Smile", skin = "Toad" })
		r.cheeks({ center = head, size = headSize, spread = 0.7, height = 0, width = 0.42 })
	end,
}

---------------------------------------------------------------------------
-- Eggs and baby shells
---------------------------------------------------------------------------

-- What a creature is built from: its own art, or (fallback hybrids) a lead and a donor.
type Plan = { art: Art, donor: Art? }

local function planFor(def: CreatureData.CreatureDef): Plan
	local art = ART[def.modelName]
	if art then
		return { art = art }
	end
	local parents = def.parents
	assert(def.hybrid and parents, `CreatureModels: no art for "{def.modelName}"`)
	local lead, donor = CreatureData.get(parents[1]), CreatureData.get(parents[2])
	assert(lead and donor, `CreatureModels: hybrid "{def.id}" has unknown parents`)
	local leadArt, donorArt = ART[lead.modelName], ART[donor.modelName]
	assert(leadArt and donorArt, `CreatureModels: no art for the parents of "{def.id}"`)
	return { art = leadArt, donor = donorArt }
end

-- Egg shell colors. Hybrid eggs use the lead's shell with the donor's spots.
local function eggColors(plan: Plan): (Color3, Color3)
	local palette = plan.art.palette
	local base = palette.Egg or palette.Primary or Color3.fromRGB(240, 240, 240)
	local spotPalette = if plan.donor then plan.donor.palette else palette
	local spot = spotPalette.Accent or spotPalette.Secondary or ModelKit.shade(base, 0.7)
	return base, spot
end

local function buildEgg(r: Rig, def: CreatureData.CreatureDef, plan: Plan)
	local base, spot = eggColors(plan)
	local rarity = Rarity.get(def.rarity)
	local lift = 0.45
	-- Egg = sphere bottom + taller ellipsoid top, which meet smoothly at the equator.
	local equator = lift + EGG_SIZE.X / 2
	local bottomSize = v3(EGG_SIZE.X, EGG_SIZE.X, EGG_SIZE.Z)
	local topSize = v3(EGG_SIZE.X, (EGG_SIZE.Y - EGG_SIZE.X / 2) * 2, EGG_SIZE.Z)
	r.ellipsoid("EggBottom", bottomSize, at(0, equator, 0), base)
	r.ellipsoid("EggTop", topSize, at(0, equator, 0), base)
	local spots = {
		v3(0.55, 0.6, -0.6),
		v3(-0.75, 0.15, -0.6),
		v3(0.9, -0.05, 0.45),
		v3(-0.5, 0.7, 0.65),
		v3(0.05, -0.3, -1),
		v3(-0.9, -0.2, 0.3),
		v3(0.25, 0.25, 1),
	}
	for i, dir in spots do
		local size = if i % 2 == 0 then v3(0.9, 0.78, 0.24) else v3(0.62, 0.55, 0.22)
		local surface, normal = ModelKit.ellipsoidSurface(v3(0, equator, 0), topSize, dir)
		if dir.Y < 0 then
			surface, normal = ModelKit.ellipsoidSurface(v3(0, equator, 0), bottomSize, dir)
		end
		r.ellipsoid(`Spot{i}`, size, ModelKit.facing(surface - normal * 0.05, normal), spot)
	end
	-- Egg cup in the rarity color.
	r.disc("Cup", 2.1, 0.55, v3(0, 0.28, 0), rarity.dark)
	r.disc("Glow", 2.5, 0.14, v3(0, 0.07, 0), rarity.color, { material = Enum.Material.Neon })
	if rarity.rank >= Rarity.rank("Legendary") then
		-- Fancy eggs get a glowing band around the middle (sparkle particles are added client-side).
		r.ellipsoid("Band", v3(EGG_SIZE.X + 0.08, 0.32, EGG_SIZE.Z + 0.08), at(0, equator + 0.35, 0), rarity.color, {
			material = Enum.Material.Neon,
		})
	end
	if def.rarity == "Secret" then
		r.rod("CrackA", v3(-0.4, 2.7, -1.12), v3(0.15, 2.2, -1.2), 0.1, rarity.color, { material = Enum.Material.Neon })
		r.rod("CrackB", v3(0.15, 2.2, -1.2), v3(-0.1, 1.7, -1.28), 0.1, rarity.color, { material = Enum.Material.Neon })
	end
end

local function buildShell(r: Rig, plan: Plan)
	local base, spot = eggColors(plan)
	-- A hatched eggshell cup: rounded bottom, straight wall, darker hollow inside and a zig-zag rim.
	r.ellipsoid("ShellBottom", v3(3.1, 0.9, 3.1), at(0, 0.32, 0), base)
	r.disc("ShellWall", 3.1, 0.5, v3(0, 0.6, 0), base)
	r.disc("ShellInside", 2.86, 0.06, v3(0, 0.84, 0), ModelKit.shade(base, 0.78))
	for i = 0, 7 do
		local angle = i * math.pi / 4 + math.pi / 8
		local pos = v3(math.cos(angle) * 1.47, 0.84, math.sin(angle) * 1.47)
		r.block(
			`Shard{i}`,
			v3(0.12, 0.42, 0.42),
			CFrame.new(pos) * CFrame.Angles(0, -angle, 0) * CFrame.Angles(math.rad(45), 0, 0),
			base
		)
	end
	r.patch("ShellSpotA", v3(0, 0.6, 0), v3(3.1, 1.4, 3.1), v3(-1, 0, 0.5), v3(0.5, 0.36, 0.14), spot)
	r.patch("ShellSpotB", v3(0, 0.6, 0), v3(3.1, 1.4, 3.1), v3(1, 0, 0.6), v3(0.42, 0.32, 0.14), spot)
end

---------------------------------------------------------------------------
-- Creature bodies (originals, named hybrids and fallback hybrids)
---------------------------------------------------------------------------

-- Builds the creature itself (no eggshell) into `rig`, in adult units. A fallback hybrid
-- is the lead's body with whatever sits in the donor's slot left out, plus the donor's
-- signature piece on the lead's matching anchor, resized to fit and in the donor's colors.
local function buildCreature(rig: Rig, plan: Plan)
	local donor = plan.donor
	if not donor then
		plan.art.build(rig, NO_OMIT)
		return
	end
	local trait = donor.trait
	local anchors = plan.art.anchors
	assert(trait and anchors, "CreatureModels: fallback hybrids need a donor trait and lead anchors")
	local anchor = anchors[trait.slot]
	assert(anchor, `CreatureModels: lead has no {trait.slot} anchor`)
	plan.art.build(rig, { [trait.slot] = true })
	local scale = math.clamp(anchor.size / trait.size, 0.45, 1.5)
	trait.build(rig.sub(anchor.at, scale, donor.palette, trait.at:Inverse()))
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CreatureModels.has(modelName: string): boolean
	return ART[modelName] ~= nil
end

function CreatureModels.palette(modelName: string): Palette?
	local art = ART[modelName]
	return if art then art.palette else nil
end

function CreatureModels.build(creatureId: string, options: BuildOptions?): Model
	local def = CreatureData.get(creatureId)
	assert(def, `CreatureModels.build: unknown creature "{creatureId}"`)
	local plan = planFor(def)
	local art = plan.art
	local opts: BuildOptions = options or {}
	local stage: Stage = opts.stage or "Adult"
	local origin = opts.origin or CFrame.new()
	local scale = opts.scale or 1

	local model = Instance.new("Model")
	model.Name = if plan.donor then def.displayName else def.modelName
	model:SetAttribute("CreatureId", def.id)
	model:SetAttribute("Stage", stage)
	model:SetAttribute("Rarity", def.rarity)

	local parts: { BasePart } = {}
	if stage == "Egg" then
		local rig = ModelKit.newRig(model, origin, scale, art.palette)
		buildEgg(rig, def, plan)
		parts = rig.parts
	elseif stage == "Baby" then
		local shellRig = ModelKit.newRig(model, origin, scale, art.palette)
		buildShell(shellRig, plan)
		local lift = (art.babyLift or 0.7) * scale
		local rig =
			ModelKit.newRig(model, origin * CFrame.new(0, lift, 0), BABY_SCALE * scale, art.palette, BABY_EYE_BOOST)
		buildCreature(rig, plan)
		parts = shellRig.parts
		for _, part in rig.parts do
			table.insert(parts, part)
		end
	else
		local rig = ModelKit.newRig(model, origin, scale, art.palette)
		buildCreature(rig, plan)
		parts = rig.parts
	end

	ModelKit.finishModel(model, parts, origin)
	return model
end

return table.freeze(CreatureModels)
