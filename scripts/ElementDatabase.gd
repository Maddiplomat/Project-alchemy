extends Node

enum ElementCategory { ORGANIC, MINERAL, METAL, VOLATILE, GAS, RADIOACTIVE, CATALYST }
enum RiskLevel { NONE, LOW, MEDIUM, HIGH, EXTREME }
enum ExtractionTool { HAND, PICKAXE, FURNACE, DISTILLATION_KIT, PRESSURE_CHAMBER, BATTERY_STATION, CONTAINMENT_TONGS }

signal element_registered(element_id: StringName)
signal element_discovered(element_id: StringName)
signal element_updated(element_id: StringName)
signal database_ready(element_count: int)

var elements: Dictionary[StringName, Dictionary] = {}
var discovered_elements: Array[StringName] = []
var biome_elements: Dictionary[StringName, Array] = {}

var starter_element_ids: Array[StringName] = [&"wood_carbon", &"silicon", &"iron", &"pure_carbon"]
var mid_game_element_ids: Array[StringName] = [&"sulfur", &"lithium", &"phosphorus", &"nitrogen"]
var late_game_element_ids: Array[StringName] = [&"uranium", &"mercury", &"sodium", &"platinum"]


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
	for element_id: StringName in elements:
		if elements[element_id].get(&"category") == category:
			result.append(element_id)

	return result


func get_elements_by_risk(risk_level: RiskLevel) -> Array[StringName]:
	var result: Array[StringName] = []
	for element_id: StringName in elements:
		if elements[element_id].get(&"risk_level") == risk_level:
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
	biome_elements.clear()

	for element_data: Dictionary in _get_seed_element_data():
		register_element(element_data)


func _get_seed_element_data() -> Array[Dictionary]:
	return [
		_create_element(
			&"wood_carbon",
			"C",
			"Wood Carbon",
			ElementCategory.ORGANIC,
			RiskLevel.NONE,
			0.8,
			ExtractionTool.HAND,
			{
				&"flammability": 0.7,
				&"toxicity": 0.0,
				&"reactivity": 0.2,
				&"conductivity": 0.0,
				&"radiation": 0.0,
			},
			"Fallen branches and charcoal-rich bark in starter forests.",
			"",
			[&"starter_forest", &"iron_hills"],
			"Universal base material and early fuel."
		),
		_create_element(
			&"silicon",
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
				&"reactivity": 0.35,
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
			"Yellow crust near geothermal vents.",
			"Ignites if carried while the player is burning or severely overheated.",
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
			"Electric-blue shimmer in dry salt flats.",
			"Reacts violently with rain and open water.",
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
	primary_use: String
) -> Dictionary:
	return {
		&"id": element_id,
		&"symbol": symbol,
		&"display_name": display_name,
		&"category": category,
		&"risk_level": risk_level,
		&"weight": weight,
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
