--------------------------------------------------------------
--此文件仅用于定义执行运动
---------------------------------------------------------------
--局部常量
local mqttFunc = require("libplugin_eco")
local Dir =
{
    Forward = 1,  --正向运动
    Backward = -1 --反向运动
}
--当前运动区域
local MotionArea =
{
    IDLE = 0,
    NORMAL = 1,       --普通情况
    LS_TRANS = 2,     --隔板过渡区
    PALLET_TRANS = 3, --栈板过渡区
}
local CurWorkDir = --当前工作方向，用以区分走哪一侧过渡点
{
    Left = 0,
    Right = 1,
}
--运行时过渡点序号
local TransStep =
{
    A = 1,
    B = 2, 
    C = 3, 
    D = 4, 
    E = 5
}
local LDVel = MotionParas.Forward.Pick.NormVel
local NLDVel = MotionParas.Backward.Pick.NormVel
local LDPlaceVel = MotionParas.Forward.Place.NormVel
local LiftingPoint = {}          --升降柱安全点位
local NearJoint = { joint = { 90, 0, 90, 0, -90, 0 } } --逆解参考点
if HighLoadFunc == true then
    LiftingPoint = DeepCopy(LiftingSafetyPoint_HL)
else
    LiftingPoint = DeepCopy(LiftingSafetyPoint)
end
---------------------------------------------------------------
--局部变量
local SingleMotion = false    --单次运动信号
local SyncSignal = false      --同步信号
local IsStandby = false       --待机位置
local IsSafeMode = false      --安全模式
local ResetMotionFlag = false --自动复位运动标志位，为true时表示当前正处在复位运动过程中
local LiftingHeight = 0       --升降柱高度
local SyncMotionVel = 1       --机器人-升降柱相对运动速度
local PrePallet = 1           --缠膜栈板号
local PrePoseHeight = 0       --缠膜高度
---------------------------------------------------------------
--系统初始化
---------------------------------------------------------------
--坐标系重定义
local function SetCoordinate(PalletNumber, PalletNum)
    PalletNumber.Layer = GetLayerCnt(PalletName, PalletNum)
    PalletNumber.Coordinate.UserNum = GetPalletUser(PalletName, PalletNum)
    local CTool = GetPalletTool(PalletName, ToolType.Conc)
    PalletNumber.Coordinate.ToolNum = CTool[1]
    PalletNumber.BoxProperty.BoxWeight = GetBoxLoad(PalletName, PalletNum)
    local PalletUser = CalcUser(PalletNumber.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
    PalletUser[3] = PalletUser[3] + PalletNumber.ProcessNum.PalletHeight
    SetUser(PalletNumber.Coordinate.UserNum, PalletUser)
    HomePointPose = PositiveKin(HomePoint,
        { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })
    if (PalletNumber.LayerSheet.Enable == true) then
        local ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.joint)
        if (ProjectType == 1) then
            local LSPickJoint = { joint = {} }
            LSPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.joint)
            PalletNumber.LayerSheet.PickPose = PositiveKin(LSPickJoint)
        else
            PalletNumber.LayerSheet.pose = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.pose)
            PalletNumber.LayerSheet.pose[3] = PalletNumber.LayerSheet.pose[3] - PalletNumber.ProcessNum.PalletHeight
        end
    end
end
---------------------------------------------------------------
--栈板状态初始化
local function InitPalletStatus()
    GetPalletStatus(FirstPallet)
    GetPalletStatus(SecondPallet)
    if (FirstPallet.State.Replace == false and SecondPallet.State.Replace == false) then
        TriLightStatus(FirstPallet, Light.Red.On)
        TriLightStatus(SecondPallet, Light.Red.On)
        Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
    elseif (FirstPallet.State.Replace == false and SecondPallet.State.Replace == true) then
        TriLightStatus(FirstPallet, Light.Red.On)
        TriLightStatus(SecondPallet, Light.Init)
        Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
    elseif (FirstPallet.State.Replace == true and SecondPallet.State.Replace == false) then
        TriLightStatus(FirstPallet, Light.Init)
        TriLightStatus(SecondPallet, Light.Red.On)
        Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
    end
end
--------------------------------------------------------------
--检查吸盘类型
local function CheckVacuumCupType()
    local CType = GetVal("PalletVacuumCupType")
    if (CType ~= PalletVacuumCupFunc) then
        -- 远程启动工程吸盘类型和工作站吸盘类型不一致时报警
        LogError("Project VacuumCup type is %s, current is %s", PalletVacuumCupFunc, CType)
        Alarm("VacuumCup type is wrong", ErrorMessage.Type.VacuumCupTypeErr)
    end
