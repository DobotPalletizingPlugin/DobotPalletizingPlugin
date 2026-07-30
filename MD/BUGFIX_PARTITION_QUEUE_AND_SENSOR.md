# Bugfix: Interlayer Queue And DI21 Timing

## Symptoms

Two related issues were observed:

1. Startup / ACK could raise a false interlayer empty alarm even when DI21 was ON.
2. If DI21 was checked after removing an interlayer action from the queue, the action could be lost after an empty-magazine stop.

## Bug 1: False Empty Alarm On Startup

### Scenario

```text
saved RePartNum = 0
DI21 = ON
startup / ACK reads saved value first
false alarm: Partition is empty!
```

### Root Cause

DI21 synchronization happened too late. The old saved count was used before the physical sensor restored the real interlayer availability.

### Fix

`src0.lua` startup sequence now synchronizes DI21 before FSM / ACK shortage logic:

```lua
InitStorageMode()
InitModbus()
SyncAllPartitionRemainBySensor(true)
InitFSM()
```

`src2.lua` also synchronizes DI21 before `CommitPalletNum()` after new pallet / ACK / reset flow.

## Bug 2: Queue Action Lost On Empty Interlayer Magazine

### Risk

If the code removes the action first:

```lua
CPoint = CQueue:Pop()
```

and then discovers DI21 is OFF, the interlayer motion has already been removed from the queue.

After the operator adds interlayers and restarts, the required interlayer action may be gone.

### Fix

The final logic checks the next action with `Peek()` before removing it:

```lua
local CPoint = CQueue:Peek()

if (CPoint.Paras ~= nil) and (CPoint.Paras.Mode == MotionType.Part) then
    if CheckPartitionRemainBeforeMotion(PalletNumber, CPoint) == false then
        return nil
    end
end

CPoint = CQueue:Pop()
```

Now the interlayer action stays in the queue if DI21 is OFF.

## Duplicate DI21 Debounce Removed

Before interlayer motion, `src0.lua` no longer calls both:

```lua
SyncPartitionRemainBySensor(PalletNumber, true)
CheckPartitionRemainBeforeMotion(PalletNumber, CPoint)
```

`CheckPartitionRemainBeforeMotion()` already reads DI21, applies debounce, updates `RePartNum`, writes values, and blocks motion if needed. Keeping both calls caused duplicate debounce delay for one interlayer action.

## Periodic DI21 Check Removed

The periodic `src2.lua` check:

```lua
SyncPartitionRemainBySensor(PalletNumber, false)
```

was removed from normal state cycles because interlayers are used infrequently and only need validation at key moments.

## Modified Files

| File | Change |
|---|---|
| `global.lua` | Shared DI21 sensor helpers. |
| `src0.lua` | Startup sync, `Peek()` before `Pop()`, single DI21 check before interlayer motion. |
| `src2.lua` | ACK/reset sync before committing count; removes periodic DI21 polling. |

## Validation

1. Start with DI21 ON and saved `RePartNum = 0`. Expected: no false empty alarm.
2. Start with DI21 OFF. Expected: count becomes 0 but normal box logic can continue until interlayer is needed.
3. Run an interlayer action with DI21 OFF. Expected: alarm before motion and the action remains in queue.
4. Add interlayers and restart. Expected: the same interlayer action can still execute.
5. Confirm only one debounce happens before each interlayer action.

