extends CanvasLayer

const GameplayData = preload("res://scripts/GameplayData.gd")
const WeatherSystem = preload("res://scripts/WeatherSystem.gd")

const WORLD_SCENE_PATH := "res://scenes/World.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const DEATH_OVERLAY_FADE_SECONDS := 1.0
const DISCOVERY_JOURNAL_SCENE := preload("res://scenes/UI/Journal.tscn")
const CARRIER_WARNING_SFX_DURATION := 0.11
const SCANNER_TOAST_SECONDS := 1.6
const NIGHT_DEFENSE_TOAST_SECONDS := 2.2
const HealthDisplayScript = preload("res://scripts/HealthDisplay.gd")
const CarrierRiskDisplayScript = preload("res://scripts/CarrierRiskDisplay.gd")
const WeatherDisplayScript = preload("res://scripts/WeatherDisplay.gd")
const ObjectivesDisplayScript = preload("res://scripts/ObjectivesDisplay.gd")

@onready var carrier_risk_strip: Panel = $CarrierRiskStrip
@onready var carrier_risk_warning_label: Label = $CarrierRiskStrip/VBoxContainer/WarningLabel
@onready var carrier_risk_hint_label: Label = $CarrierRiskStrip/VBoxContainer/HintLabel
@onready var minimap_placeholder: Control = $MinimapPlaceholder
@onready var minimap_toggle_button: Button = $MinimapToggleButton
@onready var scanner_upgrade_label: Label = $ScannerUpgradeLabel
@onready var context_interact_button: Button = $ContextInteractButton
@onready var context_interact_label: Label = $ContextInteractLabel
@onready var objectives_panel: Panel = $ObjectivesPanel
@onready var objectives_collapse_button: Button = $ObjectivesPanel/MarginContainer/VBoxContainer/HeaderRow/CollapseButton
@onready var objective_title_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var objective_1_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective1Label
@onready var objective_2_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective2Label
@onready var objective_3_label: Label = $ObjectivesPanel/MarginContainer/VBoxContainer/Objective3Label
@onready var day_time_label: Label = $DayTimeLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var weight_label: Label = $WeightLabel
@onready var held_item_container: Panel = $HeldItemContainer
@onready var held_item_icon: TextureRect = $HeldItemContainer/HBoxContainer/ActiveItemIcon
@onready var held_item_label: Label = $HeldItemContainer/HBoxContainer/ActiveItemLabel
@onready var mobile_controls: Control = $MobileControls
@onready var mobile_tutorial_overlay: Control = $MobileTutorialOverlay
@onready var mobile_tutorial_tint: ColorRect = $MobileTutorialOverlay/Tint
@onready var mobile_tutorial_dismiss_button: Button = $MobileTutorialOverlay/CenterContainer/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/DismissButton
@onready var mobile_tutorial_skip_button: Button = $MobileTutorialOverlay/SkipTutorialButton
@onready var carry_vignette: ColorRect = $CarryVignette
@onready var death_overlay: Panel = $DeathOverlay
@onready var death_cause_label: Label = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/CauseLabel
@onready var death_last_hits_label: Label = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/LastHitsLabel
@onready var retry_button: Button = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/RetryButton
@onready var quit_button: Button = $DeathOverlay/CenterContainer/DialogPanel/VBoxContainer/QuitButton

const CARRY_VIGNETTE_MAX_ALPHA := 0.35
const CARRY_VIGNETTE_START_RATIO := 0.9
const CARRY_VIGNETTE_END_RATIO := 1.0
const CARRIER_VIGNETTE_PULSE_SPEED := 5.5
const CARRIER_VIGNETTE_URGENT_SPEED := 9.0
const OBJECTIVES_PANEL_DEFAULT_TOP := 44.0
const OBJECTIVES_PANEL_DEFAULT_BOTTOM := 166.0
const TOUCH_HUD_MARGIN := 14.0
const TOUCH_MINIMAP_COLLAPSED_SIZE := 64.0
const TOUCH_MINIMAP_EXPANDED_SIZE := 108.0
const TOUCH_BOTTOM_CONTROL_CLEARANCE := 236.0
const TOUCH_SIDE_CARD_WIDTH := 168.0
const MOBILE_TUTORIAL_AUTO_DISMISS_SECONDS := 4.0
const MOBILE_HINT_FIRST_RUN := &"mobile_first_run_overlay"
const MOBILE_HINT_MOVEMENT := &"mobile_movement"
const MOBILE_HINT_ATTACK := &"mobile_attack"
const MOBILE_HINT_INVENTORY := &"mobile_inventory"
const MOBILE_HINT_CRAFTING := &"mobile_crafting"
const MOBILE_HINT_BUILDING := &"mobile_building"

@export var debug_seed_journal_entries := 0
@export var debug_open_journal_on_ready := false
@export var debug_report_journal_layout := false

var _placeholder_textures := {}
var _death_overlay_tween: Tween = null
var _journal_panel: Panel = null
var _journal_open := false
var _paused_player: Node = null
var _carrier_warning_audio_player: AudioStreamPlayer = null
var _active_carrier_risk_element: StringName = &""
var _active_carrier_risk_seconds := -1
var _weight_vignette_alpha := 0.0
var _carrier_vignette_phase := 0.0
var _scanner_upgrade_tween: Tween = null
var _night_defense_strip: Panel = null
var _night_defense_label: Label = null
var _night_defense_tween: Tween = null
var _objectives_panel_visible := true
var _toast_queue: Array[String] = []
var _is_toast_playing := false
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _weather_strip: Panel = null
var _weather_strip_style: StyleBoxFlat = null
var _weather_status_label: Label = null
var _weather_detail_label: Label = null
var _weather_warning_label: Label = null
var _weather_day_label: Label = null
var _weather_player: Node2D = null
var _journal_update_indicator: Label = null
var _journal_has_unread_entries := false
var _current_touch_interactable: Node2D = null
var _objectives_collapsed := false
var _minimap_collapsed := false
var _player_combat_source: Node = null
var _touch_interaction_candidates: Dictionary[int, Node2D] = {}
var _bound_touch_areas: Dictionary[int, bool] = {}
var health_display: Node
var carrier_risk_display: Node
var weather_display: Node
var objectives_display: Node

