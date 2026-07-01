extends Node
# Autoload: ResearchObjectives

signal objective_completed(objective_id: StringName)
signal objective_activated(objective_id: StringName)

const STARTER_SCAN_TARGETS: Array[StringName] = [&"wood", &"stone", &"iron"]
const FIRST_SMELT_OUTPUTS: Array[StringName] = [&"wrought_iron", &"steel", &"cast_iron"]
const SULFUR_FLATS_WEATHER_ENTRY_ID := &"sulfur_flats_weather_unlocked"
const CHEM_BENCH_ACCESS_ENTRY_ID := &"chem_bench_access"
const SULFUR_STORAGE_ENTRY_ID := &"sulfur_storage"
const DRY_BOX_ACCESS_ENTRY_ID := &"dry_box_access"
const BASE_POWER_ONLINE_ENTRY_ID := &"base_power_online"

var objectives: Dictionary[StringName, Dictionary] = {}

var _objective_order: Array[StringName] = []
var _progress: Dictionary[StringName, int] = {}
var _scanner_tools: Array[Node] = []


func _ready() -> void:
	_seed_objectives()
	_connect_completion_hooks()
	_activate_first_incomplete()


func get_objective(id: StringName) -> Dictionary:
	return objectives.get(id, {}).duplicate(true)


func get_active_objective() -> Dictionary:
	for objective_id: StringName in _objective_order:
		var objective: Dictionary = objectives.get(objective_id, {})
		if bool(objective.get(&"active", false)):
			return objective.duplicate(true)
	return {}


func get_all_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective_id: StringName in _objective_order:
		result.append(get_objective(objective_id))
	return result


func _connect_completion_hooks() -> void:
	if ElementDatabase != null and not ElementDatabase.element_discovered.is_connected(_on_element_discovered):
		ElementDatabase.element_discovered.connect(_on_element_discovered)
	if EventBus != null and EventBus.has_signal("crafting_completed") and not EventBus.crafting_completed.is_connected(_on_crafting_completed):
		EventBus.crafting_completed.connect(_on_crafting_completed)
	if InventoryManager != null and not InventoryManager.inventory_changed.is_connected(_on_inventory_changed):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	if EventBus != null and EventBus.has_signal("buildable_placed") and not EventBus.buildable_placed.is_connected(_on_buildable_placed):
		EventBus.buildable_placed.connect(_on_buildable_placed)
	if GameManager != null and GameManager.has_signal("scanner_tier_changed") and not GameManager.scanner_tier_changed.is_connected(_on_scanner_tier_changed):
		GameManager.scanner_tier_changed.connect(_on_scanner_tier_changed)
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)

	for node in get_tree().get_nodes_in_group(&"scanner_tool"):
		_bind_scanner_tool(node)


