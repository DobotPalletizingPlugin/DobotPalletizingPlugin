--------------------------------------------------------------
-- 信号更新文件
-- signal update file
-- 本文件负责读取传感器、更新取料许可、控制输送线和处理安全限制信号。
---------------------------------------------------------------
-- 信号更新文件双语注释说明
-- 本文件负责把外部传感器、输送线状态和栈板状态转换成机器人是否可以执行下一次取放动作。
-- BIB逻辑中，B1/B2表示机器人取料位需要两个实体箱稳定到位；B3用于检测上游额外来箱，防止继续挤压。
-- SignalReady为true时，src0运动线程才会取出CPoint并执行一次机器人动作。
-- Signal update file bilingual comment guide
-- This file converts external sensors, conveyor states, and pallet states into robot pick/place authorization.
-- In the BIB logic, B1/B2 mean that two physical boxes must be stable at the robot pick area; B3 detects an extra upstream box to prevent pushing/collision.
-- When SignalReady becomes true, the motion thread in src0 can take the next CPoint and execute one robot cycle.
---------------------------------------------------------------
-- 对BIB项目，B1+B2代表一个逻辑箱到位，B3用于防止上游继续挤压。
----------------------------------------------------------------
-- 局部变量
-- local variables
local ExecuteIndex = 1      --切换工作栈板标志位
local CurrentPallet = 0     --当前工作栈板标志位
local RestrictMove = false  --限制运动信号标志位
local StackingDirection = 0 --进入高度差限制功能的码垛方向，0：进行右侧码垛，1：进行左侧码垛
local BIBStableStartTime = {} --BIB双箱到位稳定计时起点；按栈板侧保存，避免阻塞等待影响B3刷新
-- BIB stable start timestamp per pallet side; avoids blocking waits so B3 can keep refreshing.
---------------------------------------------------------------
----------------------------------------------------------------
-- 获取普通取料信号。
-- read normal pick authorization signal
-- 当当前栈板未完成且托盘已经放好时，允许该侧进入一次取放循环。
-- 双输送模式下会把Pallet切换到当前有信号的一侧。
local function GetSignal(PalletNumber)
    if (PalletNumber.State.Done == false) and (PalletNumber.State.Replace == true) then
        if StateMachine == FSMType.DLR then
            Pallet = PalletNumber.Pallet
        end
        MotionDone = false
        SignalReady = true
        LogDebug("Signal acquired for pallet %d", PalletNumber.Pallet)
    end
end

----------------------------------------------------------------
--BIB项目输送线控制使能判断
--只在指定配方启用，避免其它项目误用BIB的双箱到位逻辑。
local function IsBIBConveyorEnabled()
    if (BIBConveyorCfg == nil) then
        return false
    end

    if (BIBConveyorCfg.Enable ~= true) then
        return false
    end

    if (PalletName == "BIB_2x10L")
        or (PalletName == "BIB_6x3L")
        or (PalletName == "BIB_2X5L") then
        return true
    end

    return false
end

