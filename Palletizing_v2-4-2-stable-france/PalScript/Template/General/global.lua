local mqttFunc = require("libplugin_eco")
-------------------------------------------------------------------------------------------
-- 全局定义文件
-- Global definition file.
-- 本文件只放公共常量、公共配置、左右栈板数据模板、通讯参数和通用工具函数。
-- This file only contains shared constants, shared configuration, left/right pallet data templates, communication parameters, and common utility functions.
-- src0~src4都会直接读取这里的变量，所以修改默认值时要确认变量是否会被插件界面、寄存器或控制器全局变量覆盖。
-- src0 to src4 read these variables directly, so before changing a default value, confirm whether it will be overwritten by the plugin UI, registers, or controller global variables.
-------------------------------------------------------------------------------------------
-- 公共全局常量
-- Shared global constants.
-------------------------------------------------------------------------------------------
Home = 0            --回零
-- Return-to-home state.
Idle = -1           --空闲
-- Idle state.
Left = 0            --左侧栈板
-- Left pallet side.
Right = 1           --右侧栈板
-- Right pallet side.
LiftingInTime = 500 --升降柱过程延时
-- Delay used during lifting-column operations.
BlinkTime = 500     --三色灯闪烁时间
-- Blink period for the three-color tower light.
-- 三色灯状态类型
-- State definitions for the three-color tower light.
Light =
{
    Init = 0,
    Yellow =
    {
        On = 1,
        Blink = 2
    },
    Green =
    {
        On = 3,
        Blink = 4
    },
    Red =
    {
        On = 5,
        Blink = 6
    }
}
-- 运动类型
-- Motion type definitions.
MotionType =
{
    Norm = 0,    --料箱取放运动
    -- Normal box pick/place motion.
    Part = 1     --隔板取放运动
    -- Interlayer sheet pick/place motion.
}
-- 工作类型
-- Work type definitions.
WorkType =
{
    Pallet = 1,  --码垛
    -- Palletizing mode.
    Depallet = 2 --拆垛
    -- Depalletizing mode.
}
-- 掉料报警类型
-- Dropped-box alarm type definitions.
DropType =
{
    Norm = 0,    --掉料检测信号OFF，吸盘信号ON，触发掉料报警
    -- Dropped-box alarm is triggered when the drop-detection signal is OFF while the sucker output is ON.
    Prep = 1     --掉料检测信号ON，吸盘信号ON，触发工艺包启动末端带料报警
    -- Start-with-load alarm is triggered when the drop-detection signal is ON while the sucker output is ON during process start.
}
-- 工具类型
-- Tool type definitions.
ToolType =
{
    Conc = 0,    --同心工具
    -- Concentric TCP/tool.
    Ecc = 1,     --偏心工具
    -- Eccentric TCP/tool.
}
-- 点位类型
-- Motion point type definitions.
PointType =
{
    -- 过渡点
    -- Transition point.
    Trans =
    {
        Index =
        {
            A = 1,
            B = 2,
            C = 3,
            D = 4,
            E = 5
        },
        Cfg =
        {
            Norm = 5, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 6  --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    },
    -- 取料点
    -- Pick point.
    Pick =
    {
        Index =
        {
            A = 6
        },
        Cfg =
        {
            Norm = 1, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 2  --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    },
    -- 取料上方点
    -- Pick offset point above the pick position.
    PickOffset =
    {
        Index =
        {
            A = 7
        },
        Cfg =
        {
            Norm = 3, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 4  --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    },
    -- 放料点
    -- Place point.
    Place =
    {
        Index =
        {
            A = 8,
            B = 9,
            C = 10,
            D = 11
        },
        Cfg =
        {
            Norm = 11, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 12  --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    },
    -- 放料上方点
    -- Place offset point above the place position.
    PlaceOffset =
    {
        Index =
        {
            A = 12,
            B = 13,
            C = 14,
            D = 15
        },
        Cfg =
        {
            Norm = 9, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 10 --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    },
    -- 放料偏移点
    -- Insertion/placing offset point.
    Insert =
    {
        Index =
        {
            A = 16,
            B = 17,
            C = 18,
            D = 19
        },
        Cfg =
        {
            Norm = 7, --取料放料动作点位
            -- Point count/setting for normal box pick/place motions.
            Part = 8  --隔板取料放料动作点位
            -- Point count/setting for interlayer pick/place motions.
        }
    }
}
-- 模式状态类型
-- Finite-state-machine mode definitions.
FSMType =
{
    DP = -3,        --双栈板
    -- Dual-pallet mode.
    SP = -2,        --单栈板
    -- Single-pallet mode.
    IDLE = -1,      --无栈板
    -- No-pallet mode.
    SL = 0,         --单传送带单左侧栈板
    -- Single conveyor with only the left pallet enabled.
    SR = 1,         --单传送带单右侧栈板
    -- Single conveyor with only the right pallet enabled.
    SLR = 2,        --单传送带双侧栈板
    -- Single conveyor serving both left and right pallets.
    DLR = 3         --双传送带双侧栈板
    -- Dual conveyors serving both left and right pallets.
}
-- 状态类型
-- Pallet/job status definitions.
StateType =
{
    LosePallet = 0, --未检测到栈板
    -- Pallet not detected.
    DisPallet = 1,  --未使能栈板
    -- Pallet side is not enabled.
    Run = 2,        --码垛/拆垛中
    -- Palletizing/depalletizing is running.
    Stop = 3,       --码垛/拆垛完成
    -- Palletizing/depalletizing is completed.
    DropBox = 4,    --掉料
    -- Dropped box/material state.
    Idle = 5        --空闲中
    -- Idle status.
}
-- 升降柱类型
-- Lifting-column type definitions.
LiftingType =
{
    EWELLIX = 0,
    GeMinG = 1,
    ZT3ILC = 2,
    LINAK = 3
}
-------------------------------------------------------------------------------------------
-- 公共全局变量
-- Shared global variables.
-- 这一段是整套码垛状态机的运行状态和功能开关。
-- This section contains the runtime states and feature switches for the palletizing state machine.
-- 大部分变量会在初始化阶段被插件界面、寄存器或控制器全局变量覆盖。
-- Most variables may be overwritten during initialization by the plugin UI, registers, or controller global variables.
-- 如果只想调整速度、吸盘、传感器或输送线，优先改对应配置块，不要直接改状态变量。
-- If only speed, sucker, sensor, or conveyor behavior needs adjustment, modify the corresponding configuration block first instead of changing runtime state variables directly.
-------------------------------------------------------------------------------------------
StorageMode = 0                                                  --数据来源选择：nil/1表示从寄存器恢复断电数据；0表示从控制器全局变量恢复断电数据。
-- Data-source selection: nil/1 restores power-loss data from registers; 0 restores it from controller global variables.
StateMachine = -1                                                --主状态机类型，初始化为空闲；后续由InitFSM根据左右栈板使能状态切换为单栈板、双栈板或双输送模式。
-- Main state-machine mode. It starts as idle and is later switched by InitFSM according to left/right pallet enable states into single-pallet, dual-pallet, or dual-conveyor mode.
Pallet = Idle                                                    --当前允许运行的栈板侧：Left表示左侧，Right表示右侧，Idle表示当前没有栈板任务可执行。
-- Currently active pallet side: Left means the left pallet, Right means the right pallet, and Idle means no pallet task is currently executable.
WorkingMode = 0                                                  --工作站模式：0单输送双侧码垛；1双输送单侧码垛；2双输送左右交替码垛。
-- Workstation mode: 0 = single conveyor with two pallet sides; 1 = dual conveyors with one pallet side; 2 = dual conveyors with alternating left/right palletizing.
AgingMode = 0                                                    --老化测试模式：0正常生产；1循环测试，主要用于长时间空跑或仿真验证。
-- Aging-test mode: 0 = normal production; 1 = loop test, mainly used for long dry-run tests or simulation validation.
PalletName = "Pallet"                                            --当前码垛配方名称；插件生成点位、箱型、层数、吸盘模式时都依赖这个名称。
-- Current palletizing recipe name. The plugin uses this name to generate points, box dimensions, layer count, and sucker mode.
SignalReady = false                                              --取料许可标志：传送带或外部信号确认物料到位后置true，运动线程执行一次动作后清false。
-- Pick-permission flag. It is set to true after the conveyor or external signal confirms material arrival, and cleared after the motion thread completes one cycle.
MotionDone = true                                                --机器人动作完成标志：false表示正在执行取放动作，true表示当前动作结束，可等待下一次取料许可。
-- Robot motion completion flag: false means a pick/place motion is running; true means the current motion has finished and the system can wait for the next pick permission.
FilmDone = true                                                  --缠膜完成标志：启用缠膜功能时，机器人需要等待缠膜流程完成后再继续。
-- Wrapping completion flag. When wrapping is enabled, the robot must wait for the wrapping process to finish before continuing.
--------------------------------------------------------------------------------------------
PalletBeInPlaceOKButton = false                                  --栈板到位确认按钮开关：false表示只看栈板检测信号；true表示需要人工按钮确认栈板已放好。
-- Pallet-in-place confirmation button switch: false means only the pallet detection signal is used; true means an operator button confirmation is also required.
PalletLiftingFunction = false                                    --升降柱功能开关：false表示工作站没有升降柱；true表示运动前会同步升降柱高度。
-- Lifting-column feature switch: false means the workstation has no lifting column; true means the lifting height is synchronized before robot motion.
PalletObstacleFunc = 0                                           --自动过渡点避障功能：0关闭；1启用后自动生成过渡点时会考虑障碍物避让。
-- Automatic transition-point obstacle-avoidance feature: 0 = disabled; 1 = automatic transition generation considers obstacle avoidance.
MultPalletFunction = false                                       --多栈板功能：false只启用单侧栈板；true左右两侧栈板都可能参与任务。
-- Multi-pallet feature: false enables only one pallet side; true allows both left and right pallet sides to participate.
PalletSuckerFunction = 0                                         --吸盘数量/控制方式：-1通讯控制单吸；1~4表示使用通用输出控制1~4路吸盘。
-- Sucker quantity/control method: -1 = communication-controlled single sucker; 1 to 4 = IO-controlled 1 to 4 sucker outputs.
RestrictMoveFunction = false                                     --左右垛型高度差限制：true时如果两侧高度差过大，会限制继续向高的一侧码垛。
-- Left/right stack-height difference limit: when true, palletizing toward the higher side is restricted if the two stack heights differ too much.
HighLoadFunc = false                                             --高负载模式：true时使用高负载安全点和更保守的升降/运动策略。
-- High-load mode: when true, high-load safety points and more conservative lifting/motion strategies are used.
BuzzerFunction = false                                           --蜂鸣器开关：true时报警或等待人工操作时可驱动蜂鸣器输出。
-- Buzzer switch: when true, the buzzer output can be driven during alarms or while waiting for operator action.
FilmFunction = true                                              --缠膜功能：true时每垛完成后等待缠膜信号；false时不进入缠膜等待流程。
-- Wrapping feature: true waits for a wrapping signal after each pallet is completed; false skips the wrapping wait process.
ResetPathFunc = false                                             --回安全点路径功能：true时回Home前先经过左右过渡点，避免从当前点直接大幅度转动。
-- Safe return-to-home path feature: when true, the robot passes through left/right transition points before Home to avoid large direct rotations from the current pose.
---------------------------------------------------------------------------------------------
ToolSpeedWithBox = 0                                             --带载速度：机器人抓着箱子或隔板移动时使用，通常来自插件界面。
-- Loaded speed used when the robot is carrying a box or interlayer; normally provided by the plugin UI.
ToolAccWithBox = 0                                               --带载加速度：抓取物料后的加速度，数值越大节拍越快，但越容易触发碰撞或预载误判。
-- Loaded acceleration after material pick. Higher values improve cycle time but increase the risk of collision or preload false alarms.
PlaceSpeed = 0                                                   --放置速度：靠近放置点、下降到放置点时使用，适合控制末端贴近垛型的速度。
-- Place speed used when approaching and descending to the place point; it controls the end-effector speed near the stack.
PlaceAcc = 0                                                     --放置加速度：放置最后阶段使用，过大可能导致箱子滑动或吸盘释放不稳定。
-- Place acceleration used during the final placing stage; too high a value may cause box sliding or unstable sucker release.
ToolSpeedWithoutBox = 0                                          --空载速度：未抓取物料时回程、去取料点、离开放置区域时使用，通常可以设得更高。
-- Unloaded speed used for return motion, moving to the pick area, and leaving the place area when not carrying material; it can usually be set higher.
ToolAccWithoutBox = 0                                            --空载加速度：未抓取物料时使用，影响回程和去取料的节拍。
-- Unloaded acceleration used when the robot is not carrying material; it affects return motion and travel to the pick point.
----------------------------------------------------------------------------------------------
ToolHigh = 0                                                     --工具高度：从法兰到吸盘工作面的高度，用于自动计算取放上方点和负载质心。
-- Tool height from the flange to the sucker working surface; used to automatically calculate pick/place offset points and payload center of mass.
ToolWeight = 0                                                   --工具重量：仅末端工具自重，不包含箱子或隔板；SetPayload时会在此基础上叠加物料重量。
-- Tool weight only, excluding boxes or interlayers. SetPayload adds material weight on top of this value.
TeachPointOffHeight = 300                                        --示教取料点上方偏移高度：自动生成取料上方点时使用，单位毫米。
-- Offset height above the taught pick point, used to generate the pick-offset point automatically. Unit: mm.
HomePoint = { joint = { 90, 0, 90, 0, -90, 0 } }                 --机器人全局安全点，通常用于初始化、异常恢复或回Home。
-- Global robot safety point, usually used for initialization, abnormal recovery, or returning Home.
HomePointPose = { pose = { 175.6, -874.8, 918.7, 180, 0, 180 } } --HomePoint对应的笛卡尔位姿缓存，用于路径判断和仿真显示。
-- Cached Cartesian pose corresponding to HomePoint, used for path judgment and simulation display.
HomeTransPointL = { joint = { 166, 8, 63, 19, -90, 0 } }         --从左侧区域回Home前经过的中间关节点，避免直接跨越工作区。
-- Intermediate joint point used before returning Home from the left area to avoid directly crossing the workspace.
HomeTransPointR = { joint = { -13, 7, 63, 18, -90, 0 } }         --从右侧区域回Home前经过的中间关节点，避免直接跨越工作区。
-- Intermediate joint point used before returning Home from the right area to avoid directly crossing the workspace.
PartSafePoint = { joint = { 90, 0, 90, 0, -90, 0 } }             --隔板动作安全点：放置隔板后先回到该点，再切换到待机点或下一动作。
-- Safety point for interlayer motion. After placing an interlayer, the robot returns here before moving to standby or the next action.
LiftingSafetyPoint = { joint = { 90, -29, 114, 4, -90, 0 } }     --升降柱联动时的普通负载安全点；无升降柱项目通常不会使用。
-- Normal-load safety point used during lifting-column coordination; normally unused in projects without a lifting column.
LiftingSafetyPoint_HL = { joint = { 90, -45, 120, 15, -90, 0 } } --高负载模式下的升降柱安全点；姿态更保守，避免重载时干涉。
-- Lifting-column safety point for high-load mode. The posture is more conservative to avoid interference under heavy load.
-----------------------------------------------------------------------------------------------
FilmDI = 14                                                      --缠膜完成输入信号：用于判断缠膜机是否完成当前托盘缠膜。
-- Wrapping completion input signal used to determine whether the wrapper has finished the current pallet.
BuzzerIO = 15                                                    --蜂鸣器输出信号：报警、等待人工处理或提示换托盘时使用。
-- Buzzer output signal used for alarms, operator waiting states, or pallet-change prompts.
-- 独立隔板吸附控制。
-- Independent interlayer suction control.
-- Enable=true时，隔板吸附不再复用箱子吸盘输出，而是使用PartCfg.Port指定的单独输出。
-- When Enable is true, interlayer suction no longer reuses the box sucker output and instead uses the dedicated output specified by PartCfg.Port.
-- 适用于箱子吸盘和隔板吸盘电磁阀分开的现场。
-- Applicable when the box sucker and interlayer sucker use separate solenoid valves on site.
-- 独立隔板控制配置
-- Independent interlayer control configuration.
PartCfg =
{
    Enable = false,                                              --false：关闭，true：打开
    -- false = disabled; true = enabled.
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        -- IO type: 0 = controller/general IO; 1 = end-effector IO.
        A = 22
    }
}
-- 隔板余量传感器配置。
-- Interlayer remaining-quantity sensor configuration.
-- 本项目使用传感器判断料仓是否还有隔板，隔板数量不再仅靠放置次数递减。
-- This project uses a sensor to determine whether the magazine still has interlayers; the remaining interlayer count is no longer based only on decrementing after each placement.
-- DI为ON时恢复默认隔板数量；DI为OFF时把剩余隔板数量写为0。
-- When the DI is ON, the default interlayer quantity is restored; when the DI is OFF, the remaining quantity is written as 0.
-- 隔板余量检测传感器配置
-- Interlayer remaining-quantity detection sensor configuration.
PartSensorCfg =
{
    Enable = true,                                               --false：关闭，true：启用
    -- false = disabled; true = enabled.
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        -- IO type: 0 = controller/general IO; 1 = end-effector IO.
        A = 21    --隔板检测DI：现场接线为DI21
        -- Interlayer detection DI. The on-site wiring uses DI21.
    },
    DelayTime = 500 --检测防抖时间ms
    -- Detection debounce time in ms.
}
-- 安全吸盘检测端口。
-- Safety sucker detection port.
-- 用于告诉外部安全模块或升降柱：末端当前是否处于带料或吸附相关状态。
-- Used to inform the external safety module or lifting column whether the end effector is currently carrying material or in a suction-related state.
-- 安全吸盘检测端口
-- Safety sucker detection port.
SPortCfg =
{
    Enable = false, --false：关闭，true：打开
    -- false = disabled; true = enabled.
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        -- IO type: 0 = controller/general IO; 1 = end-effector IO.
        A = 18
    }
}
-- 箱体吸盘控制配置。
-- Box sucker control configuration.
-- Port定义吸附输出；Dete定义掉料检测、真空检测和破真空检测。
-- Port defines suction outputs; Dete defines drop detection, vacuum detection, and vacuum-break detection.
-- PalletSuckerFunction决定实际启用几路吸盘以及是否走通讯控制。
-- PalletSuckerFunction determines how many sucker channels are enabled and whether communication control is used.
-- 吸盘控制配置
-- Sucker control configuration.
SuckerCfg =
{
    -- 吸盘类型
    -- Sucker type definitions.
    Type =
    {
        SSingle = -1, --通讯控制单吸
        -- Communication-controlled single suction.
        Single = 1,   --IO控制单吸
        -- IO-controlled single suction.
        Double = 2,   --IO控制双吸
        -- IO-controlled double suction.
        Triple = 3,   --IO控制三吸
        -- IO-controlled triple suction.
        Quadruple = 4 --IO控制四吸
        -- IO-controlled quadruple suction.
    },
    -- 端口
    -- Port configuration.
    Port =
    {
        Mode = 0,     --IO类型, 0：通用IO，1：末端IO
        -- IO type: 0 = controller/general IO; 1 = end-effector IO.
        A = 16,
        B = 17,
        C = 16,
        D = 17
    },
    -- 信号检测类型
    -- Signal detection type.
    Dete =
    {
        Mode = 0, --掉料检测模式, 0：关闭， 1：光电检测， 2：真空检测
        -- Drop-detection mode: 0 = disabled; 1 = photoelectric detection; 2 = vacuum detection.
        -- 光电检测
        -- Photoelectric detection.
        PE =
        {
            A = 18,
            B = 18,
            C = 18,
            D = 18
        },
        -- 真空检测
        -- Vacuum detection.
        Vacuum =
        {
            A = 19,
            B = 19,
            C = 19,
            D = 19
        },
        -- 破真空检测
        -- Vacuum-break detection.
        VacuumBreak =
        {
            Enable = 0, --0：关闭，1：开启
            -- 0 = disabled; 1 = enabled.
            Mode = 0,   --IO类型, 0：通用IO，1：末端IO
            -- IO type: 0 = controller/general IO; 1 = end-effector IO.
            A = 20,
            B = 20,
            C = 20,
            D = 20
        }
    }
}
------------------------------------------------------------------------------------------------
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
BIBConveyorCfg =
-- BIB-specific conveyor control configuration: two physical cartons are picked as one logical box.
{
    Enable = true, --false：关闭，true：启用，仅对下方白名单PalletName生效
    -- false = disabled; true = enabled; only effective for the whitelisted PalletName values below.
    DelayTime = 1000, --B1+B2稳定检测时间ms
    -- B1+B2 stable-detection time in ms.

    Sensor =
    {
        B1 = { Mode = 0, A = 1 },  --DI1：右侧第一取料位置
        -- DI1: right-side first pick position.
        B2 = { Mode = 0, A = 6 },  --DI6：左侧第二取料位置
        -- DI6: left-side second pick position.
        B3 = { Mode = 0, A = 19 }  --DI19：第三个纸箱到达检测
        -- DI19: third-carton arrival detection.
    },

    Motor =
    {
        M1 = { Mode = 0, A = 18 }, --DO18：上游输送电机
        -- DO18: upstream conveyor motor.
        M2 = { Mode = 0, A = 19 }  --DO19：中间定位输送电机
        -- DO19: middle positioning conveyor motor.
    }
}
------------------------------------------------------------------------------------------------
-- 产能统计参数。
-- Production statistics parameters.
-- Num保存当前脚本内存中的产能计数；RegisterID对应写入控制器寄存器的地址。
-- Num stores the production counters in script memory; RegisterID defines the controller register addresses used for writing these counters.
-- 产能参数
-- Production parameters.
Capacity =
{
    Num =
    {
        Pallet = 0,
        Box = 0,
        RePallet = 0,
        ReBox = 0
    },
    RegisterID =
    {
        Pallet = 5012,
        Box = 5013
    }
}
-- 延时参数。
-- Delay parameters.
-- Thread用于各线程循环等待；Pick/Place用于吸附、释放、信号稳定等工艺等待。
-- Thread values are used for loop waiting in each thread; Pick/Place values are used for process waits such as suction, release, and signal stabilization.
-- 修改这些时间会直接影响节拍和吸附稳定性。
-- Changing these times directly affects cycle time and suction stability.
-- 延时参数
-- Delay parameters.
Time =
{
    -- 线程等待时间ms。
    -- Thread wait time in ms.
    -- 注意：实体机器人脚本线程不能按8 ms实时刷新理解，现场按约50 ms级别设计；精确计时请使用Systime()。
    -- Note: the real robot script thread should not be treated as an 8 ms real-time loop. Design around about 50 ms; use Systime() for accurate timing.
    Thread =
    {
        s0 = 50,
        s1 = 50,
        s2 = 200,
        s3 = 20,
        s4 = 20
    },
    -- 更换新栈板过程中屏蔽栈板丢失时间s
    -- Time in seconds to mask pallet-loss detection during pallet replacement.
    Pallet =
    {
        Shield = 20
    },
    -- 取料过程等待时间ms
    -- Wait time during the pick process, in ms.
    Pick =
    {
        Pre = 0,
        In = 1500,
        Post = 0
    },
    -- 放料过程等待时间ms
    -- Wait time during the place process, in ms.
    Place =
    {
        In = 1500
    },
    Num =
    {
        Hour = 0,
        Minute = 0,
        Second = 0
    },
    RegisterID =
    {
        Hour = 5014,
        Minute = 5015,
        Second = 5016
    },
    DropDetection = 0 --吸盘延迟检测时间
    -- Delayed sucker detection time.
}
-- 报警信息
-- Alarm information.
ErrorMessage =
{
    Code = 0,         --报警码
    -- Alarm code.
    Type =
    {
        NoErr = 0,            --无报错
        -- No error.
        LinkErr = 1,          --机器人与升降轴通信失败
        -- Communication failure between robot and lifting axis.
        PointErr = 2,         --点位不可达
        -- Point is unreachable.
        PalletErr = 3,        --检测到栈板丢失
        -- Pallet loss detected.
        RestrictErr = 4,      --高度限制功能开启，双侧传送带停止工作
        -- Height-difference limit is active; both conveyors are stopped.
        DropErr = 5,          --物品掉落
        -- Object/material dropped.
        StartErr = 6,         --启动带料
        -- Process started with material already on the end effector.
        PartErr = 7,          --隔板已空/已满
        -- Interlayer magazine is empty or full.
        IPErr = 8,            --创建Modbus通信失败,请检查Modbus地址
        -- Failed to create Modbus communication. Check the Modbus address.
        LiftingErr = 9,       --升降柱运动次数过多
        -- Lifting-column motion count is too high.
        CameraAErr = 10,      --预留相机相关
        -- Reserved for camera-related functions.
        CameraBErr = 11,      --预留相机相关
        -- Reserved for camera-related functions.
        LiftingStateErr = 12, --升降柱状态异常
        -- Abnormal lifting-column status.
        CameraCErr = 13,      --预留相机相关
        -- Reserved for camera-related functions.
        PalletEnableErr = 14, --无栈板启用
        -- No pallet side is enabled.
        LiftingDataErr = 15,  --读取升降柱位置错误
        -- Error reading lifting-column position.
        QueueTimeout = 16,    --队列超时
        -- Queue timeout.
        WorkingDataErr = 17,  --工作数据错误
        -- Working data error.
    },
    PointInfo =
    {
        Type = 0,     --类型
        -- Type.
        Layer = 0,    --层数
        -- Layer count.
        Index = 0,    --序号
        -- Index.
        PalletNum = 0 --工作栈板号
        -- Active pallet number.
    },
    RegisterID =
    {
        Code = 5030,
        Type = 5031,
        Layer = 5032,
        Index = 5033,
        PalletNum = 5034
    }
}
-- 日志级别配置
-- Log level configuration.
LogConfig =
{
    Level =
    {
        DEBUG = 1,
        INFO = 2,
        WARN = 3,
        ERROR = 4
    },
    CurrentLevel = 2, --默认为INFO级别
    -- Default level is INFO.
    Enable = true     --是否启用日志
    -- Whether logging is enabled.
}
------------------------------------------------------------------------------------------
-- 栈板全局变量模板
-- Pallet global-variable template.
-- CreatePalletTemplate会分别生成FirstPallet和SecondPallet。
-- CreatePalletTemplate generates FirstPallet and SecondPallet separately.
-- 两侧栈板结构完全一致，区别只在Pallet字段、Near点和三色灯/传感器默认IO。
-- The left and right pallet structures are identical; they differ only in the Pallet field, Near point, and default tower-light/sensor IO.
------------------------------------------------------------------------------------------
local function CreatePalletTemplate(CPallet, NearJoint)
    -- CPallet：Left或Right，用于标识这份数据属于哪一侧栈板。
    -- CPallet is Left or Right and identifies which pallet side this data belongs to.
    -- NearJoint：靠近该侧栈板的安全关节点，用于初始靠近或异常恢复。
    -- NearJoint is a safe joint point near that pallet side, used for initial approach or abnormal recovery.
    return {
        StateValue =
        {
            Status = 5, --栈板状态, 初始化:StateType.Idle
            -- Pallet status, initialized as StateType.Idle.
            Enable = 0  --栈板使能状态，0：禁用，1：使能
            -- Pallet enable status: 0 = disabled; 1 = enabled.
        },

        State =
        {
            Init = false,       --数据初始化
            -- Data initialization flag.
            StateReady = false, --准备状态
            -- Ready state.
            Done = false,       --完成状态
            -- Completion state.
            Replace = false,    --更换栈板状态
            -- Pallet replacement state.
            InPlaceOK = false,  --栈板到位确认标志
            -- Pallet-in-place confirmation flag.
            FReset = false,     --第一次判断栈板是否移开
            -- First check whether the pallet has been removed.
            SReset = false,     --第二次判断栈板是否到位
            -- Second check whether the pallet is in place.
            LosePallet = false  --栈板丢失标志位
            -- Pallet-loss flag.
        },

        ProcessNum =
        {
            BoxCount = 0,             --托盘箱体计数（初始值）
            -- Pallet box count, initial value.
            PalletBoxCount = 0,       --产能料箱计数
            -- Production box counter.
            InitBoxCount = 0,         --托盘箱体计数（初始值）
            -- Pallet box count, initial value.
            RemainingAddBoxCount = 0, --双吸双放料箱额外初始计数
            -- Extra initial counter for double-suction/double-place boxes.
            TotalBoxNum = 0,          --托盘单侧箱体总数（上传至Modbus寄存器）
            -- Total number of boxes for one pallet side, uploaded to Modbus registers.
            PalletLength = 0,         --托盘信息（上位机配置）
            -- Pallet information configured by the upper-level system.
            PalletWidth = 0,          --托盘信息（上位机配置）
            -- Pallet information configured by the upper-level system.
            PalletHeight = 0,         --托盘信息（上位机配置）
            -- Pallet information configured by the upper-level system.
            PartitionNum = 10,        --隔板最大数量（上位机配置）
            -- Maximum interlayer quantity configured by the upper-level system.
            PartitionHeight = 0,      --隔板高度（上位机配置）
            -- Interlayer height configured by the upper-level system.
            PartitionWeight = 0.1       --隔板重量（上位机配置） ERM interlayer
            -- Interlayer weight configured by the upper-level system.
        },

        PalletNum =
        {
            NextBoxCount = 1, --栈板下一个箱体计数（上传至Modbus寄存器）
            -- Next box count for the pallet, uploaded to Modbus registers.
            AddBoxCount = 0,  --双吸双放料箱额外计数（上传至Modbus寄存器）
            -- Extra counter for double-suction/double-place boxes, uploaded to Modbus registers.
            LayerCount = 0,   --托盘层数计数，表示多少层已放满（上传至Modbus寄存器）
            -- Pallet layer counter indicating how many layers have been completed, uploaded to Modbus registers.
            LayerBoxNum = 0,  --从首层到当前层理论最大箱体序号数（上传至Modbus寄存器）
            -- Theoretical maximum box index from the first layer to the current layer, uploaded to Modbus registers.
            RemainBoxNum = 0  --托盘不满一层箱体的数量（上传至Modbus寄存器）
            -- Number of boxes in the incomplete current layer, uploaded to Modbus registers.
        },

        BoxProperty =
        {
            BoxLength = 0, --箱体信息（上位机配置）
            -- Box information configured by the upper-level system.
            BoxWidth = 0,  --箱体信息（上位机配置）
            -- Box information configured by the upper-level system.
            BoxHigh = 0,   --箱体信息（上位机配置）
            -- Box information configured by the upper-level system.
            BoxWeight = 0, --箱体信息（上位机配置）
            -- Box information configured by the upper-level system.
            OffsetX = 100, --目标点偏移量
            -- Target point offset.
            OffsetY = 100,
            OffsetZ = 200,
            Sucker = 0,       --吸盘属性，-1：n吸n单放，0：n吸单放，1：长边对齐双放，2：短边对齐双放，3：长边对齐三放，4：短边对齐三放，5：长边对齐四放，:6：短边对齐四放
            -- Sucker placement attribute: -1 = pick N and place N one by one; 0 = pick N and place once; 1/2 = double place aligned by long/short side; 3/4 = triple place aligned by long/short side; 5/6 = quadruple place aligned by long/short side.
            BoxDirection = 0, --箱子来料方向，0：箱体长边与来料方向垂直，1：箱体短边与来料方向垂直
            -- Box infeed direction: 0 = box long side is perpendicular to the infeed direction; 1 = box short side is perpendicular to the infeed direction.
        },

        AutoGenPoint =
        {
            TransPoint = {
                {}
            },
            PartTransPoint = {
                {}
            }
        },
        TeachPoint = {
            TransPlacePoint =
            {
                pose =
                {
                    {}, {}, {}, {}, {}
                },
                joint =
                {
                    {}, {}, {}, {}, {}
                },
                mode = {}
            }, --栈板层示教过渡点（上位机配置）
            -- Taught transition points for pallet layers, configured by the upper-level system.

            TransPartitionPoint =
            {
                pose =
                {
                    {}, {}, {}, {}, {}
                },
                joint =
                {
                    {}, {}, {}, {}, {}
                },
                mode = {}
            }, --隔板示教过渡点（上位机配置）
            -- Taught transition points for interlayer motion, configured by the upper-level system.

            TeachPickPoint =
            {
                pose = {},
                joint = {}
            }, --示教点，码垛：箱体抓取点、卸垛：箱体放置点（上位机配置）
            -- Taught point: for palletizing it is the box pick point; for depalletizing it is the box place point. Configured by the upper-level system.

            TeachPartitionPickPoint =
            {
                pose = {},
                joint = {}
            }, --示教点，码垛：隔板抓取点、卸垛：隔板放置点（上位机配置）
            -- Taught point: for palletizing it is the interlayer pick point; for depalletizing it is the interlayer place point. Configured by the upper-level system.

            TeachPartitionPlacePoint =
            {
                pose = {},
                joint = {}
            } --示教点，码垛：隔板放置点、卸垛：隔板抓取点（上位机配置）
            -- Taught point: for palletizing it is the interlayer place point; for depalletizing it is the interlayer pick point. Configured by the upper-level system.
        },

        Mode = 1,                   --工作模式，1：码垛，2：拆垛
        -- Work mode: 1 = palletizing; 2 = depalletizing.
        Pallet = CPallet,           --栈板标志，0：左侧，1：右侧
        -- Pallet side flag: 0 = left side; 1 = right side.
        OffsetHeight = 100,         --栈板放置点（拆垛抓取点）偏移高度
        -- Offset height for pallet place points, or depalletizing pick points.
        TransPointMode = 0,         --过渡点获取方式，0：示教，1：自动生成
        -- Transition-point source: 0 = taught; 1 = automatically generated.
        TransPlacePointNum = 1,     --放料过渡点数量
        -- Number of place transition points.
        TransPartPointMode = 0,     --隔板过渡点获取方式，0：示教，1：自动生成
        -- Interlayer transition-point source: 0 = taught; 1 = automatically generated.
        TransPartitionPointNum = 1, --隔板过渡点数量
        -- Number of interlayer transition points.
        -- 隔板配置
        -- Interlayer configuration.
        Partition =
        {
            Enable = false,         --隔板功能，false: 关闭，true：开启
            -- Interlayer feature: false = disabled; true = enabled.
            Layer = {},             --隔板放置层位置
            -- Layers where interlayers should be placed.
            Mode = 0,               --隔板标志位，0：常规点位，1: 隔板点位
            -- Interlayer point flag: 0 = normal points; 1 = interlayer points.
            Last = false,           --最后隔板运动信号
            -- Final interlayer motion signal.
            LastPlan = false,       --规划最后隔板运动信号
            -- Planned final interlayer motion signal.
            Place = 0,              --隔板放置结果，0：未放置，1：已放置
            -- Interlayer placement result: 0 = not placed; 1 = placed.
            RePartNum = 0           --剩余隔板数量
            -- Remaining interlayer quantity.
        },
        MultSensorFunction = 0,     --多传感器功能 0：关闭， 1：开启
        -- Multi-sensor feature: 0 = disabled; 1 = enabled.
        Layer = 0,                  --码垛总层数
        -- Total palletizing layer count.
        CompensateZData = 0,        --开始补偿放置位置Z轴向大小
        -- Start value for Z-axis placement compensation.
        CompensateLayer = 0,        --开始补偿放置位置Z轴向的层数
        -- Layer number from which Z-axis placement compensation starts.
        J4UpperLimit = 0,           --关节4允许极限角上限（暂不启用）
        -- Upper allowed limit for joint 4, currently unused.
        J4LowerLimit = 0,           --关节4允许极限角下限（暂不启用）
        -- Lower allowed limit for joint 4, currently unused.
        Near = { joint = NearJoint },

        Coordinate =
        {
            PartitionUserNum = 0, --选择隔板的User编号
            -- Selected user frame number for interlayer motion.
            UserNum = 0,          --选择的User编号
            -- Selected user frame number.
            ToolNum = 0           --选择的TCP编号
            -- Selected TCP/tool number.
        },

        BoxBeInpPlaceDI1 = 1,   --箱体到位检测DI 1
        -- Box in-position detection DI 1.
        BoxBeInpPlaceDI2 = 2,   --箱体到位检测DI 2
        -- Box in-position detection DI 2.
        BoxBeInpPlaceDI3 = 1,   --箱体到位检测DI 1
        -- Box in-position detection DI 1.
        BoxBeInpPlaceDI4 = 2,   --箱体到位检测DI 2
        -- Box in-position detection DI 2.
        InPlaceA = 3,           --栈板到位信号DI 3
        -- Pallet in-position signal DI 3.
        InPlaceB = 4,           --栈板到位信号DI 4
        -- Pallet in-position signal DI 4.
        InPlaceOK = 9,          --栈板放置确认按钮DI 9
        -- Pallet placement confirmation button DI 9.
        RestrictMoveSignal = 23, --限制垛型高度信号
        -- Stack-height limit signal.
        -- 安全IO配置
        -- Safety IO configuration.
        SafeCfg =
        {
            Grating = {
                Enable = false, --false：关闭，true：打开
                -- false = disabled; true = enabled.
                Port =
                {
                    Mode = 0, --IO类型, 0：通用DI
                    -- IO type: 0 = general DI.
                    A = 23
                }
            },
            LiDAR = {
                Enable = false, --false：关闭，true：打开
                -- false = disabled; true = enabled.
                Port =
                {
                    Mode = 0, --IO类型, 0：通用DO
                    -- IO type: 0 = general DO.
                    A = 8,
                    B = 9
                }
            },
        }
    }
end
------------------------------------------------------------------------------------------
--左侧栈板全局变量
-- Left pallet global variable.
------------------------------------------------------------------------------------------
FirstPallet = CreatePalletTemplate(Left, { 135, 5, 90, 0, -90, -10 })
FirstPallet.TriLight =
{
    Yellow = 1, --栈板三色灯黄灯DO 1
    -- Pallet tower-light yellow DO 1.
    Green = 2,  --栈板三色灯绿灯DO 2
    -- Pallet tower-light green DO 2.
    Red = 3     --栈板三色灯红灯DO 3
    -- Pallet tower-light red DO 3.
}

FirstPallet.RegisterID =
{
    PalletStatus = 5000, --码垛状态寄存器地址
    -- Palletizing status register address.
    Layer = 5002,        --当前码垛层数寄存器地址
    -- Current palletizing layer register address.
    RemainBoxNum = 5003, --当前层剩余料箱寄存器地址
    -- Remaining boxes in current layer register address.
    PalletEnable = 5007, --使能栈板寄存器地址
    -- Pallet enable register address.
    NextBoxCount = 5010, --下一个箱体数寄存器地址
    -- Next box number register address.
    LayerBoxNum = 5020,  --首层到当前层最大箱体序号数量寄存器地址
    -- Register address for the maximum box index from the first layer to the current layer.
    AddBoxCount = 5022,  --双吸双放料箱额外计数寄存器地址
    -- Register address for the extra counter of double-suction/double-place boxes.
    RePartNum = 5024,    --隔板数量寄存器地址
    -- Interlayer quantity register address.
    PlaceButton = 5038   --栈板确认按钮状态地址
    -- Pallet confirmation button status address.
}
------------------------------------------------------------------------------------------
--右侧栈板全局变量
-- Right pallet global variable.
------------------------------------------------------------------------------------------
SecondPallet = CreatePalletTemplate(Right, { 45, 5, 90, 0, -90, -10 })
SecondPallet.TriLight =
{
    Yellow = 4, --栈板三色灯黄灯DO 4
    -- Pallet tower-light yellow DO 4.
    Green = 5,  --栈板三色灯绿灯DO 5
    -- Pallet tower-light green DO 5.
    Red = 6     --栈板三色灯红灯DO 6
    -- Pallet tower-light red DO 6.
}

SecondPallet.RegisterID =
{
    PalletStatus = 5001, --码垛状态寄存器地址
    -- Palletizing status register address.
    Layer = 5004,        --当前码垛层数寄存器地址
    -- Current palletizing layer register address.
    RemainBoxNum = 5005, --当前层剩余料箱寄存器地址
    -- Remaining boxes in current layer register address.
    PalletEnable = 5009, --使能栈板寄存器地址
    -- Pallet enable register address.
    NextBoxCount = 5011, --下一个箱体数寄存器地址
    -- Next box number register address.
    LayerBoxNum = 5021,  --首层到当前层最大箱体序号数量寄存器地址
    -- Register address for the maximum box index from the first layer to the current layer.
    AddBoxCount = 5023,  --双吸双放料箱额外计数寄存器地址
    -- Register address for the extra counter of double-suction/double-place boxes.
    RePartNum = 5025,    --隔板数量寄存器地址
    -- Interlayer quantity register address.
    PlaceButton = 5039   --栈板确认按钮状态地址
    -- Pallet confirmation button status address.
}
-------------------------------------------------------------------------------------------
--通讯相关全局变量
-- Communication-related global variables.
-------------------------------------------------------------------------------------------
Communication =
{
    Lifting =
    {
        RestrictMoveFlag = false, --限制运动标志位
        -- Motion restriction flag.
        StartHeightDiff = 1500,   --开始高度差
        -- Starting height difference.
        EndHeightDiff = 1000,     --结束高度差
        -- Ending height difference.
        TimesPerHour = 0,         --升降柱每小时运动次数
        -- Number of lifting-column motions per hour.
        MaxtimesPerHour = 35,     --升降柱每小时最大运动次数
        -- Maximum number of lifting-column motions per hour.
        CMaxDis = 0,              --升降柱参数
        -- Lifting-column parameters.
        StopFlag = false,         --升降柱停止标志位
        -- Lifting-column stop flag.
        Mode = 0,                 --升降柱型号选择，0：EWELLIX，1：GeMinG，2：ZT3ILC, 3:LINAK
        -- Lifting-column model selection: 0 = EWELLIX; 1 = GeMinG; 2 = ZT3ILC; 3 = LINAK.
        Brand =
        {
            EWELLIX =
            {
                Tcp =
                {
                    Ip = "192.168.5.100", --升降柱通讯IP
                    -- Lifting-column communication IP address.
                    Port = 50001,         --升降柱通讯端口
                    -- Lifting-column communication port.
                    Socket = 0,           --升降柱通讯
                    -- Lifting-column communication.
                },
                MaxDistance = 900,        --升降柱最大运动高度
                -- Maximum lifting-column travel height.
                Command =
                {
                    GetStatus = "get_status\n",
                    StopMoving = "stop_moving\n",
                    GetPosition = "get_position\n",
                    MovePosition = "moveTo_absolutePosition,\n"
                }
            },

            GeMinG =
            {
                ModbusRTU =
                {
                    Id = 0,           --主站设备号
                    -- Master device ID.
                    SlaveId = 1,      --从站ID
                    -- Slave ID.
                    BaudRate = 57600, --RS485波特率 9600/19200/57600/115200
                    -- RS485 baud rate: 9600/19200/57600/115200.
                    Parity = "N",     --"N": 无校验/"O": 奇校验/"E": 偶校验
                    -- "N" = no parity; "O" = odd parity; "E" = even parity.
                    DataBit = 8,      --数据位
                    -- Data bits.
                    StopBit = 1       --停止位 1/2
                    -- Stop bits: 1 or 2.
                },
                MaxDistance = 700     --升降柱最大运动高度
                -- Maximum lifting-column travel height.
            },

            ZT3ILC =
            {
                Modbus =
                {
                    Id = 0,               --主站设备号
                    -- Master device ID.
                    Ip = "192.168.5.100", --通讯IP
                    -- Communication IP address.
                    Port = 502            --通讯端口
                    -- Communication port.
                },
                MaxDistance = 900         --升降柱最大运动高度
                -- Maximum lifting-column travel height.
            },

            LINAK =
            {
                Modbus =
                {
                    Id = 0,               --主站设备号
                    -- Master device ID.
                    Ip = "192.168.5.123", --通讯IP
                    -- Communication IP address.
                    Port = 502            --通讯端口
                    -- Communication port.
                },
                MaxDistance = 900,        --升降柱最大运动高度
                -- Maximum lifting-column travel height.
                HeartBeatTimes = 0        --心跳计数
                -- Heartbeat counter.
            }
        }

    },

    Controller =
    {
        Modbus =
        {
            Id = 0,             --主站设备号
            -- Master device ID.
            Ip = "192.168.5.11", --通讯IP
            -- Communication IP address.
            Port = 502,         --通讯端口
            -- Communication port.
            LinkState = false   --连接状态
            -- Connection status.
        }
    },

    Sucker =
    {
        Tcp =
        {
            Ip = "127.0.0.1",  --通讯IP
            -- Communication IP address.
            Port = 60000,      --通讯端口
            -- Communication port.
            Socket = 0,
            BaudRate = 115200, --RS485波特率 9600/19200/57600/115200
            -- RS485 baud rate: 9600/19200/57600/115200.
            Parity = "N",      --"N": 无校验/"O": 奇校验/"E": 偶校验
            -- "N" = no parity; "O" = odd parity; "E" = even parity.
            DataBit = 8,       --数据位
            -- Data bits.
            StopBit = 1,       --停止位 1/2
            -- Stop bits: 1 or 2.
        },
        Command =
        {
            ReadPDI = { 0x01, 0x04, 0x00, 0x00, 0x00, 0x28, 0xd8 },
            ReadPDO = { 0x01, 0x04, 0x00, 0x00, 0x00, 0x29, 0xdf },
            VacuumOn = { 0x01, 0x07, 0x00, 0x01, 0x00, 0x29, 0x02, 0x01, 0x00, 0x82 },
            VacuumOff = { 0x01, 0x07, 0x00, 0x01, 0x00, 0x29, 0x02, 0x00, 0x00, 0x97 }
        }
    }
}

-----------------
--仿真过程全局变量
-- Simulation-process global variables.
-----------------
SimulateProcess = {
    Id = '1',
    State = 0,                                     -- 0: 空闲 1: 运行中 2:停止
    -- 0 = idle; 1 = running; 2 = stopped.
    MqttConnected = 0,                              -- 0: 未连接 1: 已连接 
    -- 0 = disconnected; 1 = connected.
    SimulateSpeed = 1,
    SimulateTime = 1000,
    Conveyor = {            
        Speed = 5000,                            --传送带速度
        -- Conveyor speed.
        Length = 2500,                           --传送带长度
        -- Conveyor length.
        BoxInterval = 5,                        --箱子之间间隔
        -- Spacing between boxes.
        Container = {},                           --容器
        -- Container.
        FirstBoxArrived = nil,                               --0: 未到达   1已到达
        -- 0 = not arrived; 1 = arrived.
        SecondBoxArrived = nil,                              --0: 未到达   1已到达
        -- 0 = not arrived; 1 = arrived.
        BoxArrived = {},
        PickDelayTime = 0,
        PlaceDelayTime = 0
    },    
    Conveyor1 = {            
        Speed = 5000,                            --传送带速度
        -- Conveyor speed.
        Length = 2500,                           --传送带长度
        -- Conveyor length.
        BoxInterval = 5,                        --箱子之间间隔
        -- Spacing between boxes.
        Container = {},                          --容器
        -- Container.
        FirstBoxArrived = nil,                     --0: 未到达   1已到达
        -- 0 = not arrived; 1 = arrived.
        SecondBoxArrived = nil,                    --0: 未到达   1已到达
        -- 0 = not arrived; 1 = arrived.
        BoxArrived = {},
        PickDelayTime = 0,
        PlaceDelayTime = 0
    },
    LiftingColumn = {
        Speed = 100,                              --抬升速度
        -- Lifting speed.
        Length = 900,                             --最大抬升高度
        -- Maximum lifting height.
        LiftingHeight = 0,                        --抬升高度
        -- Lifting height.
        UsedTime = 0                              --抬升时间
        -- Lifting time.
    },
    GenerateInterval = 500,
    PickDelayTime = 0,                                     --等待箱子被拿走时间
    -- Time to wait for the box to be removed.
    BoxOnRobot = {},                              --在机械臂上的箱子
    -- Boxes currently on the robot arm.
    LeftPallet = {                  
        Container = {},
        CanCount = 1                                   --1:剁数可被计数，--0：不计被计数
        -- 1 = pallet count can be counted; 0 = pallet count is not counted.
    },
    RightPallet = {
        Container = {},
        CanCount = 1                                   --1:剁数可被计数，--0：不计被计数
        -- 1 = pallet count can be counted; 0 = pallet count is not counted.
    },
    LayerNum = 1,                                   --当前操作层数
    -- Current operating layer number.
    LayerBoxIndex = 0,                              --当前层的箱子索引
    -- Box index in the current layer.
    LayerBoxNum = 0,                                --首层到当前层搬运的箱子数
    -- Number of boxes moved from the first layer to the current layer.
    BoxCount = 0,                                   --已经搬运的箱子数量
    -- Number of boxes already moved.
    PickIndex = 1,                                   --吸取索引
    -- Pick index.
    PresentConveyor = {},                            --当前传送带
    -- Current conveyor.
    Regs = {},
    Capacity = {
        FirstPallet = {
            Layer = 1,
            Box = 0
        },
        SecondPallet = {
            Layer = 1,
            Box = 0
        }
    },
    Statistic = {                                    --只统计没加速的时候
    -- Only counted when acceleration/speed-up is not applied.
        FirstArrived = 0,                            --是否第一个箱子已到达
        -- Whether the first box has arrived.
        BoxCount = 0,                                --总码垛的箱子数
        -- Total number of palletized boxes.
        TotalTime = 0,                               --总耗时
        -- Total elapsed time.
        LayerRate = 0,                               --码垛完一层时平均节拍
        -- Average cycle time when one layer is completed.
        PalletNum = 0,                               --剁数
        -- Pallet/stack count.
        PalletTotalTime = 0,                          --剁有效计时
        -- Valid timing for the pallet/stack.
        PalletRate = 0                               --单栈板耗时
        -- Elapsed time for one pallet.
    },    
}

SimulateMode = 1
FirstPalletBoxDirection = 0
SecondPalletBoxDirection = 0
ConnectId = 'simulation'
BoxId = 0

Box = {
    Id = 0,
    Type = 0,    -- 0: 单个箱子    1：2个箱子   2:3个箱子   3:4个箱子
    -- 0 = single box; 1 = two boxes; 2 = three boxes; 3 = four boxes.
    Location =  0,
    Conveyor = 0, -- 0: 0号传送带 1: 1号传送带
    -- 0 = conveyor 0; 1 = conveyor 1.
    State = 0,   -- 0: 在传送带上， 1：在机械臂上  2：在栈板上 3: 销毁
    -- 0 = on conveyor; 1 = on robot arm; 2 = on pallet; 3 = destroyed.
    Pallet = 1,  -- 所属栈板
    -- Assigned pallet side.
    Layer = 1,
    Index = 1,
    Child = 0,   -- 0: 子0, 1: 子1
    -- 0 = child 0; 1 = child 1.
    Pose = {}      -- 箱子最终位姿
    -- Final box pose.
}

function Box:new(Type, Location, Conveyor, Length, Width)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.Id = BoxId
    BoxId = BoxId + 1
    o.Type = Type
    o.Location = Location
    o.Conveyor = Conveyor
    o.Length = Length
    o.Width = Width
    o.Layer = 1
    o.Index = 1
    o.PickIndex = 1
    o.Child = 0
    o.Pose = {}
    return o
end

function Box:setId (id)
    self.Id = id
end

function Box:setLayer (layer)
    self.Layer = layer
end

function Box:setIndex (index)
    self.Index = index
end

function Box:setChild (child)
    self.Child = child
end

function Box:setPickIndex (index)
    self.PickIndex = index
end

function Box:setState (state)
    self.State = state
end

function Box:setPallet (pallet)
    self.Pallet = pallet
end

function Box:setPose (pose)
    for k, v in pairs(pose) do
        self.Pose[#self.Pose+1] = v
    end
end

---------------------------------------------------------------
--发送清空栈板消息
-- Send message to clear the pallet.
function PublishClearAction(palletNum)
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id .. ':clearPallets', "[" .. palletNum .. "]", 0, false)
end

---------------------------------------------------------------
--发送填充栈板消息
-- Send message to fill the pallet.
function PublishFillAction(palletNum)
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id .. ':fillPallets', "[" .. palletNum .. "]", 0, false)
end

---------------------------------------------------------------
--延时
-- Delay.
function SWait(Ms)
    Wait(math.ceil(Ms / SimulateProcess.SimulateSpeed))
end

-----------------------------------------------------------------------------------------
--队列全局变量
-- Queue global variables.
-----------------------------------------------------------------------------------------
--定义队列类
-- Define the queue class.
function CreateQueue()
    local Queue = {}
    Queue.__index = Queue

    function Queue.New()
        return setmetatable({
            _data = {},
            _head = 1,      -- 指向下一个要弹出的元素
            -- Points to the next element to be popped.
            _tail = 1,      -- 指向下一个要插入的位置
            -- Points to the next insertion position.
            _locked = false --自旋锁标志
            -- Spin-lock flag.
        }, Queue)
    end

    ------------------------------------------------
    --内部方法
    -- Internal methods.
    ------------------------------------------------
    --获取锁
    -- Acquire the lock.
    function Queue:_acquireLock()
        local startTime = os.clock()
        while (self._locked) do
            if (os.clock() - startTime) > 5 then
                Alarm("Queue lock timeout", ErrorMessage.Type.QueueTimeout)
            end
            Wait(1) -- 短暂等待，让出执行权
            -- Wait briefly to yield execution.
        end
        self._locked = true
    end

    --释放锁
    -- Release the lock.
    function Queue:_releaseLock()
        self._locked = false
    end

    -- 内部队列是否为空的检查
    -- Internal check for whether the queue is empty.
    function Queue:_isEmpty()
        return self._head >= self._tail
    end

    --压缩存储空间
    -- Compact the storage space.
    function Queue:_compact()
        local NewData = {}
        local NewIndex = 1
        for i = self._head, self._tail - 1 do
            NewData[NewIndex] = self._data[i]
            NewIndex = NewIndex + 1
        end
        self._data = NewData
        self._tail = NewIndex
        self._head = 1
    end

    ------------------------------------------------
    --外部方法
    -- External methods.
    ------------------------------------------------
    --添加元素到队列尾部
    -- Add an element to the tail of the queue.
    function Queue:Push(Value)
        if (Value == nil) then
            Alarm("Queue Push Point Error!", ErrorMessage.Type.PointErr)
        end
        self:_acquireLock()
        self._data[self._tail] = Value
        self._tail = self._tail + 1
        self:_releaseLock()
    end

    --从队列头部弹出元素（消费后即丢弃）
    -- Pop an element from the head of the queue; it is discarded after consumption.
    function Queue:Pop()
        self:_acquireLock()
        if self:_isEmpty() then
            self:_releaseLock()
            LogWarn("Queue Pop Point Error!")
            return nil
        end

        local Value = self._data[self._head]
        self._data[self._head] = nil -- 显式设置为nil，帮助垃圾回收
        -- Explicitly set to nil to help garbage collection.
        self._head = self._head + 1

        -- 定期压缩存储空间（当空余空间太多时）
        -- Periodically compact the storage space when there is too much unused space.
        if self._head > 1 and self._head > #self._data / 2 then
            self:_compact()
        end

        self:_releaseLock()
        return Value
    end

    --查看队列头部元素但不弹出
    -- Peek at the head element without popping it.
    function Queue:Peek()
        self:_acquireLock()
        if self:_isEmpty() then
            self:_releaseLock()
            LogWarn("Queue Peek Point Error!")
            return nil
        end
        local Value = self._data[self._head]
        self:_releaseLock()
        return Value
    end

    --判断队列是否为空
    -- Check whether the queue is empty.
    function Queue:IsEmpty()
        self:_acquireLock()
        local Result = self._head >= self._tail
        self:_releaseLock()
        return Result
    end

    --获取队列当前大小
    -- Get the current queue size.
    function Queue:Size()
        self:_acquireLock()
        local Size = self._tail - self._head
        self:_releaseLock()
        return Size
    end

    --清空队列
    -- Clear the queue.
    function Queue:Clear()
        self:_acquireLock()
        self._data = {}
        self._head = 1
        self._tail = 1
        self:_releaseLock()
    end

    return Queue
end

--创建队列类
-- Create the queue class.
AQueue = CreateQueue()
--栈板1队列
-- Pallet 1 queue.
FQueue = AQueue.New()

--创建队列类
-- Create the queue class.
BQueue = CreateQueue()
--栈板2队列
-- Pallet 2 queue.
SQueue = BQueue.New()
----------------------------------------------------------------------------------------
--公共函数
-- Common functions.
----------------------------------------------------------------------------------------
--清除table
-- Clear a table.
function DeepClear(T)
    if type(T) ~= "table" then
        LogWarn("Point type is not table!")
        return
    end
    for k, v in pairs(T) do
        local vt = type(v)
        if vt == "table" then
            for m, n in pairs(v) do
                v[m] = {}
            end
        else
            T[k] = 0
        end
    end
end

---------------------------------------------------------------
--复制table
-- Deep-copy a table.
function DeepCopy(original)
    local cache = {}
    local function copy(obj)
        if type(obj) ~= "table" then return obj end
        if cache[obj] then return cache[obj] end
        local newTable = {}
        cache[obj] = newTable
        for k, v in pairs(obj) do
            newTable[copy(k)] = copy(v)
        end
        return setmetatable(newTable, getmetatable(obj))
    end
    return copy(original)
end

---------------------------------------------------------------
--获取表中变量名称
-- Get variable names from a table.
function GetTableKey(T, Value)
    for k, v in pairs(T) do
        if v == Value then
            return k
        end
    end
    LogInfo("Value: %s", Value)
    LogInfoTable("table:", T)
    Alarm("GetTableKey Error!", ErrorMessage.Type.WorkingDataErr)

    return 0
end
---------------------------------------------------------------
--检查table中存在非0 数据
-- Check whether a table contains non-zero data.
function CheckTableData(T)
    for k, v in pairs(T) do
        if (v ~= 0) and (v ~= nil) then
            return 1
        end
    end
    return 0
end

---------------------------------------------------------------
--字符串分割
-- Split a string.
function Split(Str, Sep)
    local SIndex = 1
    local SPIndex = 1
    local SPData = {}
    while true do
        if (Communication.Lifting.StopFlag == true and SPIndex > 100) then
            break
        end
        local PreIndex = string.find(Str, Sep, SIndex)
        if not PreIndex then
            SPData[SPIndex] = string.sub(Str, SIndex, string.len(Str))
            break
        end
        SPData[SPIndex] = string.sub(Str, SIndex, PreIndex - 1)
        SIndex = PreIndex + string.len(Sep)
        SPIndex = SPIndex + 1
    end
    return SPData, SPIndex
end
---------------------------------------------------------------
--日志管理函数
-- Log management functions.
---------------------------------------------------------------
--设置日志级别
-- Set the log level.
function SetLogLevel(Level)
    if LogConfig.Level[Level] then
        LogConfig.CurrentLevel = LogConfig.Level[Level]
    else
        print("Invalid log level: " .. tostring(Level))
    end
end

---------------------------------------------------------------
--通用日志打印函数
-- Generic log output function.
function Log(Level, Message, ...)
    if not LogConfig.Enable then
        return
    end

    local LevelValue = LogConfig.Level[Level]
    if not LevelValue then
        print("Invalid log level: " .. tostring(Level))
        return
    end

    if LevelValue >= LogConfig.CurrentLevel then
        local FormattedMessage = string.format(Message, ...)
        --local Timestamp = os.date("%Y-%M-%D %H:%M:%S")
        local PalletType = (WorkType.Pallet == FirstPallet.Mode) and "Palletizing" or "DePalletizing"
        print(string.format("[%s] [%s] %s\r\n", PalletType, Level, FormattedMessage))
    end
end

-----------------------------------------------------------------
--便捷日志函数
-- Convenience log functions.
function LogDebug(Message, ...)
    Log("DEBUG", Message, ...)
end

function LogInfo(Message, ...)
    Log("INFO", Message, ...)
end

function LogWarn(Message, ...)
    Log("WARN", Message, ...)
end

function LogError(Message, ...)
    Log("ERROR", Message, ...)
end
function LogDebugTable(Message, TableName)
    local LevelValue = LogConfig.Level["DEBUG"]
    if LevelValue >= LogConfig.CurrentLevel then
        local PalletType = (WorkType.Pallet == FirstPallet.Mode) and "[Palletizing]" or "[DePalletizing]"
        print(PalletType .. " [DEBUG]", Message, TableName)
    end
end
function LogInfoTable(Message, TableName)
    local LevelValue = LogConfig.Level["INFO"]
    if LevelValue >= LogConfig.CurrentLevel then
        local PalletType = (WorkType.Pallet == FirstPallet.Mode) and "[Palletizing]" or "[DePalletizing]"
        print(PalletType .. " [INFO]", Message, TableName)
    end
end
---------------------------------------------------------------
--升降柱命令
-- Lifting-column commands.
---------------------------------------------------------------
--EWELLIX
---------------------------------------------------------------
--升降柱初始化
-- Initialize the lifting column.
function EWLInit()
    return TCPStart(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5) --建立TCP连接
    -- Establish a TCP connection.
end

---------------------------------------------------------------
--升降柱使能
-- Enable the lifting column.
function EWLEnable(PowerOn)
    if PowerOn == 0 then
        TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
            Communication.Lifting.Brand.EWELLIX.Command.StopMoving)
    end
