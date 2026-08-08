# Sanitas in Tenebris — Project Handover

Last updated: 2026-08-08  
Repository: `https://github.com/hoskonen/sanitasintenebris`  
Audited branch/commit: `main` at `3303931` (`KCD2-156 Shelter buff now fixed`)  
Game/mod language: Kingdom Come: Deliverance II, Lua 5.1-style CryEngine scripting

## 1. Purpose of this document

This document is the durable handover for moving the project to another computer. It combines:

- the read-only source audit;
- the first runtime test and `kcd.log` findings;
- decisions made about scope and architecture;
- the recommended stabilization order;
- focused logging and manual test procedures;
- migration and fresh-computer checklists;
- a ready-to-use prompt for a new Codex task.

It is intentionally self-contained. A future developer or Codex session should not need the original chat history to understand where the project stands.

No stabilization changes had been implemented when this document was created. The audit deliberately avoided rewriting working engine integrations.

## 2. Important repository state before moving computers

At the time this handover was created, the Git worktree was not completely clean:

```text
## main...origin/main
 M Data/Scripts/SanitasInTenebris/Config.lua
```

The existing `Config.lua` modification belongs to the project owner and must not be discarded. It turns additional diagnostic logging on:

```diff
- enableLogOnce = false
- mainDebug = false
+ enableLogOnce = true
+ mainDebug = true
  debugPolling = true
  debugIndoorPolling = true
  debugRainTracker = true
  debugBuffLogic = true
- debugRoofDetection = false
+ debugRoofDetection = true
  fireDebug = true
  interiorLogicDebug = true
  debugDrying = true
- rainCleansDebug = false
+ rainCleansDebug = true
```

This explains the very verbose runtime log. Before transferring the project, either commit this diagnostic configuration intentionally or copy the entire working directory, including uncommitted files. Cloning only `origin/main` will not reproduce it or this handover unless they are committed/pushed first.

Missing UI icons are also known. They were not present in this checkout and are expected to be recovered later from the owner's main computer. This is an asset-recovery task and should not block lifecycle stabilization.

## 3. Project concept and release scope

Sanitas in Tenebris models environmental exposure and recovery.

The intended v1.0 scope is:

- exposed rain increases player wetness;
- recognized interiors prevent rain exposure;
- outdoor roofs and covered spaces prevent rain exposure where the physics detector works;
- wetness has mild, moderate, and severe debuff tiers;
- wetness buffs upgrade and downgrade correctly;
- all wetness buffs disappear reliably at zero wetness;
- normal indoor drying works;
- outdoor drying works after rain stops;
- nearby fire accelerates drying;
- torch-assisted drying works consistently;
- rain cleaning may ship if it proves stable;
- startup, save loading, in-session save switching, pause, and resume do not corrupt state, buffs, or timers;
- recurring tasks cannot silently stop, duplicate, or rearm after being stopped;
- settings and developer actions can eventually be exposed through an in-game mod menu.

Explicitly deferred until after a stable v1.0:

- cold accumulation and hypothermia;
- diseases;
- clothing insulation;
- wind chill;
- seasonal temperature;
- other major survival mechanics.

The `mod.manifest` currently says version `1.0`; this should not be interpreted as proof that the stabilization goals above are complete.

## 4. Strategic rules

Preserve these experimentally discovered engine integrations unless runtime evidence proves they are broken:

- `XGenAIModule.IsPointInAreaWithLabel(pos, "interior")`;
- the upward `Physics.RayWorldIntersection` roof test;
- fire entity classification and negative/unlit matching;
- wetness hysteresis;
- current rain-intensity access;
- working parts of rain cleaning.

Prefer small, reversible changes. Do not begin with a framework, a total state rewrite, or a merge of every poller into one giant callback.

Keep these concepts separate:

- raw wetness percentage vs. wetness buff tier;
- being near fire vs. actively drying;
- displayed warming/fire buff vs. drying timer activity;
- recognized interior vs. roofed outdoor space;
- logical polling suspension vs. an actually stopped timer;
- persisted authoritative state vs. derived runtime state.

## 5. Current repository layout

The relevant files are:

```text
mod.manifest
README.md
Localization/text__sanitasintenebris.xml
Data/Scripts/mods/sanitasintenebris.lua
Data/Scripts/SanitasInTenebris/
  BuffLogic.lua
  Config.lua
  DebugTools.lua
  DryingSystem.lua
  HeatDetection.lua
  IndoorDetection.lua
  InteriorLogic.lua
  Main.lua
  PollingManager.lua
  RainCleans.lua
  RainTracker.lua
  RoofDetection.lua
  State.lua
  Utils.lua
Data/Libs/Tables/rpg/buff__sanitasintenebris.xml
Data/Libs/Tables/rpg/perk__sanitasintenebris.xml
Data/Libs/Tables/rpg/perk_recipe__sanitasintenebris.xml
Data/Libs/Tables/item/item__sanitasintenebris.xml
Data/Libs/Tables/minigame/AlchemyRecipe__sanitasintenebris.xml
```

