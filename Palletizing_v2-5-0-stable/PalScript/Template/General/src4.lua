---------------------------------------------------------------
-- 此文件仅用于产能计算及高实时性状态更新
---------------------------------------------------------------
--局部变量
local STime = 0
local TotalTime = 0 --产能数据：时间
local TotalTimeStart = 0
local CurrentPallet =0 --任务模式当前完成栈板数
local CurrentBox =0 --任务模式当前完成料箱数
local PrevPalletCount = 0 --上一次完成栈板数
local PrevBoxCount = 0 --上一次完成料箱数
local PrevCompleted = 0 --上一次完成数，掉电保持用
---------------------------------------------------------------
--读取产能数据已有时间	
local function ReadProductionTime()
    local RemainingHour = 0
    local RemainingMinute = 0
    local RemainingSecond = 0

    if StorageMode == 1 then
        RemainingHour = ReadRobotModbus(Time.RegisterID.Hour)
        RemainingMinute = ReadRobotModbus(Time.RegisterID.Minute)
        RemainingSecond = ReadRobotModbus(Time.RegisterID.Second)
    else
        local TimeData = GetVal("PalletTime")
        if (TimeData == nil) then
            RemainingHour = 0
            RemainingMinute = 0
            RemainingSecond = 0
        else
            RemainingHour = TimeData.Hour
            RemainingMinute = TimeData.Minute
            RemainingSecond = TimeData.Second
        end
    end
    LogInfo("Initialized capacity data: Hour: %s, Minute: %s, Second: %s",
        RemainingHour, RemainingMinute, RemainingSecond)
    TotalTime = RemainingHour * 3600 + RemainingMinute * 60 + RemainingSecond
    TotalTimeStart = TotalTime
end
---------------------------------------------------------------
--计算产能数据：时间
local function CalProductionTime(CData)
    Time.Num.Hour = math.floor(CData / 3600)
    Time.Num.Minute = math.floor((CData % 3600) / 60)
    Time.Num.Second = math.floor((CData % 3600) % 60)
end
---------------------------------------------------------------
--上传产能数据：时间
local function CommitProductionTime()
    WriteRobotModbus(Time.Num.Hour, Time.RegisterID.Hour)
    WriteRobotModbus(Time.Num.Minute, Time.RegisterID.Minute)
    WriteRobotModbus(Time.Num.Second, Time.RegisterID.Second)
    SetOutputInt(BusRegisterID.WorkingTimeHour, Time.Num.Hour)
    SetOutputInt(BusRegisterID.WorkingTimeMinute, Time.Num.Minute)
    SetOutputInt(BusRegisterID.WorkingTimeSecond, Time.Num.Second)
    SetVal("PalletTime", Time.Num)
end
---------------------------------------------------------------
--更新时间
local function UpdateTime()
    if (PalletLiftingFunction == true) and (Communication.Lifting.Mode == LiftingType.LINAK) then
        Wait(200)
        LINAKHeartBeat()
        Wait(200)
        LINAKHeartBeat()
        Wait(200)
        LINAKHeartBeat()
    end
    if ((FirstPallet.StateValue.Status == StateType.Run) and (FirstPallet.State.Replace == true))
        or ((SecondPallet.StateValue.Status == StateType.Run) and (SecondPallet.State.Replace == true)) then
        local TTime = Systime() - STime
        Wait(1000 - TTime % 1000)
        STime = Systime()
        TotalTime = TotalTime + math.ceil(TTime * 0.001) --单位s
        if Communication.Lifting.TimesPerHour > Communication.Lifting.MaxtimesPerHour then
            Communication.Lifting.TimesPerHour = 0
            if (TotalTime - TotalTimeStart) < 3600 then
                TotalTimeStart = TotalTime
                Alarm("Moving Lifting Times Error!", ErrorMessage.Type.LiftingErr)
            end
        end
        CalProductionTime(TotalTime) --计算产能数据：时间
        CommitProductionTime()       --上传产能数据：时间
    end
