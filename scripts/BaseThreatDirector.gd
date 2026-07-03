extends Node

signal threat_lesson_triggered(lesson_id: StringName, message: String)

const CHECK_INTERVAL_SECONDS := 1.0
const EXPOSED_STORAGE_DAMAGE_SECONDS := 12.0
const RAIN_STORAGE_PURITY_LOSS := 0.25
const RAIN_STORAGE_LITHIUM_CHARGE_LOSS := 0.35
const RAIN_STATION_WARNING_SECONDS := 5.0
const VOLATILE_CHECK_SECONDS := 1.5
const VOLATILE_DANGER_DISTANCE_PIXELS := 72.0
const VOLATILE_SAFE_DISTANCE_PIXELS := 128.0
const ENCLOSURE_RADIUS_TILES := 5
const BREACH_REPORT_COOLDOWN_SECONDS := 4.0
const NIGHT_ATTRACTION_RADIUS_PIXELS := 300.0
const POST_TUTORIAL_ESCALATION_DAY_TIER_ONE := 3
const POST_TUTORIAL_ESCALATION_DAY_TIER_TWO := 5
const POST_TUTORIAL_NIGHT_ATTRACTION_RADIUS_TIER_ONE_PIXELS := 380.0
const POST_TUTORIAL_NIGHT_ATTRACTION_RADIUS_TIER_TWO_PIXELS := 440.0
const WET_STATUS_ID := &"wet"
const WET_STATUS_REFRESH_SECONDS := 3.0

const LESSON_RAIN_ROOF := &"rain_roof"
const LESSON_RAIN_ROOF_FAILURE := &"rain_roof_failure"
const LESSON_RAIN_STATION := &"rain_station"
const LESSON_RAIN_CAMPFIRE := &"rain_campfire"
const LESSON_RAIN_SURVIVAL := &"rain_survival"
const LESSON_WET_STATUS := &"wet_status"
const LESSON_DRY_BOX := &"dry_box"
const LESSON_DRY_BOX_FAILURE := &"dry_box_failure"
const LESSON_VOLATILE_SEPARATION := &"volatile_separation"
const LESSON_VOLATILE_FAILURE := &"volatile_failure"
const LESSON_COLD_ENCLOSURE := &"cold_enclosure"
const LESSON_OPEN_AIR_COLD := &"open_air_cold"
const LESSON_NIGHT_DEFENSE := &"night_defense"
const LESSON_EXPEDITION_STAGING := &"expedition_staging"

var _check_elapsed := 0.0
var _exposed_storage_elapsed := 0.0
var _rain_station_elapsed := 0.0
var _volatile_elapsed := 0.0
var _breach_report_elapsed := 0.0
var _shown_lessons: Dictionary = {}
var _last_cold_enclosed := false
var _last_cold_near_fire := false
var _night_staging_checked := false
var _rain_was_active := false
var _loop_escalation_tier := 0


func _ready() -> void:
	if GameManager != null and GameManager.has_signal("night_started"):
		GameManager.night_started.connect(_on_night_started)
	if GameManager != null and GameManager.has_signal("day_started"):
		GameManager.day_started.connect(_on_day_started)
	if GameManager != null and GameManager.has_signal("day_changed"):
		GameManager.day_changed.connect(_on_day_changed)
	if BuildSystem != null and BuildSystem.has_signal("buildable_placed"):
		BuildSystem.buildable_placed.connect(_on_buildable_placed)
	if WeatherSystem != null and WeatherSystem.has_signal("weather_changed"):
		WeatherSystem.weather_changed.connect(_on_weather_changed)
	if ResearchObjectives != null and ResearchObjectives.has_signal("objective_completed"):
		ResearchObjectives.objective_completed.connect(_on_objective_completed)
	if WeatherSystem != null and WeatherSystem.has_method("get_current_state"):
		_rain_was_active = int(WeatherSystem.get_current_state()) == WeatherSystem.WeatherState.RAIN
	_loop_escalation_tier = _get_loop_escalation_tier()


