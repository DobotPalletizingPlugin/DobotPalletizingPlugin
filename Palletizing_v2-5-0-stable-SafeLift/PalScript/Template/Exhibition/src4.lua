
-- 随主程序一起运行的并行程序，可设置I/O、变量等，不能调用运动指令。
-- Version: Lua 5.4.0
FristTimePalletFlag = false
---------------------------------------------------------------
while true do
    if Communication.Controller.Modbus.SuccessFlag == true then
        GetPalletStatusResult(FirstPallet.State, FirstPallet.InPlaceA, FirstPallet.InPlaceB)    --得到栈板到位状态结果
        GetPalletEnableResult(FirstPallet.State, FirstPallet.StateValue)                        --得到栈板上使能的结果
        GetPalletStatusResult(SecondPallet.State, SecondPallet.InPlaceA, SecondPallet.InPlaceB) --得到栈板到位状态结果
        GetPalletEnableResult(SecondPallet.State, SecondPallet.StateValue)                      --得到栈板上使能的结果
        if PalletBeInPlaceOKButton == true then
            while true do
                if (DI(FirstPallet.InPlaceOK) == ON) and (DI(FirstPallet.InPlaceA) == ON)
                    and (DI(FirstPallet.InPlaceB) == ON) and (FirstPallet.State.EnableResult == true) then --栈板到位确认标志的确定
                    if (SecondPallet.StateValue.Status ~= 2) and (FristTimePalletFlag == false) then
                        FristTimePalletFlag = true
                        Pallet = 0
                        if WorkingMode ~= 1 then
                            BoxBeInpPlaceFlag = Pallet
                        end
                    end
                    FirstPallet.State.InPlaceOK = true
                end
                Wait(Time.Thread.s4)
                if (DI(SecondPallet.InPlaceOK) == ON) and (DI(SecondPallet.InPlaceA) == ON)
                    and (DI(SecondPallet.InPlaceB) == ON) and (SecondPallet.State.EnableResult == true) then
                    if (FirstPallet.StateValue.Status ~= 2) and (FristTimePalletFlag == false) then
                        FristTimePalletFlag = true
                        Pallet = 1
                        if WorkingMode ~= 1 then
                            BoxBeInpPlaceFlag = Pallet
                        end
                    end
                    SecondPallet.State.InPlaceOK = true
                end
            end
        else
            while true do
                Wait(Time.Thread.s4)
                if (DI(FirstPallet.InPlaceA) == ON) and (DI(FirstPallet.InPlaceB) == ON)
                    and (FirstPallet.State.EnableResult == true) and (SecondPallet.State.EnableResult == false) then --栈板到位确认标志的确定
                    Pallet = 0
                    if WorkingMode ~= 1 then
                        BoxBeInpPlaceFlag = Pallet
                    end
                elseif (DI(SecondPallet.InPlaceA) == ON) and (DI(SecondPallet.InPlaceB) == ON)
                    and (SecondPallet.State.EnableResult == true) and (FirstPallet.State.EnableResult == false) then
                    Pallet = 1
                    if WorkingMode ~= 1 then
                        BoxBeInpPlaceFlag = Pallet
                    end
                end
            end
        end
    end
end