end

---------------------------------------------------------------
--获取升降柱位置
-- Get the lifting-column position.
function EWLGetPosition()
    local Err = 0
    local EHeight = {}
    local ResultLength = 0
    local EHeightResult = {}

    TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
        Communication.Lifting.Brand.EWELLIX.Command.GetPosition)
    Err, EHeight = TCPRead(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5, "string")
    EHeightResult, ResultLength = Split(EHeight, ",")

    local Res = tonumber(EHeightResult[3])
    if (Res == nil) then
        for n = 1, 10 do
            LogWarn("EWLGetPosition data is %s, split data is %s!", EHeight, EHeightResult)
            TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                Communication.Lifting.Brand.EWELLIX.Command.GetPosition)
            Err, EHeight = TCPRead(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5, "string")
            EHeightResult, ResultLength = Split(EHeight, ",")
            for i = 1, ResultLength do
                Res = tonumber(EHeightResult[i])
                if (Res ~= nil) then
                    return Err, Res
                end
            end
            Wait(50)
        end
        LogError("EWLGetPosition data is %s, split data is %s!", EHeight, EHeightResult)
        Alarm("EWLGetPosition Error!", ErrorMessage.Type.LiftingDataErr)
    end
    return Err, Res
end

---------------------------------------------------------------
--运动升降柱位置
-- Move the lifting column to the target position.
function EWLRun(Postion)
    local HRes = tostring(Postion)
    TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
        Communication.Lifting.Brand.EWELLIX.Command.MovePosition .. HRes .. "\n")
