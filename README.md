# Unista Custom Version README

## 1. 版本概览 / Version Overview

本分支为 Unista 项目的 2.4.2 定制版本，主要基于标准 `Palletizing_v2-4-2-stable` 代码进行现场适配。改动重点集中在 `Palletizing_v2-4-2-stable/PalScript/Template/General` 目录下的 Lua 运动与点位逻辑，尤其是隔板取放、吸盘控制、多吸单放、掉箱检测、双托盘切换以及 Tool / J6 姿态稳定性。

This branch is a Unista-specific custom version based on the standard `Palletizing_v2-4-2-stable` code. The main changes are concentrated in the Lua motion and point-calculation logic under `Palletizing_v2-4-2-stable/PalScript/Template/General`, especially around interlayer handling, vacuum sucker control, multi-pick single-place behavior, box drop detection, dual-pallet switching, and Tool / J6 orientation stability.

The relevant Lua files are:

- `global.lua`
- `src0.lua`
- `src1.lua`
- `src2.lua`
- `src3.lua`

`src4.lua` to `src7.lua` do not contain business-logic changes for this customization.

## 2. 隔板功能 / Interlayer Function

### 2.1 隔板取料路径 / Interlayer Pick Path

隔板取料动作不再直接按照原始抓取点下探。当前版本会先基于 `PartPick` 计算一个预取点 `PrePickPart`，并在隔板用户坐标系中沿 Z 方向上抬 300 mm，再转换回基坐标执行运动。

这样做的目的是让机器人先到达隔板堆上方的安全位置，再慢速接近隔板，减少夹具从侧面或斜向接近时碰撞隔板堆、隔板料仓或周边结构的风险。

The interlayer pick motion no longer moves directly to the original pick point. The current version calculates a pre-pick point `PrePickPart` from `PartPick`, raises it by 300 mm along the interlayer user-frame Z direction, and then transforms it back before executing the motion.

This allows the robot to approach the interlayer stack from a safer position above the stack, reducing the risk of collision with the interlayer stock, magazine, or surrounding structure.

### 2.2 隔板慢速下探和停止条件 / Slow Interlayer Approach And Stop Condition

隔板取料时新增慢速接近参数：

- `PartPickAcc = 5`
- `PartPickSpeed = 50`

机器人从预取点移动到隔板取料点时使用 `MovL`，并带有停止条件：

```lua
PartPickStopCond = "(DI(17) == 1) and (DI(18) == 1)"
```

这表示隔板取料过程中会根据 `DI(17)` 和 `DI(18)` 判断是否已经接触或检测到隔板。一旦满足条件，运动可以提前停止，避免继续下压隔板堆。

During interlayer picking, slow approach parameters are added:

- `PartPickAcc = 5`
- `PartPickSpeed = 50`

The robot moves from the pre-pick point to the interlayer pick point using `MovL` with the following stop condition:

```lua
PartPickStopCond = "(DI(17) == 1) and (DI(18) == 1)"
```

This means the robot uses `DI(17)` and `DI(18)` to detect whether the interlayer has been reached. Once the condition is satisfied, the motion can stop early to avoid pressing further into the interlayer stack.

### 2.3 隔板剥离动作 / Interlayer Peel Motion

吸取隔板后，当前版本不会简单地垂直返回原上方点，而是基于当前位姿 `GetPose()` 生成一个 `PartPeelPoint`。该点在隔板用户坐标系中增加以下偏移：

- X 方向：`-50`
- Y 方向：`-15`
- Z 方向：`+250`

随后机器人以慢速 `MovL` 移动到该剥离点。这个动作的目的，是帮助夹具从隔板堆中剥离单张隔板，降低一次吸起多张隔板或隔板粘连的概率。

After the interlayer is picked, the current version does not simply return vertically to the original upper point. Instead, it creates a `PartPeelPoint` from the current pose returned by `GetPose()`. In the interlayer user frame, the following offsets are applied:

- X direction: `-50`
- Y direction: `-15`
- Z direction: `+250`

The robot then moves to this peel point with a slow `MovL`. The purpose is to help separate one interlayer sheet from the stack and reduce the chance of picking multiple sheets or carrying stuck interlayers.

