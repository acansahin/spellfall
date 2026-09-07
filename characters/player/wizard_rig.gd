class_name WizardRig
extends Node3D

## A hooded wizard with a staff, built out of primitives and animated by hand.
##
## It replaces a capsule. The capsule was honest placeholder art and it stopped being enough
## the moment the ground and the lava had textures on them: a painted world with a pill
## standing in it reads as unfinished in a way that a painted world with a walking figure does
## not, however simple the figure is.
##
## BUILT IN CODE, not modelled, and that is the same decision the rest of this project has
## already made twice - every sound is synthesised in `audio/`, every spell icon is a vector
## shape in `vfx/spell_glyph.gd`. The reason here is specific though, and it is a measurement
## rather than a preference: **the wizard is about a twelfth of the screen's height**, which on
## a phone is sixty pixels. At sixty pixels a silhouette and a walk cycle carry the whole
## reading and polygon count carries none of it. A downloaded character model would be more
## detail delivered to a size that cannot show it, and it would arrive with a licence, an
## import pipeline and a rig this repo would then have to keep working.
##
## What it IS made of matters more than how many parts there are: a hood and a hem, because
## those two are the silhouette; legs that swing, because motion at this size is what says
## "walking" rather than "sliding"; and a staff, because the staff is the only part that says
## which way this wizard is facing at a glance.

## Metres the body travels in one full cycle - two steps.
##
## The stride, not the frame rate, is what keeps feet from skating: the cycle is advanced by
## DISTANCE COVERED, so a wizard slowed to a crawl takes slow steps of the same length rather
## than fast steps that go nowhere. At the map's 1.641 m/s this comes out at about 1.1 cycles
## a second, which is an ordinary walking cadence.
const STRIDE := 1.5

## How far a leg swings at full speed, in radians. 0.58 is about 33 degrees.
##
## Larger than a real walk, deliberately. At sixty pixels a true 20-degree swing is three
## pixels of foot travel and reads as a slide; the exaggeration is what makes the motion
## survive the size, and it is the same reason the map's own units over-swing.
const LEG_SWING := 0.58

## How far the free arm counter-swings. Less than the legs, as a real arm does.
const ARM_SWING := 0.30

## How high the body rises on each step, in metres. Twice a cycle, because both feet do it.
const BOB := 0.035

## Seconds a cast pose takes to reach and to fall back from.
const CAST_RISE := 0.10
const CAST_FALL := 0.40

## The wizard's own colour. The level sets it per side; everything cloth-coloured takes it and
## everything skin-, wood- or metal-coloured deliberately does not, so four wizards in four
## tints are still four wizards rather than four colours.
var tint := Color(0.31, 0.68, 0.93)

var _phase := 0.0
var _cast := 0.0
var _idle := 0.0
var _lean := 0.0

# Joints. Rotating a parent carries its children, which is the whole of the rig: swinging
# `_hip_l` swings the shin and the boot with it, and nothing has to be posed twice.
var _root: Node3D
var _torso: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _hem: Node3D
var _head: Node3D
var _orb: MeshInstance3D

var _cloth: StandardMaterial3D
var _skin: StandardMaterial3D
var _wood: StandardMaterial3D
var _glow: StandardMaterial3D


func _ready() -> void:
	_build()
	set_tint(tint)


## Recolours the cloth. Called by the level once, per side.
func set_tint(colour: Color) -> void:
	tint = colour
	if _cloth == null:
		return
	_cloth.albedo_color = colour
	# The hood reads as the same garment only if it is the same hue; a darker value is what
	# makes it read as a separate layer rather than as a paint mistake.
	pass


