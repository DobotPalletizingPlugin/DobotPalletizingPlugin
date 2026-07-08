--------------------------------------------------------------
-- 状态更新文件
-- state update file
-- 本文件负责初始化左右栈板工作数据、更新箱数/层数/隔板数量、处理换栈板和栈板丢失屏蔽。
---------------------------------------------------------------
-- 状态更新文件双语注释说明
-- 本文件负责维护工作数据：当前箱数、层数、剩余箱数、隔板数量、栈板更换、栈板丢失屏蔽和状态上传。
-- src0执行完一次动作后，src2根据码垛/拆垛模式更新ProcessNum和PalletNum，保证下一次点位计算读取正确状态。
-- 隔板数量在本项目中由传感器同步，避免只依赖软件计数导致现场数量和HMI数量不一致。
-- State update file bilingual comment guide
-- This file maintains working data: current box count, layer count, remaining boxes, remaining partitions, pallet replacement, pallet-loss masking, and state upload.
-- After src0 finishes one motion cycle, src2 updates ProcessNum and PalletNum according to palletizing/depalletizing mode so the next point calculation uses the correct state.
-- In this project, partition quantity is synchronized from a sensor to avoid mismatch between the real magazine quantity and HMI/software counters.
---------------------------------------------------------------
-- src0负责执行运动，src2负责把运动结果写回工作状态。
--------------------------------------------------------------
-- 局部变量
-- local variables
local mqttFunc = require("libplugin_eco")
local RePalletSTime = 0 --栈板丢失开始屏蔽时间
local RePalletETime = 0 --栈板丢失结束屏蔽时间
---------------------------------------------------------------
-- 初始化当前工作栈板。
-- initialize the active pallet side
-- 左右双栈板时，完成一侧后切换到另一侧；单栈板时保持当前侧。
local function InitPallet(PalletNumber)
    if (PalletNumber.Pallet == Left) then
        Pallet = Right
        LogInfo("Switching active pallet to right!")
    else
        Pallet = Left
        LogInfo("Switching active pallet to left!")
    end

