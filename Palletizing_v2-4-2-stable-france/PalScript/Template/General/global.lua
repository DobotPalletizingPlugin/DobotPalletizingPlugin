local mqttFunc = require("libplugin_eco")
-------------------------------------------------------------------------------------------
-- 此文件仅用于定义全局常量、全局变量和全局函数
-------------------------------------------------------------------------------------------
-- 公共全局常量
-------------------------------------------------------------------------------------------
Home = 0            --回零
Idle = -1           --空闲
Left = 0            --左侧栈板
Right = 1           --右侧栈板
LiftingInTime = 500 --升降柱过程延时
BlinkTime = 500     --三色灯闪烁时间
Light =             --三色灯状态类型
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
MotionType =     --运动类型
{
    Norm = 0,    --料箱取放运动
    Part = 1     --隔板取放运动
}
WorkType =       --工作类型
{
    Pallet = 1,  --码垛
    Depallet = 2 --拆垛
}
DropType =       --掉料报警类型
{
    Norm = 0,    --掉料检测信号OFF，吸盘信号ON，触发掉料报警
    Prep = 1     --掉料检测信号ON，吸盘信号ON，触发工艺包启动末端带料报警
}
ToolType =       --工具类型
{
    Conc = 0,    --同心工具
    Ecc = 1,     --偏心工具
}
PointType =      --点位类型
{
    Trans =      --过渡点
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
            Part = 6  --隔板取料放料动作点位
        }
    },
    Pick = --取料点
    {
        Index =
        {
            A = 6
        },
        Cfg =
        {
            Norm = 1, --取料放料动作点位
            Part = 2  --隔板取料放料动作点位
        }
    },
    PickOffset = --取料上方点
    {
        Index =
        {
            A = 7
        },
        Cfg =
        {
            Norm = 3, --取料放料动作点位
            Part = 4  --隔板取料放料动作点位
        }
    },
    Place = --放料点
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
            Part = 12  --隔板取料放料动作点位
        }
    },
    PlaceOffset = --放料上方点
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
            Part = 10 --隔板取料放料动作点位
        }
    },
    Insert = --放料偏移点
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
            Part = 8  --隔板取料放料动作点位
        }
    }
}
FSMType =           --模式状态类型
{
    DP = -3,        --双栈板
    SP = -2,        --单栈板
    IDLE = -1,      --无栈板
    SL = 0,         --单传送带单左侧栈板
    SR = 1,         --单传送带单右侧栈板
    SLR = 2,        --单传送带双侧栈板
    DLR = 3         --双传送带双侧栈板
}
StateType =         --状态类型
{
    LosePallet = 0, --未检测到栈板
    DisPallet = 1,  --未使能栈板
    Run = 2,        --码垛/拆垛中
    Stop = 3,       --码垛/拆垛完成
    DropBox = 4,    --掉料
    Idle = 5        --空闲中
}
LiftingType =       --升降柱类型
{
    EWELLIX = 0,
    GeMinG = 1,
    ZT3ILC = 2,
    LINAK = 3
}
-------------------------------------------------------------------------------------------
-- 公共全局变量
-------------------------------------------------------------------------------------------
StorageMode = 0                                                  --数据获取方式，nil/1:寄存器获取, 0：控制器中全局变量获取
StateMachine = -1                                                --工作状态, 初始化Idle：-1
Pallet = Idle                                                    --当前选择栈板，0：为第一栈板，1：为第二栈板
WorkingMode = 0                                                  --工作模式 0：单传送带码垛，1：双传送带单侧码垛，2：双传送带交替码垛
AgingMode = 0                                                    --老化模式 0:默认模式，1：老化模式
PalletName = "Pallet"                                            --配方名称
SignalReady = false                                              --信号选择状态标志位
MotionDone = true                                                --运动状态标志位
FilmDone = true                                                  --缠膜状态标志位
--------------------------------------------------------------------------------------------
PalletBeInPlaceOKButton = false                                  --栈板到位确认按钮功能，false：关闭，true：启用
PalletLiftingFunction = false                                    --升降柱功能，false：关闭，true：启用
PalletObstacleFunc = 0                                           --自动过渡点障碍物功能，0：关闭，1: 启用
MultPalletFunction = false                                       --多栈板功能，false：单栈板，true：多栈板
PalletSuckerFunction = 0                                         --多吸盘功能, -1：通讯控制单吸, 1：通用单吸， 2：通用双吸, 3：通用三吸，4：通用四吸
RestrictMoveFunction = false                                     --两侧垛型高度差限制功能，false：关闭，true：开启
HighLoadFunc = false                                             --高负载功能, false：关闭，true：打开
BuzzerFunction = false                                           --蜂鸣器功能开关，false：关闭，true：打开
FilmFunction = true                                              --缠膜功能，false：关闭，true：启用
ResetPathFunc = false                            --复位轨迹功能，false：关闭，true：打开
---------------------------------------------------------------------------------------------
ToolSpeedWithBox = 0                                             --带载TCP速度
ToolAccWithBox = 0                                               --带载TCP加速度
PlaceSpeed = 0                                                   --放置过程TCP速度
PlaceAcc = 0                                                     --放置过程TCP加速度
ToolSpeedWithoutBox = 0                                          --空载TCP速度
ToolAccWithoutBox = 0                                            --空载TCP加速度
----------------------------------------------------------------------------------------------
ToolHigh = 0                                                     --工具高度
ToolWeight = 0                                                   --工具重量
TeachPointOffHeight = 300                                        --取料示教点偏移高度
HomePoint = { joint = { 90, 0, 90, 0, -90, 0 } }                 --安全点
HomePointPose = { pose = { 175.6, -874.8, 918.7, 180, 0, 180 } }
HomeTransPointL = { joint = { 166, 8, 63, 19, -90, 0 } }
HomeTransPointR = { joint = { -13, 7, 63, 18, -90, 0 } }
PartSafePoint = { joint = { 90, 0, 90, 0, -90, 0 } }             --隔板安全点
LiftingSafetyPoint = { joint = { 90, -29, 114, 4, -90, 0 } }     --空载升降柱上升安全点
LiftingSafetyPoint_HL = { joint = { 90, -45, 120, 15, -90, 0 } } --空载升降柱上升安全点
-----------------------------------------------------------------------------------------------
FilmDI = 14                                                      --缠膜
BuzzerIO = 15                                                    --蜂鸣器
PartCfg =                                                        --独立隔板控制配置
{
    Enable = false,                                              --false：关闭，true：打开
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        A = 22
    }
}
SPortCfg =          --安全吸盘检测端口
{
    Enable = false, --false：关闭，true：打开
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        A = 18
    }
}
SuckerCfg =           --吸盘控制配置
{
    Type =            --吸盘类型
    {
        SSingle = -1, --通讯控制单吸
        Single = 1,   --IO控制单吸
        Double = 2,   --IO控制双吸
        Triple = 3,   --IO控制三吸
        Quadruple = 4 --IO控制四吸
    },
    Port =            --端口
    {
        Mode = 0,     --IO类型, 0：通用IO，1：末端IO
        A = 16,
        B = 17,
        C = 16,
        D = 17
    },
    Dete =        --信号检测类型
    {
        Mode = 0, --掉料检测模式, 0：关闭， 1：光电检测， 2：真空检测
        PE =      --光电检测
        {
            A = 18,
            B = 18,
            C = 18,
            D = 18
        },
        Vacuum = --真空检测
        {
            A = 19,
            B = 19,
            C = 19,
            D = 19
        },
        VacuumBreak =   --破真空检测
        {
            Enable = 0, --0：关闭，1：开启
            Mode = 0,   --IO类型, 0：通用IO，1：末端IO
            A = 20,
            B = 20,
            C = 20,
            D = 20
        }
    }
}
------------------------------------------------------------------------------------------------
Capacity = --产能参数
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
Time =       --延时参数
{
    Thread = --线程等待时间ms
    {
        s0 = 8,
        s1 = 8,
        s2 = 200,
        s3 = 20,
        s4 = 20
    },
    Pallet = --更换新栈板过程中屏蔽栈板丢失时间s
    {
        Shield = 20
    },
    Pick = --取料过程等待时间ms
    {
        Pre = 0,
        In = 1500,
        Post = 0
    },
    Place = --放料过程等待时间ms
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
}
ErrorMessage =        --报警信息
{
    Code = 0,         --报警码
    Type =
    {
        NoErr = 0,            --无报错
        LinkErr = 1,          --机器人与升降轴通信失败
        PointErr = 2,         --点位不可达
        PalletErr = 3,        --检测到栈板丢失
        RestrictErr = 4,      --高度限制功能开启，双侧传送带停止工作
        DropErr = 5,          --物品掉落
        StartErr = 6,         --启动带料
        PartErr = 7,          --隔板已空/已满
        IPErr = 8,            --创建Modbus通信失败,请检查Modbus地址
        LiftingErr = 9,       --升降柱运动次数过多
        CameraAErr = 10,      --预留相机相关
        CameraBErr = 11,      --预留相机相关
        LiftingStateErr = 12, --升降柱状态异常
        CameraCErr = 13,      --预留相机相关
        PalletEnableErr = 14, --无栈板启用
        LiftingDataErr = 15,  --读取升降柱位置错误
        QueueTimeout = 16,    --队列超时
        WorkingDataErr = 17,  --工作数据错误
    },
    PointInfo =
    {
        Type = 0,     --类型
        Layer = 0,    --层数
        Index = 0,    --序号
        PalletNum = 0 --工作栈板号
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
LogConfig = --日志级别配置
{
    Level =
    {
        DEBUG = 1,
        INFO = 2,
        WARN = 3,
        ERROR = 4
    },
    CurrentLevel = 2, --默认为INFO级别
    Enable = true     --是否启用日志
}
------------------------------------------------------------------------------------------
--栈板全局变量
------------------------------------------------------------------------------------------
local function CreatePalletTemplate(CPallet, NearJoint)
    return {
        StateValue =
        {
            Status = 5, --栈板状态, 初始化:StateType.Idle
            Enable = 0  --栈板使能状态，0：禁用，1：使能
        },

        State =
        {
            Init = false,       --数据初始化
            StateReady = false, --准备状态
            Done = false,       --完成状态
            Replace = false,    --更换栈板状态
            InPlaceOK = false,  --栈板到位确认标志
            FReset = false,     --第一次判断栈板是否移开
            SReset = false,     --第二次判断栈板是否到位
            LosePallet = false  --栈板丢失标志位
        },

        ProcessNum =
        {
            BoxCount = 0,             --托盘箱体计数（初始值）
            PalletBoxCount = 0,       --产能料箱计数
            InitBoxCount = 0,         --托盘箱体计数（初始值）
            RemainingAddBoxCount = 0, --双吸双放料箱额外初始计数
            TotalBoxNum = 0,          --托盘单侧箱体总数（上传至Modbus寄存器）
            PalletLength = 0,         --托盘信息（上位机配置）
            PalletWidth = 0,          --托盘信息（上位机配置）
            PalletHeight = 0,         --托盘信息（上位机配置）
            PartitionNum = 10,        --隔板最大数量（上位机配置）
            PartitionHeight = 0,      --隔板高度（上位机配置）
            PartitionWeight = 2       --隔板重量（上位机配置）
        },

        PalletNum =
        {
            NextBoxCount = 1, --栈板下一个箱体计数（上传至Modbus寄存器）
            AddBoxCount = 0,  --双吸双放料箱额外计数（上传至Modbus寄存器）
            LayerCount = 0,   --托盘层数计数，表示多少层已放满（上传至Modbus寄存器）
            LayerBoxNum = 0,  --从首层到当前层理论最大箱体序号数（上传至Modbus寄存器）
            RemainBoxNum = 0  --托盘不满一层箱体的数量（上传至Modbus寄存器）
        },

        BoxProperty =
        {
            BoxLength = 0, --箱体信息（上位机配置）
            BoxWidth = 0,  --箱体信息（上位机配置）
            BoxHigh = 0,   --箱体信息（上位机配置）
            BoxWeight = 0, --箱体信息（上位机配置）
            OffsetX = 100, --目标点偏移量
            OffsetY = 100,
            OffsetZ = 200,
            Sucker = 0,       --吸盘属性，-1：n吸n单放，0：n吸单放，1：长边对齐双放，2：短边对齐双放，3：长边对齐三放，4：短边对齐三放，5：长边对齐四放，:6：短边对齐四放
            BoxDirection = 0, --箱子来料方向，0：箱体长边与来料方向垂直，1：箱体短边与来料方向垂直
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

            TeachPickPoint =
            {
                pose = {},
                joint = {}
            }, --示教点，码垛：箱体抓取点、卸垛：箱体放置点（上位机配置）

            TeachPartitionPickPoint =
            {
                pose = {},
                joint = {}
            }, --示教点，码垛：隔板抓取点、卸垛：隔板放置点（上位机配置）

            TeachPartitionPlacePoint =
            {
                pose = {},
                joint = {}
            } --示教点，码垛：隔板放置点、卸垛：隔板抓取点（上位机配置）
        },

        Mode = 1,                   --工作模式，1：码垛，2：拆垛
        Pallet = CPallet,           --栈板标志，0：左侧，1：右侧
        OffsetHeight = 100,         --栈板放置点（拆垛抓取点）偏移高度
        TransPointMode = 0,         --过渡点获取方式，0：示教，1：自动生成
        TransPlacePointNum = 1,     --放料过渡点数量
        TransPartPointMode = 0,     --隔板过渡点获取方式，0：示教，1：自动生成
        TransPartitionPointNum = 1, --隔板过渡点数量
        Partition =                 --隔板配置
        {
            Enable = false,         --隔板功能，false: 关闭，true：开启
            Layer = {},             --隔板放置层位置
            Mode = 0,               --隔板标志位，0：常规点位，1: 隔板点位
            Last = false,           --最后隔板运动信号
            LastPlan = false,       --规划最后隔板运动信号
            Place = 0,              --隔板放置结果，0：未放置，1：已放置
            RePartNum = 0           --剩余隔板数量
        },
        MultSensorFunction = 0,     --多传感器功能 0：关闭， 1：开启
        Layer = 0,                  --码垛总层数
        CompensateZData = 0,        --开始补偿放置位置Z轴向大小
        CompensateLayer = 0,        --开始补偿放置位置Z轴向的层数
        J4UpperLimit = 0,           --关节4允许极限角上限（暂不启用）
        J4LowerLimit = 0,           --关节4允许极限角下限（暂不启用）
        Near = { joint = NearJoint },

        Coordinate =
        {
            PartitionUserNum = 0, --选择隔板的User编号
            UserNum = 0,          --选择的User编号
            ToolNum = 0           --选择的TCP编号
        },

        BoxBeInpPlaceDI1 = 1,   --箱体到位检测DI 1
        BoxBeInpPlaceDI2 = 2,   --箱体到位检测DI 2
        BoxBeInpPlaceDI3 = 1,   --箱体到位检测DI 1
        BoxBeInpPlaceDI4 = 2,   --箱体到位检测DI 2
        InPlaceA = 3,           --栈板到位信号DI 3
        InPlaceB = 4,           --栈板到位信号DI 4
        InPlaceOK = 9,          --栈板放置确认按钮DI 9
        RestrictMoveSignal = 23, --限制垛型高度信号
        SafeCfg =                --安全IO配置
        {
            Grating = {
                Enable = false, --false：关闭，true：打开
                Port =
                {
                    Mode = 0, --IO类型, 0：通用DI
                    A = 23
                }
            },
            LiDAR = {
                Enable = false, --false：关闭，true：打开
                Port =
                {
                    Mode = 0, --IO类型, 0：通用DO
                    A = 8,
                    B = 9
                }
            },
        }
    }
end
------------------------------------------------------------------------------------------
--左侧栈板全局变量
------------------------------------------------------------------------------------------
FirstPallet = CreatePalletTemplate(Left, { 135, 5, 90, 0, -90, -10 })
FirstPallet.TriLight =
{
    Yellow = 1, --栈板三色灯黄灯DO 1
    Green = 2,  --栈板三色灯绿灯DO 2
    Red = 3     --栈板三色灯红灯DO 3
}

FirstPallet.RegisterID =
{
    PalletStatus = 5000, --码垛状态寄存器地址
    Layer = 5002,        --当前码垛层数寄存器地址
    RemainBoxNum = 5003, --当前层剩余料箱寄存器地址
    PalletEnable = 5007, --使能栈板寄存器地址
    NextBoxCount = 5010, --下一个箱体数寄存器地址
    LayerBoxNum = 5020,  --首层到当前层最大箱体序号数量寄存器地址
    AddBoxCount = 5022,  --双吸双放料箱额外计数寄存器地址
    RePartNum = 5024,    --隔板数量寄存器地址
    PlaceButton = 5038   --栈板确认按钮状态地址
}
------------------------------------------------------------------------------------------
--右侧栈板全局变量
------------------------------------------------------------------------------------------
SecondPallet = CreatePalletTemplate(Right, { 45, 5, 90, 0, -90, -10 })
SecondPallet.TriLight =
{
    Yellow = 4, --栈板三色灯黄灯DO 4
    Green = 5,  --栈板三色灯绿灯DO 5
    Red = 6     --栈板三色灯红灯DO 6
}

SecondPallet.RegisterID =
{
    PalletStatus = 5001, --码垛状态寄存器地址
    Layer = 5004,        --当前码垛层数寄存器地址
    RemainBoxNum = 5005, --当前层剩余料箱寄存器地址
    PalletEnable = 5009, --使能栈板寄存器地址
    NextBoxCount = 5011, --下一个箱体数寄存器地址
    LayerBoxNum = 5021,  --首层到当前层最大箱体序号数量寄存器地址
    AddBoxCount = 5023,  --双吸双放料箱额外计数寄存器地址
    RePartNum = 5025,    --隔板数量寄存器地址
    PlaceButton = 5039   --栈板确认按钮状态地址
}
-------------------------------------------------------------------------------------------
--通讯相关全局变量
-------------------------------------------------------------------------------------------
Communication =
{
    Lifting =
    {
        RestrictMoveFlag = false, --限制运动标志位
        StartHeightDiff = 1500,   --开始高度差
        EndHeightDiff = 1000,     --结束高度差
        TimesPerHour = 0,         --升降柱每小时运动次数
        MaxtimesPerHour = 35,     --升降柱每小时最大运动次数
        CMaxDis = 0,              --升降柱参数
        StopFlag = false,         --升降柱停止标志位
        Mode = 0,                 --升降柱型号选择，0：EWELLIX，1：GeMinG，2：ZT3ILC, 3:LINAK
        Brand =
        {
            EWELLIX =
            {
                Tcp =
                {
                    Ip = "192.168.5.100", --升降柱通讯IP
                    Port = 50001,         --升降柱通讯端口
                    Socket = 0,           --升降柱通讯
                },
                MaxDistance = 900,        --升降柱最大运动高度
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
                    SlaveId = 1,      --从站ID
                    BaudRate = 57600, --RS485波特率 9600/19200/57600/115200
                    Parity = "N",     --"N": 无校验/"O": 奇校验/"E": 偶校验
                    DataBit = 8,      --数据位
                    StopBit = 1       --停止位 1/2
                },
                MaxDistance = 700     --升降柱最大运动高度
            },

            ZT3ILC =
            {
                Modbus =
                {
                    Id = 0,               --主站设备号
                    Ip = "192.168.5.100", --通讯IP
                    Port = 502            --通讯端口
                },
                MaxDistance = 900         --升降柱最大运动高度
            },

            LINAK =
            {
                Modbus =
                {
                    Id = 0,               --主站设备号
                    Ip = "192.168.5.123", --通讯IP
                    Port = 502            --通讯端口
                },
                MaxDistance = 900,        --升降柱最大运动高度
                HeartBeatTimes = 0        --心跳计数
            }
        }

    },

    Controller =
    {
        Modbus =
        {
            Id = 0,             --主站设备号
            Ip = "192.168.5.11", --通讯IP
            Port = 502,         --通讯端口
            LinkState = false   --连接状态
        }
    },

    Sucker =
    {
        Tcp =
        {
            Ip = "127.0.0.1",  --通讯IP
            Port = 60000,      --通讯端口
            Socket = 0,
            BaudRate = 115200, --RS485波特率 9600/19200/57600/115200
            Parity = "N",      --"N": 无校验/"O": 奇校验/"E": 偶校验
            DataBit = 8,       --数据位
            StopBit = 1,       --停止位 1/2
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
-----------------
SimulateProcess = {
    Id = '1',
    State = 0,                                     -- 0: 空闲 1: 运行中 2:停止
    MqttConnected = 0,                              -- 0: 未连接 1: 已连接 
    SimulateSpeed = 1,
    SimulateTime = 1000,
    Conveyor = {            
        Speed = 5000,                            --传送带速度
        Length = 2500,                           --传送带长度
        BoxInterval = 5,                        --箱子之间间隔
        Container = {},                           --容器
        FirstBoxArrived = nil,                               --0: 未到达   1已到达
        SecondBoxArrived = nil,                              --0: 未到达   1已到达
        BoxArrived = {},
        PickDelayTime = 0,
        PlaceDelayTime = 0
    },    
    Conveyor1 = {            
        Speed = 5000,                            --传送带速度
        Length = 2500,                           --传送带长度
        BoxInterval = 5,                        --箱子之间间隔
        Container = {},                          --容器
        FirstBoxArrived = nil,                     --0: 未到达   1已到达
        SecondBoxArrived = nil,                    --0: 未到达   1已到达
        BoxArrived = {},
        PickDelayTime = 0,
        PlaceDelayTime = 0
    },
    LiftingColumn = {
        Speed = 100,                              --抬升速度
        Length = 900,                             --最大抬升高度
        LiftingHeight = 0,                        --抬升高度
        UsedTime = 0                              --抬升时间
    },
    GenerateInterval = 500,
    PickDelayTime = 0,                                     --等待箱子被拿走时间
    BoxOnRobot = {},                              --在机械臂上的箱子
    LeftPallet = {                  
        Container = {},
        CanCount = 1                                   --1:剁数可被计数，--0：不计被计数
    },
    RightPallet = {
        Container = {},
        CanCount = 1                                   --1:剁数可被计数，--0：不计被计数
    },
    LayerNum = 1,                                   --当前操作层数
    LayerBoxIndex = 0,                              --当前层的箱子索引
    LayerBoxNum = 0,                                --首层到当前层搬运的箱子数
    BoxCount = 0,                                   --已经搬运的箱子数量
    PickIndex = 1,                                   --吸取索引
    PresentConveyor = {},                            --当前传送带
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
        FirstArrived = 0,                            --是否第一个箱子已到达
        BoxCount = 0,                                --总码垛的箱子数
        TotalTime = 0,                               --总耗时
        LayerRate = 0,                               --码垛完一层时平均节拍
        PalletNum = 0,                               --剁数
        PalletTotalTime = 0,                          --剁有效计时
        PalletRate = 0                               --单栈板耗时
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
    Location =  0,
    Conveyor = 0, -- 0: 0号传送带 1: 1号传送带
    State = 0,   -- 0: 在传送带上， 1：在机械臂上  2：在栈板上 3: 销毁
    Pallet = 1,  -- 所属栈板
    Layer = 1,
    Index = 1,
    Child = 0,   -- 0: 子0, 1: 子1
    Pose = {}      -- 箱子最终位姿
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
function PublishClearAction(palletNum)
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id .. ':clearPallets', "[" .. palletNum .. "]", 0, false)
end

---------------------------------------------------------------
--发送填充栈板消息
function PublishFillAction(palletNum)
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id .. ':fillPallets', "[" .. palletNum .. "]", 0, false)
end

---------------------------------------------------------------
--延时
function SWait(Ms)
    Wait(math.ceil(Ms / SimulateProcess.SimulateSpeed))
end

-----------------------------------------------------------------------------------------
--队列全局变量
-----------------------------------------------------------------------------------------
--定义队列类
function CreateQueue()
    local Queue = {}
    Queue.__index = Queue

    function Queue.New()
        return setmetatable({
            _data = {},
            _head = 1,      -- 指向下一个要弹出的元素
            _tail = 1,      -- 指向下一个要插入的位置
            _locked = false --自旋锁标志
        }, Queue)
    end

    ------------------------------------------------
    --内部方法
    ------------------------------------------------
    --获取锁
    function Queue:_acquireLock()
        local startTime = os.clock()
        while (self._locked) do
            if (os.clock() - startTime) > 5 then
                Alarm("Queue lock timeout", ErrorMessage.Type.QueueTimeout)
            end
            Wait(1) -- 短暂等待，让出执行权
        end
        self._locked = true
    end

    --释放锁
    function Queue:_releaseLock()
        self._locked = false
    end

    -- 内部队列是否为空的检查
    function Queue:_isEmpty()
        return self._head >= self._tail
    end

    --压缩存储空间
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
    ------------------------------------------------
    --添加元素到队列尾部
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
    function Queue:Pop()
        self:_acquireLock()
        if self:_isEmpty() then
            self:_releaseLock()
            LogWarn("Queue Pop Point Error!")
            return nil
        end

        local Value = self._data[self._head]
        self._data[self._head] = nil -- 显式设置为nil，帮助垃圾回收
        self._head = self._head + 1

        -- 定期压缩存储空间（当空余空间太多时）
        if self._head > 1 and self._head > #self._data / 2 then
            self:_compact()
        end

        self:_releaseLock()
        return Value
    end

    --查看队列头部元素但不弹出
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
    function Queue:IsEmpty()
        self:_acquireLock()
        local Result = self._head >= self._tail
        self:_releaseLock()
        return Result
    end

    --获取队列当前大小
    function Queue:Size()
        self:_acquireLock()
        local Size = self._tail - self._head
        self:_releaseLock()
        return Size
    end

    --清空队列
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
AQueue = CreateQueue()
--栈板1队列
FQueue = AQueue.New()

--创建队列类
BQueue = CreateQueue()
--栈板2队列
SQueue = BQueue.New()
----------------------------------------------------------------------------------------
--公共函数
----------------------------------------------------------------------------------------
--清除table
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
---------------------------------------------------------------
--设置日志级别
function SetLogLevel(Level)
    if LogConfig.Level[Level] then
        LogConfig.CurrentLevel = LogConfig.Level[Level]
    else
        print("Invalid log level: " .. tostring(Level))
    end
end

---------------------------------------------------------------
--通用日志打印函数
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
---------------------------------------------------------------
--EWELLIX
---------------------------------------------------------------
--升降柱初始化
function EWLInit()
    return TCPStart(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5) --建立TCP连接
end

---------------------------------------------------------------
--升降柱使能
function EWLEnable(PowerOn)
    if PowerOn == 0 then
        TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
            Communication.Lifting.Brand.EWELLIX.Command.StopMoving)
    end
end

---------------------------------------------------------------
--获取升降柱位置
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
function EWLRun(Postion)
    local HRes = tostring(Postion)
    TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
        Communication.Lifting.Brand.EWELLIX.Command.MovePosition .. HRes .. "\n")
end

---------------------------------------------------------------
--GeMinG
---------------------------------------------------------------
--升降柱初始化
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
function SV660CGetPostion()
    local Data = GetHoldRegs(Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId, 0x0b07, 2, "U32")
    if (Data[1] == nil) then
        Alarm("Lifting Data Error!", ErrorMessage.Type.LiftingDataErr)
    end

    return Data
end

---------------------------------------------------------------
--运动升降柱位置
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
function ConvertSigned(Value)
    local HexString = string.format("%08X", string.unpack(">I", string.pack(">f", Value))) -- 将浮点数转换为十六进制字符串
    HexString = string.sub(HexString, 1, string.len(HexString) - 4)

    return tonumber(HexString, 16) -- 将十六进制字符串转换为十进制整数
end

---------------------------------------------------------------
--十进制整数转化成32位单精度浮点数
function ConvertFloat(Value)
    -- 将整数按 "ABCD" 字节序转换为32位单精度浮点数的二进制表示
    local b1 = (Value >> 24) & 0xFF
    local b2 = (Value >> 16) & 0xFF
    local b3 = (Value >> 8) & 0xFF
    local b4 = Value & 0xFF
    local FloatBinary = string.char(b2, b1, b4, b3) -- 将字节按 "ABCD" 字节序组合成字符串

    return string.unpack("f", FloatBinary)
end

---------------------------------------------------------------
--升降柱初始化
function ZC01Init()
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 0 })
    SetHoldRegs(CurrentId, 2, 1, { 0 })
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 6, 1, { ConvertSigned(100) })  --速度
    SetHoldRegs(CurrentId, 8, 1, { ConvertSigned(100) })  --加速度
    SetHoldRegs(CurrentId, 10, 1, { ConvertSigned(100) }) --减速度
    SetHoldRegs(CurrentId, 4, 1, { ConvertSigned(0) })
    SetHoldRegs(CurrentId, 1, 1, { 64 })
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 2 }) --绝对位置运动
    Wait(LiftingInTime)
    SetHoldRegs(CurrentId, 1, 1, { 3 })
