# Unista Custom I/O

本文档只记录 Unista 版本里特殊定制使用的 I/O。  
This document only lists the I/O customized specifically for the Unista version.

## Custom I/O Table

| I/O | Direction | Usage | Code |
| --- | --- | --- | --- |
| DI16 | Input | 隔板库存检测 / Interlayer stock detection | `DI(16)` |
| DI17 | Input | 隔板取料停止条件 1 / Interlayer pick stop sensor 1 | `DI(17)` |
| DI18 | Input | 隔板取料停止条件 2 / Interlayer pick stop sensor 2 | `DI(18)` |

## DI16 - Interlayer Stock

`DI16` 用于判断隔板料仓是否还有隔板。

```lua
if (DI(16) == 0) then
    PalletNumber.Partition.RePartNum = 0
else
    PalletNumber.Partition.RePartNum = 2
end
```

- `DI16 = 0`: 隔板为空 / interlayer empty
- `DI16 = 1`: 隔板可用 / interlayer available

## DI17 + DI18 - Interlayer Pick Stop Condition

`DI17` 和 `DI18` 用于隔板取料下探时的停止条件。

```lua
PartPickStopCond = "(DI(17) == 1) and (DI(18) == 1)"
```

只有两个信号同时为 1，机器人取隔板下探动作才会提前停止。

The interlayer pick approach stops early only when both signals are 1.

## Notes

- 其他 I/O，例如吸盘、三色灯、蜂鸣器、托盘到位、安全 I/O，属于原插件通用配置，不算 Unista 特殊定制 I/O。
- 调试隔板功能时，优先检查 `DI16`、`DI17`、`DI18` 的实时状态。