## Poses the figure for this frame.
##
## `speed` is the wizard's horizontal speed in m/s and `top_speed` what it can manage, so the
## rig can tell a crawl from a sprint without knowing anything about the movement rules.
## `casting` is true on the frame a spell leaves.
func animate(delta: float, speed: float, top_speed: float, casting: bool) -> void:
	if _root == null:
		return
	if casting:
		_cast = 1.0
	# Two different rates, because a pose that snaps up and snaps back has no weight to it.
	if _cast > 0.0:
		_cast = maxf(0.0, _cast - delta / (CAST_FALL if _cast < 0.999 else CAST_RISE))

	var moving := speed > 0.05
	# Advance by DISTANCE, not by time. See STRIDE.
	_phase = fposmod(_phase + (speed * delta / STRIDE) * TAU, TAU)
	_idle += delta
	var drive: float = clampf(speed / maxf(top_speed, 0.001), 0.0, 1.4)
	# A wizard that has stopped keeps its legs where they are rather than freezing mid-stride:
	# the swing is scaled to nothing, so the pose relaxes toward standing on its own.
	var swing := LEG_SWING * drive
	var arm := ARM_SWING * drive

	var left := sin(_phase)
	var right := sin(_phase + PI)

	_hip_l.rotation.x = left * swing
	_hip_r.rotation.x = right * swing
	# A knee only bends one way. `max(0, ...)` is what stops the shin folding forwards through
	# the thigh, which is the single thing that makes a hand-animated walk look wrong.
	_knee_l.rotation.x = -maxf(0.0, -cos(_phase)) * swing * 1.6
	_knee_r.rotation.x = -maxf(0.0, -cos(_phase + PI)) * swing * 1.6

	# The free arm counter-swings the leg on its own side. The staff arm mostly does not - it
	# is carrying something - which is what makes the two sides read differently while walking.
	_shoulder_l.rotation.x = right * arm
	var carry := left * arm * 0.35
	# The cast overrides it: the staff comes up and forward, and it comes up fast.
	var raised: float = _ease(_cast)
	_shoulder_r.rotation.x = lerpf(carry, -1.55, raised)
	# ADDED to the resting angle the arms are built with, not assigned over it - assigning
	# drops the arm back against the body the moment a spell is cast, which is the opposite of
	# the pose being a tell.
	_shoulder_r.rotation.z = 0.34 + raised * 0.26
	_shoulder_l.rotation.z = -0.34 + raised * 0.10

	# Both feet push, so the body rises twice a cycle. Standing still it breathes instead.
	var bob := absf(sin(_phase)) * BOB * drive
	if not moving:
		bob = sin(_idle * 1.9) * 0.012
	_torso.position.y = bob
	_torso.rotation.z = sin(_phase) * 0.05 * drive
	# Leaning into the walk, damped so a hit that stops the wizard does not snap it upright.
	_lean = lerpf(_lean, drive * 0.12, clampf(delta * 6.0, 0.0, 1.0))
	_root.rotation.x = _lean

	# The hem swings a beat behind the legs, which is most of what sells cloth at this size.
	_hem.rotation.x = -sin(_phase - 0.6) * 0.10 * drive
	_hem.rotation.z = cos(_phase - 0.6) * 0.06 * drive
	# The head stays level while the body leans, the way a person's does.
	_head.rotation.x = -_lean * 0.6
	if _orb != null:
		# The orb brightens as the staff comes up, so a cast reads before the bolt exists.
		var mat: StandardMaterial3D = _orb.get_surface_override_material(0)
		if mat != null:
			mat.emission_energy_multiplier = 1.2 + raised * 4.0


## Smooth in, so the staff accelerates rather than teleporting to the raised pose.
func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


# ---------------------------------------------------------------------------------------
# Building it
#
# Every measurement below is in metres, and y = 0 is the CAPSULE'S CENTRE, not the ground -
# the collision shape this hangs inside spans -1.0 to +1.0, so the feet are at -1.0.
# ---------------------------------------------------------------------------------------

