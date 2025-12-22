#!/bin/bash

#===========================================
#   Cloudflare DDNS 交互式脚本
#   功能：自动检测公网IP并更新DNS记录
#   Github地址：https://github.com/iP3ter/cloudflare-ddns/
#===========================================

# 配置文件路径
CONFIG_FILE="$HOME/.cloudflare_ddns.conf"
LOG_FILE="$HOME/.cloudflare_ddns.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "DEBUG") echo -e "${CYAN}[DEBUG]${NC} ${message}" ;;
    esac
}

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════╗
  ║       Cloudflare DDNS 自动更新脚本            ║
  ║                  v1.0                         ║
  ╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 获取当前公网IP (IPv4)
get_current_ipv4() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://api.ip.sb/ip"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -4 -s --max-time 5 "$service" 2>/dev/null | tr -d '\n')
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# 获取当前公网IP (IPv6)
get_current_ipv6() {
    local ip=""
    local services=(
        "https://api6.ipify.org"
        "https://ifconfig.co"
        "https://api.ip.sb/ip"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -6 -s --max-time 5 "$service" 2>/dev/null | tr -d '\n')
        if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# 验证API Token
verify_api_token() {
    local api_token=$1
    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json")
    
    if echo "$response" | grep -q '"success":true'; then
        return 0
    fi
    return 1
}

# 获取Zone ID
get_zone_id() {
    local api_token=$1
    local domain=$2
    
    # 提取根域名
    local root_domain=$(echo "$domain" | awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}')
    
    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$root_domain" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "$response" | grep -oP '"id":"[^"]+' | head -1 | cut -d'"' -f4
    else
        echo ""
    fi
}

# 获取DNS记录
get_dns_record() {
    local api_token=$1
    local zone_id=$2
    local record_name=$3
    local record_type=$4
    
    local response=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$record_name&type=$record_type" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json")
    
    echo "$response"
}

# 创建DNS记录
create_dns_record() {
    local api_token=$1
    local zone_id=$2
    local record_type=$3
    local record_name=$4
    local ip=$5
    local proxied=$6
    local ttl=$7
    
    local response=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
    
    if echo "$response" | grep -q '"success":true'; then
        return 0
    else
        log "ERROR" "创建失败: $(echo "$response" | grep -oP '"message":"[^"]+"')"
        return 1
    fi
}

# 更新DNS记录
update_dns_record() {
    local api_token=$1
    local zone_id=$2
    local record_id=$3
    local record_type=$4
    local record_name=$5
    local ip=$6
    local proxied=$7
    local ttl=$8
    
    local response=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
    
    if echo "$response" | grep -q '"success":true'; then
        return 0
    else
        log "ERROR" "更新失败: $(echo "$response" | grep -oP '"message":"[^"]+"')"
        return 1
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Cloudflare DDNS 配置文件
# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')

API_TOKEN="$API_TOKEN"
ZONE_ID="$ZONE_ID"
RECORD_NAME="$RECORD_NAME"
RECORD_TYPE="$RECORD_TYPE"
PROXIED=$PROXIED
TTL=$TTL
CHECK_INTERVAL=$CHECK_INTERVAL
EOF
    chmod 600 "$CONFIG_FILE"
    log "INFO" "配置已保存到 $CONFIG_FILE"
}

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# 交互式配置
interactive_setup() {
    show_banner
    echo -e "${CYAN}━━━━━━━━━━━━ 配置向导 ━━━━━━━━━━━━${NC}\n"
    
    # API Token
    echo -e "${YELLOW}[1/6] 请输入 Cloudflare API Token:${NC}"
    echo -e "${CYAN}提示: 在 Cloudflare Dashboard -> My Profile -> API Tokens 创建${NC}"
    echo -e "${CYAN}需要权限: Zone.DNS (Edit)${NC}"
    read -r -s API_TOKEN
    echo ""
    
    if [[ -z "$API_TOKEN" ]]; then
        log "ERROR" "API Token 不能为空"
        return 1
    fi
    
    # 验证Token
    echo -e "${CYAN}正在验证 API Token...${NC}"
    if verify_api_token "$API_TOKEN"; then
        log "INFO" "API Token 验证成功 ✓"
    else
        log "ERROR" "API Token 验证失败"
        return 1
    fi
    
    # 域名
    echo -e "\n${YELLOW}[2/6] 请输入要更新的完整域名:${NC}"
    echo -e "${CYAN}例如: ddns.example.com 或 home.example.com${NC}"
    read -r RECORD_NAME
    
    if [[ -z "$RECORD_NAME" ]]; then
        log "ERROR" "域名不能为空"
        return 1
    fi
    
    # 记录类型
    echo -e "\n${YELLOW}[3/6] 选择记录类型:${NC}"
    echo "  1) A    (IPv4)"
    echo "  2) AAAA (IPv6)"
    read -r type_choice
    
    case $type_choice in
        1) RECORD_TYPE="A" ;;
        2) RECORD_TYPE="AAAA" ;;
        *) RECORD_TYPE="A" ;;
    esac
    log "INFO" "记录类型: $RECORD_TYPE"
    
    # 自动获取 Zone ID
    echo -e "\n${CYAN}正在获取 Zone ID...${NC}"
    ZONE_ID=$(get_zone_id "$API_TOKEN" "$RECORD_NAME")
    
    if [[ -z "$ZONE_ID" ]]; then
        echo -e "${YELLOW}无法自动获取 Zone ID，请手动输入:${NC}"
        read -r ZONE_ID
        if [[ -z "$ZONE_ID" ]]; then
            log "ERROR" "Zone ID 不能为空"
            return 1
        fi
    else
        log "INFO" "Zone ID: $ZONE_ID ✓"
    fi
    
    # 是否启用代理
    echo -e "\n${YELLOW}[4/6] 是否启用 Cloudflare 代理? (y/N):${NC}"
    echo -e "${CYAN}提示: 启用代理可隐藏真实IP，但可能影响某些服务${NC}"
    read -r proxy_choice
    
    if [[ "$proxy_choice" =~ ^[Yy]$ ]]; then
        PROXIED=true
    else
        PROXIED=false
    fi
    
    # TTL设置
    echo -e "\n${YELLOW}[5/6] 设置 TTL (秒, 直接回车使用自动):${NC}"
    echo -e "${CYAN}提示: 1=自动, 最小60秒${NC}"
    read -r ttl_input
    
    if [[ -z "$ttl_input" ]] || [[ "$ttl_input" == "1" ]]; then
        TTL=1
    elif [[ "$ttl_input" =~ ^[0-9]+$ ]] && [[ "$ttl_input" -ge 60 ]]; then
        TTL=$ttl_input
    else
        TTL=1
    fi
    
    # 检查间隔
    echo -e "\n${YELLOW}[6/6] 设置检查间隔 (分钟, 默认10):${NC}"
    read -r interval_input
    
    if [[ -z "$interval_input" ]]; then
        CHECK_INTERVAL=600
    elif [[ "$interval_input" =~ ^[0-9]+$ ]] && [[ "$interval_input" -ge 1 ]]; then
        CHECK_INTERVAL=$((interval_input * 60))
    else
        CHECK_INTERVAL=600
    fi
    
    # 保存配置
    save_config
    
    echo -e "\n${GREEN}━━━━━━━━━━━━ 配置完成 ━━━━━━━━━━━━${NC}"
    show_config
    
    return 0
}