----------------------------------------------------------------
--BIB项目输送线控制
--两个实体纸箱在本项目中作为一个逻辑箱：B1和B2稳定后才授权机器人取一次。
local function HandleBIBConveyorControl(PalletNumber, State, AllowPickSignal)
    if (IsBIBConveyorEnabled() ~= true) then
        return false
    end

    --只在码垛模式启用输送线控制；拆垛或其它模式继续走原插件逻辑
    if (PalletNumber.Mode ~= WorkType.Pallet) then
        return false
    end

    if (BIBConveyorCfg.Sensor == nil) or (BIBConveyorCfg.Motor == nil) then
        LogWarn("BIB conveyor configuration is incomplete!")
        return false
    end

    local B1Port = BIBConveyorCfg.Sensor.B1
    local B2Port = BIBConveyorCfg.Sensor.B2
    local B3Port = BIBConveyorCfg.Sensor.B3
    local M1Port = BIBConveyorCfg.Motor.M1
    local M2Port = BIBConveyorCfg.Motor.M2

    if (B1Port == nil) or (B2Port == nil) or (B3Port == nil)
        or (M1Port == nil) or (M2Port == nil) then
        LogWarn("BIB conveyor DI/DO port is not configured!")
        return false
    end

    local DelayTime = BIBConveyorCfg.DelayTime or 1000
    local NowTime = Systime()
    local TimerKey = PalletNumber.Pallet or 0
    local B1 = CheckDIRes(B1Port.Mode, B1Port.A)
    local B2 = CheckDIRes(B2Port.Mode, B2Port.A)
    local B3 = CheckDIRes(B3Port.Mode, B3Port.A)

    --M1必须持续刷新：B1+B2取料位已满且B3检测到第三个纸箱时，立刻停止上游，避免挤压。
    --M1 must be refreshed continuously: when B1+B2 are full and B3 detects a third carton, stop upstream immediately.
    if (B1 == ON) and (B2 == ON) and (B3 == ON) then
        IORes(M1Port.Mode, M1Port.A, OFF)
    else
        IORes(M1Port.Mode, M1Port.A, ON)
    end

    --M2电机控制和机器人取料授权分离：电机持续刷新；只有AllowPickSignal=true时才发SignalReady。
    --Separate motor control from robot authorization: motor refresh always runs; SignalReady is issued only when allowed.
    if (B1 == State) and (B2 == State) then
        if BIBStableStartTime[TimerKey] == nil then
            BIBStableStartTime[TimerKey] = NowTime
        end

        if (NowTime - BIBStableStartTime[TimerKey]) >= DelayTime then
            --稳定时间到达后重新读一次传感器，避免瞬时信号误判。
            --Re-read sensors after stable delay to avoid transient-signal authorization.
            B1 = CheckDIRes(B1Port.Mode, B1Port.A)
            B2 = CheckDIRes(B2Port.Mode, B2Port.A)
            B3 = CheckDIRes(B3Port.Mode, B3Port.A)

            if (B1 == ON) and (B2 == ON) and (B3 == ON) then
                IORes(M1Port.Mode, M1Port.A, OFF)
            else
                IORes(M1Port.Mode, M1Port.A, ON)
            end

            if (B1 == State) and (B2 == State) then
                IORes(M2Port.Mode, M2Port.A, OFF)
                if AllowPickSignal == true then
                    GetSignal(PalletNumber)
                end
            else
                BIBStableStartTime[TimerKey] = nil
                IORes(M2Port.Mode, M2Port.A, ON)
            end
        else
            IORes(M2Port.Mode, M2Port.A, ON)
        end
    else
        BIBStableStartTime[TimerKey] = nil
        IORes(M2Port.Mode, M2Port.A, ON)
    end

    return true
end

