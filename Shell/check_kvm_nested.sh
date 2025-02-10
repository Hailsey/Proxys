#!/bin/bash

# 版本信息
VERSION="2.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/kvm_nested_check.log"
BACKUP_DIR="/var/backup/kvm_nested"

# 帮助信息
show_help() {
    cat << EOF
KVM嵌套虚拟化检查工具 v${VERSION}

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -v, --version       显示版本信息
    -c, --check         仅检查不修改
    -e, --enable        启用嵌套虚拟化
    -d, --disable       禁用嵌套虚拟化
    -t, --test          执行性能测试
    -b, --backup        创建配置备份
    -r, --restore       从备份恢复
    -l, --log           显示日志
    -i, --info          显示系统详细信息

示例:
    $0 --check         # 仅检查状态
    $0 --enable        # 启用嵌套虚拟化
    $0 --test          # 执行性能测试

EOF
}

# 日志函数
log() {
    local level=$1
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "$message" >> "$LOG_FILE"
    case $level in
        "INFO") echo -e "${GREEN}$message${NC}" ;;
        "WARN") echo -e "${YELLOW}$message${NC}" ;;
        "ERROR") echo -e "${RED}$message${NC}" ;;
        *) echo -e "$message" ;;
    esac
}

# 检查系统兼容性
check_system_compatibility() {
    log "INFO" "检查系统兼容性..."
    
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log "INFO" "操作系统: $PRETTY_NAME"
    else
        log "WARN" "无法确定操作系统版本"
    fi

    # 检查内核版本
    local kernel_version=$(uname -r)
    log "INFO" "内核版本: $kernel_version"
    
    # 检查系统架构
    local arch=$(uname -m)
    log "INFO" "系统架构: $arch"
    
    # 检查是否为虚拟机
    if systemd-detect-virt &>/dev/null; then
        local virt_type=$(systemd-detect-virt)
        log "WARN" "当前系统运行在 $virt_type 虚拟化环境中"
    fi
}

# 备份函数
create_backup() {
    log "INFO" "创建配置备份..."
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/kvm_config_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    tar -czf "$backup_file" \
        /etc/modprobe.d/kvm*.conf \
        /etc/modules-load.d/kvm*.conf \
        2>/dev/null || true
        
    log "INFO" "备份已保存到: $backup_file"
}

# 恢复备份
restore_backup() {
    log "INFO" "正在恢复备份..."
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1)
    
    if [ -n "$latest_backup" ]; then
        tar -xzf "$latest_backup" -C /
        log "INFO" "已恢复备份: $latest_backup"
    else
        log "ERROR" "未找到备份文件"
        return 1
    fi
}

# 收集硬件信息
collect_hardware_info() {
    log "INFO" "收集硬件信息..."
    
    echo -e "\n${BLUE}CPU信息:${NC}"
    lscpu | grep -E "Model name|Socket|Core|Thread|Virtualization"
    
    echo -e "\n${BLUE}内存信息:${NC}"
    free -h
    
    echo -e "\n${BLUE}PCI设备信息:${NC}"
    lspci | grep -i "vga\|ethernet"
}

# 性能测试
perform_benchmark() {
    log "INFO" "开始性能测试..."
    
    # 检查是否安装性能测试工具
    if ! command -v sysbench &>/dev/null; then
        log "WARN" "未安装sysbench，尝试安装..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y sysbench
        elif command -v yum &>/dev/null; then
            yum install -y sysbench
        else
            log "ERROR" "无法安装sysbench"
            return 1
        fi
    fi
    
    # CPU测试
    log "INFO" "执行CPU性能测试..."
    sysbench cpu --cpu-max-prime=20000 run
    
    # 内存测试
    log "INFO" "执行内存性能测试..."
    sysbench memory --memory-block-size=1K --memory-total-size=1G run
}

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查CPU制造商
check_cpu_vendor() {
    if grep -q "Intel" /proc/cpuinfo; then
        echo "intel"
    elif grep -q "AMD" /proc/cpuinfo; then
        echo "amd"
    else
        echo "unknown"
    fi
}

# 检查CPU虚拟化支持
check_cpu_virtualization() {
    log "INFO" "检查CPU虚拟化支持"
    if grep -E "vmx|svm" /proc/cpuinfo >/dev/null; then
        log "INFO" "CPU支持虚拟化"
        if grep -q "vmx" /proc/cpuinfo; then
            log "INFO" "检测到Intel VT-x技术"
        fi
        if grep -q "svm" /proc/cpuinfo; then
            log "INFO" "检测到AMD-V技术"
        fi
        return 0
    else
        log "ERROR" "CPU不支持虚拟化"
        return 1
    fi
}

# 检查KVM模块
check_kvm_modules() {
    log "INFO" "检查KVM模块"
    if lsmod | grep -q "kvm"; then
        log "INFO" "KVM模块已加载"
        lsmod | grep kvm
        return 0
    else
        log "ERROR" "KVM模块未加载"
        return 1
    fi
}

