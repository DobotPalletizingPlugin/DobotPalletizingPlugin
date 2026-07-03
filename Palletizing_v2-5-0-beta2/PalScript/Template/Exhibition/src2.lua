
-- 子线程，随主线程一起运行的并行程序，可设置I/O、通讯、变量等，不能调用运动指令。
---------------------------------------------------------------
LightDelayTime = 500 --三色灯延时

---------------------------------------------------------------
--工作完成三色灯提示
local function FullPalletState(PalletNumber, FinishState)
	if ((PalletNumber.State.Replace == true)and(PalletNumber.State.EnableResult == true)and(FinishState == true)) then
		DO(PalletNumber.TriLight.Yellow,ON)  --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
		DO(PalletNumber.TriLight.Green,OFF)  --栈板码垛中，绿灯常亮
		DO(PalletNumber.TriLight.Red,OFF)    --栈板报错，红灯常亮	
        Wait(LightDelayTime)
		DO(PalletNumber.TriLight.Yellow,OFF)
        Wait(LightDelayTime)
        if BuzzerFunction == true then
            DO(BuzzerIO, ON) --开启蜂鸣器
        end
	end
end

--------------------------------------------------------------
--检测栈板更换
local function CheckPallet(PalletNumber, PalletData, NameStr)
    --GetPalletStatusResult(PalletNumber.State, PalletNumber.InPlaceA, PalletNumber.InPlaceB) --得到栈板到位状态结果
    --GetPalletEnableResult(PalletNumber.State, PalletNumber.StateValue)      --得到栈板上使能的结果

    --[[if (FinishState == true) and (DI(PalletNumber.InPlaceA) == OFF) and (DI(PalletNumber.InPlaceB) == OFF) then
        PalletNumber.State.FirstResetFlag = true --第1次判断栈板是否移开

        print("\rPalletNumber.State.FirstResetFlag:", PalletNumber.State.FirstResetFlag)

        DO(PalletNumber.TriLight.Yellow, ON) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
        DO(PalletNumber.TriLight.Green, OFF) --栈板码垛中，绿灯常亮
        DO(PalletNumber.TriLight.Red, OFF)   --栈板报错，红灯常亮
    end
    if (PalletNumber.State.FirstResetFlag == true) and (FinishState == true) and (PalletNumber.State.Replace == true) then
        PalletNumber.State.InPlaceOK = false
        PalletNumber.State.SecondResetFlag = true --第2次判断栈板是否到位
        print("\rSecondResetFlag:", PalletNumber.State.SecondResetFlag)

        DO(PalletNumber.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
        DO(PalletNumber.TriLight.Green, OFF)  --栈板码垛中，绿灯常亮
        DO(PalletNumber.TriLight.Red, OFF)    --栈板报错，红灯常亮
    end]]
	
    --当满载托盘到位信号变为OFF时，即表示满载托盘被取走，则复位满载信号、满载布尔变量以及箱体计数、托盘计数等
    if (PalletNumber.State.SecondResetFlag == true) and (FinishFlag == false) then
        if BuzzerFunction == true then
            DO(BuzzerIO, OFF)                 --关闭蜂鸣器
        end
        PalletNumber.Layer = GetLayerCnt(NameStr, PalletData)
        PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(NameStr, PalletData)
        TotalPalletCount = RemainingTotalPalletCount + 1
        RemainingTotalPalletCount = TotalPalletCount
        WriteRobotModbus(TotalPalletCount, 5012)
        if PalletNumber.PalletMode == 1 then
            PalletNumber.ProcessNum.BoxCount = 0 --托盘箱体计数
            PalletNumber.PalletNum.NextBoxCount = 1
            PalletNumber.PalletNum.LayerBoxNum = GetOddBoxCnt(NameStr, PalletData, 1)
            PalletNumber.PalletNum.LayerCount = 1                                          --托盘层数计数
            PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(NameStr, PalletData, 1) --托盘不满一层箱体的数量
            PalletNumber.ProcessNum.InitBoxCount = 0                                   --栈板料箱计数置位
            PalletNumber.PalletNum.AddBoxCount = 0
            PalletNumber.ProcessNum.RemainingAddBoxCount = 0
        elseif PalletNumber.PalletMode == 2 then
            PalletNumber.ProcessNum.BoxCount = PalletNumber.ProcessNum.TotalBoxNum --托盘箱体计数
            PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.TotalBoxNum
            PalletNumber.PalletNum.LayerBoxNum = PalletNumber.ProcessNum.TotalBoxNum
            PalletNumber.PalletNum.LayerCount = PalletNumber.Layer                   --托盘层数计数
            PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(NameStr, PalletData, PalletNumber.Layer) --托盘不满一层箱体的数量                                  --托盘不满一层箱体的数量
            PalletNumber.ProcessNum.InitBoxCount = PalletNumber.ProcessNum.TotalBoxNum                  --栈板料箱计数置位
            PalletNumber.PalletNum.AddBoxCount = 0
            local TempData = 0
            local TempAddData = 0
            for i = 1, PalletNumber.Layer do
                TempData, TempAddData = GetOddBoxCnt(NameStr, PalletData, i)
                PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount + TempAddData
            end
            PalletNumber.ProcessNum.RemainingAddBoxCount = PalletNumber.PalletNum.AddBoxCount
        else
            print("\rPalletMode is Error!")
            print("\rPalletMode:", PalletNumber.PalletMode)
        end
        
        CommitPalletNum(PalletNumber)                   --上传已有料箱层数、剩余料箱数

        PalletNumber.StateValue.Status = 5              --空闲中
        PalletNumber.State.FirstResetFlag = false       --第1次判断栈板是否移开，复位标志位
        PalletNumber.State.SecondResetFlag = false      --第2次判断栈板是否到位，复位标志位
        PalletNumber.State.ReplaceNewPalletFlag = false --栈板丢失标志位置位
        if PalletNumber.PalletMode == 1 then
            FirstPallet.State.Full = false
            SecondPallet.State.Full = false
        else
            FirstPallet.State.Empty = false
            SecondPallet.State.Empty = false
        end
        WorkFinishFlag = false
    end
end

---------------------------------------------------------------
--检测工作状态更新
local function PalletStateCheck(PalletNumber)
    GetPalletStatusResult(PalletNumber.State, PalletNumber.InPlaceA, PalletNumber.InPlaceB) --得到栈板到位状态结果
    GetPalletEnableResult(PalletNumber.State, PalletNumber.StateValue)                      --得到栈板上使能的结果
    if (PalletNumber.State.Replace == true) then                                            --判断当前工作状况，先判断托盘是否准备好，再判断托盘是否上使能
        if (PalletNumber.State.EnableResult == true) then
            if (PalletNumber.StateValue.Status ~= 2) and (PalletNumber.StateValue.Status ~= 3)
                or ((WorkingMode == 2) and (PalletNumber.StateValue.Status == 2)) then
                if (PalletNumber.StateValue.Status ~= 2) and (PalletNumber.StateValue.Status ~= 3) then
                    PalletNumber.StateValue.Status = 5 --空闲中
                end
                DO(PalletNumber.TriLight.Yellow, OFF) --栈板未检测到，黄灯常亮；栈板已满，黄灯闪烁
                DO(PalletNumber.TriLight.Green, ON)   --栈板码垛/拆垛中，绿灯常亮
                DO(PalletNumber.TriLight.Red, OFF)    --栈板报错，红灯常亮
            end
        else
            PalletNumber.StateValue.Status = 1 --检测到栈板但未上使能
        end
    else
        PalletNumber.StateValue.Status = 0                               --未检测到栈板
    end
    CommitPalletStatus(PalletNumber.StateValue, PalletNumber.RegisterID) --上传栈板状态
end

---------------------------------------------------------------
--子线程主流程
local function CheckPalletState(PalletNumber, PalletData, NameStr)
    local CurrentState = false

    CheckPallet(PalletNumber, PalletData, NameStr)
    PalletStateCheck(PalletNumber)
    if PalletNumber.PalletMode == 1 then
        CurrentState = PalletNumber.State.Full
    else
        CurrentState = PalletNumber.State.Empty
    end
    FullPalletState(PalletNumber, CurrentState)
end

---------------------------------------------------------------
while true do
    if Communication.Controller.Modbus.SuccessFlag == true then
        while true do
            Wait(Time.Thread.s2)
            if MultPalletFunction == true then
                CheckPalletState(FirstPallet, 0, PalletName)
                CheckPalletState(SecondPallet, 1, PalletName)
            else
                if Pallet == 0 then
                    CheckPalletState(FirstPallet, 0, PalletName)
                elseif Pallet == 1 then
                    CheckPalletState(SecondPallet, 1, PalletName)
                end
            end
        end
    end
end
