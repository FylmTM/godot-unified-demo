extends UnifiedTool
## Bakes the skeleton minions' crowd (`./uni tool bake_crowd`, headless): MinionCrowd's scene merged and lightened into
## one mesh, its clips baked into bone matrices, written to MinionCrowd's MESH, BONES and TABLE (binary resources, the
## table as text). Run it after the minion's model, weapon, clips or import settings change, or the bake's code does:
## the art checks fail while the committed bake is stale.


func _run() -> void:
	var rig: CharacterRig = (load(MinionCrowd.SCENE) as PackedScene).instantiate()
	root.add_child(rig)
	var started: int = Time.get_ticks_msec()
	var baked: CrowdBake.Baked = MinionCrowd.bake(rig)
	rig.queue_free()
	expect(ResourceSaver.save(baked.mesh, MinionCrowd.MESH) == OK, "saved " + MinionCrowd.MESH)
	expect(ResourceSaver.save(baked.clips.bones, MinionCrowd.BONES) == OK, "saved " + MinionCrowd.BONES)
	baked.clips.bones.take_over_path(MinionCrowd.BONES)  # the table refers to the image's file, not a copy of it
	expect(ResourceSaver.save(baked.clips, MinionCrowd.TABLE) == OK, "saved " + MinionCrowd.TABLE)
	var indices: PackedInt32Array = baked.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = baked.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	result["ms"] = Time.get_ticks_msec() - started
	result["triangles"] = int(indices.size() / 3.0)
	result["vertices"] = vertices.size()
	result["texture"] = "%dx%d RGBA float, %d bytes" % [
		baked.clips.bones.get_width(), baked.clips.bones.get_height(), baked.clips.bones.get_data().size()]
	var clip_frames: Dictionary[String, int] = {}
	for clip: int in baked.clips.clips.size():
		clip_frames[String(baked.clips.clips[clip])] = baked.clips.frame_counts[clip]
	result["frames"] = clip_frames
	step("baked: %d triangles, %d vertices" % [result["triangles"], vertices.size()])
