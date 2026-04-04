#!/bin/bash

# 定义颜色输出 / Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 定义安装配置 / Define installation config
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="ios_sign"
SOURCE_SCRIPT="sign_ios_app.sh"

# 检测系统语言 / Detect system language
LANG=$(defaults read -g AppleLocale)
if [[ $LANG == *"zh"* ]]; then
    DEFAULT_LANG="zh"
else
    DEFAULT_LANG="en"
fi

# 多语言消息函数 / Multilingual message functions
msg() {
    local key=$1
    case $key in
        "install_start")
            echo "开始安装 iOS 签名工具... / Starting iOS Sign Tool installation..."
            ;;
        "create_dir")
            echo "创建目录 / Creating directory"
            ;;
        "copy_script")
            echo "复制脚本到 / Copying script to"
            ;;
        "set_perm")
            echo "设置执行权限 / Setting execution permissions"
            ;;
        "set_owner")
            echo "设置所有者 / Setting owner"
            ;;
        "verify")
            echo "验证安装... / Verifying installation..."
            ;;
        "verify_success")
            echo "安装验证成功 / Installation verified successfully"
            ;;
        "install_complete")
            echo "iOS 签名工具已成功安装！/ iOS Sign Tool has been installed successfully!"
            ;;
        "error_not_macos")
            echo "此脚本只能在 macOS 系统上运行 / This script can only run on macOS"
            ;;
        "error_no_xcode")
            echo "未检测到 Xcode Command Line Tools / Xcode Command Line Tools not detected"
            ;;
        "error_install_xcode")
            echo "请运行 xcode-select --install 安装 / Please run xcode-select --install to install"
            ;;
        "error_no_source")
            echo "找不到源文件 / Source file not found"
            ;;
        "error_need_sudo")
            echo "需要管理员权限来安装 / Administrator privileges required for installation"
            ;;
        "error_enter_pass")
            echo "请输入密码: / Please enter your password:"
            ;;
        *)
            echo "$key"
            ;;
    esac
}

# 辅助函数 / Helper functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

# 环境检查函数 / Environment check function
check_environment() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "$(msg error_not_macos)"
        exit 1
    fi
    
    if ! xcode-select -p &>/dev/null; then
        print_warning "$(msg error_no_xcode)"
        print_warning "$(msg error_install_xcode)"
        exit 1
    fi

    if [ ! -f "$SOURCE_SCRIPT" ]; then
        print_error "$(msg error_no_source): $SOURCE_SCRIPT"
        exit 1
    fi
}

# 权限检查函数 / Permission check function
check_permissions() {
    if ! sudo -n true 2>/dev/null; then
        print_warning "$(msg error_need_sudo)"
        print_warning "$(msg error_enter_pass)"
    fi
}

# 安装函数 / Installation function
install_script() {
    echo "$(msg install_start)"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        if ! sudo mkdir -p "$INSTALL_DIR"; then
            print_error "$(msg create_dir) $INSTALL_DIR"
            exit 1
        fi
        print_success "$(msg create_dir) $INSTALL_DIR"
    fi

    if ! sudo cp "$SOURCE_SCRIPT" "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "$(msg copy_script) $INSTALL_DIR/$SCRIPT_NAME"
        exit 1
    fi
    print_success "$(msg copy_script) $INSTALL_DIR/$SCRIPT_NAME"

    if ! sudo chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "$(msg set_perm)"
        exit 1
    fi
    print_success "$(msg set_perm)"

    if ! sudo chown root:wheel "$INSTALL_DIR/$SCRIPT_NAME"; then
        print_error "$(msg set_owner)"
        exit 1
    fi
    print_success "$(msg set_owner)"
}

# 验证安装函数 / Verify installation function
verify_installation() {
    echo "$(msg verify)"
    
    if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        print_error "$(msg verify)"
        exit 1
    fi
    
    if [ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        print_error "$(msg verify)"
        exit 1
    fi
    
    print_success "$(msg verify_success)"
    echo
    print_success "$(msg install_complete)"
    echo "ios_sign -h"
}

# 清理函数 / Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "安装过程中发生错误，正在清理... / Error occurred during installation, cleaning up..."
        sudo rm -f "$INSTALL_DIR/$SCRIPT_NAME" 2>/dev/null
    fi
}

# 卸载函数 / Uninstall function
uninstall() {
    echo "卸载 iOS 签名工具... / Uninstalling iOS Sign Tool..."
    
    if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        if ! sudo rm -f "$INSTALL_DIR/$SCRIPT_NAME"; then
            print_error "卸载失败 / Uninstallation failed"
            exit 1
        fi
        print_success "卸载成功 / Uninstallation successful"
    else
        print_warning "未找到已安装的脚本 / Installed script not found"
    fi
}

# 主函数 / Main function
main() {
    if [ "$1" = "--uninstall" ]; then
        uninstall
        exit 0
    fi

    echo "$(msg install_start)"
    echo

    trap cleanup EXIT

    check_environment
    check_permissions
    install_script
    verify_installation
}

# 执行主函数 / Execute main function
main "$@" 