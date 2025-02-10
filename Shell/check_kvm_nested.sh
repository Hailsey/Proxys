#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以root权限运行此脚本${NC}"
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
  echo -e "\n${YELLOW}[1] 检查CPU虚拟化支持${NC}"
  if grep -E "vmx|svm" /proc/cpuinfo >/dev/null; then
    echo -e "${GREEN}✓ CPU支持虚拟化${NC}"
    if grep -q "vmx" /proc/cpuinfo; then
      echo "  - 检测到Intel VT-x技术"
    fi
    if grep -q "svm" /proc/cpuinfo; then
      echo "  - 检测到AMD-V技术"
    fi
    return 0
  else
    echo -e "${RED}✗ CPU不支持虚拟化${NC}"
    return 1
  fi
}

# 检查KVM模块
check_kvm_modules() {
  echo -e "\n${YELLOW}[2] 检查KVM模块${NC}"
  if lsmod | grep -q "kvm"; then
    echo -e "${GREEN}✓ KVM模块已加载${NC}"
    lsmod | grep kvm
    return 0
  else
    echo -e "${RED}✗ KVM模块未加载${NC}"
    return 1
  fi
}

# 检查嵌套虚拟化状态
check_nested_status() {
  echo -e "\n${YELLOW}[3] 检查嵌套虚拟化状态${NC}"
  local vendor=$(check_cpu_vendor)
  local nested_file=""

  if [ "$vendor" == "intel" ]; then
    nested_file="/sys/module/kvm_intel/parameters/nested"
  elif [ "$vendor" == "amd" ]; then
    nested_file="/sys/module/kvm_amd/parameters/nested"
  else
    echo -e "${RED}✗ 无法确定CPU类型${NC}"
    return 1
  fi

  if [ -f "$nested_file" ]; then
    local status=$(cat "$nested_file")
    if [ "$status" == "Y" ] || [ "$status" == "1" ]; then
      echo -e "${GREEN}✓ 嵌套虚拟化已启用${NC}"
      return 0
    else
      echo -e "${RED}✗ 嵌套虚拟化未启用${NC}"
      return 1
    fi
  else
    echo -e "${RED}✗ 找不到嵌套虚拟化配置文件${NC}"
    return 1
  fi
}

# 启用嵌套虚拟化
enable_nested_virtualization() {
  echo -e "\n${YELLOW}[4] 尝试启用嵌套虚拟化${NC}"
  local vendor=$(check_cpu_vendor)
  local module_name=""
  local conf_file=""

  if [ "$vendor" == "intel" ]; then
    module_name="kvm_intel"
    conf_file="/etc/modprobe.d/kvm-intel.conf"
  elif [ "$vendor" == "amd" ]; then
    module_name="kvm_amd"
    conf_file="/etc/modprobe.d/kvm-amd.conf"
  else
    echo -e "${RED}✗ 无法确定CPU类型${NC}"
    return 1
  fi

  # 创建或更新配置文件
  echo "options $module_name nested=1" >"$conf_file"
  echo "✓ 已创建配置文件: $conf_file"

  # 重新加载模块
  modprobe -r "$module_name"
  modprobe "$module_name"

  # 验证是否成功启用
  if check_nested_status; then
    echo -e "${GREEN}✓ 嵌套虚拟化已成功启用${NC}"
    return 0
  else
    echo -e "${RED}✗ 启用嵌套虚拟化失败${NC}"
    return 1
  fi
}

# 检查BIOS虚拟化设置
check_bios_virtualization() {
  echo -e "\n${YELLOW}[5] 检查BIOS虚拟化设置${NC}"
  if dmesg | grep -i "Virtualization Technology" | grep -i "disabled" >/dev/null; then
    echo -e "${RED}✗ BIOS中的虚拟化支持已禁用${NC}"
    echo "请在BIOS设置中启用以下选项之一："
    echo "  - Intel VT-x"
    echo "  - AMD-V"
    echo "  - SVM Mode"
    return 1
  else
    echo -e "${GREEN}✓ BIOS虚拟化设置正常${NC}"
    return 0
  fi
}

# 主函数
main() {
  echo -e "${YELLOW}开始检查KVM嵌套虚拟化支持...${NC}"

  # 检查root权限
  check_root

  # 运行所有检查
  check_cpu_virtualization
  check_kvm_modules
  check_bios_virtualization
  check_nested_status

  # 如果嵌套虚拟化未启用，询问是否要启用
  if [ $? -ne 0 ]; then
    echo -e "\n${YELLOW}是否要尝试启用嵌套虚拟化? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      enable_nested_virtualization
    fi
  fi

  echo -e "\n${YELLOW}检查完成${NC}"
}

# 执行主函数
main
