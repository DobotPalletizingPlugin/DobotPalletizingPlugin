-- 子线程，随主线程一起运行的并行程序，可设置I/O、通讯、变量等，不能调用运动指令。
PreFinishFlag = 0              --已完成栈板标志位
SwitchConveyorFlag = 1         --传送带切换标志位
RePalletSTime = 0              --栈板丢失开始屏蔽时间
RePalletETime = 0              --栈板丢失结束屏蔽时间
PalletStateTimeFlag = false    --码垛次数限制标志位
CurrentPallet = 0              --当前工作栈板标志位
StackingDirection = 0          --进入高度差限制功能的码垛方向，0：进行右侧码垛，1：进行左侧码垛
RestrictMoveSignalFlag = false --限制运动信号标志位
---------------------------------------------------------------
--更新码垛参数
local function InitPalletData(PalletNumber, PalletData, NameStr)
    ReadProductionData()                                           --读取产能数据
    ReadPalletNum(PalletNumber, PalletData, NameStr) --读取栈板上已有料箱层数、剩余料箱数
    RemainingTotalBoxCount = RemainingTotalBoxCount - PalletNumber.PalletNum.AddBoxCount
    print("\rLayerCount:", PalletNumber.PalletNum.LayerCount)
	print("\rNextBoxCount:", PalletNumber.PalletNum.NextBoxCount)
    print("\rRemainBoxNum:", PalletNumber.PalletNum.RemainBoxNum)
    print("\rLayerBoxNum:", PalletNumber.PalletNum.LayerBoxNum)
    print("\rAddBoxCount:", PalletNumber.PalletNum.AddBoxCount)
    print("\rRemainingTotalPalletCount:", RemainingTotalPalletCount)
    print("\rRemainingTotalBoxCount:", RemainingTotalBoxCount)
    
    local LayerBoxNum = 0
    local FinishBoxNum = 0
    if PalletNumber.PalletMode == 1 then
        for i = 1, PalletNumber.PalletNum.LayerCount do
            LayerBoxNum = GetOddBoxCnt(NameStr, PalletData, i)
            FinishBoxNum = FinishBoxNum + LayerBoxNum
        end

        PalletNumber.ProcessNum.BoxCount = FinishBoxNum - PalletNumber.PalletNum.RemainBoxNum
        if FinishBoxNum < PalletNumber.PalletNum.RemainBoxNum then
            PalletNumber.ProcessNum.BoxCount = FinishBoxNum
        end
    else
        for i = 2, PalletNumber.PalletNum.LayerCount do
            LayerBoxNum = GetOddBoxCnt(NameStr, PalletData, i - 1)
            FinishBoxNum = FinishBoxNum + LayerBoxNum
        end

        PalletNumber.ProcessNum.BoxCount = FinishBoxNum + PalletNumber.PalletNum.RemainBoxNum
    end
    PalletNumber.ProcessNum.InitBoxCount = PalletNumber.ProcessNum.BoxCount

    PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(NameStr, PalletData)
    print("\rTotalBoxNum:", PalletNumber.ProcessNum.TotalBoxNum)
    if PalletNumber.PalletMode == 1 then
        if (PalletNumber.ProcessNum.BoxCount == PalletNumber.ProcessNum.TotalBoxNum) then
            PalletNumber.State.Full = true
            PalletNumber.State.SecondResetFlag = true
            if (FirstPallet.PalletMode == 2) and (FirstPallet.ProcessNum.BoxCount == 0) then
                FirstPallet.State.SecondResetFlag = true
            elseif (SecondPallet.PalletMode == 2) and (SecondPallet.ProcessNum.BoxCount == 0) then
                SecondPallet.State.SecondResetFlag = true
            end
            FinishFlag = true
            WorkFinishFlag = true
            PalletNumber.StateValue.Status = 3                                                     --栈板已满/已空
            WriteRobotModbus(PalletNumber.StateValue.Status, PalletNumber.RegisterID.PalletStatus) --更新码垛状态
        else
            FinishFlag = false
            FirstPallet.State.Full = false
            SecondPallet.State.Full = false
        end

        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount + 1
    else
        if (PalletNumber.ProcessNum.BoxCount == 0) then
            FinishFlag = true
            FirstPallet.State.Empty = true
            SecondPallet.State.Empty = true
            PalletNumber.StateValue.Status = 3                                                     --栈板已满/已空
            WriteRobotModbus(PalletNumber.StateValue.Status, PalletNumber.RegisterID.PalletStatus) --更新码垛状态
        else
            FinishFlag = false
            if Pallet == 0 then
                SwitchConveyorFlag = 1
            else
                SwitchConveyorFlag = -1
            end
            FirstPallet.State.Empty = false
            SecondPallet.State.Empty = false
        end

        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount
    end

    print("\rBoxCount:", PalletNumber.ProcessNum.BoxCount)

    CommitPalletNum(PalletNumber) --上传已有料箱层数、剩余料箱数
    PlaceCountPallet(PalletNumber)
    PalletNumber.ProcessNum.RemainingAddBoxCount = PalletNumber.PalletNum.AddBoxCount
    RemainingTotalBoxCount = TotalBoxCount
    ReadStatePallet(PalletNumber.StateValue, PalletNumber.RegisterID)  --读使能标志
