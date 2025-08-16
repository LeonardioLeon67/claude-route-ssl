#!/bin/bash

# 过期时间管理脚本

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_PATH="/home/leon/claude-route-ssl/claude-route-ssl/update-expire-dates.py"
LOG_PATH="/home/leon/claude-route-ssl/claude-route-ssl/logs/expire-update.log"

show_help() {
    echo -e "${CYAN}=== 产品过期时间管理工具 ===${NC}"
    echo ""
    echo "使用方法:"
    echo "  ./expire-manage.sh [command]"
    echo ""
    echo "可用命令:"
    echo "  status   - 查看定时任务状态"
    echo "  run      - 立即执行更新"
    echo "  logs     - 查看最近日志"
    echo "  tail     - 实时查看日志"
    echo "  help     - 显示此帮助"
    echo ""
}

case "$1" in
    status)
        echo -e "${CYAN}📅 定时任务状态${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        systemctl status expire-update.timer --no-pager
        echo ""
        echo -e "${CYAN}下次执行时间:${NC}"
        systemctl list-timers expire-update.timer --no-pager
        ;;
        
    run)
        echo -e "${GREEN}🔄 立即执行更新...${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        python3 "$SCRIPT_PATH"
        echo ""
        echo -e "${GREEN}✅ 更新完成${NC}"
        ;;
        
    logs)
        echo -e "${BLUE}📋 最近50行日志${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if [ -f "$LOG_PATH" ]; then
            tail -50 "$LOG_PATH"
        else
            echo -e "${YELLOW}日志文件尚未创建${NC}"
        fi
        ;;
        
    tail)
        echo -e "${BLUE}📋 实时查看日志 (Ctrl+C退出)${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        tail -f "$LOG_PATH"
        ;;
        
    help|"")
        show_help
        ;;
        
    *)
        echo -e "${RED}错误: 未知命令 '$1'${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac