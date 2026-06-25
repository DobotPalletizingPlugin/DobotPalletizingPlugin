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
    Standy = {},  --待机位置
    OffSet = {},  --偏移标志位
    LH = 0,       --升降高度
    Mode = 0,     --点位类型，0：常规点位，1：隔板运动点位
    Sucker = 0,   --吸盘信号，-1：n吸n单放，0：n吸单放，1：长边对齐双放，2：短边对齐双放，3：长边对齐三放，4：短边对齐三放，5：长边对齐四放，:6：短边对齐四放
    Times = 1,    --运动次数
    TransNum = 1, --过渡点数量
    ErrIndex = 0  --不可达点位序号，0：可达，1~10：对应不可达点位
}

local function CreatePalletData(PalletType)
    return {
        Num = 0,
        Index = 0,
        Init = false,
        FMotion = false,
        CompNum = 0,
        PartNum = {},
        PartIndex = 0,
        TPartIndex = 0,
        Pick = { pose = {} },
        Standy = { pose = {} },
        PartPick = { pose = {} },
        PartPlace = { pose = {} },
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
local function InitPartition(PalletNumber, CData)
    if (PalletNumber.Partition.Enable == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.ProcessNum.BoxCount ~= 0) then
                for i = 1, PalletNumber.PalletNum.LayerCount do
                    CData.PartIndex = CData.PartIndex + PalletNumber.Partition.Layer[i]
                end
            end
        else
            for i = 1, PalletNumber.PalletNum.LayerCount + 1 do
                CData.PartIndex = CData.PartIndex + PalletNumber.Partition.Layer[i]
            end
        end
        if (PalletNumber.Partition.Place == 1) then
            if (PalletNumber.Mode == WorkType.Pallet) then
                CData.PartIndex = CData.PartIndex + 1
            else
                CData.PartIndex = CData.PartIndex - 1
            end
        end
        LogInfo("Partition data: Index: %s", CData.PartIndex)
        LogDebugTable("Partition data: Layer:", CData.PartNum)
    end
end
--------------------------------------------------------------
--获取数据序号
local function GetDataIndex(PalletNumber, CData)
    local LNum = 0
    for i = 1, PalletNumber.Layer + 1 do
        if (PalletNumber.Partition.Enable == true) then
            if (PalletNumber.Partition.Layer[i] == 1) then
                CData.TPartIndex = CData.TPartIndex + 1
                CData.PartNum[CData.TPartIndex] = LNum + CData.TPartIndex
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
    InitPartition(PalletNumber, CData)

    CData.Num = GetBoxCnt(PalletName, CData.Pallet)
    if PalletNumber.Partition.Last == true then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Num
        else
            CData.Index = 1
        end
        PalletNumber.Partition.LastPlan = true
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
        --if (PalletSuckerFunction > 1) then
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
        if (PalletNumber.Partition.Enable == true) then
            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
            if (ProjectType == 1) then
                local PartPickJoint = { joint = {} }
                PartPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
                CData.PartPick = PositiveKin(PartPickJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.PartPick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.pose)
                CData.PartPick.pose[3] = CData.PartPick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end

            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPlacePoint.joint)
            if (ProjectType == 1) then
                local PartPlaceJoint = { joint = {} }
                PartPlaceJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPlacePoint.joint)
                CData.PartPlace = PositiveKin(PartPlaceJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.PartPlace.pose = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPlacePoint.pose)
                CData.PartPlace.pose[3] = CData.PartPlace.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end
        end
        CData.Init = true
        LogInfo("%s queue initialization completed!", (CData.Pallet == Left) and "Left" or "Right")
    end
end
-----------------------------------------------------------------
--获取点位模式
local function GetPointMode(PalletNumber, CData)
    if (PalletNumber.Partition.Enable == true) then
        Res.Mode = MotionType.Norm
        local CPartIndex = 0
        LogDebug("CData.Index: %s, CData.PartIndex: %s", CData.Index, CData.PartIndex)
        if (PalletNumber.Mode == WorkType.Pallet) then
            CPartIndex = CData.PartIndex + 1
        else
            CPartIndex = CData.PartIndex
        end
        if (CData.Index + CData.PartIndex == CData.PartNum[CPartIndex]) or (PalletNumber.Partition.LastPlan == true) then
            Res.Mode = MotionType.Part
        end
    end
