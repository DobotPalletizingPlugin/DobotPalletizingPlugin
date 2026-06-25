# ERM Palletizing Program Change Summary  
# ERM 码垛程序修改总结

## 0. Comparison Scope / 对比范围

This document summarizes the differences between the original program and the modified ERM palletizing program, based on a terminal comparison of the uploaded files.

本文根据终端对比结果，总结原版程序与当前 ERM 修改版程序之间的差异。

### Compared files / 对比文件

| Module | Original version / 原版 | Modified version / 修改版 | Result / 结果 |
|---|---|---|---|
| `src0` | `src0(21).lua` | `src0(20).lua` | Major motion logic changes / 运动逻辑大幅修改 |
| `src1` | `src1(12).lua` | `src1(11).lua` | Signal debounce added / 增加信号防抖 |
| `src2` | `src2(12).lua` | `src2(11).lua` | No functional change / 无功能性修改 |
| `src3` | `src3(17).lua` | `src3(16).lua` | Point calculation and J6 logic changed / 点位计算与 J6 逻辑修改 |
| `src4` | `src4(7).lua` | `src4(6).lua` | No functional change / 无功能性修改 |
| `global` | `global(13).lua` | `global(12).lua` | ERM project parameters appended / 增加 ERM 项目配置参数 |

---

# 中文版本

## 1. 总体背景

本次修改主要围绕 ERM 项目的码垛隔板动作进行优化。  
核心问题不是单一 bug，而是一组与 **隔板路径、J1/J6 关节分支、transition 路径、standby 衔接、节拍、传感器稳定性** 相关的问题。

主要目标如下：

1. 避免放完隔板后 J1 向操作员侧危险方向旋转。
2. 避免 J6 在隔板动作后发生多余 360° 旋转。
3. 避免 J6 被归一化到超出软限位的角度，例如 `-443°`。
4. 区分普通 box transition 与隔板 transition 的运动类型。
5. 保留隔板 forward/backward 的直线退出路径，避免碰到隔板支架。
6. 每层最后一个 box 后，如果下一步是隔板动作，则跳过无效 standby。
7. 对 box 到位信号增加防抖，避免瞬时信号误触发。

---

## 2. `src0` 修改总结：运动执行逻辑

`src0` 是本次修改最多的文件，主要影响：

- `StandyMotion`
- `PTPMotion`
- `TransMotion`
- J1/J6 安全归一化
- 隔板安全点
- 下一笔任务衔接
- box 放置后的抬升逻辑

---

## 2.1 新增 J1 安全分支控制

### 原版逻辑

原版没有对 J1 做安全分支限制。  
如果控制器把等效角选择到负方向，例如 `-210°`、`-270°`，机器人可能从操作员侧绕过去。

### 修改后逻辑

新增：

```lua
local J1SafeMin = -60
local J1SafeMax = 200
```

新增函数：

```lua
NormalizeJ1ToSafeBranch(j1)
```

作用：

- 将 J1 限制在现场安全分支内。
- 典型转换：

```text
-210° → 150°
-270° → 90°
```

### 目的

避免机器人为了走数学上的最近角而进入操作员侧危险区域。

---

## 2.2 新增 J6 软限位保护

### 原版问题

之前的 J6 归一化只考虑“离当前 J6 最近”，没有检查 J6 软限位。

实际故障中出现：

```text
target J6 = -443.67°
```

这个角度与 `-83.67°` 在数学上等效，但已经超出第六轴软限位，因此控制器报：

```text
Preprocessing point exceeds joint limit
```

### 修改后逻辑

新增：

```lua
local J6SoftMin = -360
local J6SoftMax = 360
```

新增函数：

```lua
NormalizeJ6ToValidRange(j6, UseCurrentNearest)
```

作用：

- 在 `-360° ~ 360°` 范围内选择合法等效角。
- 如果 `UseCurrentNearest = true`，则在合法范围内选择最接近当前 J6 的等效角。
- 如果最近角超限，例如 `-443°`，则回退到合法角度，例如 `-83°`。

### 目的

解决 J6 被归一化到非法角度导致的 joint limit 报错。

---

## 2.3 新增 SafeMovJ / SafeMovL 包装函数

### 原版逻辑

原版直接调用：

```lua
MovJ(...)
MovL(...)
```

没有统一处理 J1 / J6。

### 修改后逻辑

新增：

```lua
SafeMovJ(Point, Option, NormalizeJ6)
SafeMovL(Point, Option, NormalizeJ6)
```

执行前会先调用：

```lua
NormalizeJointForSafeBranch(Point, NormalizeJ6)
```