func _ready() -> void:
	_setup_display_components()
	GameManager.player_health_changed.connect(_update_health)
	GameManager.player_died.connect(_show_death_overlay)
	GameManager.scanner_tier_changed.connect(_on_scanner_tier_changed)
	GameManager.day_changed.connect(_on_day_changed)
	GameManager.time_of_day_changed.connect(_on_time_of_day_changed)
	InventoryManager.inventory_changed.connect(_refresh_held_item.unbind(1))
	InventoryManager.active_slot_changed.connect(_on_held_item_changed.unbind(1))
	InventoryManager.weight_changed.connect(_on_weight_changed)
	if EventBus.get_research_objectives() != null:
		EventBus.get_research_objectives().objective_completed.connect(_on_objectives_changed)
		EventBus.get_research_objectives().objective_activated.connect(_on_objectives_changed)
		EventBus.get_research_objectives().objective_progressed.connect(_on_objectives_progressed)
		if EventBus.get_research_objectives().has_signal("objectives_restored"):
			EventBus.get_research_objectives().objectives_restored.connect(_on_objectives_state_restored)
	context_interact_button.pressed.connect(_on_context_interact_button_pressed)
	objectives_collapse_button.pressed.connect(_toggle_objectives_collapsed)
	minimap_toggle_button.pressed.connect(_toggle_minimap_collapsed)
	if mobile_tutorial_dismiss_button != null:
		mobile_tutorial_dismiss_button.pressed.connect(_dismiss_mobile_tutorial_overlay)
	if mobile_tutorial_skip_button != null:
		mobile_tutorial_skip_button.pressed.connect(_dismiss_mobile_tutorial_overlay)
	if mobile_tutorial_tint != null:
		mobile_tutorial_tint.gui_input.connect(_on_mobile_tutorial_tint_gui_input)
	get_viewport().size_changed.connect(_apply_hud_layout)
	GameManager.player_registered.connect(_on_player_registered)
	GameManager.player_unregistered.connect(_on_player_unregistered)
	if MobileInputRouter != null and MobileInputRouter.has_signal("input_mode_changed"):
		MobileInputRouter.input_mode_changed.connect(_on_input_mode_changed)
	if EventBus.get_build_system() != null and EventBus.get_build_system().has_signal("build_mode_changed"):
		EventBus.get_build_system().build_mode_changed.connect(_on_build_mode_changed)
	if EventBus.get_carrier_risk_system() != null:
		EventBus.get_carrier_risk_system().carrier_risk_warning.connect(_on_carrier_risk_warning)
		EventBus.get_carrier_risk_system().carrier_risk_cleared.connect(_on_carrier_risk_cleared)
		EventBus.get_carrier_risk_system().carrier_risk_ignition.connect(_on_carrier_risk_ignition)

	_update_health(GameManager.player_health, GameManager.max_player_health)
	_refresh_held_item()
	_on_weight_changed(InventoryManager.total_weight, InventoryManager.carry_capacity)
	_refresh_day_time()
	_refresh_objectives()
	_hide_death_overlay()
	_hide_carrier_risk_warning()
	_hide_scanner_upgrade_toast()
	_setup_discovery_journal()
	_setup_journal_update_indicator()
	_setup_night_defense_warning()
	if EventBus != null and EventBus.has_signal("night_threat_detected"):
		EventBus.night_threat_detected.connect(_on_night_threat_detected)
	if EventBus != null and EventBus.has_signal("loop_milestone_reached"):
		EventBus.loop_milestone_reached.connect(_on_loop_milestone_reached)
	if EventBus != null and EventBus.has_signal("discovery_entry_added"):
		EventBus.discovery_entry_added.connect(_on_discovery_entry_added)
	if EventBus.get_base_threat_director() != null and EventBus.get_base_threat_director().has_signal("threat_lesson_triggered"):
		EventBus.get_base_threat_director().threat_lesson_triggered.connect(_on_base_threat_lesson_triggered)
	if EventBus.get_weather_system() != null:
		if EventBus.get_weather_system().has_signal("weather_changed"):
			EventBus.get_weather_system().weather_changed.connect(_on_weather_changed)
		if EventBus.get_weather_system().has_signal("weather_forecast_changed"):
			EventBus.get_weather_system().weather_forecast_changed.connect(_on_weather_forecast_changed)
		if EventBus.get_weather_system().has_signal("weather_warning_started"):
			EventBus.get_weather_system().weather_warning_started.connect(_on_weather_warning_started)
		if EventBus.get_weather_system().has_signal("weather_warning_ended"):
			EventBus.get_weather_system().weather_warning_ended.connect(_on_weather_warning_ended)
	if not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)
	call_deferred("_bind_existing_touch_interactables")

	if debug_seed_journal_entries > 0:
		EventBus.get_discovery_log().seed_debug_entries(debug_seed_journal_entries, true)

	if debug_open_journal_on_ready:
		call_deferred("_open_debug_journal")

	_setup_toast_notification()
	GameManager.environmental_warning_changed.connect(_on_environmental_warning_changed)
	GameManager.save_completed.connect(_on_save_completed)
	_objectives_collapsed = MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	_minimap_collapsed = MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	_bind_player_combat_source(GameManager.get_player())
	if mobile_tutorial_overlay != null:
		mobile_tutorial_overlay.visible = false
	set_process(false)
	_apply_hud_layout()
	call_deferred("_show_first_run_mobile_overlay_if_needed")