end
--------------------------------------------------------------
-- 生成仿真对象随机编号
-- generate random ID for simulation object
local function GenerateRandomId(length)
    local id = ""
    local characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    math.randomseed(os.time()) -- 使用当前时间作为随机数种子
    for i = 1, length do
        local charIndex = math.random(1, #characters)
        id = id .. string.sub(characters, charIndex, charIndex)
    end
    return id
end
---------------------------------------------------------------
--初始化单侧栈板的工作数据。
-- 码垛模式从0开始累计箱数；拆垛模式从满托盘数量开始递减。
-- 同时初始化当前层数、下一箱序号、剩余层内箱数和隔板数量。
local function InitWorkingData(PalletNumber)
    PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(PalletName, PalletNumber.Pallet)
    if PalletNumber.Mode == WorkType.Pallet then
        PalletNumber.ProcessNum.BoxCount = 0 --托盘箱体计数
        PalletNumber.PalletNum.NextBoxCount = 1
        PalletNumber.PalletNum.LayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1)
        PalletNumber.PalletNum.LayerCount = 1                                                  --托盘层数计数
        PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, 1) --托盘不满一层箱体的数量
        PalletNumber.ProcessNum.InitBoxCount = 0                                               --栈板料箱计数置位
        PalletNumber.PalletNum.AddBoxCount = 0
        PalletNumber.ProcessNum.RemainingAddBoxCount = 0
        if (SimulateMode == 1) or (AgingMode == 1) then
            if PalletNumber.State.Done then
                if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
                    SecondPallet.State.SReset = true
                end
                if (SimulateMode == 1) then
                    PublishClearAction(PalletNumber.Pallet)
                    PublishClearAction(PalletNumber.Pallet)
                    PublishClearAction(PalletNumber.Pallet)
                end
            end
        end

    elseif PalletNumber.Mode == WorkType.Depallet then
        if SimulateMode == 1 then
            SimulateProcess.Statistic.FirstArrived = 1
        end
        PalletNumber.ProcessNum.BoxCount = PalletNumber.ProcessNum.TotalBoxNum --托盘箱体计数
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.TotalBoxNum
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.ProcessNum.TotalBoxNum
        PalletNumber.PalletNum.LayerCount = PalletNumber.Layer
        PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.Layer) --托盘不满一层箱体的数量                                  --托盘不满一层箱体的数量
        PalletNumber.ProcessNum.InitBoxCount = PalletNumber.ProcessNum.TotalBoxNum
        local CIndex = 0
        local CNum = 0
        CIndex, CNum = GetBoxCnt(PalletName, PalletNumber.Pallet)

        PalletNumber.PalletNum.AddBoxCount = CNum - CIndex
        PalletNumber.ProcessNum.RemainingAddBoxCount = PalletNumber.PalletNum.AddBoxCount
        if SimulateMode == 1 then
            if PalletNumber.State.Done then
                if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
                    SecondPallet.State.SReset = true
                end
                PublishFillAction(PalletNumber.Pallet)
                PublishFillAction(PalletNumber.Pallet)
                PublishFillAction(PalletNumber.Pallet)
            end
        end
    else
        LogError("Pallet Mode: %s", PalletNumber.Mode)
        Alarm("Pallet Mode is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
-- 更新码垛参数
-- update palletizing parameters
local function InitData(PalletNumber)
    if (PalletNumber.State.Replace == true) and (PalletNumber.State.Init == false) then
        if SimulateMode == 1 then
            if SimulateProcess.MqttConnected ~= 1 then
                SimulateProcess.Id = GenerateRandomId(6)
                local create = mqttFunc.MQTTCreate(ConnectId, "127.0.0.1", 1883, 600)
                local connect = mqttFunc.MQTTConnect(ConnectId)
                mqttFunc.MQTTPublish(ConnectId, 'process', SimulateProcess.Id, 0, false)
                SimulateProcess.MqttConnected = 1
            end
        end
        ReadPalletNum(PalletNumber)          --读取栈板上已有料箱层数、剩余料箱数；DI21项目会跳过历史隔板数量为0的误报警。
        SyncPartitionRemainBySensor(PalletNumber, true) --全局共用函数：隔板数量由DI21初始化覆盖，并写入寄存器/控制器全局变量。
        ReadProductionData() -- 读取产能数据
        -- read production data

        local BoxNum = 0
        local LayerBoxNum = 0
        local FinishBoxNum = 0
        PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(PalletName, PalletNumber.Pallet)
        LogInfo("%s pallet working data: TotalBoxNum: %s",
            (PalletNumber.Pallet == Left) and "Left" or "Right", PalletNumber.ProcessNum.TotalBoxNum)
        if (PalletNumber.Mode == WorkType.Pallet) then
            for i = 1, PalletNumber.PalletNum.LayerCount do
                LayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, i)
                FinishBoxNum = FinishBoxNum + LayerBoxNum
            end

            PalletNumber.ProcessNum.BoxCount = FinishBoxNum - PalletNumber.PalletNum.RemainBoxNum
            if FinishBoxNum < PalletNumber.PalletNum.RemainBoxNum then
                PalletNumber.ProcessNum.BoxCount = FinishBoxNum
            end
            BoxNum = PalletNumber.ProcessNum.TotalBoxNum
            PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount + 1
        else
            for i = 2, PalletNumber.PalletNum.LayerCount do
                LayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, i - 1)
                FinishBoxNum = FinishBoxNum + LayerBoxNum
            end

            BoxNum = 0
            PalletNumber.ProcessNum.BoxCount = FinishBoxNum + PalletNumber.PalletNum.RemainBoxNum
            PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount
        end
        LogInfo("%s pallet working data: BoxCount: %s",
            (PalletNumber.Pallet == Left) and "Left" or "Right", PalletNumber.ProcessNum.BoxCount)
        PalletNumber.ProcessNum.InitBoxCount = PalletNumber.ProcessNum.BoxCount

        if (PalletNumber.Partition.Enable == true)
            and (PalletNumber.ProcessNum.BoxCount == BoxNum)
            and (PalletNumber.Partition.Place == 0)
            and ((PalletNumber.Mode == WorkType.Pallet and PalletNumber.Partition.Layer[PalletNumber.Layer + 1] == 1)
                or (PalletNumber.Mode == WorkType.Depallet and PalletNumber.Partition.Layer[1] == 1)) then
            PalletNumber.Partition.Last = true
        end

        if (PalletNumber.ProcessNum.BoxCount == BoxNum) and (PalletNumber.Partition.Last == false) then
            PalletNumber.State.Done = true
            PalletNumber.StateValue.Status = StateType.Stop --栈板已满/已空
            if (StateMachine == FSMType.SLR and PalletBeInPlaceOKButton == false) or (StateMachine == FSMType.DLR) then
                InitPallet(PalletNumber)
            end
        else
            PalletNumber.State.Done = false
            PalletNumber.StateValue.Status = StateType.Idle -- 空闲中
            -- idle
        end
        CommitPalletStatus(PalletNumber)
        CommitPalletNum(PalletNumber) --上传已有料箱层数、剩余料箱数
        PalletNumber.ProcessNum.RemainingAddBoxCount = PalletNumber.PalletNum.AddBoxCount
        Capacity.Num.Box = Capacity.Num.ReBox
        Capacity.Num.Pallet = Capacity.Num.RePallet
        CommitCapacityPallet()
        CommitCapacityBox()
        if (StateMachine == FSMType.SL or PalletNumber.Pallet == Right) then
            SetVal("PalletPowerDown", 0)
        end
        PalletNumber.State.Init = true
        LogInfo("%s work data initialization completed!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    end
end
---------------------------------------------------------------
--周期性循环检查
local function CycleCheckPallet(PalletNumber)
    if (PalletNumber.State.Replace == true) then           --当前栈板状况
        if (PalletNumber.State.Done == false) then
            PalletNumber.State.StateReady = true
            if (PalletNumber.Pallet == Pallet) then
                PalletNumber.StateValue.Status = StateType.Run -- 码垛/拆垛中
                -- palletizing/depalletizing in progress
                TriLightStatus(PalletNumber, Light.Green.Blink)
            end
        else
            if PalletNumber.Pallet == Left then
                Capacity.Num.ReBox = Capacity.Num.ReBox + FirstPallet.ProcessNum.PalletBoxCount
                FirstPallet.ProcessNum.PalletBoxCount = 0
            else
                Capacity.Num.ReBox = Capacity.Num.ReBox + SecondPallet.ProcessNum.PalletBoxCount
                SecondPallet.ProcessNum.PalletBoxCount = 0
            end
            if (StateMachine == FSMType.SL or StateMachine == FSMType.SR) then
                LogInfo("Work is completed!")
            else
                if (PalletBeInPlaceOKButton == true) then
                    if (PalletNumber.StateValue.Status ~= StateType.Stop and PalletNumber.State.SReset == false) then
                        Pallet = Idle
                    end
                else
                    if (StateMachine == FSMType.SLR) then
                        if PalletNumber.Pallet == Left then
                            Pallet = Right
                        else
                            Pallet = Left
                        end
                    end
                end
                if (FirstPallet.State.Done == true and SecondPallet.State.Done == true) then
                    LogInfo("Work is completed!")
                end
            end
            if (PalletNumber.State.FReset == false) then
                PalletNumber.StateValue.Status = StateType.Stop --栈板已满/已空
                local WorkState = (PalletNumber.Pallet == Left and "LWorkState" or "RWorkState")
                SetVal(WorkState, PalletNumber.StateValue.Status)
            end
            TriLightStatus(PalletNumber, Light.Yellow.Blink)
            if (BuzzerFunction == true) then
                DO(BuzzerIO, ON) --开启蜂鸣器
            end
        end
    else
        PalletNumber.State.StateReady = false
    end
end

----------------------------------------------------------------
--检测栈板更换
local function CheckPallet(PalletNumber)
    if (PalletNumber.State.Done == true) and (PalletNumber.State.Replace == false) then
        PalletNumber.State.FReset = true --第一次判断栈板是否移开
        PalletNumber.State.InPlaceOK = false
        TriLightStatus(PalletNumber, Light.Yellow.On)
    end
    if (PalletNumber.State.FReset == true)
        and ((DI(PalletNumber.InPlaceA) == ON) and (DI(PalletNumber.InPlaceB) == ON)) then
        PalletNumber.State.SReset = true --第二次判断栈板是否到位
        TriLightStatus(PalletNumber, Light.Init)
        if BuzzerFunction == true then
            DO(BuzzerIO, OFF) --关闭蜂鸣器
        end
    end
    --更换栈板，初始化工作参数
    if (PalletNumber.State.SReset == true) then
        PalletNumber.Layer = GetLayerCnt(PalletName, PalletNumber.Pallet)
        Capacity.Num.Pallet = Capacity.Num.RePallet + 1
        Capacity.Num.RePallet = Capacity.Num.Pallet
        if (PalletNumber.Partition.Enable == true) then
            if (PalletNumber.Pallet == Left) then
                SetVal("PalletPartPlaceA", 0)
            else
                SetVal("PalletPartPlaceB", 0)
            end
        end
        CommitCapacityPallet()
        InitWorkingData(PalletNumber)
        -- 新托盘/ACK复位后，先按隔板传感器刷新隔板数量，再上传数量。
        SyncPartitionRemainBySensor(PalletNumber, true)
        PalletNumber.State.Done = false

        CommitPalletNum(PalletNumber)     --上传已有料箱层数、剩余料箱数
        PalletNumber.State.FReset = false --第一次判断栈板是否移开，复位标志位
        PalletNumber.State.SReset = false --第二次判断栈板是否到位，复位标志位

        if (StateMachine == FSMType.SLR and PalletBeInPlaceOKButton == false) then
            if (PalletNumber.Pallet == Left) and (SecondPallet.State.FReset == true) then
                Pallet = Left
            end
            if (PalletNumber.Pallet == Right) and (FirstPallet.State.FReset == true) then
                Pallet = Right
            end
        end
        LogInfo("%s pallet replacement completed!", (PalletNumber.Pallet == Left and "Left" or "Right"))
    end
end

----------------------------------------------------------------
-- 报警检测
-- alarm check
local function ChildProcessAction(PalletNumber)
    if (PalletNumber.State.Done == true) then
        return
    end
    if (PalletBeInPlaceOKButton == true and PalletNumber.State.InPlaceOK == false) then
        return
    end
    if (PalletNumber.State.LosePallet == false) and (PalletNumber.State.Replace == false) then
        RePalletSTime = os.time()
        PalletNumber.State.LosePallet = true
        LogWarn("%s pallet detected as lost!", (PalletNumber.Pallet == Left) and "Left" or "Right")
        TriLightStatus(PalletNumber, Light.Yellow.On)
    end
    if (PalletNumber.State.LosePallet == true) then
        if (PalletNumber.State.Replace == false) then
            RePalletETime = os.time()
        else
            PalletNumber.State.LosePallet = false
        end
    end

    if (math.floor(RePalletETime - RePalletSTime) > Time.Pallet.Shield) then --更换新栈板过程中屏蔽栈板丢失20s
        if (PalletNumber.State.Done == false) then
            TriLightStatus(PalletNumber, Light.Red.On)
            Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
        end
    end
    DropDete(PalletNumber, DropType.Norm)
end
----------------------------------------------------------------
--检测工作状态更新
local function PalletStateCheck(PalletNumber)
    if (((DI(PalletNumber.InPlaceA) == ON) and (DI(PalletNumber.InPlaceB) == ON)) == false) then
        PalletNumber.StateValue.Status = StateType.LosePallet -- 未检测到栈板
        -- pallet not detected
        LogWarn("%s pallet not found!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    else
        if (PalletNumber.StateValue.Enable ~= 1) then
            PalletNumber.StateValue.Status = StateType.DisPallet --检测到栈板但未上使能
        else
            if ((PalletNumber.StateValue.Status ~= StateType.Run) and (PalletNumber.StateValue.Status ~= StateType.Stop)) then
                PalletNumber.StateValue.Status = StateType.Idle -- 空闲中
                -- idle
                if (PalletNumber.State.InPlaceOK == true) then
                    TriLightStatus(PalletNumber, Light.Green.Blink)
                    TriLightStatus(PalletNumber, Light.Yellow.Blink)
                else
                    TriLightStatus(PalletNumber, Light.Green.On)
                end
            end
            if ((StateMachine == FSMType.DLR) and (PalletNumber.StateValue.Status == StateType.Run)) then
                TriLightStatus(PalletNumber, Light.Green.On)
            end
        end
    end
    CommitPalletStatus(PalletNumber)                          --上传栈板状态
end
---------------------------------------------------------------
--执行状态检查
local function ExecuteDeteData(PalletNumber)
    Wait(Time.Thread.s2)
    if (PalletNumber.State.Init == true) then
        -- 隔板DI21不做周期同步；只在启动/ACK和真正执行隔板动作前检查，避免普通箱子循环拖慢状态线程。
        -- DI21 is not synchronized periodically; it is checked at startup/ACK and before partition motion to avoid slowing the state thread during normal box cycles.
        CycleCheckPallet(PalletNumber)
        PalletStateCheck(PalletNumber)
        CheckPallet(PalletNumber)
        ChildProcessAction(PalletNumber)
    end
end
---------------------------------------------------------------
--获取工作状态
local function DeteDataFSM()
    local SwitchFSM =
    {
        [FSMType.IDLE] = function()
            LogWarn("DeteData FSM is IDLE!")
        end,
        [FSMType.SL] = function()
            while true do
                InitData(FirstPallet)
                ExecuteDeteData(FirstPallet)
            end
        end,
        [FSMType.SR] = function()
            while true do
                InitData(SecondPallet)
                ExecuteDeteData(SecondPallet)
            end
        end,
        [FSMType.DP] = function()
            while true do
                InitData(FirstPallet)
                InitData(SecondPallet)
                ExecuteDeteData(FirstPallet)
                ExecuteDeteData(SecondPallet)
            end
        end
    }

    local CFSM = StateMachine
    if (StateMachine == FSMType.SLR) or (StateMachine == FSMType.DLR) then
        CFSM = FSMType.DP
    end
    local switch_mode = SwitchFSM[CFSM]
    if switch_mode then
        switch_mode()
    else
        Alarm("DeteDataFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
---------------------------------------------------------------
while true do
    Wait(Time.Thread.s2)
    if Communication.Controller.Modbus.LinkState == true then
        DeteDataFSM()
    end
end
