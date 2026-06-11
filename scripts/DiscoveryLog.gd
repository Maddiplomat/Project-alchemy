extends Node

## DiscoveryLog Autoload
## Records every unique smelting outcome, broadcasts it as a signal,
## and surfaces a timestamped history for the in-game journal.

signal discovery_made(entry: Dictionary)
signal entry_added(entry: Dictionary)

## Maximum number of entries kept in memory.
const MAX_LOG_SIZE := 500

## Outcome severity tiers — mirrors ChemistryEngine result tiers.
enum OutcomeTier {
	UNKNOWN,
	WASTE,       ## coke_slag, overburned slag
	LOW,         ## wrought_iron
	MEDIUM,      ## cast_iron
	OPTIMAL,     ## charcoal, steel
	DANGER,      ## explosion
}

## Full ordered log (newest last).
var log_entries: Array[Dictionary] = []

## Set of output_ids already logged — prevents duplicate "first discovery" pings.
var _seen_outputs: Dictionary[StringName, bool] = {}
var _seen_discoveries: Dictionary[StringName, bool] = {}
var _seen_environment_entries: Dictionary[StringName, bool] = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Record a smelting result.
## result  – the Dictionary returned by ChemistryEngine.evaluate_reaction()
## inputs  – Array of {item_id, quantity} describing what was consumed
## temp    – furnace temperature at time of smelt
func log_smelt(result: Dictionary, inputs: Array, temp: float) -> void:
	var output_id := StringName(str(result.get("output_id", "")))
	var tier_str := str(result.get("tier", "unknown"))
	var notes := str(result.get("notes", ""))
	var quality := float(result.get("quality", 0.0))

	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"output_id": output_id,
		"output_name": _pretty_name(output_id),
		"tier": tier_str,
		"tier_enum": _tier_from_string(tier_str),
		"quality": quality,
		"notes": notes,
		"temperature": temp,
		"inputs": inputs.duplicate(true),
		"is_first_discovery": false,
	}
	_append_entry(entry, true)


func log_chemistry(
	result: Dictionary,
	inputs: Array,
	conditions_summary: String,
	output_name_override: String = "",
	discover_output: bool = true
) -> void:
	var output_id := StringName(str(result.get("output_id", "")))
	var tier_str := str(result.get("tier", "unknown"))
	var notes := str(result.get("notes", ""))
	var output_name := output_name_override if not output_name_override.is_empty() else _pretty_name(output_id)
	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"output_id": output_id,
		"output_name": output_name,
		"tier": tier_str,
		"tier_enum": _tier_from_string(tier_str),
		"quality": float(result.get("quality", 0.0)),
		"notes": conditions_summary if not conditions_summary.is_empty() else notes,
		"temperature": float(result.get("temperature", 0.0)),
		"inputs": inputs.duplicate(true),
		"is_first_discovery": false,
		"entry_type": "chem_bench",
		"station": "chem_bench",
	}
	_append_entry(entry, discover_output)


## Return all entries in reverse-chronological order.
func get_recent(count: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, log_entries.size() - count)
	for i in range(log_entries.size() - 1, start - 1, -1):
		result.append(log_entries[i])
	return result


## Return the full journal in reverse-chronological order.
func get_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(log_entries.size() - 1, -1, -1):
		result.append(log_entries[index].duplicate(true))
	return result


## True if this output_id has been smelted at least once.
func has_seen(output_id: StringName) -> bool:
	return has_discovery(output_id)


func has_discovery(entry_id: StringName) -> bool:
	if entry_id.is_empty():
		return false
	return _seen_discoveries.get(entry_id, false)


func is_recipe_unlocked(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	var gate: Dictionary = recipe.get(&"discovery_gate", {})
	if gate.is_empty():
		return true
	var entry_id := StringName(gate.get(&"entry_id", &""))
	if entry_id.is_empty():
		return true
	return has_discovery(entry_id)


func get_recipe_gate_hint(recipe: Dictionary) -> String:
	var gate: Dictionary = recipe.get(&"discovery_gate", {})
	return str(gate.get(&"hint", ""))


func get_recipe_locked_name(recipe: Dictionary) -> String:
	var gate: Dictionary = recipe.get(&"discovery_gate", {})
	return str(gate.get(&"locked_name", "???"))


func log_progression_discovery(entry_id: StringName, title: String, notes: String) -> bool:
	if entry_id.is_empty():
		return false
	if has_discovery(entry_id):
		return false

	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"output_id": entry_id,
		"output_name": title if not title.is_empty() else _pretty_name(entry_id),
		"tier": "progression",
		"tier_enum": OutcomeTier.UNKNOWN,
		"quality": 1.0,
		"notes": notes,
		"temperature": 0.0,
		"inputs": [],
		"is_first_discovery": false,
		"entry_type": "progression",
	}
	_append_entry(entry, true)
	return true


func get_all_discoveries() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in _seen_discoveries.keys():
		result.append(entry_id)
	result.sort()
	return result


func restore_discoveries(discoveries: Array) -> void:
	_seen_outputs.clear()
	_seen_discoveries.clear()
	if ElementDatabase != null:
		ElementDatabase.discovered_elements.clear()
	for raw_entry_id in discoveries:
		var entry_id := StringName(str(raw_entry_id))
		if entry_id.is_empty():
			continue
		_record_discovery(entry_id)


## Clear all history (for new-game resets).
func clear() -> void:
	log_entries.clear()
	_seen_outputs.clear()
	_seen_discoveries.clear()
	_seen_environment_entries.clear()


