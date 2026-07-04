extends Node

enum ElementCategory { ORGANIC, MINERAL, METAL, VOLATILE, GAS, RADIOACTIVE, CATALYST }
enum RiskLevel { NONE, LOW, MEDIUM, HIGH, EXTREME }
enum ExtractionTool { HAND, PICKAXE, FURNACE, DISTILLATION_KIT, PRESSURE_CHAMBER, BATTERY_STATION, CONTAINMENT_TONGS }

signal element_registered(element_id: StringName)
signal element_discovered(element_id: StringName)
signal element_scanned(element_id: StringName)
signal element_updated(element_id: StringName)
signal database_ready(element_count: int)

var elements: Dictionary[StringName, Dictionary] = {}
var discovered_elements: Array[StringName] = []
var scanned_elements: Dictionary[StringName, bool] = {}
var biome_elements: Dictionary[StringName, Array] = {}

const ELEMENT_DATA_DIR := "res://data/elements"

var starter_element_ids: Array[StringName] = [&"wood", &"stone", &"iron"]
var mid_game_element_ids: Array[StringName] = []
var late_game_element_ids: Array[StringName] = []


func _ready() -> void:
	_seed_elements()
	database_ready.emit(elements.size())



func has_element(element_id: StringName) -> bool:
	return elements.has(element_id)


func get_element(element_id: StringName) -> Dictionary:
	if not has_element(element_id):
		return {}

	return elements[element_id].duplicate(true)


func get_elements_for_biome(biome_id: StringName) -> Array[StringName]:
	if not biome_elements.has(biome_id):
		return []

	var result: Array[StringName] = []
	for element_id: StringName in biome_elements[biome_id]:
		result.append(element_id)

	return result


func get_elements_by_category(category: ElementCategory) -> Array[StringName]:
	var result: Array[StringName] = []
	var category_name := _category_to_string(category)
	for element_id: StringName in elements:
		var element_category = elements[element_id].get(&"category")
		if element_category == category or element_category == category_name:
			result.append(element_id)

	return result


func get_elements_by_risk(risk_level: RiskLevel) -> Array[StringName]:
	var result: Array[StringName] = []
	var risk_name := _risk_to_string(risk_level)
	for element_id: StringName in elements:
		var element_risk = elements[element_id].get(&"risk_level", elements[element_id].get(&"carrier_risk"))
		if element_risk == risk_level or element_risk == risk_name:
			result.append(element_id)

	return result


func discover_element(element_id: StringName) -> bool:
	if not has_element(element_id) or discovered_elements.has(element_id):
		return false

	discovered_elements.append(element_id)
	element_discovered.emit(element_id)
	return true


func is_element_discovered(element_id: StringName) -> bool:
	return discovered_elements.has(element_id)


func mark_element_scanned(element_id: StringName) -> bool:
	if not has_element(element_id) or scanned_elements.has(element_id):
		return false

	scanned_elements[element_id] = true
	element_scanned.emit(element_id)
	return true


func is_element_scanned(element_id: StringName) -> bool:
	return scanned_elements.has(element_id)


func get_scanned_elements() -> Array[StringName]:
	var result: Array[StringName] = []
	for element_id: StringName in scanned_elements.keys():
		result.append(element_id)
	result.sort()
	return result


func capture_persistent_state() -> Dictionary:
	return {
		"scanned_elements": get_scanned_elements(),
	}


func restore_persistent_state(data: Dictionary) -> void:
	scanned_elements.clear()
	for raw_element_id in data.get("scanned_elements", []):
		var element_id := StringName(str(raw_element_id))
		if not has_element(element_id):
			continue
		scanned_elements[element_id] = true


func clear_scanned_elements() -> void:
	scanned_elements.clear()


func register_element(element_data: Dictionary) -> bool:
	var element_id: StringName = element_data.get(&"id", &"")
	if element_id.is_empty():
		return false

	var is_new_element := not elements.has(element_id)
	elements[element_id] = element_data.duplicate(true)
	_rebuild_biome_index()

	if is_new_element:
		element_registered.emit(element_id)
	else:
		element_updated.emit(element_id)

	return true


