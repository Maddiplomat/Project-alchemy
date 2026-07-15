class_name GameplayData
extends RefCounted

const ELEMENTS: ElementDatabaseResource = preload("res://resources/databases/ElementDatabase.tres")
const RECIPES: RecipeDatabaseResource = preload("res://resources/databases/RecipeDatabase.tres")
const BUILDINGS: BuildingDatabaseResource = preload("res://resources/databases/BuildingDatabase.tres")


static func elements() -> ElementDatabaseResource:
	return ELEMENTS.init()


static func recipes() -> RecipeDatabaseResource:
	return RECIPES.init()


static func buildings() -> BuildingDatabaseResource:
	return BUILDINGS.init()