### 2.4 隔板余量检测 / Interlayer Stock Detection

`UpdatePartData()` 中的隔板余量逻辑被改为通过 `DI(16)` 判断现场隔板库存状态：

```lua
if (DI(16) == 0) then
    PalletNumber.Partition.RePartNum = 0
else
    PalletNumber.Partition.RePartNum = 2
end
```

当 `DI(16)` 表示没有隔板时，系统会将剩余隔板数量置为 0，并触发 `Partition is empty!` 报警。仿真模式下仍保持不报警的逻辑。

The interlayer stock logic in `UpdatePartData()` now uses `DI(16)` to determine whether interlayers are available:

```lua
if (DI(16) == 0) then
    PalletNumber.Partition.RePartNum = 0
else
    PalletNumber.Partition.RePartNum = 2
end
```

When `DI(16)` indicates that no interlayer is available, the remaining interlayer count is set to 0 and the system raises `Partition is empty!`. In simulation mode, the no-alarm behavior is preserved.

### 2.5 隔板放置高度补偿 / Interlayer Place Height Compensation

在 `src3.lua` 的点位计算中，隔板放置点会额外抬高 10 mm：

```lua
if (Res.Mode == MotionType.Part) then
    PlacePose.pose[3] = PlacePose.pose[3] + 10
end
```

该补偿用于避免隔板放置时下压过深，降低隔板被压弯、刮动或与已码放箱体干涉的风险。

In `src3.lua`, the calculated interlayer place point is raised by 10 mm:

```lua
if (Res.Mode == MotionType.Part) then
    PlacePose.pose[3] = PlacePose.pose[3] + 10
end
```

This compensation prevents the interlayer from being pressed too deeply during placement, reducing the risk of bending, dragging, or interfering with already placed boxes.

## 3. 运动策略 / Motion Strategy

### 3.1 待机运动改为直线运动 / Standby Motion Changed To Linear Motion

部分待机运动由 `MovJ` 改为 `MovL`。注释中说明该修改用于避免机器人回待机点时碰到隔板库存区域。

这类修改主要影响 `StandyMotion()`：

- 有升降轴高度调整时，先 `MovL` 到待机点，再调整升降高度。
- 根据层高偏移后的待机点，也使用 `MovL`。

Some standby motions are changed from `MovJ` to `MovL`. The code comments indicate that this is intended to avoid hitting the interlayer stock area while moving back to standby.

This mainly affects `StandyMotion()`:

- When lifting-height adjustment is required, the robot first moves linearly to the standby point and then adjusts the lifting height.
- The layer-height-adjusted standby point is also reached with `MovL`.

### 3.2 隔板吸附状态下低速通过 / Slow Motion While Carrying Interlayer

在 `TransMotion()` 和放置前路径中，如果当前动作是隔板模式，并且吸盘处于吸附状态：

```lua
(CPoint.Paras.Mode == MotionType.Part) and (GetToolDO(1) == ON)
```

机器人会使用较低速度通过过渡点或放置上方点。例如过渡点速度可能降到 `v = 10`，放置上方点速度可能降到 `v = 5`。

这可以减少隔板在移动过程中抖动、滑移或与周边结构发生干涉。

In `TransMotion()` and the pre-place path, when the current motion is interlayer mode and the vacuum output indicates that the interlayer is being held:

```lua
(CPoint.Paras.Mode == MotionType.Part) and (GetToolDO(1) == ON)
```

the robot moves through transition or above-place points at reduced speed. For example, transition speed can be reduced to `v = 10`, and above-place speed can be reduced to `v = 5`.

This helps reduce shaking, slipping, or interference while carrying an interlayer.

### 3.3 多吸单放后的额外抬升 / Extra Lift After Multi-pick Single-place

当前版本新增 `DepositLiftHeight = 250`。当一次吸取多个箱子、但逐个放置时，如果当前放置的不是最后一个箱子，机器人会：

1. 回到当前放置点上方。
2. 基于当前关节正解得到当前用户坐标系下的位姿。
3. 沿 Z 方向额外抬高 250 mm。
4. 再执行到下一个放置点的横向移动。

