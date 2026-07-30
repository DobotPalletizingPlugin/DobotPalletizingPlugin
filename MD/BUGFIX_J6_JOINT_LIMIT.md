# Bugfix: J6 Joint-Limit Fault

## Symptom

During testing, the controller reported:

```text
Preprocessing point exceeds joint limit
```

The target point included an invalid J6 value:

```text
J6 = -443.67 deg
```

## Root Cause

The previous J6 normalization selected the mathematically nearest equivalent angle relative to the current J6.

Example:

```text
current J6 = -329 deg
target raw J6 = -83 deg
nearest equivalent = -443 deg
```

`-443 deg` is mathematically equivalent to `-83 deg`, but it exceeds the J6 software limit.

## Fix

`src0.lua` now constrains J6 equivalent-angle selection to:

```lua
J6SoftMin = -360
J6SoftMax = 360
```

The normalization now chooses a legal equivalent angle inside this range. If the nearest equivalent angle is illegal, the code falls back to a valid equivalent such as:

```text
target raw J6 = -83 deg
nearest equivalent = -443 deg  invalid
selected equivalent = -83 deg  valid
```

## Related Safety Changes

This bugfix works together with:

- `SafeMovJ()` and `SafeMovL()` wrappers;
- J1 safe branch `-60 deg` to `200 deg`;
- separate interlayer forward/backward transition J6;
- normal box transition singularity protection in `src3.lua`;
- transition speed and acceleration caps.

## Modified Files

| File | Change |
|---|---|
| `src0.lua` | Adds J6 software-limit-aware normalization and safe motion wrappers. |
| `src3.lua` | Avoids forcing normal-box transition J6 near J5 singularity; separates interlayer forward/backward J6. |

## Validation

1. Reproduce the previous path at low speed.
2. Confirm no target J6 is generated outside `-360 deg` to `360 deg`.
3. Confirm the controller no longer reports `Preprocessing point exceeds joint limit`.
4. Confirm J6 does not make unnecessary full-circle rotations after interlayer placement.

