# Stevial Double-Pick Single-Place Change Log

本文档记录 `custom242/stevial_double-pick-single-place_index-height-fix` 分支的整理依据、修改内容和验证结果。

## Branch Purpose

本分支用于 Stevial / Volkach 酒庄项目的 2.4.2 定制版本。

目标：

- 修复前端 Debug 菜单中速度参数没有从项目数据恢复的问题。
- 修正双取单放场景的放置后抬升高度，降低剩余箱体或夹具刮碰已放置箱体的风险。
- 保留对应的最终 zip 打包产物。

## Base Branch

本分支基于：

```text
origin/custom242/微调stevial德国volkach酒庄
```

原分支已有修改：

- 双吸 / 双取单放速度使用带料箱速度。
- `Main/config.json`、`General/src0.lua`、`General/src3.lua` 已相对 France 2.4.2 基线做过项目定制。

## Source Files Used

本次整理参考用户拷贝进来的本地来源目录：

```text
修改的东西/
```

最终采用的来源文件：

```text
修改的东西/Palletizing_v2-4-2-stable-france（修正index）.zip
修改的东西/index.html
修改的东西/config.json
修改的东西/src0.lua
```

未采用为最终依据的中间文件：

```text
修改的东西/frontend/
修改的东西/General/src0.lua
```

原因：

- `修改的东西/index.html` 和 `修正index` zip 内的 `Main/index.html` 一致，并且包含 Debug 速度参数恢复补丁。
- `修改的东西/frontend/index.html` 未包含该补丁，更像中间调试文件。
- `修改的东西/src0.lua` 与 `修正index` zip 内的 `General/src0.lua` 一致。
- `修改的东西/General/src0.lua` 与最终 zip 内 `src0.lua` 不一致，不作为最终来源。

## Changed Files

本分支提交的文件：

```text
Palletizing_v2-4-2-stable-france/Main/index.html
Palletizing_v2-4-2-stable-france/Main/config.json
Palletizing_v2-4-2-stable-france/PalScript/Template/General/src0.lua
Palletizing_v2-4-2-stable-france.zip
```

## Frontend Change

文件：

```text
Palletizing_v2-4-2-stable-france/Main/index.html
```

问题：

DebugPanel 打开时，已有逻辑会从 `currentDebugState` 恢复 advanced、height compensation、safety point、move restrict 和 extra 参数，但没有恢复项目中保存的 motion / speed 参数。

修正逻辑：

在 DebugPanel 初始化 `useEffect` 中恢复当前项目的 motion 参数：

```javascript
if (projects[currentOpenProjectIndex] &&
    projects[currentOpenProjectIndex].motion) {
    setMotionParams(
        lodash_default().cloneDeep(
            projects[currentOpenProjectIndex].motion
        )
    );
}
```

效果：

- 打开 Debug 菜单后，项目内保存的速度参数可以恢复到前端状态。
- 避免调试页面显示默认速度或旧速度，导致保存/调试时覆盖真实项目速度。

## Config Change

文件：

```text
Palletizing_v2-4-2-stable-france/Main/config.json
```

修改：

```diff
- "description": "06 May - MovL backward"
+ "description": "debug menu fix"
```

用途：

- 标记当前包包含 Debug 菜单速度恢复修复。

## Lua Change

文件：

```text
Palletizing_v2-4-2-stable-france/PalScript/Template/General/src0.lua
```

问题：

双取单放时，机器人放下当前箱子后，夹具上可能还带着后续箱子。旧逻辑使用固定 `250 mm` 放置后抬升高度，在高箱体或现场堆垛空间紧张时，存在剩余箱体或夹具横移刮碰已放置箱体的风险。

修正逻辑：

放置后抬升高度从固定值改为箱高相关：

```lua
local DepositLiftHeight = math.max(
    350,
    PalletNumber.BoxProperty.BoxHigh
)
```

同时增加日志：

```lua
LogInfo(
    "DepositLiftHeight=%s mm, BoxHigh=%s mm",
    tostring(DepositLiftHeight),
    tostring(PalletNumber.BoxProperty.BoxHigh)
)
```

效果：

- 最小放置后抬升高度为 `350 mm`。
- 如果箱体高度大于 `350 mm`，使用实际箱高作为抬升高度。
- 更适合双取单放场景，避免带着第二个箱子横移时刮碰第一箱。

## Zip Package

最终打包产物：

```text
Palletizing_v2-4-2-stable-france.zip
```

来源：

```text
修改的东西/Palletizing_v2-4-2-stable-france（修正index）.zip
```

验证结果：

zip 内关键文件与目录文件一致：

```text
SAME Main/index.html
SAME Main/config.json
SAME General/src0.lua
SAME General/global.lua
SAME General/src1.lua
SAME General/src3.lua
```

## Temporary Source Directory

当前本地仍保留未跟踪目录：

```text
修改的东西/
```

用途：

- 作为用户拷贝进来的原始来源和核对资料。

建议：

- 在确认远端分支和 zip 包无误后，可以删除该本地临时目录。
- 不建议提交该目录，因为其中包含中间文件、重复 zip、临时清理脚本和未采用版本。

## Final Branch

最终分支：

```text
custom242/stevial_double-pick-single-place_index-height-fix
```

当前提交：

```text
4d09167 Fix Stevial debug motion restore and lift height
```