这样可以避免夹具和机器人上剩余箱子在横向移动时刮碰已经放好的箱子。

The current version adds `DepositLiftHeight = 250`. When multiple boxes are picked but placed one by one, and the current box is not the last one, the robot:

1. Returns to the above-place point of the current box.
2. Calculates the current pose from the current joint position.
3. Raises the pose by 250 mm along the user-frame Z direction.
4. Moves laterally toward the next place point.

This reduces the risk that the gripper or the remaining boxes collide with boxes that have already been placed.

### 3.4 回程 J6 保持 / J6 Preservation On Return Path

在部分回程过渡点运动中，当前版本会读取当前关节角：

```lua
local CurrentJoint = GetAngle().joint
```

然后将目标点的 `joint[6]` 改为当前 J6，再执行 `MovJ`。这样可以减少回程过程中第六轴突然选择另一组等效角度，降低翻腕、绕腕或触发关节限位的风险。

For some backward transition motions, the current version reads the current joint angle:

```lua
local CurrentJoint = GetAngle().joint
```

It then replaces the target point's `joint[6]` with the current J6 before executing `MovJ`. This reduces the chance that the sixth axis suddenly switches to another equivalent solution during return motion, lowering the risk of wrist flipping or joint-limit errors.

## 4. 点位与姿态计算 / Point And Orientation Calculation

### 4.1 隔板示教 Pose 优先 / Taught Pose Priority For Interlayers

隔板放置点和隔板过渡点现在优先使用示教保存的 `pose`。如果示教 `pose` 有效，系统不会优先用 `joint + current tool` 重新正解。

这样做是因为现场发现：当 Tool RZ 为 90 度时，用 joint 结合当前 Tool 做正解，可能导致隔板姿态相对示教保存姿态偏约 90 度。

For interlayer place and transition points, the system now prioritizes the taught saved `pose`. If the taught `pose` is valid, the system does not primarily recalculate the pose from `joint + current tool`.

This is because on site it was observed that when Tool RZ is 90 degrees, recalculating from joint data with the current Tool can produce an orientation approximately 90 degrees away from the taught pose.

### 4.2 隔板取料点 J6 保持 / Preserving Taught J6 For Interlayer Pick

当前版本保存隔板取料示教点的第六轴：

```lua
CData.PartPickTeachJ6 = PartPickJoint.joint[6]
```

在最终生成 `MotionPoint[6]` 时，会把该示教 J6 写回。这用于避免逆解在同一 TCP 位姿下选择另一组第六轴角度。

The current version stores the taught sixth-axis value of the interlayer pick point:

```lua
CData.PartPickTeachJ6 = PartPickJoint.joint[6]
```

When `MotionPoint[6]` is generated, this taught J6 is written back. This avoids inverse kinematics selecting another sixth-axis solution for the same TCP pose.

### 4.3 隔板回程点独立计算 / Dedicated Backward Transition Points

`src3.lua` 中新增 `BackwardMotionPoint`。隔板模式下，回程过渡点会复制正常 `MotionPoint` 的 J1 到 J5，但 J6 会统一调整为待机终点的 J6。

这样可以让去程和回程使用不同的 J6 策略：去程尽量尊重示教隔板点，回程尽量贴近最终待机点的关节分支。

`BackwardMotionPoint` is added in `src3.lua`. In interlayer mode, backward transition points copy J1 to J5 from the normal `MotionPoint`, while J6 is adjusted to match the final standby point's J6.

This allows different J6 strategies for forward and backward paths: the forward path respects the taught interlayer points, while the backward path stays closer to the final standby joint branch.

### 4.4 普通箱过渡点奇异保护 / Singularity Protection For Normal Box Transition Points

普通箱子的过渡点原逻辑会把部分过渡点 J6 强制改成放置点 J6。当前版本增加判断：如果 J5 接近 ±90 度，则不强行修改 J6。

该逻辑用于避免在腕部奇异附近制造另一组关节分支，减少“点位预处理超过关节限位”或类似关节异常。

The original logic for normal boxes forced some transition-point J6 values to match the place-point J6. The current version adds a condition: if J5 is close to ±90 degrees, J6 is not forcibly overwritten.