All XML files parsed as well-formed XML during the audit. That does not validate them against KCD2 database schemas.

## 6. Actual boot and dependency map

### 6.1 Loader sequence

`Data/Scripts/mods/sanitasintenebris.lua` currently loads modules in this order:

```text
PollingManager        (first load, before Config and Utils)
Utils
State
Config
DebugTools
RoofDetection
HeatDetection
BuffLogic
IndoorDetection
InteriorLogic
DryingSystem
RainTracker
RainCleans
Main
  └─ Main reloads PollingManager a second time
  └─ Main registers System/OnGameplayStarted
root loader exports timer-callable global functions
```

Only `PollingManager.lua` and `Main.lua` return module values. Most modules expose global tables instead. The only assigned `Script.ReloadScript` result is the second `PollingManager` reload inside `Main.lua`.

Important globals include:

```text
Config
State
Utils
PollingManager
RainTracker
BuffLogic
InteriorLogic
SanitasInTenebris
SanitasInTenebris.RoofDetection
SanitasInTenebris.HeatDetection
SanitasInTenebris.IndoorDetection
SanitasInTenebris.DryingSystem
SanitasInTenebris.RainCleans
SanitasInTenebris.DebugTools
_G.HeatDetection
```

Only one event registration was found:

```text
UIAction.RegisterEventSystemListener(
  SanitasInTenebris,
  "System",
  "OnGameplayStarted",
  "OnGameplayStarted"
)
```

There are no explicit pause, resume, pre-load, post-load, or save-switch handlers.

### 6.2 Dependency outline

```text
Main
├─ Config, State, Utils, PollingManager
├─ InteriorLogic → BuffLogic, DryingSystem, Main schedulers
├─ RoofDetection
├─ HeatDetection
├─ RainTracker → InteriorLogic, RoofDetection, HeatDetection,
│                BuffLogic, DryingSystem
├─ DryingSystem → InteriorLogic, HeatDetection, BuffLogic,
│                 RainTracker at runtime
└─ RainCleans → Config, State, Utils, environment/player context
```

`IndoorDetection.lua` is loaded but no caller uses it. If called now, it references missing or obsolete APIs/configuration:

- `SanitasInTenebris.config`;
- `maxValidDoorDistance`;
- `BuffLogic.ApplyWarmingBuff`;
- `BuffLogic.RemoveWarmingBuff`.

Treat it as experimental/deferred. Do not delete it until any useful engine-discovery knowledge has been documented.

### 6.3 Recommended safe load order

Do not change this until the first runtime baseline is safely preserved, but the eventual safe order should be approximately:

```text
namespace
Config
Utils
State
PollingManager       (exactly once)
InteriorLogic detector portion
RoofDetection
HeatDetection
BuffLogic
DryingSystem
RainTracker
RainCleans
DebugTools
Main                 (event and lifecycle owner, always last)
```

The RainTracker/DryingSystem circular runtime relationship can remain temporarily. Avoid broad module restructuring merely to remove it.

## 7. What the first runtime test proved

The attached test log was `D:\Steam\steamapps\common\KingdomComeDeliverance2\kcd.log`, last inspected on 2026-07-19.

Summary:

- total log lines: `558`;
- Sanitas lines: `518` (`92.8%` of the log);
- no actual Sanitas error, crash, exception, or failed-call messages were found;
- the player loaded in a recognized interior;
- the sheltered buff applied after its debounce and was removed on exit;
- interior/exterior transitions occurred;
- fire detection found an apothecary fireplace/light at strength `0.90`;
- fire detection's consecutive-confirmation behavior worked;
- while dry and near fire, `fire_signal` was applied as intended;
- fire detection later switched off after two negative checks;
- wetness remained zero, so real wetness gain/tier/drying behavior was not tested;
- RainCleans did not start in this run because startup occurred indoors.

### Important correction about roof detection

The runtime shelter seen in that test came from the XGen `"interior"` label, not from a successful roof ray.

The log contained:

- zero `Overhead hit` roof messages;
- zero `RoofedOutside = true` messages;
- several `No overhead geometry detected` messages;
- all printed `RoofedOutside` results were false.

Therefore roof detection has not yet been proven on this current game installation. It may still be robust, as remembered, but it needs an isolated test under a known outdoor roof that is not marked as an interior.

### Important polling evidence

The log directly confirmed that after entering an interior:

