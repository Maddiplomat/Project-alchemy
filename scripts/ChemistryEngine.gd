extends Node

## ChemistryEngine Autoload
## Handles element reactions based on temperature and ratios.

signal reaction_evaluated(result: Dictionary)

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
		# Use carbon_ratio for the rest of the logic
		var ratio := carbon_ratio
		# TEMPERATURE OVERRIDE: Explosion
		if temp >= 1600.0:
			result.output_id = "explosion"
			result.quality = 0.0
			result.tier = "danger"
			result.notes = "If heat > 1600°C — radius 2 tiles"
		
		# MINIMUM TEMPERATURE CHECK
		elif temp < 1200.0:
			result.notes = "Heat too low for reaction (1200°C-1600°C required)"
		
		# REACTION LOGIC (1200°C - 1600°C)
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