func _physics_process(delta: float) -> void:
	if not _is_active():
		return
	_check_elapsed += delta
	_breach_report_elapsed = maxf(0.0, _breach_report_elapsed - delta)
	if _check_elapsed < CHECK_INTERVAL_SECONDS:
		return
	_check_elapsed = 0.0
	_process_player_wet_status()
	_process_weather_storage(CHECK_INTERVAL_SECONDS)
	_process_rain_station_pressure(CHECK_INTERVAL_SECONDS)
	_process_volatile_storage(CHECK_INTERVAL_SECONDS)
	_process_night_pressure()
	_process_expedition_return()


func get_cold_buildup_multiplier(world_position: Vector2) -> float:
	var enclosed := is_position_in_walled_enclosure(world_position)
	_last_cold_enclosed = enclosed
	var wet_penalty := 0.45 if is_player_wet() else 0.0
	return (0.55 if enclosed else 1.55) + wet_penalty


func get_warmth_decay_multiplier(world_position: Vector2) -> float:
	var enclosed := is_position_in_walled_enclosure(world_position)
	var near_fire := _has_lit_campfire_near(world_position)
	_last_cold_enclosed = enclosed
	_last_cold_near_fire = near_fire
	if enclosed and near_fire:
		return 1.35
	if near_fire:
		return 0.35
	return 0.0


func should_count_as_warmed(world_position: Vector2) -> bool:
	return _has_lit_campfire_near(world_position) and is_position_in_walled_enclosure(world_position)


func is_player_wet() -> bool:
	return GameManager != null and GameManager.player_status_effects.has(WET_STATUS_ID)


func is_rain_exposed_at(world_position: Vector2) -> bool:
	return _get_weather_state() == WeatherSystem.WeatherState.RAIN and not _is_sheltered(world_position)


func get_chemistry_rain_risk(world_position: Vector2) -> float:
	var risk := 0.0
	if is_rain_exposed_at(world_position):
		risk += 0.45
	if is_player_wet():
		risk += 0.25
	return clampf(risk, 0.0, 0.85)


func get_chemistry_slowdown_multiplier(world_position: Vector2) -> float:
	var multiplier := 1.0
	if is_rain_exposed_at(world_position):
		multiplier += 0.55
	if is_player_wet():
		multiplier += 0.20
	return multiplier


func get_enemy_attraction_target(enemy_position: Vector2) -> Vector2:
	var best_target := Vector2(INF, INF)
	var best_distance := INF
	var attraction_radius := _get_night_attraction_radius()
	for source in _get_attraction_sources():
		var source_node := source as Node2D
		if source_node == null:
			continue
		if not _is_attraction_source_active(source_node):
			continue
		var distance := enemy_position.distance_to(source_node.global_position)
		if distance < best_distance and distance <= attraction_radius:
			best_distance = distance
			best_target = source_node.global_position
	return best_target


func get_weighted_enemy_attraction_target(
	enemy_position: Vector2,
	powered_light_weight: float = 1.0,
	heat_weight: float = 1.0,
	sulfur_storage_weight: float = 1.0
) -> Vector2:
	var best_target := Vector2(INF, INF)
	var best_score := INF
	var attraction_radius := _get_night_attraction_radius()
	for source in _get_attraction_sources():
		var source_node := source as Node2D
		if source_node == null:
			continue
		if not _is_attraction_source_active(source_node):
			continue
		var distance := enemy_position.distance_to(source_node.global_position)
		if distance > attraction_radius:
			continue
		var weight := _get_attraction_source_weight(
			source_node,
			powered_light_weight,
			heat_weight,
			sulfur_storage_weight
		)
		if weight <= 0.0:
			continue
		var score := distance / weight
		if score < best_score:
			best_score = score
			best_target = source_node.global_position
	return best_target