统一处理：

- J1 安全分支
- J6 软限位
- 根据需要选择是否让 J6 尽量贴近当前角度

### 目的

避免每个运动点单独处理 J1/J6，降低遗漏风险。

---

## 2.4 `TransMotion` 修改：区分 box / 隔板、forward / backward

### 原版 `TransMotion`

原版逻辑非常简单：

```lua
if PalletObstacleFunc == 1 then
    MovL(CPoint.MotionPoint[i], { a = Acc, v = Vel, cp = 100 })
else
    MovJ(CPoint.MotionPoint[i], { a = Acc, v = Vel, cp = 100 })
end
```

特点：

- forward 和 backward 使用同一组 `MotionPoint[1~5]`。
- 不区分普通 box 和隔板。
- 不区分工艺路径和普通换姿态路径。
- `cp = 100`。
- 没有 J1/J6 安全处理。
- 如果 `PalletObstacleFunc = 0`，则全部 transition 走 `MovJ`。

---

### 修改后 `TransMotion`

修改后逻辑变为：

| Motion type / 动作类型 | Direction / 方向 | Motion command / 运动指令 | cp | 说明 |
|---|---|---:|---:|---|
| Normal box | forward | `SafeMovJ` | `0` | 普通 box transition 不是工艺直线路径，使用 MovJ 降低奇异区风险 |
| Normal box | backward | `SafeMovJ` | `0` | 普通 box 回程同样使用 MovJ |
| Partition | forward | `SafeMovL` | `100` | 取隔板后进入放置区，需要保持示教直线路径 |
| Partition | backward | `SafeMovL` | `0` | 从隔板支架附近退出，必须避免 MovJ 抄近路扫到支架 |

### 重要变化

#### 1. backward 优先使用 `BackwardMotionPoint`

```lua
if CDir == Dir.Backward and CPoint.BackwardMotionPoint ~= nil then
    TPoint = CPoint.BackwardMotionPoint[i]
end
```

也就是说：

- forward 使用 `MotionPoint[1~5]`
- backward 优先使用 `BackwardMotionPoint[1~5]`

#### 2. transition 速度和加速度限制为 30

```lua
if TAcc == nil or TAcc > 30 then
    TAcc = 30
end

if TVel == nil or TVel > 30 then
    TVel = 30
end
```

### 修改目的

1. 普通 box transition 用 MovJ，减少 J5 接近 `±90°` 时的预处理失败。
2. 隔板 forward 保留 MovL，保证取隔板后的贴近和放置效果。
3. 隔板 backward 也改为 MovL，避免底层隔板从支架附近退出时 MovJ 走非直线路径扫到支架。
4. backward 使用专用点，避免 forward / backward 共用一套 J6 造成冲突。

---

## 2.5 `StandyMotion` 修改：隔板 standby 与 backward J6 对齐

### 原版 `StandyMotion`

原版逻辑：

```lua
if StateReady == false and LiftingHeight > 1 then
    MovJ(CPoint.Paras.Standy)
elseif CPoint.Paras.Mode == MotionType.Part then
    Standy.pose = CPoint.Paras.Standy.pose
    Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH
    MovJ(Standy)
else
    MovJ(CPoint.MotionPoint[7])
end
```

问题：

- 隔板 standby 是重新用 pose 计算的。
- J6 可能和 backward transition 的终点 J6 不一致。
- 回 standby 时容易发生 J6 多余旋转。

### 修改后逻辑

如果是隔板动作：

```lua
if CPoint.StandyMotionPoint ~= nil then
    SafeMovJ(CPoint.StandyMotionPoint, ...)
else
    SafeMovJ(GetPartitionStandbyJoint(CPoint), ...)
end
```

其中 `StandyMotionPoint` 由 `src3` 计算并传入。

### 修改目的

- 隔板 backward transition 的 J6 和 standby 的 J6 保持一致。
- 避免 backward 后再去 standby 时发生 J6 多余旋转。
- 所有 standby 运动都通过 SafeMovJ / SafeMovL 处理 J1/J6。

---

## 2.6 `PTPMotion` 修改：函数签名增加 CQueue

### 原版

```lua
PTPMotion(PalletNumber, CPoint)
```

### 修改后

```lua
PTPMotion(PalletNumber, CPoint, CQueue)
```

### 目的

`PTPMotion` 现在需要查看下一笔队列任务，用于判断：

- 当前普通 box 放完后，下一笔是不是隔板动作。
- 如果下一笔是隔板，则跳过 box standby，直接进入隔板安全路径。