```text
CheckRain skipped — polling suspended
OutdoorPoll skipped — polling suspended
```

These messages repeated. The callbacks remained scheduled and fired indoors; they merely returned early. This demonstrates the difference between `State.pollingSuspended` and an actually stopped timer.

### Main log-noise sources

- fire detection printed every entity in every nearby scan;
- fully-dry checks repeated continuously;
- logically suspended rain/outdoor callbacks logged repeatedly;
- shelter state writes emitted complete stack traces;
- most debug categories were simultaneously enabled.

## 8. Complete recurring-task inventory

| Task | Interval | Owner/start path | Stop behavior | Rearm behavior | Main finding |
|---|---:|---|---|---|---|
| `RainCheck` | 1 s | `PollingManager`, via `Main.Poll` | `Stop`/`StopAll` | Manager wrapper | Old callback can rearm after stop |
| `OutdoorPoll` | 2 s | `PollingManager`, via `Main.Poll` | `Stop`/`StopAll` | Manager wrapper | Continues firing while logically suspended |
| Manager `IndoorPoll` | 3 s | Unused `SetPollState` path | Manager | Manager wrapper | Current mode API is unused |
| Drying loop | 2 s | load restart, interior setup, RainTracker | No timer ID or Stop | Only after a successful drying tick | Can duplicate or silently die |
| Direct drying tick | During rain/indoor polls | `TryToDryOut` | None | Successful call schedules a future tick | Repeated calls can create more loops |
| RainTracker drying starter | 2 s | tier refresh | None | DryingSystem later rearms | Uses `warmingActive` as timer guard |
| RainCleans | 2 s | load restart | None | Rearms before work | Duplicate `Start` creates permanent parallel loops |
| Interior re-entry check | 3 s | outdoor gameplay startup | None | Always rearms | Every gameplay event can add another loop |
| Indoor poll one-shot | 1 s | interior setup | Boolean guard only | Wrapper rearms | No timer ID or generation |
| Interior exit check | 3 s | interior setup | Boolean guard only | Rearms while interior | No timer ID or generation |
| Delayed `Poll()` startup | 3 s | outdoor gameplay startup | None | Single shot | Old-save callback can affect a new save |
| Delayed initialization | 5 s | gameplay startup | None | Single shot | Same cross-save risk |

### Core PollingManager defect

`PollingManager.Register` creates a recursive wrapper. After the user callback returns, the wrapper always schedules itself again and writes a new timer ID.

If the callback triggered `StopAll`, `Stop`, or a re-registration, the older wrapper can still return afterward, create a new timer, and overwrite the current timer ID. This is the zombie/stale-callback failure mode.

### Drying defect

The DryingSystem timer is rearmed only at the bottom of a successful drying tick. Earlier returns for rain, delay, missing player/soul, or already-dry state terminate that particular loop.

At the same time, `TryToDryOut` can invoke `DryingSystem.Tick` synchronously; a successful synchronous tick schedules another timer. Repeated poll calls can therefore create parallel drying loops.

## 9. State audit

No Lua save serialization was found. Existing `State` fields are runtime globals retained within a Lua VM/reload chain, not proven save-persistent values. Engine buffs, in contrast, are declared persistent.

### 9.1 Authoritative or intended-authoritative state

| Field | Meaning | Main writers | Risk |
|---|---|---|---|
| `wetnessPercent` | Raw wetness, intended 0–100 | RainTracker, DryingSystem, DebugTools | Not persisted; can disagree with persistent buffs |
| `wetnessLevel` | Derived tier 0–3 | RainTracker, BuffLogic, DebugTools | Correctly separate from percentage, but also used as buff mirror |
| `rainStoppedAt` | Outdoor drying-delay timestamp | RainTracker and DryingSystem | Two owners and different delay logic |

### 9.2 Environment and transition state

| Field | Meaning | Risk |
|---|---|---|
| `pollingSuspended` | Logical indoor-mode gate | Does not mean timers are stopped |
| `wasIndoors` | Previous indoor state | Also influences timer rearming |
| `roofedOutside` | Cached roof-ray result | No age/validity metadata |
| `_roofPrev`, `_roofStableSince` | Roof debounce | Derived and not reset on load |
| `_indoorPrev`, `_indoorStableSince` | Interior debounce | Derived and not consistently reset |
| `_indoorInitDone` | Interior initialization guard | Can survive save changes and suppress setup |
| `_fireSense` | Fire hysteresis counters/state | Correct derived state; reset only on successful startup |
| `_lastFireSeenAt` | Fire UI hold timestamp | Derived UI debounce |

### 9.3 Buff and drying mirrors

