# ADR-003: No death mechanic; soft consequences for critical needs

- **Status:** Accepted
- **Date:** 2026-09-27

## Context
Trailpaw is a cozy game. Needs (hunger, thirst, temperature comfort, energy) should give
gentle motivation to explore, not create stress or punish the player (ARCHITECTURE §5).

## Decision
The animal never dies and there is no fail state. When a need reaches its critical
threshold, `EventBus.need_critical` fires and soft consequences apply: slower movement,
tired idle animation, a subtle visual hint.

## Consequences
- No game-over, respawn or checkpoint logic; saves stay simple.
- Balancing is about pacing and feel rather than difficulty; it needs playtesting.
- Consequences must stay readable without UI walls of text (Phase 12 onboarding).