---

## 2.7 `PTPMotion` 修改：取隔板前后增加 200 mm 抬升

### 修改后新增参数

```lua
local PartSlowLiftHeight = 200
local PartSlowLiftAcc = 10
local PartSlowLiftVel = 10
```

### 取隔板前

先到隔板取料点上方 200 mm：

```lua
CPartPickLift.pose[3] = CPartPick.pose[3] + 200
MovL(CPartPickLift, { cp = 0 })
```

再用力/模拟量条件下降到隔板取料点：

```lua
MovL(CPartPick, { a = 53, v = 20, stopcond = "AI(1) <= 1.5" })
```

### 取隔板后

吸取隔板后再慢速抬升 200 mm：

```lua
MovL(CPartPickLift, { a = 10, v = 10, cp = 0 })
```

### 目的

- 避免取隔板时直接冲到纸板堆。
- 通过慢速直线抬升减少纸板被拖拽或剐蹭。
- `stopcond` 用于在检测到接触/压力条件时提前停止。

---

## 2.8 `PTPMotion` 修改：隔板放置动作简化为直接 MovL 到放置点

### 原版逻辑

原版对隔板和普通 box 使用类似路径：

```text
transition
→ 放置点上方
→ 放置点
→ 放置点上方
→ backward transition
```

### 修改后逻辑

对于隔板：

```text
forward transition
→ 直接 MovL 到隔板放置点
→ 关闭吸盘
→ 垂直抬升 100 mm
→ backward transition
```

对应代码：

```lua
MovL(CPoint.MotionPoint[7 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 0 })
```

放下隔板后：

```lua
PartPlaceLift.pose[3] = PartPlaceLift.pose[3] + 100
MovL(PartPlaceLift, { a = NLDAcc, v = NLDVel, cp = 0 })
```

### 目的

- 隔板是软纸板，放置路径应更直接。
- 减少在隔板放置点附近绕行。
- 放下后先垂直抬升，避免横向移动时刮到隔板。

---

## 2.9 `PTPMotion` 修改：普通 box 放置后增加 250 mm 抬升

### 修改后

普通 box 放置后，代码增加：

```lua
local DepositLiftHeight = 250
```

如果当前还有下一次放置：

```lua
liftPoint.pose[3] = liftPoint.pose[3] + DepositLiftHeight
MovL(liftJointPoint, { a = NLDAcc, v = NLDVel, cp = 0 })
```

### 目的

- 当前 box 放完后，先抬高再进入下一段路径。
- 降低末端或箱体与已码放箱体之间的干涉风险。
- 注意：代码中注释写的是“抬高 80 mm”，但实际变量值是 `250`，因此实际行为以 `250 mm` 为准。

---

## 2.10 `PTPMotion` 修改：普通 box 最后一箱后跳过无效 standby

### 原版逻辑

普通 box 放完后总是：

```text
backward transition
→ StandyMotion
```

如果下一步是隔板，会变成：

```text
box 放完
→ box standby
→ 再去隔板 safe / 隔板取料
```

这会浪费节拍，并且可能导致 J1/J6 再次重新选择分支。

### 修改后逻辑

放完普通 box 后：

```lua
local NextPartPoint = GetNextPartitionMotion(CQueue)
if NextPartPoint ~= nil then
    PartitionGoSafePoint(NextPartPoint, false, false)
    SkipStandby = true
end
```

即：

```text
box 放完
→ backward transition
→ 下一笔隔板安全点
→ 直接进入隔板动作
```

### 目的

- 减少一次无意义的 standby 往返。
- 避免 J1 在 box standby 与隔板取料之间重新选择危险分支。
- 提高节拍。

---

## 2.11 新增 `PartitionGoSafePoint`

新增函数：

```lua
PartitionGoSafePoint(CPoint, UseGlobalPartSafePoint, KeepCurrentJ6)
```

逻辑：

1. 优先使用 `CPoint.MotionPoint[7]` 作为隔板安全点。
2. 如果没有可用点，则使用全局 `PartSafePoint`。
3. `PartSafePoint` 的数值可以在 Debug menu 中定义和修改。
4. `PartSafePoint` 默认值与 box 默认安全点一致，即默认也是：
   ```lua
   PartSafePoint = { joint = { 90, 0, 90, 0, -90, 0 } }
   ```
5. 默认保持当前 J6，避免刚离开放置点就发生腕部旋转。
6. 如果是普通 box 最后一箱后准备进入下一笔隔板，则可以不保持当前 J6，直接使用下一笔隔板安全点完整 joint。