| Field | Meaning | Risk |
|---|---|---|
| `shelteredActive` | Lua belief that sheltered buff exists | Never checks actual engine buff state |
| `warmingType` | `normal`, `fire`, `fire_signal`, or nil | UI mode and lifecycle logic are entangled |
| `warmingActive` | Any warming/drying display thought active | Also used as a timer scheduling guard |
| `normalDryingActive` | Normal drying buff mirror | Can prevent removal of a stale engine buff |
| `fireDryingActive` | Fire drying buff mirror | Does not clearly distinguish signal-only mode |
| `_shelterCandidateAt` | Shelter apply debounce start | Derived runtime state |
| `_shelterLastSeenAt` | Shelter release-hold time | Derived runtime state |
| `_shelterApplying` | Reentry guard | Could remain true if an engine call throws |

### 9.4 Timer/lifecycle guards

| Field | Meaning | Risk |
|---|---|---|
| `isInitialized` | Startup gate for buff/rain logic | Set by unmanaged delayed callbacks |
| `dryingStarted` | Interior path believes drying started | Never cleared; outdoor start does not set it |
| `_indoorTimerArmed` | Indoor one-shot guard | Boolean cannot distinguish callback generations |
| `_exitTimerArmed` | Exit one-shot guard | Same stale-callback limitation |

### 9.5 Diagnostic and subsystem state

| Field | Meaning/status |
|---|---|
| `lastRainAmount` | RainTracker cache; can become stale indoors |
| `lastRainValue` | DryingSystem rain cache; duplicates `lastRainAmount` |
| `lastRainLevel` | Derived none/light/heavy value |
| `lastRainEndTime` | Written but never read |
| `lastRainTickLog` | Written but never read |
| `_lastInteriorLog` | Transition-based XGen logging cache |
| `lastIndoorPollSuspended` | Indoor skip-log cache |
| `lastIndoorHeatCheck` | Used only by currently-unused IndoorDetection |
| `lastIsIndoors` | RainCleans cache based on a broken context lookup |
| `idleRainCleansLog` | RainCleans log suppression |
| `lastPartialWashStrength` | RainCleans log suppression |
| `wetness` | Legacy diagnostic fallback, read but never written |

### 9.6 Initialized but unused legacy fields

Do not delete these until a dedicated reference-confirmed cleanup:

```text
retryPending
lastIndoorStatus
interiorDetected
environmentScoreIndoors
lastHeatPollingSuspendedState
buffShelteredApplied
wasDryLogged
```

`State.lua` also wraps state through a metatable. Repeated reloads can create nested proxy chains. Its intended warming-state trace lies outside `__newindex` and is ineffective. Do not redesign this in the first polling PR.

## 10. Buff audit

All buffs in `Data/Libs/Tables/rpg/buff__sanitasintenebris.xml` are marked `is_persistent="true"`.

| Buff | GUID | Current owner | Expected while dry? |
|---|---|---|---|
| Sheltered | `61d8e6fd-b3b0-496c-9982-a03e9d020fe5` | Main/InteriorLogic through BuffLogic | Yes |
| Mild wetness | `6c348be1-24f1-44e4-899f-d5f5fd59395e` | RainTracker/BuffLogic | No |
| Moderate wetness | `91e8b6cf-03ad-4a3f-a3c3-bb594a8825d6` | RainTracker/BuffLogic | No |
| Severe wetness | `de21390e-bd17-4c4e-a58c-d1ab688177c8` | RainTracker/BuffLogic | No |
| Normal drying | `7c4a5e71-23d2-4e26-b70f-b2932a7b0f59` | RainTracker/BuffLogic/DryingSystem | No |
| Fire drying/signal | `43d2ef34-8f0f-4b76-8966-5c9aaf29e1bd` | RainTracker/BuffLogic | Yes, as `fire_signal` |
| Ember's Embraced | `c98c1439-bae0-43f1-9d3b-6a64a13e5e82` | Unused/deferred | Deferred |
| Refreshed | `c98c1439-bae0-43f1-9d3b-6a64a13e5e82` | Unused/deferred | Deferred |
| Cleansed and Dried | `1a1e94c5-3e1d-4d58-b442-726ae9f4f7c1` | Unused/deferred | Deferred |

Important findings:

- No code queries actual engine buff presence; decisions trust Lua mirrors.
- `RemoveWetnessBuffs()` also clears `warmingActive`, although wetness-tier and warming-buff ownership are different concerns.
- `RemoveBuffByGuid()` can refuse to remove normal drying when the Lua mirror says it is already absent, preventing stale-buff recovery.
- Ember's Embraced and Refreshed currently share one GUID. XML is well formed, but the duplicate database identity must be corrected before enabling either buff.
- The dry path can fail to remove the fire-source buff if state mirrors have already been cleared.

The largest save/load risk is therefore persistent engine buffs combined with non-persisted Lua wetness and no reconciliation.

