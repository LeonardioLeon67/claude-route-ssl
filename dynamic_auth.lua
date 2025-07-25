-- Lua脚本：动态绑定和验证API密钥与URL路径
local bindings_file = "/root/claude-route/claude-route-ssl/bindings.json"
local generated_file = "/root/claude-route/claude-route-ssl/generated_paths.txt"

-- 获取JSON库
local json = require("cjson")

-- 从URI中提取token
local uri = ngx.var.uri
local token = string.match(uri, "^/([a-zA-Z0-9]{16})/v1/messages$")

if not token then
    ngx.status = 404
    ngx.say("Invalid path format")
    ngx.exit(404)
end

-- 获取API密钥
local api_key = ngx.var.http_x_api_key or ngx.var.http_authorization
if not api_key then
    ngx.status = 401
    ngx.say("Missing API key")
    ngx.exit(401)
end

-- 处理Authorization头的Bearer格式
if string.match(api_key, "^Bearer ") then
    api_key = string.gsub(api_key, "Bearer ", "")
end

-- 读取绑定文件
local function read_bindings()
    local file = io.open(bindings_file, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    if content == "" then
        return {}
    end
    
    local success, bindings = pcall(json.decode, content)
    if success then
        return bindings
    else
        return {}
    end
end

-- 写入绑定文件
local function write_bindings(bindings)
    local file = io.open(bindings_file, "w")
    if not file then
        return false
    end
    
    file:write(json.encode(bindings))
    file:close()
    return true
end

-- 更新generated_paths.txt文件，添加已绑定标记
local function update_generated_file(token)
    local temp_file = generated_file .. ".tmp"
    local input = io.open(generated_file, "r")
    local output = io.open(temp_file, "w")
    
    if input and output then
        for line in input:lines() do
            if string.match(line, token) and not string.match(line, "（已绑定）") then
                output:write(line .. " （已绑定）\\n")
            else
                output:write(line .. "\\n")
            end
        end
        input:close()
        output:close()
        
        -- 替换原文件
        os.rename(temp_file, generated_file)
    end
end

-- 主验证逻辑
local bindings = read_bindings()

if bindings[token] then
    -- token已绑定，检查是否过期
    local current_time = os.time()
    local binding_info = bindings[token]
    
    -- 兼容旧格式（直接存储api_key字符串）
    if type(binding_info) == "string" then
        binding_info = {api_key = binding_info, expire_time = 0}
        bindings[token] = binding_info
        write_bindings(bindings)
    end
    
    -- 检查是否过期
    if binding_info.expire_time > 0 and current_time > binding_info.expire_time then
        -- 账户已过期，从绑定中删除
        bindings[token] = nil
        write_bindings(bindings)
        ngx.status = 403
        ngx.say("Account expired")
        ngx.exit(403)
    end
    
    -- 检查API密钥是否匹配
    if binding_info.api_key ~= api_key then
        ngx.status = 403
        ngx.say("This token is bound to another API key")
        ngx.exit(403)
    end
else
    -- token未绑定，进行首次绑定
    local current_time = os.time()
    local expire_time = current_time + (30 * 24 * 60 * 60)  -- 30天后过期
    
    bindings[token] = {
        api_key = api_key,
        expire_time = expire_time
    }
    
    if write_bindings(bindings) then
        -- 更新generated_paths.txt文件
        update_generated_file(token)
        ngx.log(ngx.INFO, "New binding created: " .. token .. " -> " .. api_key)
    else
        ngx.status = 500
        ngx.say("Failed to create binding")
        ngx.exit(500)
    end
end

-- 验证通过，设置正确的Authorization头
local final_api_key = type(bindings[token]) == "table" and bindings[token].api_key or bindings[token]
ngx.req.set_header("Authorization", "Bearer " .. final_api_key)