func _seed_elements() -> void:
	elements.clear()
	discovered_elements.clear()
	scanned_elements.clear()
	biome_elements.clear()

	var seed_data := _load_element_data_files()
	if seed_data.is_empty():
		seed_data = _get_seed_element_data()

	for element_data: Dictionary in seed_data:
		register_element(element_data)


func _load_element_data_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file_names := DirAccess.get_files_at(ELEMENT_DATA_DIR)

	for file_name in file_names:
		if not file_name.ends_with(".json"):
			continue

		var file_path := ELEMENT_DATA_DIR.path_join(file_name)
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			push_warning("Unable to open element data file: %s" % file_path)
			continue

		var parsed = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary:
			push_warning("Skipping invalid element data file: %s" % file_path)
			continue

		var element_data := _normalize_element_data(parsed)
		if element_data.is_empty():
			push_warning("Skipping incomplete element data file: %s" % file_path)
			continue

		result.append(element_data)

	return result


func _normalize_element_data(raw_data: Dictionary) -> Dictionary:
	var required_keys := [
		&"id",
		&"symbol",
		&"display_name",
		&"category",
		&"weight",
		&"stress_multiplier",
		&"properties",
		&"carrier_risk",
		&"biome_spawn",
	]
	for key: StringName in required_keys:
		if not raw_data.has(key):
			return {}

	var raw_properties = raw_data.get(&"properties")
	if not raw_properties is Dictionary:
		return {}

	var raw_biomes = raw_data.get(&"biome_spawn")
	if not raw_biomes is Array:
		return {}

	var normalized_biomes: Array[StringName] = []
	for biome in raw_biomes:
		normalized_biomes.append(StringName(str(biome)))

	return {
		&"id": StringName(str(raw_data.get(&"id"))),
		&"symbol": str(raw_data.get(&"symbol")),
		&"display_name": str(raw_data.get(&"display_name")),
		&"category": str(raw_data.get(&"category")),
		&"weight": float(raw_data.get(&"weight")),
		&"stress_multiplier": float(raw_data.get(&"stress_multiplier")),
		&"extraction_tool": raw_data.get(&"extraction_tool", ""),
		&"properties": raw_properties.duplicate(true),
		&"carrier_risk_conditions": raw_data.get(&"carrier_risk_conditions", {}).duplicate(true) if raw_data.get(&"carrier_risk_conditions", {}) is Dictionary else {},
		&"environmental_hint": str(raw_data.get(&"environmental_hint", "")),
		&"carrier_risk": raw_data.get(&"carrier_risk"),
		&"biome_spawn": normalized_biomes,
	}


func _category_to_string(category: ElementCategory) -> String:
	match category:
		ElementCategory.ORGANIC:
			return "organic"
		ElementCategory.MINERAL:
			return "mineral"
		ElementCategory.METAL:
			return "metal"
		ElementCategory.VOLATILE:
			return "volatile"
		ElementCategory.GAS:
			return "gas"
		ElementCategory.RADIOACTIVE:
			return "radioactive"
		ElementCategory.CATALYST:
			return "catalyst"
		_:
			return ""


func _risk_to_string(risk_level: RiskLevel) -> String:
	match risk_level:
		RiskLevel.NONE:
			return "none"
		RiskLevel.LOW:
			return "low"
		RiskLevel.MEDIUM:
			return "medium"
		RiskLevel.HIGH:
			return "high"
		RiskLevel.EXTREME:
			return "extreme"
		_:
			return ""