## 11. Confirmed or strongly evidenced code defects

### P0 — persistent buffs without load reconciliation

Cold load can produce raw Lua wetness `0` while a saved persistent wetness/drying/shelter buff remains on the player. A central reconciliation step is required after player and soul become available.

### P1 — stale PollingManager callbacks

Old callbacks can rearm after `Stop`, `StopAll`, or replacement. This should be the first implementation target.

### P1 — DryingSystem can duplicate or stop silently

It has multiple start paths, no owned timer ID, no Stop operation, early-return termination, and synchronous invocations that can schedule more loops.

### P1 — save-switch/startup cleanup is incomplete

`OnGameplayStarted` aborts if player or soul is temporarily absent and schedules no retry. Unmanaged timers from a previous save can remain active and delayed startup callbacks can affect a later save.

### P1 — `warmingActive` has multiple meanings

It indicates UI/buff state and acts as a recurring-timer scheduling guard. These must eventually become separate fields.

### P1 — undefined `indoorish` in RainTracker

`RainTracker.UpdateDryingBuffs(isIndoors, ...)` later tests `indoorish`, which is undefined in that function. Normal indoor drying UI therefore cannot be selected through that branch.

### P1 — RainCleans environment/player context is broken

RainCleans reads nonexistent `SanitasInTenebris.IsIndoors` and uses an undefined `player` variable for clothing washing. As a result, it can treat indoor rain as outdoor exposure and cannot reliably call `WashItems`.

Keep RainCleans optional until corrected and tested.

### P1 — conflicting drying permission

RainTracker permits drying when sheltered, near fire, or holding a torch, but DryingSystem rejects all outdoor rain before checking roof/fire/torch. The intended matrix must be written down and consumed consistently.

### P1 — wetness threshold question

Current thresholds are approximately:

```text
tier 1: enter 0.10, exit 0.05
tier 2: enter 20,   exit 15
tier 3: enter 50,   exit 45
```

Historical expectations were closer to 20/50/80. Do not automatically change this; confirm the intended balance with runtime evidence first.

### P2 — loader/config/debug drift

- PollingManager loads twice.
- Several callers reference undefined config names: `debugEnabled`, `debugMain`, `debugIndoor`, `indoorDebug`, `thresholds`, and `maxValidDoorDistance`.
- `DebugTools.ForceWetness` uses `Config.thresholds`, but the real table is `Config.wetnessThresholds`.

## 12. Recommended stabilization roadmap

### Phase 0 — Establish a transferable baseline

- Confirm current KCD2 compatibility on the new computer.
- Preserve the current commit and diagnostic config.
- Recover missing icons, but keep them separate from code changes.
- Create known test saves/locations:
  - dry outdoor;
  - wet outdoor;
  - wet recognized interior;
  - wet outdoor roof;
  - wet near known fire.
- Record current log behavior before refactoring.

### Phase 1 — Focused logging and PollingManager hardening

- Add per-registration generation tokens.
- Make `Stop` and `StopAll` invalidate generations.
- Prevent stale callbacks from rearming or overwriting the live timer ID.
- Record poll health metadata:
  - active;
  - interval;
  - generation;
  - timer ID;
  - tick count;
  - last tick;
  - last success;
  - last error.
- Add a compact `DumpHealth()` diagnostic.
- Do not change gameplay behavior in this task.

### Phase 2 — Explicit environment-mode ownership

- Outdoor mode owns RainCheck and OutdoorPoll.
- Indoor mode owns IndoorPoll.
- Entering an interior actually stops inappropriate outdoor polls.
- Exiting starts outdoor polls exactly once.
- Incrementally replace unmanaged re-entry/exit chains.
- Repeatedly cross an interior boundary and prove timer counts remain constant.

### Phase 3 — Single-owner DryingSystem

- One idempotent Start.
- One actual Stop.
- One recurring task owner.
- Early returns do not accidentally terminate the system.
- `TryToDryOut` requests/performs work without creating another recurring loop.
- Separate loop activity, heat proximity, active wetness reduction, and displayed warming type.

### Phase 4 — Load reconciliation

- Categorize every field as authoritative, derived, or engine mirror.
- Reset derived runtime state on every gameplay generation.
- Retry initialization until player and soul are valid, with a bounded warning policy.
- Add `ReconcileState(reason)`:
  - acquire player/soul safely;
  - reconstruct environment;
  - recompute tier;
  - remove contradictory or stale Sanitas buffs;
  - apply required buffs;
  - start/stop required systems;
  - emit one compact snapshot.
- Test cold restart and in-session save switching separately.

### Phase 5 — LuaDB persistence

