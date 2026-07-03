---------------------------------------------------------------
-- 此文件仅用于产能计算及高实时性状态更新
---------------------------------------------------------------
--局部变量
local STime = 0
local TotalTime = 0 --产能数据：时间
local TotalTimeStart = 0
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
while true do
    Wait(Time.Thread.s4)
    if Communication.Controller.Modbus.LinkState == true then
        ReadProductionTime() --读取产能数据已有时间
        STime = Systime()
        while true do
            DetePalletFSM()
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
            end
        end
    end
end

