class_name DiscoveryJournal
extends Node

const GameplayData = preload("res://scripts/GameplayData.gd")
# Autoload: DiscoveryJournal

signal journal_entry_added(entry: Dictionary)
signal journal_entry_updated(entry: Dictionary)

const DISCOVERY_DATA := {
	&"wood": {
		&"unlocks_recipe": [],
		&"next_hint": "Carbonise wood in the furnace to make charcoal.",
		&"hazard_notes": "Highly flammable. Keep it away from open ignition sources.",
		&"scanner_clue": "Organic lattice with strong burn potential.",
	},
	&"stone": {
		&"unlocks_recipe": [],
		&"next_hint": "Use stone for early structures and quarry upgrades.",
		&"hazard_notes": "Stable mineral with low reactivity.",
		&"scanner_clue": "Dense mineral mass with low volatility.",
	},
	&"iron": {
		&"unlocks_recipe": [StringName(&"wrought_iron"), StringName(&"steel"), StringName(&"cast_iron")],
		&"next_hint": "Try smelting iron with charcoal at 1200C or above.",
		&"hazard_notes": "Raw iron is safe to carry, but heat transforms its structure quickly.",
		&"scanner_clue": "Metal-rich ore source. Responds strongly to furnace refinement.",
	},
	&"charcoal": {
		&"unlocks_recipe": [StringName(&"wrought_iron"), StringName(&"steel"), StringName(&"cast_iron")],
		&"next_hint": "Pair charcoal with iron in the furnace and tune temperature carefully.",
		&"hazard_notes": "Combustible carbon source. Excess heat can overdrive reactions.",
		&"scanner_clue": "Carbon-dense fuel with strong furnace synergy.",
	},
	&"wrought_iron": {
		&"unlocks_recipe": [],
		&"next_hint": "Increase carbon ratio slightly to push toward steel.",
		&"hazard_notes": "Soft but workable metal. Low-carbon output bends under stress.",
		&"scanner_clue": "Refined iron with low carbon retention.",
	},
	&"steel": {
		&"unlocks_recipe": [],
		&"next_hint": "Build a chem bench to expand beyond metallurgy.",
		&"hazard_notes": "Stable finished alloy. Production window is narrow and heat sensitive.",
		&"scanner_clue": "Optimal iron-carbon alloy signature detected.",
	},
	&"cast_iron": {
		&"unlocks_recipe": [],
		&"next_hint": "Reduce carbon ratio to avoid brittle outcomes and reach steel instead.",
		&"hazard_notes": "Brittle high-carbon metal. Useful clue, poor general-purpose material.",
		&"scanner_clue": "Over-carbonized iron alloy with brittle structure.",
	},
	&"coke_slag": {
		&"unlocks_recipe": [],
		&"next_hint": "Too much carbon. Back off the ratio before trying again.",
		&"hazard_notes": "Waste byproduct. Indicates an overloaded furnace mix.",
		&"scanner_clue": "Reaction waste with collapsed useful structure.",
	},
	&"sulfur": {
		&"unlocks_recipe": [StringName(&"sulfuric_bolt"), StringName(&"distillation_kit")],
		&"next_hint": "Take sulfur to the chem bench and start with bolt compounds or distillation tools.",
		&"hazard_notes": "Carried sulfur can ignite at low HP, while burning, or near active heat sources. Store it in a Volatile Locker when possible. Exposed sulfur nodes degrade during Acid Mist.",
		&"scanner_clue": "Volatile yellow reagent with strong chemical branching paths.",
	},
	&"distillation_kit": {
		&"unlocks_recipe": [],
		&"next_hint": "Use distilled outputs and reactive materials at the chem bench.",
		&"hazard_notes": "Process tool. Safety depends on whatever it is distilling.",
		&"scanner_clue": "Precision apparatus tuned for separation and purification workflows.",
	},
	&"lithium": {
		&"unlocks_recipe": [],
		&"next_hint": "Keep lithium dry, then route it into power cells, traps, or late-base infrastructure.",
		&"hazard_notes": "Rain or open water drains lithium charge. Electrical storms recharge it slowly. Keep it dry or store it in a Dry Box.",
		&"scanner_clue": "Highly reactive light metal with strong charge-storage behavior.",
	},
	&"sodium": {
		&"unlocks_recipe": [],
		&"next_hint": "Keep sodium dry and use Sodium Shoals runs to practice water-safe cargo routing.",
		&"hazard_notes": "Sodium reacts violently with rain or standing water. Dry storage is mandatory.",
		&"scanner_clue": "Alkali metal crust with extreme water reactivity.",
	},
	&"mercury": {
		&"unlocks_recipe": [StringName(&"mercury_amalgam"), StringName(&"toxic_slurry")],
		&"next_hint": "Use mercury at the chem bench for amalgams or poison mixtures after contamination handling is logged.",
		&"hazard_notes": "Mercury vents toxic vapor under heat, acid mist, toxic exposure, or critical injury.",
		&"scanner_clue": "Dense liquid metal contamination trapped in shoals sediment.",
	},
	&"rust_bolt": {
		&"unlocks_recipe": [],
		&"next_hint": "Refine your chem bench process further with sulfur-bearing inputs.",
		&"hazard_notes": "Reactive ammunition. Corrosion products can spread on impact.",
		&"scanner_clue": "Low-tier chemical payload stabilized in bolt form.",
	},
	&"sulfuric_bolt": {
		&"unlocks_recipe": [],
		&"next_hint": "Push deeper into corrosive chemistry and stabilization work.",
		&"hazard_notes": "Acidic payload. Handle as a hazardous ranged compound.",
		&"scanner_clue": "Acid-bearing bolt with elevated chemical aggression.",
	},
	&"corrosive_slurry": {
		&"unlocks_recipe": [],
		&"next_hint": "Stabilize volatile mixtures before scaling production.",
		&"hazard_notes": "Corrosive suspension. Unsafe without controlled handling.",
		&"scanner_clue": "Unstable slurry with active corrosive response.",
	},
	&"mercury_amalgam": {
		&"unlocks_recipe": [],
		&"next_hint": "Use amalgam chemistry as a bridge into precision poison and metal-binding recipes.",
		&"hazard_notes": "Contains mercury. Keep away from heat and broken containers.",
		&"scanner_clue": "Mercury-wetted metal surface with stabilized contamination.",
	},
	&"toxic_slurry": {
		&"unlocks_recipe": [],
		&"next_hint": "Treat poison mixtures as payloads, not storage materials.",
		&"hazard_notes": "Toxic suspension. Exposure can compound mercury carrier risk.",
		&"scanner_clue": "Buffered mercury sulfide mixture with strong toxicity.",
	},
	&"explosion": {
		&"unlocks_recipe": [],
		&"next_hint": "Stay below the furnace danger threshold and narrow the ratio window.",
		&"hazard_notes": "Critical reaction failure caused by excessive temperature.",
		&"scanner_clue": "Runaway thermal signature. Immediate containment required.",
	},
}