The project currently does not use LuaDB. Add it only after authoritative state and reconciliation are stable; otherwise it will persist ambiguous state more reliably.

Initially persist only:

```text
schemaVersion
wetnessPercent
user settings
```

Reconstruct, do not persist:

```text
wetnessLevel
indoors/roofed/exposed
nearFire and fire hysteresis
pollingSuspended
timer IDs/generations/armed flags
shelteredActive
warmingActive/warmingType
dryingStarted
debounce timestamps and logging caches
```

Load sequence should be:

1. Wait for valid player and soul.
2. Load authoritative data.
3. Validate schema and clamp wetness.
4. Recalculate wetness tier.
5. Detect current environment.
6. Reconcile all Sanitas buffs.
7. Start exactly the recurring tasks required for the current mode.

### Phase 6 — Transition and gameplay cleanup

- Repair `indoorish` and RainCleans context/player lookup.
- Define one drying-permission matrix for rain, roof, interior, fire, and torch.
- Preserve existing XGen, ray, and fire matching implementation details.
- Decide thresholds and rates from runtime tests rather than historical memory alone.

### Phase 7 — Developer controls, menu, and v1 validation

Internal debug API first, then menu integration.

Useful settings:

```text
enable mod
rain wetness
wetness debuffs
drying
rain cleaning
interior shelter
roof shelter
fire drying
torch drying
verbose logging/profile
```

Useful developer actions:

```text
show state
show poll health
restart systems
reconcile state
clear wetness
set wetness 25/60/90
remove Sanitas buffs
test roof detection
test fire detection
select logging profile
```

## 13. Exact first implementation task

The first code change should be deliberately narrow:

> Harden `PollingManager.Register`, `Stop`, and `StopAll` with generation tokens and health metadata. Add a read-only health dump. Do not migrate other timers or change gameplay logic in the same change.

Primary file:

```text
Data/Scripts/SanitasInTenebris/PollingManager.lua
```

Possible small follow-up integration:

```text
Data/Scripts/SanitasInTenebris/DebugTools.lua
```

Acceptance criteria:

1. At most one live timer exists for each registered poll name.
2. Re-registering a name invalidates the previous generation.
3. `Stop(name)` prevents a callback from that generation from rearming.
4. `StopAll()` prevents every previous generation from rearming.
5. A stale callback cannot overwrite the timer ID of a newer generation.
6. Callback errors are recorded and the chosen rearm policy is explicit.
7. Health output shows active state, generation, interval, tick count, and last result.
8. Rain, roof, fire, wetness, and buff formulas remain unchanged.
9. A runtime test repeatedly enters/exits an interior and shows stable poll counts.

Why this is first: it fixes a proven lifecycle defect with high robustness gain while touching none of the experimentally discovered engine calls.

## 14. Focused logging profiles

Until a real category/level logger exists, edit only the current booleans and test one subsystem at a time.

### Roof-only profile

```lua
enableLogOnce = true
mainDebug = false
debugPolling = false
debugIndoorPolling = false
debugRainTracker = false
debugBuffLogic = false
debugRoofDetection = true
fireDebug = false
interiorLogicDebug = false
debugDrying = false
rainCleansDebug = false
```

### Polling-only profile

```lua
enableLogOnce = true
mainDebug = true
debugPolling = true
debugIndoorPolling = false
debugRainTracker = false
debugBuffLogic = false
debugRoofDetection = false
fireDebug = false
interiorLogicDebug = true
debugDrying = false
rainCleansDebug = false
```

### Fire-only profile

```lua
enableLogOnce = true
mainDebug = false
debugPolling = false
debugIndoorPolling = false
debugRainTracker = false
debugBuffLogic = false
debugRoofDetection = false
fireDebug = true
interiorLogicDebug = false
debugDrying = true
rainCleansDebug = false
```

The eventual logger should have:

```text
ERROR  always logged
WARN   recovery/degraded conditions
INFO   state transitions only
DEBUG  registration/restart and compact decisions
TRACE  per-tick values and per-entity scans
```

Expected guard behavior should not emit stack traces. Add category filters or named profiles such as `roof`, `polling`, `fire`, `drying`, and `all_trace`.

## 15. Focused roof test protocol

Do not change ray geometry before this test.

Use the roof-only logging profile and locate three nearby points:

1. open sky;
2. a roofed exterior such as a porch, awning, open stable, terrace, or smithy shelter;
3. a recognized XGen interior.

For each point record:

```text
location/name or coordinates
XGen interior result
roof ray result
hit class/name if present
whether shelter buff appears after debounce
whether rain wetness is suppressed (during rain test)
```

Expected semantic outcomes:

| Location | XGen interior | Roof ray | Exposure |
|---|---:|---:|---|
| Open sky | false | false | Exposed |
| Outdoor roof | false | true | Sheltered outdoor |
| Recognized interior | true | not important | Interior sheltered |