end

---------------------------------------------------------------
--升降柱使能
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
function ZC01GetPostion()
    local Data = GetHoldRegs(Communication.Lifting.Brand.ZT3ILC.Modbus.Id, 202, 1)
    if (Data[1] == nil) then
        Alarm("Lifting Data Error!", ErrorMessage.Type.LiftingDataErr)
    end

    return Data
end

---------------------------------------------------------------
--运动升降柱位置
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
function LINAKStop()
    local CurrentId = Communication.Lifting.Brand.LINAK.Modbus.Id
    SetHoldRegs(CurrentId, 8194, 1, { 64259 })
end

----------------------------------------------------------------------------------
--升降柱心跳计数
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
function LINAKGetPostion()
    return GetHoldRegs(Communication.Lifting.Brand.LINAK.Modbus.Id, 8449, 1)[1]
end

---------------------------------------------------------------------------------
--运动升降柱位置
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
---------------------------------------------------------------
--初始化
function LightInit(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--黄灯亮
function YellowOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, ON)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--黄灯闪
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
function GreenOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, ON)
    DO(PalletNumber.TriLight.Red, OFF)
end

---------------------------------------------------------------
--绿灯闪
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
function RedOn(PalletNumber)
    DO(PalletNumber.TriLight.Yellow, OFF)
    DO(PalletNumber.TriLight.Green, OFF)
    DO(PalletNumber.TriLight.Red, ON)