func report_enemy_base_breach(enemy: Node2D) -> void:
	if enemy == null or _breach_report_elapsed > 0.0:
		return
	_breach_report_elapsed = BREACH_REPORT_COOLDOWN_SECONDS
	var has_wall := not get_tree().get_nodes_in_group(&"placed_walls").is_empty()
	var has_light := BaseDefenseSystem != null and BaseDefenseSystem.has_method("get_active_light_count") and BaseDefenseSystem.get_active_light_count() > 0
	var has_trap := not get_tree().get_nodes_in_group(&"electric_trap").is_empty()
	if has_wall and has_light and has_trap:
		_emit_lesson(
			LESSON_NIGHT_DEFENSE,
			"Night enemies followed heat and light into the perimeter. Walls and traps turn that pull into a route you control."
		)
	else:
		_emit_lesson(
			LESSON_NIGHT_DEFENSE,
			"Night enemies followed your base signals. Walls, doors, powered lights, and electric traps are the answer."
		)


func is_position_in_walled_enclosure(world_position: Vector2) -> bool:
	var tile_coords: Variant = _world_to_tile(world_position)
	if tile_coords == null:
		return false
	var start: Vector2i = tile_coords as Vector2i
	var blocked: Dictionary = _build_blocked_tile_lookup()
	if blocked.has(start):
		return false
	var visited := {}
	var frontier: Array[Vector2i] = [start]
	visited[start] = true
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if abs(current.x - start.x) > ENCLOSURE_RADIUS_TILES or abs(current.y - start.y) > ENCLOSURE_RADIUS_TILES:
			return false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next_tile: Vector2i = current + offset
			if visited.has(next_tile) or blocked.has(next_tile):
				continue
			visited[next_tile] = true
			frontier.append(next_tile)
	return true


func _process_weather_storage(delta: float) -> void:
	var state := _get_weather_state()
	if state != WeatherSystem.WeatherState.RAIN and state != WeatherSystem.WeatherState.ACID_MIST:
		_exposed_storage_elapsed = 0.0
		return
	_exposed_storage_elapsed += delta
	if _exposed_storage_elapsed < EXPOSED_STORAGE_DAMAGE_SECONDS:
		return
	_exposed_storage_elapsed = 0.0

	for storage_node in get_tree().get_nodes_in_group(&"placed_storage"):
		var node := storage_node as Node2D
		if node == null:
			continue
		var container_id := _get_storage_container_id(node)
		if container_id.is_empty():
			continue
		var filter_id := StorageManager.get_container_filter_id(container_id)
		var sheltered := _is_sheltered(node.global_position)
		var items := StorageManager.get_container_items(container_id)
		if state == WeatherSystem.WeatherState.RAIN:
			if items.has(&"lithium"):
				if filter_id == StorageManager.FILTER_WATER_REACTIVE_ELEMENTS and sheltered:
					continue
				var lithium_stack: Dictionary = items.get(&"lithium", {})
				var current_charge := clampf(float(lithium_stack.get(&"charge", InventoryManager.DEFAULT_LITHIUM_CHARGE)), 0.0, 1.0)
				var next_charge := clampf(current_charge - RAIN_STORAGE_LITHIUM_CHARGE_LOSS, 0.0, 1.0)
				StorageManager.set_container_item_charge(container_id, &"lithium", next_charge)
				if next_charge <= 0.0:
					StorageManager.damage_container_item(container_id, &"lithium", 1, LESSON_DRY_BOX)
					_emit_lesson(LESSON_DRY_BOX_FAILURE, "Lithium spoiled in wet storage. A Dry Box under a Shelter Roof protects it completely.")
				else:
					_emit_lesson(LESSON_DRY_BOX_FAILURE, "Lithium charge is draining in wet storage. A roofed Dry Box stops the loss.")
				return
			if not sheltered and filter_id == StorageManager.FILTER_ANY:
				var damaged_item := _pick_weather_damage_item(items)
				if damaged_item.is_empty():
					continue
				var next_purity := StorageManager.adjust_container_item_purity(container_id, damaged_item, -RAIN_STORAGE_PURITY_LOSS)
				if next_purity <= 0.0:
					StorageManager.damage_container_item(container_id, damaged_item, 1, LESSON_RAIN_ROOF)
					_emit_lesson(LESSON_RAIN_ROOF_FAILURE, "Rain ruined an uncovered storage item. A Shelter Roof over stations and chests prevents this.")
				else:
					_emit_lesson(LESSON_RAIN_ROOF_FAILURE, "Rain lowered the quality of uncovered storage. Roofed chests stay intact.")
				return
		elif state == WeatherSystem.WeatherState.ACID_MIST and not sheltered and filter_id == StorageManager.FILTER_ANY:
			var acid_item := &"sulfur" if items.has(&"sulfur") else _pick_weather_damage_item(items)
			if not acid_item.is_empty() and StorageManager.damage_container_item(container_id, acid_item, 1, LESSON_RAIN_ROOF) > 0:
				_emit_lesson(LESSON_RAIN_ROOF_FAILURE, "Acid mist ate into uncovered storage. Roofed work areas keep stations and chests out of the weather.")
				return


