class_name InteractionPromptSettings
extends Resource
## Look and timing of the interaction prompt. Values live in
## [code]data/ui/interaction_prompt.tres[/code].

## Opacity change per second when the prompt appears or goes.
@export_range(0.1, 20.0, 0.1, "suffix:1/s") var fade_per_second: float = 0.0
## Separator between the key and the prompt text.
@export var separator: String = ""
