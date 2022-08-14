extends TileMap

signal game_started
signal game_finished(score)

onready var player:AnimatedSprite = $Player
onready var taxi:Sprite = $Taxi
onready var score_label:Label = $Score
onready var time_left_label:Label = $TimeLeft
onready var game_over_sound:AudioStreamPlayer = $GameOverSound
onready var level_complete_sound:AudioStreamPlayer = $LevelCompleteSound
onready var level_music:AudioStreamPlayer = $LevelMusic

var water_id = tile_set.find_tile_by_name("water")
var grass_id = tile_set.find_tile_by_name("grass")
var area = Rect2(Vector2(1,1), Vector2(5,5))
var border = area.grow(1)
var astar = AStar2D.new()
var start = area.position
var finish = area.end - Vector2(1,1)
var player_tile = start
var escape_count = 0
var level_begin_cooldown = 0
var player_movement_cooldown = 0
var step_duration = 0.15
var time_left = 10
var is_game_started = false

const NEIGHBOR_OFFSETS = [
	Vector2.UP,
	Vector2.RIGHT,
	Vector2.DOWN,
	Vector2.LEFT,
]

const DIAGONAL_NEIGHBOR_OFFSETS = [
	Vector2(1, -1),
	Vector2(1, 1),
	Vector2(-1, -1),
	Vector2(-1, 1),
]

func _init():
	randomize()


func start_game():
	game_over_sound.stop()
	area = Rect2(Vector2(1,1), Vector2(5,5))
	time_left_label.visible = true
	score_label.visible = true
	player.visible = true
	taxi.visible = true
	is_game_started = true
	generate_area()
	emit_signal("game_started")


func finish_game():
	level_music.stop()
	level_complete_sound.stop()
	game_over_sound.play()
	time_left_label.visible = false
	score_label.visible = false
	player.visible = false
	taxi.visible = false
	is_game_started = false
	clear()
	astar.clear()
	emit_signal("game_finished", escape_count)
	escape_count = 0
	
	
func exit_game():
	get_tree().quit()


func astar_id(pos):
	return (int(pos.y) << 8) + int(pos.x)


func set_grass(pos):
	set_cellv(pos, grass_id)
	astar.add_point(astar_id(pos), pos)
	for offset in NEIGHBOR_OFFSETS:
		var neighbor_pos = pos + offset
		var neighbor_id = astar_id(neighbor_pos)
		if astar.has_point(neighbor_id):
			astar.connect_points(astar_id(pos), neighbor_id)


func set_water(pos):
	set_cellv(pos, water_id)
	astar.remove_point(astar_id(pos))


func get_random_water_pos():
	var water_pos = null
	var i = 0
	while not water_pos:
		var pos = Vector2(randi() % int(area.size.x) + int(area.position.x),
			randi() % int(area.size.y) + int(area.position.y))
		if get_cellv(pos) == water_id:
			water_pos = pos
		i += 1
		assert(i < 10000, "Didn't find a random water tile")
	
	return water_pos


func generate_area():
	astar.clear()
	clear()
	
	start = area.position
	finish = area.end - Vector2(1,1)
	player_tile = start
	border = area.grow(1)
	
	for x in range(border.position.x, border.end.x):
		for y in range(border.position.y, border.end.y):
			set_cell(x, y, water_id)
			
	set_grass(start)
	set_grass(finish)
	
	while not astar.get_point_path(astar_id(start), astar_id(finish)):
		var pos = get_random_water_pos()
		set_grass(pos)
		
	
	if (astar.get_point_count() > area.get_area() * 0.67):
		return generate_area()
		
	var grassable_positions = []
	for point_id in astar.get_points():
		var point_pos = astar.get_point_position(point_id)
		var neighbor_grasses = astar.get_point_connections(point_id).size()
		if neighbor_grasses == 4:
			for offset in DIAGONAL_NEIGHBOR_OFFSETS:
				if get_cellv(point_pos + offset) == grass_id:
					neighbor_grasses += 1
		if neighbor_grasses == 8 and randf() <= 0.7:
			grassable_positions.append(point_pos)
		
	for grassable_pos in grassable_positions:
		set_water(grassable_pos)
	
	var path = astar.get_point_path(astar_id(start), astar_id(finish))
	assert(path, "Map Generation failed")
	
	
	player.position = (player_tile + Vector2(0.5,0.15)) * cell_size
	taxi.position = (finish + Vector2(0.6,0.5)) * cell_size
	score_label.text = "Times Escaped: %s" % escape_count
	time_left_label.text = "!!! GET READY !!!"
	player_movement_cooldown = 0
	level_begin_cooldown = max(level_begin_cooldown, 0.4)
	time_left = max(6 - escape_count, 0.5) + path.size() / 5.1
		
	update_bitmask_region(border.position, border.end)
	
	


func _process(delta):
	if not is_game_started:
		if Input.is_action_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_E):
			start_game()
		return
		
	if level_begin_cooldown > 0:
		level_begin_cooldown -= delta
		if level_begin_cooldown <= 0:
			level_music.play()
		return
	
	player_movement_cooldown -= delta
	var target_player_pos = (player_tile + Vector2(0.5,0.15)) * cell_size
	time_left -= delta
	if time_left < 0:
		return finish_game()
		
	time_left_label.text = "Time Left: %.2fs" % time_left
	
	if (player_movement_cooldown > 0):
		player.position = player.position.linear_interpolate(target_player_pos, delta * 16)
		return

	
	if (player_movement_cooldown <= 0 and player_tile == finish):
		level_music.stop()
		level_complete_sound.play()
		level_begin_cooldown = 0.8
		escape_count += 1
		player_movement_cooldown = 2
		area = area.grow_individual(0, 0, 2, 1)
		player.stop()
		player.animation = "default"
		player.frame = 0
		call_deferred("generate_area")
		return
	
	var keys = 0
	var direction = null
	var animation_name = null
	if Input.is_action_pressed("ui_cancel"):
		return finish_game()
	if Input.is_action_pressed("ui_up"):
		direction = Vector2.UP
		animation_name = "up"
		keys += 1
	if Input.is_action_pressed("ui_right"):
		direction = Vector2.RIGHT
		animation_name = "right"
		keys += 1
	if Input.is_action_pressed("ui_down"):
		direction = Vector2.DOWN
		animation_name = "down"
		keys += 1
	if Input.is_action_pressed("ui_left"):
		direction = Vector2.LEFT
		animation_name = "left"
		keys += 1
	
	if keys != 1:
		if (player_movement_cooldown <= 0):
			player.stop()
			player.frame = 0
			player.position = target_player_pos
		return
	
	var requested_tile_pos = player_tile + direction
	if not area.has_point(requested_tile_pos):
		return
		
	var requested_tile_id = get_cellv(requested_tile_pos)
	if requested_tile_id == water_id:
		return
		
		
	player_tile += direction
	player_movement_cooldown = step_duration
	if player.animation != animation_name or not player.playing:
		player.play(animation_name)


func _on_StartGame_pressed():
	start_game()


func _on_ExitGame_pressed():
	exit_game()