end
---------------------------------------------------------------
--状态初始化
local function InitFSM()
    CheckVacuumCupType()
    GetEnableStatus()
    if (FirstPallet.StateValue.Enable == 1)
        and (SecondPallet.StateValue.Enable == 1) then
        ExecuteSafeModule(FirstPallet, SecondPallet)
        ExecuteSafeModule(SecondPallet, FirstPallet)
        Wait(Time.Thread.s0)

        local SwitchMode =
        {
            [ModeType.SC] = function()
                if (PalletBeInPlaceOKButton == false) or SimulateMode==1 then
                    InitPalletStatus()
                    Pallet = Left
                else
                    Pallet = Idle
                end
                StateMachine = FSMType.SLR
                LogInfo("Initialized single conveyor dual pallet mode!")
            end,
            [ModeType.DCS] = function()
                LogInfo("Initialized dual conveyor single pallet mode!")
                Alarm("ModeType is wrong!", ErrorMessage.Type.WorkingDataErr)
            end,
            [ModeType.DC] = function()
                if (PalletBeInPlaceOKButton == false) or SimulateMode==1 then
                    InitPalletStatus()
                    Pallet = Left
                else
                    Pallet = Idle
                end
                StateMachine = FSMType.DLR
                LogInfo("Initialized dual conveyor dual pallet mode!")
            end,
            [ModeType.Exh] = function()
                InitPalletStatus()
                --从寄存器读取上次完成方向和当前方向，判断是否需要交替栈板
                Pallet = ReadRobotModbus(FirstPallet.RegisterID.PalletDir)
                local PreFinishDir = ReadRobotModbus(FirstPallet.RegisterID.LastFinishDir)
                --上次完成方向和当前方向一致，则切换至另一侧栈板
                if (PreFinishDir == Pallet + 1 and PreFinishDir ~= 0) then
                    if (Pallet == Left) then
                        Pallet = Right
                        WorkingSignalDir = SignalDir.Right
                    else
                        Pallet = Left
                        WorkingSignalDir = SignalDir.Left
                    end
                --首次运行或刚完成一轮交替，方向不变，维持当前PalletDir
                else
                    if (Pallet == Left) then
                        WorkingSignalDir = SignalDir.Left
                    else
                        WorkingSignalDir = SignalDir.Right
                    end
                end
                --使用双传送带交替状态机(DLR)，两侧栈板交替执行码垛/拆垛
                StateMachine = FSMType.DLR
                LogInfo("Initialized exhibition mode!")
            end
        }

        local switch_mode = SwitchMode[WorkingMode]
        if switch_mode then
            switch_mode()
        else
            Alarm("SwitchMode is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
        SetCoordinate(SecondPallet, Right)
        SetCoordinate(FirstPallet, Left)
    else
        if (FirstPallet.StateValue.Enable == 1) then
            ExecuteSafeModule(FirstPallet, SecondPallet)
            GetPalletStatus(FirstPallet)
            if (FirstPallet.State.Replace == false and PalletBeInPlaceOKButton == false) then
                TriLightStatus(FirstPallet, Light.Red.On)
                TriLightStatus(SecondPallet, Light.Init)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            end
            Pallet = Left
            StateMachine = FSMType.SL
            SetCoordinate(FirstPallet, Left)
            LogInfo("Initialized single conveyor single left pallet mode!")
        elseif (SecondPallet.StateValue.Enable == 1) then
            ExecuteSafeModule(SecondPallet, FirstPallet)
            GetPalletStatus(SecondPallet)
            if (SecondPallet.State.Replace == false and PalletBeInPlaceOKButton == false) then
                TriLightStatus(FirstPallet, Light.Init)
                TriLightStatus(SecondPallet, Light.Red.On)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            end
            Pallet = Right
            StateMachine = FSMType.SR
            SetCoordinate(SecondPallet, Right)
            LogInfo("Initialized single conveyor single right pallet mode!")
        else
            StateMachine = FSMType.IDLE
            TriLightStatus(FirstPallet, Light.Red.On)
            TriLightStatus(SecondPallet, Light.Red.On)
            Alarm("Pallet not enabled!", ErrorMessage.Type.PalletEnableErr)
        end
    end
end
--------------------------------------------------------------
--数据获取模式初始化
local function InitStorageMode()
    StorageMode = GetVal("PalletPowerDown")
    LogInfo("%s", (StorageMode == 0) and "Get working data from controller global variables!" or
        "Get working data from registers!")
    SetVal("PalletProjectName", PalletName)
    SetVal("PalletWorkingMode", WorkingMode)
    SetVal("LWorkState", StateType.Idle)
    SetVal("RWorkState", StateType.Idle)
    SetVal("ScriptState", true)
    SetVal("SoftStopState", false)
    if (StorageMode == nil) then
        StorageMode = 1
        SetVal("PalletTime", Time.Num)
        SetVal("PalletCapacity", Capacity.Num)
        SetVal("PalletWorkingDataA", FirstPallet.PalletNum)
        SetVal("PalletWorkingDataB", SecondPallet.PalletNum)
    end
    RemoteMode = GetVal("PalletRemoteMode")
    if (RemoteMode == nil) then
        RemoteMode = 1
    end
    SetVal("PalletRemoteMode", 1)
    if (GetVal("PalletPartNumA") == nil) then
        SetVal("PalletPartNumA", FirstPallet.LayerSheet.ReLSNum)
    end
    if (GetVal("PalletPartNumB") == nil) then
        SetVal("PalletPartNumB", SecondPallet.LayerSheet.ReLSNum)
    end
    if (GetVal("PalletPartPlaceA") == nil) then
        SetVal("PalletPartPlaceA", FirstPallet.LayerSheet.Place)
    end
    if (GetVal("PalletPartPlaceB") == nil) then
        SetVal("PalletPartPlaceB", SecondPallet.LayerSheet.Place)
    end
    --初始化时将两个栈板的码垛/拆垛模式写入全局变量
    if (WorkingMode == ModeType.Exh) then
        if (GetVal("PalletModeA") == nil) then
            SetVal("PalletModeA", FirstPallet.Mode)
        end
        if (GetVal("PalletModeB") == nil) then
            SetVal("PalletModeB", SecondPallet.Mode)
        end
    end
    if (GetVal("PalletMotionArea") == nil) then
        SetVal("PalletMotionArea", MotionArea.NORMAL)
    end
    if (GetVal("CurWorkDir") == nil) then
        SetVal("CurWorkDir", CurWorkDir.Left)
    end
    if (GetVal("PalletTransDir") == nil) then
        SetVal("PalletTransDir", Dir.Forward)
    end
    if (GetVal("PalletTransStep") == nil) then
        SetVal("PalletTransStep", TransStep.A)
    end
    if (GetVal("PalletCurPoints") == nil) then
        SetVal("PalletCurPoints", {})
    end
    if (GetVal("PalletVacuumCupType") == nil) then
        SetVal("PalletVacuumCupType", PalletVacuumCupFunc)
    end
end
---------------------------------------------------------------
--三色灯状态初始化
local function InitLight()
    if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
        TriLightStatus(FirstPallet, Light.Green.On)
        TriLightStatus(SecondPallet, Light.Green.On)
    elseif (StateMachine == FSMType.SL) then
        TriLightStatus(FirstPallet, Light.Green.On)
        TriLightStatus(SecondPallet, Light.Init)
    else
        TriLightStatus(FirstPallet, Light.Init)
        TriLightStatus(SecondPallet, Light.Green.On)
    end
    LogInfo("Initialized tri-color light success!")
end
---------------------------------------------------------------
--软停止动作
local function SoftStopMotion()
    if (SoftStopRequested == true) then
        SoftStopSignal = false      --软停止信号标志位复位
        SoftStopRequested = false   --软停止请求标志位复位
        LogInfo("Execute soft stop motion!")
        MovJ(HomePoint, { v = MotionParas.Backward.Pick.NormVel * 0.25, cp = 0 })
        SetVal("SoftStopState", false)  --软停止状态，供上位机状态显示使用：值为true表示软停止触发，值为false表示软停止动作结束
        Halt()
    end
end 
---------------------------------------------------------------
--升降柱相关接口
---------------------------------------------------------------
-----------------------------仿真------------------------------
--发送升降台升降动作消息
local function PublishLiftAction(Dest, UsedTime)
    local ActionStr = "[" .. Dest .. "," .. math.ceil(UsedTime) .. "]"
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':liftAction', ActionStr, 0, false)
end
---------------------------------------------------------------
--模拟升降台升降  
local function SimulateLiftingColumnMove(dest)
    LogInfo("Lifting column move to %s!", dest)
    LiftingColumn = SimulateProcess.LiftingColumn
    if LiftingColumn.LiftingHeight ~= dest then
        local UsedTime = math.floor(math.abs(LiftingColumn.LiftingHeight - dest) / LiftingColumn.Speed / SimulateProcess.SimulateSpeed * 1000)
        UsedTime = math.ceil(UsedTime / 100) * 100
        LiftingColumn.UsedTime = UsedTime * 1.0
        LiftingColumn.LiftingHeight = dest
        LogInfo("Lifting column move to %s, used time %s ms!", LiftingColumn.LiftingHeight, LiftingColumn.UsedTime)
        if (StateMachine == FSMType.DLR and Pallet ~= PrePallet) then
            PublishLiftAction(dest, LiftingColumn.UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            --Wait(100)
        else
            PublishLiftAction(dest, LiftingColumn.UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            --Wait(100)
        end
    end
end
---------------------------------------------------------------
--发送机械臂抓取动作消息  
local function PublishRobotAction()

    local BoxOnRobotStr = "["
    RobotContainer = SimulateProcess.BoxOnRobot

    if #RobotContainer == 0 then
        BoxOnRobotStr = BoxOnRobotStr.."]"
    else
        for k, v in pairs(RobotContainer) do
            local BoxStr = "["..v.Id..","..v.Layer..","..v.Pallet..","..v.State..","..v.Child.."]"
            if v == RobotContainer[#RobotContainer] then
                BoxOnRobotStr = BoxOnRobotStr..BoxStr .."]"
            else
                BoxOnRobotStr = BoxOnRobotStr..BoxStr .. ","
            end
        end
    end

    Joint = GetAngle().joint

    local JointStr = "["..Joint[1]..","..Joint[2]..","..Joint[3]..","..Joint[4]..","..Joint[5]..","..Joint[6].."]"
    local ActionStr = "["..BoxOnRobotStr..","..JointStr.."]"

    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':robotAction', ActionStr, 0, false)
end
---------------------------------------------------------------
--发送机械臂抓取动作消息  
local function PublishLayerSheetAction(action, palletNum)
    local Joint = GetAngle().joint
    local JointStr = "["..Joint[1]..","..Joint[2]..","..Joint[3]..","..Joint[4]..","..Joint[5]..","..Joint[6].."]"

    local ActionStr = "["..action..","..JointStr..","..palletNum.."]"
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':partitionAction', ActionStr, 0, false)
end
---------------------------------------------------------------
-- 按栈板当前层剩余空位，为本次新增箱子分配所属层号（从 1 起为第一层）
-- 一次抓多箱且跨层时，靠前的箱子落在当前层，超出部分递推到后续层
-- RemainBoxNum<=0 时仅在未达总层数时 +1；禁止对越界层号调用 GetOddBoxCnt（会报 can not find specified layer）
local function AssignPickBoxLayers(boxList, startIndex, PalletNumber)
    local maxLayer = PalletNumber.Layer
    if type(maxLayer) ~= "number" or maxLayer < 1 then
        maxLayer = 1
    end
    local layer = PalletNumber.PalletNum.LayerCount or 1
    if layer < 1 then
        layer = 1
    elseif layer > maxLayer then
        layer = maxLayer
    end
    local remain = PalletNumber.PalletNum.RemainBoxNum or 0
    if remain < 0 then
        remain = 0
    end

    local function refillRemainForLayer()
        -- 层号合法时才查垛型容量；失败或非法则保底 1，避免脚本中断
        if layer >= 1 and layer <= maxLayer then
            local ok, cnt = pcall(GetOddBoxCnt, PalletName, PalletNumber.Pallet, layer)
            if ok and type(cnt) == "number" and cnt > 0 then
                remain = cnt
                return
            end
        end
        remain = 1
    end

    for i = startIndex, #boxList do
        if remain <= 0 then
            if layer < maxLayer then
                layer = layer + 1
                refillRemainForLayer()
            else
                -- 已在末层仍无空位：不再跨层、不查越界层号
                remain = 1
            end
        end
        boxList[i]:setLayer(layer)
        remain = remain - 1
    end
end
---------------------------------------------------------------
--更新箱子抓取状态
local function UpdatePickBoxState(PalletNumber, CPoint)
    local ContainerIn = SimulateProcess.BoxOnRobot
    local Conveyor = SimulateProcess.PresentConveyor

    if CPoint.Paras.Mode == MotionType.Norm then
    
        if PalletNumber.Mode == WorkType.Pallet then

            ContainerOut = Conveyor.Container
            local startIndex = #ContainerIn + 1

            if CPoint.Paras.VacuumCup > 0 then --吸多个箱子时
                for i = 1, math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1 do
                    table.insert(ContainerIn, ContainerOut[i]) 
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1
            elseif CPoint.Paras.VacuumCup == -1 then -- 多吸单放
                for i = 1, math.abs(PalletVacuumCupFunc) do
                    table.insert(ContainerIn, ContainerOut[i]) 
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + PalletVacuumCupFunc
            else --吸单个箱子时
                table.insert(ContainerIn, ContainerOut[1])
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + 1
            end

            AssignPickBoxLayers(ContainerIn, startIndex, PalletNumber)
            for i = startIndex, #ContainerIn do
                local v = ContainerIn[i]
                v:setState(1)
                v:setIndex(SimulateProcess.LayerBoxIndex)
                v:setPickIndex(SimulateProcess.PickIndex)
                v:setPallet(Pallet)
            end
            -- 抓取后先停后续箱子前移，避免与吸盘上尚未抬离的箱子碰撞
            Conveyor.PickDelayTime = SimulateProcess.PickDelayTime
        else
            local ContainerIn = SimulateProcess.BoxOnRobot
            local ConveyorNo = Pallet
            local BoxSize = PalletNumber.BoxProperty

            local BoxDirection
            if ConveyorNo == 0 then
                BoxDirection = FirstPalletBoxDirection
            else
                BoxDirection = SecondPalletBoxDirection
            end

            if CPoint.Paras.VacuumCup > 0 then ---吸多个箱子时
                for i = 1, math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1 do
                    local B
                    if BoxDirection == 0 then
                        B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxWidth, BoxSize.BoxLength)
                    else
                        B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxLength, BoxSize.BoxWidth)
                    end
                    
                    table.insert(ContainerIn, B)
                    B:setId(PalletNumber.PalletNum.NextBoxCount)
                    B:setState(1)
                    B:setLayer(PalletNumber.PalletNum.LayerCount)
                    B:setIndex(SimulateProcess.LayerBoxIndex)
                    B:setPickIndex(SimulateProcess.PickIndex)
                    B:setPallet(Pallet)
                    B:setChild(i - 1)
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1
                -- elseif CPoint.Paras.VacuumCup == -1 then
                --     for i = 1, PalletVacuumCupFunc do
                --         local B
                --         if BoxDirection == 0 then
                --             B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxWidth, BoxSize.BoxLength)
                --         else
                --             B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxLength, BoxSize.BoxWidth)
                --         end
                    
                --         table.insert(ContainerIn, B)
                --         B:setId(PalletNumber.PalletNum.NextBoxCount)
                --         B:setState(1)
                --         B:setLayer(PalletNumber.PalletNum.LayerCount)
                --         B:setIndex(SimulateProcess.LayerBoxIndex)
                --         B:setPickIndex(SimulateProcess.PickIndex)
                --         B:setPallet(Pallet)
                --         B:setChild(i - 1)
                --     end
                --     SimulateProcess.BoxCount = SimulateProcess.BoxCount + PalletVacuumCupFunc
            else
                local B
                if BoxDirection == 0 then
                    B = Box:new(0, Conveyor.Length - 0.5 * BoxSize.BoxWidth, ConveyorNo, BoxSize.BoxWidth,
                        BoxSize.BoxLength)
                else
                    B = Box:new(0, Conveyor.Length - 0.5 * BoxSize.BoxLength, ConveyorNo, BoxSize.BoxLength,
                        BoxSize.BoxWidth)
                end
                table.insert(ContainerIn, B)

                B:setId(PalletNumber.PalletNum.NextBoxCount)
                B:setState(1)
                B:setLayer(PalletNumber.PalletNum.LayerCount)
                B:setIndex(SimulateProcess.LayerBoxIndex)
                B:setPickIndex(SimulateProcess.PickIndex)
                B:setPallet(Pallet)

                SimulateProcess.BoxCount = SimulateProcess.BoxCount + 1
            end
        end
            
        SimulateProcess.LayerBoxIndex = SimulateProcess.LayerBoxIndex + 1
        SimulateProcess.PickIndex = SimulateProcess.PickIndex + 1
        
        PublishRobotAction()
        -- PublishRobotAction()
        -- PublishRobotAction()
    else
        PublishLayerSheetAction(1, Pallet)
        -- PublishLayerSheetAction(1, Pallet)
        -- PublishLayerSheetAction(1, Pallet)
    end