func _setup_display_components() -> void:
	health_display = _ensure_display_component("HealthDisplay", HealthDisplayScript)
	carrier_risk_display = _ensure_display_component("CarrierRiskDisplay", CarrierRiskDisplayScript)
	weather_display = _ensure_display_component("WeatherDisplay", WeatherDisplayScript)
	objectives_display = _ensure_display_component("ObjectivesDisplay", ObjectivesDisplayScript)
	health_display.configure(health_bar, health_label, death_overlay, death_cause_label, death_last_hits_label, retry_button, quit_button)
	carrier_risk_display.configure(carrier_risk_strip, carrier_risk_warning_label, carrier_risk_hint_label, carry_vignette)
	weather_display.configure(self)
	_weather_strip = weather_display.weather_strip
	_weather_day_label = weather_display.day_label
	if day_time_label != null:
		day_time_label.visible = false
	var objective_labels: Array[Label] = [objective_1_label, objective_2_label, objective_3_label]
	objectives_display.configure(objectives_panel, objectives_collapse_button, objective_title_label, objective_labels)


func _ensure_display_component(node_name: String, component_script: Script) -> Node:
	var component := get_node_or_null(node_name)
	if component != null:
		return component
	component = Node.new()
	component.name = node_name
	component.set_script(component_script)
	add_child(component)
	return component


func _unhandled_input(event: InputEvent) -> void:
	if death_overlay.visible:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _journal_open:
		_close_journal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_journal"):
		if _journal_open:
			_close_journal()
		else:
			_open_journal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_inventory"):
		_maybe_show_inventory_tutorial()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"toggle_objectives_panel") or (
		event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O
	):
		_toggle_objectives_panel()
		get_viewport().set_input_as_handled()


func _toggle_objectives_panel() -> void:
	_objectives_panel_visible = not _objectives_panel_visible
	if objectives_panel != null:
		objectives_panel.visible = _objectives_panel_visible
	_apply_hud_layout()


func _toggle_objectives_collapsed() -> void:
	_objectives_collapsed = not _objectives_collapsed
	_refresh_objectives()
	_apply_hud_layout()


func _toggle_minimap_collapsed() -> void:
	_minimap_collapsed = not _minimap_collapsed
	_apply_hud_layout()


func _update_touch_interaction_prompt() -> void:
	if context_interact_button == null or context_interact_label == null:
		return
	if not _should_show_touch_interaction_prompt():
		_hide_touch_interaction_prompt()
		return

	var player := GameManager.get_player() as Node2D
	if player == null:
		_hide_touch_interaction_prompt()
		return

	var interactable := _find_touch_interactable(player)
	if interactable == null:
		_hide_touch_interaction_prompt()
		return

	var previous_interactable := _current_touch_interactable
	_current_touch_interactable = interactable
	var prompt_text := "Interact"
	if interactable.has_method("get_touch_interaction_prompt"):
		prompt_text = str(interactable.call("get_touch_interaction_prompt"))
	if prompt_text.is_empty():
		prompt_text = "Interact"

	var world_position := interactable.global_position
	if interactable.has_method("get_touch_interaction_world_position"):
		world_position = interactable.call("get_touch_interaction_world_position")
	var screen_position := _world_to_screen(world_position)
	var viewport_rect := get_viewport().get_visible_rect()
	var safe_insets := _get_safe_insets(viewport_rect.size)
	var inset_left := float(safe_insets.get(&"left", 0.0))
	var inset_top := float(safe_insets.get(&"top", 0.0))
	var inset_right := float(safe_insets.get(&"right", 0.0))
	var inset_bottom := float(safe_insets.get(&"bottom", 0.0))
	screen_position.x = clampf(
		screen_position.x,
		88.0 + inset_left,
		viewport_rect.size.x - 88.0 - inset_right
	)
	screen_position.y = clampf(
		screen_position.y - 54.0,
		72.0 + inset_top,
		viewport_rect.size.y - 164.0 - inset_bottom
	)

	context_interact_button.visible = true
	context_interact_label.visible = true
	context_interact_button.text = "Interact"
	context_interact_button.global_position = screen_position - Vector2(context_interact_button.size.x * 0.5, 0.0)
	context_interact_label.text = prompt_text
	context_interact_label.global_position = screen_position - Vector2(context_interact_label.size.x * 0.5, 26.0)
	if interactable != previous_interactable:
		_maybe_show_station_tutorial()


func _hide_touch_interaction_prompt() -> void:
	_current_touch_interactable = null
	if context_interact_button != null:
		context_interact_button.visible = false
	if context_interact_label != null:
		context_interact_label.visible = false


func _should_show_touch_interaction_prompt() -> bool:
	if not MobileInputRouter.prefers_touch_controls():
		return false
	if _journal_open or death_overlay.visible:
		return false
	return true


func _find_touch_interactable(player: Node2D) -> Node2D:
	var best_node: Node2D = null
	var best_distance := INF
	var stale_ids: Array[int] = []
	for instance_id: int in _touch_interaction_candidates.keys():
		var interactable := _touch_interaction_candidates[instance_id] as Node2D
		if interactable == null or not is_instance_valid(interactable):
			stale_ids.append(instance_id)
			continue
		if not interactable.has_method("can_touch_interact"):
			continue
		if not bool(interactable.call("can_touch_interact", player)):
			continue
		var distance := player.global_position.distance_to(interactable.global_position)
		if distance < best_distance:
			best_distance = distance
			best_node = interactable
	for instance_id in stale_ids:
		_touch_interaction_candidates.erase(instance_id)
	return best_node


func _bind_existing_touch_interactables() -> void:
	for interactable in get_tree().get_nodes_in_group(&"touch_interactable"):
		_bind_touch_interactable(interactable)


func _on_scene_node_added(node: Node) -> void:
	if node == null:
		return
	call_deferred("_bind_touch_interactable", node)