### 目的

- 让机器人从隔板区域回到安全区域。
- 避免从隔板放置点直接向 standby 大幅旋转。
- 控制 J1/J6 的过渡分支。

---

## 2.12 新增 `GetNextPartitionMotion`

新增函数：

```lua
GetNextPartitionMotion(CQueue)
```

用途：

- 查看队列下一笔任务。
- 如果下一笔是隔板动作，则返回该隔板点位。
- 供 `PTPMotion` 判断是否跳过普通 box standby。

---

## 2.13 新增 `GetAdjustedPartitionPoint`

新增函数：

```lua
GetAdjustedPartitionPoint(PalletNumber, BasePoint)
```

当前逻辑：

```lua
if PalletNumber.Pallet == 1 then
    AdjustedPoint.pose[1] = AdjustedPoint.pose[1] - 1000
end
```

用途：

- 对右侧栈板的隔板点位做额外 X 方向偏移。
- 用于拆垛/隔板相关路径中对 `PartPick` 的修正。

---

## 3. `src3` 修改总结：点位计算与 J6 防旋转

`src3` 负责点位计算。本次修改主要是为 `src0` 提供更稳定的 forward/backward 点位，以及避免 J6 被错误改写。

---

## 3.1 `CreatePalletData` 增加 J6 记录字段

### 原版

原版只保存：

```lua
PartPick
PartPlace
```

### 修改后新增

```lua
PartPickTeachJ6 = nil
PartTransTeachJ6 = {}
```

### 目的

- `PartPickTeachJ6`：保存隔板取料示教点 J6。
- `PartTransTeachJ6`：保存隔板 transition 示教点 J6。
- 防止后续逆解或统一 J6 改写破坏现场示教姿态。

---

## 3.2 `GetTeachPoint` 保存隔板示教 J6

### 修改内容

如果隔板取料点是 joint 示教点：

```lua
CData.PartPickTeachJ6 = PartPickJoint.joint[6]
```

同时遍历隔板 transition 示教点：

```lua
CData.PartTransTeachJ6[i] = PalletNumber.TeachPoint.TransPartitionPoint.joint[i][6]
```

### 目的

- 隔板取料点 `MotionPoint[6]` 保持示教 J6。
- 隔板 forward transition `MotionPoint[1~5]` 保持示教 J6。
- 防止 J6 被 `GetInvK` 或后续统一 J6 逻辑改掉。

---

## 3.3 `GetPickPlacePoint`：隔板放置点抬高 10 mm

### 修改后

当 `Res.Mode == MotionType.Part`：

```lua
PlacePose.pose[3] = PlacePose.pose[3] + 10
```

### 目的

- 隔板是纸质/较软材料。
- 放置点稍微抬高，避免压太深、刮到箱子或托盘。
- 减少隔板变形和摩擦。

---

## 3.4 `GetAutoGenPoint`：隔板自动 transition 改为放置点上方 100 mm

### 原版

自动 transition 会把姿态 Rz 改成放置点姿态：

```lua
TPoint.pose[6] = Point.Pose[8][6]
```

### 修改后

如果是隔板：

```lua
TPoint.pose[3] = Point.Pose[8][3] + 100
```

### 目的

- 隔板 transition 不再沿用过高或不合适的自动点 Z。
- 让隔板路径更接近实际放置点。
- 避免过高绕行导致节拍浪费或姿态变化过大。

---

## 3.5 `GetTransPoint`：隔板最后一个 transition 固定为放置点上方 100 mm

### 原版

原版会根据：

```lua
Point.Pose[8][3] + PalletNumber.OffsetHeight + OffSet[1][3]
```

以及取料上方高度 `PHeight` 调整 transition 高度。

### 修改后

如果是隔板：

```lua
THeight = Point.Pose[8][3] + 100
```

并且：

```lua
if i == Res.TransNum then
    CopyPoint.pose[i][3] = THeight
end
```

### 目的

- 最后一个隔板 transition 必须贴近放置点。
- 固定为放置点上方 100 mm。
- 避免最后 transition 过高，导致隔板进入放置区域时路径过大。
- 也避免过低，导致提前碰撞。

---

## 3.6 `GetTransPoint`：隔板 transition 不再强制继承放置点 Rz

### 原版

原版对 transition 点执行：

```lua
CopyPoint.pose[i][6] = Point.Pose[8][6]
```

这意味着 transition 姿态会被强行改成放置点姿态。

### 修改后

只有普通 box 保持此逻辑：

```lua
if Res.Mode ~= MotionType.Part then
    CopyPoint.pose[i][6] = Point.Pose[8][6]
end
```

