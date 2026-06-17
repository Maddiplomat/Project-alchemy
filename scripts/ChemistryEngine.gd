extends Node

## ChemistryEngine Autoload
## Handles element reactions based on temperature and ratios.

signal reaction_evaluated(result: Dictionary)
signal heat_event(source_node: Node, radius: float, intensity: float)

const CHEM_BENCH_REACTION_DATA_PATH := "res://data/chemistry/chem_bench_reactions.json"

var _chem_bench_reaction_families: Array[Dictionary] = []
var _chem_bench_reactant_ids: Array[StringName] = []


func _ready() -> void:
	_load_chem_bench_reactions()


func evaluate_reaction(element_a, element_b, ratio_b_pct: float, temp: float) -> Dictionary:
	var result = {
		"output_id": null,
		"quality": 0.0,
		"tier": "unknown",
		"notes": ""
	}

	var normalized_a := _normalize_element_ref(element_a)
	var normalized_b := _normalize_element_ref(element_b)
	if _is_carbonisation_request(normalized_a, normalized_b):
		result = _evaluate_carbonisation(temp)
		reaction_evaluated.emit(result)
		return result

	var element_a_data := _get_element_data(normalized_a)
	var element_b_data := _get_element_data(normalized_b)
	var is_iron_a := _is_iron_source(normalized_a, element_a_data)
	var is_iron_b := _is_iron_source(normalized_b, element_b_data)
	var carbon_pct_a := get_carbon_percentage(normalized_a)
	var carbon_pct_b := get_carbon_percentage(normalized_b)
	var carbon_ratio := 0.0
	var is_valid_pair := false

	# Convert material ratio into effective carbon content using element data.
	if is_iron_a and carbon_pct_b > 0.0:
		is_valid_pair = true
		carbon_ratio = ratio_b_pct * carbon_pct_b
	elif is_iron_b and carbon_pct_a > 0.0:
		is_valid_pair = true
		carbon_ratio = (100.0 - ratio_b_pct) * carbon_pct_a

	if is_valid_pair:
		var ratio := carbon_ratio
		if temp >= 1600.0:
			result.output_id = "explosion"
			result.quality = 0.0
			result.tier = "danger"
			result.notes = "If heat > 1600°C — radius 2 tiles"
		elif temp < 1200.0:
			result.notes = "Heat too low for reaction (1200°C-1600°C required)"
		else:
			if ratio < 0.5:
				result.output_id = "wrought_iron"
				result.quality = 0.6
				result.tier = "low"
				result.notes = "Soft, bends — usable but weak"
			elif ratio >= 0.5 and ratio <= 2.1:
				result.output_id = "steel"
				result.quality = 1.0
				result.tier = "optimal"
				result.notes = "Optimal — triggers Discovery Journal"
			elif ratio > 2.1 and ratio <= 4.5:
				result.output_id = "cast_iron"
				result.quality = 0.4
				result.tier = "medium"
				result.notes = "Brittle — logs failed attempt"
			elif ratio > 4.5:
				result.output_id = "coke_slag"
				result.quality = 0.0
				result.tier = "waste"
				result.notes = "Useless — logs as 'Unknown compound'"

	reaction_evaluated.emit(result)
	return result


func emit_heat_event(source_node: Node, radius: float, intensity: float) -> void:
	if source_node == null or not is_instance_valid(source_node):
		return
	heat_event.emit(source_node, maxf(radius, 0.0), maxf(intensity, 0.0))


