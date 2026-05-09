extends Panel

@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel

func update_slot(item_id: String, quantity: int, purity: float):
	if quantity > 0:
		item_icon.visible = true
		quantity_label.text = str(quantity)
		tooltip_text = "%s (Purity: %.2f)" % [item_id, purity]
		
		# Placeholder color mapping
		match item_id:
			"wood": item_icon.modulate = Color.BURLYWOOD
			"stone": item_icon.modulate = Color.GRAY
			"iron": item_icon.modulate = Color.SILVER
			_: item_icon.modulate = Color.WHITE
	else:
		item_icon.visible = false
		quantity_label.text = ""
		tooltip_text = ""

func clear():
	item_icon.visible = false
	quantity_label.text = ""
	tooltip_text = ""
