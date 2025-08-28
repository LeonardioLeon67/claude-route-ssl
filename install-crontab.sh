#!/bin/bash

# 安装定时任务脚本
# 每天北京时间1:00和13:00执行update-expire-dates.py

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Claude Route SSL 定时任务安装 ===${NC}"
echo ""

# 检查Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python3 is not installed${NC}"
    exit 1
fi

# 检查脚本文件
SCRIPT_PATH="/home/leon/claude-route-ssl/claude-route-ssl/update-expire-dates.py"
if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "${RED}Error: Script not found: $SCRIPT_PATH${NC}"
    exit 1
fi

# 创建日志目录
LOG_DIR="/home/leon/claude-route-ssl/claude-route-ssl/logs"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}Created log directory: $LOG_DIR${NC}"
fi

# 获取当前时区
TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}' || echo "Unknown")
echo -e "${BLUE}Current timezone: $TIMEZONE${NC}"

# 根据时区设置cron时间
if [[ "$TIMEZONE" == *"Amsterdam"* ]] || [[ "$TIMEZONE" == *"CEST"* ]]; then
    # CEST时区 (UTC+2)
    echo -e "${YELLOW}Using CEST timezone configuration${NC}"
    CRON_LINES="# Claude Route SSL - Update expire dates (Beijing time 1:00 and 13:00)
0 19 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1
0 7 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1"
elif [[ "$TIMEZONE" == *"Shanghai"* ]] || [[ "$TIMEZONE" == *"Beijing"* ]] || [[ "$TIMEZONE" == *"CST"* ]]; then
    # 北京时间
    echo -e "${YELLOW}Using Beijing timezone configuration${NC}"
    CRON_LINES="# Claude Route SSL - Update expire dates (Beijing time 1:00 and 13:00)
0 1 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1
0 13 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1"
else
    # 默认使用UTC
    echo -e "${YELLOW}Using UTC timezone configuration${NC}"
    CRON_LINES="# Claude Route SSL - Update expire dates (Beijing time 1:00 and 13:00)
0 17 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1
0 5 * * * /usr/bin/python3 $SCRIPT_PATH >> $LOG_DIR/cron.log 2>&1"
fi

# 检查crontab是否已存在这些任务
if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    echo -e "${YELLOW}Warning: Crontab entries already exist for this script${NC}"
    echo "Current entries:"
    crontab -l | grep "$SCRIPT_PATH"
    echo ""
    read -p "Do you want to replace them? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled${NC}"
        exit 0
    fi
    # 删除旧的条目
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH") | crontab -
fi

# 添加新的crontab条目
(crontab -l 2>/dev/null; echo ""; echo "$CRON_LINES") | crontab -

echo ""
echo -e "${GREEN}✓ Crontab installed successfully!${NC}"
echo ""
echo "Installed cron jobs:"
echo "$CRON_LINES"
echo ""
echo "Execution times (Beijing time):"
echo -e "${BLUE}  - 01:00 AM (凌晨1点)${NC}"
echo -e "${BLUE}  - 01:00 PM (下午1点)${NC}"
echo ""
echo "Commands to manage:"
echo -e "${YELLOW}  crontab -l${NC}         # List current crontab"
echo -e "${YELLOW}  crontab -e${NC}         # Edit crontab"
echo -e "${YELLOW}  crontab -r${NC}         # Remove all crontab"
echo ""
echo "Test the script manually:"
echo -e "${GREEN}  python3 $SCRIPT_PATH${NC}"
echo ""
echo "View logs:"
echo -e "${GREEN}  tail -f $LOG_DIR/cron.log${NC}"
echo -e "${GREEN}  tail -f $LOG_DIR/expire-update.log${NC}"