func _bind_touch_interactable(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node is Node:
		return
	var candidate := node as Node
	if not candidate.is_in_group(&"touch_interactable"):
		return
	var interactable := candidate as Node2D
	if interactable == null:
		return
	var interaction_area := interactable as Area2D
	if interaction_area == null:
		interaction_area = interactable.get_node_or_null("InteractionArea") as Area2D
	if interaction_area == null:
		return
	var area_id := interaction_area.get_instance_id()
	if _bound_touch_areas.has(area_id):
		return
	_bound_touch_areas[area_id] = true
	interaction_area.body_entered.connect(_on_touch_interaction_body_entered.bind(interactable))
	interaction_area.body_exited.connect(_on_touch_interaction_body_exited.bind(interactable))
	interaction_area.tree_exited.connect(_on_touch_interaction_area_exited.bind(area_id, interactable.get_instance_id()))
	var prompt_label := interactable.get_node_or_null("PromptLabel") as CanvasItem
	if prompt_label != null:
		prompt_label.visibility_changed.connect(_on_touch_interactable_state_changed)
	for body in interaction_area.get_overlapping_bodies():
		_on_touch_interaction_body_entered(body, interactable)


func _on_touch_interaction_body_entered(body: Node, interactable: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	_touch_interaction_candidates[interactable.get_instance_id()] = interactable
	_update_touch_interaction_prompt()


func _on_touch_interaction_body_exited(body: Node, interactable: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	_touch_interaction_candidates.erase(interactable.get_instance_id())
	_update_touch_interaction_prompt()


func _on_touch_interaction_area_exited(area_id: int, interactable_id: int) -> void:
	_bound_touch_areas.erase(area_id)
	_touch_interaction_candidates.erase(interactable_id)
	_update_touch_interaction_prompt()


func _on_touch_interactable_state_changed() -> void:
	_update_touch_interaction_prompt()


func _world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position


func _on_context_interact_button_pressed() -> void:
	if _current_touch_interactable == null or not is_instance_valid(_current_touch_interactable):
		return
	if _current_touch_interactable.has_method("perform_touch_interaction"):
		_current_touch_interactable.call("perform_touch_interaction")
		return
	MobileInputRouter.tap_action(&"interact")


func _on_input_mode_changed(_mode: StringName) -> void:
	_apply_hud_layout()
	_refresh_journal_indicator_copy()
	_show_first_run_mobile_overlay_if_needed()
	_update_touch_interaction_prompt()


func _on_player_registered(player_node: Node2D) -> void:
	_bind_player_combat_source(player_node)
	call_deferred("_bind_existing_touch_interactables")


func _on_player_unregistered(player_node: Node2D) -> void:
	if _player_combat_source == player_node:
		_bind_player_combat_source(null)
	_touch_interaction_candidates.clear()
	_hide_touch_interaction_prompt()


func _bind_player_combat_source(player_node: Node) -> void:
	if _player_combat_source != null and is_instance_valid(_player_combat_source):
		var previous_callback := Callable(self, "_on_player_combat_state_changed")
		if _player_combat_source.has_signal("combat_state_changed") and _player_combat_source.combat_state_changed.is_connected(previous_callback):
			_player_combat_source.combat_state_changed.disconnect(previous_callback)
	_player_combat_source = player_node
	if _player_combat_source != null and _player_combat_source.has_signal("combat_state_changed"):
		_player_combat_source.combat_state_changed.connect(_on_player_combat_state_changed)


func _on_player_combat_state_changed(_cooldown_remaining: float, _cooldown_duration: float, attack_label: String, _weapon_type: StringName) -> void:
	if not _prefers_touch_hud() or GameManager.has_seen_tutorial_hint(MOBILE_HINT_ATTACK):
		return
	if attack_label == "Use Hands":
		return
	_queue_mobile_tutorial(MOBILE_HINT_ATTACK, "Attack: tap the right Attack button. The aim pad can steer ranged shots, and melee follows your facing.")


func _on_build_mode_changed(active: bool) -> void:
	if not active or not _prefers_touch_hud():
		return
	_queue_mobile_tutorial(MOBILE_HINT_BUILDING, "Building: tap Build, pick a card, drag to adjust the snapped preview, then use Rotate, Confirm, or Cancel.")

func _update_health(current_health: int, max_health: int) -> void:
	health_display.update_health(current_health, max_health)

func _refresh_held_item() -> void:
	var held_item := InventoryManager.get_slot_data(InventoryManager.active_slot_index)
	if held_item.item_id == &"" or held_item.quantity <= 0:
		held_item_icon.texture = null
		held_item_icon.modulate = Color(1.0, 1.0, 1.0, 0.25)
		held_item_label.text = "Hands Empty"
		return

	var item_id := String(held_item.item_id)
	var element_data := GameplayData.elements().get_element(held_item.item_id)
	held_item_icon.texture = _get_placeholder_texture(item_id)
	held_item_icon.modulate = _get_item_color(item_id)
	held_item_label.text = (
		str(element_data.get("display_name", item_id))
		if not element_data.is_empty() else item_id
	)

func _on_held_item_changed() -> void:
	_refresh_held_item()

func _on_weight_changed(total_weight: float, carry_capacity: float) -> void:
	weight_label.text = "%.1f / %.1f kg" % [total_weight, carry_capacity]
	carrier_risk_display.update_weight(total_weight, carry_capacity)


func _on_save_completed(result: Dictionary) -> void:
	if int(result.get(&"trigger", -1)) != GameManager.SaveTrigger.MANUAL:
		return
	if bool(result.get(&"success", false)):
		_queue_toast("Game saved to slot %d." % int(result.get(&"slot_id", GameManager.active_save_slot)))
		return
	_queue_toast("Save failed: %s" % str(result.get(&"error", "Unknown error")))


func _on_day_changed(_day: int) -> void:
	_refresh_day_time()


func _on_time_of_day_changed(_time_of_day: float) -> void:
	_refresh_day_time()


func _refresh_day_time() -> void:
	var day_time_text := _get_day_time_text()
	day_time_label.text = day_time_text
	weather_display.refresh_day_time()


func _on_objectives_changed(_objective_id: StringName) -> void:
	_refresh_objectives()


func _on_objectives_state_restored() -> void:
	_refresh_objectives()


func _refresh_objectives() -> void:
	objectives_display.panel_visible = _objectives_panel_visible
	objectives_display.set_collapsed(_objectives_collapsed)
	objectives_display.refresh()


func _refresh_objectives_collapse_state() -> void:
	objectives_display.set_collapsed(_objectives_collapsed)


func _apply_hud_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var touch_mode := MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()
	if touch_mode:
		_apply_touch_hud_layout(viewport_size)
	else:
		_apply_desktop_hud_layout()


func _apply_touch_hud_layout(viewport_size: Vector2) -> void:
	var safe_insets := _get_safe_insets(viewport_size)
	var inset_left := float(safe_insets.get(&"left", 0.0))
	var inset_top := float(safe_insets.get(&"top", 0.0))
	var inset_right := float(safe_insets.get(&"right", 0.0))
	var inset_bottom := float(safe_insets.get(&"bottom", 0.0))
	var left := inset_left + TOUCH_HUD_MARGIN
	var top := inset_top + TOUCH_HUD_MARGIN
	var right := viewport_size.x - inset_right - TOUCH_HUD_MARGIN
	var bottom := viewport_size.y - inset_bottom - TOUCH_HUD_MARGIN

	var minimap_size := TOUCH_MINIMAP_COLLAPSED_SIZE if _minimap_collapsed else TOUCH_MINIMAP_EXPANDED_SIZE
	minimap_placeholder.anchor_left = 0.0
	minimap_placeholder.anchor_top = 0.0
	minimap_placeholder.anchor_right = 0.0
	minimap_placeholder.anchor_bottom = 0.0
	minimap_placeholder.offset_left = right - minimap_size
	minimap_placeholder.offset_top = top
	minimap_placeholder.offset_right = right
	minimap_placeholder.offset_bottom = top + minimap_size
	minimap_toggle_button.visible = true
	minimap_toggle_button.position = Vector2(right - 42.0, top + 4.0)
	minimap_toggle_button.size = Vector2(42.0, 28.0)
	minimap_toggle_button.text = "+" if _minimap_collapsed else "-"

	objectives_panel.anchor_left = 0.0
	objectives_panel.anchor_top = 0.0
	objectives_panel.anchor_right = 0.0
	objectives_panel.anchor_bottom = 0.0
	objectives_panel.offset_left = left
	objectives_panel.offset_top = top
	objectives_panel.offset_right = left + minf(286.0, viewport_size.x * 0.52)
	objectives_panel.offset_bottom = top + (52.0 if _objectives_collapsed else 146.0)
	objectives_panel.visible = _objectives_panel_visible
	_refresh_objectives_collapse_state()

	var header_bottom := top + 50.0
	day_time_label.visible = true
	day_time_label.anchor_left = 0.0
	day_time_label.anchor_top = 0.0
	day_time_label.anchor_right = 0.0
	day_time_label.anchor_bottom = 0.0
	day_time_label.offset_left = (viewport_size.x - 180.0) * 0.5
	day_time_label.offset_top = header_bottom
	day_time_label.offset_right = day_time_label.offset_left + 180.0
	day_time_label.offset_bottom = header_bottom + 28.0
	day_time_label.add_theme_font_size_override("font_size", 16)

	if _weather_strip != null:
		_weather_strip.position = Vector2((viewport_size.x - _weather_strip.size.x) * 0.5, header_bottom + 24.0)

	if carrier_risk_strip != null:
		carrier_risk_strip.position = Vector2((viewport_size.x - carrier_risk_strip.size.x) * 0.5, header_bottom + 24.0)

	health_bar.anchor_left = 0.0
	health_bar.anchor_top = 0.0
	health_bar.anchor_right = 0.0
	health_bar.anchor_bottom = 0.0
	health_bar.offset_left = left
	health_bar.offset_top = bottom - TOUCH_BOTTOM_CONTROL_CLEARANCE
	health_bar.offset_right = left + 150.0
	health_bar.offset_bottom = health_bar.offset_top + 24.0
	health_label.add_theme_font_size_override("font_size", 13)
	weight_label.anchor_left = 0.0
	weight_label.anchor_top = 0.0
	weight_label.anchor_right = 0.0
	weight_label.anchor_bottom = 0.0
	weight_label.offset_left = left
	weight_label.offset_top = health_bar.offset_top + 30.0
	weight_label.offset_right = left + 156.0
	weight_label.offset_bottom = weight_label.offset_top + 24.0
	weight_label.add_theme_font_size_override("font_size", 14)

	held_item_container.anchor_left = 0.0
	held_item_container.anchor_top = 0.0
	held_item_container.anchor_right = 0.0
	held_item_container.anchor_bottom = 0.0
	held_item_container.offset_left = right - TOUCH_SIDE_CARD_WIDTH
	held_item_container.offset_top = top + minimap_size + 12.0
	held_item_container.offset_right = right
	held_item_container.offset_bottom = held_item_container.offset_top + 54.0
	held_item_label.add_theme_font_size_override("font_size", 14)

	if _journal_update_indicator != null:
		_journal_update_indicator.anchor_left = 0.0
		_journal_update_indicator.anchor_top = 0.0
		_journal_update_indicator.anchor_right = 0.0
		_journal_update_indicator.anchor_bottom = 0.0
		_journal_update_indicator.offset_left = held_item_container.position.x - 8.0
		_journal_update_indicator.offset_top = held_item_container.position.y + held_item_container.size.y + 8.0
		_journal_update_indicator.offset_right = held_item_container.position.x + held_item_container.size.x
		_journal_update_indicator.offset_bottom = _journal_update_indicator.offset_top + 22.0
		_journal_update_indicator.text = _get_journal_indicator_text()

	if _night_defense_strip != null:
		_night_defense_strip.position = Vector2(left, top + objectives_panel.size.y + 8.0)


func _apply_desktop_hud_layout() -> void:
	minimap_placeholder.anchor_left = 1.0
	minimap_placeholder.anchor_top = 0.0
	minimap_placeholder.anchor_right = 1.0
	minimap_placeholder.anchor_bottom = 0.0
	minimap_placeholder.offset_left = -72.0
	minimap_placeholder.offset_top = 8.0
	minimap_placeholder.offset_right = -8.0
	minimap_placeholder.offset_bottom = 72.0
	minimap_toggle_button.visible = false

	objectives_panel.anchor_left = 0.0
	objectives_panel.anchor_top = 0.0
	objectives_panel.anchor_right = 0.0
	objectives_panel.anchor_bottom = 0.0
	objectives_panel.offset_left = 16.0
	objectives_panel.offset_top = 44.0
	objectives_panel.offset_right = 292.0
	objectives_panel.offset_bottom = 166.0
	objectives_panel.visible = _objectives_panel_visible
	_objectives_collapsed = false
	_refresh_objectives_collapse_state()

	day_time_label.anchor_left = 0.5
	day_time_label.anchor_top = 0.0
	day_time_label.anchor_right = 0.5
	day_time_label.anchor_bottom = 0.0
	day_time_label.visible = _weather_strip == null
	day_time_label.offset_left = -90.0
	day_time_label.offset_top = 18.0
	day_time_label.offset_right = 90.0
	day_time_label.offset_bottom = 42.0
	day_time_label.add_theme_font_size_override("font_size", 18)
	health_bar.anchor_left = 0.0
	health_bar.anchor_top = 1.0
	health_bar.anchor_right = 0.0
	health_bar.anchor_bottom = 1.0
	health_bar.offset_left = 24.0
	health_bar.offset_top = -52.0
	health_bar.offset_right = 124.0
	health_bar.offset_bottom = -24.0
	weight_label.anchor_left = 0.0
	weight_label.anchor_top = 1.0
	weight_label.anchor_right = 0.0
	weight_label.anchor_bottom = 1.0
	weight_label.offset_left = 136.0
	weight_label.offset_top = -52.0
	weight_label.offset_right = 292.0
	weight_label.offset_bottom = -24.0
	held_item_container.anchor_left = 0.5
	held_item_container.anchor_top = 1.0
	held_item_container.anchor_right = 0.5
	held_item_container.anchor_bottom = 1.0
	held_item_container.offset_left = -110.0
	held_item_container.offset_top = -88.0
	held_item_container.offset_right = 110.0
	held_item_container.offset_bottom = -24.0
	if _journal_update_indicator != null:
		_journal_update_indicator.anchor_left = 1.0
		_journal_update_indicator.anchor_right = 1.0
		_journal_update_indicator.offset_left = -180.0
		_journal_update_indicator.offset_top = 46.0
		_journal_update_indicator.offset_right = -20.0
		_journal_update_indicator.offset_bottom = 72.0
		_journal_update_indicator.text = _get_journal_indicator_text()


func _get_safe_insets(viewport_size: Vector2) -> Dictionary:
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if DisplayServer.has_method("get_display_safe_area"):
		var safe_area: Variant = DisplayServer.get_display_safe_area()
		if safe_area is Rect2i:
			safe_rect = Rect2(safe_area.position, safe_area.size)
		elif safe_area is Rect2:
			safe_rect = safe_area
	return {
		&"left": maxf(0.0, safe_rect.position.x),
		&"top": maxf(0.0, safe_rect.position.y),
		&"right": maxf(0.0, viewport_size.x - safe_rect.end.x),
		&"bottom": maxf(0.0, viewport_size.y - safe_rect.end.y),
	}


func _show_death_overlay(cause_of_death: StringName) -> void:
	health_display.show_death(cause_of_death)


func _hide_death_overlay() -> void:
	health_display.hide_death()


func _on_carrier_risk_warning(element_id: StringName, seconds_remaining: int) -> void:
	carrier_risk_display.show_warning(element_id, seconds_remaining)


func _on_carrier_risk_cleared(element_id: StringName) -> void:
	carrier_risk_display.clear_warning(element_id)


func _on_carrier_risk_ignition(element_id: StringName) -> void:
	carrier_risk_display.clear_warning(element_id)


func _hide_carrier_risk_warning() -> void:
	carrier_risk_display.clear_warning()


func _on_scanner_tier_changed(previous_tier: int, new_tier: int) -> void:
	if previous_tier != GameManager.ScannerTier.BASIC or new_tier != GameManager.ScannerTier.ADVANCED:
		return
	_show_scanner_upgrade_toast()


func _show_scanner_upgrade_toast() -> void:
	if _scanner_upgrade_tween != null:
		_scanner_upgrade_tween.kill()

	scanner_upgrade_label.text = "Scanner upgraded"
	scanner_upgrade_label.visible = true
	scanner_upgrade_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_scanner_upgrade_tween = create_tween()
	_scanner_upgrade_tween.tween_property(scanner_upgrade_label, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	_scanner_upgrade_tween.tween_interval(SCANNER_TOAST_SECONDS)
	_scanner_upgrade_tween.tween_property(scanner_upgrade_label, "modulate:a", 0.0, 0.28).set_ease(Tween.EASE_IN)
	_scanner_upgrade_tween.tween_callback(_hide_scanner_upgrade_toast)


func _hide_scanner_upgrade_toast() -> void:
	scanner_upgrade_label.visible = false
	scanner_upgrade_label.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _setup_night_defense_warning() -> void:
	_night_defense_strip = Panel.new()
	_night_defense_strip.name = "NightDefenseStrip"
	_night_defense_strip.visible = false
	_night_defense_strip.offset_left = 24.0
	_night_defense_strip.offset_top = 120.0
	_night_defense_strip.offset_right = 384.0
	_night_defense_strip.offset_bottom = 164.0
	add_child(_night_defense_strip)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.10, 0.07, 0.92)
	style.border_color = Color(0.88, 0.62, 0.24, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_night_defense_strip.add_theme_stylebox_override("panel", style)

	_night_defense_label = Label.new()
	_night_defense_label.offset_left = 12.0
	_night_defense_label.offset_top = 10.0
	_night_defense_label.offset_right = 344.0
	_night_defense_label.offset_bottom = 34.0
	_night_defense_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_night_defense_label.text = "Movement detected in the powered perimeter."
	_night_defense_strip.add_child(_night_defense_label)


func _on_night_threat_detected(_world_position: Vector2, stack_count: int) -> void:
	if _night_defense_strip == null or _night_defense_label == null:
		return
	if _night_defense_tween != null:
		_night_defense_tween.kill()
	_night_defense_label.text = "Movement detected in the powered perimeter. Light stack: %d" % stack_count
	_night_defense_strip.visible = true
	_night_defense_strip.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_night_defense_tween = create_tween()
	_night_defense_tween.tween_property(_night_defense_strip, "modulate:a", 1.0, 0.16)
	_night_defense_tween.tween_interval(NIGHT_DEFENSE_TOAST_SECONDS)
	_night_defense_tween.tween_property(_night_defense_strip, "modulate:a", 0.0, 0.24)
	_night_defense_tween.tween_callback(func() -> void:
		if _night_defense_strip != null:
			_night_defense_strip.visible = false
	)


func _on_weather_warning_started(target_state: int, seconds_remaining: float) -> void:
	_queue_toast(
		"%s incoming in %s. Shelter or store sensitive materials now."
			% [_get_weather_state_name(target_state), _format_weather_eta(seconds_remaining)]
	)
	_update_weather_strip()


func _on_weather_warning_ended(_target_state: int) -> void:
	_update_weather_strip()


func _on_weather_changed(_new_state: int) -> void:
	_update_weather_strip()


func _on_weather_forecast_changed(_next_state: int, _seconds_until_change: float) -> void:
	_update_weather_strip()


func _setup_discovery_journal() -> void:
	_journal_panel = DISCOVERY_JOURNAL_SCENE.instantiate()
	add_child(_journal_panel)
	if _journal_panel.has_signal("close_requested"):
		_journal_panel.close_requested.connect(_close_journal)
	if _journal_panel.has_method("hide_panel"):
		_journal_panel.hide_panel()


func _setup_journal_update_indicator() -> void:
	if _journal_update_indicator != null:
		return
	_journal_update_indicator = Label.new()
	_journal_update_indicator.name = "JournalUpdateIndicator"
	_journal_update_indicator.visible = false
	_journal_update_indicator.text = _get_journal_indicator_text()
	_journal_update_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_journal_update_indicator.add_theme_font_size_override("font_size", 14)
	_journal_update_indicator.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42, 1.0))
	_journal_update_indicator.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05, 0.9))
	_journal_update_indicator.add_theme_constant_override("outline_size", 3)
	_journal_update_indicator.anchor_left = 1.0
	_journal_update_indicator.anchor_right = 1.0
	_journal_update_indicator.offset_left = -180.0
	_journal_update_indicator.offset_top = 46.0
	_journal_update_indicator.offset_right = -20.0
	_journal_update_indicator.offset_bottom = 72.0
	_journal_update_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_journal_update_indicator)