end
---------------------------------------------------------------
--更新箱子放下状态
local function UpdatePlaceBoxState(PalletNumber, CPoint)
    ContainerOut = SimulateProcess.BoxOnRobot
    local TempBoxOnRobot = DeepCopy(SimulateProcess.BoxOnRobot)
    if CPoint.Paras.Mode == MotionType.Norm then
        if PalletNumber.Mode == WorkType.Pallet then
            if PalletNumber == FirstPallet then
                ContainerIn = SimulateProcess.LeftPallet.Container
            else
                ContainerIn = SimulateProcess.RightPallet.Container
            end

            if CPoint.Paras.VacuumCup == -1 then
                local value = ContainerOut[1]
                ContainerIn[#ContainerIn + 1] = value.id
                -- 放下前用当前工作层校正：多吸单放跨层时以此刻 LayerCount 为准
                value:setLayer(PalletNumber.PalletNum.LayerCount)
                value:setState(2)
                if SimulateProcess.SimulateSpeed == 1 then
                    SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                end
            else 
              for k, v in pairs(ContainerOut) do
                  ContainerIn[#ContainerIn + 1] = v.Id
                  -- 保持抓取时按空位分配的层号；若无效则回退到当前工作层
                  if v.Layer == nil or v.Layer < 1 then
                      v:setLayer(PalletNumber.PalletNum.LayerCount)
                  end
                  v:setState(2)
                  if SimulateProcess.SimulateSpeed == 1 then
                      SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                  end
              end
            end
            if CPoint.Paras.VacuumCup == -1 then
                SimulateProcess.BoxOnRobot = { SimulateProcess.BoxOnRobot[1] }
            end
        else
            SimulateProcess.PresentConveyor.PlaceDelayTime = Time.Place.In
            ContainerIn = SimulateProcess.PresentConveyor.Container
            for k, v in pairs(ContainerOut) do
                ContainerIn[#ContainerIn + 1] = v
                v:setState(0)
                if SimulateProcess.SimulateSpeed == 1 then
                    SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                end
            end
        end

        LogInfo("%s", SimulateProcess.BoxOnRobot)
        PublishRobotAction()
        -- PublishRobotAction()
        -- PublishRobotAction()


        if PalletNumber.Mode == WorkType.Pallet then
            if CPoint.Paras.VacuumCup == -1 then
                table.remove(TempBoxOnRobot, 1)
                SimulateProcess.BoxOnRobot = TempBoxOnRobot
            else 
                for i = 1, #ContainerOut do
                    table.remove(ContainerOut, 1)
                end
            end
        else
            for i = 1, #ContainerOut do
                table.remove(ContainerOut, 1)
            end
        end

    else
        PublishLayerSheetAction(0, Pallet)
        -- PublishLayerSheetAction(0, Pallet)
        -- PublishLayerSheetAction(0, Pallet)
    end
end
---------------------------------------------------------------
--检测传送带上是否还有箱子
local function CheckBoxOnConveyor(Conveyor, PalletNo)
    for k, v in pairs(Conveyor.Container) do
        if v.Pallet == PalletNo then
            return true
        end
    end

    return false
end
---------------------------------------------------------------
--统计仿真码垛节拍
local function StatisticLayerRate()
    if SimulateProcess.Statistic.TotalTime > 0 then
        SimulateProcess.Statistic.LayerRate = math.floor(SimulateProcess.Statistic.BoxCount / SimulateProcess.Statistic.TotalTime * 1000 * 60 * 10)
    end
end
---------------------------------------------------------------
--统计单栈板耗时
local function StatisticPalletRate(PalletSide)
    if PalletSide.CanCount == 1 then
        SimulateProcess.Statistic.PalletNum = SimulateProcess.Statistic.PalletNum + 1
        SimulateProcess.Statistic.PalletRate = math.floor(SimulateProcess.Statistic.PalletTotalTime / 1000 / 60 /
            SimulateProcess.Statistic.PalletNum * 10)
    end

    if SimulateProcess.SimulateSpeed > 1 then
        PalletSide.CanCount = 0
    else
        PalletSide.CanCount = 1
    end
end
---------------------------------------------------------------
----------------------------实际-------------------------------
--升降柱初始化
local function InitLifting()
    if (PalletLiftingFunction == true) then
        if SimulateMode == 1 then
            if (Communication.Lifting.Mode == LiftingType.EWELLIX) then
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.EWELLIX.MaxDistance
            elseif (Communication.Lifting.Mode == LiftingType.GeMinG) then
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.GeMinG.MaxDistance
            elseif (Communication.Lifting.Mode == LiftingType.ZT3ILC) then
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.ZT3ILC.MaxDistance
            else
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.LINAK.MaxDistance
            end
            LogInfo("Simulate mode: CreateTcpConnection not excute!")
            return
        end

        local Err = 0
        local CurrentHeight
        local SwitchCommMode =
        {
            [LiftingType.EWELLIX] = function()
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.EWELLIX.MaxDistance
                Err, Communication.Lifting.Brand.EWELLIX.Tcp.Socket = TCPCreate(false,
                    Communication.Lifting.Brand.EWELLIX.Tcp.Ip, Communication.Lifting.Brand.EWELLIX.Tcp.Port) --创建TCP客户端
                LogInfo("Attempting to create TCP connection to EWELLIX lifting at %s:%d!",
                    Communication.Lifting.Brand.EWELLIX.Tcp.Ip, Communication.Lifting.Brand.EWELLIX.Tcp.Port)
            end,
            [LiftingType.GeMinG] = function()
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.GeMinG.MaxDistance
                Err, Communication.Lifting.Brand.GeMinG.ModbusRTU.Id = ModbusRTUCreate(
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId,
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.BaudRate,
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.Parity,
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.DataBit,
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.StopBit)
                LogInfo("Attempting to create modbus RTU connection to GeMinG lifting with slave ID %d!",
                    Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId)
            end,
            [LiftingType.ZT3ILC] = function()
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.ZT3ILC.MaxDistance
                Err, Communication.Lifting.Brand.ZT3ILC.Modbus.Id = ModbusCreate(
                    Communication.Lifting.Brand.ZT3ILC.Modbus.Ip,
                    Communication.Lifting.Brand.ZT3ILC.Modbus.Port)
                LogInfo("Attempting to create modbus TCP connection to ZT3ILC lifting at %s:%d!",
                    Communication.Lifting.Brand.ZT3ILC.Modbus.Ip, Communication.Lifting.Brand.ZT3ILC.Modbus.Port)
            end,
            [LiftingType.LINAK] = function()
                Communication.Lifting.CMaxDis = Communication.Lifting.Brand.LINAK.MaxDistance
                Err, Communication.Lifting.Brand.LINAK.Modbus.Id = ModbusCreate(
                    Communication.Lifting.Brand.LINAK.Modbus.Ip,
                    Communication.Lifting.Brand.LINAK.Modbus.Port)
                LogInfo("Attempting to create modbus TCP connection to Linak lifting at %s:%d!",
                    Communication.Lifting.Brand.LINAK.Modbus.Ip, Communication.Lifting.Brand.LINAK.Modbus.Port)
            end
        }
        local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
        if switch_mode then
            switch_mode()
        else
            Alarm("CommMode is error!", ErrorMessage.Type.WorkingDataErr)
        end
        if (Err == 0) then
            LogInfo("Communication initialization completed!")
        else
            Alarm("Communication initialization failed!", ErrorMessage.Type.LinkErr)
        end

        local SwitchCommInitMode =
        {
            [LiftingType.EWELLIX] = function()
                LogInfo("Create tcp client success!")
                EWLInit()
                CurrentHeight = EWLGetPosition()
                if (Communication.Lifting.StopFlag == true) then
                    Communication.Lifting.StopFlag = false
                    CurrentHeight = EWLGetPosition()
                end
            end,
            [LiftingType.GeMinG] = function()
                LogInfo("Create RTUModbus client success!")
                SV660CInit()
                SV660CEnable(1)
                CurrentHeight = SV660CGetPosition()
                CurrentHeight = 0.1 * CurrentHeight
            end,
            [LiftingType.ZT3ILC] = function()
                LogInfo("Create modbus client success!")
                ZC01Init()
                ZC01Enable(1)
                CurrentHeight = ZC01GetPosition()
                CurrentHeight = ConvertFloat(CurrentHeight)
            end,
            [LiftingType.LINAK] = function()
                LogInfo("Create modbus client success!")
                LINAKInit()
                CurrentHeight = LINAKGetPosition()
                CurrentHeight = 0.1 * CurrentHeight
            end
        }

        local switch_init_mode = SwitchCommInitMode[Communication.Lifting.Mode]
        if switch_init_mode then
            switch_init_mode()
        else
            Alarm("switch_init_mode is error!", ErrorMessage.Type.WorkingDataErr)
        end

        LiftingHeight = math.ceil(CurrentHeight)
        Communication.Lifting.Init = true
        LogInfo("Initialized lifting success!")
    end
end
---------------------------------------------------------------
--实时获取升降柱高度
local function GetLiftingHeight(CLH)
    local Err = 0
    local Res = 0
    local SwitchCommMode =
    {
        [LiftingType.EWELLIX] = function()
            Res = EWLGetPosition()
            if ((Res >= CLH - 3) and (Res <= CLH + 3)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.GeMinG] = function()
            local RLH = math.ceil(CLH * 10)
            Res = SV660CGetPosition()
            if ((Res <= RLH + 10) and (Res >= RLH - 10)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.ZT3ILC] = function()
            Res = math.ceil(ZC01GetPosition())
            if ((Res <= math.ceil(CLH + 1)) and (Res >= math.ceil(CLH - 1))) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.LINAK] = function()
            local RLH = math.ceil(CLH * 10)
            Res = LINAKGetPosition()
            if ((Res <= RLH + 30) and (Res >= RLH - 30)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end
    }
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]

    if (SyncSignal == true and SimulateMode == 0) then
        if switch_mode then
            switch_mode()
        else
            Alarm("CommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
        end
    end
end
---------------------------------------------------------------
--等待升降柱到位运动
local function LiftingMotion(CLH)
    local Res = 0
    local Err = 0
    local StartTime = os.time()
    local Timeout = 60 --60s 超时报警
    local SwitchCommMode =
    {
        [LiftingType.EWELLIX] = function()
            repeat
                Res = EWLGetPosition()
                if Err ~= 0 then
                    Alarm("Lifting state error!", ErrorMessage.Type.LiftingStateErr)
                end
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    EWLRun(CLH)
                    LogInfo("Lifting motion target position is %s mm!", CLH)
                    Res = EWLGetPosition()
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", Res)
                Wait(100)
            until ((Res <= CLH + 3) and (Res >= CLH - 3))
        end,
        [LiftingType.GeMinG] = function()
            local RLH = math.ceil(CLH * 10)
            repeat
                Res = SV660CGetPosition()
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    SV660CRun(RLH)
                    LogInfo("Lifting motion target position is %s mm!", 0.1 * RLH)
                    Res = SV660CGetPosition()
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", 0.1 * Res)
                Wait(100)
            until ((Res <= RLH + 10) and (Res >= RLH - 10))
        end,
        [LiftingType.ZT3ILC] = function()
            repeat
                Res = math.ceil(ZC01GetPosition())
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    ZC01Init()
                    ZC01Run(math.ceil(CLH))
                    LogInfo("Lifting motion target position is %s mm!", CLH)
                    Res = math.ceil(ZC01GetPosition())
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", Res)
                Wait(100)
            until ((Res <= math.ceil(CLH + 1)) and (Res >= math.ceil(CLH - 1)))
        end,
        [LiftingType.LINAK] = function()
            local RLH = math.ceil(CLH * 10)
            repeat
                Res = LINAKGetPosition()
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    LINAKInit()
                    LINAKRun(RLH)
                    LogInfo("Lifting motion target position is %s mm!", 0.1 * RLH)
                    Res = LINAKGetPosition()
                end
                LogInfo("Lifting motion position is %s mm! ", 0.1 * Res)
                Wait(100)
            until ((Res <= RLH + 30) and (Res >= RLH - 30))
        end
    }
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("Lifting motion completed!")
    else
        Alarm("CommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
    end
end
---------------------------------------------------------------
--调整升降柱高度
local function AdjustLiftingHeight(CLH)
    if (PalletLiftingFunction == true) and (math.abs(CLH - LiftingHeight) > 1) then
        LogInfo("Lifting relative motion distance is %s mm!", math.abs(CLH - LiftingHeight))
        SyncSignal = true
        SyncMotionVel = NLDVel
        LogInfo("Lifting-Robot motion velocity ratio is %s!", SyncMotionVel)
        LiftingHeight = CLH
        Communication.Lifting.TimesPerHour = Communication.Lifting.TimesPerHour + 1
        LogInfo("Lifting motion target position is %s mm!", CLH)
        --先到固定安全姿态，升降到位前保持该姿态
        MovJ(LiftingPoint, { v = NLDVel, cp = 0 })
        local StartTime = os.time()
        local InPosition = false
        repeat
            Wait(100)
            local CJoint = GetAngle()
            InPosition = type(CJoint) == "table" and type(CJoint.joint) == "table"
            if InPosition then
                for i = 1, 6 do
                    if type(CJoint.joint[i]) ~= "number"
                        or not (math.abs(CJoint.joint[i] - LiftingPoint.joint[i]) <= 0.1) then
                        InPosition = false
                        break
                    end
                end
            end
            if (InPosition == false) and (os.time() - StartTime > 60) then
                Alarm("Lifting safety posture timeout!", ErrorMessage.Type.PointErr)
            end
        until InPosition
        LiftingDestHeight = CLH
        if (SimulateMode == 1) then
            SimulateLiftingColumnMove(CLH)
            LogInfo("Simulate mode: moveTo_absolutePosition, %s", CLH)
            Wait(math.ceil(SimulateProcess.LiftingColumn.UsedTime))
            SimulateProcess.LiftingColumn.UsedTime = 0
        else
            local SwitchCommMode =
            {
                [LiftingType.EWELLIX] = function()
                    EWLRun(CLH)
                end,
                [LiftingType.GeMinG] = function()
                    SV660CRun(math.ceil(CLH * 10))
                end,
                [LiftingType.ZT3ILC] = function()
                    ZC01Run(CLH)
                end,
                [LiftingType.LINAK] = function()
                    LINAKRun(math.ceil(CLH * 10))
                end
            }
            local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
            if switch_mode then
                switch_mode()
                LiftingMotion(CLH)
            else
                Alarm("SwitchCommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
            end
        end
        LiftingDestHeight = -1
    else
        SyncSignal = false
        SyncMotionVel = NLDVel
    end
end
---------------------------------------------------------------
--吸盘相关接口
---------------------------------------------------------------
--吸盘控制
local function VacuumCupControll(PortCfg, State, Num)
    local DIPorts = {
        PortCfg.A,
        PortCfg.B,
        PortCfg.C,
        PortCfg.D
    }
    if (ToggleSignalFunc == true) then
        State = (State == ON) and OFF or ON
    end
    for i = 1, Num do
        IORes(PortCfg.Mode, DIPorts[i], State)
    end
end
----------------------------------------------------------------
--控制单信号
local function VacuumCupChannelControll(PortCfg, State, Num)
    local DIPorts = {
        PortCfg.A,
        PortCfg.B,
        PortCfg.C,
        PortCfg.D
    }
    if (ToggleSignalFunc == true) then
        State = (State == ON) and OFF or ON
    end
    IORes(PortCfg.Mode, DIPorts[Num], State)
end
---------------------------------------------------------------
--吸盘安全信号
local function VacuumCupSafeIO(State)
    if (SPortCfg.Enable == true or Communication.Lifting.Mode == LiftingType.EWELLIX) then
        IORes(SPortCfg.Port.Mode, SPortCfg.Port.A, State)
    end
end
---------------------------------------------------------------
--计算工具和工件的组合几何体负载质心
--输入：工具质量、工具坐标系、料箱偏移量、料箱质量、料箱高度
local function GetPayloadCenter(ToolMass, ToolCoordinate, LoadOffset, LoadMass, LoadHeight)
    local TotalMass = ToolMass + LoadMass
    if (TotalMass <= 0) then
        return { 0, 0, 0 }
    end

    return {
        (ToolMass * ToolCoordinate[1] + LoadMass * LoadOffset[1]) / TotalMass,
        (ToolMass * ToolCoordinate[2] + LoadMass * LoadOffset[2]) / TotalMass,
        (ToolMass * ToolCoordinate[3] * 0.5 + LoadMass * (LoadOffset[3] + LoadHeight * 0.5)) / TotalMass
    }
end
---------------------------------------------------------------
--吸盘初始化
local function InitVacuumCup()
    DropDete(FirstPallet, DropType.Prep)
    DropDete(SecondPallet, DropType.Prep)

    if (PalletVacuumCupFunc == VacuumCupCfg.Type.SSingle) then
        local ErrA = 0
        local ErrB = 0
        SetTool485(Communication.VacuumCup.Tcp.BaudRate, Communication.VacuumCup.Tcp.Parity,
            Communication.VacuumCup.Tcp.StopBit)
        ErrA, Communication.VacuumCup.Tcp.Socket = TCPCreate(false,
            Communication.VacuumCup.Tcp.Ip, Communication.VacuumCup.Tcp.Port) --创建TCP客户端
        ErrB = TCPStart(Communication.VacuumCup.Tcp.Socket, 5)                --建立TCP连接
        if ErrA ~= 0 or ErrB ~= 0 then
            Alarm("Initialized vacuum cup failed!", ErrorMessage.Type.IPErr)
        else
            LogInfo("Create vacuum cup tcp client success!")
        end
    else
        VacuumCupControll(VacuumCupCfg.Port, OFF, math.abs(PalletVacuumCupFunc))
        if (PalletVacuumCupFunc ~= VacuumCupCfg.Type.SSingle) then
            VacuumCupSafeIO(OFF)
        end
        if PartCfg.Enable then
            IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF)
        end
        if VacuumCupCfg.Dete.VacuumBreak.Enable == 1 then
            VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, OFF, math.abs(PalletVacuumCupFunc))
        end
    end
    local Weight = 0
    local ToolData = {}
    local CTool = {}
    Weight = ToolWeight
    if (Pallet == Left) then
        CTool = CalcTool(FirstPallet.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    else
        CTool = CalcTool(SecondPallet.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    end

    ToolData = { CTool[1], CTool[2], 0.5 * CTool[3] }
    LogInfo("[InitVacuumCup] Weight: %s!", Weight)
    LogInfo("[InitVacuumCup] Center of gravity: x = %s, y = %s, z = %s", ToolData[1], ToolData[2], ToolData[3])
    LogInfo("Initialized vacuum cup success!")
end
---------------------------------------------------------------
--打开吸盘
local function OpenVacuumCup(PalletNumber, CPoint, CIndex)
    local BoxNum = 0
    local Weight = 0
    local ToolData = {}
    local CTool = {}
    local ToolCoordinate = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    if (CPoint.Paras.ToolData == nil) then
        LogInfoTable("ToolData is ", CPoint.Paras.ToolData)
        Alarm("ToolData is wrong", ErrorMessage.Type.WorkingDataErr)
    end
    if (PalletNumber.Mode == WorkType.Pallet) then
        if (CPoint.Paras.VacuumCup == -1) then
            CTool = ToolCoordinate
        else
            CTool = CPoint.Paras.ToolData[1]
        end
    else
        if (CPoint.Paras.VacuumCup == -1 and CIndex ~= 1) then
            CTool = CPoint.Paras.ToolData[CIndex]
        else
            CTool = ToolCoordinate
        end
    end
    local SwitchVacuumCup =
    {
        [MotionType.Norm] = function()
            if (CPoint.Paras.VacuumCup == -1) then
                if (PalletNumber.Mode == WorkType.Pallet) then
                    BoxNum = math.abs(PalletVacuumCupFunc)
                    VacuumCupControll(VacuumCupCfg.Port, ON, BoxNum)
                else
                    BoxNum = math.abs(PalletVacuumCupFunc) - CIndex + 1
                    VacuumCupChannelControll(VacuumCupCfg.Port, ON, CIndex)
                end
                VacuumCupSafeIO(OFF)
            elseif (PalletVacuumCupFunc == VacuumCupCfg.Type.SSingle and CPoint.Paras.VacuumCup == 0) then
                BoxNum = 1
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOn)
            else
                BoxNum = math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1
                VacuumCupControll(VacuumCupCfg.Port, ON, BoxNum)
                VacuumCupSafeIO(OFF)
            end
            Wait(Time.Pick.In)
            Weight = BoxNum * PalletNumber.BoxProperty.BoxWeight + ToolWeight
            ToolData = GetPayloadCenter(ToolWeight, ToolCoordinate, CTool, BoxNum * PalletNumber.BoxProperty.BoxWeight,
                PalletNumber.BoxProperty.BoxHigh) --质心计算
            --ToolData = { CTool[1], CTool[2], 0.5 * (CTool[3] + PalletNumber.BoxProperty.BoxHigh) }
        end,
        [MotionType.LayerSheet] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, ON)
            elseif (PalletVacuumCupFunc == VacuumCupCfg.Type.SSingle) then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOn)
            else
                VacuumCupControll(VacuumCupCfg.Port, ON, math.abs(PalletVacuumCupFunc))
                VacuumCupSafeIO(OFF)
            end
            Wait(Time.Pick.In)
            Weight = PalletNumber.ProcessNum.LayerSheetWeight + ToolWeight
            ToolData = GetPayloadCenter(ToolWeight, ToolCoordinate, CTool, PalletNumber.ProcessNum.LayerSheetWeight,
                PalletNumber.ProcessNum.LayerSheetHeight) --质心计算
            --ToolData = { CTool[1], CTool[2], 0.5 * CTool[3] }
        end
    }

    local switch_mode = SwitchVacuumCup[CPoint.Paras.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("[OpenVacuumCup] Weight: %s!", Weight)
        LogInfo("[OpenVacuumCup] Center of gravity: x = %s, y = %s, z = %s", ToolData[1], ToolData[2], ToolData[3])
        SetPayload(Weight, ToolData) --设置负载指令，加上箱子重量
        LogInfo("Open vacuum cup success!")
        CarryBoxFlag = true --设置带箱子标志位
    else
        Alarm("OpenVacuumCup is error, please check it!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--关闭吸盘
local function CloseVacuumCup(PalletNumber, CPoint, CIndex)
    local CTool = {}
    local Weight = 0
    local ToolData = {}
    local ToolCoordinate = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    if (CPoint.Paras.ToolData == nil) then
        LogInfoTable("ToolData is ", CPoint.Paras.ToolData)
        Alarm("ToolData is wrong", ErrorMessage.Type.WorkingDataErr)
    end
    if (PalletNumber.Mode == WorkType.Pallet) then
        if (CPoint.Paras.VacuumCup == -1 and CIndex == 1) then
            CTool = CPoint.Paras.ToolData[CIndex + 1]
            ToolData = GetPayloadCenter(ToolWeight, ToolCoordinate, CTool, PalletNumber.BoxProperty.BoxWeight, PalletNumber.BoxProperty.BoxHigh)--质心计算
            --CTool[3] = CTool[3] + PalletNumber.BoxProperty.BoxHigh
            Weight = PalletNumber.BoxProperty.BoxWeight + ToolWeight
        else
            CTool = ToolCoordinate
            ToolData = (ToolWeight == 0) and { 0, 0, 0 } or { CTool[1], CTool[2], 0.5 * CTool[3] }
            Weight = ToolWeight
        end
    else
        CTool = ToolCoordinate
        ToolData = (ToolWeight == 0) and { 0, 0, 0 } or { CTool[1], CTool[2], 0.5 * CTool[3] }
        Weight = ToolWeight
    end
    --local ToolData = { CTool[1], CTool[2], 0.5 * CTool[3] }
    LogInfo("[CloseVacuumCup] Weight: %s!", Weight)
    LogInfo("[CloseVacuumCup] Center of gravity: x = %s, y = %s, z = %s", ToolData[1], ToolData[2], ToolData[3])
    SetPayload(ToolWeight, ToolData) ---设置负载为吸取箱子的负载
    local SwitchVacuumCup =
    {
        [MotionType.Norm] = function()
            if (CPoint.Paras.VacuumCup == -1) then
                if (PalletNumber.Mode == WorkType.Pallet) then
                    VacuumCupChannelControll(VacuumCupCfg.Port, OFF, CIndex)
                    VacuumCupSafeIO(ON)
                    if (VacuumCupCfg.Dete.VacuumBreak.Enable == 1) then
                        VacuumCupChannelControll(VacuumCupCfg.Dete.VacuumBreak, ON, CIndex)
                        Wait(Time.Place.In)
                        VacuumCupChannelControll(VacuumCupCfg.Dete.VacuumBreak, OFF, CIndex)
                        return
                    end
                else
                    VacuumCupControll(VacuumCupCfg.Port, OFF, math.abs(PalletVacuumCupFunc))
                    VacuumCupSafeIO(ON)
                    if (VacuumCupCfg.Dete.VacuumBreak.Enable == 1) then
                        VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, ON, math.abs(PalletVacuumCupFunc))
                        Wait(Time.Place.In)
                        VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, OFF, math.abs(PalletVacuumCupFunc))
                        return
                    end
                end
            elseif (PalletVacuumCupFunc == VacuumCupCfg.Type.SSingle and CPoint.Paras.VacuumCup == 0) then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOff)
            else
                VacuumCupControll(VacuumCupCfg.Port, OFF, math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1)
                VacuumCupSafeIO(ON)
                if (VacuumCupCfg.Dete.VacuumBreak.Enable == 1) then
                    VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, ON, math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1)
                    Wait(Time.Place.In)
                    VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, OFF, math.ceil(0.5 * CPoint.Paras.VacuumCup) + 1)
                    return
                end
            end
            Wait(Time.Place.In)
        end,
        [MotionType.LayerSheet] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF)
            elseif (PalletVacuumCupFunc == VacuumCupCfg.Type.SSingle) then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOff)
            else
                VacuumCupControll(VacuumCupCfg.Port, OFF, math.abs(PalletVacuumCupFunc))
                VacuumCupSafeIO(ON)
                if (VacuumCupCfg.Dete.VacuumBreak.Enable == 1) then
                    VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, ON, math.abs(PalletVacuumCupFunc))
                    Wait(Time.Place.In)
                    VacuumCupControll(VacuumCupCfg.Dete.VacuumBreak, OFF, math.abs(PalletVacuumCupFunc))
                    return
                end
            end
            Wait(Time.Place.In)
        end
    }

    local switch_mode = SwitchVacuumCup[CPoint.Paras.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("Close vacuum cup success!")
        CarryBoxFlag = false --设置不带箱子标志位
    else
        Alarm("CloseVacuumCup is error, please check it!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--外设初始化
---------------------------------------------------------------
local function InitPeripheral()
    if BuzzerFunction == true then
        DO(BuzzerIO, OFF)
        LogInfo("Initialized buzzer success!")
    end
    InitVacuumCup()
    InitLight()
    InitLifting()
end
---------------------------------------------------------------
--更新工作数据
---------------------------------------------------------------
--计算码垛数量
local function GetPalletIndex(PalletNumber)
    if PalletNumber.ProcessNum.BoxCount > PalletNumber.PalletNum.LayerBoxNum then
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount + 1
        end
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum +
            GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
        if SimulateMode == 1 then
            SimulateProcess.LayerNum = SimulateProcess.LayerNum + 1
            StatisticLayerRate()
        end    
    end

    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.PalletNum.LayerBoxNum - PalletNumber.ProcessNum.BoxCount
end
---------------------------------------------------------------
--计算放置箱子数量
local function CalPlaceBoxNum(PalletNumber, CPoint)
    if (PalletNumber.PalletNum.NextBoxCount <= PalletNumber.ProcessNum.TotalBoxNum) then
        PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount        --托盘已放置箱体的数量
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount + 1 --托盘下一个放置箱体的数量
        PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(PalletName, PalletNumber.Pallet)
        if PalletNumber.ProcessNum.BoxCount > PalletNumber.ProcessNum.TotalBoxNum then
            LogWarn("BoxCount is wrong!")
            PalletNumber.ProcessNum.BoxCount = PalletNumber.ProcessNum.TotalBoxNum
            PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.TotalBoxNum + 1
        end
        GetPalletIndex(PalletNumber)
        if (CPoint.Paras.VacuumCup > 0) then
            PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount +
                math.ceil(CPoint.Paras.VacuumCup * 0.5)
        end

        CommitPalletNum(PalletNumber)  --上传已有料箱层数、剩余料箱数
        PlaceCountPallet(PalletNumber) --调用放置计数程序
    end
    --码垛完成后将当前栈板号+1写入LastFinishDir，供下次初始化判断是否交替
    if (WorkingMode == ModeType.Exh) then
        WriteRobotModbus(Pallet + 1, FirstPallet.RegisterID.LastFinishDir)
    end
    --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
    if (PalletNumber.PalletNum.NextBoxCount > PalletNumber.ProcessNum.TotalBoxNum) then
        if (PalletNumber.LayerSheet.Enable == true) then
            if (PalletNumber.LayerSheet.Last == false)
                and (PalletNumber.LayerSheet.Layer[PalletNumber.Layer + 1] == 1) then
                PalletNumber.LayerSheet.Last = true
                LogInfo("Enter last layer LayerSheet motion!")
                return
            else
                PalletNumber.LayerSheet.Last = false
            end
        end
        PalletNumber.State.Done = true --将满载布尔变量置为true
        if (StateMachine ~= FSMType.DLR)
            or ((StateMachine == FSMType.DLR)
                and (FirstPallet.State.Done == true)
                and (SecondPallet.State.Done == true)) then
            PalletNumber.State.StateReady = false
            --两侧栈板均已完成：交换码垛/拆垛角色，重置状态准备下一轮循环
            if (WorkingMode == ModeType.Exh) then
                WriteRobotModbus(0, FirstPallet.RegisterID.LastFinishDir)  -- PreFinishDir=0 → 0~=0为假 → 不交换
                if (FirstPallet.Mode == WorkType.Pallet) then
                    FirstPallet.Mode = WorkType.Depallet
                    SecondPallet.Mode = WorkType.Pallet
                    WorkingSignalDir = SignalDir.Left
                    WriteRobotModbus(Left, FirstPallet.RegisterID.PalletDir)
                else
                    FirstPallet.Mode = WorkType.Pallet
                    SecondPallet.Mode = WorkType.Depallet
                    WorkingSignalDir = SignalDir.Right
                    WriteRobotModbus(Right, FirstPallet.RegisterID.PalletDir)
                end
                FirstPallet.State.SReset = true
                SecondPallet.State.SReset = true
                WriteRobotModbus(FirstPallet.Mode, FirstPallet.RegisterID.PalletMode)
                WriteRobotModbus(SecondPallet.Mode, SecondPallet.RegisterID.PalletMode)
            end
        end
        if SimulateMode == 1 then
            LogInfo(" %s pallet is full!", (Pallet == Left) and 'Left' or 'Right')
            if FirstPallet.State.Done then
                StatisticPalletRate(SimulateProcess.LeftPallet)
            end
            if SecondPallet.State.Done then
                StatisticPalletRate(SimulateProcess.RightPallet)
            end
            if PalletNumber.State.StateReady == false then
                LogInfo("NotReady!")
                SimulateProcess.LayerNum = 1      --当前操作层数
                SimulateProcess.LayerBoxIndex = 0 --当前层的箱子索引
                SimulateProcess.LayerBoxNum = 0   --首层到当前层搬运的箱子数
                SimulateProcess.PickIndex = 1     --吸取索引
            end
        end
        LogInfo("%s pallet is completed!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    end
end
---------------------------------------------------------------
--计算拆垛数量
local function GetDePalletIndex(PalletNumber)
    local LocalLayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
    local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.ProcessNum.BoxCount - TempBoxNum
    if PalletNumber.ProcessNum.BoxCount <= TempBoxNum then
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount - 1
            PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet,
                PalletNumber.PalletNum.LayerCount)
            if SimulateMode == 1 then
                StatisticLayerRate()
            end
        end
    end
end
---------------------------------------------------------------
--计算拆垛箱子数量
local function CalDePalletPlaceBoxNum(PalletNumber, CPoint)
    if (PalletNumber.PalletNum.NextBoxCount > 0) then
        PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount - 1 --托盘已放置箱体的数量
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount     --托盘下一个放置箱体的数量
        if (PalletNumber.ProcessNum.BoxCount < 0) then
            LogWarn("BoxCount is wrong!")
            PalletNumber.ProcessNum.BoxCount = 0
            PalletNumber.PalletNum.NextBoxCount = 0
        end
        GetDePalletIndex(PalletNumber)
        if (CPoint.Paras.VacuumCup > 0) then
            PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount -
                math.ceil(CPoint.Paras.VacuumCup * 0.5)
        end

        CommitPalletNum(PalletNumber)                  --上传已有料箱层数、剩余料箱数
        PlaceCountPallet(PalletNumber)                 --调用放置计数程序
    end
    --拆垛完成后将当前栈板号+1写入LastFinishDir，供下次初始化判断是否交替
    if (WorkingMode == ModeType.Exh) then
        WriteRobotModbus(Pallet + 1, FirstPallet.RegisterID.LastFinishDir)
    end
    if (PalletNumber.PalletNum.NextBoxCount <= 0) then --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
        if (PalletNumber.LayerSheet.Enable == true) then
            if (PalletNumber.LayerSheet.Last == false) and (PalletNumber.LayerSheet.Layer[1] == 1) then
                PalletNumber.LayerSheet.Last = true
                LogInfo("Enter last layer LayerSheet motion!")
                return
            else
                PalletNumber.LayerSheet.Last = false
            end
        end
        PalletNumber.State.Done = true --将满载布尔变量置为true
        if (StateMachine ~= FSMType.DLR)
            or ((StateMachine == FSMType.DLR)
                and (FirstPallet.State.Done == true)
                and (SecondPallet.State.Done == true))
        then
            PalletNumber.State.StateReady = false
        end
        if SimulateMode == 1 then
            LogInfo(" %s pallet is empty!", (Pallet == Left) and 'Left' or 'Right')
            if FirstPallet.State.Done == true then
                StatisticPalletRate(SimulateProcess.LeftPallet)
            end

            if SecondPallet.State.Done == true then
                StatisticPalletRate(SimulateProcess.RightPallet)
            end
        end
        LogInfo("%s pallet is completed!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    end
end
---------------------------------------------------------------
--更新隔板数据
local function UpdateLSData(PalletNumber, CPoint)
    if (CPoint.Paras.Mode == MotionType.LayerSheet) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.LayerSheet.PlanType == PlanType.OffLine) then
                if (PalletNumber.LayerSheet.ReLSNum <= PalletNumber.LayerSheet.ReLSSafeNum) then
                    LogWarn("Layer sheet count less than %s!", PalletNumber.LayerSheet.ReLSSafeNum)
                    ErrorMessage.Code = ErrorMessage.Type.LayerSheetSafeErr
                    CommitErrorMsg(ErrorMessage.Code)
                end
                if (PalletNumber.LayerSheet.ReLSNum <= 0) then
                    if SimulateMode == 1 then
                        PalletNumber.LayerSheet.ReLSNum = PalletNumber.ProcessNum.LayerSheetNum
                        return
                    end
                    Alarm("LayerSheet is empty!", ErrorMessage.Type.LayerSheetErr)
                    PalletNumber.LayerSheet.ReLSNum = PalletNumber.ProcessNum.LayerSheetNum
                    WriteLSNum(PalletNumber)
                end
            end
        else
            if (PalletNumber.LayerSheet.ReLSNum >= PalletNumber.ProcessNum.LayerSheetNum) then
                if SimulateMode == 1 then
                    PalletNumber.LayerSheet.ReLSNum = 0
                    return
                end
                Alarm("LayerSheet is full!", ErrorMessage.Type.LayerSheetErr)
                PalletNumber.LayerSheet.ReLSNum = 0
                WriteLSNum(PalletNumber)
            end
        end
    end
end
---------------------------------------------------------------
--更新工作数据
local function UpdateData(PalletNumber, CPoint)
    if (PalletNumber.LayerSheet.Enable == true) then
        if (PalletNumber.Pallet == Left) then
            SetVal("PalletPartPlaceA", CPoint.Paras.Mode)
        else
            SetVal("PalletPartPlaceB", CPoint.Paras.Mode)
        end
    end
    if (CPoint.Paras.Mode == MotionType.Norm) or (PalletNumber.LayerSheet.Last == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CalPlaceBoxNum(PalletNumber, CPoint)         --执行托盘码垛计数
        else
            CalDePalletPlaceBoxNum(PalletNumber, CPoint) --执行托盘拆垛计数
        end
    end
    if (CPoint.Paras.Mode == MotionType.LayerSheet and PalletNumber.LayerSheet.PlanType == PlanType.OffLine) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            PalletNumber.LayerSheet.ReLSNum = PalletNumber.LayerSheet.ReLSNum - 1
        else
            PalletNumber.LayerSheet.ReLSNum = PalletNumber.LayerSheet.ReLSNum + 1
        end
        WriteLSNum(PalletNumber)
    end
end
--------------------------------------------------------------
--安全相关接口
--------------------------------------------------------------
--进入安全模式
local function SetSafeMode(PalletNumber, CPoint, Mode)
    if (WorkingMode == ModeType.Exh or CPoint.Paras.Mode == MotionType.LayerSheet) then
        return
    end
    if (Mode == true and IsSafeMode == false) then
        local CLayer = PalletNumber.PalletNum.LayerCount
        if (WorkType.Pallet == PalletNumber.Mode) then
            if (PalletNumber.ProcessNum.BoxCount >= PalletNumber.PalletNum.LayerBoxNum) then
                if (PalletNumber.PalletNum.LayerBoxNum > 0) then
                    CLayer = CLayer + 1
                end
            end
        else
            local LocalLayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
            local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
            if (PalletNumber.ProcessNum.BoxCount <= TempBoxNum) then
                if (PalletNumber.PalletNum.LayerBoxNum > 0) then
                    CLayer = CLayer - 1
                end
            end
        end

        if (PalletNumber.CollisionLevel[CLayer] == 1) then
            IsSafeMode = true
            LogInfo("Enter safe mode")
            Wait(500)
            SetCollisionLevel(SafeType.LEVEL_1)
        end
    else
        if (IsSafeMode == true) then
            IsSafeMode = false
            LogInfo("Exit safe mode")
            Wait(500)
            RecoverCollisionLevel()
        end
    end
end
---------------------------------------------------------------
--运动相关接口
---------------------------------------------------------------
--设置运动模式
local function SetMotionMode(Mode)
    if (OptimalTrajectoryFunc == true) then
        local Paras = { usingTimeOptimal = Mode, normalAccLimit = 1500 } --设置功能开关和转角加速度
        CP(0)
        Wait(8)
        SetAdvancedFunction(Paras) --设置高速运动功能, 更改配置需保证无过渡段处理，CP(0)
        LogInfo("%s optimal trajectory function", (Mode == true) and "Open" or "Close")
        Wait(50)
    end
end
---------------------------------------------------------------
--获取点位模式
local function GetPointMode(CMode, CType)
    if CMode == MotionType.LayerSheet then
        ErrorMessage.PointInfo.Type = CType.LayerSheet
    else
        ErrorMessage.PointInfo.Type = CType.Norm
    end
end
---------------------------------------------------------------
--获取点位类型
local function GetPointType(CPoint)
    if CPoint.Paras.ErrIndex <= PointType.Trans.Index.E then
        GetPointMode(CPoint.Paras.Mode, PointType.Trans.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex == PointType.Pick.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.Pick.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex == PointType.PickOffset.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.PickOffset.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.Place.Index.A
        and CPoint.Paras.ErrIndex <= PointType.Place.Index.D then
        GetPointMode(CPoint.Paras.Mode, PointType.Place.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.PlaceOffset.Index.A
        and CPoint.Paras.ErrIndex <= PointType.PlaceOffset.Index.D then
        GetPointMode(CPoint.Paras.Mode, PointType.PlaceOffset.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.Insert.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.Insert.Cfg)
        return
    end
end
---------------------------------------------------------------
--获取点位信息
local function GetPointInfo(PalletNumber, CPoint)
    local LayerNum = 0
    GetPointType(CPoint)
    if PalletNumber.Mode == WorkType.Pallet then
        if (PalletNumber.ProcessNum.BoxCount >= PalletNumber.PalletNum.LayerBoxNum)
            and (PalletNumber.PalletNum.LayerBoxNum > 0) and (CPoint.Paras.Mode == MotionType.Norm) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount + 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    else
        local LocalLayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
        local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if (PalletNumber.ProcessNum.BoxCount <= TempBoxNum)
            and (TempBoxNum > 0) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount - 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    end
    if ErrorMessage.PointInfo.Type == 5 or ErrorMessage.PointInfo.Type == 6 then
        ErrorMessage.PointInfo.Index = PalletNumber.PalletNum.NextBoxCount
    else
        for i = 1, (ErrorMessage.PointInfo.Layer - 1) do
            LayerNum = LayerNum + GetOddBoxCnt(PalletName, PalletNumber.Pallet, i)
        end
        ErrorMessage.PointInfo.Index = PalletNumber.PalletNum.NextBoxCount - LayerNum
    end
    ErrorMessage.PointInfo.PalletNum = PalletNumber.Pallet
    LogError("Point unreachable - Pallet: %d, Type: %d, Layer: %d, Index: %d",
        ErrorMessage.PointInfo.PalletNum, ErrorMessage.PointInfo.Type,
        ErrorMessage.PointInfo.Layer, ErrorMessage.PointInfo.Index)
    Alarm("Point Unreachable!", ErrorMessage.Type.PointErr)
end
---------------------------------------------------------------
--缠膜运动
local function FilmMotion()
    local DestPose = {}
    local JointAngle = {}
    if FilmFunction == true then
        if (DI(FilmDI) == ON)
            and (FilmDone == true)
            and ((CheckDORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == OFF)
            and (CheckDORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B) == OFF) and (ToggleSignalFunc == false) 
            or ((CheckDORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == ON)
            and (CheckDORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B) == ON) and (ToggleSignalFunc == true) )) then
            FilmDone = false
            JointAngle = DeepCopy(LiftingPoint)
            MovJ(JointAngle, { v = NLDVel, cp = 100 })
            DestPose = GetPose()
            if PrePoseHeight > DestPose.pose[3] then
                AdjustLiftingHeight(math.floor(PrePoseHeight - DestPose.pose[3]))
            end

            if PrePallet == 1 then
                JointAngle.joint[1] = 180
            elseif PrePallet == 2 then
                JointAngle.joint[1] = 0
            else
                Alarm("Pallet is wrong!", ErrorMessage.Type.WorkingDataErr)
            end
            MovJ(JointAngle, { v = NLDVel, cp = 100 })
            LogInfo("Enter FilmMotion!")
        end
        if (DI(FilmDI) == OFF) and (FilmDone == false) then
            MovJ(LiftingPoint, { v = NLDVel, cp = 100 })
            DestPose = GetPose()
            if PrePoseHeight > DestPose.pose[3] then
                AdjustLiftingHeight(math.floor(PrePoseHeight - DestPose.pose[3]))
            end
            FilmDone = true
            LogInfo("Exit FilmMotion!")
        end
    end
end
---------------------------------------------------------------
--隔板安全点运动
local function LSSafeMotion(SafePoint, CDir, LH, Vel)
    local PointNum = 1
    local SrcPoint = {}
    local Step = 1
    local CSafePoint = { joint = {} }
    --隔板过渡区域
    SetVal("PalletMotionArea", MotionArea.LS_TRANS)
    SetVal("PalletTransDir", CDir)
    if (CDir == Dir.Forward) then
        PointNum = SafePoint.Forward.Num
        SrcPoint = DeepCopy(SafePoint.Forward.joint)
    else
        PointNum = SafePoint.Backward.Num
        SrcPoint = DeepCopy(SafePoint.Backward.joint)
    end
    local Index = 1
    if (ResetMotionFlag) then
        Index = GetVal("PalletTransStep")
        if (CDir == Dir.Forward) then   --正向倒序回去，逆向不变
            Step = -1       
            PointNum = 1
            Index = Index - 1
        end 
    end
    for i = Index, PointNum, Step do
        SetVal("PalletTransStep", i)
        CSafePoint.joint = DeepCopy(SrcPoint[i])
        if (LH > 0) then
            local CPoint = RelPointUser(CSafePoint, { 0, 0, -LH, 0, 0, 0 })
            MovL(CPoint, { v = Vel, cp = 100 })     --运动到隔板安全点
        else
            MovL(CSafePoint, { v = Vel, cp = 100 }) --运动到隔板安全点
        end
    end
    SetVal("PalletMotionArea", MotionArea.NORMAL)
end
---------------------------------------------------------------
--过渡点运动
local function TransMotion(CPoint, CDir, Vel)
    local SD = 1
    local ED = CPoint.Paras.TransNum
    --栈板过渡区域
    SetVal("PalletMotionArea", MotionArea.PALLET_TRANS)
    SetVal("PalletTransDir", CDir)
    if (CDir == Dir.Backward) then
        SD = CPoint.Paras.TransNum
        ED = 1
    end
    if (ResetMotionFlag) then
        SD = GetVal("PalletTransStep")
        if (CDir == Dir.Forward) then   --正向的话变为逆向，逆向的话不变
            CDir = -CDir
            ED = 1
            SD = SD - 1
        end
    end
    for i = SD, ED, CDir do
        SetVal("PalletTransStep", i)  -- 记录当前过渡点索引(用于中断恢复)
        if (type(CPoint.MotionPoint[i]) == "table") then
            if (PalletObstacleFunc == 1) then
                MovL(CPoint.MotionPoint[i], { v = Vel, cp = 100 }) --运动到层过渡点
            else
                if (CPoint.Paras.Times > 1 and LabelFunction == true) then
                    if (CDir == Dir.Backward) then
                        CPoint.MotionPoint[i].joint[6] = CPoint.Paras.RePlanData[i]
                    end
                    MovJ(CPoint.MotionPoint[i], { v = Vel, cp = 100 }) --运动到层过渡点
                else
                    MovL(CPoint.MotionPoint[i], { v = Vel, cp = 100 }) --运动到层过渡点
                end
            end
        end
    end
    SetVal("PalletMotionArea", MotionArea.NORMAL)
end
---------------------------------------------------------------
--升降柱同步运动
local function SyncMotion(CLH)
    if (SimulateMode == 1) then
        SyncSignal = false
        if SimulateProcess.LiftingColumn.UsedTime ~= 0 then
            -- if (CLH < 1) then
            Wait(math.ceil(SimulateProcess.LiftingColumn.UsedTime))
            SimulateProcess.LiftingColumn.UsedTime = 0
            -- else
            --     Wait(100)
            -- end
        end
        return
    end
    if (SyncSignal == true) then
        SyncSignal = false
        LiftingMotion(CLH)
    end
end
---------------------------------------------------------------
--待机位置运动
local function StandbyMotion(PalletNumber, CPoint)
    if (PalletNumber.State.StateReady == false) and (LiftingHeight > 1) then
        MovJ(CPoint.Paras.Standby, { v = NLDVel, cp = 100 })
        AdjustLiftingHeight(Home)
        SyncMotion(Home)
    elseif (CPoint.Paras.Mode == MotionType.LayerSheet) then
        local Standby = { pose = {} }
        Standby.pose = DeepCopy(CPoint.Paras.Standby.pose)
        Standby.pose[3] = Standby.pose[3] - CPoint.Paras.LH
        local ErrID = 0
        local CJoint = { joint = {} }
        ErrID, CJoint = InverseKin(Standby, { jointNear = NearJoint, useJointNear = true })
        if (ErrID ~= 0) then
            LogInfoTable("Standby:", Standby)
            Alarm("Point Unreachable!", ErrorMessage.Type.PointErr)
        end
        MovJ(CJoint, { v = NLDVel, cp = 100 })
    else
        MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = NLDVel, cp = 100 })
    end
    IsStandby = true
end
---------------------------------------------------------------
--复位轨迹运动
local function ResetPathMotion(CPallet)
    local CopyPoint = { pose = {}, joint = {}, mode = {} }
    local CPoint = { joint = {} }
    if (CPallet.ResetPathFunc == true) then
        LogInfo("User teach point go home")
        CopyPoint.joint = DeepCopy(CPallet.TeachPoint.HomeTransPoint.joint)
        for i = 1, 3 do
            if type(CopyPoint.joint[i]) == "table" then
                local IsValid = true
                for j = 1, 6 do
                    if CopyPoint.joint[i][j] == nil then
                        IsValid = false
                        break
                    end
                end
                if IsValid then
                    CPoint.joint = DeepCopy(CopyPoint.joint[i])
                    MovL(CPoint, { v = NLDVel * 0.25, cp = 100 })
                end
            end
        end
    -- 没有上位机配置复位过渡点 执行以下复位逻辑
    elseif (CPallet.ResetPathFunc == false) then
        LogInfo("Auto go home")
        --1. 普通区域，往上50mm，然后回到Home位
        --2. 过渡点区域，去向，逆序执行已经走过的过渡点，然后回到Home位
        --回向，把剩余的过渡点走完，然后回到Home位
        ResetMotionFlag = true
        local Area = GetVal("PalletMotionArea")
        if (Area == MotionArea.NORMAL) then
            local CPose = GetPose()
            CPose.pose[3] = CPose.pose[3] + 50
            MovL(CPose, { v = NLDVel * 0.25, cp = 100 })
            ResetMotionFlag = false
        elseif (Area == MotionArea.LS_TRANS) then
            local CDir = GetVal("PalletTransDir")
            local CPoint = GetVal("PalletCurPoints")
            LSSafeMotion(CPallet.LayerSheet.SafePoint, CDir, CPoint.Paras.LH, NLDVel * 0.25)
            ResetMotionFlag = false
        elseif (Area == MotionArea.PALLET_TRANS) then
            local CDir = GetVal("PalletTransDir")
            local CPoint = GetVal("PalletCurPoints")
            TransMotion(CPoint, CDir, NLDVel * 0.25)
            ResetMotionFlag = false
        end
    end
    MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
end
---------------------------------------------------------------
--回HOME位
local function InitRobot()
    --HomePointPose = { pose = { 175.6, -874.8, 918.7, 180, 0, 180 } }
    --HomePoint = { joint = { 90, 0, 90, 0, -90, 0 } } --安全点
    local CPallet = nil

    --先判断当前工作的托盘是左托盘还是右托盘
    if (GetVal("CurWorkDir") == CurWorkDir.Left) then
        CPallet = FirstPallet   --当前工作在左栈板
    elseif (GetVal("CurWorkDir") == CurWorkDir.Right) then
        CPallet = SecondPallet  --当前工作在右栈板
    end

    local CJoints = GetAngle()
    --J1 80-100 直接回
    if (CJoints.joint[1] >= 80 and CJoints.joint[1] <= 100) then
        MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
    elseif (CJoints.joint[1] > 100 and CJoints.joint[1] <= 260) then
        if (CPallet ~= nil and CPallet == FirstPallet) then
            ResetPathMotion(CPallet)
        else
            MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
        end
    elseif (CJoints.joint[1] >= -80 and CJoints.joint[1] < 80) then
        if (CPallet ~= nil and CPallet == SecondPallet) then
            ResetPathMotion(CPallet)
        else
            MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
        end
    elseif (CJoints.joint[1] > 260 or CJoints.joint[1] < -80) then
        Alarm("Robot go home error!", ErrorMessage.Type.RobotGoHomeErr)
    end
    LogInfo("Robot go home success!")
end
---------------------------------------------------------------
--任务设置模式任务完成，机器人停止
local function TaskModeDone()
    if Capacity.TaskDone == 0 then
        return    
    else 
        MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
        Pallet = Idle
        StateMachine = FSMType.IDLE
        SignalReady = false
        MotionDone = true
        LogInfo("TaskMode target reached, production stopped.")
        if (GetVal("ScriptState") ~= nil) then
            SetVal("ScriptState", false)--脚本运行状态
        end
        Halt()
    end
end
---------------------------------------------------------------
--判断是否需要在当前层结束后手动放置隔板并暂停
local function CheckManualLaysheetPause(PalletNumber)
    --判断当前层是否需要手动放置隔板
    if (PalletNumber.LayerSheet.PlaceLayerSheetType ~= 1) then
        return
    end
    --判断当前托盘是否为码垛模式
    if (PalletNumber.Mode ~= WorkType.Pallet) then
        return
    end
    --判断当前层是否已放置完箱子
    if (PalletNumber.ProcessNum.BoxCount ~= PalletNumber.PalletNum.LayerBoxNum) and PalletNumber.ProcessNum.BoxCount ~= 0 then
        return
    end
    --判断当前托盘是否有隔板层
    if (PalletNumber.ProcessNum.HandLayerSheetLayers == nil) then
        return
    end
    --判断当前层是否为手动放置隔板层
    local CompletedLayer = 0
    if PalletNumber.PalletNum.LayerCount==1 and PalletNumber.ProcessNum.BoxCount == 0 then
        CompletedLayer = 0
    else
        CompletedLayer = PalletNumber.PalletNum.LayerCount
    end
    local Flags = PalletNumber.ProcessNum.HandLayerSheetLayers
    -- 检索当前层是否为手动放置隔板层，如果是则暂停
    if Flags[CompletedLayer + 1] == 1 then
        -- 仿真模式下底部隔板（第0层且当前箱数为0）不停止、不发布 scriptPause
        if (SimulateMode == 1 and CompletedLayer == 0 and PalletNumber.ProcessNum.BoxCount == 0) then
            return
        else
            LogInfo("%s manual layersheet pause at layer %s", (PalletNumber.Pallet == Left) and "Left" or "Right", CompletedLayer)
            if (PalletLiftingFunction == true) then
                AdjustLiftingHeight(Home)
            end
            MovJ(HomePoint, { v = NLDVel * 0.25, cp = 100 })
            if SimulateMode == 1 then
                -- 先通知前端，再 Pause（与 debugger suspend 一致，可 Continue/Run）
                local ActionStr = "[" .. CompletedLayer .. "," .. PalletNumber.Pallet .. "]"
                mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id .. ':scriptPause', ActionStr, 0, false)
                Pause()
                return
            else
                PalletNumber.LayerSheet.PlaceLayerSheetPause = 1
                WriteRobotModbus(PalletNumber.LayerSheet.PlaceLayerSheetPause, PalletNumber.RegisterID.LayerSheetPause)
                Pause() --手动放置隔板层，暂停
                PalletNumber.LayerSheet.PlaceLayerSheetPause = 0
                WriteRobotModbus(PalletNumber.LayerSheet.PlaceLayerSheetPause, PalletNumber.RegisterID.LayerSheetPause)
                return
            end
        end
    end