func log_environment(entry_id: StringName, title: String, notes: String, one_time: bool = true) -> bool:
	if entry_id.is_empty():
		return false
	if one_time and _seen_environment_entries.get(entry_id, false):
		return false

	if one_time:
		_seen_environment_entries[entry_id] = true

	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"output_id": entry_id,
		"output_name": title,
		"tier": "environment",
		"tier_enum": OutcomeTier.UNKNOWN,
		"quality": 1.0,
		"notes": notes,
		"temperature": 0.0,
		"inputs": [],
		"is_first_discovery": false,
		"entry_type": "environment",
	}
	_append_entry(entry, false)
	return true


func seed_debug_entries(count: int, clear_existing: bool = true) -> void:
	if clear_existing:
		clear()

	var capped_count := maxi(count, 0)
	var sample_results := [
		{
			"output_id": "steel",
			"quality": 1.0,
			"tier": "optimal",
			"notes": "Optimal alloy in the steel window.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 1}],
			"temp": 1480.0,
		},
		{
			"output_id": "wrought_iron",
			"quality": 0.6,
			"tier": "low",
			"notes": "Soft, bends under stress.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 1}],
			"temp": 1280.0,
		},
		{
			"output_id": "cast_iron",
			"quality": 0.4,
			"tier": "medium",
			"notes": "High carbon, brittle output.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 1}],
			"temp": 1390.0,
		},
		{
			"output_id": "coke_slag",
			"quality": 0.0,
			"tier": "waste",
			"notes": "Carbon overwhelmed the iron.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 2}],
			"temp": 1505.0,
		},
		{
			"output_id": "",
			"quality": 0.0,
			"tier": "unknown",
			"notes": "Heat too low for reaction.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 1}],
			"temp": 980.0,
		},
		{
			"output_id": "charcoal",
			"quality": 1.0,
			"tier": "optimal",
			"notes": "Carbonisation stable: wood chars into charcoal.",
			"inputs": [{"item_id": &"wood", "quantity": 1}],
			"temp": 620.0,
		},
		{
			"output_id": "slag",
			"quality": 0.0,
			"tier": "waste",
			"notes": "Overburned: carbon collapses into slag.",
			"inputs": [{"item_id": &"wood", "quantity": 1}],
			"temp": 700.0,
		},
		{
			"output_id": "explosion",
			"quality": 0.0,
			"tier": "danger",
			"notes": "Temperature exceeded 1600°C during smelting. Furnace overheated.",
			"inputs": [{"item_id": &"iron", "quantity": 1}, {"item_id": &"charcoal", "quantity": 1}],
			"temp": 1600.0,
		},
	]

	var base_timestamp := Time.get_ticks_msec() - (capped_count * 1000)
	for index in range(capped_count):
		var sample: Dictionary = sample_results[index % sample_results.size()]
		var entry := {
			"timestamp": base_timestamp + (index * 1000),
			"output_id": StringName(str(sample.get("output_id", ""))),
			"output_name": _pretty_name(StringName(str(sample.get("output_id", "")))),
			"tier": str(sample.get("tier", "unknown")),
			"tier_enum": _tier_from_string(str(sample.get("tier", "unknown"))),
			"quality": float(sample.get("quality", 0.0)),
			"notes": str(sample.get("notes", "")),
			"temperature": float(sample.get("temp", 0.0)),
			"inputs": (sample.get("inputs", []) as Array).duplicate(true),
			"is_first_discovery": false,
		}
		log_entries.append(entry)

	if log_entries.size() > MAX_LOG_SIZE:
		log_entries = log_entries.slice(log_entries.size() - MAX_LOG_SIZE, log_entries.size())


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _pretty_name(output_id: StringName) -> String:
	if output_id.is_empty():
		return "Nothing"
	var element_data := ElementDatabase.get_element(output_id)
	if not element_data.is_empty():
		return str(element_data.get("display_name", String(output_id).capitalize()))
	return String(output_id).replace("_", " ").capitalize()


func _append_entry(entry: Dictionary, discover_output: bool) -> void:
	var output_id := StringName(str(entry.get("output_id", "")))
	if discover_output and not output_id.is_empty() and not has_discovery(output_id):
		entry["is_first_discovery"] = true
		_record_discovery(output_id)

	log_entries.append(entry)
	if log_entries.size() > MAX_LOG_SIZE:
		log_entries.pop_front()

	discovery_made.emit(entry)
	entry_added.emit(entry)
	_print_entry(entry)


func _tier_from_string(tier: String) -> int:
	match tier.to_lower():
		"waste":
			return OutcomeTier.WASTE
		"low":
			return OutcomeTier.LOW
		"medium":
			return OutcomeTier.MEDIUM
		"optimal":
			return OutcomeTier.OPTIMAL
		"danger":
			return OutcomeTier.DANGER
		_:
			return OutcomeTier.UNKNOWN


func _print_entry(entry: Dictionary) -> void:
	var flag := "[NEW!] " if entry.get("is_first_discovery", false) else ""
	var name_str := str(entry.get("output_name", "?"))
	var tier_str := str(entry.get("tier", "?"))
	var temp_str := "%d°C" % int(entry.get("temperature", 0.0))
	var notes_str := str(entry.get("notes", ""))
	print(
		"[DiscoveryLog] %s%s (%s) @ %s — %s"
		% [flag, name_str, tier_str, temp_str, notes_str]
	)


func _record_discovery(entry_id: StringName) -> void:
	if entry_id.is_empty() or _seen_discoveries.get(entry_id, false):
		return
	_seen_discoveries[entry_id] = true
	_seen_outputs[entry_id] = true
	if ElementDatabase.has_element(entry_id):
		ElementDatabase.discover_element(entry_id)