func _open_journal() -> void:
	if _journal_panel == null or _journal_open:
		return

	_pause_player_input()
	_journal_open = true
	_set_journal_update_indicator(false)
	_journal_panel.show_panel()
	_refresh_journal_indicator_copy()


func _close_journal() -> void:
	if _journal_panel == null or not _journal_open:
		return

	_journal_open = false
	_journal_panel.hide_panel()
	_resume_player_input()
	_refresh_journal_indicator_copy()


func _on_discovery_entry_added(_entry: Dictionary) -> void:
	if _journal_open:
		return
	_set_journal_update_indicator(true)


func _set_journal_update_indicator(active: bool) -> void:
	_journal_has_unread_entries = active
	if _journal_update_indicator != null:
		_journal_update_indicator.visible = active
		_journal_update_indicator.text = _get_journal_indicator_text()


func _refresh_journal_indicator_copy() -> void:
	if _journal_update_indicator != null:
		_journal_update_indicator.text = _get_journal_indicator_text()


func _get_journal_indicator_text() -> String:
	return "New Entry" if _prefers_touch_hud() else "New Entry [J]"


func _pause_player_input() -> void:
	var player := GameManager.get_player()
	if player == null or not player.has_method("pause_input"):
		return

	_paused_player = player
	player.pause_input()


