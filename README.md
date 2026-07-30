# ERM Vin Perret Palletizing Package

## 1. Project Scope

This branch contains the ERM / Vin Perret custom palletizing package based on `2-4-2-stable-france`.

本分支为 ERM / Vin Perret 终端项目定制版本，基于 `2-4-2-stable-france` 制作。

The final delivered plugin package is:

- `Palletizing_v2-4-2-stable-france/`
- `Palletizing_v2-4-2-stable-france.zip`

The project recipe file is:

- `BIB_2x10L-20260728100621.json`

Development and handover documents are kept in:

- `MD/`
- `ERM项目总结.docx`
- `ERM_码垛项目功能与版本演进说明.docx`
- `CR30HT_力传碰撞误触问题修复总结.docx`
- `ERM_Pallet_ACK_Root_Cause_Summary.md`

## 2. Final Package Status

The final `global.lua` and `src0.lua` to `src7.lua` are inside:

```text
Palletizing_v2-4-2-stable-france/PalScript/Template/General/
```

The zip package contains the same final Lua files and `Main/config.json`.

当前最终 Lua 代码已经放在 `Palletizing_v2-4-2-stable-france/PalScript/Template/General/` 中，zip 包内的对应文件与目录版本一致。

Note: MovS was tested on site but was not usable for the final delivery. The final package has been changed back to the non-MovS motion implementation, using the current `SafeMovJ()` / `SafeMovL()` wrappers and segmented motion logic.

注意：MovS 已在现场测试过，但最终不可用；交付版已经改回非 MovS 实现。最终说明以当前 `SafeMovJ()` / `SafeMovL()` 和分段运动逻辑为准。

## 3. Main Custom Features

### BIB Conveyor Logic

ERM BIB recipes treat two physical cartons as one logical pick unit.

- B1 and B2 must both be stable before robot pick authorization.
- B3 is used as upstream anti-pushing detection.
- M1 and M2 conveyor outputs are controlled only for whitelisted BIB recipes.

Relevant files:

- `global.lua`
- `src1.lua`
- `MD/FEATURE_BIB_CONVEYOR.md`

### Interlayer Sensor And Queue Protection

The interlayer magazine availability is controlled by a physical sensor through `PartSensorCfg`.

- Sensor ON restores the configured/default interlayer count.
- Sensor OFF sets remaining interlayer count to 0.
- Before interlayer motion, the queue is checked with `Peek()` first.
- The action is only removed with `Pop()` after the interlayer sensor check passes.
- DI21 is the stock / magazine detection input only; it is not the interlayer suction output.

This prevents the interlayer action from being lost when the magazine is empty.

Relevant files:

- `global.lua`
- `src0.lua`
- `src2.lua`
- `MD/FEATURE_PARTITION_SENSOR_DI21.md`
- `MD/BUGFIX_PARTITION_QUEUE_AND_SENSOR.md`

### Pallet ACK Fix

The pallet replacement state machine was fixed so that a full pallet cannot be cleared simply because the ACK latch was reset.

The corrected sequence requires:

1. Old pallet physically removed.
2. New pallet physically present.
3. Operator ACK accepted.

Relevant files:

- `src2.lua`
- `ERM_Pallet_ACK_Root_Cause_Summary.md`

### Interlayer Path And J1/J6 Safety

The ERM layout has long left-to-right movement between pick, interlayer, and pallet areas. The final code adds safety handling for:

- J1 safe branch selection.
- J6 software-limit-aware equivalent-angle selection.
- `SafeMovJ()` and `SafeMovL()` wrappers.
- Separate forward and backward interlayer transition points.
- Taught J6 preservation for interlayer pick and transition points.

Relevant files:

- `src0.lua`
- `src3.lua`
- `MD/FEATURE_PARTITION_TRAJECTORY_SAFETY.md`
- `MD/BUGFIX_J6_JOINT_LIMIT.md`

### Independent Interlayer Suction

The interlayer vacuum output is separated from the normal box sucker.

- Final code uses `PartCfg.Port` for interlayer pick and release.
- `PartCfg.Port` is configurable in the frontend and injected into `global.lua`.
- The current ERM site configuration uses DO16 for interlayer suction.
- DI21 remains the interlayer stock detection input and should not be treated as the suction output.

Relevant files:

- `global.lua`
- `src0.lua`
- `CUSTOM_IO.md`

### Payload Transition For Heavy Vacuum Picking

The CR30HT force-sensor false collision issue was addressed with:

- J4/J5 torque sensor zero calibration.
- Staged payload updates after vacuum ON.
- Delayed payload update after release/vacuum break.

The final code uses staged payload values in `OpenSucker()` and delayed release update in `CloseSucker()`.

Relevant files:

- `src0.lua`
- `CR30HT_力传碰撞误触问题修复总结.docx`

### Compressed-air Check

The APAVE requirement is implemented through `AirPressureCfg` and `CheckCompressedAirPresence()`.

- Default air presence input: DI22.
- If compressed air is missing, the project start / ACK flow is blocked.
- The alarm message is in French.

Relevant files:

- `global.lua`
- `src2.lua`
- `MD/apave.md`

## 4. Project Recipe Snapshot

From `BIB_2x10L-20260728100621.json`:

- Project name: `BIB_2x10L`
- Robot type: `CR30`
- Box count: `36`
- Layers: `3`
- Box size: `415 x 205 x 329 mm`
- Box weight: `21.5 kg`
- Pallet: `1200 x 800 x 145 mm`
- Interlayer enabled: yes
- Interlayer user frame: `5`
- Left pallet user: `8`
- Right pallet user: `7`
- Tool: `2`

## 5. Documentation Notes

The Word and Markdown files in this repository are part of the project handover material and should be kept with the branch.

Do not delete the root project JSON, `MD/`, `Safety/`, or Word documents. They document why the final code exists and are needed for maintenance and later review.

仓库中的 Word、Markdown、项目 JSON 和 Safety 文件夹都是项目开发与交付资料，不是临时文件。后续整理时应保留。