end

---------------------------------------------------------------
--GeMinG
---------------------------------------------------------------
--升降柱初始化
-- Initialize the lifting column.
function SV660CInit()
    local CurrentId = Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId
    SetHoldRegs(CurrentId, 0x030a, 1, { 0 }, "U16")
    SetHoldRegs(CurrentId, 0x0200, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x0C09, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x0C0a, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x1700, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x0500, 1, { 2 }, "U16")
    SetHoldRegs(CurrentId, 0x1100, 1, { 5 }, "U16")
    SetHoldRegs(CurrentId, 0x1702, 1, { 28 }, "U16")
    SetHoldRegs(CurrentId, 0x110e, 1, { 1200 }, "U16")
    SetHoldRegs(CurrentId, 0x110f, 1, { 500 }, "U16")
    SetHoldRegs(CurrentId, 0x1104, 1, { 1 }, "U16")
end

---------------------------------------------------------------
--升降柱使能
-- Enable the lifting column.
function SV660CEnable(PowerOn)
    local CurrentId = Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId
    if PowerOn == 1 then
        SetHoldRegs(CurrentId, 0x3100, 1, { 1 }, "U16")
    else
        SetHoldRegs(CurrentId, 0x3100, 1, { 0 }, "U16")
    end
end

---------------------------------------------------------------
--获取升降柱位置
-- Get the lifting-column position.
function SV660CGetPostion()
    local Data = GetHoldRegs(Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId, 0x0b07, 2, "U32")
    if (Data[1] == nil) then
        Alarm("Lifting Data Error!", ErrorMessage.Type.LiftingDataErr)
    end

    return Data
