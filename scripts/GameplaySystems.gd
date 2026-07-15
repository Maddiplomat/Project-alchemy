class_name GameplaySystems
extends Node

const WeatherSystem = preload("res://scripts/WeatherSystem.gd")
const StorageManager = preload("res://scripts/StorageManager.gd")
const ResearchObjectives = preload("res://scripts/ResearchObjectives.gd")

@onready var crafting_manager: Node = $CraftingManager
@onready var world_system: Node = $WorldSystem
@onready var chemistry_engine: Node = $ChemistryEngine
@onready var weather_system: Node = $WeatherSystem
@onready var discovery_log: Node = $DiscoveryLog
@onready var discovery_journal: Node = $DiscoveryJournal
@onready var combat_system: Node = $CombatSystem
@onready var carrier_risk_system: Node = $CarrierRiskSystem
@onready var build_system: Node = $BuildSystem
@onready var research_objectives: Node = $ResearchObjectives
@onready var storage_manager: Node = $StorageManager
@onready var base_defense_system: Node = $BaseDefenseSystem
@onready var base_threat_director: Node = $BaseThreatDirector

const SERVICE_NODES := {
	EventBus.SERVICE_CRAFTING_MANAGER: NodePath("CraftingManager"),
	EventBus.SERVICE_WORLD_SYSTEM: NodePath("WorldSystem"),
	EventBus.SERVICE_CHEMISTRY_ENGINE: NodePath("ChemistryEngine"),
	EventBus.SERVICE_WEATHER_SYSTEM: NodePath("WeatherSystem"),
	EventBus.SERVICE_DISCOVERY_LOG: NodePath("DiscoveryLog"),
	EventBus.SERVICE_DISCOVERY_JOURNAL: NodePath("DiscoveryJournal"),
	EventBus.SERVICE_COMBAT_SYSTEM: NodePath("CombatSystem"),
	EventBus.SERVICE_CARRIER_RISK_SYSTEM: NodePath("CarrierRiskSystem"),
	EventBus.SERVICE_BUILD_SYSTEM: NodePath("BuildSystem"),
	EventBus.SERVICE_RESEARCH_OBJECTIVES: NodePath("ResearchObjectives"),
	EventBus.SERVICE_STORAGE_MANAGER: NodePath("StorageManager"),
	EventBus.SERVICE_BASE_DEFENSE_SYSTEM: NodePath("BaseDefenseSystem"),
	EventBus.SERVICE_BASE_THREAT_DIRECTOR: NodePath("BaseThreatDirector"),
}


func _enter_tree() -> void:
	# Register before child _ready callbacks run so sibling services can resolve
	# one another during scene initialization.
	for service_id: StringName in SERVICE_NODES:
		EventBus.register_service(service_id, get_node(SERVICE_NODES[service_id]))


func _exit_tree() -> void:
	for service_id: StringName in SERVICE_NODES:
		EventBus.unregister_service(service_id, get_node_or_null(SERVICE_NODES[service_id]))