end

-----------------------------------------------------------------
--初始化
local function Init()
    ErrorMessage.Code = 0
    CommitErrorMessage()
    FirstPallet.PalletMode = ReadRobotModbus(FirstPallet.RegisterID.PalletMode)
    SecondPallet.PalletMode = ReadRobotModbus(SecondPallet.RegisterID.PalletMode)
    SwitchConveyorFlag = ReadRobotModbus(5028)
    if SwitchConveyorFlag == 2 then
        SwitchConveyorFlag = -1
    end
    Pallet = ReadRobotModbus(5029)
    PreFinishFlag = ReadRobotModbus(5037)
    if PreFinishFlag == Pallet + 1 then
        if Pallet == 0 then
            Pallet = 1
            SwitchConveyorFlag = -1
        else
            Pallet = 0
            SwitchConveyorFlag = 1
        end
    end
    if MultPalletFunction == true then
        if FirstPallet.PalletMode == 1 then
            InitPalletData(SecondPallet, 1, PalletName)
            InitPalletData(FirstPallet, 0, PalletName)
        else
            InitPalletData(FirstPallet, 0, PalletName)
            InitPalletData(SecondPallet, 1, PalletName)
        end
    else
        if Pallet == 0 then
            InitPalletData(FirstPallet, 0, PalletName)
        elseif Pallet == 1 then
            InitPalletData(SecondPallet, 1, PalletName)
        end
    end
    if FirstPallet.PalletMode == 1 then
        local SrcPose = { pose = {} }
        local CurrentPose = { pose = {} }
        local CurrentPoint = { pose = {}, joint = {} }
        SrcPose.pose = DeepCopy(SecondPallet.TeachPoint.TeachPickPoint.pose)
        CurrentPose = GetAddUserPos(SecondPallet.Coordinate.UserNum, FirstPallet.Coordinate.UserNum, SrcPose)
        CurrentPoint.pose = DeepCopy(CurrentPose.pose)
        CurrentPoint.joint = DeepCopy(SecondPallet.TeachPoint.TeachPickPoint.joint)
        FirstPickPose = PalletGetPose(FirstPallet, CurrentPoint, 0)

        SrcPose.pose = DeepCopy(FirstPallet.TeachPoint.TeachPickPoint.pose)
        CurrentPose = GetAddUserPos(FirstPallet.Coordinate.UserNum, SecondPallet.Coordinate.UserNum, SrcPose)
        CurrentPoint.pose = DeepCopy(CurrentPose.pose)
        CurrentPoint.joint = DeepCopy(FirstPallet.TeachPoint.TeachPickPoint.joint)
        SecondPickPose = PalletGetPose(SecondPallet, CurrentPoint, 0)
    elseif FirstPallet.PalletMode == 2 then
        FirstPickPose = PalletGetPose(FirstPallet, FirstPallet.TeachPoint.TeachPickPoint, 0)
        SecondPickPose = PalletGetPose(SecondPallet, SecondPallet.TeachPoint.TeachPickPoint, 0)
    end
    PalletNumInitFlag = true