----------------------------------------------------------------
--获取检测模式
local function GetDeteMode(PalletNumber, State)
    local Num = 0
    local Sucker = 0
    local OffSet = {}
    if PalletNumber.MultSensorFunction ~= 0 or SimulateMode == 1 then
        Num = PalletNumber.PalletNum.NextBoxCount
        if Num == 0 then
            Num = 1
        elseif Num > PalletNumber.ProcessNum.TotalBoxNum then
            Num = PalletNumber.ProcessNum.TotalBoxNum
        end
        OffSet, Sucker = GetBoxProPerty(PalletName, PalletNumber.Pallet, Num)
    end

    if SimulateMode == 1 then
        local Conveyor
        
        if WorkingMode == 2 then
            if PalletNumber == FirstPallet then
                Conveyor = SimulateProcess.Conveyor
            else
                Conveyor = SimulateProcess.Conveyor1
            end
        else
            if PalletNumber == FirstPallet and Pallet ~= Left then
                return
            end

            if PalletNumber == SecondPallet and Pallet ~= Right then
                return
            end
            Conveyor = SimulateProcess.Conveyor
        end

        SimulateProcess.PresentConveyor = Conveyor

        if PalletNumber.Mode == 1 then
            if Sucker == 0 then -- 单个箱子
                if Conveyor.BoxArrived[1] and Conveyor.BoxArrived[1].State == 0 then
                    GetSignal(PalletNumber)
                    if SimulateProcess.Statistic.FirstArrived == 0 then
                        SimulateProcess.Statistic.FirstArrived = 1
                    end
                    LogInfo("SimulateProcess.FirstBoxArrived!")
                end
            else -- 多个箱子
                local BoxCnt
                if Sucker == -1 then
                    BoxCnt = PalletSuckerFunction
                else
                    BoxCnt = math.ceil(Sucker * 0.5)
                end

                local AllArrived = true
                for i = 1, BoxCnt do
                    if Conveyor.BoxArrived[i] == nil or Conveyor.BoxArrived[i].State ~= 0 then
                        AllArrived = false
                        break
                    end
                end

                if AllArrived == true then
                    GetSignal(PalletNumber)
                    if SimulateProcess.Statistic.FirstArrived == 0 then
                        SimulateProcess.Statistic.FirstArrived = 1
                    end
                    LogInfo("SimulateProcess All Boxes Arrived!")
                end
            end
        else
            if Sucker == 0 then
                if Conveyor.BoxArrived[1] == nil then
                    GetSignal(PalletNumber)
                    LogInfo("SimulateProcess.FirstBoxLeft!")
                end
            else
                local BoxCnt
                if Sucker == -1 then
                    BoxCnt = PalletSuckerFunction
                else
                    BoxCnt = math.ceil(Sucker * 0.5)
                end

                local AllLeft = true
                for i = 1, BoxCnt do
                    if Conveyor.BoxArrived[i] ~= nil then
                        AllLeft = false
                        break
                    end
                end

                if AllLeft == true then
                    GetSignal(PalletNumber)
                    LogInfo("SimulateProcess All Boxes Left!")
                end
            end
        end
        return
    end


    local DelayTime = 500
    if Sucker == 0 then
        if (DI(PalletNumber.BoxBeInpPlaceDI1) == State) then
            Wait(DelayTime)
            if (DI(PalletNumber.BoxBeInpPlaceDI1) == State) then
                GetSignal(PalletNumber)
            end
        end
    else
        if Sucker == 1 or Sucker == 2 then
            if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                and (DI(PalletNumber.BoxBeInpPlaceDI2) == State) then
                Wait(DelayTime)
                if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                    and (DI(PalletNumber.BoxBeInpPlaceDI2) == State) then
                    GetSignal(PalletNumber)
                end
            end
            return
        end

        if Sucker == 3 or Sucker == 4 then
            if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                and (DI(PalletNumber.BoxBeInpPlaceDI2) == State)
                and ((DI(PalletNumber.BoxBeInpPlaceDI3) == State)) then
                Wait(DelayTime)
                if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                    and (DI(PalletNumber.BoxBeInpPlaceDI2) == State)
                    and ((DI(PalletNumber.BoxBeInpPlaceDI3) == State)) then
                    GetSignal(PalletNumber)
                end
            end
            return
        end

        if Sucker == 5 or Sucker == 6 or Sucker == -1 then
            if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                and (DI(PalletNumber.BoxBeInpPlaceDI2) == State)
                and (DI(PalletNumber.BoxBeInpPlaceDI3) == State)
                and (DI(PalletNumber.BoxBeInpPlaceDI4) == State) then
                Wait(DelayTime)
                if (DI(PalletNumber.BoxBeInpPlaceDI1) == State)
                    and (DI(PalletNumber.BoxBeInpPlaceDI2) == State)
                    and (DI(PalletNumber.BoxBeInpPlaceDI3) == State)
                    and (DI(PalletNumber.BoxBeInpPlaceDI4) == State) then
                    GetSignal(PalletNumber)
                end
            end
            return
        end
    end