隔板不再强制改 Rz。

### 目的

- 保留隔板 transition 的示教姿态。
- 减少 J6 被重新计算或大幅旋转。
- 保证隔板 forward 路径符合现场示教。

---

## 3.7 `GetResult`：增加 `BackwardMotionPoint`

### 原版

```lua
Ret = { MotionPoint = {}, Paras = {} }
```

forward 和 backward 使用同一组 `MotionPoint[1~5]`。

### 修改后

```lua
Ret = { MotionPoint = {}, BackwardMotionPoint = {}, Paras = {} }
```

对于隔板：

```lua
Ret.BackwardMotionPoint[i] = DeepCopy(Ret.MotionPoint[i])
Ret.BackwardMotionPoint[i].joint[6] = BackwardTransJ6
```

### 目的

- forward 使用示教 J6。
- backward 使用 standby 方向 J6。
- 避免一套 transition 点同时服务 forward/backward，导致 J6 不能兼顾两边。

---

## 3.8 `GetResult`：计算 `StandyMotionPoint` 和 `BackwardTransJ6`

### 修改后

当是隔板动作时，使用 standby pose 做逆解：

```lua
ErrId, StandyJoint = InverseKin(Standy)
BackwardTransJ6 = StandyJoint.joint[6]
Ret.StandyMotionPoint = DeepCopy(StandyJoint)
```

### 目的

- backward transition 的 J6 与 standby 终点 J6 一致。
- `src0.StandyMotion()` 可以直接使用 `StandyMotionPoint`。
- 避免 backward 结束后再去 standby 时 J6 额外旋转。

---

## 3.9 `GetResult`：隔板 forward transition 保留示教 J6

### 修改后

对于 `i < 6` 的 transition 点：

```lua
if Res.Mode == MotionType.Part then
    Ret.MotionPoint[i].joint[6] = CData.PartTransTeachJ6[i]
end
```

### 目的

- `MotionPoint[1~5]` 用于隔板 forward。
- forward 是取隔板后进入放置区域的工艺路径。
- 必须保留现场示教 J6，否则隔板姿态会变化。

---

## 3.10 `GetResult`：隔板取料点保留示教 J6

### 修改后

```lua
Ret.MotionPoint[6].joint[6] = CData.PartPickTeachJ6
```

### 目的

- 防止隔板取料点经过逆解后 J6 改变。
- 保证取隔板时末端姿态与示教一致。

---

## 3.11 `GetResult`：普通 box transition 增加 J5 奇异区保护

### 问题

普通 box transition 原逻辑会把 J6 强制改成放置点 J6：

```lua
Ret.MotionPoint[i].joint[6] = CJoint[8][6]
```

当 J5 接近 `±90°` 时，强改 J6 容易制造腕部奇异区附近的另一套关节分支，引发预处理失败。

### 修改后

如果 J5 接近 `±90°`：

```lua
math.abs(math.abs(J5) - 90) < 3
```

则保留 `GetInvK` 的原始 J6，不再强制改成放置点 J6。

### 目的

- 避免普通 box transition 在腕部奇异区切换分支。
- 配合 `src0` 的 J6 软限位逻辑，避免再出现 `-443°` 这类非法角度。

---

## 4. `src1` 修改总结：增加信号防抖

## 4.1 增加 500 ms 信号防抖

### 原版

DI 满足条件后立即触发：

```lua
if DI(...) == State then
    GetSignal(PalletNumber)
end
```

### 修改后

新增：

```lua
local DelayTime = 500
```

检测到 DI 后先等待 500 ms，再二次确认：

```lua
if DI(...) == State then
    Wait(DelayTime)
    if DI(...) == State then
        GetSignal(PalletNumber)
    end
end
```

该逻辑覆盖：

- 单传感器
- 双传感器
- 三传感器
- 四传感器

### 目的

- 防止传感器脉冲、抖动、反光误触发。
- 确保 box 到位信号是持续稳定状态。

---

## 5. `global` 修改总结

`global` 中的公共结构基本保持原版框架。当前修改版追加了 ERM 项目参数，例如：

- `PalletName = "BIB_6x3L"`
- `PalletBeInPlaceOKButton = true`
- `TeachPointOffHeight = 200`
- `PartCfg.Enable = true`
- `PartCfg.Port.A = 21`
- `Time.Pick.In = 200`
- `Time.Place.In = 200`
- `PartSafePoint = { joint = {90, 0, 90, 0, -90, 0} }`

---

---

## 6. 最终运动逻辑总结