end

---------------------------------------------------------------
--运动升降柱位置
-- Move the lifting column to the target position.
function SV660CRun(Postion)
    local CurrentId = Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId
    if Postion == nil then
        Alarm("Postion is nil!", ErrorMessage.Type.LiftingDataErr)
    end
    SetHoldRegs(CurrentId, 0x110c, 2, { Postion }, "U32")
    SetHoldRegs(CurrentId, 0x3100, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x3100, 1, { 3 }, "U16")
end

---------------------------------------------------------------
--ZT3ILC_ZC01
---------------------------------------------------------------
--32位单精度浮点数转化成十六进制整数
-- Convert a 32-bit single-precision float into a hexadecimal integer.
function ConvertSigned(Value)
    local HexString = string.format("%08X", string.unpack(">I", string.pack(">f", Value))) -- 将浮点数转换为十六进制字符串
    -- Convert the float value into a hexadecimal string.
    HexString = string.sub(HexString, 1, string.len(HexString) - 4)

    return tonumber(HexString, 16) -- 将十六进制字符串转换为十进制整数
    -- Convert the hexadecimal string into a decimal integer.
end

---------------------------------------------------------------
--十进制整数转化成32位单精度浮点数
-- Convert a decimal integer into a 32-bit single-precision float.
function ConvertFloat(Value)
    -- 将整数按 "ABCD" 字节序转换为32位单精度浮点数的二进制表示
    -- Convert the integer into the binary representation of a 32-bit single-precision float using "ABCD" byte order.
    local b1 = (Value >> 24) & 0xFF
    local b2 = (Value >> 16) & 0xFF
    local b3 = (Value >> 8) & 0xFF
    local b4 = Value & 0xFF
    local FloatBinary = string.char(b2, b1, b4, b3) -- 将字节按 "ABCD" 字节序组合成字符串
    -- Combine bytes into a string using "ABCD" byte order.

    return string.unpack("f", FloatBinary)
