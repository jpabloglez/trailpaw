# ADR-012: Need effects by tier — restrictions without losing control

- **Status:** Accepted
- **Date:** 2026-11-25

## Context
ADR-003 rules out death and asks for soft consequences. The first version (Phase 6) slows
the animal by 15–20 % while any need is critical, plus the tired idle and the vignette. In
play this reads as cosmetic: every need does the same thing, nothing changes at 0, and the
meters feel indicative only. We want needs to matter without making the game less fun.

## Decision
Each need has a **tier**: normal, **low** (at or below its critical threshold) and **empty**
(at 0, left only above `empty_recover_margin`). Each need gets its **own** effect per tier,
as data (`NeedEffect` in `data/needs/effects/`, listed in `data/needs/need_effects.tres`),
combined by the pure `NeedEffects`:

- Effects only take away **extras** — sprinting (in bursts, or not at all), high jumps,
  quick rests — or make **other** needs drain faster (capped, so no runaway spirals).
  Walking, trotting, interacting, resting and sniffing always work; speed never drops
  below 90 %. The animal never acts on its own (no forced stops or lying down).
- Each effect has a body-language **cue** (pant, growl, tired, shiver), so the player can
  read what is wrong from the animal; a blocked action pulses the meter that causes it.
- The nose **helps** with the remedy: low thirst / hunger widen the sniff range for water /
  food. Heat effects pause in shade or water.
- Feeling well (every need ≥ 70 %) gives a small **bonus** (+5 % speed): a carrot as well as
  a stick.
- A setting chooses **Off / Gentle / Normal** gameplay effects; cues and sniff help stay.

## Consequences
- Needs become a gentle pacing system rather than decoration; balancing (rates, burst
  lengths, the low → empty window) needs playtesting.
- `NeedDefinition.critical_speed_factor` and `tired_when_critical` are superseded by
  `NeedEffect` and are removed once movement reads `NeedEffects`.
- New effects are data: a `.tres` per need and tier, validated by `NeedEffectTable`.
- Extends ADR-003 (still no death and no fail state).