func _build() -> void:
	_cloth = _material(tint, 0.85)
	# Deliberately not tinted: a wizard's face and its staff are the same in every colour, and
	# that is what keeps four tinted wizards reading as four PEOPLE rather than four swatches.
	_skin = _material(Color(0.86, 0.71, 0.58), 0.7)
	# Light enough to read against grass and against the wizard's own shadow, which is where
	# the staff spends half its time. At 0.40 it was a dark line on a dark patch.
	_wood = _material(Color(0.74, 0.58, 0.38), 0.85)
	_glow = _material(Color(1.0, 0.95, 0.75), 0.3)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.86, 0.5)
	_glow.emission_energy_multiplier = 1.2

	_root = Node3D.new()
	_root.name = "Root"
	# A little larger than the collision it stands in. The capsule is 2m tall and half of that
	# is hidden under a robe and a hood; the FIGURE reads at about 1.75m, and at sixty pixels
	# on screen the difference between 1.75 and 1.9 is the difference between a person and a
	# smudge. Nothing about the fight changes - the collision shape is untouched.
	_root.scale = Vector3.ONE * 1.09
	add_child(_root)

	# --- legs. Hips first, so a swing carries the shin and the boot with it ----------------
	_hip_l = _joint(_root, "HipL", Vector3(-0.12, -0.34, 0.0))
	_hip_r = _joint(_root, "HipR", Vector3(0.12, -0.34, 0.0))
	# Trousers and boots in their own browns rather than in the robe's colour. Two masses that
	# move against each other read as a person walking; one mass reads as a cone sliding.
	var _leg := _material(Color(0.30, 0.26, 0.30), 0.9)
	var boot_colour := _material(Color(0.42, 0.32, 0.24), 0.9)
	for side in [[_hip_l, "L"], [_hip_r, "R"]]:
		var hip: Node3D = side[0]
		_limb(hip, "Thigh", 0.30, 0.080, 0.070, _leg)
		var knee := _joint(hip, "Knee" + String(side[1]), Vector3(0.0, -0.30, 0.0))
		_limb(knee, "Shin", 0.28, 0.070, 0.055, _leg)
		var boot := _box(knee, "Boot", Vector3(0.13, 0.09, 0.24), boot_colour)
		boot.position = Vector3(0.0, -0.315, 0.03)
		if String(side[1]) == "L":
			_knee_l = knee
		else:
			_knee_r = knee

	# --- torso. Everything above the hips hangs off this, so the bob moves all of it -------
	_torso = _joint(_root, "Torso", Vector3(0.0, 0.0, 0.0))

	# THE PROPORTIONS BELOW ARE FOR A CAMERA LOOKING DOWN AT 55 DEGREES, and the first attempt
	# was not. Built as a figure you would see from the side - tall hood, long robe, arms at
	# the sides - it came out as a blue cone with a bead on top, because from above a cone is
	# all you can see of a cone. What reads from up there is WIDTH: the span of the shoulders,
	# the arms held out from the body, and the staff as a line across the ground plan. Height
	# is the one dimension this camera throws away, so nothing important is stacked vertically.

	# The robe. Narrower than the shoulders on purpose, so the figure is not one silhouette
	# from hem to hood, and short enough that the boots show under it and the walk is visible.
	_hem = _joint(_torso, "Hem", Vector3(0.0, -0.26, 0.0))
	# Short. A floor-length robe hides the legs, and the legs are the animation - a hooded
	# figure that glides is exactly what this was replacing.
	var skirt := _cone(_hem, "Skirt", 0.36, 0.17, 0.27, _cloth)
	skirt.position = Vector3(0.0, -0.18, 0.0)

	var chest := _cone(_torso, "Chest", 0.50, 0.19, 0.23, _cloth)
	chest.position = Vector3(0.0, 0.0, 0.0)

	var sash := _cylinder(_torso, "Sash", 0.09, 0.215, _material(
		Color(tint.r * 0.42, tint.g * 0.42, tint.b * 0.42), 0.8))
	sash.position = Vector3(0.0, -0.20, 0.0)

	# A MANTLE over the shoulders - a wide, shallow cone. This is the single part that makes
	# the figure legible from above: it puts a disc where the shoulders are, so the head reads
	# as a separate spot sitting on a body instead of as the top of one long cone.
	var mantle := _cone(_torso, "Mantle", 0.13, 0.15, 0.36, _material(
		Color(tint.r * 0.62, tint.g * 0.62, tint.b * 0.68), 0.85))
	mantle.position = Vector3(0.0, 0.24, 0.0)

	# --- arms, held OUT from the body ------------------------------------------------------
	#
	# The Z rotations are what make the arms visible at all. Hanging straight down they sit
	# inside the mantle's outline and the wizard has none.
	# THE SIGNS ARE THE POINT. A limb hangs along -Y, and rotating it about +Z carries it
	# toward +X - which is the wizard's RIGHT, because a body facing -Z with +Y up has its
	# right hand at +X. So the right arm swings out on a POSITIVE z and the left on a negative
	# one. They were the other way round for a while and it put both arms across the chest:
	# the arms vanished into the robe's outline and the staff spent its whole length inside
	# the skirt, which read as a wizard holding a floating bead.
	_shoulder_l = _joint(_torso, "ShoulderL", Vector3(-0.235, 0.20, 0.0))
	_shoulder_l.rotation.z = -0.34
	_limb(_shoulder_l, "ArmL", 0.44, 0.070, 0.052, _cloth)
	var hand_l := _sphere(_shoulder_l, "HandL", 0.055, _skin)
	hand_l.position = Vector3(0.0, -0.46, 0.0)

	_shoulder_r = _joint(_torso, "ShoulderR", Vector3(0.235, 0.20, 0.0))
	_shoulder_r.rotation.z = 0.34
	_limb(_shoulder_r, "ArmR", 0.44, 0.070, 0.052, _cloth)
	var hand_r := _sphere(_shoulder_r, "HandR", 0.055, _skin)
	hand_r.position = Vector3(0.0, -0.46, 0.0)

	# --- the staff, in the right hand ------------------------------------------------------
	#
	# Held in the hand and therefore a CHILD of the shoulder: raising the arm raises the staff
	# with it, and nothing has to keep the two in step.
	#
	# Long, and leaning across the body rather than standing upright. Upright, this camera sees
	# a dot; leaning, it sees a line - and a line is the only thing at this size that says
	# which way a wizard is facing before it has cast anything.
	# AS TALL AS THE WIZARD, ground to head, and it was half a metre longer than that.
	#
	# The hand sits about 0.77m above the feet, so a staff whose butt is on the ground and
	# whose head is level with the wizard's own reaches roughly 0.72 below the hand and 0.78
	# above it. That is where the two numbers come from, and it is why they are not symmetric:
	# more of a staff is below the hand than above it, which is how anyone actually holds one.
	var staff := _joint(_shoulder_r, "Staff", Vector3(0.0, -0.44, 0.0))
	# The Z here CANCELS the shoulder's own -0.34 and then leans a little further out. The
	# staff is a child of the arm, so without the cancellation it inherits the arm's angle and
	# hangs INWARDS - its whole lower half ends up inside the robe, which is exactly what
	# happened: the orb showed at head height and the shaft below the hand was nowhere.
	staff.rotation = Vector3(0.28, 0.0, -0.22)
	var shaft := _cylinder(staff, "Shaft", 1.50, 0.060, _wood)
	shaft.position = Vector3(0.0, 0.03, 0.0)
	_orb = _sphere(staff, "Orb", 0.095, _glow)
	_orb.position = Vector3(0.0, 0.83, 0.0)
	# Three prongs around the orb, so the head of the staff is a shape rather than a bead.
	for i in 3:
		var angle := TAU * float(i) / 3.0
		var prong := _box(staff, "Prong%d" % i, Vector3(0.022, 0.17, 0.022), _wood)
		prong.position = Vector3(sin(angle) * 0.080, 0.75, cos(angle) * 0.080)
		prong.rotation = Vector3(cos(angle) * 0.55, 0.0, -sin(angle) * 0.55)

	# --- head and hood ----------------------------------------------------------------------
	#
	# Small. The first attempt gave it a 0.42m cone that was wider than the chest and taller
	# than the head inside it, and from above that is the entire wizard.
	_head = _joint(_torso, "Head", Vector3(0.0, 0.30, 0.0))
	var face := _sphere(_head, "Face", 0.125, _skin)
	face.position = Vector3(0.0, 0.13, 0.0)
	var hood := _cone(_head, "Hood", 0.26, 0.012, 0.165, _cloth)
	hood.position = Vector3(0.0, 0.21, -0.015)
	hood.rotation = Vector3(-0.26, 0.0, 0.0)
	# The shadow inside it. Not black - nothing in this game is - a deep version of the cloth.
	var shade := _sphere(_head, "Shade", 0.105, _material(
		Color(tint.r * 0.24, tint.g * 0.24, tint.b * 0.30), 1.0))
	shade.position = Vector3(0.0, 0.14, 0.055)
	shade.scale = Vector3(1.0, 1.0, 0.55)