end

---------------------------------------------------------------
--升降柱初始化
-- Initialize the lifting column.
function ZC01Init()
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 0 })
    SetHoldRegs(CurrentId, 2, 1, { 0 })
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 6, 1, { ConvertSigned(100) })  --速度
    -- Speed.
    SetHoldRegs(CurrentId, 8, 1, { ConvertSigned(100) })  --加速度
    -- Acceleration.
    SetHoldRegs(CurrentId, 10, 1, { ConvertSigned(100) }) --减速度
    -- Deceleration.
    SetHoldRegs(CurrentId, 4, 1, { ConvertSigned(0) })
    SetHoldRegs(CurrentId, 1, 1, { 64 })
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 2 }) --绝对位置运动
    -- Absolute position motion.
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 1, 1, { 3 })
end

---------------------------------------------------------------
--升降柱使能
-- Enable the lifting column.
function ZC01Enable(PowerOn)
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    if PowerOn == 1 then
        SetHoldRegs(CurrentId, 1, 1, { 3 })
    else
        SetHoldRegs(CurrentId, 1, 1, { 0 })
    end
end

---------------------------------------------------------------
--获取升降柱位置
-- Get the lifting-column position.
function ZC01GetPostion()
    local Data = GetHoldRegs(Communication.Lifting.Brand.ZT3ILC.Modbus.Id, 202, 1)
    if (Data[1] == nil) then
        Alarm("Lifting Data Error!", ErrorMessage.Type.LiftingDataErr)
    end

    return Data
