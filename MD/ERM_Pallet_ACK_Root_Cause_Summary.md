# ERM Pallet Replacement ACK Bug – Root Cause Summary

## 1. Issue Summary

The pallet could correctly reach the **Full** state, but after pallet replacement the system could clear the Full state and restart the next pallet cycle **without a new operator ACK**.

The issue was not caused by the ACK push button hardware. The ACK inputs are momentary signals:

- Left pallet ACK: configured through `FirstPallet.InPlaceOK`
- Right pallet ACK: configured through `SecondPallet.InPlaceOK`
- The input is ON only while the operator presses the button
- The input is normally OFF

The real problem was in the pallet replacement state logic inside `src2.lua`.

---

## 2. System Configuration

Each pallet side physically uses only one pallet-presence sensor, but the software structure contains two variables:

```lua
PalletNumber.InPlaceA
PalletNumber.InPlaceB
```

For this project, both variables are configured to the same physical input.

Example:

```lua
FirstPallet.InPlaceA = 3
FirstPallet.InPlaceB = 3
FirstPallet.InPlaceOK = 9

SecondPallet.InPlaceA = 5
SecondPallet.InPlaceB = 5
SecondPallet.InPlaceOK = 10
```

Therefore, this generic test is still valid:

```lua
local PalletPresent =
    (DI(PalletNumber.InPlaceA) == ON)
    and (DI(PalletNumber.InPlaceB) == ON)
```

When both variables point to the same DI, it is equivalent to checking that one physical sensor.

---

## 3. Root Cause

The original logic confused two different concepts:

1. **ACK/run permission state**
2. **Physical pallet presence state**

The variable:

```lua
PalletNumber.State.Replace
```

was used as if it meant that the old pallet had physically been removed.

However, when a pallet becomes full, the ACK latch is intentionally cleared:

```lua
PalletNumber.State.InPlaceOK = false
PalletNumber.State.Replace = false
```

This only means that the next pallet must receive a new ACK. It does **not** mean that the old pallet has already been removed.

The original `CheckPallet()` logic contained this condition:

```lua
if (PalletNumber.State.Done == true)
    and (PalletNumber.State.Replace == false) then
    PalletNumber.State.FReset = true
end
```

As soon as the pallet became Full:

```lua
Done = true
Replace = false
```

The program immediately set:

```lua
FReset = true
```

This incorrectly interpreted "ACK cleared" as "old pallet removed".

---

## 4. Why the Full State Was Cleared Automatically

After `FReset` became true, the next condition checked whether the pallet sensor was ON:

```lua
if (PalletNumber.State.FReset == true)
    and (DI(PalletNumber.InPlaceA) == ON)
    and (DI(PalletNumber.InPlaceB) == ON) then
    PalletNumber.State.SReset = true
end
```

At that moment, the old full pallet could still be physically present, so the pallet sensor remained ON.

The program then immediately set:

```lua
SReset = true
```

The following block initialized the next pallet cycle without checking for a new ACK:

```lua
if (PalletNumber.State.SReset == true) then
    InitWorkingData(PalletNumber)
    PalletNumber.State.Done = false
end
```

Because there was no condition requiring:

```lua
PalletNumber.State.InPlaceOK == true
and PalletNumber.State.Replace == true
```

`InitWorkingData()` ran automatically and cleared the Full state.

---

## 5. Original Faulty Sequence

```text
Pallet becomes Full
    ↓
Done = true
    ↓
ACK latch is cleared
    ↓
InPlaceOK = false
Replace = false
    ↓
Original src2 logic interprets Replace = false as pallet removed
    ↓
FReset = true
    ↓
Old pallet is still present, so pallet sensor is still ON
    ↓
SReset = true
    ↓
InitWorkingData() runs without a new ACK
    ↓
Done = false
    ↓
Full state disappears and the next pallet cycle is prepared
```

---

## 6. Corrected Logic

The corrected logic separates the three required events:

1. Old pallet physically removed
2. New pallet physically present
3. Operator ACK accepted

### 6.1 Detect real pallet removal

The first reset stage must be triggered by the actual pallet sensor becoming OFF, not by `Replace == false`.

```lua
local PalletRemoved =
    (DI(PalletNumber.InPlaceA) == OFF)
    or (DI(PalletNumber.InPlaceB) == OFF)

if (PalletNumber.State.Done == true)
    and (PalletNumber.State.FReset == false)
    and (PalletRemoved == true) then
    PalletNumber.State.FReset = true
    PalletNumber.State.InPlaceOK = false
end
```

Because A and B may point to the same physical DI, this still works correctly.

### 6.2 Detect new pallet arrival

The new pallet arrival only sets the second reset flag:

```lua
local PalletPresent =
    (DI(PalletNumber.InPlaceA) == ON)
    and (DI(PalletNumber.InPlaceB) == ON)

if (PalletNumber.State.FReset == true)
    and (PalletPresent == true) then
    PalletNumber.State.SReset = true
end
```

At this stage, the pallet remains Full:

```lua
Done = true
Status = StateType.Stop
```

No working data is reset yet.

### 6.3 Require a new ACK before initialization

The next pallet cycle is initialized only after the configured ACK logic accepts the new pallet:

```lua
if (PalletNumber.State.SReset == true)
    and (PalletNumber.State.InPlaceOK == true)
    and (PalletNumber.State.Replace == true) then

    InitWorkingData(PalletNumber)

    PalletNumber.State.Done = false
    PalletNumber.State.FReset = false
    PalletNumber.State.SReset = false
end
```

The ACK input itself is not hard-coded. It is read through:

```lua
PalletNumber.InPlaceOK
```

This preserves the plugin configuration and allows the DI mapping to be changed without editing `src2.lua`.

---

## 7. Correct Sequence After the Fix

```text
Pallet becomes Full
    ↓
Done = true
Status = Stop
ACK latch is cleared
    ↓
Wait for real pallet sensor OFF
    ↓
FReset = true
    ↓
Wait for pallet sensor ON again
    ↓
SReset = true
    ↓
Keep Done = true and keep Full state
    ↓
Wait for the operator to press the configured ACK input
    ↓
InPlaceOK = true
Replace = true
    ↓
Run InitWorkingData()
    ↓
Done = false
    ↓
Start the next pallet cycle
```

---

## 8. Final Root Cause Statement

The root cause was that the original pallet replacement state machine used:

```lua
Replace == false
```

as proof that the old pallet had been physically removed.

In reality, `Replace` is an ACK/run-permission state. It is intentionally cleared when the pallet becomes Full. This caused the state machine to enter the replacement sequence immediately, detect the still-present full pallet as a "new pallet", and execute `InitWorkingData()` without waiting for a new ACK.

The fix was to:

- Use the configured pallet-presence inputs to detect real removal and arrival
- Keep the Full state after the new pallet arrives
- Require both `InPlaceOK == true` and `Replace == true` before initializing the next pallet
- Continue using configuration variables instead of hard-coded DI numbers

---

## 9. Scope of the Change

Only the pallet replacement logic in `src2.lua` was modified.

The following behavior was intentionally left unchanged:

- Startup data recovery
- Full-state recovery after restart
- Box counting
- Layer counting
- Partition handling
- Pallet configuration
- ACK input mapping
- Other source files