end
---------------------------------------------------------------
--MotionPoint[index]:
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料前偏移点（自动生成），20~23：放料后偏移点（自动生成）
---------------------------------------------------------------
--执行点位运动
local function PTPMotion(PalletNumber, CPoint)
    local CPose = { pose = {} }
    --记录当前码垛点位信息
    SetVal("PalletCurPoints", CPoint)
    --记录当前工作方向
    SetVal("CurWorkDir", PalletNumber.Pallet == Right and CurWorkDir.Right or CurWorkDir.Left)
    --码垛运动
    if (PalletNumber.Mode == WorkType.Pallet) then
        Wait(Time.Pick.Pre)
        if (CPoint.Paras.Mode == MotionType.LayerSheet) then
            if (SingleMotion == false) then
                SingleMotion = true
            end
            -- 隔板抓取阶段
            local CLSPick = DeepCopy(PalletNumber.LayerSheet.PickPose)
            local NLDLSVel = MotionParas.Backward.Pick.LSVel
            --MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = SyncMotionVel, cp = 100 })
            NearJoint = GetAngle()
            --隔板安全点运动 不带料
            LSSafeMotion(PalletNumber.LayerSheet.SafePoint, Dir.Backward, CPoint.Paras.LH, NLDLSVel)
            --升降柱同步运动
            SyncMotion(CPoint.Paras.LH)
            CLSPick.pose[3] = CLSPick.pose[3] - CPoint.Paras.LH
            CLSPick = GetAddUserPos(0, PalletNumber.Coordinate.LayerSheetUserNum, CLSPick)
            CLSPick.pose[3] = CLSPick.pose[3] +
                PalletNumber.ProcessNum.LayerSheetHeight * PalletNumber.LayerSheet.ReLSNum
            CLSPick = GetAddUserPos(PalletNumber.Coordinate.LayerSheetUserNum, 0, CLSPick)
            if (PalletNumber.LayerSheet.PlanType == PlanType.OffLine) then
                MovL(CLSPick, { v = NLDLSVel, cp = 100 }) --运动到抓取点
            else
                local IOPort = PalletNumber.LayerSheet.SafePortA
                MovL(CLSPick, { v = NLDLSVel, cp = 100, stopcond = GetIOString(IOPort, ON) }) --运动到抓取点
            end
        else
            if ((SingleMotion == false) or (SyncSignal == true)
                    or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet)) then
                SingleMotion = true
                MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = SyncMotionVel * 0.8, cp = 100 }) --运动到取料上方点
                SyncMotion(CPoint.Paras.LH)
            end
            MovL(CPoint.MotionPoint[PointType.Pick.Index.A], { v = NLDVel, cp = 100 }) --运动到取料点
        end
        OpenVacuumCup(PalletNumber, CPoint)
        if SimulateMode == 1 then
            UpdatePickBoxState(PalletNumber, CPoint)
        end
        if (CPoint.Paras.Mode == MotionType.LayerSheet) then
            local LDLSVel = MotionParas.Forward.Pick.LSVel
            LSSafeMotion(PalletNumber.LayerSheet.SafePoint, Dir.Forward, CPoint.Paras.LH, LDLSVel)
        else
            MovL(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = LDVel, cp = 100 }) --回取料上方点
        end

        Wait(Time.Pick.Post)
        --过渡点运动 带料
        TransMotion(CPoint, Dir.Forward, LDVel)
        --放料运动
        for i = 1, CPoint.Paras.Times do
            if CPoint.Paras.Offset[i] == 1 then
                if (CPoint.Paras.Times > 1 and LabelFunction == true) then
                    MovJ(CPoint.MotionPoint[PointType.Insert.Index.A + i - 1], { v = LDVel, cp = 100 }) --运动到放置过渡点
                else
                    MovL(CPoint.MotionPoint[PointType.Insert.Index.A + i - 1], { v = LDVel, cp = 100 }) --运动到放置过渡点
                end
                SetSafeMode(PalletNumber, CPoint, true)
                MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = LDPlaceVel, cp = 100 }) --运动到放置点正上方
            else
                if (CPoint.Paras.Times > 1 and LabelFunction == true) then
                    MovJ(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = LDVel, cp = 100 }) --运动到放置点正上方
                else
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = LDVel, cp = 100 }) --运动到放置点正上方
                end
                SetSafeMode(PalletNumber, CPoint, true)
            end
            MovL(CPoint.MotionPoint[PointType.Place.Index.A + i - 1], { v = LDPlaceVel, cp = 100 })
            CloseVacuumCup(PalletNumber, CPoint, i)
            if SimulateMode == 1 then
                UpdatePlaceBoxState(PalletNumber, CPoint)
            end
            UpdateData(PalletNumber, CPoint)
            if CPoint.Paras.LeaveOffset[i] == 1 then
                if (CPoint.Paras.Times > 1 and i == 1) then
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A], { v = LDPlaceVel, cp = 100 })     --运动到放置点正上方
                    PalletReleaseDete(CPoint, i)
                    MovL(CPoint.MotionPoint[PointType.LeaveInsert.Index.A], { v = LDPlaceVel, cp = 100 })     --运动到放置过渡点
                else
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = NLDVel, cp = 100 }) --运动到放置点正上方
                    PalletReleaseDete(CPoint, i)
                    MovL(CPoint.MotionPoint[PointType.LeaveInsert.Index.A + i - 1], { v = NLDVel, cp = 100 }) --运动到放置过渡点
                end
            else
                if (CPoint.Paras.Times > 1 and i == 1) then
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A], { v = LDPlaceVel, cp = 100 })     --运动到放置点正上方
                else
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = NLDVel, cp = 100 }) --运动到放置点正上方
                end
                PalletReleaseDete(CPoint, i)
            end
        end
        SetSafeMode(PalletNumber, CPoint, false)
        TransMotion(CPoint, Dir.Backward, NLDVel)
        CPose = GetPose()
        StandbyMotion(PalletNumber, CPoint)
    else
        if (SingleMotion == false) or (SyncSignal == true)
            or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet) then
            --SyncSignal为false时直接置SingleMotion=true，跳过待机点运动
            if ((SingleMotion == false) or (WorkingMode == ModeType.Exh and SyncSignal == false)) then
                SingleMotion = true
            else
                local Standby = { pose = {} }
                Standby.pose = DeepCopy(CPoint.Paras.Standby.pose)
                Standby.pose[3] = Standby.pose[3] - CPoint.Paras.LH
                MovJ(Standby, { v = SyncMotionVel * 0.8, cp = 100 }) --待机点运动
            end
            SyncMotion(CPoint.Paras.LH)
        end
        TransMotion(CPoint, Dir.Forward, NLDVel)
        local CVal = NLDVel
        for i = CPoint.Paras.Times, 1, -1 do
            CVal = (i == CPoint.Paras.Times) and NLDVel or LDVel
            if (CPoint.Paras.Offset[i] == 1) then
                if (CPoint.Paras.Times > 1 and LabelFunction == true) then
                    MovJ(CPoint.MotionPoint[PointType.Insert.Index.A + i - 1], { v = CVal, cp = 100 }) --运动到放置过渡点
                else
                    MovL(CPoint.MotionPoint[PointType.Insert.Index.A + i - 1], { v = CVal, cp = 100 }) --运动到放置过渡点
                end
                SetSafeMode(PalletNumber, CPoint, true)
                MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = CVal, cp = 100 }) --运动到放置点正上方
            else
                if (CPoint.Paras.Times > 1 and LabelFunction == true) then
                    MovJ(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = CVal, cp = 100 }) --运动到放置点正上方
                else
                    MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = CVal, cp = 100 }) --运动到放置点正上方
                end
                SetSafeMode(PalletNumber, CPoint, true)
            end
            MovL(CPoint.MotionPoint[PointType.Place.Index.A + i - 1], { v = CVal, cp = 100 })
            OpenVacuumCup(PalletNumber, CPoint, i)
            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end
            UpdateData(PalletNumber, CPoint)
            MovL(CPoint.MotionPoint[PointType.PlaceOffset.Index.A + i - 1], { v = LDVel, cp = 100 })     --运动到放置点正上方
            if (CPoint.Paras.LeaveOffset[i] == 1) then
                MovL(CPoint.MotionPoint[PointType.LeaveInsert.Index.A + i - 1], { v = LDVel, cp = 100 }) --运动到放置过渡点
            end
        end
        SetSafeMode(PalletNumber, CPoint, false)
        TransMotion(CPoint, Dir.Backward, LDVel)
        CPose = GetPose()
        if (CPoint.Paras.Mode == MotionType.LayerSheet) then
            local LDLSVel = MotionParas.Backward.Pick.LSVel
            LSSafeMotion(PalletNumber.LayerSheet.SafePoint, Dir.Backward, CPoint.Paras.LH, LDLSVel)
            local CLSPick = DeepCopy(PalletNumber.LayerSheet.PickPose)
            CLSPick.pose[3] = CLSPick.pose[3] - CPoint.Paras.LH +
                PalletNumber.ProcessNum.LayerSheetHeight * PalletNumber.LayerSheet.ReLSNum
            MovL(CLSPick, { v = LDVel, cp = 100 }) --运动到放料点
        else
            MovL(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = LDVel, cp = 100 })
            MovL(CPoint.MotionPoint[PointType.Pick.Index.A], { v = LDVel, cp = 100 }) --运动到放料点
        end
        CloseVacuumCup(PalletNumber, CPoint)
        if SimulateMode == 1 then
            UpdatePlaceBoxState(PalletNumber, CPoint)
        end
        if (CPoint.Paras.Mode == MotionType.LayerSheet) then
            local NLDLSVel = MotionParas.Forward.Pick.LSVel
            LSSafeMotion(PalletNumber.LayerSheet.SafePoint, Dir.Forward, CPoint.Paras.LH, NLDLSVel)
            NearJoint = GetAngle()
        end
        DepalletReleaseDete(CPoint)
        StandbyMotion(PalletNumber, CPoint)
    end
    UpdateLSData(PalletNumber, CPoint)
    PrePallet = PalletNumber.Pallet
    PrePoseHeight = CPose.pose[3] + CPoint.Paras.LH