end

---------------------------------------------------------------
--周期性循环检查
local function CycleCheckPallet(PalletNumber, CurrentState)
    if (PalletNumber.State.Replace == true) then --判断当前工作状况，先判断托盘是否准备好，再判断托盘是否上使能 	
        if (PalletNumber.State.EnableResult == true) then
            GetPalletStatusResult(PalletNumber.State, PalletNumber.InPlaceA, PalletNumber.InPlaceB) --得到栈板到位状态结果
            if (CurrentState == false) and (PalletNumber.State.Replace == true) then
                PalletNumber.StateValue.Status = 2                                                  --码垛/拆垛中
                IsReady = true
                --[[if PalletStateTimeFlag == false then
                    PalletStateTimeFlag = true
                    IsReady = true
                end]]
                DO(PalletNumber.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
                DO(PalletNumber.TriLight.Green, ON)   --栈板码垛/拆垛中，绿灯常亮
                DO(PalletNumber.TriLight.Red, OFF)    --栈板报错，红灯常亮
                Wait(500)
                DO(PalletNumber.TriLight.Green, OFF)
                Wait(500)
            else
                PalletNumber.StateValue.Status = 3    --栈板已满/已空
                --PalletStateTimeFlag = false
                if (WorkingMode == 2) then
                    if Pallet == 0 then
                        RemainingTotalBoxCount = RemainingTotalBoxCount + FirstPallet.ProcessNum.PalletBoxCount
                        FirstPallet.ProcessNum.PalletBoxCount = 0
                    elseif Pallet == 1 then
                        RemainingTotalBoxCount = RemainingTotalBoxCount + SecondPallet.ProcessNum.PalletBoxCount
                        SecondPallet.ProcessNum.PalletBoxCount = 0
                    end
                else
                    RemainingTotalBoxCount = TotalBoxCount
                end

                ReadStatePallet(PalletNumber.StateValue, PalletNumber.RegisterID)
                FinishFlag = false
                if Pallet == 0 then
                    Pallet = 1
                else
                    Pallet = 0
                end
            end
        else
            ReadStatePallet(PalletNumber.StateValue, PalletNumber.RegisterID)
            IsReady = false
            --PalletStateTimeFlag = false
        end
    else
        IsReady = false
        --PalletStateTimeFlag = false
    end
end

---------------------------------------------------------------
--掉料检测功能
local function DropDetectionAction(TriLight)
    DO(TriLight.Yellow, OFF) --栈板三色灯
    DO(TriLight.Green, OFF)
    DO(TriLight.Red, ON)
    IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A, OFF) --数字输出控制吸盘关闭
    IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B, OFF) --数字输出控制吸盘关闭
    if PartitionSignalFunction == true then
        IORes(PartSignalMode, PartitionSignal, OFF)    --数字输出控制吸盘关闭
    end
    ErrorMessage.Code = 5
    Alarm("检测到箱子/隔板掉落")
end

