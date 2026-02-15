extends Node3D

const GRID_WIDTH := 50
const GRID_HEIGHT := 50
const LEVEL_POINT_TARGET := 5
const BASE_TICK_WAIT := 0.14
const SPEED_MULTIPLIER_PER_LEVEL := 1.10
const MIN_TICK_WAIT := 0.04
const SPEED_STEP := 0.01
const MIN_WALL_SEGMENT_LENGTH := 15
const MAX_WALL_SEGMENT_LENGTH := 24
const CELL_WORLD_SIZE := 1.0
const FLOOR_THICKNESS := 0.1
const WALL_HEIGHT := 1.2
const SNAKE_HEIGHT := 0.75
const FOOD_HEIGHT := 1.0
const CAMERA_TOPDOWN_PERCENT := 0.45
const CAMERA_DISTANCE := 48.0
const CAMERA_ROTATE_SENSITIVITY := 0.01
const WINDOW_SCREEN_PERCENT := 0.80

const BACKGROUND_COLOR := Color("0b1220")
const BOARD_COLOR := Color("1f2937")
const WALL_COLOR := Color("64748b")
const SNAKE_HEAD_COLOR := Color("22c55e")
const SNAKE_BODY_COLOR := Color("16a34a")
const FOOD_COLOR := Color("ef4444")

enum GameState {
	READY,
	RUNNING,
	GAME_OVER
}

@onready var tick_timer: Timer = $TickTimer
@onready var world_root: Node3D = $World
@onready var orbit_camera: Camera3D = $OrbitCamera
@onready var score_label: Label = $HUD/ScoreLabel
@onready var message_label: Label = $HUD/MessageLabel

var rng := RandomNumberGenerator.new()
var snake: Array[Vector2i] = []
var walls: Array[Vector2i] = []
var direction := Vector2i.RIGHT
var pending_direction := Vector2i.RIGHT
var food := Vector2i.ZERO
var score := 0
var level := 1
var level_score := 0
var state := GameState.READY
var level_slowest_tick_wait := BASE_TICK_WAIT
var camera_yaw := deg_to_rad(35.0)
var camera_pitch := -deg_to_rad(90.0 * CAMERA_TOPDOWN_PERCENT)
var wall_multimesh_instance: MultiMeshInstance3D
var snake_body_multimesh_instance: MultiMeshInstance3D
var snake_head_instance: MeshInstance3D
var food_instance: MeshInstance3D

func _ready() -> void:
	call_deferred("apply_window_layout")
	rng.randomize()
	tick_timer.timeout.connect(_on_tick_timer_timeout)
	setup_world_visuals()
	reset_round()
	state = GameState.READY
	tick_timer.stop()
	update_hud()
	update_camera_transform()

func apply_window_layout() -> void:
	if OS.has_feature("headless"):
		return
	var window: Window = get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var screen_index: int = DisplayServer.window_get_current_screen()
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
	var target_size := Vector2i(
		int(float(usable_rect.size.x) * WINDOW_SCREEN_PERCENT),
		int(float(usable_rect.size.y) * WINDOW_SCREEN_PERCENT)
	)
	if target_size.x < 640:
		target_size.x = 640
	if target_size.y < 360:
		target_size.y = 360
	var target_position := Vector2i(
		usable_rect.position.x + int((usable_rect.size.x - target_size.x) / 2),
		usable_rect.position.y + int((usable_rect.size.y - target_size.y) / 2)
	)
	window.min_size = Vector2i(640, 360)
	window.size = target_size
	window.position = target_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		handle_camera_mouse_drag(event as InputEventMouseMotion)
		return

	if event is not InputEventKey:
		return

	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]:
		start_game(true)
		return

	handle_direction_input(key_event.keycode)

func reset_round() -> void:
	level = 1
	score = 0
	level_score = 0
	walls.clear()
	apply_level_speed()
	reset_snake_position(3)
	spawn_food()
	refresh_world_visuals()

func reset_snake_position(desired_length: int = 3) -> void:
	var snake_length: int = desired_length
	if snake_length < 3:
		snake_length = 3
	if snake_length > GRID_WIDTH:
		snake_length = GRID_WIDTH

	var head_x: int = int(GRID_WIDTH / 2)
	if head_x < snake_length - 1:
		head_x = snake_length - 1
	if head_x >= GRID_WIDTH:
		head_x = GRID_WIDTH - 1

	var center_y: int = int(GRID_HEIGHT / 2)
	var head: Vector2i = Vector2i(head_x, center_y)

	snake.clear()
	for i in range(snake_length):
		snake.append(head + Vector2i.LEFT * i)

	direction = Vector2i.RIGHT
	pending_direction = Vector2i.RIGHT

