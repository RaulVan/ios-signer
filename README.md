# iOS App Resign Tool / iOS 应用重签名工具

English | 简体中文

> This project's scripts and documentation are generated by Cursor AI.
> 该项目脚本代码以及文档使用 Cursor AI 生成。

---

# English Documentation

## Introduction

This is a command-line tool for iOS application re-signing, primarily used for enterprise application re-signing and distribution. It helps developers and enterprises quickly complete the iOS application re-signing process, supporting complex applications with extensions.

### Key Features
- Support for IPA file re-signing
- Automatic handling of App Extensions
- Automatic handling of Embedded Frameworks
- Preserve all components of the original IPA
- Automatic certificate information extraction and validation
- Detailed logging output

### Technical Features
- Written in Shell script, no additional dependencies required
- Provides automatic installation script for easy deployment
- Supports command-line parameters for automation integration
- Includes comprehensive error handling and logging

## Documentation

### 1. Installation

#### 1.1 Using Installation Script (Recommended)

An automatic installation script `install.sh` is provided to complete all installation steps:

```bash
# Add execution permission
chmod +x install.sh

# Execute installation
./install.sh
```

Installation Script Features:
- Automatic system environment check (macOS and Xcode tools)
- Automatic permission and dependency handling
- Automatic installation verification
- Uninstallation support

Uninstall command:
```bash
./install.sh --uninstall
```

#### 1.2 Manual Installation (Optional)

If you prefer not to use the installation script, you can install manually:

##### 1.2.1 Create System Directory
```bash
sudo mkdir -p /usr/local/bin
```

##### 1.2.2 Copy Script to System Directory
```bash
sudo cp sign_ios_app.sh /usr/local/bin/ios_sign
```

##### 1.2.3 Set Correct Permissions
```bash
# Add execution permission
sudo chmod 755 /usr/local/bin/ios_sign

# Set owner to root
sudo chown root:wheel /usr/local/bin/ios_sign
```

##### 1.2.4 Verify Installation
```bash
# Check if command is available
which ios_sign

# Should output: /usr/local/bin/ios_sign
```

### 2. Usage

#### 2.1 Command Format
```bash
ios_sign -f <ipa_file> -p <profile_file> -v <version> -b <build>
```

#### 2.2 Parameters
- `-f, --file`: IPA file path to be signed
- `-p, --profile`: Provisioning profile (.mobileprovision) path
- `-v, --version`: Version number (e.g., 1.0)
- `-b, --build`: Build number (e.g., 1)
- `-h, --help`: Show help information

#### 2.3 Examples
```bash
# Show help information
ios_sign -h

# Sign application
ios_sign -f MyApp.ipa -p MyApp.mobileprovision -v 1.0 -b 1
```

### 3. Prerequisites

#### 3.1 Requirements
- Ensure Xcode Command Line Tools is installed
- Ensure signing certificate is imported to Keychain
- Ensure valid provisioning profile (.mobileprovision) is available

#### 3.2 File Requirements
- IPA file must exist and be readable
- Provisioning profile must exist and be valid
- If app contains extensions, corresponding profiles should be in the same directory

#### 3.3 Permission Requirements
- Sufficient permissions to access Keychain
- Write permissions to target directory

### 4. Output

#### 4.1 Generated Files
- Signed IPA filename format: `version-build-timestamp.ipa`
- Example: `1.0-3-20250206_122425.ipa`

#### 4.2 Log Information
- Shows detailed signing process
- Shows all signed components (main app, frameworks, plugins)
- Shows final verification results

### 5. Troubleshooting

#### 5.1 Common Errors
- `command not found`: Check installation path and permissions
- `no identity found`: Check if certificate is properly imported to Keychain
- `signing verification failed`: Check if certificate and profile match

#### 5.2 Solutions
- Run `security find-identity -v -p codesigning` to view available signing certificates
- Ensure certificate name in profile matches exactly with Keychain
- Check if IPA file is complete and not corrupted

### 6. Maintenance

#### 6.1 Update Using Installation Script
```bash
# Update installation
./install.sh

# Uninstall old version
./install.sh --uninstall
```

#### 6.2 Manual Update
```bash
# Update script content
sudo vim /usr/local/bin/ios_sign

# Or copy new version
sudo cp new_sign_ios_app.sh /usr/local/bin/ios_sign
```

#### 6.3 Uninstallation
```bash
# Uninstall using installation script
./install.sh --uninstall

# Or manual uninstall
sudo rm /usr/local/bin/ios_sign
```

### 7. Features

#### 7.1 Automatic Processing
- Automatically identifies and preserves all folders from original IPA (Payload, SwiftSupport, Symbols, etc.)
- Automatically extracts certificate information from profile
- Automatically handles extension signing

#### 7.2 Security Features
- Uses temporary directory for processing, avoiding original file pollution
- Automatic cleanup of temporary files
- Complete signing verification process

#### 7.3 Error Handling
- Detailed error messages
- Automatic cleanup on failure
- Signing integrity verification

---

# 中文文档