func _resume_player_input() -> void:
	if _paused_player == null or not is_instance_valid(_paused_player):
		_paused_player = null
		return
	if _paused_player.has_method("resume_input"):
		_paused_player.resume_input()
	_paused_player = null


func _open_debug_journal() -> void:
	_open_journal()
	if debug_report_journal_layout and _journal_panel != null and _journal_panel.has_method("debug_report_layout"):
		await get_tree().process_frame
		await get_tree().process_frame
		_journal_panel.debug_report_layout()


func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood":
			return Color.BURLYWOOD
		"stone":
			return Color.GRAY
		"iron":
			return Color.SILVER
		"steel":
			return Color(0.70, 0.76, 0.82, 1.0)
		"charcoal":
			return Color(0.17, 0.18, 0.20, 1.0)
		"lithium":
			return Color(0.76, 0.88, 1.0, 1.0)
		"sodium":
			return Color(0.92, 0.94, 0.86, 1.0)
		"mercury":
			return Color(0.84, 0.86, 0.90, 1.0)
		"rust_bolt":
			return Color(0.84, 0.38, 0.12, 1.0)
		"sulfuric_bolt":
			return Color(0.76, 0.90, 0.22, 1.0)
		"mercury_amalgam":
			return Color(0.72, 0.75, 0.79, 1.0)
		"toxic_slurry":
			return Color(0.42, 0.90, 0.35, 1.0)
		"steel_sword":
			return Color(0.82, 0.85, 0.90, 1.0)
		_:
			return Color.WHITE