end

---------------------------------------------------------------
--运动升降柱位置
-- Move the lifting column to the target position.
function ZC01Run(Postion)
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    if ConvertSigned(Postion) == nil then
        Alarm("Postion is nil!", ErrorMessage.Type.LiftingDataErr)
    end
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 4, 1, { ConvertSigned(Postion) })
    SetHoldRegs(CurrentId, 1, 1, { 3 })
    SetHoldRegs(CurrentId, 1, 1, { 131 })
end

--------------------------------------------------------------------------------
--LINAK
--------------------------------------------------------------------------------
--升降柱初始化
-- Initialize the lifting column.
function LINAKInit()
    local CurrentId = Communication.Lifting.Brand.LINAK.Modbus.Id
    SetHoldRegs(CurrentId, 8195, 1, { 251 })
    SetHoldRegs(CurrentId, 8196, 1, { 251 })
    SetHoldRegs(CurrentId, 8197, 1, { 251 })
    SetHoldRegs(CurrentId, 8198, 1, { 251 })
    Wait(500)
end

---------------------------------------------------------------------------------
--升降柱停止
-- Stop the lifting column.
function LINAKStop()
    local CurrentId = Communication.Lifting.Brand.LINAK.Modbus.Id
    SetHoldRegs(CurrentId, 8194, 1, { 64259 })
end

----------------------------------------------------------------------------------
--升降柱心跳计数
-- Lifting-column heartbeat count.
function LINAKHeartBeat()
    local CurrentId = Communication.Lifting.Brand.LINAK.Modbus.Id
    if Communication.Lifting.Brand.LINAK.HeartBeatTimes > 255 then
        Communication.Lifting.Brand.LINAK.HeartBeatTimes = 0
    else
        Communication.Lifting.Brand.LINAK.HeartBeatTimes = Communication.Lifting.Brand.LINAK.HeartBeatTimes + 1
    end
    SetHoldRegs(CurrentId, 8193, 1, { Communication.Lifting.Brand.LINAK.HeartBeatTimes })
end

----------------------------------------------------------------------------------
--获取升降柱位置
-- Get the lifting-column position.
function LINAKGetPostion()
    return GetHoldRegs(Communication.Lifting.Brand.LINAK.Modbus.Id, 8449, 1)[1]
end

---------------------------------------------------------------------------------
--运动升降柱位置
-- Move the lifting column to the target position.
function LINAKRun(Postion)
    if Postion == nil then
        LogWarn("Postion is nil!")
        Pause()
    end

    local Err = 0
    local Status = 0
    local CurrentId = Communication.Lifting.Brand.LINAK.Modbus.Id
    repeat
        Err = GetHoldRegs(CurrentId, 8452, 1)
        Status = GetHoldRegs(CurrentId, 8451, 1)
        LogInfo("Linak lifting: error code: %s, status: %s", Err, Status)
        SetHoldRegs(CurrentId, 8194, 1, { 64256 })
    until (Err[1] == 0)

    SetHoldRegs(CurrentId, 8194, 1, { Postion })
end
---------------------------------------------------------------
--三色灯命令
-- Three-color tower-light commands.
---------------------------------------------------------------
--初始化
-- Initialize.
function LightInit(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--黄灯亮
-- Yellow light ON.
function YellowOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, ON)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--黄灯闪
-- Yellow light blinking.
function YellowBlink(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, ON)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, OFF)
    Wait(BlinkTime)
    DO(PalletNumber.TriLight.Yellow, OFF)
    Wait(BlinkTime)
end

---------------------------------------------------------------
--绿灯亮
-- Green light ON.
function GreenOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, ON)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--绿灯闪
-- Green light blinking.
function GreenBlink(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, ON)
    DO(PalletNumber.TriLight.Red, OFF)
    Wait(BlinkTime)
    DO(PalletNumber.TriLight.Green, OFF)
    Wait(BlinkTime)
end

---------------------------------------------------------------
--红灯亮
-- Red light ON.
function RedOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, ON)
end

---------------------------------------------------------------
--红灯闪
-- Red light blinking.
function RedBlink(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, ON)
    Wait(BlinkTime)
    DO(PalletNumber.TriLight.Red, OFF)
    Wait(BlinkTime)
end

---------------------------------------------------------------
--状态更新
-- Status update.
function TriLightStatus(PalletNumber, State)
    local SwitchState =
    {
        [0] = function()
            LightInit(PalletNumber)
        end,
        [1] = function()
            YellowOn(PalletNumber)
        end,
        [2] = function()
            YellowBlink(PalletNumber)
        end,
        [3] = function()
            GreenOn(PalletNumber)
        end,
        [4] = function()
            GreenBlink(PalletNumber)
        end,
        [5] = function()
            RedOn(PalletNumber)
        end,
        [6] = function()
            RedBlink(PalletNumber)
        end
    }
    local switch_State = SwitchState[State]
    if switch_State then
        switch_State()
    else
        Alarm("TriLight state is error, please check it!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--回调函数
-- Callback function.
---------------------------------------------------------------
--暂停
-- Pause.
function callBackStopLifting()
    if PalletLiftingFunction == true then
        local SwitchPauseMode =
        {
            [LiftingType.EWELLIX] = function()
                EWLEnable(0)
            end,
            [LiftingType.GeMinG] = function()
                SV660CEnable(1)
            end,
            [LiftingType.ZT3ILC] = function()
                ZC01Enable(0)
            end,
            [LiftingType.LINAK] = function()
                LINAKStop()
            end
        }
        local switch_mode = SwitchPauseMode[Communication.Lifting.Mode]
        if switch_mode then
            switch_mode()
        else
            Alarm("PauseMode is error, please check it!", ErrorMessage.Type.WorkingDataErr)
        end
        LogWarn("Pause lifting!")
        Communication.Lifting.StopFlag = true
    end
    SetVal("ScriptState", false)
    SetVal("LRSignal", FirstPallet.State.SReset)
    SetVal("RRSignal", SecondPallet.State.SReset)
    SetVal("LButton", FirstPallet.State.InPlaceOK)
    SetVal("RButton", SecondPallet.State.InPlaceOK)

    PalletizingStartSignalCheck()
    LogInfo("Signal State: LWorkState: %s, RWorkState: %s", GetTableKey(StateType, GetVal("LWorkState")),
        GetTableKey(StateType, GetVal("RWorkState")))
    LogInfo("Pause script!")
end
RegistePauseHandler("callBackStopLifting")
---------------------------------------------------------------
--继续
-- Continue.
function callContinuteMotion()
    LogInfo("Script continue and lifting continue moving!")
    SetVal("ScriptState", true)
    FirstPallet.State.SReset = GetVal("LRSignal")
    SecondPallet.State.SReset = GetVal("RRSignal")
    FirstPallet.State.InPlaceOK = GetVal("LButton")
    SecondPallet.State.InPlaceOK = GetVal("RButton")
    if (FirstPallet.State.SReset == true) then
        FirstPallet.State.FReset = true
        FirstPallet.StateValue.Status = StateType.Idle
        CommitPalletStatus(FirstPallet)
    end
    if (SecondPallet.State.SReset == true) then
        SecondPallet.State.FReset = true
        SecondPallet.StateValue.Status = StateType.Idle
        CommitPalletStatus(SecondPallet)
    end
    PalletizingStopSignalCheck()
    LogInfo("Signal State: LRSignal: %s, RRSignal: %s, LButton: %s, RButton: %s", FirstPallet.State.SReset,
        SecondPallet.State.SReset, FirstPallet.State.InPlaceOK, SecondPallet.State.InPlaceOK)
end

RegisteContinueHandler("callContinuteMotion")
---------------------------------------------------------------
--报警命令
-- Alarm commands.
---------------------------------------------------------------
--上传报错信息
-- Upload error information.
function CommitErrorMsg(ErrorCode)
    if SimulateMode == 1 then
        if SimulateProcess.MqttConnected == 1 then
            local ActionStr = "["..ErrorMessage.Code..","..ErrorMessage.PointInfo.Type..","..ErrorMessage.PointInfo.Layer..","..ErrorMessage.PointInfo.Index..","..ErrorMessage.PointInfo.PalletNum.."]"
            mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':luaAlarm', ActionStr, 0, false)
            mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':luaAlarm', ActionStr, 0, false)
            mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':luaAlarm', ActionStr, 0, false)
        end
    end
    WriteRobotModbus(ErrorCode, ErrorMessage.RegisterID.Code)
    if (ErrorCode == ErrorMessage.Type.PointErr) then
        WriteRobotModbus(ErrorMessage.PointInfo.Type, ErrorMessage.RegisterID.Type)
        WriteRobotModbus(ErrorMessage.PointInfo.Layer, ErrorMessage.RegisterID.Layer)
        WriteRobotModbus(ErrorMessage.PointInfo.Index, ErrorMessage.RegisterID.Index)
        WriteRobotModbus(ErrorMessage.PointInfo.PalletNum, ErrorMessage.RegisterID.PalletNum)
    end
end
---------------------------------------------------------------
--清除报警
-- Clear alarms.
function ClearError()
    ErrorMessage.Code = ErrorMessage.Type.NoErr
    CommitErrorMsg(ErrorMessage.Code)
    TriLightStatus(FirstPallet, Light.Init)
    TriLightStatus(SecondPallet, Light.Init)
    LogInfo("Initialized error message successfully!")
end
---------------------------------------------------------------
--报警
-- Alarm.
function Alarm(Message, ErrorCode)
    if ErrorCode ~= nil then
        ErrorMessage.Code = ErrorCode
    else
        LogError("ErrorCode is nil!")
        Halt()
    end
    if (PalletLiftingFunction == true) and (Communication.Lifting.CMaxDis ~= 0) then
        local SwitchStopMode =
        {
            [LiftingType.EWELLIX] = function()
                LogInfo("Stopping EWELLIX lifting")
                EWLEnable(0)
            end,
            [LiftingType.GeMinG] = function()
                LogInfo("Stopping GeMinG lifting")
                SV660CEnable(0)
            end,
            [LiftingType.ZT3ILC] = function()
                LogInfo("Stopping ZT3ILC lifting")
                ZC01Enable(0)
            end,
            [LiftingType.LINAK] = function()
                LogInfo("Stopping Linak lifting")
                LINAKStop()
            end
        }
        local switch_mode = SwitchStopMode[Communication.Lifting.Mode]
        if switch_mode then
            switch_mode()
        else
            LogError("StopMode is error, please check it!")
            Halt()
        end
    end
    CommitErrorMsg(ErrorMessage.Code)
    if (ErrorMessage.Code == ErrorMessage.Type.IPErr) then
        TriLightStatus(FirstPallet, Light.Red.Blink)
        TriLightStatus(SecondPallet, Light.Red.Blink)
    elseif (ErrorMessage.Code ~= ErrorMessage.Type.PalletErr) then
        TriLightStatus(FirstPallet, Light.Red.On)
        TriLightStatus(SecondPallet, Light.Red.On)
    end
    LogError("Error code: %s, %s", ErrorMessage.Code, Message)
    if (ErrorMessage.Code == ErrorMessage.Type.PartErr) then
        LogInfo("Pause robot motion")
        Pause() --暂停机器人当前运动
        -- Pause the robot's current motion.
        ClearError()
    else
        LogInfo("Halting robot motion")
        Halt()  --立即停止机器人当前运动
        -- Immediately stop the robot's current motion.
    end
