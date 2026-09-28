class_name VegetationPalette
extends Resource
## Optional recolouring of imported vegetation materials: maps an imported material name
## (e.g. [code]leafsGreen[/code]) to the colour used instead. Unmapped materials keep their
## original colour.

## Material name → replacement colour.
@export var colors: Dictionary[String, Color] = {}
