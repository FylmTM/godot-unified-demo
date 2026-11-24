extends Node3D

@onready var session: UnifiedSession = %UnifiedSession


func _ready() -> void:
	session.sim_event.connect(_on_sim_event)
	if not session.running:
		session.start_single()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var throw := CommandThrowBall.new()
		throw.speed = 4
		session.send_command(throw)
	elif event.is_action_pressed("ui_cancel"):  # Esc pauses or resumes the game for everyone (the co-op pause)
		var pause := CommandSetPaused.new()
		pause.paused = not Unified.data.hud.paused
		session.send_command(pause)


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:  # printed once final: an EMITTED event can still be cancelled
		return

	if event is EventPlayerJoined:
		var joined := event as EventPlayerJoined
		print("tick %d: player %d joined in slot %d (returning: %s)" % [event.tick, joined.player, joined.slot, joined.returning])
	elif event is EventPlayerLeft:
		var left := event as EventPlayerLeft
		print("tick %d: player %d left slot %d" % [event.tick, left.player, left.slot])
