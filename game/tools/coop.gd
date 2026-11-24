extends UnifiedCoop
## Crypt Crew's co-op play (the flow is the library's, UnifiedCoop): the friend's hero must arrive beside the host's
## (a late join lands by the party, not at the floor's start), as each side sees it; then the host walks a square,
## swinging as it goes, while the joiner keeps moving, until the host leaves.

## How far from the host's hero the friend's may arrive (metres): the arrival ring (tuning.odin's ARRIVAL_RING, 2.5 m)
## and a metre for the capsule settling on the floor.
const BESIDE: float = 3.5

## How long the joiner's hero stands where it arrived (seconds), so the host sees it there too.
const STILL_S: float = 3.0

const DIRS: Array[StringName] = [&"move_left", &"move_down", &"move_right", &"move_up"]


func _host_play() -> void:
	var friend: int = _friend_player()
	await wait_for(func() -> bool: return _hero(friend) != null, 10.0, "the friend's hero appears")
	if failed():
		return
	var mine: Node3D = _hero(session.local_player)
	var gap: float = _floor_distance(mine, _hero(friend))
	expect(gap < BESIDE, "the friend's hero arrived %.2f m from the host's (at most %.1f)" % [gap, BESIDE])
	step("friend's hero arrived %.2f m from the host's" % gap)
	await shot("c03_arrived_beside")
	for i in 16:
		if i % 4 == 0:
			Input.action_press(&"attack")
		await hold(DIRS[floori(i / 4.0) % DIRS.size()], 0.25)
		Input.action_release(&"attack")
	await shot("c04_coop_play")
	step("played together: %d skeletons" % Unified.data.hud.minions)


func _join_play() -> void:
	await wait_for(_playing, 20.0, "the joiner's hero appears")
	var gap: float = _floor_distance(_hero(session.local_player), _hero(_friend_player()))
	expect(gap < BESIDE, "the hero arrived %.2f m from the host's (at most %.1f)" % [gap, BESIDE])
	step("hero in, %.2f m from the host's" % gap)
	await seconds(STILL_S)
	Input.action_press(&"move_down")  # keeps moving while the host plays on


## The joiner's hero is in the crypt.
func _playing() -> bool:
	return _hero(session.local_player) != null


## Player `player`'s hero view (null: none yet).
func _hero(player: int) -> Node3D:
	return session.get_player_view(EnumView.HERO, player) as Node3D


## The distance between two views on the floor (x, z); INF when either is missing.
func _floor_distance(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return INF
	var d: Vector3 = a.global_position - b.global_position
	return Vector2(d.x, d.z).length()
