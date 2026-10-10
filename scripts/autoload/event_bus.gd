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

## The player completed an interaction ([param interaction_type] is an
## [enum InteractionDefinition.Type]; [param definition_id] its data id).
@warning_ignore("unused_signal")
signal interaction_performed(interaction_type: int, definition_id: StringName)

## The player greeted a wild animal of species [param species_id].
@warning_ignore("unused_signal")
signal animal_greeted(species_id: StringName)

## The player played with a wild animal of species [param species_id].
@warning_ignore("unused_signal")
signal animal_played(species_id: StringName)

## The weather changed to [param weather] ([code]&"clear"[/code], [code]&"cloudy"[/code],
## [code]&"rain"[/code]).
@warning_ignore("unused_signal")
signal weather_changed(weather: StringName)

## A need of the player reached its critical threshold (soft consequences start, ADR-003).
@warning_ignore("unused_signal")
signal need_critical(need_id: StringName)

## A critical need of the player recovered above its threshold + recover margin.
@warning_ignore("unused_signal")
signal need_recovered(need_id: StringName)

## The player opened the map (Phase 12: onboarding).
@warning_ignore("unused_signal")
signal map_opened

## The player met an animal of the journal for the first time (Phase 15).
@warning_ignore("unused_signal")
signal animal_discovered(entry_id: StringName)

## The player entered a biome for the first time, except the very first one where the game
## starts (Phase 16b: the atlas).
@warning_ignore("unused_signal")
signal biome_discovered(biome_id: StringName)

## The player opened the journal (Phase 15: onboarding).
@warning_ignore("unused_signal")
signal journal_opened

## A villager shooed the fox away from [param from] (global) (Phase 16).
@warning_ignore("unused_signal")
signal fox_shooed(from: Vector3)

## The fox came near a hamlet's food for the first time this session (Phase 16: onboarding).
@warning_ignore("unused_signal")
signal hamlet_food_seen
