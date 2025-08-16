#!/bin/bash

# Claude Route SSL - Redis清理脚本
# 清理Redis中多余的账户数据（不在文件系统中的账户）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ACCOUNT_DIR="$PROJECT_DIR/account"

echo "=== Claude Route SSL Redis清理工具 ==="
echo "项目目录: $PROJECT_DIR"
echo "账户目录: $ACCOUNT_DIR"
echo ""

# 检查Redis连接
echo "检查Redis连接..."
if ! redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "❌ Redis连接失败 (端口6380)"
    exit 1
fi
echo "✅ Redis连接正常"
echo ""

# 1. 收集文件系统中的所有账户
echo "📁 扫描文件系统中的账户..."
declare -A file_accounts

# 扫描medium目录
if [ -d "$ACCOUNT_DIR/medium" ]; then
    for file in "$ACCOUNT_DIR/medium"/*.json; do
        if [ -f "$file" ]; then
            account_name=$(basename "$file" .json)
            file_accounts["medium:$account_name"]=1
            echo "  Medium: $account_name"
        fi
    done
fi

# 扫描high目录
if [ -d "$ACCOUNT_DIR/high" ]; then
    for file in "$ACCOUNT_DIR/high"/*.json; do
        if [ -f "$file" ]; then
            account_name=$(basename "$file" .json)
            file_accounts["high:$account_name"]=1
            echo "  High: $account_name"
        fi
    done
fi

# 扫描supreme目录
if [ -d "$ACCOUNT_DIR/supreme" ]; then
    for file in "$ACCOUNT_DIR/supreme"/*.json; do
        if [ -f "$file" ]; then
            account_name=$(basename "$file" .json)
            file_accounts["supreme:$account_name"]=1
            echo "  Supreme: $account_name"
        fi
    done
fi

echo ""
echo "文件系统中共找到 ${#file_accounts[@]} 个账户"
echo ""

# 2. 检查Redis中的多余账户数据
echo "🔍 检查Redis中的多余数据..."
declare -a cleanup_keys

# 检查slot数据
echo "检查slot数据..."
for tier in medium high supreme; do
    # 获取该级别的所有slot键
    redis_slots=$(redis-cli -p 6380 --scan --pattern "${tier}_pool:slots:*" 2>/dev/null || true)
    
    if [ -n "$redis_slots" ]; then
        while IFS= read -r slot_key; do
            if [ -n "$slot_key" ]; then
                # 提取账户名
                account_name=$(echo "$slot_key" | sed "s/^${tier}_pool:slots://")
                
                # 检查文件系统中是否存在
                if [ -z "${file_accounts["$tier:$account_name"]}" ]; then
                    echo "  ❌ 多余slot: $slot_key (账户: $tier/$account_name 不存在)"
                    cleanup_keys+=("$slot_key")
                fi
            fi
        done <<< "$redis_slots"
    fi
done

# 检查黑名单数据
echo "检查黑名单数据..."
for tier in medium high supreme; do
    blacklist_keys=$(redis-cli -p 6380 --scan --pattern "account_blacklist:${tier}:*" 2>/dev/null || true)
    
    if [ -n "$blacklist_keys" ]; then
        while IFS= read -r blacklist_key; do
            if [ -n "$blacklist_key" ]; then
                # 提取账户名
                account_name=$(echo "$blacklist_key" | sed "s/^account_blacklist:${tier}://")
                
                # 检查文件系统中是否存在
                if [ -z "${file_accounts["$tier:$account_name"]}" ]; then
                    echo "  ❌ 多余黑名单: $blacklist_key (账户: $tier/$account_name 不存在)"
                    cleanup_keys+=("$blacklist_key")
                fi
            fi
        done <<< "$blacklist_keys"
    fi
done

# 检查永久绑定数据
echo "检查永久绑定数据..."
for tier in medium high supreme; do
    binding_data=$(redis-cli -p 6380 hgetall "permanent_binding:$tier" 2>/dev/null || true)
    
    if [ -n "$binding_data" ]; then
        # 解析hash数据 (key value key value...)
        declare -a binding_array
        readarray -t binding_array <<< "$binding_data"
        
        for ((i=1; i<${#binding_array[@]}; i+=2)); do
            account_name="${binding_array[i]}"
            
            if [ -n "$account_name" ] && [ -z "${file_accounts["$tier:$account_name"]}" ]; then
                client_key="${binding_array[i-1]}"
                echo "  ❌ 多余绑定: $tier/$account_name <- $client_key (账户不存在)"
                # 记录需要删除的hash字段
                cleanup_keys+=("HDEL:permanent_binding:$tier:$client_key")
            fi
        done
    fi
done

# 检查账户相关的其他可能的Redis键
echo "检查其他账户相关数据..."
for tier in medium high supreme; do
    for account_key in $(printf '%s\n' "${!file_accounts[@]}" | grep "^$tier:"); do
        account_name="${account_key#$tier:}"
        
        # 检查可能存在的其他Redis键模式
        other_keys=$(redis-cli -p 6380 --scan --pattern "*:${tier}:${account_name}" 2>/dev/null || true)
        other_keys2=$(redis-cli -p 6380 --scan --pattern "*:${account_name}:${tier}" 2>/dev/null || true)
        
        # 这里可以根据实际Redis键模式继续扩展检查
    done
done

echo ""

# 3. 执行清理
if [ ${#cleanup_keys[@]} -eq 0 ]; then
    echo "✅ 未发现需要清理的多余数据"
    exit 0
fi

echo "发现 ${#cleanup_keys[@]} 个需要清理的Redis键:"
for key in "${cleanup_keys[@]}"; do
    echo "  - $key"
done
echo ""

read -p "确认要清理这些多余的Redis数据吗? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 开始清理..."
    
    success_count=0
    error_count=0
    
    for key in "${cleanup_keys[@]}"; do
        if [[ "$key" == HDEL:* ]]; then
            # 处理HDEL命令
            hash_key=$(echo "$key" | cut -d: -f2-3)
            field=$(echo "$key" | cut -d: -f4)
            
            if redis-cli -p 6380 hdel "$hash_key" "$field" > /dev/null 2>&1; then
                echo "  ✅ 已删除hash字段: $hash_key -> $field"
                ((success_count++))
            else
                echo "  ❌ 删除失败: $hash_key -> $field"
                ((error_count++))
            fi
        else
            # 处理普通DEL命令
            if redis-cli -p 6380 del "$key" > /dev/null 2>&1; then
                echo "  ✅ 已删除: $key"
                ((success_count++))
            else
                echo "  ❌ 删除失败: $key"
                ((error_count++))
            fi
        fi
    done
    
    echo ""
    echo "清理完成: ✅ $success_count 成功, ❌ $error_count 失败"
    
    if [ $error_count -eq 0 ]; then
        echo "🎉 所有多余的Redis数据已成功清理!"
    fi
else
    echo "❌ 用户取消了清理操作"
fi