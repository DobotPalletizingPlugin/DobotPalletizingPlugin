--------------------------------------------------------------
--此文件仅用于定义点位计算
--------------------------------------------------------------
--局部常量
local BufLen = 10
--------------------------------------------------------------
--局部变量
local OffSet =
{
    {}
}
local Point =
{
    Pose = {}
}

local Res =
{
    Standy = {},                    --待机位置
    OffSet = {},                    --偏移量
    ToolData = {},                  --工具坐标数据
    RePlanData = { 0, 0, 0, 0, 0 }, --重规划关节
    LH = 0,                         --升降高度
    Mode = 0,                       --点位类型，0：常规点位，1：隔板运动点位
    VacuumCup = 0,                  --吸盘属性，-1：n吸n单放，0：n吸单放，1：长边对齐双放，2：短边对齐双放，3：长边对齐三放，4：短边对齐三放，5：长边对齐四放，:6：短边对齐四放
    Times = 1,                      --运动次数
    TransNum = 1,                   --过渡点数量
    ErrIndex = 0                    --不可达点位序号，0：可达，1~10：对应不可达点位
}

local function CreatePalletData(PalletType)
    return {
        Num = 0,
        Index = 0,
        Init = false,
        FMotion = false,
        CompNum = 0,
        LSNum = {},
        LSIndex = 0,
        TLSIndex = 0,
        Pick = { pose = {} },
        Standy = { pose = {} },
        LSPick = { pose = {} },
        LSPlace = { pose = {} },
        Pallet = PalletType,
        User = 0,
        Tool = {
            Conc = 0,    --同心工具号
            Ecc = {},    --偏心工具号
            EccData = {} --偏心数据
        }
    }
end

local FData = CreatePalletData(Left)
local SData = CreatePalletData(Right)

--------------------------------------------------------------
--初始化隔板数量
local function InitLayerSheet(PalletNumber, CData)
    if (PalletNumber.LayerSheet.Enable == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.ProcessNum.BoxCount ~= 0) then
                for i = 1, PalletNumber.PalletNum.LayerCount do
                    CData.LSIndex = CData.LSIndex + PalletNumber.LayerSheet.Layer[i]
                end
            end
        else
            for i = 1, PalletNumber.PalletNum.LayerCount + 1 do
                CData.LSIndex = CData.LSIndex + PalletNumber.LayerSheet.Layer[i]
            end
        end
        if (PalletNumber.LayerSheet.Place == 1) then
            if (PalletNumber.Mode == WorkType.Pallet) then
                CData.LSIndex = CData.LSIndex + 1
            else
                CData.LSIndex = CData.LSIndex - 1
            end
        end
        LogInfo("LayerSheet data: Index: %s", CData.LSIndex)
        LogDebugTable("LayerSheet data: Layer:", CData.LSNum)
    end
end
--------------------------------------------------------------
--获取数据序号
local function GetDataIndex(PalletNumber, CData)
    local LNum = 0
    for i = 1, PalletNumber.Layer + 1 do
        if (PalletNumber.LayerSheet.Enable == true) then
            if (PalletNumber.LayerSheet.Layer[i] == 1) then
                CData.TLSIndex = CData.TLSIndex + 1
                CData.LSNum[CData.TLSIndex] = LNum + CData.TLSIndex
            end
        end
        if (i <= PalletNumber.Layer) then
            LNum = LNum + GetOddBoxCnt(PalletName, CData.Pallet, i)
            if (i == PalletNumber.CompensateLayer) then
                if (i == 1) then
                    CData.CompNum = 0
                else
                    CData.CompNum = LNum
                end
            end
        end
    end
    InitLayerSheet(PalletNumber, CData)

    CData.Num = GetBoxCnt(PalletName, CData.Pallet)
    if PalletNumber.LayerSheet.Last == true then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Num
        else
            CData.Index = 1
        end
        PalletNumber.LayerSheet.LastPlan = true
    else
        CData.Index = PalletNumber.PalletNum.NextBoxCount
    end
