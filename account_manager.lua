#!/usr/bin/env lua

-- 账户管理脚本
local json = require("cjson")
local bindings_file = "/root/claude-route/claude-route-ssl/bindings.json"

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

-- 格式化时间戳为可读时间
local function format_time(timestamp)
    if timestamp == 0 then
        return "永不过期"
    end
    -- 转换为北京时间 (UTC+8)
    return os.date("%Y-%m-%d %H:%M:%S", timestamp + 8 * 3600) .. " (北京时间)"
end

-- 从Redis获取URL过期时间
local function get_url_expire_time(token)
    local handle = io.popen("redis-cli HGET url:" .. token .. " expire_at")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result ~= "" then
            return tonumber(result:match("^%d+"))
        end
    end
    return nil
end

-- 显示所有账户状态
local function list_accounts()
    local bindings = read_bindings()
    local current_time = os.time()
    
    print("=== 账户状态列表 ===")
    print(string.format("%-18s %-12s %-20s %-20s", "Token", "状态", "过期时间", "API密钥前缀"))
    print(string.rep("-", 80))
    
    for token, info in pairs(bindings) do
        local status = "有效"
        local expire_time = 0
        local api_key = ""
        
        if type(info) == "string" then
            -- 旧格式兼容
            api_key = string.sub(info, 1, 20) .. "..."
        else
            api_key = string.sub(info.api_key, 1, 20) .. "..."
        end
        
        -- 从Redis获取URL的过期时间
        local redis_expire_time = get_url_expire_time(token)
        if redis_expire_time then
            expire_time = redis_expire_time
            if current_time > expire_time then
                status = "已过期"
            end
        else
            status = "未知"
        end
        
        print(string.format("%-18s %-12s %-20s %-20s", 
            token, status, format_time(expire_time), api_key))
    end
    print()
end

-- 手动设置账户过期时间
local function set_expire_time(token, days)
    local bindings = read_bindings()
    
    if not bindings[token] then
        print("错误: Token " .. token .. " 不存在")
        return false
    end
    
    local current_time = os.time()
    local expire_time = current_time + (days * 24 * 60 * 60)
    
    -- 更新Redis中的过期时间
    os.execute("redis-cli HSET url:" .. token .. " expire_at " .. expire_time .. " > /dev/null")
    os.execute("redis-cli EXPIRE url:" .. token .. " " .. (days * 24 * 60 * 60) .. " > /dev/null")
    
    print("成功设置 " .. token .. " 的过期时间为 " .. format_time(expire_time))
    return true
end

-- 清理过期账户
local function cleanup_expired()
    local bindings = read_bindings()
    local current_time = os.time()
    local removed_count = 0
    
    for token, info in pairs(bindings) do
        local should_remove = false
        
        -- 从Redis获取URL的过期时间
        local redis_expire_time = get_url_expire_time(token)
        if redis_expire_time and current_time > redis_expire_time then
            should_remove = true
        end
        
        if should_remove then
            bindings[token] = nil
            removed_count = removed_count + 1
            -- 同时从Redis中删除
            os.execute("redis-cli DEL url:" .. token .. " > /dev/null")
            print("已删除过期账户: " .. token)
        end
    end
    
    if removed_count > 0 then
        if write_bindings(bindings) then
            print("清理完成，共删除 " .. removed_count .. " 个过期账户")
        else
            print("错误: 无法保存清理结果")
        end
    else
        print("没有发现过期账户")
    end
end

-- 主程序
local function main()
    local cmd = arg[1]
    
    if cmd == "list" then
        list_accounts()
    elseif cmd == "set" then
        local token = arg[2]
        local days = tonumber(arg[3])
        if not token or not days then
            print("用法: lua account_manager.lua set <token> <天数>")
            return
        end
        set_expire_time(token, days)
    elseif cmd == "cleanup" then
        cleanup_expired()
    else
        print("账户管理工具")
        print("用法:")
        print("  lua account_manager.lua list           - 显示所有账户状态")
        print("  lua account_manager.lua set <token> <天数>  - 设置账户过期时间")
        print("  lua account_manager.lua cleanup        - 清理过期账户")
    end
end

main()