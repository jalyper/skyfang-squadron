extends Camera3D
## Rail camera that tracks the PathFollow3D's orientation so the player gets a
## roller-coaster feel through curves, dives, and banks.
##
## The camera sits behind and slightly above the rail point, in the rail's
## local frame. It also laterally eases toward the player when they push
## outside a center dead zone.

var pole_length: float = 7.0    # distance behind path point along rail forward
var pole_height: float = 2.8    # height above path in rail-local space

# Dead zone — fraction of player move_bounds where camera doesn't pan
var dead_zone_ratio: float = 0.5

# Smoothing speeds
var follow_speed: float = 4.0          # lateral ease toward player offset
var orient_lerp: float = 10.0          # ease camera rotation toward rail basis

var _cam_offset: Vector2 = Vector2.ZERO
var _initialized: bool = false


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var pf: PathFollow3D = gw.path_follow
	var player = GameManager.player

	# ── Compute desired lateral offset based on player position ──
	var target_offset := Vector2.ZERO
	if player != null and not player.is_dead:
		var px: float = player.position.x
		var py: float = player.position.y
		var bounds_x: float = player.move_bounds.x
		var bounds_y: float = player.move_bounds.y

		var dz_x: float = bounds_x * dead_zone_ratio
		var dz_y: float = bounds_y * dead_zone_ratio

		if abs(px) > dz_x:
			var excess_x: float = abs(px) - dz_x
			var max_excess_x: float = bounds_x - dz_x
			if max_excess_x > 0:
				target_offset.x = sign(px) * (excess_x / max_excess_x) * (bounds_x * 0.5)

		if abs(py) > dz_y:
			var excess_y: float = abs(py) - dz_y
			var max_excess_y: float = bounds_y - dz_y
			if max_excess_y > 0:
				target_offset.y = sign(py) * (excess_y / max_excess_y) * (bounds_y * 0.35)

	_cam_offset = _cam_offset.lerp(target_offset, follow_speed * delta)

	# ── Build the camera transform in rail-local space ──
	# PathFollow3D's basis follows the rail tangent; local +Z is "behind"
	# in PathFollow's frame, so pole_length is positive Z.
	var pf_xf: Transform3D = pf.global_transform
	var local_offset := Vector3(_cam_offset.x, pole_height + _cam_offset.y, pole_length)
	var target_pos: Vector3 = pf_xf * local_offset

	# Target basis: aligned with the rail so the camera looks along rail forward.
	# PathFollow3D already provides this via its basis.
	var target_basis: Basis = pf_xf.basis

	if not _initialized:
		global_position = target_pos
		global_basis = target_basis
		_cam_offset = target_offset
		_initialized = true
	else:
		global_position = global_position.lerp(target_pos, clampf(orient_lerp * delta, 0.0, 1.0))
		global_basis = global_basis.slerp(target_basis, clampf(orient_lerp * delta, 0.0, 1.0))