--------------------------------------------------------------
--报警检测
local function ChildProcessAction(PalletNumber, FinishState)
    GetPalletStatusResult(PalletNumber.State, PalletNumber.InPlaceA, PalletNumber.InPlaceB) --得到栈板到位状态结果
    GetPalletEnableResult(PalletNumber.State, PalletNumber.StateValue)                      --得到栈板上使能的结果

    --报警4："检测到栈板丢失"
    if (PalletNumber.State.ReplaceNewPalletFlag == false) and
        ((DI(PalletNumber.InPlaceA) == OFF) or (DI(PalletNumber.InPlaceB) == OFF)) then
        RePalletSTime = os.time()
        PalletNumber.State.ReplaceNewPalletFlag = true
    end
    if (PalletNumber.State.ReplaceNewPalletFlag == true) then
        if ((DI(PalletNumber.InPlaceA) == OFF) or (DI(PalletNumber.InPlaceB) == OFF)) then
            RePalletETime = os.time()
        else
            PalletNumber.State.ReplaceNewPalletFlag = false
        end
    end

    if (math.floor(RePalletETime - RePalletSTime) > Time.Pallet.Shield) then --更换新栈板过程中屏蔽栈板丢失20s
        if ((PalletNumber.State.Replace == false) and (FinishState == false)) then
            print("\r报警4_StateReplace:", PalletNumber.State.Replace)
            print("\r报警4_StateFull:", FinishState)

            DO(PalletNumber.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
            DO(PalletNumber.TriLight.Green, OFF)  --栈板码垛中，绿灯常亮
            DO(PalletNumber.TriLight.Red, ON)     --栈板报错，红灯常亮

            ErrorMessage.Code = 3
            Alarm("检测到栈板丢失")
        end
    end
    --报警5："检测到箱子掉落"
    if SuckerCfg.Dete.Mode > 0 then
        if PalletSuckerFunction == 1 then
            if SuckerCfg.Dete.Mode == 1 then
                if (PalletNumber.Partition.Enable == true) and (PartitionSignalFunction == true) then
                    if (ToolDI(SuckerCfg.Dete.PE.A) == OFF) and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                        Wait(Time.DropDetection)
                        if (ToolDI(SuckerCfg.Dete.PE.A) == OFF) and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                else
                    if (ToolDI(SuckerCfg.Dete.PE.A) == OFF) and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON) then
                        Wait(Time.DropDetection)
                        if (ToolDI(SuckerCfg.Dete.PE.A) == OFF) and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                end
            elseif SuckerCfg.Dete.Mode == 2 then
                if (PalletNumber.Partition.Enable == true) and (PartitionSignalFunction == true) then
                    if (DI(SuckerCfg.Dete.Vacuum.A) == OFF) and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                        Wait(Time.DropDetection)
                        if (DI(SuckerCfg.Dete.Vacuum.A) == OFF) and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                else
                    if (DI(SuckerCfg.Dete.Vacuum.A) == OFF) and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON) then
                        Wait(Time.DropDetection)
                        if (DI(SuckerCfg.Dete.Vacuum.A) == OFF) and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                end
            end
        elseif PalletSuckerFunction == 2 then
            if SuckerCfg.Dete.Mode == 1 then
                if (PalletNumber.Partition.Enable == true) and (PartitionSignalFunction == true) then
                    if ((ToolDI(SuckerCfg.Dete.PE.A) == OFF) or (ToolDI(SuckerCfg.Dete.PE.B) == OFF))
                        and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                        Wait(Time.DropDetection)
                        if ((ToolDI(SuckerCfg.Dete.PE.A) == OFF) or (ToolDI(SuckerCfg.Dete.PE.B) == OFF))
                            and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                else
                    if ((ToolDI(SuckerCfg.Dete.PE.A) == OFF) or (ToolDI(SuckerCfg.Dete.PE.B) == OFF))
                        and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON or CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B) == ON) then
                        Wait(Time.DropDetection)
                        if ((ToolDI(SuckerCfg.Dete.PE.A) == OFF) or (ToolDI(SuckerCfg.Dete.PE.B) == OFF))
                            and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON or CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                end
            elseif SuckerCfg.Dete.Mode == 2 then
                if (PalletNumber.Partition.Enable == true) and (PartitionSignalFunction == true) then
                    if ((DI(SuckerCfg.Dete.Vacuum.A) == OFF) or (DI(SuckerCfg.Dete.Vacuum.B) == OFF))
                        and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                        Wait(Time.DropDetection)
                        if ((DI(SuckerCfg.Dete.Vacuum.A) == OFF) or (DI(SuckerCfg.Dete.Vacuum.B) == OFF))
                            and (CheckIORes(PartSignalMode, PartitionSignal) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                else
                    if ((DI(SuckerCfg.Dete.Vacuum.A) == OFF) or (DI(SuckerCfg.Dete.Vacuum.B) == OFF))
                        and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON or CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B) == ON) then
                        Wait(Time.DropDetection)
                        if ((DI(SuckerCfg.Dete.Vacuum.A) == OFF) or (DI(SuckerCfg.Dete.Vacuum.B) == OFF))
                            and (CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == ON or CheckIORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B) == ON) then
                            DropDetectionAction(PalletNumber.TriLight)
                        end
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
--工作模式切换
local function GetWorkingMode(PalletNumber, InpPlaceFlag)
    local CurrentState = false

    if PalletNumber.PalletMode == 1 then
        CurrentState = PalletNumber.State.Full
    else
        CurrentState = PalletNumber.State.Empty
    end
    local SwitchWorkingMode =
    {
        [0] = function()
            if (CurrentState == false)
                and (PalletNumber.State.EnableResult == true)
                and (PalletNumber.State.Replace == true) then
                BoxBeInpPlaceFlag = Pallet
                PalletFinishFlag = false
                PalletChosenFlag = true
            end
        end,
        [1] = function()
            if PalletNumber.PalletMode == 1 then
                if (Pallet == 0
                        and FirstPallet.State.Full == false
                        and FirstPallet.State.EnableResult == true
                        and FirstPallet.State.Replace == true)
                    or (Pallet == 1
                        and SecondPallet.State.Full == false
                        and SecondPallet.State.EnableResult == true
                        and SecondPallet.State.Replace == true) then
                    BoxBeInpPlaceFlag = InpPlaceFlag
                    PalletFinishFlag = false
                    PalletChosenFlag = true
                end
            else
                if (Pallet == 0
                        and FirstPallet.State.Empty == false
                        and FirstPallet.State.EnableResult == true
                        and FirstPallet.State.Replace == true)
                    or (Pallet == 1
                        and SecondPallet.State.Empty == false
                        and SecondPallet.State.EnableResult == true
                        and SecondPallet.State.Replace == true) then
                    BoxBeInpPlaceFlag = InpPlaceFlag
                    PalletFinishFlag = false
                    PalletChosenFlag = true
                end
            end
        end,
        [2] = function()
            if (CurrentState == false)
                and (PalletNumber.State.EnableResult == true)
                and (PalletNumber.State.Replace == true) then
                BoxBeInpPlaceFlag = InpPlaceFlag
                Pallet = InpPlaceFlag
                WriteRobotModbus(Pallet, 5029)
                SwitchConveyorFlag = -1 * SwitchConveyorFlag
                if SwitchConveyorFlag == -1 then
                    WriteRobotModbus(2, 5028)
                else
                    WriteRobotModbus(SwitchConveyorFlag, 5028)
                end
                PalletFinishFlag = false
                PalletChosenFlag = true
            end
        end
    }

    local switch_mode = SwitchWorkingMode[WorkingMode]

    if switch_mode then
        switch_mode()
    else
        print("The Switch Working Mode is error, please check it!")
        Pause()
    end