func _update_weather_strip() -> void:
	weather_display.refresh()

func _get_weather_state_name(state: int) -> String:
	return weather_display.state_name(state)

func _format_weather_eta(seconds: float) -> String:
	return weather_display.format_eta(seconds)

func _get_day_time_text() -> String:
	var total_minutes: int = int(round(GameManager.time_of_day * 24.0 * 60.0)) % (24 * 60)
	var hour: int = int(floor(float(total_minutes) / 60.0))
	var minute: int = total_minutes % 60
	return "Day %d  %02d:%02d" % [GameManager.current_day, hour, minute]


func _get_placeholder_texture(item_id: String) -> Texture2D:
	if _placeholder_textures.has(item_id):
		return _placeholder_textures[item_id]

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 48
	texture.height = 48
	_placeholder_textures[item_id] = texture
	return texture

func _setup_toast_notification() -> void:
	_toast_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_color = Color(0.8, 0.7, 0.2, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_toast_panel.add_theme_stylebox_override("panel", style)
	_toast_panel.modulate.a = 0.0
	
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 20)
	
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)
	
	_toast_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_panel.offset_top = 100
	_toast_panel.offset_bottom = 140
	_toast_panel.offset_left = 300
	_toast_panel.offset_right = -300
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.z_index = 100
	
	if GameplayData.elements() != null:
		GameplayData.elements().element_discovered.connect(_on_element_discovered_toast)

