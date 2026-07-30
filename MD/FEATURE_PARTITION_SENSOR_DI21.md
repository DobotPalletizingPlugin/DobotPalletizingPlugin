# Feature: DI21 Interlayer Sensor Logic

## Purpose

This feature makes the physical DI21 sensor the source of truth for interlayer availability.

It fixes cases where the saved software count says there are no interlayers while the real magazine sensor is ON.

## Core Rule

When interlayer sensor mode is enabled:

```text
DI21 ON  -> RePartNum = ProcessNum.PartitionNum
DI21 OFF -> RePartNum = 0
```

The remaining interlayer count is not decremented by action count after placing an interlayer. It is determined by the sensor.

## Configuration

The interlayer sensor is configured in `global.lua` through the project partition sensor configuration. DI21 is used only for the interlayer magazine / stock presence signal.

Do not confuse this DI21 stock sensor with the interlayer suction output. Interlayer suction is controlled by `PartCfg.Port`, which is configurable in the frontend and injected into `global.lua`; the current ERM site configuration uses DO16.

The shared helper is:

```lua
SyncPartitionRemainBySensor(PalletNumber, NeedWait)
```

This helper is defined once in `global.lua` and reused by `src0.lua` and `src2.lua`.

## Startup / ACK Synchronization

During startup, the sequence in `src0.lua` must synchronize DI21 before ACK / false shortage checks can read the stale saved value:

```lua
InitStorageMode()
InitModbus()
SyncAllPartitionRemainBySensor(true)
InitFSM()
```

This prevents a startup case like:

```text
DI21 = ON
saved RePartNum = 0
false alarm: Partition is empty!
```

## New Pallet / Reset Synchronization

In `src2.lua`, after new pallet / ACK / reset flow, the interlayer count is synchronized before:

```lua
CommitPalletNum()
```

This ensures HMI and Modbus values do not keep the old `0` when DI21 is actually ON.

## Before Interlayer Motion

Immediately before executing an interlayer motion, the script checks DI21 again:

```text
DI21 ON:
    RePartNum = ProcessNum.PartitionNum
    WritePartNum()
    allow interlayer motion

DI21 OFF:
    RePartNum = 0
    WritePartNum()
    block interlayer motion
```

## Intentional Optimization

The final version removes the periodic DI21 check from the normal `src2.lua` state cycle.

Reason:

- interlayers are used only every 8 to 10 cartons;
- the magazine usually contains around 20 to 30 sheets;
- periodic debounce during every normal box cycle slows the state thread unnecessarily;
- DI21 only needs to be checked at startup / ACK / reset and before interlayer motion.

## Modified Files

| File | Change |
|---|---|
| `global.lua` | Defines shared DI21 helper functions and sensor-mode checks. |
| `src0.lua` | Synchronizes DI21 during startup and before interlayer motion. |
| `src2.lua` | Synchronizes DI21 before committing pallet/reset values; removes periodic DI21 checks. |

## Validation

1. Start with saved `RePartNum = 0` and DI21 ON. Expected: no false `Partition is empty!`; count restores to default.
2. Start with DI21 OFF. Expected: count becomes 0, but the program only blocks when an interlayer action is required.
3. Before an interlayer action with DI21 OFF. Expected: alarm before motion and the action remains available for retry.
4. Before an interlayer action with DI21 ON. Expected: one DI21 debounce and normal motion.
5. Normal box cycles between interlayer actions. Expected: no periodic DI21 debounce slowdown.