func _process_rain_station_pressure(delta: float) -> void:
	if _get_weather_state() != WeatherSystem.WeatherState.RAIN:
		_rain_station_elapsed = 0.0
		return
	_rain_station_elapsed += delta
	if _rain_station_elapsed < RAIN_STATION_WARNING_SECONDS:
		return
	_rain_station_elapsed = 0.0
	for station_node in get_tree().get_nodes_in_group(&"placed_stations"):
		var node := station_node as Node2D
		if node == null or _is_sheltered(node.global_position):
			continue
		var type_name := String(node.get(&"object_type")) if "object_type" in node else ""
		if type_name == "chem_bench":
			_emit_lesson(LESSON_RAIN_STATION, "Rain is contaminating the exposed Chem Bench. Roofed stations run cleaner and more reliably.")
			return
		if type_name == "campfire":
			_emit_lesson(LESSON_RAIN_CAMPFIRE, "The uncovered campfire is sputtering in rain. A Shelter Roof keeps heat usable.")
			return


func _process_player_wet_status() -> void:
	if _get_weather_state() != WeatherSystem.WeatherState.RAIN:
		return
	var player := _get_player()
	if player == null or _is_sheltered(player.global_position):
		return
	var health_system := player.get_node_or_null("HealthSystem")
	if health_system == null or not health_system.has_method("add_status_effect"):
		return
	health_system.add_status_effect(WET_STATUS_ID, 0, WET_STATUS_REFRESH_SECONDS, "Rain exposure")
	_emit_lesson(LESSON_WET_STATUS, "Rain soaked you. Wet hands make cold worse and reactive chemistry less reliable.")


func _process_volatile_storage(delta: float) -> void:
	_volatile_elapsed += delta
	if _volatile_elapsed < VOLATILE_CHECK_SECONDS:
		return
	_volatile_elapsed = 0.0
	var heat_sources := _get_heat_sources()
	if heat_sources.is_empty():
		return
	for storage_node in get_tree().get_nodes_in_group(&"placed_storage"):
		var node := storage_node as Node2D
		if node == null:
			continue
		var container_id := _get_storage_container_id(node)
		if container_id.is_empty() or StorageManager.get_container_quantity(container_id, &"sulfur") <= 0:
			continue
		var filter_id := StorageManager.get_container_filter_id(container_id)
		var nearest_heat := _nearest_distance_to_nodes(node.global_position, heat_sources)
		if nearest_heat <= VOLATILE_DANGER_DISTANCE_PIXELS:
			var lost := StorageManager.damage_container_item(container_id, &"sulfur", 1, LESSON_VOLATILE_SEPARATION)
			if lost > 0:
				_emit_lesson(LESSON_VOLATILE_FAILURE, "Sulfur flashed beside heat. Keep volatile lockers separated from furnaces and campfires.")
				_spawn_small_warning_flash(node.global_position)
				return
		if filter_id == StorageManager.FILTER_VOLATILE_ELEMENTS and nearest_heat >= VOLATILE_SAFE_DISTANCE_PIXELS:
			_emit_lesson(LESSON_VOLATILE_SEPARATION, "Separated sulfur stayed stable in the Volatile Locker. Distance from heat is the protection.")


