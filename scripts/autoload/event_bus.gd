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