Only after this evidence should technical roof improvements be considered. Low-risk improvements may include structured diagnostic results (`roofed`, hit class/name/distance), better snapshot reporting, or multiple-hit handling. Preserve the proven central ray behavior until a failing case is reproducible.

## 16. Manual v1 test matrix

| Initial condition | Action | Expected wetness | Expected buffs | Expected lifecycle/log |
|---|---|---|---|---|
| Dry, exposed, no rain | Wait 30 s | Remains 0 | None | One outdoor/rain poll each |
| Dry, exposed, raining | Wait through thresholds | Increases monotonically | Exactly one tier buff | One rain transition; no INFO tick spam |
| Wet, rain continues | Cross thresholds upward | Increases | Correct upgrade, old tier absent | Tier transitions only |
| Wet, rain stops | Wait before/after delay | Stable, then decreases | Context-appropriate drying UI | Exactly one drying loop |
| Wet, recognized interior | Enter building | No rain gain, drying proceeds | Shelter plus normal/fire drying | Outdoor polls stopped, indoor active |
| Wet interior to dry exterior | Exit | Allowed outdoor drying | Shelter released after hold | Outdoor polls restored once |
| Wet, roofed exterior, rain | Enter known roof | No further rain gain | Shelter after debounce | Roof transition logged |
| Roofed to exposed in rain | Leave cover | Rain gain resumes | Shelter releases | No flicker or duplicate tasks |
| Wet near strong fire | Approach/leave | Faster decrease, then base rate | Fire then correct replacement/removal | Fire ON/OFF transitions |
| Dry near strong fire | Approach/leave | Remains 0 | Fire signal allowed | No wetness-drying loop required |
| Wet with torch | Equip/unequip inside/outside | Rate follows defined matrix | No stale fire buff | Torch shown in snapshot |
| Rain cleaning enabled | Compare exposed/roofed/interior rain | Independent wetness rules | No cleaning buff required | Only exposed rain advances cleaning |
| Save while wet | Cold exit/restart/load | Restored/reconciled value | Exactly one correct tier | Fresh lifecycle generation |
| Save A to Save B | Load another save in-session | Matches Save B | No Save A buffs | Old callbacks ignored |
| Player unavailable at startup | Load transition-heavy scene | No corruption | No premature buff changes | Bounded retry then initialize |
| Pause/resume | Pause during rain/drying | No duplicate elapsed work | Buffs consistent | Same live generations |

## 17. Proposed branch/PR sequence

Keep work narrow and reversible. Suggested branch names:

```text
codex/poll-generation-guard
codex/diagnostic-snapshot
codex/environment-mode-ownership
codex/drying-lifecycle-owner
codex/load-reconciliation
codex/luadb-persistence
codex/rain-cleans-repair
codex/config-debug-repair
codex/v1-validation-fixes
```

Do not combine timer migration, state renaming, buff reconciliation, persistence, and balance changes in one PR.

## 18. Migration checklist for the main computer

### Preserve source and uncommitted work

- [ ] Copy or commit `handover.md`.
- [ ] Preserve the modified `Data/Scripts/SanitasInTenebris/Config.lua`.
- [ ] Check `git status --short --branch` before and after transfer.
- [ ] If using Git alone, commit and push everything intentionally before cloning.
- [ ] If copying files manually, include hidden `.git` only if the full repository history/worktree should move unchanged.
- [ ] Do not copy a generated game log as though it were source; archive it separately if wanted.

### Recover external/missing assets

- [ ] Locate the missing buff/UI icons on the original main computer.
- [ ] Record their expected paths and names before adding them.
- [ ] Verify licensing/original ownership if any assets came from external sources.
- [ ] Keep the icon recovery commit separate from polling changes.

### Validate the new installation

- [ ] Confirm the mod directory is under the active KCD2 installation.
- [ ] Confirm `mod.manifest` and `Data` are present.
- [ ] Launch once with current code before refactoring.
- [ ] Verify `OnGameplayStarted`, interior detection, sheltered buff, and the known apothecary fire.
- [ ] Run the isolated roof test.
- [ ] Save the resulting `kcd.log` outside the repository or under a deliberately ignored diagnostics folder.

### Git ownership note

On the audited computer, Git reported dubious ownership for the repository. Read-only commands were run with a per-command override rather than changing global Git configuration:

```powershell
$repo = 'D:/Steam/steamapps/common/KingdomComeDeliverance2/mods/sanitasintenebris'
git -c "safe.directory=$repo" status --short --branch
git -c "safe.directory=$repo" log -8 --oneline --decorate
```

