# ERM Vin Perret Project Documentation

This folder contains the maintained technical notes for the ERM Vin Perret palletizing customization.

本目录保存 ERM Vin Perret 项目的开发、调试和交接资料。

## Final Delivery Status

The final package is based on `2-4-2-stable-france`.

Final plugin files:

- `Palletizing_v2-4-2-stable-france/`
- `Palletizing_v2-4-2-stable-france.zip`

Project recipe:

- `BIB_2x10L-20260728100621.json`

Important correction:

- MovS was tested on site but was not usable.
- The final delivered version has been changed back to the non-MovS motion implementation.
- Current final motion documentation should refer to `SafeMovJ()`, `SafeMovL()`, J1/J6 normalization, separated transitions, and segmented motion logic.

## Feature Documents

| File | Scope | Current Status |
| --- | --- | --- |
| `FEATURE_BIB_CONVEYOR.md` | BIB conveyor logic: B1/B2 logical box, B3 anti-pushing, M1/M2 control. | Active |
| `FEATURE_PARTITION_SENSOR_DI21.md` | Interlayer magazine sensor logic through `PartSensorCfg`; default Lua sensor is DI21. | Active |
| `FEATURE_PARTITION_TRAJECTORY_SAFETY.md` | Interlayer trajectory, J1/J6 branch safety, transition behavior. | Active, but any MovS wording should be treated as historical context only |
| `apave.md` | APAVE requirements: dropped-box alarm and compressed-air presence check. | Active |

## Bugfix Documents

| File | Scope | Current Status |
| --- | --- | --- |
| `BUGFIX_J6_JOINT_LIMIT.md` | Fix for invalid equivalent J6 angles such as `-443 deg`. | Active |
| `BUGFIX_PARTITION_QUEUE_AND_SENSOR.md` | Queue `Peek()` before `Pop()`, DI21 timing, false empty alarm prevention. | Active |

## Coding Guide

| File | Scope |
| --- | --- |
| `COMMENT_STYLE_GUIDE.md` | Bilingual Lua comment style rules for this project. |

## Root-level Handover Documents

These files are part of the project handover and should be kept:

- `README.md`
- `CUSTOM_IO.md`
- `ERM项目总结.docx`
- `ERM_码垛项目功能与版本演进说明.docx`
- `CR30HT_力传碰撞误触问题修复总结.docx`
- `ERM_Pallet_ACK_Root_Cause_Summary.md`
- `BIB_2x10L-20260728100621.json`
- `Safety/`

## Final Script Package

Final Lua files:

- `global.lua`
- `src0.lua`
- `src1.lua`
- `src2.lua`
- `src3.lua`
- `src4.lua`
- `src5.lua`
- `src6.lua`
- `src7.lua`

Location:

```text
Palletizing_v2-4-2-stable-france/PalScript/Template/General/
```

## Maintenance Notes

- Do not delete the Word documents, Markdown notes, project JSON, or `Safety/` folder. They are not temporary files.
- `signal.interlayer = 16` in the project JSON is the interlayer suction/output signal.
- `PartCfg.Port` is the independent interlayer suction output configuration. It is configurable in the frontend and injected into `global.lua`; the current ERM site configuration uses DO16.
- `PartSensorCfg.Port.A = 21` in Lua is only the interlayer magazine / stock presence sensor.
- MovS is not the final implemented motion strategy.
- Before changing I/O, check the project JSON, Lua defaults, and the machine electrical drawing together.
