# ERM Vin Perret Custom I/O

This file summarizes the project-specific I/O used by the final ERM Vin Perret package.

本文档记录 ERM Vin Perret 最终版本中需要重点关注的项目 I/O。

## Project Recipe

Source file:

```text
BIB_2x10L-20260728100621.json
```

## Main Project I/O

| Signal | Port | Direction | Purpose |
| --- | ---: | --- | --- |
| B1 | DI1 / DI16 in project recipe | Input | BIB first carton / first incoming signal |
| B2 | DI6 / DI18 in project recipe | Input | BIB second carton / second incoming signal |
| B3 | DI19 | Input | Upstream third-carton anti-pushing sensor |
| M1 | DO18 | Output | Upstream conveyor motor |
| M2 | DO19 | Output | Middle positioning conveyor motor |
| Interlayer stock sensor | DI21 in Lua `PartSensorCfg` | Input | Interlayer magazine / stock availability |
| Interlayer suction | `PartCfg.Port`, current project DO16 | Output | Independent interlayer vacuum output; configurable in frontend and injected into `global.lua` |
| Left pallet ready | DI3 / DI3 | Input | Left pallet presence, both software channels use same physical input |
| Right pallet ready | DI5 / DI5 | Input | Right pallet presence, both software channels use same physical input |
| Left pallet ACK | DI9 | Input | Operator ACK for left pallet |
| Right pallet ACK | DI10 | Input | Operator ACK for right pallet |
| Compressed air | DI22 | Input | Air-pressure presence check for APAVE requirement |
| Buzzer | DO21 | Output | Buzzer output in project recipe |

## Notes

- `PartSensorCfg.Port.A = 21` in Lua is only the interlayer stock / magazine sensor.
- Interlayer suction is controlled by `PartCfg.Port`, which comes from the frontend configuration injected into `global.lua`; the current ERM site configuration uses DO16.
- `signal.interlayer = 16` in the project JSON corresponds to the interlayer suction/output configuration, not the DI21 stock sensor.
- MovS was tested on site and is not part of the final delivered motion implementation.
- Always verify the project JSON, Lua defaults, and the real electrical drawing together before changing I/O.