end
--------------------------------------------------------------
--获取放料/取料段路径点位
local function GetPlacePath(CPointList, CPoint, CDir, Index)
    local CIndex =
    {
        PointType.Place.Index.A + Index - 1,
        PointType.PlaceOffset.Index.A + Index - 1,
        PointType.Insert.Index.A + Index - 1
    }
    local CLIndex =
    {
        PointType.Place.Index.A + Index - 1,
        PointType.PlaceOffset.Index.A + Index - 1,
        PointType.LeaveInsert.Index.A + Index - 1
    }

    local SPointNum = CheckTableNum(CPointList)
    if (CDir == Dir.Forward) then
        local CPointNum = (CPoint.Paras.LeaveOffset[1] == 1) and 3 or 2
        for i = 1, CPointNum do
            CPointList[SPointNum + i] = CPoint.MotionPoint[CLIndex[i]]
        end
    else
        local CPointNum = (CPoint.Paras.Offset[1] == 1) and 3 or 2
        for i = 1, CPointNum do
            CPointList[SPointNum + i] = CPoint.MotionPoint[CIndex[CPointNum - i + 1]]
        end
    end

    return CPointList
end
--------------------------------------------------------------
--获取全局规划运动路径点位
local function GetPath(PalletNumber, CPoint, CDir, Time)
    local PathList = {}
    local PointNum = 0

    if (CDir == Dir.Forward) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (Time == 1) then
                PathList[1] = CPoint.MotionPoint[PointType.Pick.Index.A]
                PathList[2] = CPoint.MotionPoint[PointType.PickOffset.Index.A]
                for i = 1, CPoint.Paras.TransNum do
                    PathList[i + 2] = CPoint.MotionPoint[i]
                end
            else
                PathList = GetPlacePath(PathList, CPoint, Dir.Forward, Time - 1)
            end
        else
            if (Time == CPoint.Paras.Times) then
                if (SingleMotion == false) then
                    SingleMotion = true
                    PathList[1] = HomePoint
                    PointNum = 1
                    LogInfo("Start position is home point")
                else
                    if (IsStandby == true) then
                        IsStandby = false
                        PathList[1] = CPoint.MotionPoint[PointType.PickOffset.Index.A]
                        PointNum = 1
                        LogInfo("Start position is standby point")
                    else
                        PathList[1] = CPoint.MotionPoint[PointType.Pick.Index.A]
                        PathList[2] = CPoint.MotionPoint[PointType.PickOffset.Index.A]
                        PointNum = 2
                        LogInfo("Start position is pick point")
                    end
                end

                for i = 1, CPoint.Paras.TransNum do
                    PathList[i + PointNum] = CPoint.MotionPoint[i]
                end
            else
                PathList = GetPlacePath(PathList, CPoint, Dir.Forward, Time + 1)
            end
        end
        PathList = GetPlacePath(PathList, CPoint, Dir.Backward, Time)
        PointNum = CheckTableNum(PathList)
        for i = 1, PointNum do
            PathList[i] = PositiveKin(PathList[i])
        end
    else
        PathList = GetPlacePath(PathList, CPoint, Dir.Forward, Time)
        PointNum = CheckTableNum(PathList)

        for i = 1, CPoint.Paras.TransNum do
            PathList[i + PointNum] = CPoint.MotionPoint[CPoint.Paras.TransNum - i + 1]
        end
        PointNum = CheckTableNum(PathList)

        if (PalletNumber.State.StateReady == false) and (LiftingHeight > 1) then
            PathList[1 + PointNum] = CPoint.Paras.Standby
        else
            PathList[1 + PointNum] = CPoint.MotionPoint[PointType.PickOffset.Index.A]
            local TaskDone = PalletNumber.State.Done == true
            if StateMachine == FSMType.SLR or StateMachine == FSMType.DLR then
                TaskDone = FirstPallet.State.Done == true and SecondPallet.State.Done == true
            end
            if IsStandby == false and SoftStopRequested == false and TaskDone == false then
                PathList[2 + PointNum] = CPoint.MotionPoint[PointType.Pick.Index.A]
                LogInfo("Execute the full path")
            end
            PointNum = CheckTableNum(PathList)
        end

        for i = 1, PointNum do
            PathList[i] = PositiveKin(PathList[i])
        end
    end

    LogInfo("%s path length: %s ", (Pallet == Left) and "Left" or "Right", CheckTableNum(PathList))
    LogDebugTable("PathList: ", PathList)

    return PathList
