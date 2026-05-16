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

	# Use ElementDatabase to resolve IDs and properties
	var data_a := ElementDatabase.get_element(element_a)
	var data_b := ElementDatabase.get_element(element_b)
	
	if data_a.is_empty():
		return result

	var symbol_a: String = data_a.get("symbol", "")
	var symbol_b: String = data_b.get("symbol", "") if not data_b.is_empty() else ""

	# --- SINGLE ELEMENT REACTIONS (Carbonization, etc.) ---
	if data_b.is_empty() or element_a == element_b:
		# Wood carbonization: 400°C - 600°C
		if symbol_a == "C" and data_a.get("id") == "wood":
			if temp >= 400.0 and temp <= 700.0:
				result.output_id = "charcoal"
				result.quality = 1.0
				result.tier = "intermediate"
				result.notes = "Wood carbonized into high-purity Charcoal."
			elif temp > 700.0:
				result.output_id = "coke_slag"
				result.notes = "Wood burnt too fast, leaving only useless ash/slag."
			
			if result.output_id != null:
				reaction_evaluated.emit(result)
				return result

	# --- TWO ELEMENT REACTIONS (Steel, etc.) ---
	if data_b.is_empty():
		return result

	# Resolve actual carbon ratio based on element properties
	var is_valid_pair := false
	var ratio := 0.0

	# Helper to get carbon contribution
	var get_carbon_contribution = func(data: Dictionary, mass_pct: float) -> float:
		var symbol = data.get("symbol", "")
		var props = data.get("properties", {})
		if symbol == "C" or symbol == "C+":
			return mass_pct * props.get("carbon_pct_when_burned", 1.0)
		return 0.0

	# Case 1: A is Iron, B is Carbon source
	if symbol_a == "Fe":
		var carbon_contrib = get_carbon_contribution.call(data_b, ratio_b_pct)
		if carbon_contrib > 0 or symbol_b in ["C", "C+"]:
			is_valid_pair = true
			ratio = carbon_contrib
	# Case 2: B is Iron, A is Carbon source
	elif symbol_b == "Fe":
		var carbon_contrib = get_carbon_contribution.call(data_a, 100.0 - ratio_b_pct)
		if carbon_contrib > 0 or symbol_a in ["C", "C+"]:
			is_valid_pair = true
			ratio = carbon_contrib

	if is_valid_pair:
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