func _process_night_pressure() -> void:
	if GameManager == null or not GameManager.has_method("is_night") or not GameManager.is_night():
		return
	var player := _get_player()
	if player == null:
		return
	var near_fire := _has_lit_campfire_near(player.global_position)
	var enclosed := is_position_in_walled_enclosure(player.global_position)
	if near_fire and enclosed:
		_emit_lesson(LESSON_COLD_ENCLOSURE, "The walled room is holding campfire heat. Plan shelter before night, then close it with doors.")
	elif near_fire and not enclosed and GameManager.get_cold_level() >= 20.0:
		_emit_lesson(LESSON_OPEN_AIR_COLD, "Open air is bleeding off campfire heat. Walls and doors make night shelter retain warmth.")


func _process_expedition_return() -> void:
	if _night_staging_checked:
		return
	var player := _get_player()
	if player == null:
		return
	if not _is_near_any_storage(player.global_position):
		return
	var has_unstaged_lithium := InventoryManager.has_item(&"lithium") and not _has_storage_filter(StorageManager.FILTER_WATER_REACTIVE_ELEMENTS)
	var has_unstaged_sulfur := InventoryManager.has_item(&"sulfur") and not _has_storage_filter(StorageManager.FILTER_VOLATILE_ELEMENTS)
	if not has_unstaged_lithium and not has_unstaged_sulfur:
		return
	_night_staging_checked = true
	var item_id := &"lithium" if has_unstaged_lithium else &"sulfur"
	if InventoryManager.remove_item(item_id, 1):
		_emit_lesson(
			LESSON_EXPEDITION_STAGING,
			"Expedition cargo had no planned home zone, so %s was lost on return. Restock Dry Boxes and Volatile Lockers before long runs." % _display_item_name(item_id)
		)


func _on_night_started() -> void:
	_night_staging_checked = false
	var player := _get_player()
	if player == null:
		return
	if _has_lit_campfire_near(player.global_position) and is_position_in_walled_enclosure(player.global_position):
		_emit_lesson(LESSON_COLD_ENCLOSURE, "Night is colder outside the walls. Campfire heat lasts inside an enclosure with doors.")
	else:
		_emit_lesson(LESSON_COLD_ENCLOSURE, "Night cold builds fastest in open air. Campfire plus walls and doors is the base response.")


func _on_day_started() -> void:
	_night_staging_checked = false


func _on_day_changed(_day: int) -> void:
	_refresh_loop_escalation_tier()


func _on_weather_changed(new_state: int) -> void:
	var rain_active := new_state == WeatherSystem.WeatherState.RAIN
	if rain_active:
		_rain_was_active = true
		_emit_lesson(LESSON_RAIN_ROOF, "Rain exposes bad base layouts. Roof stations, storage, and campfires before the next storm.")
		return
	if _rain_was_active:
		_rain_was_active = false
		if _has_sheltered_base_assets():
			_emit_lesson(LESSON_RAIN_SURVIVAL, "The roofed part of the base came through rain intact. Covered stations and storage stayed dry.")


func _on_buildable_placed(buildable_id: StringName) -> void:
	match buildable_id:
		&"shelter_roof":
			_emit_lesson(LESSON_RAIN_ROOF, "Shelter Roof placed. Anything under its 3x3 cover is protected from rain and acid mist.")
		&"dry_box":
			_emit_lesson(LESSON_DRY_BOX, "Dry Box placed. Water-reactive cargo stored here is safe in rain; ordinary chests are not.")
		&"volatile_locker":
			_emit_lesson(LESSON_VOLATILE_SEPARATION, "Volatile Locker placed. Put sulfur here, away from furnaces and campfires.")
		&"wall", &"door", &"campfire":
			_emit_lesson(LESSON_COLD_ENCLOSURE, "Night shelter needs three parts: heat, walls, and doors.")
		&"powered_light_post", &"electric_trap":
			_emit_lesson(LESSON_NIGHT_DEFENSE, "Powered defenses shape night attacks: lights reveal pressure and traps punish the route.")


