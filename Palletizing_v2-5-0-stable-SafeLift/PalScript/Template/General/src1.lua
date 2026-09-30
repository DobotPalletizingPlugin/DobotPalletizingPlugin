--------------------------------------------------------------
--此文件仅用于定义信号更新
--------------------------------------------------------------
--局部变量
local ExecuteIndex = 1      --切换工作栈板标志位
local RestrictMove = Idle   --限制栈板工作方向标志位
local StackingDirection = 0 --进入高度差限制功能的码垛方向，0：进行右侧码垛，1：进行左侧码垛
---------------------------------------------------------------
---------------------------------------------------------------
--获取信号
local function GetSignal(PalletNumber)
    if (PalletNumber.State.Done == false) and (PalletNumber.State.Replace == true) then
        if StateMachine == FSMType.DLR then
            Pallet = PalletNumber.Pallet
            --写入当前栈板号，并自动切换信号方向（左右交替），实现双栈板轮转
            if (WorkingMode == ModeType.Exh) then
                WriteRobotModbus(Pallet, FirstPallet.RegisterID.PalletDir)
                if (WorkingSignalDir == SignalDir.Left) then
                    WorkingSignalDir = SignalDir.Right
                elseif (WorkingSignalDir == SignalDir.Right) then
                    WorkingSignalDir = SignalDir.Left
                end
            end
        end
        MotionDone = false
        SignalReady = true
        LogDebug("Signal acquired for pallet %d", PalletNumber.Pallet)
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
        if (RestrictMoveFunction == true) then
            if DI(FirstPallet.RestrictMoveSignal) == OFF and DI(SecondPallet.RestrictMoveSignal) == ON then
                RestrictMove = Right
            elseif DI(FirstPallet.RestrictMoveSignal) == ON and DI(SecondPallet.RestrictMoveSignal) == OFF then
                RestrictMove = Left
            elseif DI(FirstPallet.RestrictMoveSignal) == ON and DI(SecondPallet.RestrictMoveSignal) == ON then
                RestrictMove = Idle
            else
                if (RestrictMove ~= Idle) then
                    RestrictMove = Idle
                end
                GetRestrictMoveResult()
            end
            if (PalletNumber.Pallet == RestrictMove) then
                break
            end
        end
        if (MotionDone == true) then
            if (GetDeteMode(PalletNumber, false, State) == true) then
                GetSignal(PalletNumber)
            end
            if (StateMachine == FSMType.DLR) then
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
    if (HeightDiff >= Communication.Lifting.StartHeightDiff) then
        if (FPose.pose[3] > SPose.pose[3]) then
            StackingDirection = Left
            if (FirstPallet.PalletNum.LayerCount == FirstPallet.Layer) and (FirstPallet.State.Done == false) then
                RestrictMove = Right
            else
                RestrictMove = Left
            end
        else
            StackingDirection = Right
            if (SecondPallet.PalletNum.LayerCount == SecondPallet.Layer) and (SecondPallet.State.Done == false) then
                RestrictMove = Left
            else
                RestrictMove = Right
            end
        end
    elseif (HeightDiff <= Communication.Lifting.EndHeightDiff)
        or (StackingDirection == Left and FPose.pose[3] < SPose.pose[3])
        or (StackingDirection == Right and FPose.pose[3] > SPose.pose[3]) then
        RestrictMove = Idle
    end
end

----------------------------------------------------------------
--获取复合检测模式
local function GetMulSignalFSM()
    local SwitDeteMode =
    {
        [SignalDir.Idle] = function()
            LogWarn("Conveyor stop Working!")
        end,
        [SignalDir.Left] = function()
            GetSignalFSM(FirstPallet)
        end,
        [SignalDir.Right] = function()
            GetSignalFSM(SecondPallet)
        end
    }

    local switch_mode
    local SwitchIndex = SignalDir.Idle
    --Exh模式信号方向由WorkingSignalDir决定
    if (WorkingMode == ModeType.Exh) then
        if (FirstPallet.State.Init == false or SecondPallet.State.Init == false) then
            LogWarn("Pallet not initialized, skipping signal FSM!")
            return
        end

        switch_mode = SwitDeteMode[WorkingSignalDir]
        if switch_mode then
            switch_mode()
        else
            Alarm("Conveyor is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
    else
        if (PalletBeInPlaceOKButton == false) then
            if (FirstPallet.State.Init == false or SecondPallet.State.Init == false) then
                LogWarn("Pallet not initialized, skipping signal FSM!")
                return
            end
        else
            if (FirstPallet.State.Init == true and SecondPallet.State.Init == false) then
                SwitchIndex = SignalDir.Left
            elseif (FirstPallet.State.Init == false and SecondPallet.State.Init == true) then
                SwitchIndex = SignalDir.Right
            elseif (FirstPallet.State.Init == false and SecondPallet.State.Init == false) then
                LogWarn("Pallet not initialized, skipping signal FSM!")
                return
            end

            if SwitchIndex ~= SignalDir.Idle then
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
        for i = -1, 1, 2 do
            SwitchIndex = i * ExecuteIndex
            switch_mode = SwitDeteMode[SwitchIndex]
            if switch_mode then
                switch_mode()
            else
                Alarm("Conveyor is wrong!", ErrorMessage.Type.WorkingDataErr)
            end
            if (MotionDone == false) then
                ExecuteIndex = SwitchIndex
                break
            end
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