end
---------------------------------------------------------------
--Modbus相关命令
-- Modbus-related commands.
---------------------------------------------------------------
--创建Modbus连接
-- Create a Modbus connection.
function InitModbus()
    -- if SimulateMode == 1 then
    --     Communication.Controller.Modbus.LinkState = true
    --     return
    -- end

    local Err = 0
    Err, Communication.Controller.Modbus.Id = ModbusCreate(Communication.Controller.Modbus.Ip,
        Communication.Controller.Modbus.Port)
    if Err == 0 then
        LogInfo("Modbus connection successful!")
        ClearError()
        Communication.Controller.Modbus.LinkState = true
    else
        while true do
            Communication.Controller.Modbus.LinkState = false
            Alarm("Modbus connection failed!", ErrorMessage.Type.IPErr)
        end
    end
end
---------------------------------------------------------------
--从Modbus寄存器中读取命令
-- Read commands from Modbus registers.
function ReadRobotModbus(Address)
    -- if SimulateMode == 1 then
    --     AddressStr = tostring(Address)
    --     if SimulateProcess.Regs[AddressStr] then
    --         return SimulateProcess.Regs[AddressStr]
    --     else
    --         return 0
    --     end
    -- end
    local buffer = GetHoldRegs(Communication.Controller.Modbus.Id, Address, 1, "U16")
    while buffer[1] == nil do
        LogWarn("Modbus register data is nil!")
        buffer = GetHoldRegs(Communication.Controller.Modbus.Id, Address, 1, "U16")
    end
    return buffer[1]
end

---------------------------------------------------------------
--机器人写数据到Modbus寄存器
-- Robot writes data to Modbus registers.
function WriteRobotModbus(Data, Address)
    -- if SimulateMode == 1 then
    --     AddressStr = tostring(Address)
    --     SimulateProcess.Regs[AddressStr] = Data
    --     return
    -- end
    
    local Err = 0
    local buffer = { Data }
    if (Data == nil or Address == nil) then
        LogError("Address: %s, Data is nil!,", Address)
        Alarm("Data is nil!", ErrorMessage.Type.WorkingDataErr)
    end
    for i = 1, 20, 1 do
        Err = SetHoldRegs(Communication.Controller.Modbus.Id, Address, #buffer, buffer, "U16")
        if (Err == 0) then
            break
        end
        if (i == 20) then
            LogError(("Adress is %s, Data is %s, Err is %s!"), Address, Data, Err)
            Alarm("Write Robot Modbus data failed!", ErrorMessage.Type.WorkingDataErr)
        end
        Wait(4)
    end
end

---------------------------------------------------------------
--上传隔板计数
-- Upload the interlayer count.
function WritePartNum(PalletNumber)
    if PalletNumber.Pallet == Left then
        SecondPallet.Partition.RePartNum = FirstPallet.Partition.RePartNum
    else
        FirstPallet.Partition.RePartNum = SecondPallet.Partition.RePartNum
    end
    WriteRobotModbus(FirstPallet.Partition.RePartNum, FirstPallet.RegisterID.RePartNum)
    WriteRobotModbus(SecondPallet.Partition.RePartNum, SecondPallet.RegisterID.RePartNum)
    SetVal("PalletPartNumA", FirstPallet.Partition.RePartNum)
    SetVal("PalletPartNumB", SecondPallet.Partition.RePartNum)
end
---------------------------------------------------------------
-- 根据隔板余量传感器同步隔板数量。
-- Synchronize remaining partition count from the interlayer sensor.
-- DI = ON/1：认为料仓有隔板，恢复默认隔板数量，并写入寄存器/控制器全局变量。
-- DI ON/1 means interlayers are available; restore the default count and write it to Modbus/controller globals.
-- DI = OFF/0：认为料仓无隔板，将剩余隔板数量置为0，并写入寄存器/控制器全局变量。
-- DI OFF/0 means no interlayers are available; set the remaining count to 0 and write it to Modbus/controller globals.
function SyncPartitionRemainBySensor(PalletNumber, ForceLog)
    if (PalletNumber == nil) or (PalletNumber.Partition == nil) then
        return
    end

    if (PalletNumber.Partition.Enable ~= true) or (PalletNumber.Mode ~= WorkType.Pallet) then
        return
    end

    if (PartSensorCfg == nil) or (PartSensorCfg.Enable ~= true) then
        return
    end

    if (PartSensorCfg.Port == nil) or (PartSensorCfg.Port.A == nil) then
        LogWarn("Partition remain sensor DI is not configured!")
        return
    end

    if SimulateMode == 1 then
        return
    end

    local DelayTime = PartSensorCfg.DelayTime or 0
    local SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)

    if DelayTime > 0 then
        Wait(DelayTime)
        SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)
    end

    local TargetPartNum = 0
    if SensorState == ON then
        TargetPartNum = PalletNumber.ProcessNum.PartitionNum
    end

    if (PalletNumber.Partition.RePartNum ~= TargetPartNum) or (ForceLog == true) then
        PalletNumber.Partition.RePartNum = TargetPartNum
        WritePartNum(PalletNumber)
        if SensorState == ON then
            LogInfo("Partition remain sensor DI%s is ON. Restore remaining partition number to default and write Modbus: %s.",
                tostring(PartSensorCfg.Port.A), tostring(PalletNumber.Partition.RePartNum))
        else
            LogWarn("Partition remain sensor DI%s is OFF. Set remaining partition number to 0 and write Modbus.",
                tostring(PartSensorCfg.Port.A))
        end
    end
end
---------------------------------------------------------------
-- 判断当前托盘是否使用DI隔板余量传感器。
-- Check whether this pallet uses the DI-based interlayer remaining sensor.
function IsPartitionRemainSensorMode(PalletNumber)
    return (PalletNumber ~= nil)
        and (PalletNumber.Partition ~= nil)
        and (PalletNumber.Partition.Enable == true)
        and (PalletNumber.Mode == WorkType.Pallet)
        and (PartSensorCfg ~= nil)
        and (PartSensorCfg.Enable == true)
        and (SimulateMode ~= 1)
end
---------------------------------------------------------------
--读取栈板上已有料箱层数、剩余料箱数。
-- Read the existing box layer count and remaining box count on the pallet.
function ReadPalletNum(PalletNumber)
    if StorageMode == 1 then
        PalletNumber.PalletNum.LayerCount = ReadRobotModbus(PalletNumber.RegisterID.Layer)
        PalletNumber.PalletNum.RemainBoxNum = ReadRobotModbus(PalletNumber.RegisterID.RemainBoxNum)
        PalletNumber.PalletNum.LayerBoxNum = ReadRobotModbus(PalletNumber.RegisterID.LayerBoxNum)
        PalletNumber.PalletNum.AddBoxCount = ReadRobotModbus(PalletNumber.RegisterID.AddBoxCount)
        PalletNumber.PalletNum.NextBoxCount = ReadRobotModbus(PalletNumber.RegisterID.NextBoxCount)
        PalletNumber.Partition.RePartNum = ReadRobotModbus(PalletNumber.RegisterID.RePartNum)
    else
        local TData = {}
        if PalletNumber.Pallet == Left then
            TData = GetVal("PalletWorkingDataA")
            FirstPallet.Partition.RePartNum = GetVal("PalletPartNumA")
        else
            TData = GetVal("PalletWorkingDataB")
            SecondPallet.Partition.RePartNum = GetVal("PalletPartNumB")
        end
        PalletNumber.PalletNum.LayerCount = TData.LayerCount
        PalletNumber.PalletNum.RemainBoxNum = TData.RemainBoxNum
        PalletNumber.PalletNum.LayerBoxNum = TData.LayerBoxNum
        PalletNumber.PalletNum.AddBoxCount = TData.AddBoxCount
        PalletNumber.PalletNum.NextBoxCount = TData.NextBoxCount
    end
    if PalletNumber.PalletNum.NextBoxCount < PalletNumber.PalletNum.AddBoxCount then
        LogInfo("%s pallet working data: NextBoxCount: %s, AddBoxCount: %s",
            (PalletNumber.Pallet == Left and "Left" or "Right"),
            PalletNumber.PalletNum.NextBoxCount, PalletNumber.PalletNum.AddBoxCount)
        Alarm("ReadPalletNum: AddBoxCount is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
    PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount - PalletNumber.PalletNum.AddBoxCount
    if PalletNumber.PalletNum.LayerCount < 1 then
        PalletNumber.ProcessNum.BoxCount = 0 --托盘箱体计数
        -- Pallet box counter.
        PalletNumber.PalletNum.NextBoxCount = 1
        PalletNumber.PalletNum.LayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1)
        PalletNumber.PalletNum.LayerCount = 1                                                  --托盘层数计数
        -- Pallet layer counter.
        PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1) --托盘不满一层箱体的数量
        -- Number of boxes in the incomplete pallet layer.
        PalletNumber.ProcessNum.InitBoxCount = 0                                               --栈板料箱计数置位
        -- Set/reset the pallet box-count state.
        PalletNumber.PalletNum.AddBoxCount = 0
        PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
    end
    if (PalletNumber.Partition.Enable == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.Partition.RePartNum <= 0) then
                -- DI21传感器项目中，隔板余量不再相信历史RePartNum；启动/ACK后由SyncPartitionRemainBySensor()按DI重新写回。
                -- In DI-sensor projects, do not trust the saved RePartNum for empty detection; SyncPartitionRemainBySensor() restores it from DI after startup/ACK.
                if IsPartitionRemainSensorMode(PalletNumber) == true then
                    LogInfo("Partition remain is controlled by DI sensor. Skip saved RePartNum empty alarm before sensor synchronization.")
                else
                    -- 仿真模式，不需要隔板数量报警
                    -- In simulation mode, interlayer quantity alarms are not required.
                    if (SimulateMode == 1) then
                        PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                        return
                    end
                    Alarm("Partition is empty!", ErrorMessage.Type.PartErr)
                    PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                    WritePartNum(PalletNumber)
                end
            end
            if (PalletNumber.Partition.RePartNum > PalletNumber.ProcessNum.PartitionNum) then
                PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
            end
        else
            if (PalletNumber.Partition.RePartNum >= PalletNumber.ProcessNum.PartitionNum) then
                -- 仿真模式，不需要隔板数量报警
                -- In simulation mode, interlayer quantity alarms are not required.
                if SimulateMode == 1 then
                    PalletNumber.Partition.RePartNum = 0
                    return
                end
                Alarm("Partition is full!", ErrorMessage.Type.PartErr)
                PalletNumber.Partition.RePartNum = 0
                WritePartNum(PalletNumber)
            end
            if (PalletNumber.Partition.RePartNum < 0) then
                PalletNumber.Partition.RePartNum = 0
            end
        end
        WritePartNum(PalletNumber)
        if PalletNumber.Pallet == Left then
            FirstPallet.Partition.Place = GetVal("PalletPartPlaceA")
        else
            SecondPallet.Partition.Place = GetVal("PalletPartPlaceB")
        end
    end
    LogInfo(
        "%s pallet working data: LayerCount: %s, NextBoxCount: %s, RemainBoxNum: %s, LayerBoxNum: %s, AddBoxCount: %s, PartPlace: %s, PartitionNum: %s",
        (PalletNumber.Pallet == Left and "Left" or "Right"),
        PalletNumber.PalletNum.LayerCount, PalletNumber.PalletNum.NextBoxCount,
        PalletNumber.PalletNum.RemainBoxNum, PalletNumber.PalletNum.LayerBoxNum,
        PalletNumber.PalletNum.AddBoxCount, PalletNumber.Partition.Place, PalletNumber.Partition.RePartNum)