func _material(colour: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	return mat


func _joint(parent: Node3D, name_: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name_
	node.position = at
	parent.add_child(node)
	return node


## A tapered limb hanging DOWN from a joint, with its top at the joint's origin.
##
## Hanging down rather than centred is what makes the rig readable: a joint's rotation is the
## angle of the thing below it, so `_hip_l.rotation.x` is literally how far that leg has
## swung.
func _limb(parent: Node3D, name_: String, length: float, top: float, bottom: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var node := _cone(parent, name_, length, bottom, top, mat)
	node.position = Vector3(0.0, -length * 0.5, 0.0)
	return node


func _cone(parent: Node3D, name_: String, height: float, top: float, bottom: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	# Eight sides. Enough to read as round at sixty pixels, few enough that the facets do the
	# same job a hand-painted highlight would.
	mesh.radial_segments = 8
	mesh.rings = 1
	return _mesh(parent, name_, mesh, mat)


func _cylinder(parent: Node3D, name_: String, height: float, radius: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	return _cone(parent, name_, height, radius, radius, mat)


func _sphere(parent: Node3D, name_: String, radius: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	return _mesh(parent, name_, mesh, mat)


func _box(parent: Node3D, name_: String, size: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, name_, mesh, mat)


func _mesh(parent: Node3D, name_: String, mesh: Mesh,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_
	node.mesh = mesh
	# An override rather than the mesh's own material, so two wizards sharing a mesh cannot
	# share a colour. Every instance builds its own here anyway, but the rule is cheap.
	node.set_surface_override_material(0, mat)
	parent.add_child(node)
	return node