end

----------------------------------------------------------------
--获取到位信号标志位
local function GetBeInpPlaceDIFlag(PalletNumber, Sucker, InpPlaceFlag)
    local InpPlaceState
    if PalletNumber.PalletMode == 1 then
        InpPlaceState = ON
    else
        InpPlaceState = OFF
    end
    if Sucker == 0 then
        if (DI(PalletNumber.BoxBeInpPlaceDI1) == InpPlaceState) then
            GetWorkingMode(PalletNumber, InpPlaceFlag)
        end
    else
        if (DI(PalletNumber.BoxBeInpPlaceDI1) == InpPlaceState)
            and (DI(PalletNumber.BoxBeInpPlaceDI2) == InpPlaceState) then
            GetWorkingMode(PalletNumber, InpPlaceFlag)
        end
    end
end

----------------------------------------------------------------
--多传感器取料信号
local function GetSuckerFlag(PalletNumber, PalletNum)
    local OffSet = {}
    local Sucker = 0
    if PalletNumber.MultSensorFunction ~= 0 then
        if PalletNumber.PalletMode == 1 and PalletNumber.State.Full == true then
            OffSet, Sucker = GetBoxProPerty(PalletName, PalletNum, PalletNumber.ProcessNum.TotalBoxNum)
        else
            if PalletNumber.PalletNum.NextBoxCount < 1 then
                OffSet, Sucker = GetBoxProPerty(PalletName, PalletNum, 1)
            elseif PalletNumber.PalletNum.NextBoxCount > PalletNumber.ProcessNum.TotalBoxNum then
                OffSet, Sucker = GetBoxProPerty(PalletName, PalletNum, PalletNumber.ProcessNum.TotalBoxNum)
            else
                OffSet, Sucker = GetBoxProPerty(PalletName, PalletNum, PalletNumber.PalletNum.NextBoxCount)
            end
        end
    end

    return Sucker