## 项目介绍

这是一个用于 iOS 应用重签名的命令行工具，主要用于企业级应用的重新签名和分发。它可以帮助开发者和企业快速完成 iOS 应用的重签名过程，支持处理包含扩展插件的复杂应用。

### 主要功能
- 支持 IPA 文件的重签名
- 自动处理应用扩展（App Extensions）
- 自动处理嵌入式框架（Embedded Frameworks）
- 保留原始 IPA 的所有组件
- 自动提取和验证证书信息
- 提供详细的日志输出

### 技术特点
- 使用 Shell 脚本编写，无需额外依赖
- 提供自动安装脚本，便于部署
- 支持命令行参数，便于集成到自动化流程
- 包含完整的错误处理和日志记录

## 使用文档

### 1. 安装步骤

#### 1.1 使用安装脚本（推荐）

提供了自动安装脚本 `install.sh`，可以自动完成所有安装步骤：

```bash
# 添加执行权限
chmod +x install.sh

# 执行安装
./install.sh
```

安装脚本特性：
- 自动检查系统环境（macOS 和 Xcode 工具）
- 自动处理权限和依赖
- 自动验证安装结果
- 提供卸载功能

卸载命令：
```bash
./install.sh --uninstall
```

#### 1.2 手动安装（可选）

如果您不想使用安装脚本，也可以手动安装：

##### 1.2.1 创建系统级目录
```bash
sudo mkdir -p /usr/local/bin
```

##### 1.2.2 复制脚本到系统目录
```bash
sudo cp sign_ios_app.sh /usr/local/bin/ios_sign
```

##### 1.2.3 设置正确的权限
```bash
# 添加执行权限
sudo chmod 755 /usr/local/bin/ios_sign

# 设置所有者为root
sudo chown root:wheel /usr/local/bin/ios_sign
```

##### 1.2.4 验证安装
```bash
# 检查命令是否可用
which ios_sign

# 应该输出：/usr/local/bin/ios_sign
```

### 2. 使用方法

#### 2.1 命令格式
```bash
ios_sign -f <ipa文件> -p <描述文件> -v <版本号> -b <构建号>
```

#### 2.2 参数说明
- `-f, --file`: 要签名的IPA文件路径
- `-p, --profile`: 描述文件(.mobileprovision)路径
- `-v, --version`: 版本号（如：1.0）
- `-b, --build`: 构建号（如：1）
- `-h, --help`: 显示帮助信息

#### 2.3 使用示例
```bash
# 显示帮助信息
ios_sign -h

# 签名应用
ios_sign -f MyApp.ipa -p MyApp.mobileprovision -v 1.0 -b 1
```

### 3. 注意事项

#### 3.1 前置条件
- 确保系统已安装 Xcode 命令行工具
- 确保签名证书已导入到钥匙串中
- 确保有正确的描述文件(.mobileprovision)

#### 3.2 文件要求
- IPA文件必须存在且可读
- 描述文件必须存在且有效
- 如果应用包含扩展插件，相应的描述文件应该位于同一目录下

#### 3.3 权限要求
- 需要有足够的权限访问钥匙串
- 需要有目标目录的写入权限

### 4. 输出说明

#### 4.1 生成文件
- 签名后的IPA文件名格式：`版本号-构建号-时间戳.ipa`
- 例如：`1.0-3-20250206_122425.ipa`

#### 4.2 日志信息
- 显示签名过程的详细信息
- 显示所有签名的组件（主程序、框架、插件等）
- 显示最终的验证结果

### 5. 故障排除

#### 5.1 常见错误
- `command not found`: 检查安装路径和权限
- `no identity found`: 检查证书是否正确导入钥匙串
- `验证签名失败`: 检查证书和描述文件是否匹配

#### 5.2 解决方法
- 运行 `security find-identity -v -p codesigning` 查看可用的签名证书
- 确保描述文件中的证书名称与钥匙串中的完全匹配
- 检查 IPA 文件是否完整且未损坏

### 6. 更新维护

#### 6.1 使用安装脚本更新
```bash
# 更新安装
./install.sh

# 卸载旧版本
./install.sh --uninstall
```

#### 6.2 手动更新
```bash
# 更新脚本内容
sudo vim /usr/local/bin/ios_sign

# 或者重新复制新版本
sudo cp new_sign_ios_app.sh /usr/local/bin/ios_sign
```

#### 6.3 卸载
```bash
# 使用安装脚本卸载
./install.sh --uninstall

# 或者手动卸载
sudo rm /usr/local/bin/ios_sign
```

### 7. 功能特性

#### 7.1 自动处理
- 自动识别并保留原始IPA中的所有文件夹（如 Payload、SwiftSupport、Symbols 等）
- 自动从描述文件中提取证书信息
- 自动处理扩展插件的签名

#### 7.2 安全特性
- 使用临时目录处理文件，避免污染原始文件
- 自动清理临时文件
- 完整的签名验证流程

#### 7.3 错误处理
- 详细的错误提示
- 失败时自动清理
- 验证签名完整性 