func _get_seed_element_data() -> Array[Dictionary]:
	return [
		_create_element(
			&"wood",
			"C",
			"Wood Carbon",
			ElementCategory.ORGANIC,
			RiskLevel.NONE,
			0.8,
			ExtractionTool.HAND,
			{
				&"flammability": 0.9,
				&"toxicity": 0.0,
				&"reactivity": 0.2,
				&"carbon_pct_when_burned": 0.12,
				&"steel_window_carbon_min_pct": 0.5,
				&"steel_window_carbon_max_pct": 2.1,
				&"fuel_value": 200.0,
				&"conductivity": 0.0,
				&"radiation": 0.0,
			},
			"Fallen branches and charcoal-rich bark in starter forests.",
			"",
			[&"starter_forest", &"iron_hills"],
			"Universal base material and early fuel."
		),
		_create_element(
			&"stone",
			"Si",
			"Stone Silicon",
			ElementCategory.MINERAL,
			RiskLevel.NONE,
			1.5,
			ExtractionTool.PICKAXE,
			{
				&"flammability": 0.0,
				&"toxicity": 0.0,
				&"reactivity": 0.1,
				&"conductivity": 0.1,
				&"radiation": 0.0,
			},
			"Pale stone seams in rocky ground.",
			"",
			[&"starter_forest", &"iron_hills", &"crystal_caverns"],
			"Tools, building, and precision components."
		),
		_create_element(
			&"iron",
			"Fe",
			"Iron",
			ElementCategory.METAL,
			RiskLevel.LOW,
			2.8,
			ExtractionTool.PICKAXE,
			{
				&"flammability": 0.0,
				&"toxicity": 0.0,
				&"reactivity": 0.4,
				&"melting_point": 1538.0,
				&"conductivity": 0.55,
				&"radiation": 0.0,
			},
			"Rust-red ore bands exposed on hillsides.",
			"Rusts during rain unless protected.",
			[&"iron_hills", &"starter_forest", &"deep_mines"],
			"Weapons, structures, and steel alloys."
		),
		_create_element(
			&"pure_carbon",
			"C+",
			"Pure Carbon",
			ElementCategory.ORGANIC,
			RiskLevel.LOW,
			1.0,
			ExtractionTool.FURNACE,
			{
				&"flammability": 0.85,
				&"toxicity": 0.05,
				&"reactivity": 0.45,
				&"carbon_percentage": 0.85,
				&"steel_window_carbon_min_pct": 0.6,
				&"steel_window_carbon_max_pct": 2.5,
				&"fuel_value": 600.0,
				&"conductivity": 0.15,
				&"radiation": 0.0,
			},
			"Refined from burned organic matter or coal deposits.",
			"Burns quickly near open flame.",
			[&"starter_forest", &"iron_hills", &"deep_mines"],
			"Alloys, fuel, and compressed carbon upgrades."
		),
		_create_element(
			&"sulfur",
			"S",
			"Sulfur",
			ElementCategory.VOLATILE,
			RiskLevel.MEDIUM,
			1.2,
			ExtractionTool.DISTILLATION_KIT,
			{
				&"flammability": 0.9,
				&"toxicity": 0.3,
				&"reactivity": 0.8,
				&"conductivity": 0.0,
				&"radiation": 0.0,
			},
			"Yellow crust near geothermal vents and unstable weather pockets.",
			"Carried sulfur ignites at low HP, while burning, or near active heat sources. Exposed sulfur nodes degrade during Acid Mist.",
			[&"sulfur_flats", &"volcanic", &"cave_deep"],
			"Explosives, acids, and sulfuric weapons."
		),
		_create_element(
			&"lithium",
			"Li",
			"Lithium",
			ElementCategory.VOLATILE,
			RiskLevel.HIGH,
			0.7,
			ExtractionTool.BATTERY_STATION,
			{
				&"flammability": 0.65,
				&"toxicity": 0.2,
				&"reactivity": 0.95,
				&"conductivity": 0.8,
				&"radiation": 0.0,
			},
			"Electric-blue shimmer in dry, storm-prone flats.",
			"Rain or open water drains charge. Electrical storms recharge it slowly if you keep carrying it.",
			[&"lithium_wastes", &"deep_mines"],
			"Batteries, charge cells, and high-risk energy tech."
		),
		_create_element(
			&"phosphorus",
			"P",
			"Phosphorus",
			ElementCategory.VOLATILE,
			RiskLevel.HIGH,
			1.1,
			ExtractionTool.DISTILLATION_KIT,
			{
				&"flammability": 0.95,
				&"toxicity": 0.45,
				&"reactivity": 0.85,
				&"conductivity": 0.05,
				&"radiation": 0.0,
			},
			"Soft glow in sulfur flats and old bone deposits.",
			"Self-ignites if stored hot or exposed to oxygen spikes.",
			[&"sulfur_flats", &"cave_deep"],
			"Fire weapons, light sources, and volatile compounds."
		),
		_create_element(
			&"nitrogen",
			"N",
			"Nitrogen",
			ElementCategory.GAS,
			RiskLevel.LOW,
			0.4,
			ExtractionTool.PRESSURE_CHAMBER,
			{
				&"flammability": 0.0,
				&"toxicity": 0.1,
				&"reactivity": 0.35,
				&"conductivity": 0.0,
				&"radiation": 0.0,
			},
			"Lush growth and rich soil patches.",
			"Pressurized canisters can rupture under impact.",
			[&"starter_forest", &"lithium_wastes"],
			"Fertilizer, pressurized gas, and energy path materials."
		),
		_create_element(
			&"uranium",
			"U",
			"Uranium",
			ElementCategory.RADIOACTIVE,
			RiskLevel.EXTREME,
			4.5,
			ExtractionTool.CONTAINMENT_TONGS,
			{
				&"flammability": 0.0,
				&"toxicity": 0.8,
				&"reactivity": 0.6,
				&"conductivity": 0.2,
				&"radiation": 1.0,
			},
			"Dead plants in a circular pattern around green-glowing ore.",
			"Applies radiation exposure without containment.",
			[&"deep_mines"],
			"Power sources, radiation fields, and late-game mastery."
		),
		_create_element(
			&"mercury",
			"Hg",
			"Mercury",
			ElementCategory.METAL,
			RiskLevel.HIGH,
			3.4,
			ExtractionTool.CONTAINMENT_TONGS,
			{
				&"flammability": 0.0,
				&"toxicity": 0.9,
				&"reactivity": 0.4,
				&"conductivity": 0.6,
				&"radiation": 0.0,
			},
			"Silver liquid beads in deep mine cracks.",
			"Toxic vapor builds if heated or stored in damaged containers.",
			[&"deep_mines", &"crystal_caverns"],
			"Poison weapons, amalgams, and exotic crafting."
		),
		_create_element(
			&"sodium",
			"Na",
			"Sodium",
			ElementCategory.VOLATILE,
			RiskLevel.HIGH,
			0.9,
			ExtractionTool.CONTAINMENT_TONGS,
			{
				&"flammability": 0.75,
				&"toxicity": 0.15,
				&"reactivity": 1.0,
				&"conductivity": 0.5,
				&"radiation": 0.0,
			},
			"White mineral crusts in dry, storm-prone wastes.",
			"Explodes on water exposure.",
			[&"lithium_wastes"],
			"Explosive water reactions and high-risk chemistry."
		),
		_create_element(
			&"platinum",
			"Pt",
			"Platinum",
			ElementCategory.CATALYST,
			RiskLevel.LOW,
			3.9,
			ExtractionTool.PICKAXE,
			{
				&"flammability": 0.0,
				&"toxicity": 0.0,
				&"reactivity": 0.15,
				&"conductivity": 0.9,
				&"radiation": 0.0,
			},
			"Rare bright veins in crystal caverns and deep mines.",
			"",
			[&"deep_mines", &"crystal_caverns"],
			"Catalysts and precision crafting."
		),
	]