func _seed_objectives() -> void:
	objectives.clear()
	_objective_order.clear()
	_progress.clear()

	_add_objective({
		&"id": &"scan_starters",
		&"title": "Scan the Basics",
		&"hint": "Scan wood, stone, and iron with the scanner.",
		&"condition_type": "scan",
		&"condition_target": &"starter_elements",
		&"condition_count": 3,
		&"reward_type": "unlock_recipe",
		&"reward_target": &"charcoal",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"make_charcoal",
		&"title": "Make Charcoal",
		&"hint": "Produce charcoal for your first proper fuel source.",
		&"condition_type": "craft",
		&"condition_target": &"charcoal",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": &"charcoal",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"first_smelt",
		&"title": "First Smelt",
		&"hint": "Smelt iron with charcoal and produce any iron output.",
		&"condition_type": "craft",
		&"condition_target": &"iron_output",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": &"wrought_iron",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"discover_steel",
		&"title": "Discover Steel",
		&"hint": "Find the right furnace window to discover steel.",
		&"condition_type": "discover",
		&"condition_target": &"steel",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": CHEM_BENCH_ACCESS_ENTRY_ID,
		&"reward_entry_title": "Chem Bench Plans",
		&"reward_entry_notes": "Steelwork unlocks the chem bench build and opens your first reactive station.",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"build_chem_bench",
		&"title": "Build a Chem Bench",
		&"hint": "Place a chem bench back at base.",
		&"condition_type": "build",
		&"condition_target": &"chem_bench",
		&"condition_count": 1,
		&"reward_type": "unlock_recipe",
		&"reward_target": &"distillation_kit",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"distillation_kit",
		&"title": "Craft a Distillation Kit",
		&"hint": "Assemble a distillation kit at the chem bench.",
		&"condition_type": "craft",
		&"condition_target": &"distillation_kit",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": &"sulfur",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"reach_sulfur_flats",
		&"title": "Reach the Sulfur Flats",
		&"hint": "Push into the sulfur flats and log the weather shift there.",
		&"condition_type": "discover",
		&"condition_target": SULFUR_FLATS_WEATHER_ENTRY_ID,
		&"condition_count": 1,
		&"reward_type": "",
		&"reward_target": &"",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"sulfur_run",
		&"title": "Sulfur Run",
		&"hint": "Bring sulfur back alive and do not leave it riding in your pack.",
		&"condition_type": "collect",
		&"condition_target": &"sulfur",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": SULFUR_STORAGE_ENTRY_ID,
		&"reward_entry_title": "Volatile Storage",
		&"reward_entry_notes": "Sulfur handling now warrants a dedicated Volatile Locker instead of open carry.",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"build_volatile_locker",
		&"title": "Build a Volatile Locker",
		&"hint": "Place a Volatile Locker so sulfur enters base storage as its own system.",
		&"condition_type": "build",
		&"condition_target": &"volatile_locker",
		&"condition_count": 1,
		&"reward_type": "",
		&"reward_target": &"",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"recover_lithium",
		&"title": "Recover Lithium",
		&"hint": "Bring back lithium and treat weather exposure as part of the resource.",
		&"condition_type": "collect",
		&"condition_target": &"lithium",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": DRY_BOX_ACCESS_ENTRY_ID,
		&"reward_entry_title": "Dry Storage Plans",
		&"reward_entry_notes": "Lithium handling unlocks the Dry Box for weather-safe storage and staging.",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"build_dry_box",
		&"title": "Build a Dry Box",
		&"hint": "Place a Dry Box before lithium becomes routine cargo.",
		&"condition_type": "build",
		&"condition_target": &"dry_box",
		&"condition_count": 1,
		&"reward_type": "",
		&"reward_target": &"",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"charge_base",
		&"title": "Charge the Base Grid",
		&"hint": "Use lithium and iron at the Battery Station, then slot an energy cell into the grid.",
		&"condition_type": "upgrade",
		&"condition_target": &"advanced_scanner",
		&"condition_count": 1,
		&"reward_type": "unlock_journal",
		&"reward_target": BASE_POWER_ONLINE_ENTRY_ID,
		&"reward_entry_title": "Base Grid Online",
		&"reward_entry_notes": "Charged grid power unlocks perimeter lighting and trap placement from one shared source.",
		&"completed": false,
		&"active": false,
	})
	_add_objective({
		&"id": &"power_defenses",
		&"title": "Set a Powered Perimeter",
		&"hint": "Place a Powered Light or Electric Trap to bring base defense online through the battery grid.",
		&"condition_type": "build",
		&"condition_target": &"powered_defense",
		&"condition_count": 1,
		&"reward_type": "",
		&"reward_target": &"",
		&"completed": false,
		&"active": false,
	})


func _add_objective(objective: Dictionary) -> void:
	var objective_id := StringName(objective.get(&"id", &""))
	if objective_id.is_empty():
		return
	objectives[objective_id] = objective.duplicate(true)
	_objective_order.append(objective_id)
	_progress[objective_id] = 0


func _activate_first_incomplete() -> void:
	for objective_id: StringName in _objective_order:
		var objective: Dictionary = objectives.get(objective_id, {})
		if not bool(objective.get(&"completed", false)):
			_set_active_objective(objective_id)
			_refresh_active_objective()
			return
	_clear_active_flags()


func _set_active_objective(objective_id: StringName) -> void:
	var already_active := false
	for id: StringName in _objective_order:
		var objective: Dictionary = objectives.get(id, {})
		var should_be_active := id == objective_id
		already_active = already_active or (should_be_active and bool(objective.get(&"active", false)))
		objective[&"active"] = should_be_active
		objectives[id] = objective
	if not already_active:
		objective_activated.emit(objective_id)


