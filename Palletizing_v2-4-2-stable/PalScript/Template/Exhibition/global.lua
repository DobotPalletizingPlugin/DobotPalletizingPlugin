-------------------------------------------------------------------------------------------
-- 此文件仅用于定义变量和子函数。
-------------------------------------------------------------------------------------------
-- 栈板1全局变量
-------------------------------------------------------------------------------------------
FirstPallet = 
{
	StateValue = 
	{
        Status = 0, --栈板状态（上传至Modbus寄存器），
        --0代表未检测到栈板，1代表检测到栈板但未上使能，2代表码垛中，
        --3代表栈板已满，4代表报错（箱子掉落、码垛过程中栈板丢失）,5代表空闲中
        Cancel = 0, --取消栈板，0代表不取消，1代表取消（读取Modbus寄存器的值）
        Enable = 0  --使能栈板，0代表不使能，1代表使能（读取Modbus寄存器的值）				
    },
	
	State = 
	{
        Full = false,                --托盘满载布尔量（初始值）
        Empty = false,               --托盘空载布尔量（初始值）
        Replace = false,             --更换栈板状态
        Enable = true,               --托盘使能状态布尔量（上位机配置）
        EnableResult = false,        --栈板上使能的结果
        InPlaceOK = false,           --栈板到位确认标志
        FirstResetFlag = false,      --第1次判断栈板是否移开
        SecondResetFlag = false,     --第2次判断栈板是否到位
        ReplaceNewPalletFlag = false --栈板丢失标志位
    },

    PalletNumStr =
    {
        Layer = "Layer",
        RemainBoxNum = "RemainBoxNum",
        LayerBoxNum = "LayerBoxNum",
        AddBoxCount = "AddBoxCount",
        NextBoxCount = "NextBoxCount",
        PartitionNum = "PartitionNum"
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
        PartitionHeight = 0,      --隔板高度（上位机配置）
        PartitionNum = 10,        --隔板数量（上位机配置）
        PartitionWeight = 2       --隔板重量（上位机配置）
    },
    PalletNum =
    {
        NextBoxCount = 1, --栈板下一个箱体计数（上传至Modbus寄存器）
        AddBoxCount = 0,  --双吸双放料箱额外计数（上传至Modbus寄存器）
        LayerCount = 0,   --托盘层数计数，表示多少层已放满（上传至Modbus寄存器）
        LayerBoxNum = 0,  --从首层到当前层理论最大箱体序号数（上传至Modbus寄存器）
        RemainBoxNum = 0, --托盘不满一层箱体的数量（上传至Modbus寄存器）
        PartitionNum = 10 --隔板数量（上位机配置）
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
        Sucker = 0,   --吸盘属性，单吸 = 0，双吸 = 1
        SuckerRz = 90,    --吸盘RZ旋转补偿量(-90/0/90/180)
        BoxDirection = 0, --箱子来料方向，0：箱体长边与来料方向垂直，1：箱体短边与来料方向垂直
    },
	
    AutoGenPoint =
    {
        TransPoint =
        {
            {}
        },
        PartTransPoint =
        {
            {}
        }
    },
    TeachPoint =
	{
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
	
    PalletMode = 2,             --码垛模式选择，1为码垛，2为拆垛
    OffsetHeight = 100,         --栈板放置点（拆垛抓取点）偏移高度
    TransPointMode = 0,         --过渡点获取方式，0：示教，1：自动生成
    TransPlacePointNum = 1,     --放料过渡点数量
    TransPartitionPointNum = 1, --隔板过渡点数量
    Partition =                 --隔板配置
    {
        Enable = false,         --隔板功能，false: 关闭，true：开启
        Layer = {},             --隔板放置层位置
        Mode = 0,               --隔板标志位，0：常规点位，1: 隔板点位
        Last = false,           --最后隔板运动信号
        LastPlan = false,       --规划最后隔板运动信号
    },
    MultSensorFunction = 0,     --多传感器功能 0：关闭， 1：开启
    Layer = 0,                  --码垛总层数
    CompensateZData = 0,        --开始补偿放置位置Z轴向大小
    CompensateLayer = 0,        --开始补偿放置位置Z轴向的层数
    J4UpperLimit = 0,           --关节4允许极限角上限（暂不启用）
    J4LowerLimit = 0,           --关节4允许极限角下限（暂不启用）
    NearFlag = false,
    Near = { joint = { 135, 5, 90, 0, -90, -10 } },
    
	Coordinate = 
    {
        PartitionUserNum = 0, --选择隔板的User编号
        UserNum = 0,          --选择的User编号
        ToolNum = 0           --选择的TCP编号
    },
	
    BoxBeInpPlaceDI1 = 1, --箱体到位检测DI 1
    BoxBeInpPlaceDI2 = 2, --箱体到位检测DI 2
    InPlaceA = 3,         --栈板到位信号DI 3
    InPlaceB = 4,         --栈板到位信号DI 4
    InPlaceOK = 9,           --栈板放置确认按钮DI 9
    RestrictMoveSignal = 23, --限制垛型高度信号
	
	TriLight = 
	{
        Yellow = 1, --栈板三色灯黄灯DO 1
        Green = 2,  --栈板三色灯绿灯DO 2
        Red = 3     --栈板三色灯红灯DO 3
    },

	RegisterID = 
    {
        PalletStatus = 5000, --码垛状态寄存器地址
        Layer = 5002,        --当前码垛层数寄存器地址
        RemainBoxNum = 5003, --当前层剩余料箱寄存器地址
        PalletCancel = 5006, --取消栈板寄存器地址
        PalletEnable = 5007, --使能栈板寄存器地址
        NextBoxCount = 5010, --下一个箱体数寄存器地址
        LayerBoxNum = 5020,  --首层到当前层最大箱体序号数量寄存器地址
        AddBoxCount = 5022,  --双吸双放料箱额外计数寄存器地址
        PartitionNum = 5024, --隔板数量寄存器地址
        PalletMode = 5026    --码垛模式寄存器地址
	}
}

------------------------------------------------------------------------------------------
-- 栈板2全局变量
-------------------------------------------------------------------------------------------
SecondPallet = 
{
	StateValue = 
	{
		Status = 0, 							--栈板状态（上传至Modbus寄存器），
        --0代表未检测到栈板，1代表检测到栈板但未上使能，2代表码垛中，
        --3代表栈板已满，4代表报错（箱子掉落、码垛过程中栈板丢失）,5代表空闲中
		Cancel = 0,   							--取消栈板，0代表不取消，1代表取消（读取Modbus寄存器的值）
		Enable = 0  							--使能栈板，0代表不使能，1代表使能（读取Modbus寄存器的值）				
    },
	
	State = 
	{
		Full = false,           				--托盘满载布尔量（初始值）
		Empty = false,        	 				--托盘空载布尔量（初始值）
		Replace = false,     	 				--更换栈板状态
		Enable = true,		 					--托盘使能状态布尔量（上位机配置）
		EnableResult = false,					--栈板上使能的结果
        InPlaceOK = false, 						--栈板到位确认标志
		FirstResetFlag = false,  				--第1次判断栈板是否移开
		SecondResetFlag = false,  				--第2次判断栈板是否到位
		ReplaceNewPalletFlag = false        	--栈板丢失标志位
    },

    PalletNumStr =
    {
        Layer = "Layer",
        RemainBoxNum = "RemainBoxNum",
        LayerBoxNum = "LayerBoxNum",
        AddBoxCount = "AddBoxCount",
        NextBoxCount = "NextBoxCount",
        PartitionNum = "PartitionNum"
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
        PartitionHeight = 0,      --隔板高度（上位机配置）
        PartitionNum = 10,        --隔板数量（上位机配置）
        PartitionWeight = 2       --隔板重量（上位机配置）
    },
    
    PalletNum =
    {
        NextBoxCount = 1, --栈板下一个箱体计数（上传至Modbus寄存器）
        AddBoxCount = 0,  --双吸双放料箱额外计数（上传至Modbus寄存器）
        LayerCount = 0,   --托盘层数计数，表示多少层已放满（上传至Modbus寄存器）
        LayerBoxNum = 0,  --从首层到当前层理论最大箱体序号数（上传至Modbus寄存器）
        RemainBoxNum = 0, --托盘不满一层箱体的数量（上传至Modbus寄存器）
        PartitionNum = 10 --隔板数量（上位机配置）
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
        Sucker = 0,   --吸盘属性，单吸 = 0，双吸 = 1
        SuckerRz = 90,    --吸盘RZ旋转补偿量(-90/0/90/180)
        BoxDirection = 0 --箱子来料方向，0：箱体长边与来料方向垂直，1：箱体短边与来料方向垂直
    },

    AutoGenPoint =
    {
        TransPoint =
        {
            {}
        },
        PartTransPoint =
        {
            {}
        }
    },
    TeachPoint =
	{
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
	
    PalletMode = 1,             --码垛模式选择，1为码垛，2为拆垛
    OffsetHeight = 100,         --栈板放置点（拆垛抓取点）偏移高度
    TransPointMode = 0,         --过渡点获取方式，0：示教，1：自动生成
    TransPlacePointNum = 1,     --放料过渡点数量
    TransPartitionPointNum = 1, --隔板过渡点数量
    Partition =                 --隔板配置
    {
        Enable = false,         --隔板功能，false: 关闭，true：开启
        Layer = {},             --隔板放置层位置
        Mode = 0,               --隔板标志位，0：常规点位，1: 隔板点位
        Last = false,           --最后隔板运动信号
        LastPlan = false,       --规划最后隔板运动信号
    },
    MultSensorFunction = 0,     --多传感器功能 0：关闭， 1：开启
    Layer = 0,                  --码垛总层数
    CompensateZData = 0,        --开始补偿放置位置Z轴向大小
    CompensateLayer = 0,        --开始补偿放置位置Z轴向的层数
    J4UpperLimit = 0,           --关节4允许极限角上限（暂不启用）
    J4LowerLimit = 0,           --关节4允许极限角下限（暂不启用）
    NearFlag = false,
    Near = { joint = { 45, 5, 90, 0, -90, -10 } },
    
	Coordinate = 
    {
        PartitionUserNum = 0, --选择隔板的User编号
        UserNum = 0,          --选择的User编号
        ToolNum = 0           --选择的TCP编号
    },
	
    BoxBeInpPlaceDI1 = 5, --箱体到位检测DI 5
    BoxBeInpPlaceDI2 = 6, --箱体到位检测DI 6
    InPlaceA = 7,         --栈板到位信号DI 7
    InPlaceB = 8,         --栈板到位信号DI 8
    InPlaceOK = 10,          --栈板放置确认按钮DI 10
    RestrictMoveSignal = 24, --限制垛型高度信号

    TriLight =
	{
        Yellow = 4, --栈板三色灯黄灯DO 4
        Green = 5,  --栈板三色灯绿灯DO 5
        Red = 6     --栈板三色灯红灯DO 6
    },
	
    RegisterID =
    {
        PalletStatus = 5001, --码垛状态寄存器地址
        Layer = 5004,        --当前码垛层数寄存器地址
        RemainBoxNum = 5005, --当前层剩余料箱寄存器地址
        PalletCancel = 5008, --取消栈板寄存器地址
        PalletEnable = 5009, --使能栈板寄存器地址
        NextBoxCount = 5011, --下一个箱体数寄存器地址
        LayerBoxNum = 5021,  --首层到当前层最大箱体序号数量寄存器地址
        AddBoxCount = 5023,  --双吸双放料箱额外计数寄存器地址
        PartitionNum = 5025, --隔板数量寄存器地址
        PalletMode = 5027    --码垛模式寄存器地址
	}
}

----------------------------------------------------------------------------------------------
--通讯相关全局变量
----------------------------------------------------------------------------------------------
Communication =
{
    Lifting =
    {
        RestrictMoveFlag = false, --限制运动标志位
        StartHeightDiff = 1500,   --开始高度差
        EndHeightDiff = 1000,     --结束高度差
        TimesPerHour = 0,         --升降柱每小时运动次数
        MaxtimesPerHour = 35,     --升降柱每小时最大运动次数
        StopLiftingFlag = false,  --升降柱停止标志位
        Mode = 0,                 --升降柱型号选择，0：EWELLIX，1：GeMinG，2：ZT3ILC
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
                MaxDistance = 900     --升降柱最大运动高度
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
            }
        }

    },

    Controller =
    {
        Modbus =
        {
            Id = 0,             --主站设备号
            Ip = "192.168.5.1", --通讯IP
            Port = 502,         --通讯端口
            SuccessFlag = false --连接成功标志位
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

--------------------------------------------------------------------------------
--升降柱命令
--------------------------------------------------------------------------------
--GeMinG
--------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------
--升降柱使能
function SV660CEnable(PowerOn)
    local CurrentId = Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId
    if PowerOn == 1 then
        SetHoldRegs(CurrentId, 0x3100, 1, { 1 }, "U16")
    else
        SetHoldRegs(CurrentId, 0x3100, 1, { 0 }, "U16")
    end
end

----------------------------------------------------------------------------------
--获取升降柱位置
function SV660CGetPostion()
    return GetHoldRegs(Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId, 0x0b07, 2, "U32")
end

----------------------------------------------------------------------------------
--运动升降柱位置
function SV660CRun(Postion)
    local CurrentId = Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId
    if Postion == nil then
        print("Postion Is Nil")
    end
    SetHoldRegs(CurrentId, 0x110c, 2, { Postion }, "U32")
    SetHoldRegs(CurrentId, 0x3100, 1, { 1 }, "U16")
    SetHoldRegs(CurrentId, 0x3100, 1, { 3 }, "U16")
end

--------------------------------------------------------------------------------
--ZT3ILC_ZC01
--------------------------------------------------------------------------------
--32位单精度浮点数转化成十六进制整数
function ConvertSigned(Value)
    local HexString = string.format("%08X", string.unpack(">I", string.pack(">f", Value))) -- 将浮点数转换为十六进制字符串
    HexString = string.sub(HexString, 1, string.len(HexString) - 4)

    return tonumber(HexString, 16) -- 将十六进制字符串转换为十进制整数
end

--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------
--升降柱初始化
function ZC01Init()
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 0 })
    SetHoldRegs(CurrentId, 2, 1, { 0 })
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    Wait(500)
    SetHoldRegs(CurrentId, 6, 1, { ConvertSigned(100) })  --速度
    SetHoldRegs(CurrentId, 8, 1, { ConvertSigned(100) })  --加速度
    SetHoldRegs(CurrentId, 10, 1, { ConvertSigned(100) }) --减速度
    SetHoldRegs(CurrentId, 4, 1, { ConvertSigned(0) })
    SetHoldRegs(CurrentId, 1, 1, { 64 })
    Wait(500)
    SetHoldRegs(CurrentId, 1, 1, { 0 })
    SetHoldRegs(CurrentId, 3, 1, { 2 }) --绝对位置运动
    Wait(500)
    SetHoldRegs(CurrentId, 1, 1, { 3 })
end

---------------------------------------------------------------------------------
--升降柱使能
function ZC01Enable(PowerOn)
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    if PowerOn == 1 then
        SetHoldRegs(CurrentId, 1, 1, { 3 })
    else
        SetHoldRegs(CurrentId, 1, 1, { 0 })
    end
end

-------------------------------------------------------------------------------------------
--获取升降柱位置
function ZC01GetPostion()
    return GetHoldRegs(Communication.Lifting.Brand.ZT3ILC.Modbus.Id, 202, 1)
end

---------------------------------------------------------------------------------
--运动升降柱位置
function ZC01Run(Postion)
    local CurrentId = Communication.Lifting.Brand.ZT3ILC.Modbus.Id
    if ConvertSigned(Postion) == nil then
        print("Postion Is Nil")
    end
    Wait(500)
    SetHoldRegs(CurrentId, 4, 1, { ConvertSigned(Postion) })
    SetHoldRegs(CurrentId, 1, 1, { 3 })
    SetHoldRegs(CurrentId, 1, 1, { 131 })
end

-------------------------------------------------------------------------------------------
-- 公共全局变量
-------------------------------------------------------------------------------------------
WorkFinishFlag = false          --码垛拆垛完成标志位
FinishFlag = false              --码垛完成标志位
SwitchConveyorFlag = 1          --传送带切换标志位
IsReady = false                 --开始运行码垛、卸垛的状态变量（初始值）
Pallet = 0                      --码垛任务标识，0:为第一栈板，1:为第二栈板
WorkingMode = 0                 --工作模式 0：单传送带码垛，1：双传送带单侧码垛，2：双传送带交替码垛
PalletName = "Pallet"           --配方名称
PalletChosenFlag = false        --栈板选择完成标志位
PalletFinishFlag = true         --码垛一次标志位
PalletNumInitFlag = false       --码垛计数初始化完成标志位
PalletBeInPlaceOKButton = false --启动栈板到位确认按钮
PalletLiftingFunction = false   --升降柱功能状态布尔量
PalletObstacleFunc = 0          --启用自动过渡点障碍物功能，0：关闭，1启用
MultPalletFunction = false      --多栈板功能
BoxBeInpPlaceFlag = 1           --传送带标志位
PalletSuckerFunction = 1        --多吸盘功能, -1：通讯控制单吸, 1：通用单吸， 2：通用双吸
DropDetectionFunction = false   --掉料检测功能 false：关闭， true：开启
RestrictMoveFunction = false    --两侧垛型高度差限制功能，false：关闭，true：开启
RemainingTotalPalletCount = 0
RemainingTotalBoxCount = 0
TotalPalletCountStr = "TotalPalletCount"
TotalBoxCountStr = "TotalBoxCount"
TotalPalletCount = 0 --产能数据：总栈板数（上传至Modbus寄存器）
TotalBoxCount = 0    --产能数据：总料箱数（上传至Modbus寄存器）
Hour = 0             --产能数据：工作时长，时：分：秒（上传至Modbus寄存器）
Minute = 0
Second = 0
BeReachableButtonValue = 0 --栈板到位检查按钮，0代表未启动按钮，1代表启动按钮
PointType =                --点位类型
{
    PickPoint =
    {
        NoPartition = 1,
        WithPartition = 2
    }, --取料点
    PickOffsetPoint =
    {
        NoPartition = 3,
        WithPartition = 4
    }, --取料上方点
    TransPoint =
    {
        NoPartition = 5,
        WithPartition = 6
    }, --过渡点
    InsertPoint =
    {
        NoPartition = 7,
        WithPartition = 8
    }, --放料偏移点
    PlaceOffsetPoint =
    {
        NoPartition = 9,
        WithPartition = 10
    }, --放料上方点
    PlacePoint =
    {
        NoPartition = 11,
        WithPartition = 12
    }, --放料点
}
PartCfg =           --独立隔板控制配置
{
    Enable = false, --false：关闭，true：打开
    Port =
    {
        Mode = 0, --IO类型, 0：通用IO，1：末端IO
        A = 22
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
        A = 1,
        B = 2,
        C = 3,
        D = 4,
    },

    Dete =        --信号检测类型
    {
        Mode = 0, --掉料检测模式, 0：关闭， 1：光电检测， 2：真空检测
        PE =      --光电检测
        {
            A = 1,
            B = 2,
            C = 3,
            D = 4
        },
        Vacuum = --真空检测
        {
            A = 1,
            B = 2,
            C = 3,
            D = 4
        },
        VacuumBreak =   --破真空检测
        {
            Enable = 0, --0：关闭，1：开启
            Mode = 0,   --IO类型, 0：通用IO，1：末端IO
            A = 1,
            B = 2,
            C = 3,
            D = 4
        }
    }
}
Time =       --延时参数
{
    Thread = --线程等待时间ms
    {
        s0 = 4,
        s1 = 4,
        s2 = 1000,
        s3 = 1000,
        s4 = 1000
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
    DropDetection = 0 --吸盘延迟检测时间
}
--报错信息（上传至Modbus寄存器），0代表无报错
--1代表机器人与升降轴通信失败
--2代表点位不可达
--3代表检测到栈板丢失
--4代表高度限制功能开启，双侧传送带停止工作
--5代表物品掉落
--6启动带料
--7隔板已空/已满
--8创建Modbus通信失败,请检查Modbus地址
--9升降柱运动次数过多
--10（预留相机相关）
--11（预留相机相关）
--12升降柱状态异常
--13（预留相机相关）
ErrorMessage = --报警信息
{
    Code = 0,  --报警码
    PointInfo =
    {
        Type = 0,     --类型
        Layer = 0,    --层数
        Index = 0,    --序号
        PalletNum = 0 --工作栈板号
    }
}

ToolSpeedWithBox = 0                                         --带箱体工具速度比例
ToolAccWithBox = 0                                           --带箱体工具加速度比例
PlaceSpeed = 0                                               --放置箱体速度比例
PlaceAcc = 0                                                 --放置箱体加速度比例
ToolSpeedWithoutBox = 0                                      --不带箱体工具速度比例
ToolAccWithoutBox = 0                                        --不带箱体工具加速度比例
ToolHigh = 0                                                 --工具高度
ToolWeight = 0                                               --工具重量
Joint3Angle = 15                                             --关节3允许极限角绝对值
TeachPointOffHeight = 300                                    --取料示教点偏移高度
HomePoint = { joint = { 90, 0, 90, 0, -90, 0 } }             --安全点
PartSafePoint = { joint = { 90, 0, 90, 0, -90, 0 } }         --隔板安全点
LiftingSafetyPoint = { joint = { 90, -29, 114, 4, -90, 0 } } --空载升降柱上升安全点
LiftingSafetyPoint_HL = { joint = { 90, -45, 120, 15, -90, 0 } } --空载升降柱上升安全点
HighLoadFunc = false                                             --高负载功能：false：关闭，true：打开

BuzzerFunction = false                                       --蜂鸣器功能开关，false：关闭，true：打开
BuzzerIO = 24                                                --蜂鸣器IO

PartSignalMode = 0                                           --控制隔板取放IO类型 0：通用IO，1：末端IO
PartitionSignal = 22                                         --隔板取放IO信号	
PartitionSignalFunction = false                                  --独立隔板IO信号开关，false：关闭，true：打开
FilmDI = 24                                                  --缠膜IO
FilmFlag = true                                              --缠膜标志位
FilmFunction = true                                          --缠膜功能标志位

----------------------------------------------------------------------------------
--回调函数
----------------------------------------------------------------------------------
--暂停
function callBackStopLifting()
    local SwitchStopMode =
    {
        [0] = function()
            TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                Communication.Lifting.Brand.EWELLIX.Command.StopMoving)
        end,
        [1] = function()
            SV660CEnable(1)
        end,
        [2] = function()
            ZC01Enable(0)
        end,
    }
    local switch_mode = SwitchStopMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
    else
        print("The SwitchStopMode is error, please check it!")
    end
    print("脚本暂停，升降柱停止运动！")
    Communication.Lifting.StopLiftingFlag = true
end

RegistePauseHandler("callBackStopLifting")

-----------------------------------------------------------------------------------
--公共函数
-----------------------------------------------------------------------------------
-- 复制table
function DeepCopy(Object)
    local function Func(Object)
        if type(Object) ~= "table" then
            return Object
        end
        local NewTable = {}
        for k, v in pairs(Object) do
            NewTable[Func(k)] = Func(v)
        end

        return setmetatable(NewTable, getmetatable(Object))
    end

    return Func(Object)
end

------------------------------------------------------------------------------------
--检查table中存在非0 数据
function CheckTableData(T)
    for k, v in pairs(T) do
        if (v ~= 0) and (v ~= nil) then
            return 1
        end
    end
    return 0
end

-----------------------------------------------------------------------------------
--逆解参考关节
NearJoint = {}
NearLeftJoint = { 135, 5, 90, 0, -90, -10 }
NearRightJoint = { 45, 5, 90, 0, -90, -10 }
SwitchJoint =
{
    [0] = function()
        NearJoint = NearLeftJoint
    end,
    [1] = function()
        NearJoint = NearRightJoint
    end
}
----------------------------------------------------------------------------------
--上传报错信息
function CommitErrorMessage()
    WriteRobotModbus(ErrorMessage.Code, 5030)
    if ErrorMessage.Code == 2 then
        WriteRobotModbus(ErrorMessage.PointInfo.Type, 5031)
        WriteRobotModbus(ErrorMessage.PointInfo.Layer, 5032)
        WriteRobotModbus(ErrorMessage.PointInfo.Index, 5033)
        WriteRobotModbus(ErrorMessage.PointInfo.PalletNum, 5034)
    end
end

----------------------------------------------------------------------------------
--报警
function Alarm(...)
    local SwitchStopMode =
    {
        [0] = function()
            TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                Communication.Lifting.Brand.EWELLIX.Command.StopMoving)
        end,
        [1] = function()
            SV660CEnable(0)
        end,
        [2] = function()
            ZC01Enable(0)
        end,
    }
    local switch_mode = SwitchStopMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
    else
        print("The SwitchStopMode is error, please check it!")
    end
    CommitErrorMessage()
    Pause() --立即停止机器人当前运动
    print(ErrorMessage.Code)
    print(...)
    Wait(100)
    ErrorMessage.Code = 0
    CommitErrorMessage()