end

---------------------------------------------------------------
--红灯闪
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
---------------------------------------------------------------
--暂停
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
---------------------------------------------------------------
--上传报错信息
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
function ClearError()
    ErrorMessage.Code = ErrorMessage.Type.NoErr
    CommitErrorMsg(ErrorMessage.Code)
    TriLightStatus(FirstPallet, Light.Init)
    TriLightStatus(SecondPallet, Light.Init)
    LogInfo("Initialized error message successfully!")
end
---------------------------------------------------------------
--报警
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
        ClearError()
    else
        LogInfo("Halting robot motion")
        Halt()  --立即停止机器人当前运动
    end
end
---------------------------------------------------------------
--Modbus相关命令
---------------------------------------------------------------
--创建Modbus连接
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
--读取栈板上已有料箱层数、剩余料箱数
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
        PalletNumber.PalletNum.NextBoxCount = 1
        PalletNumber.PalletNum.LayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1)
        PalletNumber.PalletNum.LayerCount = 1                                                  --托盘层数计数
        PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1) --托盘不满一层箱体的数量
        PalletNumber.ProcessNum.InitBoxCount = 0                                               --栈板料箱计数置位
        PalletNumber.PalletNum.AddBoxCount = 0
        PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
    end
    if (PalletNumber.Partition.Enable == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.Partition.RePartNum <= 0) then
                -- 仿真模式，不需要隔板数量报警
                if (SimulateMode == 1) then
                    PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                    return
                end
                Alarm("Partition is empty!", ErrorMessage.Type.PartErr)
                PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                WritePartNum(PalletNumber)
            end
            if (PalletNumber.Partition.RePartNum > PalletNumber.ProcessNum.PartitionNum) then
                PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
            end
        else
            if (PalletNumber.Partition.RePartNum >= PalletNumber.ProcessNum.PartitionNum) then
                -- 仿真模式，不需要隔板数量报警
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
function CommitCapacityPallet()
    WriteRobotModbus(Capacity.Num.Pallet, Capacity.RegisterID.Pallet)
    SetVal("PalletCapacity", Capacity.Num)
