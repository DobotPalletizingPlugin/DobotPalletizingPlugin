# Feature: Interlayer Trajectory And J1/J6 Safety

## Purpose

This feature adapts the standard palletizing trajectory for ERM's paper interlayer process and long left-to-right robot movements.

It focuses on:

- safer interlayer pick and place paths;
- separated forward/backward transition points;
- J1 safe branch control;
- J6 software-limit protection;
- avoiding unnecessary standby motion before interlayer actions.

## Background

The ERM site has:

- carton pick area on the left side;
- interlayer pick area on the left side;
- pallet placement area on the right side;
- long transitions that can trigger different J1/J6 inverse-kinematic branches;
- paper interlayers that need careful approach and release paths.

## J1 Safe Branch

`src0.lua` constrains J1 to a safe branch:

```lua
J1SafeMin = -60
J1SafeMax = 200
```

Example conversions:

```text
-210 deg -> 150 deg
-270 deg -> 90 deg
```

This avoids the arm choosing an equivalent angle that rotates toward the operator side.

## J6 Software-Limit Range

`src0.lua` constrains J6 equivalent-angle selection to:

```lua
J6SoftMin = -360
J6SoftMax = 360
```

The code no longer chooses only the mathematically nearest J6 angle. It must choose a valid equivalent angle inside the software limit.

## Safe Motion Wrappers

The script adds wrappers:

```lua
SafeMovJ(Point, Option, NormalizeJ6)
SafeMovL(Point, Option, NormalizeJ6)
```

Before motion, these wrappers normalize:

- J1 to the safe branch;
- J6 to a valid software-limit range;
- J6 nearest-equivalent behavior when requested.

## Forward / Backward Transition Separation

`src3.lua` provides separate transition point sets:

```text
MotionPoint[1..5]         = forward transition
BackwardMotionPoint[1..5] = backward transition
```

For interlayers:

- forward transition keeps the taught J6;
- backward transition uses a J6 aligned with standby / return direction.

This prevents one transition set from serving two incompatible wrist orientations.

## Taught J6 Preservation

`src3.lua` stores:

```lua
PartPickTeachJ6
PartTransTeachJ6
```

These values preserve the taught J6 for:

- interlayer pick point;
- interlayer forward transition points.

This avoids inverse kinematics rewriting the wrist branch and changing the real interlayer handling posture.

## Interlayer Pick Path

The interlayer pick path adds a 200 mm safe approach and lift:

```text
move above interlayer pick point by 200 mm
slow MovL down with AI stop condition
turn suction on
slow MovL lift by 200 mm
```

The downward pick uses:

```lua
stopcond = "AI(1) <= 0.5"
```

This helps adapt to interlayer stack-height variation and avoids pressing too deeply into the paper stack.

## Interlayer Place Path

Interlayer placement is simplified and made more careful:

```text
forward transition
direct MovL to interlayer place point
release suction
vertical lift by 100 mm
backward transition
PartSafePoint / standby / next box direction
```

The place point is raised by 10 mm in `src3.lua` to reduce compression and scraping of paper interlayers.

## Transition Motion Types

Final transition policy:

| Motion type | Direction | Command | cp | Reason |
|---|---|---:|---:|---|
| Normal box | forward | `SafeMovJ` | 0 | Non-process path; lowers wrist singularity/preprocessing risk. |
| Normal box | backward | `SafeMovJ` | 0 | Return path; lowers branch-switching risk. |
| Interlayer | forward | `SafeMovL` | 100 | Keeps taught process path and interlayer posture. |
| Interlayer | backward | `SafeMovL` | 0 | Exits the interlayer/pallet area predictably. |

Transition acceleration and speed are capped at 30.

## Normal Box Deposit Lift

After normal box placement, the script can lift by:

```lua
DepositLiftHeight = 250
```

This reduces interference with already placed boxes.

## Skip Useless Standby Before Interlayer

`PTPMotion()` receives `CQueue` so it can look ahead:

```lua
GetNextPartitionMotion(CQueue)
```

If the next action is an interlayer, the robot skips the normal box standby:

```text
box placed
backward transition
next interlayer safe point
interlayer action
```

This improves cycle time and avoids unnecessary J1/J6 branch reselection.

## Modified Files

| File | Change |
|---|---|
| `src0.lua` | Motion execution, SafeMovJ/SafeMovL, J1/J6 normalization, queue look-ahead, interlayer pick/place path. |
| `src3.lua` | Point calculation, taught J6 preservation, `BackwardMotionPoint`, `StandyMotionPoint`, interlayer Z adjustments. |
| `global.lua` | Project safety parameters such as `PartSafePoint`. |

## Validation

1. Run interlayer pick at low speed and confirm the 200 mm approach/lift path.
2. Confirm AI stop condition prevents pressing too deeply into the paper stack.
3. Confirm interlayer forward path keeps the taught posture.
4. Confirm interlayer backward exits safely and does not switch to an unsafe J1/J6 branch.
5. Confirm normal box to interlayer transition skips unnecessary standby.
6. Watch J1 and J6 during long left-right moves at low speed.
