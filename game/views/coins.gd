extends MultiMeshInstance3D
## The coins on the floor: one MultiMesh of KayKit's coin, filled by its UnifiedMultiView from the extension's
## loot_instance (simulation/extension/frame.odin), each instance popped out of where it fell, stood on its edge, spun,
## hovered and, in its last seconds, blinked by coin.gdshader from its custom data: its value and the seconds since it
## fell, which the host writes at the shown time. A coin shows once its drop is verified (the loot kind's
## Appear.Verified), so a kill a rollback takes back never flashes a coin; a pickup takes it off at once, as the
## prediction has it (play.gd glints there), and a rollback that takes the pickup back puts it back where it lay.
##
## The model's mesh is the imported glTF's, taken once here (a MultiMesh draws a Mesh, not a scene), its bounds grown
## by the size, hover and hop the shader gives it, so the renderer never culls a coin in mid-air. Its material is made
## here, every value from its home: the palette and roughness of the dungeon pack's shared material, the sizes below,
## the coin's life from the sim (Unified.constants.loot_life).

## A coin worth 1 drawn this many times the model's size (KayKit's coin is 36 cm across: small at the game's camera) ...
const SIZE: float = 1.6
## ... and this much bigger for each gold more, up to MOST_GOLD (an elite's coins are worth more).
const SIZE_PER_GOLD: float = 0.15
const MOST_GOLD: float = 5.0
## The most the shader lifts a coin above where it lies (metres: its hover and bob at the top of its hop).
const LIFT: float = 1.4

## KayKit's coin (assets/kaykit/dungeon/coin.gltf): its mesh is what each instance draws.
@export var model: PackedScene
## The coins' shader (coin.gdshader).
@export var shader: Shader
## The dungeon pack's shared material (game/materials/dungeon.tres): the palette and roughness the coin draws with.
@export var skin: StandardMaterial3D


func _ready() -> void:
	var scene: Node = model.instantiate()
	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	var coin: ArrayMesh = (meshes[0] as MeshInstance3D).mesh.duplicate() as ArrayMesh
	scene.free()
	var model_size: Vector3 = coin.get_aabb().size
	var reach: float = maxf(model_size.x, maxf(model_size.y, model_size.z)) * SIZE * (1.0 + SIZE_PER_GOLD * MOST_GOLD)
	coin.custom_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(2.0 * reach, 2.0 * reach + LIFT, 2.0 * reach))
	multimesh.mesh = coin
	var look := ShaderMaterial.new()
	look.shader = shader
	look.set_shader_parameter("palette", skin.albedo_texture)
	look.set_shader_parameter("roughness", skin.roughness)
	look.set_shader_parameter("size", SIZE)
	look.set_shader_parameter("size_per_gold", SIZE_PER_GOLD)
	look.set_shader_parameter("most_gold", MOST_GOLD)
	look.set_shader_parameter("life", Unified.constants.loot_life)
	material_override = look
