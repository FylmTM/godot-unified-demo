extends UnifiedTool
## Bakes the skeleton minions' crowd (`./uni tool bake_crowd`, headless): unified's UnifiedCrowdBake makes what
## MinionBake's recipe says, the minion scene merged and lightened into one mesh and its clips baked into bone
## matrices, and writes it where the recipe says (the mesh and the bones as binary resources, the table as text). Run it
## after the minion's model, weapon, clips or import settings change, the recipe does, or unified's bake: the art checks
## fail while the committed bake is stale.


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var baked: UnifiedCrowdBake.Baked = UnifiedCrowdBake.bake(MinionBake.recipe(), root)
	if not baked.errors.is_empty():
		fail("the bake: " + "; ".join(baked.errors))
		return
	expect(baked.save() == OK, "saved %s, %s and %s" % [MinionCrowd.MESH, MinionCrowd.BONES, MinionCrowd.TABLE])
	var indices: PackedInt32Array = baked.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = baked.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	result["ms"] = Time.get_ticks_msec() - started
	result["triangles"] = int(indices.size() / 3.0)
	result["vertices"] = vertices.size()
	result["texture"] = "%dx%d RGBA float, %d bytes" % [
		baked.clips.bones.get_width(), baked.clips.bones.get_height(), baked.clips.bones.get_data().size()]
	var clip_frames: Dictionary[String, int] = {}
	for clip: int in baked.clips.clips.size():
		clip_frames[String(baked.clips.clips[clip])] = baked.clips.frame_count(clip)
	result["frames"] = clip_frames
	step("baked: %d triangles, %d vertices" % [result["triangles"], vertices.size()])
