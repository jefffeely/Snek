extends Node2D

const GRID_WIDTH := 50
const GRID_HEIGHT := 50
const CELL_SIZE := 20
const BOARD_OFFSET := Vector2i(16, 80)
const LEVEL_POINT_TARGET := 5
const BASE_TICK_WAIT := 0.14
const SPEED_MULTIPLIER_PER_LEVEL := 1.10
const MIN_TICK_WAIT := 0.04
const MIN_WALL_SEGMENT_LENGTH := 15
const MAX_WALL_SEGMENT_LENGTH := 24

const BACKGROUND_COLOR := Color("0f172a")
const GRID_COLOR := Color("1e293b")
const BOARD_COLOR := Color("111827")
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

func _ready() -> void:
	rng.randomize()
	tick_timer.timeout.connect(_on_tick_timer_timeout)
	reset_round()
	state = GameState.READY
	tick_timer.stop()
	update_hud()

func _unhandled_input(event: InputEvent) -> void:
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
	queue_redraw()

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
	queue_redraw()

func apply_level_speed() -> void:
	var speed_multiplier: float = pow(SPEED_MULTIPLIER_PER_LEVEL, float(level - 1))
	var next_wait_time: float = BASE_TICK_WAIT / speed_multiplier
	if next_wait_time < MIN_TICK_WAIT:
		next_wait_time = MIN_TICK_WAIT
	tick_timer.wait_time = next_wait_time
	if state == GameState.RUNNING:
		tick_timer.start()

func handle_direction_input(keycode: Key) -> void:
	if state == GameState.GAME_OVER:
		return

	var new_direction: Vector2i = pending_direction
	match keycode:
		KEY_UP, KEY_W:
			new_direction = Vector2i.UP
		KEY_DOWN, KEY_S:
			new_direction = Vector2i.DOWN
		KEY_LEFT, KEY_A:
			new_direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D:
			new_direction = Vector2i.RIGHT
		_:
			return

	queue_direction(new_direction)

	if state == GameState.READY:
		start_game()

func queue_direction(new_direction: Vector2i) -> void:
	if new_direction + direction == Vector2i.ZERO:
		return
	pending_direction = new_direction

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
	queue_redraw()

func advance_level() -> void:
	level += 1
	level_score = 0
	apply_level_speed()
	var carry_length: int = snake.size()
	reset_snake_position(carry_length)
	generate_walls_for_level()
	spawn_food()
	update_hud()
	queue_redraw()

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
	queue_redraw()

func update_hud() -> void:
	var to_next_level: int = LEVEL_POINT_TARGET - level_score
	score_label.text = "Score: %d   Level: %d   Next level in: %d" % [score, level, to_next_level]
	match state:
		GameState.READY:
			message_label.text = "Press Enter/Space (or any direction) to start."
		GameState.RUNNING:
			message_label.text = "Arrow keys/WASD to move. Eat %d food to advance." % LEVEL_POINT_TARGET
		GameState.GAME_OVER:
			pass

func _draw() -> void:
	var board_rect: Rect2 = Rect2(Vector2(BOARD_OFFSET), Vector2(GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE))
	draw_rect(board_rect, BACKGROUND_COLOR, true)
	draw_rect(board_rect, GRID_COLOR, false, 2.0)

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			draw_rect(cell_rect(Vector2i(x, y)).grow(-1.0), BOARD_COLOR, true)

	for wall_cell_value in walls:
		var wall_cell: Vector2i = wall_cell_value
		draw_rect(cell_rect(wall_cell).grow(-1.0), WALL_COLOR, true)

	if food.x >= 0 and food.y >= 0:
		draw_rect(cell_rect(food).grow(-2.0), FOOD_COLOR, true)

	for index in range(snake.size()):
		var color: Color = SNAKE_HEAD_COLOR if index == 0 else SNAKE_BODY_COLOR
		draw_rect(cell_rect(snake[index]).grow(-2.0), color, true)

func cell_rect(cell: Vector2i) -> Rect2:
	var pixel_pos: Vector2 = Vector2(BOARD_OFFSET + cell * CELL_SIZE)
	return Rect2(pixel_pos, Vector2(CELL_SIZE, CELL_SIZE))