func _on_objective_completed(objective_id: StringName) -> void:
	if objective_id != &"power_defenses":
		return
	_refresh_loop_escalation_tier()


func _emit_lesson(lesson_id: StringName, message: String) -> void:
	if lesson_id.is_empty() or _shown_lessons.has(lesson_id):
		return
	_shown_lessons[lesson_id] = true
	threat_lesson_triggered.emit(lesson_id, message)


func _is_active() -> bool:
	return GameManager != null \
		and GameManager.game_state == GameManager.GameState.PLAYING \
		and not GameManager.is_paused


func _get_weather_state() -> int:
	if WeatherSystem == null or not WeatherSystem.has_method("get_current_state"):
		return -1
	return int(WeatherSystem.get_current_state())


func _get_storage_container_id(node: Node) -> StringName:
	if node == null:
		return &""
	if "container_id" in node:
		return StringName(node.get("container_id"))
	if "chest_id" in node:
		return StringName(node.get("chest_id"))
	return &""


func _is_sheltered(world_position: Vector2) -> bool:
	return WeatherSystem != null \
		and WeatherSystem.has_method("get_shelter_at") \
		and bool(WeatherSystem.get_shelter_at(world_position))


func _pick_weather_damage_item(items: Dictionary) -> StringName:
	for preferred in [&"wood", &"charcoal", &"iron", &"sulfur"]:
		if items.has(preferred) and int((items[preferred] as Dictionary).get(&"quantity", 0)) > 0:
			return preferred
	for raw_item_id in items.keys():
		var item_id := StringName(raw_item_id)
		if int((items[item_id] as Dictionary).get(&"quantity", 0)) > 0:
			return item_id
	return &""


func _get_heat_sources() -> Array[Node2D]:
	var sources: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(&"heat_source"):
		var node_2d := node as Node2D
		if node_2d != null:
			sources.append(node_2d)
	for node in get_tree().get_nodes_in_group(&"placed_stations"):
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var type_name := String(node_2d.get(&"object_type")) if "object_type" in node_2d else ""
		if type_name == "furnace" or type_name == "campfire":
			if "is_lit" in node_2d and not bool(node_2d.get("is_lit")):
				continue
			sources.append(node_2d)
	return sources


func _nearest_distance_to_nodes(world_position: Vector2, nodes: Array[Node2D]) -> float:
	var nearest := INF
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		nearest = minf(nearest, world_position.distance_to(node.global_position))
	return nearest


func _get_attraction_sources() -> Array[Node2D]:
	var sources: Array[Node2D] = _get_heat_sources()
	for node in get_tree().get_nodes_in_group(&"powered_light"):
		var node_2d := node as Node2D
		if node_2d != null:
			sources.append(node_2d)
	for storage_node in get_tree().get_nodes_in_group(&"placed_storage"):
		var node_2d := storage_node as Node2D
		if node_2d == null:
			continue
		var container_id := _get_storage_container_id(node_2d)
		if not container_id.is_empty() and StorageManager.get_container_quantity(container_id, &"sulfur") > 0:
			sources.append(node_2d)
	return sources


func _is_attraction_source_active(source_node: Node2D) -> bool:
	if source_node.is_in_group(&"powered_light") and source_node.has_method("is_attracting_swarmer"):
		return bool(source_node.call("is_attracting_swarmer"))
	return true


func _get_attraction_source_weight(
	source_node: Node2D,
	powered_light_weight: float,
	heat_weight: float,
	sulfur_storage_weight: float
) -> float:
	if source_node.is_in_group(&"powered_light"):
		return powered_light_weight
	if source_node.is_in_group(&"placed_storage"):
		var container_id := _get_storage_container_id(source_node)
		if not container_id.is_empty() and StorageManager.get_container_quantity(container_id, &"sulfur") > 0:
			return sulfur_storage_weight
	if source_node.is_in_group(&"heat_source"):
		return heat_weight
	if source_node.is_in_group(&"placed_stations"):
		var type_name := String(source_node.get(&"object_type")) if "object_type" in source_node else ""
		if type_name == "furnace" or type_name == "campfire":
			return heat_weight
	return 1.0