end
---------------------------------------------------------------
--获取点位数据
local function GetTeachPoint(PalletNumber, CData)
    if (CData.Init == false) then
        GetDataIndex(PalletNumber, CData)

        CData.User = PalletNumber.Coordinate.UserNum
        CData.Tool.Conc = PalletNumber.Coordinate.ToolNum
        --local EccTool = {}
        --if (PalletVacuumCupFunc > 1) then
        --    CData.Tool.Ecc, EccTool, CData.Tool.EccData = GetPalletTool(PalletName, ToolType.Ecc)
        --end

        local ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPickPoint.joint)
        if (ProjectType == 1) then
            local PickJoint = { joint = {} }
            PickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPickPoint.joint)
            CData.Pick = PositiveKin(PickJoint, { user = CData.User, tool = CData.Tool.Conc })
            CData.Standy = PositiveKin(PickJoint)
            CData.Standy.pose[3] = CData.Standy.pose[3] + TeachPointOffHeight
        else
            CData.Pick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPickPoint.pose)
            CData.Pick.pose[3] = CData.Pick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            CData.Standy = GetAddUserPos(PalletNumber.Coordinate.UserNum, 0, CData.Pick)
            CData.Standy.pose[3] = CData.Standy.pose[3] + TeachPointOffHeight
        end
        if (PalletNumber.LayerSheet.Enable == true) then
            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.joint)
            if (ProjectType == 1) then
                local LSPickJoint = { joint = {} }
                LSPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.joint)
                CData.LSPick = PositiveKin(LSPickJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.LSPick.pose = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPickPoint.pose)
                CData.LSPick.pose[3] = CData.LSPick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end

            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachLayerSheetPlacePoint.joint)
            if (ProjectType == 1) then
                local LSPlaceJoint = { joint = {} }
                LSPlaceJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPlacePoint.joint)
                CData.LSPlace = PositiveKin(LSPlaceJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.LSPlace.pose = DeepCopy(PalletNumber.TeachPoint.TeachLayerSheetPlacePoint.pose)
                CData.LSPlace.pose[3] = CData.LSPlace.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end
        end
        CData.Init = true
        LogInfo("%s queue initialization completed!", (CData.Pallet == Left) and "Left" or "Right")
    end
end
-----------------------------------------------------------------
--获取点位模式
local function GetPointMode(PalletNumber, CData)
    if (PalletNumber.LayerSheet.Enable == true) then
        Res.Mode = MotionType.Norm
        local CLSIndex = 0
        LogDebug("CData.Index: %s, CData.LSIndex: %s", CData.Index, CData.LSIndex)
        if (PalletNumber.Mode == WorkType.Pallet) then
            CLSIndex = CData.LSIndex + 1
        else
            CLSIndex = CData.LSIndex
        end
        if (CData.Index + CData.LSIndex == CData.LSNum[CLSIndex]) or (PalletNumber.LayerSheet.LastPlan == true) then
            Res.Mode = MotionType.LayerSheet
        end
    end
end
----------------------------------------------------------------
--计算偏心位置坐标
local function GetEccPoint(CData, CPose)
    if (Res.Mode == MotionType.Norm
            and (PalletVacuumCupFunc == VacuumCupCfg.Type.Double
                or PalletVacuumCupFunc == VacuumCupCfg.Type.Triple
                or PalletVacuumCupFunc == VacuumCupCfg.Type.Quadruple)) then
        local SwitchFSM =
        {
            [VacuumCupCfg.Type.Double] = function()
                if Res.VacuumCup == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
            end,
            [VacuumCupCfg.Type.Triple] = function()
                if Res.VacuumCup == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.VacuumCup == 1 or Res.VacuumCup == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
            end,
            [VacuumCupCfg.Type.Quadruple] = function()
                if Res.VacuumCup == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.VacuumCup == 1 or Res.VacuumCup == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
                if Res.VacuumCup == 3 or Res.VacuumCup == 4 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[4][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[4][2]
                end
            end
        }

        local switch_mode = SwitchFSM[PalletVacuumCupFunc]
        if switch_mode then
            switch_mode()
        else
            Alarm("VacuumCup type is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
    end

    return CPose
end
----------------------------------------------------------------
--计算取放位置
local function GetPickPlacePoint(PalletNumber, CData)
    local PickPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local PlacePose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local TempPose = { pose = { 0, 0, 0, 0, 0, 0 } }

    GetPointMode(PalletNumber, CData)
    OffSet[1], Res.VacuumCup = GetBoxProPerty(PalletName, CData.Pallet, CData.Index)
    if (Res.Mode == MotionType.LayerSheet) or (Res.VacuumCup >= 0) then
        Res.Times = 1
    else
        Res.Times = math.abs(PalletVacuumCupFunc)
    end
    for i = 1, Res.Times do
        if (Res.Mode == MotionType.LayerSheet) then
            PickPose = DeepCopy(CData.LSPick)
            PlacePose = DeepCopy(CData.LSPlace)
            TempPose = GetBoxPos(PalletName, CData.Pallet, CData.Index)
            if (PalletNumber.LayerSheet.LastPlan == false and PalletNumber.Mode == WorkType.Pallet)
                or (PalletNumber.LayerSheet.LastPlan == true and PalletNumber.Mode == WorkType.Depallet) then
                PlacePose.pose[3] = TempPose.pose[3] - PalletNumber.BoxProperty.BoxHigh
            else
                PlacePose.pose[3] = TempPose.pose[3] + PalletNumber.ProcessNum.LayerSheetHeight
            end
        else
            PickPose = DeepCopy(CData.Pick)
            if (PalletNumber.Mode == WorkType.Pallet) then
                PlacePose = GetBoxPos(PalletName, CData.Pallet, CData.Index + i - 1)
            else
                PlacePose = GetBoxPos(PalletName, CData.Pallet, CData.Index - i + 1)
            end
        end
        if (CData.Index > CData.CompNum) then
            PlacePose.pose[3] = PlacePose.pose[3] - PalletNumber.CompensateZData
        end
        if (PalletNumber.Mode == WorkType.Pallet) then
            OffSet[i], Res.VacuumCup = GetBoxProPerty(PalletName, CData.Pallet, CData.Index + i - 1)
            if (OffSet[i][1] == 0) and (OffSet[i][2] == 0) then
                Res.OffSet[i] = 0
            else
                Res.OffSet[i] = 1
            end
            Point.Pose[7 + i] = DeepCopy(PlacePose.pose)
        else
            local CIndex = Res.Times - i + 1
            OffSet[CIndex], Res.VacuumCup = GetBoxProPerty(PalletName, CData.Pallet, CData.Index - i + 1)
            if (OffSet[CIndex][1] == 0) and (OffSet[CIndex][2] == 0) then
                Res.OffSet[CIndex] = 0
            else
                Res.OffSet[CIndex] = 1
            end
            Point.Pose[7 + CIndex] = DeepCopy(PlacePose.pose)
        end
        --PickPose.pose = GetEccPoint(CData, PickPose.pose)
    end

    Point.Pose[6] = DeepCopy(PickPose.pose)
    Res.Standy = DeepCopy(CData.Standy)
end
---------------------------------------------------------------
--选择自动过渡点
local function GetAutoGenPoint(PalletNumber, CData)
    local TPoint = { pose = {} }

    if Res.Mode == MotionType.LayerSheet then
        if (PalletNumber.Mode == WorkType.Pallet) then
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.LSIndex + 1])
        else
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.LSIndex])
        end
    else
        TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.TransPoint[CData.Index])
    end

    Res.TransNum = CheckTableData(TPoint.pose)
    if Res.TransNum > 0 then
        TPoint = GetAddUserPos(0, PalletNumber.Coordinate.UserNum, TPoint)
        TPoint.pose[6] = Point.Pose[8][6] --过渡点与放置姿态一致
        Point.Pose[1] = DeepCopy(TPoint.pose)
    else
        Point.Pose[1] = { 0, 0, 0, 0, 0, 0 }
    end