end
---------------------------------------------------------------
--上传产能箱子数据
function CommitCapacityBox()
    WriteRobotModbus(Capacity.Num.Box, Capacity.RegisterID.Box)
    SetVal("PalletCapacity", Capacity.Num)
end
---------------------------------------------------------------
--产能计数:检查箱体数量
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
end

---------------------------------------------------------------
--上传栈板状态
function CommitPalletStatus(PalletNumber)
    WriteRobotModbus(PalletNumber.StateValue.Status, PalletNumber.RegisterID.PalletStatus)
    local WorkState = (PalletNumber.Pallet == Left and "LWorkState" or "RWorkState")
    SetVal(WorkState, PalletNumber.StateValue.Status)
end
---------------------------------------------------------------
--获取栈板使能状态
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
function DropSignalDete(PalletNumber, DeteState, SuckerPort, Mode)
    if (Mode == DropType.Norm) then
        if (PalletNumber.Partition.Mode == MotionType.Part) and (PartCfg.Enable == true) then
            if (DeteState == OFF) and (CheckDORes(PartCfg.Port.Mode, PartCfg.Port.A) == ON) then
                Wait(Time.DropDetection)
                if (DeteState == OFF) and (CheckDORes(PartCfg.Port.Mode, PartCfg.Port.A) == ON) then
                    IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF) --数字输出控制吸盘关闭
                    Alarm("Partition Fall Down!", ErrorMessage.Type.DropErr)
                end
            end
        else
            if (DeteState == OFF) and (CheckDORes(SuckerCfg.Port.Mode, SuckerPort) == ON) then
                Wait(Time.DropDetection)
                if (DeteState == OFF) and (CheckDORes(SuckerCfg.Port.Mode, SuckerPort) == ON) then
                    IORes(SuckerCfg.Port.Mode, SuckerPort, OFF) --数字输出控制吸盘关闭
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
function DropDete(PalletNumber, Mode)
    local SwitchDropMode =
    {
        [0] = function() --关闭检测

        end,
        [1] = function() --光电检测
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
function IORes(Flag, Num, State)
    if (Flag == 0) then
        DO(Num, State)
    else
        ToolDO(Num, State)
    end
end
---------------------------------------------------------------
--检查吸盘输出信号类型
function CheckDORes(Flag, Num)
    if (Flag == 0) then
        return GetDO(Num)
    else
        return GetToolDO(Num)
    end
end

---------------------------------------------------------------
--检查输入信号状态
function CheckDIRes(Flag, Num)
    if (Flag == 0) then
        return DI(Num)
    else
        return GetToolDI(Num)
    end
end
