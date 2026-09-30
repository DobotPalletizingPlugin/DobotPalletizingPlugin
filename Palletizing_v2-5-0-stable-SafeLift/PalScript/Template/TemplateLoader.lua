require('PalScript.Tool.Utils')

local TemplateLoader = {}

TemplateLoader.FileNameList = {
    [1] = 'src0.lua',
    [2] = 'global.lua',
    [3] = 'src1.lua',
    [4] = 'src2.lua',
    [5] = 'src3.lua',
    [6] = 'src4.lua',
    [7] = 'src5.lua',
    [8] = 'src6.lua',
    [9] = 'src7.lua'
}

-- mode: 0为通用脚本；1为展示模式脚本；
function TemplateLoader.GetContent(mode)
    local info = debug.getinfo(1, "S")
    local currentDir = info.source:sub(2):match("(.*[/\\])")
    local targetDir = ''
    if mode == 1 then
        -- 展示模式
        targetDir = 'Exhibition/'
    else
        -- 通用脚本
        targetDir = 'General/'
    end
    return TemplateLoader.LoadContentByPath(currentDir .. targetDir)
end

function TemplateLoader.LoadContentByPath(path)
    EcoLog('LoadContentByPath path: ' .. path)
    local result = {}
    for key, value in ipairs(TemplateLoader.FileNameList) do
        local content = ToolUtils.FileSysRead(path .. value)
        if content.code == 0 then result[value] = content.data end
    end
    return result
end

return TemplateLoader