### 6.1 普通 box

```text
取箱
→ box forward transition: MovJ
→ 放箱
→ 放置后抬升 250 mm（多放时）
→ box backward transition: MovJ
→ 如果下一笔是隔板：跳过 box standby，直接去下一笔隔板安全点
→ 如果下一笔不是隔板：正常 standby
```

---

### 6.2 隔板

```text
去隔板安全/上方点
→ 到隔板取料点上方 200 mm
→ MovL 慢速接近隔板取料点，带 AI stop condition
→ 开吸
→ MovL 慢速抬升 200 mm
→ partition forward transition: MovL, cp=100
→ 直接 MovL 到隔板放置点
→ 关闭吸盘
→ 垂直抬升 100 mm
→ partition backward transition: MovL, cp=0
→ PartSafePoint / MotionPoint[7]
→ standby
```

---

## 7. 已解决的问题

| Problem / 问题 | Modification / 修改 | Result / 结果 |
|---|---|---|
| J1 向操作员侧旋转 | J1 safe branch `-60° ~ 200°` | 避免危险 J1 分支 |
| J6 多余旋转 | forward/backward 分开 J6，standby J6 对齐 | 减少腕部旋转 |
| J6 `-443°` 超限 | J6 soft limit `-360° ~ 360°` | 修复 joint limit |
| 隔板 backward MovJ 可能扫到支架 | 隔板 backward 改为 MovL + cp=0 | 底层退出更安全 |
| 最后一箱后回无效 standby | CQueue 判断下一笔隔板并跳过 standby | 提高节拍 |
| 普通 transition 在 J5≈±90° 预处理失败 | 普通 transition 改 MovJ；src3 保留奇异区 J6 | 降低预处理失败风险 |
| 传感器瞬时误触发 | src1 增加 500 ms 二次确认 | 信号更稳定 |
| 隔板压太深 / 刮蹭 | 放置点 Z +10 mm，放后抬升 100 mm | 减少干涉 |
| 隔板 transition 过高 | 最后 transition = 放置点上方 100 mm | 路径更合理 |

---

# English Version

## 1. Background

The modification focused on the ERM palletizing project, especially the partition sheet handling sequence.  
The main issues were related to:

- partition motion path,
- J1 safety branch,
- J6 wrist rotation,
- forward/backward transition conflicts,
- unnecessary standby motions,
- preprocessing joint-limit alarms,
- partition frame collision risk,
- conveyor signal stability.

---

## 2. `src0` Changes: Motion Execution

`src0` contains the main execution logic.  
The key modified functions are:

- `StandyMotion`
- `PTPMotion`
- `TransMotion`
- J1/J6 normalization helpers
- partition safe-point logic
- queue look-ahead logic

---

## 2.1 J1 Safe Branch Control

### Original behavior

The original code did not constrain equivalent J1 solutions.  
The controller could select equivalent angles such as `-210°` or `-270°`, causing the arm to rotate toward the operator area.

### Modified behavior

A safe J1 branch was added:

```lua
J1SafeMin = -60
J1SafeMax = 200
```

The new function:

```lua
NormalizeJ1ToSafeBranch(j1)
```

converts unsafe equivalent angles into the desired branch:

```text
-210° → 150°
-270° → 90°
```

### Purpose

To prevent the robot from rotating into the operator side while still using an equivalent joint solution.

---

## 2.2 J6 Software-Limit Protection

### Original issue

The previous wrist normalization only selected the mathematically nearest equivalent angle.  
In one fault case, the target J6 became:

```text
-443.67°
```

Although equivalent to about `-83.67°`, it exceeded the J6 software limit.

### Modified behavior

J6 is now normalized only inside:

```lua
J6SoftMin = -360
J6SoftMax = 360
```

The new function:

```lua
NormalizeJ6ToValidRange(j6, UseCurrentNearest)
```

selects a valid equivalent angle inside the software limit.

### Purpose

To prevent `Preprocessing point exceeds joint limit` caused by illegal J6 equivalent angles.

---

## 2.3 SafeMovJ / SafeMovL Wrappers

The original program called:

```lua
MovJ(...)
MovL(...)
```

directly.

The modified program adds:

```lua
SafeMovJ(Point, Option, NormalizeJ6)
SafeMovL(Point, Option, NormalizeJ6)
```

Before motion execution, these wrappers apply:

- J1 safe-branch normalization,
- J6 software-limit normalization,
- optional J6 nearest-equivalent selection.

---

## 2.4 `TransMotion`: Box vs Partition, Forward vs Backward

### Original behavior

