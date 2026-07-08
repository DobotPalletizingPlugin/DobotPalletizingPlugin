---------------------------------------------------------------
-- 产能与周期状态更新文件
-- production and periodic state update file
-- 本文件负责累计运行时间、写入产能寄存器、周期性维护通信心跳。
---------------------------------------------------------------
-- 产能统计文件双语注释说明
-- 本文件只负责运行时间、产能统计和周期性状态维护，不直接控制机器人运动。
-- 产能时间会写入寄存器和控制器全局变量，用于HMI显示和断电恢复。
-- Production/statistics file bilingual comment guide
-- This file only handles runtime accumulation, production statistics, and periodic state maintenance. It does not directly command robot motion.
-- Production time is written to registers and controller global variables for HMI display and power-loss recovery.
---------------------------------------------------------------
-- 它不直接控制机器人运动，只为界面和统计提供实时数据。
---------------------------------------------------------------
-- 局部变量
-- local variables
local STime = 0
local TotalTime = 0 -- 产能数据：时间
-- production data: time
local TotalTimeStart = 0
---------------------------------------------------------------
--读取历史产能时间。
-- 断电恢复时从寄存器或控制器全局变量读取累计运行时间，避免重新上电后产能统计清零。	
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
--把累计秒数转换成小时、分钟、秒三段数据。
local function CalProductionTime(CData)
    Time.Num.Hour = math.floor(CData / 3600)
    Time.Num.Minute = math.floor((CData % 3600) / 60)
    Time.Num.Second = math.floor((CData % 3600) % 60)
end
---------------------------------------------------------------
--把当前产能时间写回寄存器和控制器全局变量，供界面显示和断电恢复使用。
local function CommitProductionTime()
    WriteRobotModbus(Time.Num.Hour, Time.RegisterID.Hour)
    WriteRobotModbus(Time.Num.Minute, Time.RegisterID.Minute)
    WriteRobotModbus(Time.Num.Second, Time.RegisterID.Second)
    SetVal("PalletTime", Time.Num)
end
---------------------------------------------------------------
--周期更新时间。
-- 每个工作循环都会调用，用于累计运行时间；启用LINAK升降柱时，也在这里补充心跳维护。
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
        TotalTime = TotalTime + math.ceil(TTime * 0.001) -- 单位为秒
        -- unit: seconds
        if Communication.Lifting.TimesPerHour > Communication.Lifting.MaxtimesPerHour then
            Communication.Lifting.TimesPerHour = 0
            if (TotalTime - TotalTimeStart) < 3600 then
                TotalTimeStart = TotalTime
                Alarm("Moving Lifting Times Error!", ErrorMessage.Type.LiftingErr)
            end
        end
        CalProductionTime(TotalTime) --把累计秒数转换成小时、分钟、秒三段数据。
        CommitProductionTime()       --把当前产能时间写回寄存器和控制器全局变量，供界面显示和断电恢复使用。
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
        ReadProductionTime() --读取历史产能时间。
-- 断电恢复时从寄存器或控制器全局变量读取累计运行时间，避免重新上电后产能统计清零。
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