end
---------------------------------------------------------------
--获取栈板状态
local function DetePalletFSM()
    local SwitchFSM =
    {
        [FSMType.IDLE] = function()
            LogWarn("DetePallet FSM is IDLE!")
        end,
        [FSMType.SL] = function()
            GetPalletStatus(FirstPallet)
        end,
        [FSMType.SR] = function()
            GetPalletStatus(SecondPallet)
        end,
        [FSMType.DP] = function()
            GetPalletStatus(FirstPallet)
            GetPalletStatus(SecondPallet)
        end
    }

    local CFSM = StateMachine
    if (StateMachine == FSMType.SLR) or (StateMachine == FSMType.DLR) then
        CFSM = FSMType.DP
    end
    local switch_conveyor = SwitchFSM[CFSM]
    if switch_conveyor then
        switch_conveyor()
        GetSafeModuleStatus()
    else
        Alarm("DetePalletFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
---------------------------------------------------------------
-- 软停止单次检查
local function SoftStopSignalCheck()
    --来源：寄存器信号
    if (ReadRobotModbus(SoftStopRegisterID) == 1) then
        LogInfo("Received SoftStop signal from Register!")
        SoftStopSignal = true
        WriteRobotModbus(0, SoftStopRegisterID)    -- 清零寄存器，防止重复触发
    end
    --来源：IO信号
    if ((SoftStopFromIOCfg.Enable and DI(SoftStopFromIOCfg.Port.A) == ON)) then
        LogInfo("Received SoftStop signal from IO!")
        SoftStopSignal = true
        SetVal("SoftStopState", true)  --软停止状态，供上位机状态显示使用：值为true表示软停止触发，值为false表示软停止动作结束
    end
    --有信号标志且不带箱子
    if (SoftStopSignal == true) and (CarryBoxFlag == false) then
        SoftStopRequested = true                   --发起软停止请求
    end
    Wait(20) 
end
---------------------------------------------------------------
---------------------------------------------------------------
--任务设置模式
local function SetTargetInit()
    --初始化当前栈板数量和料箱数量
    if StorageMode == 1 then
        CurrentPallet = ReadRobotModbus(Capacity.RegisterID.Pallet)
        CurrentBox = ReadRobotModbus(Capacity.RegisterID.Box)
    else
        local TData = GetVal("PalletCapacity")
        if (TData == nil) then
            CurrentPallet = 0
            CurrentBox = 0
        else
            CurrentPallet = TData.Pallet
            CurrentBox = TData.Box
        end
    end
    Capacity.Num.Box = CurrentBox
    Capacity.Num.Pallet = CurrentPallet
    --判断设置的是栈板任务模式，还是料箱任务模式
    if Capacity.TaskMode.Mode == "Pallet" then
        PrevCompleted =GetVal("PrevPalletCompleted")--读取掉电保存
        if PrevCompleted==nil then
            PrevCompleted = 0
        end
        LogInfo("Set %s TaskMode, Target is: %s", Capacity.TaskMode.Mode, Capacity.TaskMode.TargetPallet)
    end
    if Capacity.TaskMode.Mode == "Box"  then
        PrevCompleted =GetVal("PrevBoxCompleted")--读取掉电保存
        if PrevCompleted==nil then
            PrevCompleted = 0
        end
        LogInfo("Set %s TaskMode, Target is: %s", Capacity.TaskMode.Mode, Capacity.TaskMode.TargetBox)
    end
end

local function TargetReached()
     --判断是否达到任务模式的目标
    if (Capacity.TaskMode.Mode == "Pallet") and (Capacity.TaskMode.TargetPallet > 0) then
        
        --当前栈板数-初始栈板数>=目标数 则完成任务
        if  (Capacity.Num.Pallet-CurrentPallet+PrevCompleted >= Capacity.TaskMode.TargetPallet) then
            SetVal("PrevPalletCompleted", 0)
            WriteRobotModbus(1, Capacity.RegisterID.TaskDone)
            Capacity.TaskDone = 1
        else
            SetVal("PrevPalletCompleted", Capacity.Num.Pallet-CurrentPallet+PrevCompleted)
        end
    elseif (Capacity.TaskMode.Mode == "Box") and (Capacity.TaskMode.TargetBox > 0) then
        --当前料箱数-初始料箱数>=目标数 则完成任务
         
        if ((Capacity.Num.Box-CurrentBox+PrevCompleted) >= Capacity.TaskMode.TargetBox) then
            SetVal("PrevBoxCompleted", 0)
            WriteRobotModbus(1, Capacity.RegisterID.TaskDone)
            Capacity.TaskDone = 1
        else
            SetVal("PrevBoxCompleted", Capacity.Num.Box-CurrentBox+PrevCompleted)
        end
    end
end

local function TaskMode()
    TargetReached()
    WriteRobotModbus(Capacity.TaskDone, Capacity.RegisterID.TaskDone)
    if Capacity.TaskMode.Mode=="Pallet" then
        local Completed = Capacity.Num.Pallet - CurrentPallet+PrevCompleted
        WriteRobotModbus(Completed, Capacity.RegisterID.TaskCurrentPallet)
        if Completed ~= PrevPalletCount then
            LogInfo("Pallet TaskMode, Target Pallet Count is: %s,Completed Pallet Count is: %s", Capacity.TaskMode.TargetPallet, Completed)
            PrevPalletCount = Completed
        end
    elseif Capacity.TaskMode.Mode=="Box" then
        local Completed = Capacity.Num.Box - CurrentBox+PrevCompleted
        WriteRobotModbus(Completed, Capacity.RegisterID.TaskCurrentBox)
        if Completed ~= PrevBoxCount then
            LogInfo("Box TaskMode, Target Box Count is: %s,Completed Box Count is: %s", Capacity.TaskMode.TargetBox, Completed)
            PrevBoxCount = Completed
        end
    end
end
-------------------------------------------------------------------------------
while true do
    Wait(Time.Thread.s4)
    if Communication.Controller.Modbus.LinkState == true then
        ReadProductionTime() --读取产能数据已有时间
        STime = Systime()
        SetTargetInit() --初始化任务模式
        while true do
            DetePalletFSM()
            SoftStopSignalCheck()   -- 软停止检查
            if SimulateMode == 1 then
                if ((StateMachine == FSMType.SL and FirstPallet.Mode == 1) or
                    (StateMachine == FSMType.SR and SecondPallet.Mode == 1) or
                    ((StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) and FirstPallet.Mode == 1)) and
                    SimulateProcess.Statistic.FirstArrived == 1 then
                    UpdateTime()
                else
                    UpdateTime()
                end
            else
                UpdateTime()
                TaskMode() --任务模式
            end
            Wait(Time.Thread.s4)
        end
    end
end