# 检查嵌套虚拟化状态
check_nested_status() {
    log "INFO" "检查嵌套虚拟化状态"
    local vendor=$(check_cpu_vendor)
    local nested_file=""
    
    if [ "$vendor" == "intel" ]; then
        nested_file="/sys/module/kvm_intel/parameters/nested"
    elif [ "$vendor" == "amd" ]; then
        nested_file="/sys/module/kvm_amd/parameters/nested"
    else
        log "ERROR" "无法确定CPU类型"
        return 1
    fi

    if [ -f "$nested_file" ]; then
        local status=$(cat "$nested_file")
        if [ "$status" == "Y" ] || [ "$status" == "1" ]; then
            log "INFO" "嵌套虚拟化已启用"
            return 0
        else
            log "WARN" "嵌套虚拟化未启用"
            return 1
        fi
    else
        log "ERROR" "找不到嵌套虚拟化配置文件"
        return 1
    fi
}

# 启用嵌套虚拟化
enable_nested_virtualization() {
    log "INFO" "尝试启用嵌套虚拟化"
    local vendor=$(check_cpu_vendor)
    local module_name=""
    local conf_file=""

    # 创建备份
    create_backup

    if [ "$vendor" == "intel" ]; then
        module_name="kvm_intel"
        conf_file="/etc/modprobe.d/kvm-intel.conf"
    elif [ "$vendor" == "amd" ]; then
        module_name="kvm_amd"
        conf_file="/etc/modprobe.d/kvm-amd.conf"
    else
        log "ERROR" "无法确定CPU类型"
        return 1
    fi

    # 创建或更新配置文件
    echo "options $module_name nested=1" > "$conf_file"
    log "INFO" "已创建配置文件: $conf_file"

    # 重新加载模块
    modprobe -r "$module_name"
    modprobe "$module_name"
    
    # 验证是否成功启用
    if check_nested_status; then
        log "INFO" "嵌套虚拟化已成功启用"
        return 0
    else
        log "ERROR" "启用嵌套虚拟化失败"
        return 1
    fi
}

# 禁用嵌套虚拟化
disable_nested_virtualization() {
    log "INFO" "尝试禁用嵌套虚拟化"
    local vendor=$(check_cpu_vendor)
    local module_name=""
    local conf_file=""

    # 创建备份
    create_backup

    if [ "$vendor" == "intel" ]; then
        module_name="kvm_intel"
        conf_file="/etc/modprobe.d/kvm-intel.conf"
    elif [ "$vendor" == "amd" ]; then
        module_name="kvm_amd"
        conf_file="/etc/modprobe.d/kvm-amd.conf"
    else
        log "ERROR" "无法确定CPU类型"
        return 1
    fi

    # 更新配置文件
    echo "options $module_name nested=0" > "$conf_file"
    log "INFO" "已更新配置文件: $conf_file"

    # 重新加载模块
    modprobe -r "$module_name"
    modprobe "$module_name"
    
    # 验证是否成功禁用
    if ! check_nested_status; then
        log "INFO" "嵌套虚拟化已成功禁用"
        return 0
    else
        log "ERROR" "禁用嵌套虚拟化失败"
        return 1
    fi
}

# 显示交互式菜单
show_menu() {
    while true; do
        echo -e "\n${BLUE}KVM嵌套虚拟化管理工具${NC}"
        echo "1. 检查系统状态"
        echo "2. 启用嵌套虚拟化"
        echo "3. 禁用嵌套虚拟化"
        echo "4. 执行性能测试"
        echo "5. 创建配置备份"
        echo "6. 恢复配置备份"
        echo "7. 显示系统信息"
        echo "8. 查看日志"
        echo "9. 退出"
        
        read -p "请选择操作 [1-9]: " choice
        
        case $choice in
            1) check_system_compatibility; check_cpu_virtualization; check_kvm_modules; check_nested_status ;;
            2) enable_nested_virtualization ;;
            3) disable_nested_virtualization ;;
            4) perform_benchmark ;;
            5) create_backup ;;
            6) restore_backup ;;
            7) collect_hardware_info ;;
            8) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || echo "日志文件不存在" ;;
            9) break ;;
            *) echo "无效选择" ;;
        esac
    done
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 处理命令行参数
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}" ;;
        -c|--check) check_system_compatibility; check_cpu_virtualization; check_kvm_modules; check_nested_status ;;
        -e|--enable) enable_nested_virtualization ;;
        -d|--disable) disable_nested_virtualization ;;
        -t|--test) perform_benchmark ;;
        -b|--backup) create_backup ;;
        -r|--restore) restore_backup ;;
        -l|--log) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || echo "日志文件不存在" ;;
        -i|--info) collect_hardware_info ;;
        "") show_menu ;;
        *) show_help ;;
    esac
}

# 执行主函数
main "$@"