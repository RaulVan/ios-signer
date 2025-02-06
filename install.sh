#!/bin/bash

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 定义安装配置
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="ios_sign"
SOURCE_SCRIPT="sign_ios_app.sh"

# 辅助函数
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

# 环境检查函数
check_environment() {
    # 检查是否为 macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "此脚本只能在 macOS 系统上运行"
        exit 1
    fi
    
    # 检查 Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        print_warning "未检测到 Xcode Command Line Tools"
        print_warning "请运行 xcode-select --install 安装"
        exit 1
    fi

    # 检查源文件是否存在
    if [ ! -f "$SOURCE_SCRIPT" ]; then
        print_error "找不到源文件: $SOURCE_SCRIPT"
        exit 1
    fi
}

# 权限检查函数
check_permissions() {
    if ! sudo -n true 2>/dev/null; then
        print_warning "需要管理员权限来安装"
        print_warning "请输入密码:"
    fi
}

# 安装函数
install_script() {
    echo "开始安装..."
    
    # 创建安装目录
    if [ ! -d "$INSTALL_DIR" ]; then
        if ! sudo mkdir -p "$INSTALL_DIR"; then
            print_error "创建目录 $INSTALL_DIR 失败"
            exit 1
        fi
        print_success "创建目录 $INSTALL_DIR"
    fi

    # 复制脚本
    if ! sudo cp "$SOURCE_SCRIPT" "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "复制脚本失败"
        exit 1
    fi
    print_success "复制脚本到 $INSTALL_DIR/$SCRIPT_NAME"

    # 设置权限
    if ! sudo chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "设置执行权限失败"
        exit 1
    fi
    print_success "设置执行权限"

    if ! sudo chown root:wheel "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "设置所有者失败"
        exit 1
    fi
    print_success "设置所有者"
}

# 验证安装函数
verify_installation() {
    echo "验证安装..."
    
    if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        print_error "安装验证失败：找不到文件 $INSTALL_DIR/$SCRIPT_NAME"
        exit 1
    fi
    
    if [ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        print_error "安装验证失败：文件没有执行权限"
        exit 1
    fi
    
    print_success "安装验证成功"
    echo
    echo -e "${GREEN}iOS 签名工具已成功安装！${NC}"
    echo "使用方法: $SCRIPT_NAME -h"
}

# 清理函数
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "安装过程中发生错误，正在清理..."
        # 如果安装失败，删除已安装的文件
        sudo rm -f "$INSTALL_DIR/$SCRIPT_NAME" 2>/dev/null
    fi
}

# 卸载函数
uninstall() {
    echo "卸载 iOS 签名工具..."
    
    if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        if ! sudo rm -f "$INSTALL_DIR/$SCRIPT_NAME"; then
            print_error "卸载失败"
            exit 1
        fi
        print_success "卸载成功"
    else
        print_warning "未找到已安装的脚本"
    fi
}

# 主函数
main() {
    # 处理命令行参数
    if [ "$1" = "--uninstall" ]; then
        uninstall
        exit 0
    fi

    echo "开始安装 iOS 签名工具..."
    echo

    # 设置清理钩子
    trap cleanup EXIT

    # 执行安装步骤
    check_environment
    check_permissions
    install_script
    verify_installation
}

# 执行主函数
main "$@" 