# 执行DDNS更新
do_ddns_update() {
    log "INFO" "开始检查 DNS 更新..."
    
    # 获取当前IP
    local current_ip
    if [[ "$RECORD_TYPE" == "A" ]]; then
        current_ip=$(get_current_ipv4)
    else
        current_ip=$(get_current_ipv6)
    fi
    
    if [[ -z "$current_ip" ]]; then
        log "ERROR" "无法获取当前公网IP"
        return 1
    fi
    
    log "INFO" "当前公网IP: $current_ip"
    
    # 获取DNS记录
    local response=$(get_dns_record "$API_TOKEN" "$ZONE_ID" "$RECORD_NAME" "$RECORD_TYPE")
    local record_id=$(echo "$response" | grep -oP '"id":"[^"]+' | head -1 | cut -d'"' -f4)
    local dns_ip=$(echo "$response" | grep -oP '"content":"[^"]+' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$record_id" ]]; then
        # 记录不存在，创建新记录
        log "INFO" "DNS记录不存在，正在创建..."
        if create_dns_record "$API_TOKEN" "$ZONE_ID" "$RECORD_TYPE" "$RECORD_NAME" "$current_ip" "$PROXIED" "$TTL"; then
            log "INFO" "✓ DNS记录创建成功: $RECORD_NAME -> $current_ip"
        else
            log "ERROR" "DNS记录创建失败"
            return 1
        fi
    elif [[ "$current_ip" == "$dns_ip" ]]; then
        log "INFO" "✓ IP未变化 ($current_ip)，无需更新"
    else
        # IP变化，更新记录
        log "WARN" "IP变化检测: $dns_ip -> $current_ip"
        
        if update_dns_record "$API_TOKEN" "$ZONE_ID" "$record_id" "$RECORD_TYPE" "$RECORD_NAME" "$current_ip" "$PROXIED" "$TTL"; then
            log "INFO" "✓ DNS记录更新成功: $RECORD_NAME -> $current_ip"
        else
            log "ERROR" "DNS记录更新失败"
            return 1
        fi
    fi
    
    return 0
}

# 守护进程模式
daemon_mode() {
    local interval=${CHECK_INTERVAL:-600}
    
    log "INFO" "启动守护进程模式"
    log "INFO" "域名: $RECORD_NAME | 类型: $RECORD_TYPE | 间隔: $((interval/60))分钟"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  DDNS 服务已启动${NC}"
    echo -e "${GREEN}  按 Ctrl+C 停止${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 立即执行一次
    do_ddns_update
    
    while true; do
        local next_time=$(date -d "+${interval} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v+${interval}S '+%Y-%m-%d %H:%M:%S')
        log "INFO" "下次检查: $next_time"
        sleep "$interval"
        do_ddns_update
    done
}

# 查看配置
show_config() {
    if load_config; then
        echo ""
        echo -e "${CYAN}┌────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│           当前配置信息                 │${NC}"
        echo -e "${CYAN}├────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC} API Token : ${GREEN}${API_TOKEN:0:8}...${API_TOKEN: -4}${NC}"
        echo -e "${CYAN}│${NC} Zone ID   : ${GREEN}$ZONE_ID${NC}"
        echo -e "${CYAN}│${NC} 域名      : ${GREEN}$RECORD_NAME${NC}"
        echo -e "${CYAN}│${NC} 记录类型  : ${GREEN}$RECORD_TYPE${NC}"
        echo -e "${CYAN}│${NC} CDN代理   : ${GREEN}$PROXIED${NC}"
        echo -e "${CYAN}│${NC} TTL       : ${GREEN}$([[ $TTL == 1 ]] && echo "自动" || echo "${TTL}秒")${NC}"
        echo -e "${CYAN}│${NC} 检查间隔  : ${GREEN}$((CHECK_INTERVAL/60))分钟${NC}"
        echo -e "${CYAN}└────────────────────────────────────────┘${NC}"
    else
        log "WARN" "未找到配置文件，请先进行配置"
    fi
}

# 创建 systemd 服务
create_systemd_service() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}需要 root 权限，正在使用 sudo...${NC}"
    fi
    
    local script_path=$(readlink -f "$0")
    local service_content="[Unit]
Description=Cloudflare DDNS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$script_path --daemon
Restart=always
RestartSec=30
User=$(whoami)
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target"

    echo "$service_content" | sudo tee /etc/systemd/system/cloudflare-ddns.service > /dev/null
    
    sudo systemctl daemon-reload
    sudo systemctl enable cloudflare-ddns
    sudo systemctl start cloudflare-ddns
    
    log "INFO" "系统服务已创建并启动"
    echo ""
    echo -e "${GREEN}服务管理命令:${NC}"
    echo "  查看状态: sudo systemctl status cloudflare-ddns"
    echo "  停止服务: sudo systemctl stop cloudflare-ddns"
    echo "  启动服务: sudo systemctl start cloudflare-ddns"
    echo "  查看日志: sudo journalctl -u cloudflare-ddns -f"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${BLUE}┌────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│             主菜单                     │${NC}"
    echo -e "${BLUE}├────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC}  1. ${GREEN}配置 DDNS${NC}                         ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  2. ${GREEN}立即更新 DNS${NC}                      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  3. ${GREEN}启动自动更新${NC} (后台运行)           ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  4. ${GREEN}查看当前配置${NC}                      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  5. ${GREEN}查看当前公网IP${NC}                    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  6. ${GREEN}查看运行日志${NC}                      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  7. ${GREEN}设为系统服务${NC} (开机自启)           ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  8. ${GREEN}删除配置${NC}                          ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  0. ${RED}退出${NC}                              ${BLUE}│${NC}"
    echo -e "${BLUE}└────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "${YELLOW}请选择 [0-8]: ${NC}"
}

