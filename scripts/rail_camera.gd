extends Camera3D
## Rail camera — always faces the direction the rail is traveling, never sways.
## The player can move freely inside a center dead zone without the camera
## shifting. Once the player pushes past the dead zone toward the screen edges,
## the camera smoothly pans to keep them in frame, but still only looks forward
## along the rail. Closer default distance for a tighter, more cinematic feel.

var pole_length: float = 7.0    # distance behind path center (closer than before)
var pole_height: float = 2.8    # height above path
var look_ahead: float = 12.0    # how far ahead to look along the rail

# Dead zone — fraction of player move_bounds where camera doesn't pan
# e.g. 0.5 means the inner 50% of the movement range is "free"
var dead_zone_ratio: float = 0.5

# How fast the camera catches up when the player exits the dead zone
var follow_speed: float = 4.0

var _cam_offset: Vector2 = Vector2.ZERO  # current lateral/vertical camera offset
var _initialized: bool = false


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var pf: PathFollow3D = gw.path_follow
	var player = GameManager.player

	# Path orientation — camera ALWAYS faces rail direction
	var forward := -pf.global_transform.basis.z
	var up := pf.global_transform.basis.y
	var right := pf.global_transform.basis.x

	# ── Compute desired lateral offset based on player position ──
	var target_offset := Vector2.ZERO
	if player != null and not player.is_dead:
		var px: float = player.position.x  # local offset from rail center
		var py: float = player.position.y
		var bounds_x: float = player.move_bounds.x
		var bounds_y: float = player.move_bounds.y

		# Dead zone edges (in local units)
		var dz_x: float = bounds_x * dead_zone_ratio
		var dz_y: float = bounds_y * dead_zone_ratio

		# Only pan when player is outside dead zone
		# The pan amount is proportional to how far past the dead zone they are
		if abs(px) > dz_x:
			var excess: float = abs(px) - dz_x
			var max_excess: float = bounds_x - dz_x
			if max_excess > 0:
				target_offset.x = sign(px) * (excess / max_excess) * (bounds_x * 0.5)

		if abs(py) > dz_y:
			var excess: float = abs(py) - dz_y
			var max_excess: float = bounds_y - dz_y
			if max_excess > 0:
				target_offset.y = sign(py) * (excess / max_excess) * (bounds_y * 0.35)

	# Smoothly approach target offset
	_cam_offset = _cam_offset.lerp(target_offset, follow_speed * delta)

	# Position: behind the path center, shifted by lateral offset
	var base_pos := pf.global_position - forward * pole_length + up * pole_height
	var offset_pos := base_pos + right * _cam_offset.x + up * _cam_offset.y

	if not _initialized:
		global_position = offset_pos
		_cam_offset = target_offset  # snap on first frame
		_initialized = true
	else:
		global_position = offset_pos

	# Look straight ahead along the rail — no turning toward the player
	var look_target := pf.global_position + forward * look_ahead
	look_at(look_target, up)