func start_game(force_reset: bool = false) -> void:
	if force_reset or state == GameState.GAME_OVER:
		reset_round()

	if state == GameState.RUNNING:
		return

	state = GameState.RUNNING
	tick_timer.start()
	update_hud()

func apply_level_speed() -> void:
	var speed_multiplier: float = pow(SPEED_MULTIPLIER_PER_LEVEL, float(level - 1))
	var next_wait_time: float = BASE_TICK_WAIT / speed_multiplier
	if next_wait_time < MIN_TICK_WAIT:
		next_wait_time = MIN_TICK_WAIT
	level_slowest_tick_wait = next_wait_time
	tick_timer.wait_time = level_slowest_tick_wait
	if state == GameState.RUNNING:
		tick_timer.start()

func handle_direction_input(keycode: Key) -> void:
	if state == GameState.GAME_OVER:
		return

	var base_direction: Vector2i = pending_direction
	var new_direction: Vector2i = base_direction
	match keycode:
		KEY_UP, KEY_W:
			adjust_speed(true)
			if state == GameState.READY:
				start_game()
			return
		KEY_DOWN, KEY_S:
			adjust_speed(false)
			if state == GameState.READY:
				start_game()
			return
		KEY_LEFT, KEY_A:
			new_direction = turn_left(base_direction)
		KEY_RIGHT, KEY_D:
			new_direction = turn_right(base_direction)
		_:
			return

	queue_direction(new_direction)

	if state == GameState.READY:
		start_game()

func queue_direction(new_direction: Vector2i) -> void:
	if new_direction + direction == Vector2i.ZERO:
		return
	pending_direction = new_direction

func turn_left(input_direction: Vector2i) -> Vector2i:
	return Vector2i(input_direction.y, -input_direction.x)

func turn_right(input_direction: Vector2i) -> Vector2i:
	return Vector2i(-input_direction.y, input_direction.x)

func adjust_speed(increase_speed: bool) -> void:
	var next_wait_time: float = tick_timer.wait_time
	if increase_speed:
		next_wait_time -= SPEED_STEP
		if next_wait_time < MIN_TICK_WAIT:
			next_wait_time = MIN_TICK_WAIT
	else:
		next_wait_time += SPEED_STEP
		if next_wait_time > level_slowest_tick_wait:
			next_wait_time = level_slowest_tick_wait
	tick_timer.wait_time = next_wait_time
	if state == GameState.RUNNING:
		tick_timer.start()

func _on_tick_timer_timeout() -> void:
	if state != GameState.RUNNING:
		return

	direction = pending_direction
	var next_head: Vector2i = snake[0] + direction
	var will_grow: bool = next_head == food

	if is_out_of_bounds(next_head):
		end_game(false)
		return
	if walls.has(next_head):
		end_game(false)
		return

	var body_to_check: Array[Vector2i] = snake.duplicate()
	if not will_grow:
		body_to_check.pop_back()
	if body_to_check.has(next_head):
		end_game(false)
		return

	snake.push_front(next_head)
	if will_grow:
		score += 1
		level_score += 1
		if level_score >= LEVEL_POINT_TARGET:
			advance_level()
			return
		spawn_food()
	else:
		snake.pop_back()

	update_hud()
	refresh_world_visuals()

func advance_level() -> void:
	level += 1
	level_score = 0
	apply_level_speed()
	var carry_length: int = snake.size()
	reset_snake_position(carry_length)
	generate_walls_for_level()
	spawn_food()
	update_hud()
	refresh_world_visuals()

func generate_walls_for_level() -> void:
	walls.clear()
	if level <= 1:
		return

	var reserved: Dictionary = build_reserved_cells()
	var max_cells: int = int(float(GRID_WIDTH * GRID_HEIGHT) * 0.32)
	var target_cells: int = (level - 1) * 35
	if target_cells > max_cells:
		target_cells = max_cells
	var max_segment_length: int = MIN_WALL_SEGMENT_LENGTH + level * 2
	if max_segment_length > MAX_WALL_SEGMENT_LENGTH:
		max_segment_length = MAX_WALL_SEGMENT_LENGTH
	var attempts: int = 0

	while walls.size() < target_cells and attempts < 2000:
		attempts += 1
		try_add_wall_segment(reserved, max_segment_length)

