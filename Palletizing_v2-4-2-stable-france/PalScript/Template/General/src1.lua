--------------------------------------------------------------
--此文件仅用于定义信号更新
----------------------------------------------------------------
--局部变量
local ExecuteIndex = 1      --切换工作栈板标志位
local CurrentPallet = 0     --当前工作栈板标志位
local RestrictMove = false  --限制运动信号标志位
local StackingDirection = 0 --进入高度差限制功能的码垛方向，0：进行右侧码垛，1：进行左侧码垛
---------------------------------------------------------------
----------------------------------------------------------------
--获取信号
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

    local DelayTime = 3000
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
        if (MotionDone == true) then
            GetDeteMode(PalletNumber, State)
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
