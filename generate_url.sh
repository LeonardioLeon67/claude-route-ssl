#!/bin/bash

# 生成随机URL路径的脚本
# 用法: ./generate_url.sh

generate_random_path() {
    # 生成16位随机字符串，包含字母和数字
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1
}

# 生成随机路径
RANDOM_PATH=$(generate_random_path)
CURRENT_TIME=$(date +%s)
EXPIRE_TIME=$((CURRENT_TIME + 2592000))  # 30天后的时间戳

echo "生成的随机URL路径: /$RANDOM_PATH/v1/messages"
echo "完整URL: https://api.816981.xyz/$RANDOM_PATH/v1/messages"
echo "过期时间: $(TZ='Asia/Shanghai' date -d @$EXPIRE_TIME +"%Y-%m-%d %H:%M:%S") (北京时间)"

# 记录路径和过期时间到Redis
redis-cli HSET "url:$RANDOM_PATH" "created_at" "$CURRENT_TIME" > /dev/null
redis-cli HSET "url:$RANDOM_PATH" "expire_at" "$EXPIRE_TIME" > /dev/null
redis-cli EXPIRE "url:$RANDOM_PATH" 2592000 > /dev/null  # 设置Redis键30天后过期

# 可选：记录生成的完整base URL到文件
echo "https://api.816981.xyz/$RANDOM_PATH" >> /root/claude-route/claude-route-ssl/generated_paths.txt
echo "URL已记录到 generated_paths.txt"
echo "URL将在30天后过期"