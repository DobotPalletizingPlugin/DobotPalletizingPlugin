# Feature: BIB Conveyor Control

## Purpose

This feature adds a project-specific conveyor logic for ERM BIB products without changing the standard palletizing behavior for other projects.

For the targeted BIB projects, two physical cartons are treated as one logical box by the palletizing script:

```text
B1 + B2 stable = 1 logical box ready
```

## Enabled Projects

The logic is enabled only when both conditions are true:

```lua
BIBConveyorCfg.Enable == true
```

and `PalletName` exactly matches one of:

```lua
PalletName == "BIB_2x10L"
or PalletName == "BIB_6x3L"
or PalletName == "BIB_2X5L"
```

Do not replace this whitelist with a fuzzy check such as `string.find(PalletName, "BIB")`.

## I/O Mapping

| Name | Port | Role |
|---|---:|---|
| B1 | DI1 | First carton at pick position |
| B2 | DI6 | Second carton at pick position |
| B3 | DI19 | Third upstream carton, used for anti-pushing |
| M1 | DO18 | Upstream conveyor |
| M2 | DO19 | Middle positioning conveyor |

The configuration is defined in `global.lua`:

```lua
BIBConveyorCfg =
{
    Enable = true,
    DelayTime = 1000,

    Sensor =
    {
        B1 = { Mode = 0, A = 1 },
        B2 = { Mode = 0, A = 6 },
        B3 = { Mode = 0, A = 19 }
    },

    Motor =
    {
        M1 = { Mode = 0, A = 18 },
        M2 = { Mode = 0, A = 19 }
    }
}
```

## Robot Pick Authorization

Robot pick is authorized only when:

```text
B1 = ON
B2 = ON
stable for 1000 ms
```

Then the script stops M2 and calls the normal palletizing signal authorization:

```text
M2 = OFF
GetSignal(PalletNumber)
SignalReady = true
MotionDone = false
```

The 1000 ms stable timing uses `Systime()` instead of thread-cycle accumulation, so it does not depend on the real execution period of the Lua thread.

The BIB stable timer is intentionally not cleared immediately after `SignalReady`, because B1/B2 can already be stable while the robot is palletizing. This avoids forcing another 1000 ms wait when the robot returns.

## M1 / B3 Anti-Pushing Logic

B3 does not authorize robot picking. Its only role is to prevent the upstream carton from pushing into B1/B2 when the pick positions are already full.

Final logic:

```text
if B1 = ON and B2 = ON and B3 = ON:
    M1 = OFF
else:
    M1 = ON
```

Meaning:

| B1 | B2 | B3 | M1 | Reason |
|---:|---:|---:|---:|---|
| 0 | 0 | 1 | ON | B3 carton can continue toward B2/B1 |
| 1 | 0 | 1 | ON | One pick position is still empty |
| 0 | 1 | 1 | ON | One pick position is still empty |
| 1 | 1 | 1 | OFF | Pick position is full, stop upstream pushing |

## M2 Positioning Logic

M2 moves cartons toward B1/B2 and stays active until both pick positions are stable:

```text
if B1 != ON or B2 != ON:
    M2 = ON

if B1 = ON and B2 = ON stable for 1000 ms:
    M2 = OFF
```

## Modified Files

| File | Change |
|---|---|
| `global.lua` | Adds `BIBConveyorCfg`. |
| `src1.lua` | Adds BIB-specific detection and conveyor control before the standard `GetDeteMode()` logic. |

The BIB conveyor feature does not modify `src0.lua`, `src2.lua`, `src3.lua`, or `src4.lua`.

## Non-BIB Behavior

If the project name is not in the whitelist, this logic does not control M1/M2 and the script returns to the original plugin detection flow.

Standard project behavior remains:

- single-box projects use the original `BoxBeInpPlaceDI1` detection and debounce;
- multi-sucker or multi-box projects use the original multi-sensor detection flow;
- BIB-specific M1/M2 control is not executed.

## Validation

1. Confirm `B1 + B2` stable for 1000 ms stops M2 and authorizes robot pick.
2. Confirm `B1 + B2 + B3` stops M1.
3. Confirm B3 alone does not stop M1.
4. Confirm non-whitelisted projects still use standard detection and do not control DO18 / DO19.