end
---------------------------------------------------------------
--获取当前工作序号
function GetCurrentNumber(PalletNum)
    local BoxCount = 0
    local MaxBoxCount = 0
    if PalletNum == 0 then
        BoxCount = FirstPallet.PalletNum.NextBoxCount
        MaxBoxCount = FirstPallet.PalletNum.LayerBoxNum
    else
        BoxCount = SecondPallet.PalletNum.NextBoxCount
        MaxBoxCount = SecondPallet.PalletNum.LayerBoxNum
    end
    if PalletMode == 1 then
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
    local FirstPalletNumber = 1
    local SecondPalletNumber = 1
    local FirstPalletPose = {}
    local SecondPalletPose = {}
    local HeightDiff = 0

    FirstPalletNumber = GetCurrentNumber(0)
    SecondPalletNumber = GetCurrentNumber(1)
    FirstPalletPose = GetBoxPos(PalletName, 0, FirstPalletNumber)
    SecondPalletPose = GetBoxPos(PalletName, 1, SecondPalletNumber)
    print("FirstPalletPose ", FirstPalletPose)
    print("SecondPalletPose ", SecondPalletPose)

    HeightDiff = math.abs(FirstPalletPose.pose[3] - SecondPalletPose.pose[3])
    if HeightDiff >= Communication.Lifting.StartHeightDiff then
        if FirstPalletPose.pose[3] > SecondPalletPose.pose[3] then
            StackingDirection = 0
            if (FirstPallet.PalletNum.LayerCount == FirstPallet.Layer) and (FirstPallet.State.Full == false) then
                CurrentPallet = -1
            else
                CurrentPallet = 1
            end
        else
            StackingDirection = 1
            if (SecondPallet.PalletNum.LayerCount == SecondPallet.Layer) and (SecondPallet.State.Full == false) then
                CurrentPallet = 1
            else
                CurrentPallet = -1
            end
        end
        Communication.Lifting.RestrictMoveFlag = true
    elseif (HeightDiff <= Communication.Lifting.EndHeightDiff)
        or (StackingDirection == 0 and FirstPalletPose.pose[3] < SecondPalletPose.pose[3])
        or (StackingDirection == 1 and FirstPalletPose.pose[3] > SecondPalletPose.pose[3]) then
        Communication.Lifting.RestrictMoveFlag = false
    end
