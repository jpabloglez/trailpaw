## Global signal hub. Systems emit and connect here instead of referencing each other.
##
## Holds signals only and never stores state. Signals are added by the phase that
## introduces them.
## [br][br]
## Autoload name: [code]EventBus[/code]. No [code]class_name[/code]: it would hide the
## autoload singleton.
extends Node

## The floating origin moved: every [code]origin_shiftable[/code] node was shifted by
## [code]-offset[/code] and [code]GameState.origin_chunk[/code] advanced accordingly.
## Listeners holding cached local positions must subtract [param offset] from them.
@warning_ignore("unused_signal")
signal origin_shifted(offset: Vector3)

## The F3 debug overlay was shown or hidden. Debug visualisers (chunk borders, ...) follow it.
@warning_ignore("unused_signal")
signal debug_overlay_toggled(overlay_visible: bool)

## The player entered a new biome (dominant with weight >= the tracker's threshold).
@warning_ignore("unused_signal")
signal biome_entered(biome_id: StringName, display_name: String)

## A need of the player reached its critical threshold (soft consequences start, ADR-003).
@warning_ignore("unused_signal")
signal need_critical(need_id: StringName)

## A critical need of the player recovered above its threshold + recover margin.
@warning_ignore("unused_signal")
signal need_recovered(need_id: StringName)
