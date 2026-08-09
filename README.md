# Sanitas in Tenebris

Sanitas in Tenebris is a Kingdom Come: Deliverance II Lua mod for environmental exposure and recovery. The v1 focus is rain wetness, shelter/interior detection, drying, fire/torch warmth, and reliable lifecycle behavior across startup, save load, pause/resume, and interior transitions.

## Current Status

Read `handover.md` before larger changes. It contains the full audit, runtime findings, and manual test matrix from the previous machine.

This checkout currently includes the handover commit and a profile-driven logging configuration. The current logging profile is `indoor`, set in `Data/Scripts/SanitasInTenebris/Config.lua`.

The first stabilization pass has started with `PollingManager` hardening:

- poll registrations now carry generation tokens;
- `Stop` and `StopAll` invalidate old generations;
- stale callbacks cannot rearm or overwrite newer timer IDs;
- poll health metadata is tracked;
- `PollingManager.DumpHealth()` and `SanitasInTenebris.DebugTools.DumpPollHealth()` expose a compact status dump.

## Logging Profiles

Set `Config.logging.profile` to one profile before launching the game:

- `quiet`: only important unconditional errors and explicit debug-tool output.
- `polling`: poll registration, stop/restart, and compact suspended-poll breadcrumbs.
- `indoor`: interior transitions, indoor polling, sheltered buff decisions, and poll lifecycle.
- `roof`: XGen interior changes plus roof-ray results.
- `shelter`: interior, roof, indoor, and sheltered-buff decisions without polling lifecycle spam.
- `fire`: fire ON/OFF transitions without per-entity scan spam.
- `fire_trace`: detailed fire entity scanning for fire-classification work only.
- `rain`: rain/wetness transitions and wetness buff tiering.
- `drying`: drying context, drying rates, and drying buff decisions.
- `rain_cleans`: rain cleaning only.
- `all_trace`: everything; use briefly because it will create large logs.

Use `Config.logging.overrides` for one-off additions without making a new profile. Example:

```lua
overrides = {
    debugRoofDetection = true
}
```

Module load breadcrumbs are controlled separately with `Config.logging.moduleLoads`.
Raw per-timer `PollingManager` tick lines are controlled by `debugPollTicks` and are only enabled by `all_trace` by default.
Set `Config.logging.enabled = false` to force every profile flag off.

Useful focused debug calls:

```lua
SanitasInTenebris.DebugTools.DumpPollHealth()
SanitasInTenebris.DebugTools.DumpShelterStatus()
```

## Stabilization Priorities

1. Harden recurring poll ownership and prove timer counts stay stable.
2. Split indoor/outdoor lifecycle ownership so inactive modes actually stop their pollers.
3. Make `DryingSystem` a single-owner loop with idempotent `Start` and explicit `Stop`.
4. Add load/save-switch reconciliation for persistent Sanitas buffs and runtime wetness state.
5. Repair RainCleans and debug/config drift after the core lifecycle is reliable.
6. Validate roof, rain, fire, torch, drying, and wetness-tier mechanics one subsystem at a time.
7. Add persistence and user-facing settings only after recovery behavior is proven.

## Known High-Risk Areas

- Persistent engine buffs can survive while Lua runtime state resets.
- Drying timers can still duplicate or silently stop outside `PollingManager`.
- `Main.lua` has unmanaged delayed callbacks for startup and interior re-entry checks.
- `warmingActive` mixes UI state, heat proximity, drying state, and timer ownership.
- RainCleans still has broken environment/player lookup and should remain optional.
- Roof detection has not yet been proven on this installation under a known outdoor roof.

## Manual Runtime Checks

Use focused logging profiles from `handover.md` and capture `kcd.log` outside the repo.

Immediate checks after polling changes:

- launch a dry outdoor save and confirm exactly one `RainCheck` and one `OutdoorPoll`;
- call `SanitasInTenebris.DebugTools.DumpPollHealth()` after startup;
- enter and exit a recognized interior several times;
- confirm stopped/replaced poll generations do not continue ticking;
- confirm rain, roof, fire, wetness, and buff formulas behave unchanged.

Next focused tests:

- open sky vs. outdoor roof vs. recognized interior;
- wetness gain during exposed rain;
- tier upgrades and downgrades;
- indoor drying;
- outdoor drying after rain stops;
- fire and torch-assisted drying.

## Development Rules

- Preserve the known engine integrations unless runtime evidence proves they are broken:
  `XGenAIModule.IsPointInAreaWithLabel`, upward `Physics.RayWorldIntersection`, fire classification, rain intensity access, and wetness hysteresis.
- Keep changes narrow and reversible.
- Do not mix lifecycle hardening, gameplay balance, persistence, and feature work in one pass.
- Do not delete experimental modules until useful engine-discovery knowledge has been documented.