This avoids creating another joint branch near wrist singularity and reduces the risk of joint-limit or point-preprocessing errors.

### 4.5 隔板自动过渡点高度 / Auto-generated Interlayer Transition Height

当使用自动生成隔板过渡点时，当前版本将其固定为放置点上方 100 mm：

```lua
TPoint.pose[3] = Point.Pose[8][3] + 100
```

这避免沿用过高或不适合当前隔板动作的过渡点 Z 值。

When using auto-generated interlayer transition points, the current version fixes the transition height at 100 mm above the place point:

```lua
TPoint.pose[3] = Point.Pose[8][3] + 100
```

This avoids using transition Z values that are too high or unsuitable for the current interlayer motion.

## 5. 吸盘功能 / Vacuum Sucker Function

### 5.1 吸盘 DO 状态校验 / Vacuum DO Verification

当前版本新增 `VerifySuckerDO()`，用于在打开吸盘后检查对应 DO 是否达到期望状态：

```lua
local ActualState = CheckDORes(PortCfg.Mode, DOIndex)
if (ActualState ~= ExpectedState) then
    Alarm("Sucker DO" .. tostring(DOIndex) .. " state mismatch!", ErrorMessage.Type.WorkingDataErr)
end
```

在打开吸盘后，程序会等待 1000 ms，然后检查 A/B/C/D 中实际使用的吸盘输出。如果输出状态不符合预期，会触发报警。

The current version adds `VerifySuckerDO()` to verify whether the corresponding DO reaches the expected state after the vacuum sucker is enabled:

```lua
local ActualState = CheckDORes(PortCfg.Mode, DOIndex)
if (ActualState ~= ExpectedState) then
    Alarm("Sucker DO" .. tostring(DOIndex) .. " state mismatch!", ErrorMessage.Type.WorkingDataErr)
end
```

After enabling the vacuum, the program waits 1000 ms and then checks the actually used A/B/C/D vacuum outputs. If the output state does not match the expected state, an alarm is raised.

### 5.2 多吸模式按实际数量控制 / Multi-sucker Control By Actual Box Count

多吸模式下，程序会根据当前动作实际需要的箱数 `BoxNum` 控制和检查对应数量的吸盘。对于单个放置动作，也会根据 `CIndex` 分别控制 A/B/C/D。

这可以避免多吸单放过程中吸盘状态和实际剩余箱数不一致。

In multi-sucker mode, the program controls and verifies vacuum outputs according to the actual required box count `BoxNum`. For single-place steps, it also controls A/B/C/D according to `CIndex`.

This helps avoid inconsistencies between vacuum output state and the actual remaining boxes during multi-pick single-place operations.

### 5.3 偏心工具与动态负载 / Eccentric Tool And Dynamic Payload

当前版本新增 `CalcEccTool()`，用于根据吸盘模式、实际吸取或剩余箱数计算偏心工具位置。随后 `SetPayload()` 会使用该工具位置和实际重量更新机器人负载。

打开吸盘后，负载会按吸取箱数计算：

```lua
BoxNum * PalletNumber.BoxProperty.BoxWeight + ToolWeight
```

关闭吸盘后，负载会按剩余箱数计算：

```lua
(PalletSuckerFunction - CIndex) * PalletNumber.BoxProperty.BoxWeight + ToolWeight
```

这对双吸、多吸、单放场景尤其重要，因为机器人末端负载和重心会随着每次放箱发生变化。

The current version adds `CalcEccTool()` to calculate the eccentric tool position based on sucker mode and the actual picked or remaining box count. `SetPayload()` then updates the robot payload using the calculated tool position and actual weight.

After opening the vacuum, the payload is calculated based on picked box count:

```lua
BoxNum * PalletNumber.BoxProperty.BoxWeight + ToolWeight
```

After closing the vacuum, the payload is calculated based on remaining box count:

```lua
(PalletSuckerFunction - CIndex) * PalletNumber.BoxProperty.BoxWeight + ToolWeight
```

This is especially important for double-sucker, multi-sucker, and single-place scenarios, because the end-effector load and center of gravity change after each placed box.

## 6. 掉箱检测 / Box Drop Detection