func build_reserved_cells() -> Dictionary:
	var reserved: Dictionary = {}
	var center: Vector2i = Vector2i(int(GRID_WIDTH / 2), int(GRID_HEIGHT / 2))
	for y in range(center.y - 3, center.y + 4):
		for x in range(center.x - 5, center.x + 6):
			var cell: Vector2i = Vector2i(x, y)
			if not is_out_of_bounds(cell):
				reserved[cell] = true
	return reserved

func can_place_wall(cell: Vector2i, reserved: Dictionary) -> bool:
	if is_out_of_bounds(cell):
		return false
	if cell.x <= 0 or cell.x >= GRID_WIDTH - 1:
		return false
	if cell.y <= 0 or cell.y >= GRID_HEIGHT - 1:
		return false
	if reserved.has(cell):
		return false
	if walls.has(cell):
		return false
	if snake.has(cell):
		return false
	return true

func try_add_wall_segment(reserved: Dictionary, max_segment_length: int) -> void:
	var start: Vector2i = Vector2i(rng.randi_range(1, GRID_WIDTH - 2), rng.randi_range(1, GRID_HEIGHT - 2))
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var direction_index: int = rng.randi_range(0, directions.size() - 1)
	var direction_choice: Vector2i = directions[direction_index]
	var segment_length: int = rng.randi_range(MIN_WALL_SEGMENT_LENGTH, max_segment_length)
	var segment: Array[Vector2i] = []

	for i in range(segment_length):
		var cell: Vector2i = start + direction_choice * i
		if not can_place_wall(cell, reserved):
			break
		segment.append(cell)

	if segment.size() < MIN_WALL_SEGMENT_LENGTH:
		return
	walls.append_array(segment)

func spawn_food() -> void:
	var open_cells: Array[Vector2i] = []
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var cell := Vector2i(x, y)
			if not snake.has(cell) and not walls.has(cell):
				open_cells.append(cell)

	if open_cells.is_empty():
		food = Vector2i(-1, -1)
		end_game(true)
		return

	food = open_cells[rng.randi_range(0, open_cells.size() - 1)]

func is_out_of_bounds(cell: Vector2i) -> bool:
	return cell.x < 0 or cell.x >= GRID_WIDTH or cell.y < 0 or cell.y >= GRID_HEIGHT

func end_game(won: bool) -> void:
	state = GameState.GAME_OVER
	tick_timer.stop()
	if won:
		message_label.text = "You win at level %d! Press Enter/Space/R to play again." % level
	else:
		message_label.text = "Game over at level %d. Press Enter/Space/R to restart." % level

func update_hud() -> void:
	var to_next_level: int = LEVEL_POINT_TARGET - level_score
	score_label.text = "Score: %d   Level: %d   Next level in: %d" % [score, level, to_next_level]
	match state:
		GameState.READY:
			message_label.text = "Press Enter/Space (or any direction) to start."
		GameState.RUNNING:
			message_label.text = "Left/Right or A/D turn. Up/Down or W/S adjust speed. Right-drag mouse to orbit camera. Eat %d food to advance." % LEVEL_POINT_TARGET
		GameState.GAME_OVER:
			pass