func _has_lit_campfire_near(world_position: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(&"placed_stations"):
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		if not ("object_type" in node_2d) or String(node_2d.get("object_type")) != "campfire":
			continue
		if "is_lit" in node_2d and not bool(node_2d.get("is_lit")):
			continue
		if world_position.distance_to(node_2d.global_position) <= 72.0:
			return true
	return false


func _is_near_any_storage(world_position: Vector2) -> bool:
	for storage_node in get_tree().get_nodes_in_group(&"placed_storage"):
		var node_2d := storage_node as Node2D
		if node_2d != null and world_position.distance_to(node_2d.global_position) <= 96.0:
			return true
	return false


func _has_storage_filter(filter_id: StringName) -> bool:
	for storage_node in get_tree().get_nodes_in_group(&"placed_storage"):
		var container_id := _get_storage_container_id(storage_node as Node)
		if container_id.is_empty() or StorageManager.get_container_filter_id(container_id) != filter_id:
			continue
		return true
	return false


func _has_sheltered_base_assets() -> bool:
	for group_name in [&"placed_storage", &"placed_stations"]:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			var node := node_variant as Node2D
			if node != null and _is_sheltered(node.global_position):
				return true
	return false


func _build_blocked_tile_lookup() -> Dictionary:
	var blocked := {}
	for wall_node in get_tree().get_nodes_in_group(&"placed_walls"):
		var node := wall_node as Node
		if node == null:
			continue
		if node.is_in_group(&"placed_doors") and "is_open" in node and bool(node.get("is_open")):
			continue
		if node.has_method("get_occupied_tile_coords"):
			for tile: Vector2i in node.call("get_occupied_tile_coords"):
				blocked[tile] = true
		elif "placed_at" in node:
			blocked[Vector2i(node.get("placed_at"))] = true
	return blocked


func _world_to_tile(world_position: Vector2) -> Variant:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	var ground := current_scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return null
	return ground.local_to_map(ground.to_local(world_position))


func _get_player() -> Node2D:
	return GameManager.get_player()


func _display_item_name(item_id: StringName) -> String:
	var data := ElementDatabase.get_element(item_id)
	if not data.is_empty():
		return str(data.get(&"display_name", item_id))
	return String(item_id).replace("_", " ").capitalize()


func _get_night_attraction_radius() -> float:
	match _get_loop_escalation_tier():
		2:
			return POST_TUTORIAL_NIGHT_ATTRACTION_RADIUS_TIER_TWO_PIXELS
		1:
			return POST_TUTORIAL_NIGHT_ATTRACTION_RADIUS_TIER_ONE_PIXELS
		_:
			return NIGHT_ATTRACTION_RADIUS_PIXELS


func _get_loop_escalation_tier() -> int:
	if GameManager == null:
		return 0
	if not GameManager.post_tutorial_loop_active:
		return 0
	if GameManager.current_day >= POST_TUTORIAL_ESCALATION_DAY_TIER_TWO:
		return 2
	if GameManager.current_day >= POST_TUTORIAL_ESCALATION_DAY_TIER_ONE:
		return 1
	return 0


func _refresh_loop_escalation_tier() -> void:
	var next_tier := _get_loop_escalation_tier()
	if next_tier <= _loop_escalation_tier:
		_loop_escalation_tier = next_tier
		return
	for tier in range(_loop_escalation_tier + 1, next_tier + 1):
		if EventBus != null and EventBus.has_method("emit_loop_milestone_reached"):
			EventBus.emit_loop_milestone_reached(tier)
	_loop_escalation_tier = next_tier


func _spawn_small_warning_flash(world_position: Vector2) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var flash := PointLight2D.new()
	flash.name = "VolatileStorageFlash"
	flash.global_position = world_position
	flash.energy = 1.2
	flash.color = Color(1.0, 0.64, 0.22, 1.0)
	current_scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "energy", 0.0, 0.45)
	tween.finished.connect(flash.queue_free, CONNECT_ONE_SHOT)