end
--------------------------------------------------------------
--预处理信号
local function PreDealSignal(PalletNumber, CPoint, IsPreDeal, State)
    local CState = false

    if (StateMachine ~= FSMType.DLR) then
        CState = GetDeteMode(PalletNumber, IsPreDeal, State)
        if (CState == true) then
            local TQueue = (PalletNumber.Pallet == Left) and FQueue or SQueue

            if not TQueue:IsEmpty() then
                local CQueue = TQueue:Peek()
                if (CQueue.Paras.LH ~= CPoint.Paras.LH) then
                    IsStandby = true
                    LogInfo("Go to Standby position")
                end
            end
        else
            IsStandby = true
            LogInfo("Go to Standby position")
        end
    else
        local CSignalState = false
        if (PalletNumber.Pallet == Left) then
            CSignalState = GetDeteMode(SecondPallet, IsPreDeal, State)
        else
            CSignalState = GetDeteMode(FirstPallet, IsPreDeal, State)
        end
        CState = (CSignalState == true) or (GetDeteMode(PalletNumber, IsPreDeal, State) == false)
        if (CState == true) then
            local TQueue = (PalletNumber.Pallet == Left) and SQueue or FQueue

            if not TQueue:IsEmpty() then
                IsStandby = true
                LogInfo("Go to Standby position")
            end
        end
    end