end
---------------------------------------------------------------
--上传已有料箱层数、剩余料箱数和下一料箱号
-- Upload the existing box layer count, remaining box count, and next box number.
function CommitPalletNum(PalletNumber)
    PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount + PalletNumber.PalletNum.AddBoxCount
    WriteRobotModbus(PalletNumber.PalletNum.LayerCount, PalletNumber.RegisterID.Layer)
    WriteRobotModbus(PalletNumber.PalletNum.AddBoxCount, PalletNumber.RegisterID.AddBoxCount)
    WriteRobotModbus(PalletNumber.PalletNum.NextBoxCount, PalletNumber.RegisterID.NextBoxCount)
    WriteRobotModbus(PalletNumber.PalletNum.RemainBoxNum, PalletNumber.RegisterID.RemainBoxNum)
    WriteRobotModbus(PalletNumber.PalletNum.LayerBoxNum, PalletNumber.RegisterID.LayerBoxNum)
    if PalletNumber.Pallet == Left then
        SetVal("PalletWorkingDataA", PalletNumber.PalletNum)
        SetVal("PalletPartNumA", PalletNumber.Partition.RePartNum)
        if SimulateMode == 1 then
            SimulateProcess.Capacity.FirstPallet.Layer = PalletNumber.PalletNum.LayerCount
            SimulateProcess.Capacity.FirstPallet.Box = PalletNumber.PalletNum.NextBoxCount
        end
    else
        SetVal("PalletWorkingDataB", PalletNumber.PalletNum)
        SetVal("PalletPartNumB", PalletNumber.Partition.RePartNum)
        if SimulateMode == 1 then
            SimulateProcess.Capacity.SecondPallet.Layer = PalletNumber.PalletNum.LayerCount
            SimulateProcess.Capacity.SecondPallet.Box = PalletNumber.PalletNum.NextBoxCount
        end
    end
    PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount - PalletNumber.PalletNum.AddBoxCount
end
---------------------------------------------------------------
--读取产能数据
-- Read production data.
function ReadProductionData()
    if StorageMode == 1 then
        Capacity.Num.RePallet = ReadRobotModbus(Capacity.RegisterID.Pallet)
        Capacity.Num.ReBox = ReadRobotModbus(Capacity.RegisterID.Box)
    else
        local TData = GetVal("PalletCapacity")
        if (TData == nil) then
            Capacity.Num.RePallet = 0
            Capacity.Num.ReBox = 0
        else
            Capacity.Num.RePallet = TData.Pallet
            Capacity.Num.ReBox = TData.Box
        end
    end
    LogInfo("Initialized capacity data: Pallet: %s, Box: %s", Capacity.Num.RePallet, Capacity.Num.ReBox)
end

---------------------------------------------------------------
--上传产能栈板数据
-- Upload pallet production data.
function CommitCapacityPallet()
    WriteRobotModbus(Capacity.Num.Pallet, Capacity.RegisterID.Pallet)
    SetVal("PalletCapacity", Capacity.Num)
end
---------------------------------------------------------------
--上传产能箱子数据
-- Upload box production data.
function CommitCapacityBox()
    WriteRobotModbus(Capacity.Num.Box, Capacity.RegisterID.Box)
    SetVal("PalletCapacity", Capacity.Num)
end
---------------------------------------------------------------
--产能计数:检查箱体数量
-- Production count: check box quantity.
function PlaceCountPallet(PalletNumber)
    PalletNumber.ProcessNum.PalletBoxCount =
        math.abs(PalletNumber.PalletNum.AddBoxCount - PalletNumber.ProcessNum.RemainingAddBoxCount) +
        math.abs(PalletNumber.ProcessNum.BoxCount - PalletNumber.ProcessNum.InitBoxCount)
    if (StateMachine == FSMType.DLR) then
        Capacity.Num.Box = Capacity.Num.ReBox + FirstPallet.ProcessNum.PalletBoxCount +
            SecondPallet.ProcessNum.PalletBoxCount
    else
        Capacity.Num.Box = Capacity.Num.ReBox + PalletNumber.ProcessNum.PalletBoxCount
    end

    CommitCapacityBox() --上传产能数据
    -- Upload production data.
end

---------------------------------------------------------------
--上传栈板状态
-- Upload pallet status.
function CommitPalletStatus(PalletNumber)
    WriteRobotModbus(PalletNumber.StateValue.Status, PalletNumber.RegisterID.PalletStatus)
    local WorkState = (PalletNumber.Pallet == Left and "LWorkState" or "RWorkState")
    SetVal(WorkState, PalletNumber.StateValue.Status)
end
---------------------------------------------------------------
--获取栈板使能状态
-- Get pallet enable status.
function GetEnableStatus()
    -- if SimulateMode == 1 then
    --     if MultPalletFunction == true then
    --         FirstPallet.StateValue.Enable = 1
    --         SecondPallet.StateValue.Enable = 1
    --     else
    --         if Pallet == Left then
    --             FirstPallet.StateValue.Enable = 1
    --             SecondPallet.StateValue.Enable = 0
    --         else
    --             FirstPallet.StateValue.Enable = 0
    --             SecondPallet.StateValue.Enable = 1
    --         end
    --     end
    --     return
    -- end
    FirstPallet.StateValue.Enable = ReadRobotModbus(FirstPallet.RegisterID.PalletEnable)
    SecondPallet.StateValue.Enable = ReadRobotModbus(SecondPallet.RegisterID.PalletEnable)
end
---------------------------------------------------------------
--执行安全功能模块
-- Execute the safety function module.
function ExecuteSafeModule(PalletNumberA, PalletNumberB)
    local ModuleA = PalletNumberA.SafeCfg
    local ModuleB = PalletNumberB.SafeCfg
    if (ModuleA.Grating.Enable == true) then
        while (CheckDIRes(ModuleA.Grating.Port.Mode, ModuleA.Grating.Port.A) == OFF) do
            LogWarn("Grating module is triggered!")
            Pause()
        end
        return
    end
    if (ModuleA.LiDAR.Enable == true) then
        IORes(ModuleA.LiDAR.Port.Mode, ModuleA.LiDAR.Port.A, ON)
        IORes(ModuleA.LiDAR.Port.Mode, ModuleA.LiDAR.Port.B, ON)
    end
    if (PalletBeInPlaceOKButton == false and FirstPallet.State.Done == true and SecondPallet.State.Done == true) then
        if (ModuleB.LiDAR.Enable == true) then
            IORes(ModuleB.LiDAR.Port.Mode, ModuleB.LiDAR.Port.A, ON)
            IORes(ModuleB.LiDAR.Port.Mode, ModuleB.LiDAR.Port.B, ON)
        end
    else
        if (ModuleB.LiDAR.Enable == true and Pallet ~= Idle) then
            IORes(ModuleB.LiDAR.Port.Mode, ModuleB.LiDAR.Port.A, OFF)
            IORes(ModuleB.LiDAR.Port.Mode, ModuleB.LiDAR.Port.B, OFF)
        end
    end
end

---------------------------------------------------------------
--获取安全信号状态
-- Get safety signal status.
function GetSafeModuleStatus()
    local SwitchFSM =
    {
        [Idle] = function()
            ExecuteSafeModule(FirstPallet, SecondPallet)
            ExecuteSafeModule(SecondPallet, FirstPallet)
        end,
        [Left] = function()
            ExecuteSafeModule(FirstPallet, SecondPallet)
        end,
        [Right] = function()
            ExecuteSafeModule(SecondPallet, FirstPallet)
        end
    }

    local switch_mode = SwitchFSM[Pallet]
    if switch_mode then
        switch_mode()
    else
        Alarm("SwitchFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--得到栈板工作状态	
-- Get pallet working status.
function GetPalletStatus(PalletNumber)
    if SimulateMode == 1 then
        PalletNumber.State.Replace = true
        return
    end
    if (PalletNumber.StateValue.Enable == 1) then
        if (PalletBeInPlaceOKButton == true) then
            PalletNumber.State.Replace = (DI(PalletNumber.InPlaceA) == ON)
                and (DI(PalletNumber.InPlaceB) == ON)
                and ((DI(PalletNumber.InPlaceOK) == ON)
                    or (PalletNumber.State.InPlaceOK == true))
            if (PalletNumber.State.Replace == true) then
                PalletNumber.State.InPlaceOK = true
                if (Pallet ~= Idle) then
                    return
                end
                if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
                    if (PalletNumber.Pallet == Left and FirstPallet.State.Init == true) then
                        if (FirstPallet.StateValue.Status == StateType.Idle
                                and SecondPallet.StateValue.Status ~= StateType.Run
                                and PalletNumber.State.InPlaceOK == true) then
                            Pallet = Left
                        end
                    elseif (PalletNumber.Pallet == Right and SecondPallet.State.Init == true) then
                        if (SecondPallet.StateValue.Status == StateType.Idle
                                and FirstPallet.StateValue.Status ~= StateType.Run
                                and PalletNumber.State.InPlaceOK == true) then
                            Pallet = Right
                        end
                    end
                else
                    if (PalletNumber.StateValue.Status == StateType.Idle) then
                        Pallet = PalletNumber.Pallet
                    end
                end
            end
        else
            PalletNumber.State.Replace = (DI(PalletNumber.InPlaceA) == ON)
                and (DI(PalletNumber.InPlaceB) == ON)
        end
    end
end
----------------------------------------------------------------
--掉料信号检测
-- Dropped-box signal detection.
function DropSignalDete(PalletNumber, DeteState, SuckerPort, Mode)
    if (Mode == DropType.Norm) then
        if (PalletNumber.Partition.Mode == MotionType.Part) and (PartCfg.Enable == true) then
            if (DeteState == OFF) and (CheckDORes(PartCfg.Port.Mode, PartCfg.Port.A) == ON) then
                Wait(Time.DropDetection)
                if (DeteState == OFF) and (CheckDORes(PartCfg.Port.Mode, PartCfg.Port.A) == ON) then
                    IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF) --数字输出控制吸盘关闭
                    -- Use digital output to turn off the sucker.
                    Alarm("Partition Fall Down!", ErrorMessage.Type.DropErr)
                end
            end
        else
            if (DeteState == OFF) and (CheckDORes(SuckerCfg.Port.Mode, SuckerPort) == ON) then
                Wait(Time.DropDetection)
                if (DeteState == OFF) and (CheckDORes(SuckerCfg.Port.Mode, SuckerPort) == ON) then
                    IORes(SuckerCfg.Port.Mode, SuckerPort, OFF) --数字输出控制吸盘关闭
                    -- Use digital output to turn off the sucker.
                    Alarm("Box Fall Down!", ErrorMessage.Type.DropErr)
                end
            end
        end
    else
        if (PartCfg.Enable == true) then
            if (DeteState == ON) and (CheckDORes(PartCfg.Port.Mode, PartCfg.Port.A) == ON) then
                PalletNumber.StateValue.Status = StateType.DropBox
                CommitPalletStatus(PalletNumber)
                Alarm("TCP With Box!", ErrorMessage.Type.StartErr)
            end
        end
        if (DeteState == ON) and (CheckDORes(SuckerCfg.Port.Mode, SuckerPort) == ON) then
            PalletNumber.StateValue.Status = StateType.DropBox
            CommitPalletStatus(PalletNumber)
            Alarm("TCP With Box!", ErrorMessage.Type.StartErr)
        end
    end
end

----------------------------------------------------------------
--掉料检测
-- Dropped-box detection.
function DropDete(PalletNumber, Mode)
    local SwitchDropMode =
    {
        [0] = function() --关闭检测
        -- Close/turn-off detection.

        end,
        [1] = function() --光电检测
        -- Photoelectric detection.
            if (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                return
            end
            DropSignalDete(PalletNumber, ToolDI(SuckerCfg.Dete.PE.A), SuckerCfg.Port.A, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Single) then
                return
            end
            DropSignalDete(PalletNumber, ToolDI(SuckerCfg.Dete.PE.B), SuckerCfg.Port.B, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Double) then
                return
            end
            DropSignalDete(PalletNumber, ToolDI(SuckerCfg.Dete.PE.C), SuckerCfg.Port.C, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Triple) then
                return
            end
            DropSignalDete(PalletNumber, ToolDI(SuckerCfg.Dete.PE.D), SuckerCfg.Port.D, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Quadruple) then
                return
            end
        end,
        [2] = function() --真空检测
        -- Vacuum detection.
            if (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                return
            end
            DropSignalDete(PalletNumber, DI(SuckerCfg.Dete.Vacuum.A), SuckerCfg.Port.A, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Single) then
                return
            end
            DropSignalDete(PalletNumber, DI(SuckerCfg.Dete.Vacuum.B), SuckerCfg.Port.B, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Double) then
                return
            end
            DropSignalDete(PalletNumber, DI(SuckerCfg.Dete.Vacuum.C), SuckerCfg.Port.C, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Triple) then
                return
            end
            DropSignalDete(PalletNumber, DI(SuckerCfg.Dete.Vacuum.D), SuckerCfg.Port.D, Mode)
            if (PalletSuckerFunction == SuckerCfg.Type.Quadruple) then
                return
            end
        end
    }

    local switch_mode = SwitchDropMode[SuckerCfg.Dete.Mode]
    if switch_mode then
        switch_mode()
    else
        Alarm("DropSignal is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--吸盘输出信号类型
-- Sucker output signal type.
function IORes(Flag, Num, State)
    if (Flag == 0) then
        DO(Num, State)
    else
        ToolDO(Num, State)
    end
end
---------------------------------------------------------------
--检查吸盘输出信号类型
-- Check the sucker output signal type.
function CheckDORes(Flag, Num)
    if (Flag == 0) then
        return GetDO(Num)
    else
        return GetToolDO(Num)
    end
end

---------------------------------------------------------------
--检查输入信号状态
-- Check input signal status.
function CheckDIRes(Flag, Num)
    if (Flag == 0) then
        return DI(Num)
    else
        return GetToolDI(Num)
    end
end