func evaluate_chem_bench_reaction(state: Dictionary) -> Dictionary:
	_ensure_chem_bench_reactions_loaded()
	var input_a := _normalize_bench_slot_state(state.get(&"input_a", {}))
	var input_b := _normalize_bench_slot_state(state.get(&"input_b", {}))
	var catalyst := _normalize_bench_slot_state(state.get(&"catalyst", {}))
	var ratio_target_slot := _normalize_ratio_target_slot(StringName(state.get(&"ratio_target_slot", &"input_b")))
	var ratio_percent := clampf(float(state.get(&"ratio_percent", 50.0)), 0.0, 100.0)
	var temperature_c := clampf(float(state.get(&"temperature_c", 90.0)), 0.0, 260.0)

	var base_result := _build_chem_bench_result()
	base_result[&"temperature"] = temperature_c
	base_result[&"ratio_percent"] = ratio_percent
	base_result[&"ratio_target_slot"] = ratio_target_slot

	if int(input_a.get(&"quantity", 0)) <= 0 or int(input_b.get(&"quantity", 0)) <= 0:
		base_result[&"preview_label"] = "Load two reactants"
		base_result[&"notes"] = "The bench needs two reactive materials before chemistry can begin."
		return base_result

	var input_a_id := StringName(input_a.get(&"item_id", &""))
	var input_b_id := StringName(input_b.get(&"item_id", &""))
	var family := _find_chem_bench_family(input_a_id, input_b_id)
	if family.is_empty():
		base_result[&"preview_label"] = "Unsupported pair"
		base_result[&"notes"] = "This pair does not map to a known chem-bench reaction family."
		return base_result

	var ratio_item_id := StringName(family.get(&"ratio_item_id", &""))
	var target_item_id := input_b_id if ratio_target_slot == &"input_b" else input_a_id
	var effective_b_ratio := ratio_percent if target_item_id == ratio_item_id else 100.0 - ratio_percent
	var catalyst_id := StringName(catalyst.get(&"item_id", &""))

	for outcome: Dictionary in family.get(&"outcomes", []):
		if not _outcome_matches(outcome, effective_b_ratio, temperature_c, catalyst_id):
			continue
		var result := _build_chem_bench_result()
		result[&"output_id"] = StringName(outcome.get(&"output_id", &""))
		result[&"output_qty"] = int(outcome.get(&"output_qty", 1))
		result[&"quality"] = float(outcome.get(&"quality", 0.0))
		result[&"tier"] = str(outcome.get(&"tier", "unknown"))
		result[&"notes"] = str(outcome.get(&"notes", ""))
		result[&"preview_label"] = str(outcome.get(&"preview_label", ""))
		result[&"requires_stabilization"] = bool(outcome.get(&"requires_stabilization", false))
		result[&"failure_reason"] = StringName(outcome.get(&"failure_reason", &""))
		result[&"temperature"] = temperature_c
		result[&"ratio_percent"] = ratio_percent
		result[&"ratio_target_slot"] = ratio_target_slot
		result[&"consumed_inputs"] = [
			{&"slot_id": &"input_a", &"quantity": 1},
			{&"slot_id": &"input_b", &"quantity": 1},
		]
		result[&"consumed_catalyst"] = int(outcome.get(&"consumed_catalyst", 0))
		result[&"consume_catalyst_on_success"] = bool(outcome.get(&"consume_catalyst_on_success", false))
		return result

	base_result[&"preview_label"] = "No reaction"
	base_result[&"notes"] = "The pair is valid, but the current ratio, temperature, and catalyst state fall outside any known reaction window."
	return base_result


func can_use_chem_bench_reactant(item_id: StringName) -> bool:
	_ensure_chem_bench_reactions_loaded()
	return _chem_bench_reactant_ids.has(item_id)


func get_carbon_percentage(element_ref) -> float:
	var element_data := _get_element_data(element_ref)
	if element_data.is_empty():
		return 0.0

	var properties: Dictionary = element_data.get(&"properties", {})
	return clampf(
		float(properties.get(&"carbon_percentage", properties.get(&"carbon_pct_when_burned", 0.0))),
		0.0,
		1.0
	)


func get_fuel_value(element_ref) -> float:
	var element_data := _get_element_data(element_ref)
	if element_data.is_empty():
		return 0.0

	var properties: Dictionary = element_data.get(&"properties", {})
	return maxf(float(properties.get(&"fuel_value", 0.0)), 0.0)


func _ensure_chem_bench_reactions_loaded() -> void:
	if not _chem_bench_reaction_families.is_empty():
		return
	_load_chem_bench_reactions()