end
---------------------------------------------------------------
--执行点位运动
local function CPMotion(PalletNumber, CPoint)
    local CPose = { pose = {} }
    local PoseList = {}
    --记录当前码垛点位信息
    SetVal("PalletCurPoints", CPoint)
    --记录当前工作方向
    SetVal("CurWorkDir", PalletNumber.Pallet == Right and CurWorkDir.Right or CurWorkDir.Left)
    if (PalletNumber.Mode == WorkType.Pallet) then
        Wait(Time.Pick.Pre)
        if ((SingleMotion == false) or (SyncSignal == true)
                or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet)) then
            SingleMotion = true
            MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = SyncMotionVel * 0.8, cp = 100 })
            SyncMotion(CPoint.Paras.LH)
        end
        MovL(CPoint.MotionPoint[PointType.Pick.Index.A], { v = NLDVel, cp = 0 }) --运动到抓取点
        OpenVacuumCup(PalletNumber, CPoint)
        if SimulateMode == 1 then
            UpdatePickBoxState(PalletNumber, CPoint)
        end
        SetMotionMode(true)
        for i = 1, CPoint.Paras.Times do
            PoseList = GetPath(PalletNumber, CPoint, Dir.Forward, i)
            PMovS(PoseList, { v = LDVel })
            CloseVacuumCup(PalletNumber, CPoint, i)
            if SimulateMode == 1 then
                UpdatePlaceBoxState(PalletNumber, CPoint)
            end
            UpdateData(PalletNumber, CPoint)
        end
        IsStandby = false
        PreDealSignal(PalletNumber, CPoint, true, ON)
        PoseList = GetPath(PalletNumber, CPoint, Dir.Backward, CPoint.Paras.Times)
        PMovS(PoseList, { v = NLDVel })
        SetMotionMode(false)
    else
        if (SingleMotion == false) or (SyncSignal == true)
            or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet) then
            if (SingleMotion == true) then
                MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = SyncMotionVel * 0.8, cp = 0 })
                IsStandby = true
            end
            SyncMotion(CPoint.Paras.LH)
        end
        SetMotionMode(true)
        for i = CPoint.Paras.Times, 1, -1 do
            PoseList = GetPath(PalletNumber, CPoint, Dir.Forward, i)
            PMovS(PoseList, { v = NLDVel })
            OpenVacuumCup(PalletNumber, CPoint, i)
            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end
            UpdateData(PalletNumber, CPoint)
        end

        PoseList = GetPath(PalletNumber, CPoint, Dir.Backward, 1)
        PMovS(PoseList, { v = LDVel })
        CloseVacuumCup(PalletNumber, CPoint)
        if SimulateMode == 1 then
            UpdatePlaceBoxState(PalletNumber, CPoint)
        end
        SetMotionMode(false)
        PreDealSignal(PalletNumber, CPoint, true, OFF)
        if (IsStandby == true) then
            MovJ(CPoint.MotionPoint[PointType.PickOffset.Index.A], { v = NLDVel, cp = 100 })
        end
    end

    if (PalletNumber.State.StateReady == false) and (LiftingHeight > 1) then
        AdjustLiftingHeight(Home)
        SyncMotion(Home)
    end
    CPose = GetPose()
    PrePallet = PalletNumber.Pallet
    PrePoseHeight = CPose.pose[3] + CPoint.Paras.LH
