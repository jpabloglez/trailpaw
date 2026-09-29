## Tests for [InteractionPrompt]: follows the interactor's target and fades.
extends GdUnitTestSuite

const ANIMAL_SCENE: String = "res://scenes/player/animal.tscn"
const PROMPT_SCENE: String = "res://scenes/ui/interaction_prompt.tscn"


func _setup() -> Array:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var animal: Animal = auto_free(load(ANIMAL_SCENE).instantiate())
	add_child(animal)
	animal.get_node("%PlayerInput").set_physics_process(false)
	var prompt: InteractionPrompt = auto_free(load(PROMPT_SCENE).instantiate())
	prompt.interactor = animal.get_node("%Interactor")
	add_child(prompt)
	prompt.set_process(false)
	return [animal, prompt]


func _interactable(at: Vector3) -> Interactable:
	var definition := InteractionDefinition.new()
	definition.id = &"test"
	definition.prompt = "Eat berries"
	definition.animation = &"eat"
	definition.duration = 1.0
	definition.food_kind = &"berries"
	var node: Interactable = auto_free(Interactable.new())
	node.definition = definition
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	node.add_child(shape)
	node.position = at
	add_child(node)
	return node


func test_hidden_without_a_target() -> void:
	var prompt: InteractionPrompt = _setup()[1]
	for i in 10:
		await get_tree().physics_frame
	prompt.advance(1.0)
	assert_float(prompt.opacity()).is_equal(0.0)


func test_shows_the_key_and_prompt_for_a_target_then_fades_out() -> void:
	var prompt: InteractionPrompt = _setup()[1]
	var node := _interactable(Vector3(0, 0.3, -1.0))
	for i in 20:
		await get_tree().physics_frame
	prompt.advance(1.0)
	assert_float(prompt.opacity()).is_equal(1.0)
	assert_str(prompt.text()).is_equal(InteractionPrompt.interact_key() + "  ·  Eat berries")
	assert_str(InteractionPrompt.interact_key()).is_equal("E")
	node.available = false
	for i in 20:
		await get_tree().physics_frame
	prompt.advance(0.1)
	assert_float(prompt.opacity()).is_between(0.0, 0.99)  # fading, not snapping
	prompt.advance(1.0)
	assert_float(prompt.opacity()).is_equal(0.0)