The original `TransMotion` used one common logic:

```lua
if PalletObstacleFunc == 1 then
    MovL(...)
else
    MovJ(...)
end
```

It did not distinguish:

- normal box vs partition,
- forward vs backward,
- process path vs posture-change path,
- forward transition J6 vs backward transition J6.

### Modified behavior

| Motion | Direction | Command | cp | Reason |
|---|---|---:|---:|---|
| Normal box | forward | `SafeMovJ` | `0` | Avoid wrist singularity and preprocessing errors |
| Normal box | backward | `SafeMovJ` | `0` | Same reason, not a process straight-line path |
| Partition | forward | `SafeMovL` | `100` | Preserve taught approach path and sheet posture |
| Partition | backward | `SafeMovL` | `0` | Avoid MovJ shortcut hitting the partition rack |

Acceleration and speed for transition points are capped at `30`.

Backward motion now uses:

```lua
BackwardMotionPoint[i]
```

when available.

---

## 2.5 `StandyMotion`: Align Partition Standby J6

### Original behavior

For partition standby, the original code recomputed standby from pose and executed `MovJ`.  
This could produce a different J6 from the backward transition endpoint.

### Modified behavior

The modified code uses:

```lua
CPoint.StandyMotionPoint
```

when available, otherwise it computes standby joint using:

```lua
GetPartitionStandbyJoint(CPoint)
```

### Purpose

To align:

```text
partition backward transition J6
=
partition standby J6
```

and reduce unnecessary wrist rotation.

---

## 2.6 `PTPMotion`: Queue-Aware Execution

The function signature changed from:

```lua
PTPMotion(PalletNumber, CPoint)
```

to:

```lua
PTPMotion(PalletNumber, CPoint, CQueue)
```

The queue is used to check whether the next task is a partition motion.  
If yes, the robot skips the normal box standby and goes directly to the next partition safe point.

---

## 2.7 Partition Pick: 200 mm Lift and AI Stop Condition

Before picking a partition sheet, the robot now moves to a point 200 mm above the pick point:

```lua
PartSlowLiftHeight = 200
```

Then it approaches the partition pick point while using the analog input signal to detect the partition sheet position:

```lua
MovL(CPartPick, { a = 53, v = 20, stopcond = "AI(1) <= 1.5" })
```

Here, `AI(1)` is an analog input used to detect the actual partition sheet position / height.  
When the analog signal reaches the defined threshold, the downward motion stops early instead of continuing to press down.

After suction is enabled, it lifts slowly by 200 mm:

```lua
MovL(CPartPickLift, { a = 10, v = 10, cp = 0 })
```

### Purpose

To detect the actual partition sheet position, compensate for partition stack height variation, avoid pressing too deep into the paper stack, and reduce dragging or scraping after suction.

---

## 2.8 Partition Place: Direct MovL and 100 mm Vertical Lift

For partition placement, the modified code goes directly to the placement point:

```lua
MovL(CPoint.MotionPoint[7 + i], { cp = 0 })
```

After placing the partition, it lifts vertically by 100 mm:

```lua
PartPlaceLiftHeight = 100
```

### Purpose

To reduce sheet interference and avoid lateral scraping immediately after release.

---

## 2.9 Normal Box Deposit Lift: 250 mm

For normal box placement, when more placements remain, the robot now lifts by:

```lua
DepositLiftHeight = 250
```

This lift is computed using current joint → FK → Z offset → IK → `MovL`.

### Purpose

To reduce collision risk with already placed boxes.  
Note: the code comment mentions 80 mm, but the actual value is `250 mm`.

---

## 2.10 Skip Useless Standby Before Partition

After placing a normal box, the modified code checks:

```lua
GetNextPartitionMotion(CQueue)
```

If the next task is a partition motion:

```text
box placed
→ backward transition
→ next partition safe point
→ partition motion
```

The robot does not return to the normal box standby.

### Purpose

To reduce cycle time and avoid unnecessary J1/J6 branch switching.

---

## 2.11 Partition Safe Point

A new helper was added:

```lua
PartitionGoSafePoint(CPoint, UseGlobalPartSafePoint, KeepCurrentJ6)
```

It uses:

1. `CPoint.MotionPoint[7]` if available,
2. otherwise the global `PartSafePoint`.

`PartSafePoint` is defined and editable in the Debug menu.  
Its default value is the same as the default box safe point:

```lua
PartSafePoint = { joint = { 90, 0, 90, 0, -90, 0 } }
```

It can either keep current J6 or use the target joint J6 depending on the scenario.

---