end
---------------------------------------------------------------
--预处理运动主流程
local function PreDealMotion(PalletNumber, CQueue)
    local CPoint = CQueue:Pop()
    if (CPoint == nil) then
        Alarm("PreMotion Point Error!", ErrorMessage.Type.PointErr)
    end
    if (CPoint.Paras.ErrIndex > 0) then
        GetPointInfo(PalletNumber, CPoint)
    end 
    if ( PalletNumber.PalletNum.LayerCount==1 and PalletNumber.ProcessNum.BoxCount==0) then
        CheckManualLaysheetPause(PalletNumber) --判断第0层手动放置隔板，机器人停止
    end
    if (PalletNumber.LayerSheet.Enable == true) then
        PalletNumber.LayerSheet.Mode = CPoint.Paras.Mode
        if (PalletNumber.LayerSheet.PlanType == PlanType.OnLine
                and CPoint.Paras.Mode == MotionType.LayerSheet) then
            if (CheckDIRes(PalletNumber.LayerSheet.SafePortB.Mode, PalletNumber.LayerSheet.SafePortB.A) == ON) then
                Alarm("LayerSheet is empty!", ErrorMessage.Type.LayerSheetErr)
            end
        end
    end
    AdjustLiftingHeight(CPoint.Paras.LH)
    return CPoint
end
---------------------------------------------------------------
--执行运动流程
local function ExecuteMotion(PalletNumber, CQueue)
    while true do
        Wait(Time.Thread.s0)
        TaskModeDone()                         --若任务设置模式任务完成，机器人停止    
        if (PalletNumber.State.Done == true or PalletNumber.Pallet ~= Pallet or Pallet == Idle) then
            break
        end
        if (CQueue:IsEmpty() == false) then
            local CPoint = PreDealMotion(PalletNumber, CQueue)
            while true do
                Wait(Time.Thread.s0)
                if Capacity.TaskDone == 1 and (Capacity.TaskMode.Mode=="Box" or Capacity.TaskMode.Mode=="Pallet") then
                    break  --若任务设置模式任务完成,退出循环
                end  
                SoftStopMotion()
                FilmMotion()
                GetLiftingHeight(CPoint.Paras.LH)
                if (CPoint.Paras.Mode == MotionType.LayerSheet and PalletNumber.State.Replace == true)
                    or ((PalletNumber.State.StateReady == true) and (SignalReady == true) and (FilmDone == true)) then
                    LogInfo("%s pallet is working!", (Pallet == Left) and "Left" or "Right")
                    SignalReady = false
                    -- PMovS 仅 CR30 提供；仿真/非 CR30 强制走 PTPMotion
                    if (OptimalTrajectoryFunc == true and CPoint.Paras.Mode == MotionType.Norm and WorkingMode ~= ModeType.Exh) then
                        CPMotion(PalletNumber, CPoint)
                    else
                        PTPMotion(PalletNumber, CPoint)
                    end
                    CheckManualLaysheetPause(PalletNumber) --判断除第0层的手动放置隔板，机器人停止
                    if (SignalReady == false) then
                        MotionDone = true
                    end
                    SoftStopMotion()   -- 运动结束后检查软停止，防止最后一段运动完成后请求被丢弃
                    if (StateMachine == FSMType.DLR) then
                        return
                    else
                        break
                    end
                end
            end
        end
    end
end
---------------------------------------------------------------
--获取运动状态
local function GetMotionFSM(PalletNumber, CQueue)
    if (PalletNumber.State.Init == true) then
        ExecuteMotion(PalletNumber, CQueue)
        if (SimulateMode == 1) or (AgingMode == 1) then
            if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
                if FirstPallet.State.Done == true and SecondPallet.State.Done == true then
                    FirstPallet.State.SReset = true
                end
            else
                PalletNumber.State.SReset = true
            end
        end
    end
end
---------------------------------------------------------------
--获取工作状态
local function MotionFSM()
    local SwitchFSM =
    {
        [Idle] = function()
        end,
        [Left] = function()
            GetMotionFSM(FirstPallet, FQueue)
        end,
        [Right] = function()
            GetMotionFSM(SecondPallet, SQueue)
        end
    }

    if (StateMachine ~= FSMType.DLR)
        or (StateMachine == FSMType.DLR and SignalReady == true) then
        local switch_mode = SwitchFSM[Pallet]
        if switch_mode then
            switch_mode()
        else
            Alarm("SwitchFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
    end
end
---------------------------------------------------------------
--初始化，复位信号、复位程序数据
local function InitPallet()
    InitStorageMode()
    InitModbus()
    InitFSM()
    InitPeripheral()
    InitRobot()
end
---------------------------------------------------------------
---------------------------------------------------------------
--主程序
InitPallet()
while true do
    Wait(Time.Thread.s0)
    SoftStopMotion()    --补充软停止边界，在码垛完成后仍然需要响应前端的软停止请求
    MotionFSM()
end