在 `global.lua` 的 `DropSignalDete()` 中，原版逻辑在掉箱报警时会关闭对应吸盘输出：

```lua
IORes(SuckerCfg.Port.Mode, SuckerPort, OFF)
```

当前 Unista 版本删除了这一步。也就是说，当检测到 `Box Fall Down!` 时，系统会报警，但不会自动关闭吸盘 DO。

该行为可以避免误检测时立即释放仍被吸住的箱子或隔板，使现场人员有机会先确认状态再处理。

In `DropSignalDete()` inside `global.lua`, the original logic turned off the corresponding vacuum output when a box-drop alarm was raised:

```lua
IORes(SuckerCfg.Port.Mode, SuckerPort, OFF)
```

This step is removed in the current Unista version. When `Box Fall Down!` is detected, the system raises an alarm but does not automatically turn off the vacuum DO.

This can prevent an accidental release of boxes or interlayers during false detection and allows on-site staff to confirm the situation before taking action.

## 7. 到位信号检测 / In-place Signal Detection

`src1.lua` 中的 `GetDeteMode()` 增加了二次 DI 确认逻辑。对于不同吸盘数量，程序会先判断所有需要的到位输入是否满足条件，然后再次读取同一组 DI，确认仍然满足后才调用 `GetSignal(PalletNumber)`。

该修改用于降低输入信号抖动、瞬间误触发或传感器不稳定导致的误判。

与 `2.4.2-france` 相比，当前版本保留了二次读取结构，但没有保留 France 版本中的 `DelayTime = 500` 和对应 `Wait(DelayTime)`。

In `src1.lua`, `GetDeteMode()` now performs a second DI confirmation. For different sucker counts, the program first checks whether all required in-place inputs meet the expected state, then reads the same DI group again. Only if the second check still passes does it call `GetSignal(PalletNumber)`.

This reduces false detection caused by input jitter, momentary triggers, or unstable sensors.

Compared with `2.4.2-france`, the current version keeps the double-check structure but does not keep the `DelayTime = 500` and `Wait(DelayTime)` used in the France version.

## 8. 双托盘切换 / Dual Pallet Switching

`src2.lua` 中的 `CycleCheckPallet()` 对双托盘切换做了 Unista 定制。原逻辑在某些情况下会直接将当前托盘切回 `Left`。当前版本增加条件：

```lua
if SecondPallet.State.Done then
    Pallet = Left
end
```

这表示只有第二托盘完成后，才允许切回左托盘。该修改可以避免右托盘尚未完成时过早切回左侧，从而影响连续生产流程。

In `src2.lua`, `CycleCheckPallet()` contains a Unista-specific dual-pallet switching change. The original logic could switch the current pallet back to `Left` directly in some cases. The current version adds the condition:

```lua
if SecondPallet.State.Done then
    Pallet = Left
end
```

This means switching back to the left pallet is allowed only after the second pallet is done. It prevents the system from returning to the left side too early while the right pallet is not yet complete.

## 9. 日志与诊断 / Logging And Diagnostics

当前版本增加了多个现场诊断日志，主要用于排查 Tool、User、隔板坐标系、正逆解和负载问题。

Examples include:

- `SetCoordinate Tool Check`
- `SetCoordinate RealTool`
- `src3 GetTeachPoint Tool Check`
- `src3 Tool Data`
- `BoxWeight`

当 `GetPalletTool()` 返回 nil、Tool 正解失败、隔板点位逆解失败或 deposit lift 逆解失败时，程序会通过 `Alarm()` 或 `LogWarn()` 给出更明确的现场诊断信息。

The current version adds several on-site diagnostic logs for troubleshooting Tool, User, interlayer coordinate frame, forward/inverse kinematics, and payload issues.

Examples include:

- `SetCoordinate Tool Check`
- `SetCoordinate RealTool`
- `src3 GetTeachPoint Tool Check`
- `src3 Tool Data`
- `BoxWeight`

When `GetPalletTool()` returns nil, Tool calculation fails, interlayer inverse kinematics fails, or deposit-lift inverse kinematics fails, the program reports clearer diagnostic information through `Alarm()` or `LogWarn()`.

