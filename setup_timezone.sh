#!/bin/bash

# 设置系统时区为北京时间的脚本

echo "正在设置系统时区为北京时间..."

# 设置时区为Asia/Shanghai
timedatectl set-timezone Asia/Shanghai

# 显示当前时间设置
echo "时区设置完成！"
echo "当前系统时间信息："
timedatectl

echo ""
echo "当前北京时间："
date "+%Y-%m-%d %H:%M:%S"