end
---------------------------------------------------------------
--选择示教过渡点
local function GetTransPoint(PalletNumber)
    local CopyPoint = {}
    if Res.Mode == MotionType.LayerSheet then
        Res.TransNum = PalletNumber.TransLayerSheetPointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransLayerSheetPoint)
    else
        Res.TransNum = PalletNumber.TransPlacePointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransPlacePoint)
    end
    local PHeight = Point.Pose[6][3] + TeachPointOffHeight
    local THeight = Point.Pose[8][3] + PalletNumber.OffsetHeight + OffSet[1][3]

    for i = 1, Res.TransNum do
        if CopyPoint.mode[i] == 0 then
            CopyPoint.pose[i][6] = Point.Pose[8][6] --过渡点与放置姿态一致
            if CopyPoint.pose[i][3] <= THeight then
                CopyPoint.pose[i][3] = THeight
            end

            if CopyPoint.pose[i][3] <= PHeight then
                CopyPoint.pose[i][3] = PHeight
            end
        end

        Point.Pose[i] = DeepCopy(CopyPoint.pose[i])
    end
end

---------------------------------------------------------------
--计算放料位置
local function GetInterPoint(PalletNumber)
    local PreTrans = { pose = {} }
    local PreOffset = { pose = {} }
    local PrePoint = { pose = {} }

    if Res.Mode == MotionType.LayerSheet then
        local SafePoint = { joint = {} }
        SafePoint.joint = DeepCopy(PalletNumber.LayerSheet.SafePoint.Forward.joint[1])
        PrePoint = PositiveKin(SafePoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
    else
        PrePoint.pose = DeepCopy(Point.Pose[6])
        PrePoint.pose[3] = PrePoint.pose[3] + TeachPointOffHeight --取料上方点
    end
    Point.Pose[7] = DeepCopy(PrePoint.pose)

    for i = 1, Res.Times do
        PreTrans.pose = DeepCopy(Point.Pose[7 + i])
        PreTrans.pose[1] = PreTrans.pose[1] + OffSet[i][1]
        PreTrans.pose[2] = PreTrans.pose[2] + OffSet[i][2]
        PreTrans.pose[3] = PreTrans.pose[3] + OffSet[i][3] + PalletNumber.OffsetHeight

        PreOffset.pose = DeepCopy(Point.Pose[7 + i])
        if (Res.OffSet[i] == 0) then
            PreOffset.pose[3] = PreOffset.pose[3] + OffSet[i][3] + PalletNumber.OffsetHeight
        else
            PreOffset.pose[3] = PreOffset.pose[3] + PalletNumber.OffsetHeight
        end
        Point.Pose[15 + i] = DeepCopy(PreTrans.pose)
        Point.Pose[11 + i] = DeepCopy(PreOffset.pose)
    end
end

-----------------------------------------------------------------
--重规划路径关节
local function RePlanTrajectory(SPoint)
    if (Res.Times <= 1 or LabelFunction == false) then
        return
    end
    local RePlanPoint = { Point = {} }
    RePlanPoint.Point[1] = PositiveKin(SPoint[7])
    for i = 1, Res.TransNum do
        RePlanPoint.Point[i + 1] = PositiveKin(SPoint[i])
    end
    RePlanPoint.Point[2 + Res.TransNum] = PositiveKin(SPoint[9])

    local DisList = {}
    local TotalDis = 0
    for i = 1, Res.TransNum + 1 do
        local SP = RePlanPoint.Point[i].pose
        local EP = RePlanPoint.Point[i + 1].pose

        local DX = SP[1] - EP[1]
        local DY = SP[2] - EP[2]
        local DZ = SP[3] - EP[3]

        local Dis = math.sqrt(DX * DX + DY * DY + DZ * DZ)
        TotalDis = TotalDis + Dis
        DisList[i] = TotalDis
    end
    LogInfo("Start Joint:%s, End Joint:%s", SPoint[7].joint[6], SPoint[9].joint[6])
    for i = 1, Res.TransNum do
        local Scale = DisList[i] / TotalDis
        Res.RePlanData[i] = SPoint[7].joint[6] + Scale * (SPoint[9].joint[6] - SPoint[7].joint[6])
        LogInfo("RePlanData[%s]:%s", i, Res.RePlanData[i])
    end
end
-----------------------------------------------------------------
--MotionPoint[index]:
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料偏移点（自动生成）
-----------------------------------------------------------------
--获取点位结果
local function GetResult(CData)
    local Ret = { MotionPoint = {}, Paras = {} }
    local ToolNum = 0
    local CJoint = {}
    if (Res.Mode == MotionType.LayerSheet) then
        ToolNum = math.abs(PalletVacuumCupFunc) - 1
    else
        if (Res.VacuumCup >= 0) then
            ToolNum = math.ceil(Res.VacuumCup * 0.5)
        else
            ToolNum = Res.VacuumCup
        end
    end
    CJoint, Res.LH, Res.ErrIndex, Res.ToolData = GetInvK(PalletName, CData.Pallet, Point.Pose, ToolNum)
    for i = 1, 19 do
        Ret.MotionPoint[i] = { joint = CJoint[i] }
        if (Res.Times > 1 and LabelFunction == true) then
            if (i < 6 or i == 12 or i == 16) then
                Ret.MotionPoint[i].joint[6] = CJoint[8][6]
            end
            if (i == 13 or i == 17) then
                Ret.MotionPoint[i].joint[6] = CJoint[9][6]
            end
            if (i == 14 or i == 18) then
                Ret.MotionPoint[i].joint[6] = CJoint[10][6]
            end
            if (i == 15 or i == 19) then
                Ret.MotionPoint[i].joint[6] = CJoint[11][6]
            end
        end
    end
    RePlanTrajectory(Ret.MotionPoint)
    Ret.Paras = DeepCopy(Res)
    return Ret
end
-----------------------------------------------------------------
--获取点位
local function GetPoint(PalletNumber, CData)
    local CPoint = {}
    GetPickPlacePoint(PalletNumber, CData)
    LogDebug("Pick and place point calculation completed at %f", os.clock())
    if (Res.Mode == MotionType.Norm) then
        if (PalletNumber.TransPointMode == 0) then
            GetTransPoint(PalletNumber)
        else
            GetAutoGenPoint(PalletNumber, CData)
        end
    else
        if (PalletNumber.TransPartPointMode == 0) then
            GetTransPoint(PalletNumber)
        else
            GetAutoGenPoint(PalletNumber, CData)
        end
    end
    LogDebug("Trans point calculation completed at %f", os.clock())
    GetInterPoint(PalletNumber)
    LogDebug("Inter point calculation completed at %f", os.clock())
    CPoint = GetResult(CData)
    return CPoint
end
----------------------------------------------------------------
--更新目录
local function UpdateIndex(PalletNumber, CData)
    if (Res.Mode == MotionType.LayerSheet) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.LSIndex = CData.LSIndex + 1
        else
            CData.LSIndex = CData.LSIndex - 1
        end
    end
    if (Res.Mode == MotionType.Norm) or (PalletNumber.LayerSheet.LastPlan == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Index + Res.Times
            if (CData.Index > CData.Num) then
                if (PalletNumber.LayerSheet.Enable == true) then
                    if (PalletNumber.LayerSheet.LastPlan == false)
                        and (PalletNumber.LayerSheet.Layer[PalletNumber.Layer + 1] == 1) then
                        CData.Index = CData.Num
                        PalletNumber.LayerSheet.LastPlan = true
                        return
                    else
                        PalletNumber.LayerSheet.LastPlan = false
                    end
                end
                CData.Index = 1
                CData.LSIndex = 0
            end
        else
            CData.Index = CData.Index - Res.Times
            if (CData.Index <= 0) then
                if (PalletNumber.LayerSheet.Enable == true) then
                    if (PalletNumber.LayerSheet.LastPlan == false) and (PalletNumber.LayerSheet.Layer[1] == 1) then
                        CData.Index = 1
                        PalletNumber.LayerSheet.LastPlan = true
                        return
                    else
                        PalletNumber.LayerSheet.LastPlan = false
                    end
                end
                CData.Index = CData.Num
                CData.LSIndex = CData.TLSIndex
            end
        end
    end
end
----------------------------------------------------------------
--更新点位
local function UpdatePoint(PalletNumber, CQueue, CData)
    local CPoint = {}
    local QueueL = math.min(BufLen, CData.Num)
    if (CQueue:Size() < QueueL) then
        for i = 1, 19 do
            Point.Pose[i] = { 0, 0, 0, 0, 0, 0 }
        end
        CPoint = GetPoint(PalletNumber, CData)
        LogDebug("All point calculation completed at %f", os.clock())
        UpdateIndex(PalletNumber, CData)
        LogDebug("UpdateIndex completed at %f", os.clock())
        CQueue:Push(CPoint)
        LogDebug("Point pushed to queue completed at %f", os.clock())
        local Dir = (CData.Pallet == Left) and "Left" or "Right"
        LogInfo("%s queue - index: %d, size: %d", Dir, CData.Index, CQueue:Size())
        LogDebugTable(Dir .. " queue data is: ", CPoint)
    end
end
----------------------------------------------------------------
--执行动作
local function ExecuteFSM(PalletNumber, CQueue, CData)
    if (PalletNumber.State.Init == false) then
        return
    end
    LogDebug("Queue start calculation at: %f", os.clock())
    while (PalletNumber.Pallet == Pallet) or (CData.FMotion == false) do
        CData.FMotion = true
        if (PalletNumber.State.Done == true) then
            break
        end
        GetTeachPoint(PalletNumber, CData)
        UpdatePoint(PalletNumber, CQueue, CData)
        if (StateMachine == FSMType.DLR)
            or (StateMachine == FSMType.SLR
                and (CQueue:Size() > 2)
                and (FData.FMotion == false or SData.FMotion == false)) then
            break
        end
    end
end
-----------------------------------------------------------------
--获取点位状态
local function PointFSM()
    local SwitchFSM =
    {
        [FSMType.IDLE] = function()
            LogWarn("Point FSM is IDLE!")
        end,
        [FSMType.SL] = function()
            ExecuteFSM(FirstPallet, FQueue, FData)
        end,
        [FSMType.SR] = function()
            ExecuteFSM(SecondPallet, SQueue, SData)
        end,
        [FSMType.DP] = function()
            ExecuteFSM(FirstPallet, FQueue, FData)
            ExecuteFSM(SecondPallet, SQueue, SData)
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
        Alarm("PointFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
    end
end
-----------------------------------------------------------------
-----------------------------------------------------------------
while true do
    Wait(Time.Thread.s3)
    if (Communication.Controller.Modbus.LinkState == true) then
        PointFSM()
    end
end
