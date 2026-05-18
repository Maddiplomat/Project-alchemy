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

	# Flag first-ever occurrence of this output.
	if not output_id.is_empty() and not _seen_outputs.get(output_id, false):
		entry["is_first_discovery"] = true
		_seen_outputs[output_id] = true
		# Notify ElementDatabase so it marks the element discovered.
		if ElementDatabase.has_element(output_id):
			ElementDatabase.discover_element(output_id)

	log_entries.append(entry)
	if log_entries.size() > MAX_LOG_SIZE:
		log_entries.pop_front()

	discovery_made.emit(entry)
	entry_added.emit(entry)

	_print_entry(entry)


## Return all entries in reverse-chronological order.
func get_recent(count: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, log_entries.size() - count)
	for i in range(log_entries.size() - 1, start - 1, -1):
		result.append(log_entries[i])
	return result


## True if this output_id has been smelted at least once.
func has_seen(output_id: StringName) -> bool:
	return _seen_outputs.get(output_id, false)


## Clear all history (for new-game resets).
func clear() -> void:
	log_entries.clear()
	_seen_outputs.clear()


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