On the new computer, use normal Git commands if ownership is correct. Avoid adding a global safe-directory exception unless it is genuinely needed and understood.

## 19. Fresh audit protocol on the new computer

A complete audit does not need to be repeated automatically if the transferred tree matches commit `3303931` plus the documented local changes. Begin with a delta audit.

### 19.1 Establish identity and changes

```powershell
git status --short --branch
git log -8 --oneline --decorate
git diff -- Data/Scripts/SanitasInTenebris/Config.lua
rg --files
```

Confirm:

- HEAD commit;
- uncommitted files;
- whether icons or other assets were restored;
- whether any code changed after this handover.

### 19.2 Re-run targeted static searches

```powershell
rg -n "Script\.ReloadScript|UIAction\.RegisterEventSystemListener" Data/Scripts
rg -n "SetTimer|SetTimerForFunction|KillTimer|PollingManager" Data/Scripts/SanitasInTenebris
rg -n -o "State\.[A-Za-z_][A-Za-z0-9_]*" Data/Scripts/SanitasInTenebris
rg -n "AddBuff|RemoveAllBuffsByGuid|HasBuff|buff_id" Data Localization
rg -n "SanitasInTenebris\.config|Config\.thresholds|ApplyWarmingBuff|RemoveWarmingBuff|indoorish" Data/Scripts
```

### 19.3 Compare runtime behavior

For a new `kcd.log`, record:

```text
total lines and Sanitas lines
actual ERROR/WARN lines
OnGameplayStarted count
poll Register/Re-register/Stop counts
roof true/false transitions
interior true/false transitions
fire ON/OFF transitions
wetness and tier transitions
drying Start/Tick counts
RainCleans Start count
```

Do not interpret a sheltered buff as proof of roof detection unless XGen is false and the roof ray is true.

### 19.4 When a full re-audit is warranted

Repeat the full audit if any of these are true:

- HEAD or source differs substantially from this handover;
- KCD2 or a modding framework update changes timer/event APIs;
- LuaDB or a mod-menu framework has been introduced;
- recurring task ownership has been redesigned;
- save/load behavior differs between computers;
- the new runtime log contradicts the findings here.

## 20. Ready-to-use prompt for a new Codex session

Copy this into a new task after opening the repository:

```text
Read handover.md completely before acting. This is a KCD2 Lua 5.1 mod.

First perform a read-only delta check:
- verify HEAD and git status;
- preserve all user changes, especially Config.lua and recovered icons;
- compare current timer, state, buff, and loader references against the handover;
- inspect the newest kcd.log if supplied.

Do not rewrite the architecture or change gameplay formulas. Preserve XGen interior detection, the physics roof ray, fire classification, and wetness hysteresis.

The first intended implementation task is only:
Harden PollingManager.Register/Stop/StopAll with generation tokens and health metadata, add a compact read-only health dump, and verify that stale callbacks cannot rearm. Do not migrate other timers or alter rain, roof, fire, drying, wetness, or buff behavior in the same change.

Before editing, report any differences between the repository and handover.md. After editing, show exact files changed, validation performed, remaining runtime test steps, and do not commit or push unless explicitly asked.
```

## 21. Open questions to resolve with evidence

1. Does the roof ray still return true under a known outdoor roof on the current KCD2 build?
2. What are the intended wetness thresholds: current `0.10/20/50`, historical `20/50/80`, or another curve?
3. Are current drying multipliers expressed in percentage points per second as intended?
4. Should fire or torch permit outdoor drying during active rain, or only while sheltered?
5. Should roofed exterior spaces dry at ordinary outdoor speed during rain?
6. Which game events reliably distinguish cold startup, resume, and in-session save switching?
7. Which LuaDB implementation/version is appropriate for the current KCD2 mod ecosystem?
8. Are Ember's Embraced, Refreshed, and Cleansed and Dried still planned, and what GUID should each own?
9. Which missing icons exist on the main computer, and what exact paths does KCD2 expect?
10. Is RainCleans part of v1.0 or optional until after core lifecycle validation?

## 22. Current priority summary

The five highest-priority risks are:

1. Persistent engine buffs without Lua state persistence or load reconciliation.
2. Stale and duplicate recurring timers.
3. Drying loops that can multiply or silently terminate.
4. Save-switch/startup callbacks crossing lifecycle generations.
5. Conflation of heat proximity, displayed warming state, active drying, and timer activity.

The first three milestones are:

1. Transfer and reproduce the current baseline, including a focused roof test.
2. Harden PollingManager and add poll health visibility.
3. Establish explicit indoor/outdoor lifecycle ownership before touching gameplay balance.

The project is large, but the first step is intentionally small. Stabilize how recurring work starts and stops; then make state recoverable; then validate gameplay one subsystem at a time.