func setup_world_visuals() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d1d5db")
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.light_energy = 2.4
	sunlight.rotation_degrees = Vector3(-58.0, 35.0, 0.0)
	add_child(sunlight)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(GRID_WIDTH * CELL_WORLD_SIZE, FLOOR_THICKNESS, GRID_HEIGHT * CELL_WORLD_SIZE)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	floor_mesh.material_override = make_material(BOARD_COLOR)
	world_root.add_child(floor_mesh)

	wall_multimesh_instance = MultiMeshInstance3D.new()
	var wall_multimesh := MultiMesh.new()
	wall_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(CELL_WORLD_SIZE * 0.92, WALL_HEIGHT, CELL_WORLD_SIZE * 0.92)
	wall_multimesh.mesh = wall_mesh
	wall_multimesh_instance.multimesh = wall_multimesh
	wall_multimesh_instance.material_override = make_material(WALL_COLOR)
	world_root.add_child(wall_multimesh_instance)

	snake_body_multimesh_instance = MultiMeshInstance3D.new()
	var body_multimesh := MultiMesh.new()
	body_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(CELL_WORLD_SIZE * 0.86, SNAKE_HEIGHT, CELL_WORLD_SIZE * 0.86)
	body_multimesh.mesh = body_mesh
	snake_body_multimesh_instance.multimesh = body_multimesh
	snake_body_multimesh_instance.material_override = make_material(SNAKE_BODY_COLOR)
	world_root.add_child(snake_body_multimesh_instance)

	snake_head_instance = MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(CELL_WORLD_SIZE * 0.9, SNAKE_HEIGHT, CELL_WORLD_SIZE * 0.9)
	snake_head_instance.mesh = head_mesh
	snake_head_instance.material_override = make_material(SNAKE_HEAD_COLOR)
	world_root.add_child(snake_head_instance)

	food_instance = MeshInstance3D.new()
	var food_mesh := SphereMesh.new()
	food_mesh.radius = CELL_WORLD_SIZE * 0.48
	food_mesh.height = FOOD_HEIGHT
	food_instance.mesh = food_mesh
	food_instance.material_override = make_material(FOOD_COLOR)
	world_root.add_child(food_instance)

	orbit_camera.current = true
	orbit_camera.fov = 58.0

func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func grid_to_world(cell: Vector2i) -> Vector3:
	var x: float = (float(cell.x) - float(GRID_WIDTH) * 0.5 + 0.5) * CELL_WORLD_SIZE
	var z: float = (float(cell.y) - float(GRID_HEIGHT) * 0.5 + 0.5) * CELL_WORLD_SIZE
	return Vector3(x, 0.0, z)

func refresh_world_visuals() -> void:
	update_wall_visuals()
	update_snake_visuals()
	update_food_visuals()
	update_camera_transform()

func update_wall_visuals() -> void:
	var wall_multimesh: MultiMesh = wall_multimesh_instance.multimesh
	wall_multimesh.instance_count = walls.size()
	for i in range(walls.size()):
		var cell: Vector2i = walls[i]
		var transform := Transform3D(Basis.IDENTITY, grid_to_world(cell) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0))
		wall_multimesh.set_instance_transform(i, transform)

func update_snake_visuals() -> void:
	if snake.is_empty():
		snake_head_instance.visible = false
		snake_body_multimesh_instance.multimesh.instance_count = 0
		return

	snake_head_instance.visible = true
	snake_head_instance.position = grid_to_world(snake[0]) + Vector3(0.0, SNAKE_HEIGHT * 0.5, 0.0)

	var body_multimesh: MultiMesh = snake_body_multimesh_instance.multimesh
	var body_count: int = max(snake.size() - 1, 0)
	body_multimesh.instance_count = body_count
	for i in range(body_count):
		var cell: Vector2i = snake[i + 1]
		var transform := Transform3D(Basis.IDENTITY, grid_to_world(cell) + Vector3(0.0, SNAKE_HEIGHT * 0.5, 0.0))
		body_multimesh.set_instance_transform(i, transform)

func update_food_visuals() -> void:
	if food.x < 0 or food.y < 0:
		food_instance.visible = false
		return
	food_instance.visible = true
	food_instance.position = grid_to_world(food) + Vector3(0.0, FOOD_HEIGHT * 0.5 + 0.04, 0.0)

func handle_camera_mouse_drag(event: InputEventMouseMotion) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	camera_yaw -= event.relative.x * CAMERA_ROTATE_SENSITIVITY
	update_camera_transform()

func update_camera_transform() -> void:
	if snake.is_empty():
		return
	var target: Vector3 = grid_to_world(snake[0]) + Vector3(0.0, SNAKE_HEIGHT * 0.35, 0.0)
	var horizontal_distance: float = CAMERA_DISTANCE * cos(abs(camera_pitch))
	var camera_height: float = CAMERA_DISTANCE * sin(abs(camera_pitch))
	var offset := Vector3(
		sin(camera_yaw) * horizontal_distance,
		camera_height,
		cos(camera_yaw) * horizontal_distance
	)
	orbit_camera.global_position = target + offset
	orbit_camera.look_at(target, Vector3.UP)