end
----------------------------------------------------------------
--获取到位信号
local function GetBeInpPlaceDI()
    local FirstSucker = 0
    local SecondSucker = 0
    local SwitchConveyor =
    {
        [-1] = function()
            FirstSucker = GetSuckerFlag(FirstPallet, 0)
            GetPalletStatusResult(FirstPallet.State, FirstPallet.InPlaceA, FirstPallet.InPlaceB) --得到栈板到位状态结果
            GetPalletEnableResult(FirstPallet.State, FirstPallet.StateValue)                     --得到栈板上使能的结果
            GetBeInpPlaceDIFlag(FirstPallet, FirstSucker, 0)
        end,
        [1] = function()
            SecondSucker = GetSuckerFlag(SecondPallet, 1)
            GetPalletStatusResult(SecondPallet.State, SecondPallet.InPlaceA, SecondPallet.InPlaceB) --得到栈板到位状态结果
            GetPalletEnableResult(SecondPallet.State, SecondPallet.StateValue)                      --得到栈板上使能的结果
            GetBeInpPlaceDIFlag(SecondPallet, SecondSucker, 1)
        end
    }

    local switch_conveyor
    --for i = -1, 1, 2 do
    local i = -1
    switch_conveyor = SwitchConveyor[i * SwitchConveyorFlag]
    if switch_conveyor then
        switch_conveyor()
    else
        print("The Switch Conveyor Is Wrong !")
        Pause()
    end
    --end
end

--------------------------------------------------------------
--子线程码垛主流程
local function ChoosePallet(PalletNumber)
	ChildProcessAction(PalletNumber, PalletNumber.State.Full)
    CycleCheckPallet(PalletNumber, PalletNumber.State.Full)
	CommitPalletStatus(PalletNumber.StateValue, PalletNumber.RegisterID) --上传栈板状态
end

--------------------------------------------------------------
--码垛栈板切换
local function PalletChildProcess()
	local SwitchPallet =
	{
        [0] = function()
            ChoosePallet(FirstPallet)
		end,
        [1] = function()
            ChoosePallet(SecondPallet)
		end
    }
	
    local switch_mode = SwitchPallet[Pallet]
    if switch_mode then
        switch_mode()
    else
        print("The Palletizing Stop!")
        Pause()
    end
end

---------------------------------------------------------------
--子线程拆垛主流程
local function ChooseDePallet(PalletNumber)
	ChildProcessAction(PalletNumber, PalletNumber.State.Empty)
    CycleCheckPallet(PalletNumber, PalletNumber.State.Empty)
	CommitPalletStatus(PalletNumber.StateValue, PalletNumber.RegisterID)         --上传栈板状态
end

---------------------------------------------------------------
--拆垛栈板切换
local function DePalletChildProcess()
	local SwitchDePallet =
	{
        [0] = function()
            ChooseDePallet(FirstPallet)
		end,
        [1] = function()
            ChooseDePallet(SecondPallet)
		end
	}

    local switch_mode = SwitchDePallet[Pallet]
    if switch_mode then
        switch_mode()
    else
        print("The Palletizing Stop!")
        Pause()
    end
end

---------------------------------------------------------------
---------------------------------------------------------------
--正常状态
local SwitchPalletMode =
{
    [1] = function()
        Wait(Time.Thread.s1)
        ::UpdateState::
        PalletChildProcess()
        if FinishFlag == true then
            goto UpdateState
        else
        if PalletFinishFlag == true
            and ((FirstPallet.State.Full == false) or (SecondPallet.State.Full == false))
                and (WorkFinishFlag == false) then
                GetBeInpPlaceDI()
            end
        end
    end,
    [2] = function()
        Wait(Time.Thread.s1)
        ::UpdateDeState::
        DePalletChildProcess()
        if FinishFlag == true then
            goto UpdateDeState
        end
        if PalletFinishFlag == true
            and ((FirstPallet.State.Empty == false) or (SecondPallet.State.Empty == false))
            and (WorkFinishFlag == false) then
            GetBeInpPlaceDI()
        end
    end
}

while true do
    if Communication.Controller.Modbus.SuccessFlag == true then
        Init()
        print("\rChildProcess Start:")
        local switch_mode
        while true do
            if (Pallet == 0) then
                switch_mode = SwitchPalletMode[FirstPallet.PalletMode]
            else
                switch_mode = SwitchPalletMode[SecondPallet.PalletMode]
            end
            if switch_mode then
                switch_mode()
            else
                print("The ChildProcess SwitchPalletMode is error, please check it!")
                Pause()
            end
        end
    end
end