end

----------------------------------------------------------------
--执行状态
local function ExecuteSignal(PalletNumber, State)
    while true do
        Wait(Time.Thread.s1)
        if (PalletNumber.State.Done == true) then
            break
        end

        local AllowPickSignal = (MotionDone == true)
        local BIBHandled = HandleBIBConveyorControl(PalletNumber, State, AllowPickSignal)

        if (BIBHandled ~= true) and (MotionDone == true) then
            GetDeteMode(PalletNumber, State)
            if StateMachine == FSMType.DLR then
                break
            end
        elseif (BIBHandled == true) and (AllowPickSignal == true) then
            --BIB模式下，电机刷新不退出循环；只有本轮允许取货授权时，保持原DLR单次检查行为。
            --In BIB mode, motor refresh keeps looping; only an authorization-capable cycle keeps the original DLR single-check behavior.
            if StateMachine == FSMType.DLR then
                break
            end
        end
    end
end

----------------------------------------------------------------
--获取状态
local function GetSignalFSM(PalletNumber)
    if (PalletNumber.State.Init == true) then
        if (StateMachine == FSMType.DLR)
            or (PalletNumber.Pallet == Pallet and StateMachine ~= FSMType.DLR) then
            if (PalletNumber.Mode == WorkType.Pallet) then
                ExecuteSignal(PalletNumber, ON)
            else
                ExecuteSignal(PalletNumber, OFF)
            end
        end
    end
end

---------------------------------------------------------------
--获取工作序号
function GetIndex(PalletNumber, PalletNum)
    local BoxCount = 0
    local MaxBoxCount = 0
    if PalletNum == Left then
        BoxCount = FirstPallet.PalletNum.NextBoxCount
        MaxBoxCount = FirstPallet.PalletNum.LayerBoxNum
    else
        BoxCount = SecondPallet.PalletNum.NextBoxCount
        MaxBoxCount = SecondPallet.PalletNum.LayerBoxNum
    end
    if PalletNumber.Mode == WorkType.Pallet then
        if BoxCount > MaxBoxCount then
            BoxCount = MaxBoxCount
        end
    else
        if BoxCount < 1 then
            BoxCount = 1
        end
    end

    return BoxCount
end

---------------------------------------------------------------
--获取当前位置
function GetRestrictMoveResult()
    local FNum = 1
    local SNum = 1
    local FPose = {}
    local SPose = {}
    local HeightDiff = 0

    FNum = GetIndex(FirstPallet, Left)
    SNum = GetIndex(SecondPallet, Right)
    FPose = GetBoxPos(PalletName, Left, FNum)
    SPose = GetBoxPos(PalletName, Right, SNum)
    LogDebug("FPose: %s", FPose.pose[3])
    LogDebug("SPose: %s", SPose.pose[3])

    HeightDiff = math.abs(FPose.pose[3] - SPose.pose[3])
    if HeightDiff >= Communication.Lifting.StartHeightDiff then
        if FPose.pose[3] > SPose.pose[3] then
            StackingDirection = 0
            if (FirstPallet.PalletNum.LayerCount == FirstPallet.Layer) and (FirstPallet.State.Done == false) then
                CurrentPallet = -1
            else
                CurrentPallet = 1
            end
        else
            StackingDirection = 1
            if (SecondPallet.PalletNum.LayerCount == SecondPallet.Layer) and (SecondPallet.State.Done == false) then
                CurrentPallet = 1
            else
                CurrentPallet = -1
            end
        end
        Communication.Lifting.RestrictMoveFlag = true
    elseif (HeightDiff <= Communication.Lifting.EndHeightDiff)
        or (StackingDirection == 0 and FPose.pose[3] < SPose.pose[3])
        or (StackingDirection == 1 and FPose.pose[3] > SPose.pose[3]) then
        Communication.Lifting.RestrictMoveFlag = false
    end
