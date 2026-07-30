# Lua bilingual comment style guide

## 目标

这套注释规范用于 ERM / BIB 码垛脚本。目标不是改代码逻辑，而是让后续工程师能快速理解变量、条件判断和运动流程。

所有原有中文注释必须保留，并补充对应英文说明。英文说明不使用 `EN:` 前缀。

## 总体规则

1. 不修改 Lua 代码逻辑、变量名、函数名、点位索引和 IO 配置。
2. 中文注释保留在前，英文注释放在后。
3. 长说明使用一段中文 + 一段英文，不要一句中文一句英文交替。
4. 字段级短注释可以使用中文一行 + 英文一行。
5. 行尾中文注释如果太长，可以改为变量前的独立注释块，避免变量定义行过长。
6. 不使用 `EN:`、`中文:`、`English:` 这类标签。
7. `global.lua` 重点解释变量来源、单位、默认值含义、是否来自插件界面、是否会被运行时覆盖。
8. `src0.lua` 重点解释抽象条件判断，例如 `MotionType.Norm`、`MotionType.Part`、`WorkType.Pallet`、`CPoint.Paras.Sucker == -1`、`CIndex`、`LDVel/NLDVel`。
9. `src1.lua` 重点解释信号、传感器、输送线和机器人取料授权。
10. `src2.lua` 重点解释状态更新、箱数/层数/隔板数量更新和托盘更换流程。
11. `src3.lua` 重点解释点位索引、`CPoint`、`MotionPoint`、隔板 J6 / transition 逻辑。
12. `src4.lua` 重点解释产能统计和周期状态更新。

## 长说明格式

适用于文件头、配置块、复杂业务逻辑、多条件判断。

```lua
--[[
BIB 项目输送线配置。

两个实体纸箱在现场作为一个逻辑箱处理。只有 B1 和 B2 同时稳定检测到纸箱后，
才允许机器人执行一次取料。B3 用于检测上游第三个纸箱，避免继续挤压已经停在取料位的纸箱。
M1 控制上游输送段，M2 控制中间定位输送段，用于把纸箱送到 B1/B2 取料位置。

BIB project conveyor configuration.

Two physical cartons are treated as one logical box on site. The robot is allowed to perform one pick
only after both B1 and B2 stably detect cartons. B3 is used to detect the upstream third carton,
preventing it from pushing against cartons already stopped at the pick position. M1 controls the
upstream conveyor section, and M2 controls the middle positioning conveyor section that moves cartons
to the B1/B2 pick positions.
]]
```

## 字段级短注释格式

适用于配置项、端口、标志位、速度参数。

```lua
-- 使能 BIB 项目专用输送线控制逻辑。
-- Enables the BIB-specific conveyor control logic.
Enable = true,

-- B1 和 B2 同时检测到纸箱后，需要持续稳定的确认时间，单位：ms。
-- Stable confirmation time after both B1 and B2 detect cartons, in milliseconds.
DelayTime = 1000,
```

## 行尾注释改写规则

如果原来是：

```lua
BIBConveyorCfg = -- BIB项目专用输送线控制配置：两个实体纸箱作为一个逻辑箱取料
{
```

建议改成：

```lua
-- BIB 项目专用输送线控制配置：两个实体纸箱作为一个逻辑箱取料。
-- BIB-specific conveyor control configuration: two physical cartons are picked as one logical box.
BIBConveyorCfg =
{
```

## 条件判断注释示例

```lua
-- 普通箱子动作：从输送线取箱并放到托盘。
-- Normal-box motion: picks cartons from the conveyor and places them on the pallet.
if (CPoint.Paras.Mode == MotionType.Norm) then

-- 隔板动作：从隔板料仓取隔板并放到指定层之间。
-- Interlayer motion: picks an interlayer from the magazine and places it between configured layers.
elseif (CPoint.Paras.Mode == MotionType.Part) then
```

## 输出要求

最终输出文件名必须保持插件脚本原始命名：

- `global.lua`
- `src0.lua`
- `src1.lua`
- `src2.lua`
- `src3.lua`
- `src4.lua`

不要输出 `src0_cn_en_comments.lua` 这类带后缀的文件名。