func _on_element_discovered_toast(element_id: StringName) -> void:
	var elem = GameplayData.elements().get_element(element_id)
	if elem.is_empty():
		return
	var display_name = str(elem.get("display_name", element_id))
	_queue_toast("%s discovered — new entries added to journal" % display_name)
	
	for recipe_id in GameplayData.recipes().recipes.keys():
		var recipe = GameplayData.recipes().get_recipe(recipe_id)
		if recipe.get("requires_discovery") == element_id:
			_queue_toast("New recipe available: %s" % recipe.get("name", recipe_id))


func _on_environmental_warning_changed(warning_id: StringName, active: bool) -> void:
	if not active:
		return
	match warning_id:
		&"rain":
			_queue_toast("Rain started — carried lithium charge drains unless sheltered or stored dry.")
		&"electrical_storm":
			_queue_toast("Electrical storm — carried lithium slowly recharges while the storm holds.")
		&"acid_mist":
			_queue_toast("Acid Mist — exposed sulfur nodes are degrading in the open.")
		_:
			pass


func _on_base_threat_lesson_triggered(_lesson_id: StringName, message: String) -> void:
	_queue_toast(message)


func _on_loop_milestone_reached(tier: int) -> void:
	match tier:
		1:
			_queue_toast("Loop pressure increased. Night threats now pull from farther heat, light, and sulfur trails.")
		2:
			_queue_toast("Loop pressure increased again. The perimeter now needs tighter routes and steadier power.")
		_:
			_queue_toast("Loop pressure increased to tier %d." % tier)


func _on_objectives_progressed(_objective_id: StringName, _current: int, _target: int) -> void:
	_refresh_objectives()

func _queue_toast(message: String) -> void:
	_toast_queue.append(message)
	_play_next_toast()


func _prefers_touch_hud() -> bool:
	return MobileInputRouter != null and MobileInputRouter.prefers_touch_controls()


func _queue_mobile_tutorial(hint_id: StringName, message: String) -> void:
	if not _prefers_touch_hud() or GameManager.has_seen_tutorial_hint(hint_id):
		return
	GameManager.mark_tutorial_hint_seen(hint_id)
	_queue_toast(message)


func _show_first_run_mobile_overlay_if_needed() -> void:
	if not _prefers_touch_hud():
		return
	if mobile_tutorial_overlay == null or GameManager.has_seen_tutorial_hint(MOBILE_HINT_FIRST_RUN):
		return
	mobile_tutorial_overlay.visible = true
	GameManager.mark_tutorial_hint_seen(MOBILE_HINT_FIRST_RUN)
	get_tree().create_timer(MOBILE_TUTORIAL_AUTO_DISMISS_SECONDS).timeout.connect(_dismiss_mobile_tutorial_overlay)


func _dismiss_mobile_tutorial_overlay() -> void:
	if mobile_tutorial_overlay != null:
		mobile_tutorial_overlay.visible = false
	_queue_mobile_tutorial(MOBILE_HINT_MOVEMENT, "Movement: drag the left pad to move. Tap Sprint when you need speed and have stamina to spare.")


func _on_mobile_tutorial_tint_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dismiss_mobile_tutorial_overlay()
	elif event is InputEventMouseButton and event.pressed:
		_dismiss_mobile_tutorial_overlay()


func _maybe_show_inventory_tutorial() -> void:
	if not _prefers_touch_hud():
		return
	_queue_mobile_tutorial(MOBILE_HINT_INVENTORY, "Inventory: use the five-slot hotbar at the bottom, tap a slot to equip, long-press for details, and drag stacks to move them.")


func _maybe_show_station_tutorial() -> void:
	if not _prefers_touch_hud() or _current_touch_interactable == null or not is_instance_valid(_current_touch_interactable):
		return
	var prompt_text := ""
	if _current_touch_interactable.has_method("get_touch_interaction_prompt"):
		prompt_text = str(_current_touch_interactable.call("get_touch_interaction_prompt"))
	if prompt_text.findn("Furnace") != -1 or prompt_text.findn("ChemBench") != -1:
		_queue_mobile_tutorial(MOBILE_HINT_CRAFTING, "Crafting: walk up to a station and tap Interact. Furnaces handle heat work, and the ChemBench handles recipes and kits.")

func _play_next_toast() -> void:
	if _is_toast_playing or _toast_queue.is_empty():
		return
		
	_is_toast_playing = true
	var message = _toast_queue.pop_front()
	_toast_label.text = message
	
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
		
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.finished.connect(func():
		_is_toast_playing = false
		_play_next_toast()
	)