end

----------------------------------------------------------------
--获取复合检测模式
local function GetMulSignalFSM()
    local SwitDeteMode =
    {
        [0] = function()
            LogWarn("Conveyor stop Working!")
        end,
        [-1] = function()
            GetSignalFSM(FirstPallet)
        end,
        [1] = function()
            GetSignalFSM(SecondPallet)
        end
    }

    local switch_mode
    local SwitchIndex = 0
    if (PalletBeInPlaceOKButton == false) then
        if (FirstPallet.State.Init == false or SecondPallet.State.Init == false) then
            LogWarn("Pallet not initialized, skipping signal FSM!")
            return
        end
    else
        if (FirstPallet.State.Init == true and SecondPallet.State.Init == false) then
            SwitchIndex = -1
        elseif (FirstPallet.State.Init == false and SecondPallet.State.Init == true) then
            SwitchIndex = 1
        elseif (FirstPallet.State.Init == false and SecondPallet.State.Init == false) then
            LogWarn("Pallet not initialized, skipping signal FSM!")
            return
        end

        if SwitchIndex ~= 0 then
            switch_mode = SwitDeteMode[SwitchIndex]
            if switch_mode then
                switch_mode()
            else
                Alarm("Conveyor is wrong!", ErrorMessage.Type.RestrictErr)
            end
            if MotionDone == false then
                ExecuteIndex = SwitchIndex
            end
            return
        end
    end
    if RestrictMoveFunction == true then
        if DI(FirstPallet.RestrictMoveSignal) == OFF and DI(SecondPallet.RestrictMoveSignal) == ON then
            CurrentPallet = -1
            RestrictMove = true
            Communication.Lifting.RestrictMoveFlag = true
        elseif DI(FirstPallet.RestrictMoveSignal) == ON and DI(SecondPallet.RestrictMoveSignal) == OFF then
            CurrentPallet = 1
            RestrictMove = true
            Communication.Lifting.RestrictMoveFlag = true
        elseif DI(FirstPallet.RestrictMoveSignal) == ON and DI(SecondPallet.RestrictMoveSignal) == ON then
            CurrentPallet = 0
            RestrictMove = true
            Communication.Lifting.RestrictMoveFlag = true
        else
            if RestrictMove == true then
                RestrictMove = false
                Communication.Lifting.RestrictMoveFlag = false
            end
            GetRestrictMoveResult()
        end
    end
    for i = -1, 1, 2 do
        if Communication.Lifting.RestrictMoveFlag == true then
            SwitchIndex = CurrentPallet
        else
            SwitchIndex = i * ExecuteIndex
        end

        switch_mode = SwitDeteMode[SwitchIndex]
        if switch_mode then
            switch_mode()
        else
            Alarm("Conveyor is wrong!", ErrorMessage.Type.RestrictErr)
        end
        if MotionDone == false then
            ExecuteIndex = SwitchIndex
            break
        end
    end
end

---------------------------------------------------------------
--获取工作状态
local function SignalFSM()
    local SwitchFSM =
    {
        [FSMType.IDLE] = function()
            LogWarn("Signal FSM is IDLE!")
        end,
        [FSMType.SL] = function()
            GetSignalFSM(FirstPallet)
        end,
        [FSMType.SR] = function()
            GetSignalFSM(SecondPallet)
        end,
        [FSMType.SLR] = function()
            GetSignalFSM(FirstPallet)
            GetSignalFSM(SecondPallet)
        end,
        [FSMType.DLR] = function()
            GetMulSignalFSM()
        end
    }

    local switch_conveyor = SwitchFSM[StateMachine]
    if switch_conveyor then
        switch_conveyor()
    else
        Alarm("SignalFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end

---------------------------------------------------------------
---------------------------------------------------------------
while true do
    Wait(Time.Thread.s1)
    SignalFSM()
end