func _load_chem_bench_reactions() -> void:
	_chem_bench_reaction_families.clear()
	_chem_bench_reactant_ids.clear()

	var file := FileAccess.open(CHEM_BENCH_REACTION_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Unable to open chem bench reaction data file: %s" % CHEM_BENCH_REACTION_DATA_PATH)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("Skipping invalid chem bench reaction data file: %s" % CHEM_BENCH_REACTION_DATA_PATH)
		return

	for raw_family in parsed:
		if not raw_family is Dictionary:
			continue
		var family := _normalize_chem_bench_family(raw_family)
		if family.is_empty():
			continue
		_chem_bench_reaction_families.append(family)
		for item_id: StringName in family.get(&"pair", []):
			if not _chem_bench_reactant_ids.has(item_id):
				_chem_bench_reactant_ids.append(item_id)


func _normalize_chem_bench_family(raw_family: Dictionary) -> Dictionary:
	var raw_pair: Variant = raw_family.get(&"pair", [])
	var raw_outcomes: Variant = raw_family.get(&"outcomes", [])
	if not raw_pair is Array or raw_pair.size() != 2 or not raw_outcomes is Array or raw_outcomes.is_empty():
		return {}

	var pair: Array[StringName] = []
	for item_id in raw_pair:
		pair.append(StringName(str(item_id)))
	pair.sort()
	var ratio_item_id := StringName(str(raw_pair[1]))

	var outcomes: Array[Dictionary] = []
	for raw_outcome in raw_outcomes:
		if not raw_outcome is Dictionary:
			continue
		outcomes.append({
			&"ratio_min": float(raw_outcome.get(&"ratio_min", 0.0)),
			&"ratio_max": float(raw_outcome.get(&"ratio_max", 100.0)),
			&"temp_min": float(raw_outcome.get(&"temp_min", 0.0)),
			&"temp_max": float(raw_outcome.get(&"temp_max", 9999.0)),
			&"catalyst": StringName(str(raw_outcome.get(&"catalyst", "any"))),
			&"output_id": StringName(str(raw_outcome.get(&"output_id", ""))),
			&"output_qty": int(raw_outcome.get(&"output_qty", 1)),
			&"quality": float(raw_outcome.get(&"quality", 0.0)),
			&"tier": str(raw_outcome.get(&"tier", "unknown")),
			&"notes": str(raw_outcome.get(&"notes", "")),
			&"preview_label": str(raw_outcome.get(&"preview_label", "")),
			&"requires_stabilization": bool(raw_outcome.get(&"requires_stabilization", false)),
			&"failure_reason": StringName(str(raw_outcome.get(&"failure_reason", ""))),
			&"consumed_catalyst": int(raw_outcome.get(&"consumed_catalyst", 0)),
			&"consume_catalyst_on_success": bool(raw_outcome.get(&"consume_catalyst_on_success", false)),
		})

	return {
		&"id": StringName(str(raw_family.get(&"id", ""))),
		&"pair": pair,
		&"ratio_item_id": ratio_item_id,
		&"outcomes": outcomes,
	}


func _find_chem_bench_family(input_a_id: StringName, input_b_id: StringName) -> Dictionary:
	var pair: Array[StringName] = [input_a_id, input_b_id]
	pair.sort()
	for family: Dictionary in _chem_bench_reaction_families:
		if family.get(&"pair", []) == pair:
			return family
	return {}


func _outcome_matches(outcome: Dictionary, effective_b_ratio: float, temperature_c: float, catalyst_id: StringName) -> bool:
	var catalyst_mode := StringName(outcome.get(&"catalyst", &"any"))
	if catalyst_mode == &"none":
		if not catalyst_id.is_empty():
			return false
	elif catalyst_mode != &"any" and catalyst_mode != catalyst_id:
		return false

	return (
		effective_b_ratio >= float(outcome.get(&"ratio_min", 0.0))
		and effective_b_ratio <= float(outcome.get(&"ratio_max", 100.0))
		and temperature_c >= float(outcome.get(&"temp_min", 0.0))
		and temperature_c <= float(outcome.get(&"temp_max", 9999.0))
	)


func _normalize_bench_slot_state(slot_state: Dictionary) -> Dictionary:
	return {
		&"item_id": StringName(slot_state.get(&"item_id", &"")),
		&"quantity": int(slot_state.get(&"quantity", 0)),
	}


func _build_chem_bench_result() -> Dictionary:
	return {
		&"output_id": &"",
		&"output_qty": 0,
		&"quality": 0.0,
		&"tier": "unknown",
		&"notes": "",
		&"preview_label": "",
		&"requires_stabilization": false,
		&"failure_reason": &"",
		&"ratio_target_slot": &"input_b",
		&"consumed_inputs": [],
		&"consumed_catalyst": 0,
		&"consume_catalyst_on_success": false,
	}


func _normalize_ratio_target_slot(slot_id: StringName) -> StringName:
	if slot_id == &"input_a":
		return &"input_a"
	return &"input_b"


func _get_element_data(element_ref) -> Dictionary:
	var normalized_ref := _normalize_element_ref(element_ref)
	if normalized_ref.is_empty():
		return {}

	var direct_lookup := ElementDatabase.get_element(StringName(normalized_ref.to_lower()))
	if not direct_lookup.is_empty():
		return direct_lookup

	for element_id: StringName in ElementDatabase.elements:
		var element_data: Dictionary = ElementDatabase.elements[element_id]
		var symbol := str(element_data.get(&"symbol", ""))
		if symbol.to_lower() == normalized_ref.to_lower():
			return element_data.duplicate(true)

	return {}


func _is_iron_source(element_ref: String, element_data: Dictionary) -> bool:
	if not element_data.is_empty():
		return StringName(element_data.get(&"id", &"")) == &"iron"

	var normalized_ref := element_ref.to_lower()
	return normalized_ref == "iron" or normalized_ref == "fe"


func _normalize_element_ref(element_ref) -> String:
	if element_ref == null:
		return ""
	return str(element_ref).strip_edges()


func _is_carbonisation_request(element_a: String, element_b: String) -> bool:
	if not element_b.is_empty():
		return false

	var normalized_a := element_a.to_lower()
	return normalized_a == "wood" or normalized_a == "c"


func _evaluate_carbonisation(temp: float) -> Dictionary:
	var result := {
		"output_id": null,
		"quality": 0.0,
		"tier": "unknown",
		"notes": ""
	}

	if temp < 400.0:
		result.notes = "Heat too low for carbonisation (400°C-700°C for charcoal)"
	elif temp < 700.0:
		result.output_id = "charcoal"
		result.quality = 1.0
		result.tier = "optimal"
		result.notes = "Carbonisation stable: wood chars into charcoal"
	else:
		result.output_id = "slag"
		result.quality = 0.0
		result.tier = "waste"
		result.notes = "Overburned: carbon collapses into slag"

	return result