# 主函数
main() {
    # 检查依赖
    if ! command -v curl &> /dev/null; then
        log "ERROR" "请先安装 curl"
        exit 1
    fi
    
    # 命令行参数处理
    case "$1" in
        --daemon|-d)
            if ! load_config; then
                log "ERROR" "请先运行脚本进行配置"
                exit 1
            fi
            daemon_mode
            ;;
        --update|-u)
            if ! load_config; then
                log "ERROR" "请先运行脚本进行配置"
                exit 1
            fi
            do_ddns_update
            ;;
        --config|-c)
            interactive_setup
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --daemon, -d    启动守护进程模式(自动更新)"
            echo "  --update, -u    立即更新一次"
            echo "  --config, -c    运行配置向导"
            echo "  --help, -h      显示帮助信息"
            echo ""
            echo "不带参数运行将进入交互式菜单"
            exit 0
            ;;
        *)
            # 交互式菜单模式
            while true; do
                show_banner
                if load_config 2>/dev/null; then
                    echo -e "${GREEN}当前配置: $RECORD_NAME ($RECORD_TYPE)${NC}"
                fi
                show_menu
                read -r choice
                
                case $choice in
                    1)
                        interactive_setup
                        read -p "按回车键继续..."
                        ;;
                    2)
                        if load_config; then
                            do_ddns_update
                        else
                            log "WARN" "请先进行配置 (选项1)"
                        fi
                        read -p "按回车键继续..."
                        ;;
                    3)
                        if load_config; then
                            daemon_mode
                        else
                            log "WARN" "请先进行配置 (选项1)"
                            read -p "按回车键继续..."
                        fi
                        ;;
                    4)
                        show_config
                        read -p "按回车键继续..."
                        ;;
                    5)
                        echo ""
                        echo -e "${CYAN}正在获取公网IP...${NC}"
                        ipv4=$(get_current_ipv4)
                        ipv6=$(get_current_ipv6)
                        echo ""
                        [[ -n "$ipv4" ]] && echo -e "${GREEN}IPv4: $ipv4${NC}"
                        [[ -n "$ipv6" ]] && echo -e "${GREEN}IPv6: $ipv6${NC}"
                        [[ -z "$ipv4" && -z "$ipv6" ]] && log "ERROR" "无法获取公网IP"
                        read -p "按回车键继续..."
                        ;;
                    6)
                        if [[ -f "$LOG_FILE" ]]; then
                            echo -e "\n${CYAN}━━━ 最近20条日志 ━━━${NC}\n"
                            tail -20 "$LOG_FILE"
                        else
                            log "WARN" "日志文件不存在"
                        fi
                        read -p "按回车键继续..."
                        ;;
                    7)
                        if load_config; then
                            create_systemd_service
                        else
                            log "WARN" "请先进行配置 (选项1)"
                        fi
                        read -p "按回车键继续..."
                        ;;
                    8)
                        echo -e "${RED}确定要删除配置? (y/N):${NC}"
                        read -r confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            rm -f "$CONFIG_FILE"
                            log "INFO" "配置已删除"
                        fi
                        read -p "按回车键继续..."
                        ;;
                    0)
                        echo -e "${GREEN}再见！${NC}"
                        exit 0
                        ;;
                    *)
                        log "WARN" "无效选项，请重新选择"
                        sleep 1
                        ;;
                esac
            done
            ;;
    esac
}

# 捕获退出信号
trap 'echo ""; log "INFO" "DDNS 服务已停止"; exit 0' SIGINT SIGTERM

# 运行主函数
main "$@"