func _create_element(
	element_id: StringName,
	symbol: String,
	display_name: String,
	category: ElementCategory,
	risk_level: RiskLevel,
	weight: float,
	extraction_tool: ExtractionTool,
	properties: Dictionary,
	environmental_hint: String,
	carrier_risk: String,
	biome_spawn: Array[StringName],
	primary_use: String,
	stress_multiplier: float = 1.0
) -> Dictionary:
	return {
		&"id": element_id,
		&"symbol": symbol,
		&"display_name": display_name,
		&"category": category,
		&"risk_level": risk_level,
		&"weight": weight,
		&"stress_multiplier": stress_multiplier,
		&"extraction_tool": extraction_tool,
		&"properties": properties,
		&"environmental_hint": environmental_hint,
		&"carrier_risk": carrier_risk,
		&"biome_spawn": biome_spawn,
		&"primary_use": primary_use,
	}


func _rebuild_biome_index() -> void:
	biome_elements.clear()

	for element_id: StringName in elements:
		var biome_spawn: Array = elements[element_id].get(&"biome_spawn", [])
		for biome_id: StringName in biome_spawn:
			if not biome_elements.has(biome_id):
				biome_elements[biome_id] = []

			if not biome_elements[biome_id].has(element_id):
				biome_elements[biome_id].append(element_id)