## 10. 与原版和 France 版本的关系 / Relationship With Original And France Versions

### 10.1 Compared With Original 2.4.2 / 相比原版 2.4.2

相比原版 `2.4.2`，Unista 版本增加了大量现场定制逻辑，主要集中在：

- 隔板取料、检测、剥离和放置补偿。
- 吸盘 DO 状态确认。
- 多吸单放时的动态负载和额外抬升。
- Tool RZ=90 时的隔板姿态保护。
- 取料点、过渡点和回程点 J6 保护。
- 双托盘切换条件。
- 掉箱报警时不自动关闭吸盘。
- 更多 Tool / User / payload 诊断日志。

Compared with the original `2.4.2`, the Unista version adds substantial on-site customization, mainly including:

- Interlayer pick, detection, peel motion, and place compensation.
- Vacuum DO state verification.
- Dynamic payload and extra lift for multi-pick single-place motion.
- Interlayer orientation protection when Tool RZ is 90 degrees.
- J6 protection for pick points, transition points, and return paths.
- Dual-pallet switching condition.
- No automatic vacuum shutoff on box-drop alarm.
- Additional Tool / User / payload diagnostic logs.

### 10.2 Compared With 2.4.2 France / 相比 2.4.2 France

相比 `2.4.2-france`，当前 Unista 版本不是简单复制 France 版本，而是在其部分隔板思路上进一步定制：

- France 版本已有部分隔板慢速和隔板相关路径处理；当前版本增加了 `DI(17)` / `DI(18)` stop condition。
- 当前版本新增隔板剥离动作，而不仅是简单慢速上抬。
- 当前版本增加多吸单放后的 250 mm 额外抬升。
- 当前版本进一步加强 Tool RZ=90、示教 pose、J6 和回程点处理。
- 当前版本的到位信号二次确认没有保留 France 版本中的 500 ms 延时。
- `src4.lua` 到 `src7.lua` 无实际业务逻辑变化。

Compared with `2.4.2-france`, the current Unista version is not a simple copy of the France version. It further customizes several interlayer-related ideas:

- The France version already contains some slow interlayer and interlayer path handling; the current version adds the `DI(17)` / `DI(18)` stop condition.
- The current version adds an interlayer peel motion instead of only a simple slow lift.
- The current version adds a 250 mm extra lift after each non-final placement in multi-pick single-place motion.
- The current version further strengthens Tool RZ=90, taught pose, J6, and backward transition handling.
- The current version keeps double DI confirmation but does not keep the 500 ms delay from the France version.
- `src4.lua` to `src7.lua` contain no actual business-logic changes.

## 11. Maintenance Notes / 维护注意事项

后续维护该版本时，建议重点检查以下内容：

- 现场 `DI(16)`、`DI(17)`、`DI(18)` 是否与隔板检测硬件一致。
- 吸盘 A/B/C/D 的 DO 配置是否与 `SuckerCfg.Port` 一致。
- Tool RZ、用户坐标系、隔板用户坐标系是否与示教时一致。
- 多吸单放时，`PalletSuckerFunction`、箱体重量和 ToolWeight 是否正确。
- 如果调整隔板料仓、隔板厚度或隔板取料点，需要重新验证 `PrePickPart` 和 `PartPeelPoint` 的偏移。
- 如果现场出现 J6 翻腕或关节限位问题，应优先检查 `src3.lua` 中隔板点位和回程点的 J6 处理逻辑。

When maintaining this version, the following items should be checked carefully:

- Whether on-site `DI(16)`, `DI(17)`, and `DI(18)` match the interlayer detection hardware.
- Whether vacuum A/B/C/D DO configuration matches `SuckerCfg.Port`.
- Whether Tool RZ, user frame, and interlayer user frame match the taught setup.
- Whether `PalletSuckerFunction`, box weight, and ToolWeight are correct for multi-pick single-place operations.
- If the interlayer magazine, interlayer thickness, or interlayer pick point is changed, `PrePickPart` and `PartPeelPoint` offsets should be revalidated.
- If J6 wrist flipping or joint-limit issues occur on site, first check the interlayer point and backward-transition J6 handling in `src3.lua`.