func _clear_active_flags() -> void:
	for objective_id: StringName in _objective_order:
		var objective: Dictionary = objectives.get(objective_id, {})
		objective[&"active"] = false
		objectives[objective_id] = objective


func _complete_objective(objective_id: StringName) -> void:
	var objective: Dictionary = objectives.get(objective_id, {})
	if objective.is_empty() or bool(objective.get(&"completed", false)):
		return

	objective[&"completed"] = true
	objective[&"active"] = false
	objectives[objective_id] = objective
	_apply_reward(objective)
	objective_completed.emit(objective_id)
	_activate_first_incomplete()


func _apply_reward(objective: Dictionary) -> void:
	var reward_type := str(objective.get(&"reward_type", ""))
	var reward_target := StringName(objective.get(&"reward_target", &""))
	if reward_type.is_empty() or reward_target.is_empty():
		return

	match reward_type:
		"unlock_recipe":
			if RecipeDatabase != null:
				RecipeDatabase.unlock_recipe(reward_target)
		"unlock_journal":
			if DiscoveryLog != null and DiscoveryLog.has_method("log_progression_discovery"):
				var title := str(objective.get(&"reward_entry_title", objective.get(&"title", "Objective Reward")))
				var notes := str(objective.get(&"reward_entry_notes", ""))
				if notes.is_empty():
					notes = "Research objective reward unlocked: %s" % String(reward_target).replace("_", " ").capitalize()
				DiscoveryLog.log_progression_discovery(reward_target, title, notes)
		"unlock_upgrade":
			pass


func _refresh_active_objective() -> void:
	var objective := get_active_objective()
	if objective.is_empty():
		return

	var objective_id := StringName(objective.get(&"id", &""))
	match objective_id:
		&"scan_starters":
			if _get_scan_progress() >= int(objective.get(&"condition_count", 0)):
				_complete_objective(objective_id)
		&"make_charcoal":
			if InventoryManager != null and InventoryManager.get_stack(&"charcoal").quantity >= 1:
				_complete_objective(objective_id)
		&"first_smelt":
			for output_id: StringName in FIRST_SMELT_OUTPUTS:
				if ElementDatabase != null and ElementDatabase.is_element_discovered(output_id):
					_complete_objective(objective_id)
					return
		&"discover_steel":
			if ElementDatabase != null and ElementDatabase.is_element_discovered(&"steel"):
				_complete_objective(objective_id)
		&"build_chem_bench":
			if _has_placed_buildable(&"chem_bench"):
				_complete_objective(objective_id)
		&"distillation_kit":
			if InventoryManager != null and InventoryManager.get_stack(&"distillation_kit").quantity >= 1:
				_complete_objective(objective_id)
		&"reach_sulfur_flats":
			if DiscoveryLog != null and DiscoveryLog.has_method("has_discovery") and DiscoveryLog.has_discovery(SULFUR_FLATS_WEATHER_ENTRY_ID):
				_complete_objective(objective_id)
		&"sulfur_run":
			if InventoryManager != null and InventoryManager.get_stack(&"sulfur").quantity >= 1:
				_complete_objective(objective_id)
		&"build_volatile_locker":
			if _has_placed_buildable(&"volatile_locker"):
				_complete_objective(objective_id)
		&"recover_lithium":
			if InventoryManager != null and InventoryManager.get_stack(&"lithium").quantity >= 1:
				_complete_objective(objective_id)
			elif ElementDatabase != null and ElementDatabase.is_element_discovered(&"lithium"):
				_complete_objective(objective_id)
		&"build_dry_box":
			if _has_placed_buildable(&"dry_box"):
				_complete_objective(objective_id)
		&"charge_base":
			if GameManager != null and GameManager.scanner_tier == GameManager.ScannerTier.ADVANCED:
				_complete_objective(objective_id)
		&"power_defenses":
			if _has_placed_any_buildable([&"powered_light_post", &"electric_trap"]):
				_complete_objective(objective_id)


func _on_tree_node_added(node: Node) -> void:
	_bind_scanner_tool(node)