end

-----------------------------------------------------------------------------------
--创建Modbus连接
function CreateModbusConnection()
    local Err = 0
    Err, Communication.Controller.Modbus.Id = ModbusCreate(Communication.Controller.Modbus.Ip,
        Communication.Controller.Modbus.Port)
    if Err == 0 then
        print("创建Modbus通信成功！！！")
        Communication.Controller.Modbus.SuccessFlag = true
    else
        while true do
            Communication.Controller.Modbus.SuccessFlag = false
            if Pallet == 0 then
                DO(FirstPallet.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
                DO(FirstPallet.TriLight.Green, OFF)  --栈板码垛中，绿灯常亮
                DO(FirstPallet.TriLight.Red, ON)     --栈板报错，红灯常亮
                Wait(500)
                DO(FirstPallet.TriLight.Yellow, OFF)
                Wait(500)
            else
                DO(SecondPallet.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
                DO(SecondPallet.TriLight.Green, OFF)  --栈板码垛中，绿灯常亮
                DO(SecondPallet.TriLight.Red, ON)     --栈板报错，红灯常亮
                Wait(500)
                DO(SecondPallet.TriLight.Yellow, OFF)
                Wait(500)
            end
            ErrorMessage.Code = 8
            Alarm("创建Modbus通信失败,请检查Modbus地址！")
        end
    end
end

-----------------------------------------------------------------------------------
--从Modbus寄存器中读取命令
function ReadRobotModbus(Address)
    local buffer = GetHoldRegs(Communication.Controller.Modbus.Id, Address, 1, "U16")
    while buffer[1] == nil do
        print("Modbus register data is nil")
        buffer = GetHoldRegs(Communication.Controller.Modbus.Id, Address, 1, "U16")
    end
    
	return buffer[1]
end

---------------------------------------------------------------
--读取栈板上使能的动作标志
function ReadStatePallet(StateValue, RegisterID)
	StateValue.Cancel = ReadRobotModbus(RegisterID.PalletCancel)
	StateValue.Enable = ReadRobotModbus(RegisterID.PalletEnable)
end

---------------------------------------------------------------
--读取栈板上已有料箱层数、剩余料箱数
function ReadPalletNum(PalletNumber, PalletData, NameStr)
    PalletNumber.PalletNum.LayerCount = ReadRobotModbus(PalletNumber.RegisterID.Layer)
    if PalletNumber.PalletNum.LayerCount < 1 then
        PalletNumber.ProcessNum.BoxCount = 0 --托盘箱体计数
        PalletNumber.PalletNum.NextBoxCount = 1
        PalletNumber.PalletNum.LayerBoxNum = GetOddBoxCnt(NameStr, PalletData, 1)
        PalletNumber.PalletNum.LayerCount = 1                                      --托盘层数计数
        PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(NameStr, PalletData, 1) --托盘不满一层箱体的数量
        PalletNumber.ProcessNum.InitBoxCount = 0                                   --栈板料箱计数置位
        PalletNumber.PalletNum.AddBoxCount = 0
    end
    PalletNumber.PalletNum.RemainBoxNum = ReadRobotModbus(PalletNumber.RegisterID.RemainBoxNum)
    PalletNumber.PalletNum.LayerBoxNum = ReadRobotModbus(PalletNumber.RegisterID.LayerBoxNum)
    PalletNumber.PalletNum.AddBoxCount = ReadRobotModbus(PalletNumber.RegisterID.AddBoxCount)
    PalletNumber.PalletNum.NextBoxCount = ReadRobotModbus(PalletNumber.RegisterID.NextBoxCount)
    if PalletNumber.PalletNum.NextBoxCount < PalletNumber.PalletNum.AddBoxCount then
        print("ReadPalletNum:PalletNum.AddBoxCount is Wrong!")
        Pause()
    end

    PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount - PalletNumber.PalletNum.AddBoxCount
end

---------------------------------------------------------------
--读取产能数据
function ReadProductionData()
    RemainingTotalPalletCount = ReadRobotModbus(5012)
    RemainingTotalBoxCount = ReadRobotModbus(5013)
end
----------------------------------------------------------------------------------
----------------------------------------------------------------------------------
--机器人写数据到Modbus寄存器
function WriteRobotModbus(Data, Address)
    local buffer = { Data }
    SetHoldRegs(Communication.Controller.Modbus.Id, Address, #buffer, buffer, "U16")
end

----------------------------------------------------------------------------------
--上传已有料箱层数、剩余料箱数和下一料箱号
function CommitPalletNum(PalletNumber)
    WriteRobotModbus(PalletNumber.PalletNum.LayerCount, PalletNumber.RegisterID.Layer)
    WriteRobotModbus(PalletNumber.PalletNum.AddBoxCount, PalletNumber.RegisterID.AddBoxCount)
	WriteRobotModbus(PalletNumber.PalletNum.NextBoxCount + PalletNumber.PalletNum.AddBoxCount,
					 PalletNumber.RegisterID.NextBoxCount)
    WriteRobotModbus(PalletNumber.PalletNum.RemainBoxNum, PalletNumber.RegisterID.RemainBoxNum)
    WriteRobotModbus(PalletNumber.PalletNum.LayerBoxNum, PalletNumber.RegisterID.LayerBoxNum)
end

----------------------------------------------------------------------------------
--上传产能数据
function CommitProductionData()
    WriteRobotModbus(TotalBoxCount, 5013)
end

---------------------------------------------------------------
--上传栈板状态
function CommitPalletStatus(StateValue, RegisterID)
    WriteRobotModbus(StateValue.Status, RegisterID.PalletStatus)
end
---------------------------------------------------------------
--得到栈板到位状态结果	
function GetPalletStatusResult(State, InPlaceA, InPlaceB)
    if PalletBeInPlaceOKButton == true then
        State.Replace = (DI(InPlaceA) == ON) and (DI(InPlaceB) == ON) and (State.InPlaceOK == true)
    else
        State.Replace = (DI(InPlaceA) == ON) and (DI(InPlaceB) == ON)
    end
end

---------------------------------------------------------------
--得到栈板上使能的结果
function GetPalletEnableResult(State, StateValue)
    if State.Enable == true then
        if StateValue.Cancel == 0 then
            State.EnableResult = true
        else
            State.EnableResult = false
        end
    else
        if StateValue.Enable == 1 then
            State.EnableResult = true
        else
            State.EnableResult = false
        end
    end
end

---------------------------------------------------------------
--码垛/拆垛计数
local function PalletCountAction(PalletNumber)
    PalletNumber.ProcessNum.PalletBoxCount =
        math.abs(PalletNumber.PalletNum.AddBoxCount - PalletNumber.ProcessNum.RemainingAddBoxCount)
        + math.abs(PalletNumber.ProcessNum.BoxCount - PalletNumber.ProcessNum.InitBoxCount)
end
---------------------------------------------------------------
--计数:检查箱体的数量
function PlaceCountPallet(PalletNumber)
    --托盘箱体的数量
    if WorkingMode == 2 then
        if Pallet == 0 then
            PalletCountAction(FirstPallet)
        end
        if Pallet == 1 then
            PalletCountAction(SecondPallet)
        end
        TotalBoxCount = RemainingTotalBoxCount + FirstPallet.ProcessNum.PalletBoxCount +
            SecondPallet.ProcessNum.PalletBoxCount
    else
        TotalBoxCount = RemainingTotalBoxCount
            + math.abs(PalletNumber.PalletNum.AddBoxCount - PalletNumber.ProcessNum.RemainingAddBoxCount)
            + math.abs(PalletNumber.ProcessNum.BoxCount - PalletNumber.ProcessNum.InitBoxCount)
    end

    CommitProductionData() --上传产能数据
end

---------------------------------------------------------------
--吸盘输出信号类型
function IORes(Flag, Num, State)
    if Flag == 0 then
        DO(Num, State)
    else
        ToolDO(Num, State)
    end
end

---------------------------------------------------------------
--检查吸盘输出信号类型
function CheckIORes(Flag, Num)
    if Flag == 0 then
        return GetDO(Num)
    else
        return GetToolDO(Num)
    end
end
