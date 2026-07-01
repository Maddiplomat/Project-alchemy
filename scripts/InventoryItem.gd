class_name InventoryItem
extends RefCounted

var id: StringName = &""
var item_id: StringName = &""
var display_name: String = ""
var category: int = 0
var risk_level: int = 0
var quantity: int = 0
var purity: float = 1.0
var unit_weight: float = 1.0
var weight: float = 1.0
var has_durability: bool = false
var durability: float = 1.0
var max_durability: float = 1.0
var charge: float = 1.0
var max_charge: float = 1.0
var extra_data: Dictionary = {}


static func from_variant(data, defaults: Dictionary = {}):
	var item = preload("res://scripts/InventoryItem.gd").new()
	if data != null and data.has_method("duplicate_item"):
		return data.duplicate_item()

	var source: Dictionary = {}
	if data is Dictionary:
		source = data
	item.id = StringName(_read_value(source, "id", _read_value(source, "item_id", defaults.get(&"id", &""))))
	item.item_id = item.id
	item.display_name = str(_read_value(source, "display_name", defaults.get(&"display_name", "")))
	item.category = int(_read_value(source, "category", defaults.get(&"category", 0)))
	item.risk_level = int(_read_value(source, "risk_level", defaults.get(&"risk_level", 0)))
	item.quantity = int(_read_value(source, "quantity", defaults.get(&"quantity", 0)))
	item.purity = float(_read_value(source, "purity", defaults.get(&"purity", 1.0)))
	item.unit_weight = float(_read_value(source, "unit_weight", _read_value(source, "weight", defaults.get(&"unit_weight", 1.0))))
	item.weight = float(_read_value(source, "weight", item.unit_weight))
	item.charge = float(_read_value(source, "charge", defaults.get(&"charge", 1.0)))
	item.max_charge = float(_read_value(source, "max_charge", defaults.get(&"max_charge", 1.0)))

	var durability_value = _read_value(source, "durability", null)
	var max_durability_value = _read_value(source, "max_durability", null)
	item.has_durability = durability_value != null or max_durability_value != null or bool(defaults.get(&"has_durability", false))
	item.max_durability = float(max_durability_value if max_durability_value != null else defaults.get(&"max_durability", 1.0))
	item.durability = float(durability_value if durability_value != null else defaults.get(&"durability", item.max_durability))

	item.extra_data = {}
	for raw_key in source.keys():
		var normalized_key := str(raw_key)
		if normalized_key in [
			"id",
			"item_id",
			"display_name",
			"category",
			"risk_level",
			"quantity",
			"purity",
			"unit_weight",
			"weight",
			"durability",
			"max_durability",
			"charge",
			"max_charge",
		]:
			continue
		item.extra_data[normalized_key] = source[raw_key]

	return item


func duplicate_item():
	var duplicated = preload("res://scripts/InventoryItem.gd").new()
	duplicated.id = id
	duplicated.item_id = item_id
	duplicated.display_name = display_name
	duplicated.category = category
	duplicated.risk_level = risk_level
	duplicated.quantity = quantity
	duplicated.purity = purity
	duplicated.unit_weight = unit_weight
	duplicated.weight = weight
	duplicated.has_durability = has_durability
	duplicated.durability = durability
	duplicated.max_durability = max_durability
	duplicated.charge = charge
	duplicated.max_charge = max_charge
	duplicated.extra_data = extra_data.duplicate(true)
	return duplicated


func merge_metadata_from(other) -> void:
	if other == null:
		return
	id = other.id
	item_id = other.item_id
	display_name = other.display_name
	category = other.category
	risk_level = other.risk_level
	unit_weight = other.unit_weight
	weight = other.weight
	has_durability = other.has_durability
	durability = other.durability
	max_durability = other.max_durability
	charge = other.charge
	max_charge = other.max_charge
	extra_data = other.extra_data.duplicate(true)


func to_dict() -> Dictionary:
	var data := extra_data.duplicate(true)
	data["id"] = id
	data["item_id"] = item_id
	data["display_name"] = display_name
	data["category"] = category
	data["risk_level"] = risk_level
	data["quantity"] = quantity
	data["purity"] = purity
	data["unit_weight"] = unit_weight
	data["weight"] = weight
	data["charge"] = charge
	data["max_charge"] = max_charge
	if has_durability:
		data["durability"] = durability
		data["max_durability"] = max_durability
	else:
		data["durability"] = null
		data["max_durability"] = null
	return data


static func _read_value(data: Dictionary, key: String, default_value = null):
	if data.has(key):
		return data[key]
	var key_name := StringName(key)
	if data.has(key_name):
		return data[key_name]
	return default_value