func _bind_scanner_tool(node: Node) -> void:
	if node == null or _scanner_tools.has(node):
		return
	if not node.has_signal("scan_completed"):
		return
	var scan_callable := Callable(self, "_on_scan_completed")
	if not node.is_connected("scan_completed", scan_callable):
		node.connect("scan_completed", scan_callable)
	node.tree_exited.connect(_on_scanner_tool_exited.bind(node), CONNECT_ONE_SHOT)
	_scanner_tools.append(node)


func _on_scanner_tool_exited(node: Node) -> void:
	_scanner_tools.erase(node)


func _on_scan_completed(element_id: StringName) -> void:
	if not _is_active_objective(&"scan_starters"):
		return
	if not STARTER_SCAN_TARGETS.has(element_id):
		return

	_progress[&"scan_starters"] = _get_scan_progress()
	if _get_scan_progress() >= 3:
		_complete_objective(&"scan_starters")


func _on_crafting_completed(recipe_id: StringName, output: Dictionary) -> void:
	if _is_active_objective(&"make_charcoal") and recipe_id == &"charcoal":
		_progress[&"make_charcoal"] = 1
		_complete_objective(&"make_charcoal")
		return

	if _is_active_objective(&"first_smelt"):
		var output_id := StringName(output.get(&"id", output.get(&"item_id", &"")))
		if FIRST_SMELT_OUTPUTS.has(recipe_id) or FIRST_SMELT_OUTPUTS.has(output_id):
			_progress[&"first_smelt"] = 1
			_complete_objective(&"first_smelt")
			return

	if _is_active_objective(&"distillation_kit") and recipe_id == &"distillation_kit":
		_progress[&"distillation_kit"] = 1
		_complete_objective(&"distillation_kit")


func _on_element_discovered(element_id: StringName) -> void:
	if _is_active_objective(&"first_smelt") and FIRST_SMELT_OUTPUTS.has(element_id):
		_progress[&"first_smelt"] = 1
		_complete_objective(&"first_smelt")
		return

	if _is_active_objective(&"discover_steel") and element_id == &"steel":
		_progress[&"discover_steel"] = 1
		_complete_objective(&"discover_steel")


func _on_inventory_changed(_slot_index: int) -> void:
	_refresh_active_objective()


func _on_buildable_placed(buildable_id: StringName) -> void:
	match buildable_id:
		&"chem_bench":
			if _is_active_objective(&"build_chem_bench"):
				_progress[&"build_chem_bench"] = 1
				_complete_objective(&"build_chem_bench")
		&"volatile_locker":
			if _is_active_objective(&"build_volatile_locker"):
				_progress[&"build_volatile_locker"] = 1
				_complete_objective(&"build_volatile_locker")
		&"dry_box":
			if _is_active_objective(&"build_dry_box"):
				_progress[&"build_dry_box"] = 1
				_complete_objective(&"build_dry_box")
		&"powered_light_post", &"electric_trap":
			if _is_active_objective(&"power_defenses"):
				_progress[&"power_defenses"] = 1
				_complete_objective(&"power_defenses")


func _on_scanner_tier_changed(_previous_tier: int, new_tier: int) -> void:
	if not _is_active_objective(&"charge_base"):
		return
	if new_tier != GameManager.ScannerTier.ADVANCED:
		return
	_progress[&"charge_base"] = 1
	_complete_objective(&"charge_base")


func _is_active_objective(objective_id: StringName) -> bool:
	var objective: Dictionary = objectives.get(objective_id, {})
	return not objective.is_empty() and bool(objective.get(&"active", false)) and not bool(objective.get(&"completed", false))


func _get_scan_progress() -> int:
	var total := 0
	for element_id: StringName in STARTER_SCAN_TARGETS:
		if ElementDatabase != null and ElementDatabase.has_method("is_element_scanned") and ElementDatabase.is_element_scanned(element_id):
			total += 1
	return total


func _has_placed_buildable(buildable_id: StringName) -> bool:
	for node in get_tree().get_nodes_in_group(&"placed_objects"):
		if not (node is Node):
			continue
		var object_type := StringName((node as Node).get_meta(&"object_type", &""))
		if object_type == buildable_id:
			return true
	return false


func _has_placed_any_buildable(buildable_ids: Array[StringName]) -> bool:
	for buildable_id: StringName in buildable_ids:
		if _has_placed_buildable(buildable_id):
			return true
	return false