var entries: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	_connect_sources()


func get_entry(element_id: StringName) -> Dictionary:
	if not entries.has(element_id):
		return {}
	return (entries[element_id] as Dictionary).duplicate(true)


func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[StringName] = []
	for element_id: StringName in entries.keys():
		ids.append(element_id)
	ids.sort()
	for element_id: StringName in ids:
		result.append(get_entry(element_id))
	return result


func has_entry(element_id: StringName) -> bool:
	return entries.has(element_id)


func clear() -> void:
	entries.clear()


func ensure_entry(element_id: StringName) -> Dictionary:
	if element_id.is_empty():
		return {}

	var existing: bool = has_entry(element_id)
	var entry: Dictionary = entries.get(element_id, {})
	var meta: Dictionary = DISCOVERY_DATA.get(element_id, {})
	var unlocks: Array[StringName] = []
	for recipe_id: StringName in meta.get(&"unlocks_recipe", []):
		unlocks.append(recipe_id)

	entry[&"element_id"] = element_id
	entry[&"discovered_at_day"] = GameManager.current_day if GameManager != null else 0
	entry[&"unlocks_recipe"] = unlocks
	entry[&"next_hint"] = str(meta.get(&"next_hint", _default_next_hint(element_id)))
	entry[&"hazard_notes"] = str(meta.get(&"hazard_notes", "No hazard notes recorded yet."))
	entry[&"scanner_clue"] = str(meta.get(&"scanner_clue", _default_scanner_clue(element_id)))
	entries[element_id] = entry

	if existing:
		journal_entry_updated.emit(entry.duplicate(true))
	else:
		journal_entry_added.emit(entry.duplicate(true))
	return entry.duplicate(true)


func _connect_sources() -> void:
	if GameplayData.elements() != null and not GameplayData.elements().element_discovered.is_connected(_on_element_discovered):
		GameplayData.elements().element_discovered.connect(_on_element_discovered)
	if EventBus.get_chemistry_engine() != null and not EventBus.get_chemistry_engine().reaction_evaluated.is_connected(_on_reaction_evaluated):
		EventBus.get_chemistry_engine().reaction_evaluated.connect(_on_reaction_evaluated)


func _on_element_discovered(element_id: StringName) -> void:
	ensure_entry(element_id)


func _on_reaction_evaluated(result: Dictionary) -> void:
	var raw_output = result.get("output_id", result.get(&"output_id", ""))
	if raw_output == null:
		return
	var output_id: StringName = StringName(str(raw_output))
	if output_id.is_empty():
		return
	ensure_entry(output_id)


func _default_next_hint(element_id: StringName) -> String:
	var recipe_ids: Array[StringName] = _get_recipe_ids_for_output(element_id)
	if not recipe_ids.is_empty():
		return "New recipe paths opened: %s" % ", ".join(_stringify_ids(recipe_ids))
	return "Record more scans and controlled reactions to expand this entry."


func _default_scanner_clue(element_id: StringName) -> String:
	var element_data: Dictionary = GameplayData.elements().get_element(element_id) if GameplayData.elements() != null else {}
	if element_data.is_empty():
		return "No scanner clue logged."
	return "Scanner tagged %s as %s." % [
		str(element_data.get(&"display_name", element_id)),
		str(element_data.get(&"category", "unknown material"))
	]


func _get_recipe_ids_for_output(output_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if GameplayData.recipes() == null or not GameplayData.recipes().has_method("get_recipes_for_output"):
		return result
	var recipes: Array[Dictionary] = GameplayData.recipes().get_recipes_for_output(output_id)
	for recipe: Dictionary in recipes:
		var recipe_id: StringName = StringName(recipe.get(&"id", &""))
		if not recipe_id.is_empty():
			result.append(recipe_id)
	return result


func _stringify_ids(ids: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in ids:
		result.append(String(value))
	return result