end
----------------------------------------------------------------
--计算偏心位置坐标
local function GetEccPoint(CData, CPose)
    if (Res.Mode == MotionType.Norm
            and (PalletSuckerFunction == SuckerCfg.Type.Double
                or PalletSuckerFunction == SuckerCfg.Type.Triple
                or PalletSuckerFunction == SuckerCfg.Type.Quadruple)) then
        local SwitchFSM =
        {
            [SuckerCfg.Type.Double] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
            end,
            [SuckerCfg.Type.Triple] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.Sucker == 1 or Res.Sucker == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
            end,
            [SuckerCfg.Type.Quadruple] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.Sucker == 1 or Res.Sucker == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
                if Res.Sucker == 3 or Res.Sucker == 4 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[4][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[4][2]
                end
            end
        }

        local switch_mode = SwitchFSM[PalletSuckerFunction]
        if switch_mode then
            switch_mode()
        else
            Alarm("Sucker type is wrong!", ErrorMessage.Type.WorkingDataErr)
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
    OffSet[1], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index)
    if (Res.Mode == MotionType.Part) or (Res.Sucker >= 0) then
        Res.Times = 1
    else
        Res.Times = math.abs(PalletSuckerFunction)
    end
    for i = 1, Res.Times do
        if (Res.Mode == MotionType.Part) then
            PickPose = DeepCopy(CData.PartPick)
            PlacePose = DeepCopy(CData.PartPlace)
            TempPose = GetBoxPos(PalletName, CData.Pallet, CData.Index)
            if (PalletNumber.Partition.LastPlan == false and PalletNumber.Mode == WorkType.Pallet)
                or (PalletNumber.Partition.LastPlan == true and PalletNumber.Mode == WorkType.Depallet) then
                PlacePose.pose[3] = TempPose.pose[3] - PalletNumber.BoxProperty.BoxHigh
            else
                PlacePose.pose[3] = TempPose.pose[3] + PalletNumber.ProcessNum.PartitionHeight
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
            OffSet[i], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index + i - 1)
            if (OffSet[i][1] == 0) and (OffSet[i][2] == 0) then
                Res.OffSet[i] = 0
            else
                Res.OffSet[i] = 1
            end
            Point.Pose[7 + i] = DeepCopy(PlacePose.pose)
        else
            local CIndex = Res.Times - i + 1
            OffSet[CIndex], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index - i + 1)
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

    if Res.Mode == MotionType.Part then
        if (PalletNumber.Mode == WorkType.Pallet) then
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.PartIndex + 1])
        else
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.PartIndex])
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
    if Res.Mode == MotionType.Part then
        Res.TransNum = PalletNumber.TransPartitionPointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransPartitionPoint)
    else
        Res.TransNum = PalletNumber.TransPlacePointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransPlacePoint)
    end
    local PHeight = Point.Pose[6][3] + TeachPointOffHeight
    local THeight = Point.Pose[8][3] + PalletNumber.OffsetHeight + OffSet[1][3]

    for i = 1, Res.TransNum do
        if (Res.Mode == MotionType.Part) then
            if (i > Res.TransNum - 2) then
                CopyPoint.pose[i][6] = Point.Pose[8][6]
            end
        else
            CopyPoint.pose[i][6] = Point.Pose[8][6] --过渡点与放置姿态一致
        end

        if CopyPoint.mode[i] == 0 then
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

    if Res.Mode == MotionType.Part then
        PrePoint = PositiveKin(PartSafePoint,
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
--MotionPoint[index]:
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料偏移点（自动生成）
-----------------------------------------------------------------
--获取点位结果
local function GetResult(CData)
    local Ret = { MotionPoint = {}, Paras = {} }
    local ToolNum = 0
    local CJoint = {}
    if (Res.Mode == MotionType.Part) then
        ToolNum = math.abs(PalletSuckerFunction) - 1
    else
        if (Res.Sucker >= 0) then
            ToolNum = math.ceil(Res.Sucker * 0.5)
        else
            ToolNum = Res.Sucker
        end
    end
    CJoint, Res.LH, Res.ErrIndex = GetInvK(PalletName, CData.Pallet, Point.Pose, ToolNum)
    for i = 1, 19 do
        Ret.MotionPoint[i] = { joint = CJoint[i] }
        if (Res.Mode == MotionType.Part) then
            -- 隔板：只有最后2个过渡点使用放置A点对应的joint6
            if ((i > Res.TransNum - 2 and i <= Res.TransNum) or i == 12 or i == 16) then
                Ret.MotionPoint[i].joint[6] = CJoint[8][6]
            end
        else
            -- 普通箱子：保持原先逻辑，1~5过渡点都使用放置A点对应的joint6
            if (i < 6 or i == 12 or i == 16) then
                Ret.MotionPoint[i].joint[6] = CJoint[8][6]
            end
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
    if (Res.Mode == MotionType.Part) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.PartIndex = CData.PartIndex + 1
        else
            CData.PartIndex = CData.PartIndex - 1
        end
    end
    if (Res.Mode == MotionType.Norm) or (PalletNumber.Partition.LastPlan == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Index + Res.Times
            if (CData.Index > CData.Num) then
                if (PalletNumber.Partition.Enable == true) then
                    if (PalletNumber.Partition.LastPlan == false)
                        and (PalletNumber.Partition.Layer[PalletNumber.Layer + 1] == 1) then
                        CData.Index = CData.Num
                        PalletNumber.Partition.LastPlan = true
                        return
                    else
                        PalletNumber.Partition.LastPlan = false
                    end
                end
                CData.Index = 1
                CData.PartIndex = 0
            end
        else
            CData.Index = CData.Index - Res.Times
            if (CData.Index <= 0) then
                if (PalletNumber.Partition.Enable == true) then
                    if (PalletNumber.Partition.LastPlan == false) and (PalletNumber.Partition.Layer[1] == 1) then
                        CData.Index = 1
                        PalletNumber.Partition.LastPlan = true
                        return
                    else
                        PalletNumber.Partition.LastPlan = false
                    end
                end
                CData.Index = CData.Num
                CData.PartIndex = CData.TPartIndex
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
