extends Node

## ChemistryEngine Autoload
## Handles element reactions based on temperature and ratios.

signal reaction_evaluated(result: Dictionary)

func evaluate_reaction(element_a: String, element_b: String, ratio_b_pct: float, temp: float) -> Dictionary:
	var result = {
		"output_id": null,
		"quality": 0.0,
		"tier": "unknown",
		"notes": ""
	}

	# Identify if this is the Fe + C (Iron + Carbon) reaction
	# Use ElementDatabase to resolve IDs and properties
	var data_a := ElementDatabase.get_element(element_a)
	var data_b := ElementDatabase.get_element(element_b)
	
	if data_a.is_empty() or data_b.is_empty():
		return result

	var symbol_a: String = data_a.get("symbol", "")
	var symbol_b: String = data_b.get("symbol", "")

	var carbon_ratio := 0.0
	var is_valid_pair := false

	# Case 1: A is Iron, B is Carbon
	if symbol_a == "Fe" and (symbol_b == "C" or symbol_b == "C+"):
		is_valid_pair = true
		carbon_ratio = ratio_b_pct
	# Case 2: A is Carbon, B is Iron
	elif symbol_b == "Fe" and (symbol_a == "C" or symbol_a == "C+"):
		is_valid_pair = true
		carbon_ratio = 100.0 - ratio_b_pct

	if is_valid_pair:
		# For Prototype 3, the thresholds are still specific to the Fe+C reaction tier table.
		# However, we now identify the reaction by chemical symbols from the Database.
		var ratio := carbon_ratio
		
		# TEMPERATURE OVERRIDE: Explosion
		if temp > 1600.0:
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
