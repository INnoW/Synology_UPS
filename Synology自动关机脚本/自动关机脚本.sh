#!/bin/bash

# ================== 配置变量 ==================
ROUTER_IP_1="192.168.xx.xx"                   # 硬路由
ROUTER_IP_2="192.168.xx.xx"                   # 软路由
PING_COUNT=6                                  # 每次发送 6 个 ICMP 包
PING_FAIL_FILE="/tmp/pingfail_dual"           # 定义一个“失败标记文件”
SCRIPT_DIR=$(dirname "$0")                    # 获取脚本所在目录路径
LOG_FILE="${SCRIPT_DIR}/Network_Logs.log"     # 定义日志文件路径

# ============== 清理日志（30天） ==============
cleanup_log() {
    [[ -f "$LOG_FILE" ]] || return

    local cutoff tmp_file
    cutoff=$(date -d '30 days ago' '+%Y-%m-%d %H:%M:%S')
    tmp_file="${LOG_FILE}.tmp"

    awk -v cutoff="$cutoff" '
        {
            ts = substr($0, 1, 19)
            if (ts >= cutoff) print
        }
    ' "$LOG_FILE" > "$tmp_file" && mv "$tmp_file" "$LOG_FILE"
}

# ================= 日志函数 =================
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# ================= 关机函数 =================
shutdown_synology() {
    log_message "UPS 供电状态告警，剩余电量低于安全阈值，执行停机保护流程"
    synopoweroff
}

# ================== 主函数 ==================
main() {
    cleanup_log

    log_message "监测任务已启动，执行双节点连通性检测"

    # ---------- Ping 检测 ----------
    ping -c "$PING_COUNT" "$ROUTER_IP_1" >/dev/null 2>&1
    result1=$?

    ping -c "$PING_COUNT" "$ROUTER_IP_2" >/dev/null 2>&1
    result2=$?

    # ---------- 判定逻辑 ----------
    if [[ $result1 -eq 0 || $result2 -eq 0 ]]; then
        rm -f "$PING_FAIL_FILE"

        if [[ $result1 -eq 0 && $result2 -eq 0 ]]; then
            log_message "连通性检测完成，双节点均在线，链路状态正常"
        elif [[ $result1 -eq 0 ]]; then
            log_message "连通性检测完成，硬路由 ${ROUTER_IP_1} 在线，软路由 ${ROUTER_IP_2} 连通性异常"
        else
            log_message "连通性检测完成，软路由 ${ROUTER_IP_2} 在线，硬路由 ${ROUTER_IP_1} 连通性异常"
        fi

    else
        log_message "双节点均不可达，硬路由 ${ROUTER_IP_1} 与软路由 ${ROUTER_IP_2} 同时离线，判定电源出现中断"

        if [[ -f "$PING_FAIL_FILE" ]]; then
            log_message "异常状态持续存在，满足停机条件，触发停机保护流程"
            shutdown_synology
            rm -f "$PING_FAIL_FILE"
        else
            touch "$PING_FAIL_FILE"
            log_message "检测到首次全链路中断，已记录异常并进入观察阶段"
        fi
    fi
}

# ================== 执行 ==================
main
exit 0