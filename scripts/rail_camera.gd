extends Camera3D
## Rail camera — rides the same rail as the player ship and snaps to a
## fixed offset behind it each frame. No panning: the camera's frustum is
## sized so the entire player move_bounds rectangle is always on screen.
## What you see is always what the player can reach.
##
## Sizing for move_bounds = (12, 5) at FOV 70 vertical on 16:9:
##   Visible half-height at distance d = d * tan(35°)  ≈ 0.700 * d
##   Visible half-width  at distance d = d * tan(51.3°) ≈ 1.246 * d
##   d = 10 gives ±7 vertical, ±12.5 horizontal — both cover bounds.

var pole_length: float = 7.25   # distance behind rail point (path-local +Z)
var pole_height: float = 1.5    # height above rail (path-local +Y)


func _process(_delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return
	var pf: PathFollow3D = gw.path_follow
	var pf_xf: Transform3D = pf.global_transform
	var local_offset := Vector3(0.0, pole_height, pole_length)
	global_transform = Transform3D(pf_xf.basis, pf_xf * local_offset)
