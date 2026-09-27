## Global signal hub. Systems emit and connect here instead of referencing each other.
##
## Holds signals only and never stores state. Signals are added by the phase that
## introduces them (e.g. [code]biome_entered[/code] in Phase 3).
## [br][br]
## Autoload name: [code]EventBus[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node