## 2.12 Right-Pallet Partition Pick Adjustment

A helper was added:

```lua
GetAdjustedPartitionPoint(PalletNumber, BasePoint)
```

For the right pallet:

```lua
AdjustedPoint.pose[1] = AdjustedPoint.pose[1] - 1000
```

This is used to adjust partition-related pick motion for the right-side pallet.

---

## 3. `src3` Changes: Point Calculation and J6 Rotation Prevention

`src3` was modified to provide better point data for `src0`.

---

## 3.1 Store Taught J6 Values

Two fields were added:

```lua
PartPickTeachJ6
PartTransTeachJ6
```

They store:

- the taught J6 of the partition pick point,
- the taught J6 of partition transition points.

---

## 3.2 Preserve Partition Pick J6

If the partition pick point is taught as a joint point:

```lua
CData.PartPickTeachJ6 = PartPickJoint.joint[6]
```

Later:

```lua
Ret.MotionPoint[6].joint[6] = CData.PartPickTeachJ6
```

### Purpose

To prevent IK from changing the partition pick wrist angle.

---

## 3.3 Preserve Partition Forward Transition J6

For partition transition points:

```lua
CData.PartTransTeachJ6[i]
```

is stored and then applied to:

```lua
Ret.MotionPoint[i].joint[6]
```

for `i = 1..5`.

### Purpose

The forward partition transition must keep the taught J6, because it is part of the real sheet handling process.

---

## 3.4 Partition Placement Z Raised by 10 mm

When `Res.Mode == MotionType.Part`:

```lua
PlacePose.pose[3] = PlacePose.pose[3] + 10
```

### Purpose

To reduce paper sheet compression and interference.

---

## 3.5 Last Partition Transition = 100 mm Above Place Point

For partition transitions:

```lua
THeight = Point.Pose[8][3] + 100
```

The last transition point is forced to this height:

```lua
if i == Res.TransNum then
    CopyPoint.pose[i][3] = THeight
end
```

### Purpose

To keep the final approach closer to the placement point while maintaining safe clearance.

---

## 3.6 Partition Transition Does Not Force Placement Rz

For normal boxes, transition Rz still follows placement Rz.  
For partition motion, this is not done.

### Purpose

To preserve taught partition transition posture and avoid unwanted J6 rotation.

---

## 3.7 BackwardMotionPoint

`src3` now returns:

```lua
BackwardMotionPoint[1..5]
```

for partition motion.

These points are copies of the forward transition points, but their J6 is replaced by the standby J6:

```lua
Ret.BackwardMotionPoint[i].joint[6] = BackwardTransJ6
```

### Purpose

To separate forward and backward J6 requirements.

---

## 3.8 StandyMotionPoint and BackwardTransJ6

`src3` computes standby joint using IK and stores:

```lua
Ret.StandyMotionPoint
Ret.Paras.BackwardTransJ6
```

### Purpose

To make partition backward transition and partition standby share the same wrist branch.

---

## 3.9 Normal Box Transition Singularity Protection

For normal box transition points, when J5 is near `±90°`, the modified code no longer forces J6 to the placement point J6.

Condition:

```lua
math.abs(math.abs(J5) - 90) < 3
```

### Purpose

To avoid generating an unstable wrist branch near singularity.

---

## 4. `src1` Signal Debounce

A 500 ms debounce was added before confirming the input signal.

Original behavior:

```lua
if DI(...) == State then
    GetSignal(PalletNumber)
end
```

Modified behavior:

```lua
if DI(...) == State then
    Wait(DelayTime)
    if DI(...) == State then
        GetSignal(PalletNumber)
    end
end
```

This applies to single-sensor, dual-sensor, three-sensor and four-sensor cases.

Purpose:

- avoid false triggering caused by short pulses,
- avoid unstable sensor input,
- confirm that the box arrival signal is stable before starting motion.

---

---

## 5. Final Result

The final behavior is:

```text
Normal box:
Pick box
→ box transition by MovJ
→ place box
→ lift 250 mm if needed
→ box backward by MovJ
→ skip standby if next task is partition

Partition:
Move above pick
→ approach by MovL with AI(1) analog partition-position detection
→ pick partition
→ lift 200 mm slowly
→ forward transition by MovL
→ place partition directly
→ lift 100 mm
→ backward transition by MovL
→ safe point
→ standby
```

This version solves:

- unsafe J1 branch selection,
- J6 over-rotation,
- J6 software-limit fault,
- partition backward collision risk with rack,
- unnecessary standby before partition,
- transition singularity problems,
- unstable input triggering.

