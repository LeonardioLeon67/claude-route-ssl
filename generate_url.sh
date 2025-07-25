#!/bin/bash

# 生成随机URL路径的脚本
# 用法: ./generate_url.sh

generate_random_path() {
    # 生成16位随机字符串，包含字母和数字
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1
}

# 生成随机路径
RANDOM_PATH=$(generate_random_path)
echo "生成的随机URL路径: /$RANDOM_PATH/v1/messages"
echo "完整URL: https://api.816981.xyz/$RANDOM_PATH/v1/messages"

# 可选：记录生成的完整base URL到文件
echo "https://api.816981.xyz/$RANDOM_PATH" >> /root/claude-route/claude-route-ssl/generated_paths.txt
echo "URL已记录到 generated_paths.txt"