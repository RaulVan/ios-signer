#!/bin/bash

# 显示使用方法
show_usage() {
    echo "使用方法: $(basename $0) [选项]"
    echo "选项:"
    echo "  -f, --file <ipa文件>           要签名的IPA文件 (必需)"
    echo "  -p, --profile <描述文件>       描述文件路径 (必需)"
    echo "  -v, --version <版本号>         版本号 (必需)"
    echo "  -b, --build <构建号>          构建号 (必需)"
    echo "  -h, --help                    显示此帮助信息"
    echo
    echo "示例:"
    echo "  $(basename $0) -f app.ipa -p profile.mobileprovision -v 1.0 -b 1"
    exit 1
}

# 获取当前工作目录
CURRENT_DIR="$(pwd)"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            SOURCE_IPA="$2"
            shift 2
            ;;
        -p|--profile)
            PROVISIONING_PROFILE="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -b|--build)
            BUILD="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "错误: 未知参数 $1"
            show_usage
            ;;
    esac
done

# 检查必需参数
if [ -z "$SOURCE_IPA" ] || [ -z "$PROVISIONING_PROFILE" ] || [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "错误: 缺少必需参数"
    show_usage
fi

# 检查文件是否存在
if [ ! -f "$SOURCE_IPA" ]; then
    echo "错误: 找不到源IPA文件: $SOURCE_IPA"
    exit 1
fi

if [ ! -f "$PROVISIONING_PROFILE" ]; then
    echo "错误: 找不到描述文件: $PROVISIONING_PROFILE"
    exit 1
fi

# 创建临时工作目录
TEMP_DIR="temp_signing_$(date +%s)"
cleanup() {
    echo "清理工作目录..."
    rm -f profile.plist entitlements.plist
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# 设置退出时的清理
trap 'cleanup' EXIT
trap 'cleanup' ERR

# 定义变量
CURRENT_TIME=$(date "+%Y%m%d_%H%M%S")
IPA_NAME="${VERSION}-${BUILD}-${CURRENT_TIME}.ipa"

# 创建并进入临时工作目录
echo "创建临时工作目录: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# 解压IPA文件
echo "解压IPA文件..."
unzip -q "../$SOURCE_IPA"

# 检查解压后的文件夹
echo "检查解压后的文件夹结构..."
# 使用find命令查找所有一级目录
FOLDERS_TO_PACK=()
while IFS= read -r folder; do
    folder_name=$(basename "$folder")
    echo "发现文件夹: $folder_name"
    FOLDERS_TO_PACK+=("$folder_name")
done < <(find . -maxdepth 1 -type d ! -path "." | sort)

if [ ${#FOLDERS_TO_PACK[@]} -eq 0 ]; then
    echo "错误: 解压后没有找到任何文件夹"
    exit 1
fi

# 获取实际的应用路径
APP_PATH=$(find . -name "*.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "错误: 在IPA中找不到.app文件"
    cd ..
    exit 1
fi

echo "找到应用程序包: $APP_PATH"

# 从描述文件中获取信息
echo "从描述文件中获取信息..."

# 解析描述文件获取信息
security cms -D -i "../$PROVISIONING_PROFILE" > profile.plist

# 获取证书类型
CERT_TYPE=$(/usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:0" profile.plist | openssl x509 -inform DER -noout -subject | grep "CN=" | sed 's/.*CN=\([^,]*\).*/\1/')
echo "证书类型: $CERT_TYPE"

TEAM_NAME=$(/usr/libexec/PlistBuddy -c "Print :TeamName" profile.plist)
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" profile.plist)
BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" profile.plist | sed "s/^$TEAM_ID.//")

# 使用从描述文件中获取的证书类型
SIGNING_CERTIFICATE="$CERT_TYPE"

echo "获取到的信息："
echo "团队名称: $TEAM_NAME"
echo "团队ID: $TEAM_ID"
echo "Bundle ID: $BUNDLE_IDENTIFIER"
echo "签名证书: $SIGNING_CERTIFICATE"

# 检查证书是否存在
echo "检查证书是否存在..."
if security find-identity -v -p codesigning | grep "$SIGNING_CERTIFICATE" > /dev/null; then
    echo "✅ 找到签名证书: $SIGNING_CERTIFICATE"
else
    echo "❌ 错误: 找不到有效的签名证书"
    echo "尝试查找的证书名称:"
    echo "$SIGNING_CERTIFICATE"
    echo
    echo "请确保以下事项："
    echo "1. 证书已经导入到钥匙串中"
    echo "2. 证书未过期"
    echo "3. 证书名称完全匹配"
    echo
    echo "可用的签名证书列表："
    security find-identity -v -p codesigning
    cd ..
    exit 1
fi

# 修改Info.plist中的包名和版本号
echo "修改包名为: $BUNDLE_IDENTIFIER"
echo "设置版本号: $VERSION (Build $BUILD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_PATH/Info.plist"

# 复制描述文件到应用程序包中
echo "复制描述文件..."
cp "../$PROVISIONING_PROFILE" "$APP_PATH/embedded.mobileprovision"

# 删除旧的签名文件（如果存在）
if [ -d "$APP_PATH/_CodeSignature" ]; then
    echo "删除旧的签名..."
    rm -rf "$APP_PATH/_CodeSignature"
fi

# 提取主应用描述文件中的权限
echo "提取主应用描述文件中的权限..."
security cms -D -i "../$PROVISIONING_PROFILE" > profile.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' profile.plist > entitlements.plist

# 首先签名所有嵌入的框架
echo "开始签名框架..."
if [ -d "$APP_PATH/Frameworks" ]; then
    find "$APP_PATH/Frameworks" -name "*.framework" -type d | while read framework; do
        echo "签名框架: $(basename "$framework")"
        # 删除框架的旧签名
        if [ -d "$framework/_CodeSignature" ]; then
            rm -rf "$framework/_CodeSignature"
        fi
        # 签名框架
        codesign --force --sign "$SIGNING_CERTIFICATE" \
                 --timestamp=none \
                 --preserve-metadata=identifier,entitlements,flags \
                 --verbose "$framework"
    done
    
    # 签名动态库
    find "$APP_PATH/Frameworks" -name "*.dylib" -type f | while read dylib; do
        echo "签名动态库: $(basename "$dylib")"
        codesign --force --sign "$SIGNING_CERTIFICATE" \
                 --timestamp=none \
                 --preserve-metadata=identifier,entitlements,flags \
                 --verbose "$dylib"
    done
fi

# 检查是否存在扩展插件目录
EXTENSIONS_DIR="$APP_PATH/PlugIns"
HAS_EXTENSIONS=false
if [ -d "$EXTENSIONS_DIR" ]; then
    HAS_EXTENSIONS=true
    echo "检测到扩展插件目录: $EXTENSIONS_DIR"
    
    # 列出所有扩展插件
    echo "发现的扩展插件:"
    find "$EXTENSIONS_DIR" -name "*.appex" -type d | while read appex; do
        extension_name=$(basename "$appex" .appex)
        echo "- $extension_name"
        
        # 检查是否有对应的描述文件
        extension_profile="${extension_name}.mobileprovision"
        if [ -f "$extension_profile" ]; then
            echo "  找到对应的描述文件: $extension_profile"
        else
            echo "  未找到对应的描述文件，将使用主应用描述文件签名"
        fi
    done
fi

# 签名扩展插件
echo "开始签名扩展插件..."
if [ "$HAS_EXTENSIONS" = true ]; then
    find "$APP_PATH/PlugIns" -name "*.appex" -type d | while read appex; do
        extension_name=$(basename "$appex" .appex)
        echo "处理扩展插件: $extension_name"
        
        # 检查是否有对应的描述文件
        extension_profile="../${extension_name}.mobileprovision"
        if [ -f "$extension_profile" ]; then
            echo "使用描述文件: $extension_profile"
            
            # 复制描述文件到扩展插件中
            cp "$extension_profile" "$appex/embedded.mobileprovision"
            
            # 提取扩展插件的权限
            security cms -D -i "$extension_profile" > extension_profile.plist
            /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' extension_profile.plist > extension_entitlements.plist
            
            # 删除扩展插件的旧签名
            if [ -d "$appex/_CodeSignature" ]; then
                rm -rf "$appex/_CodeSignature"
            fi
            
            # 如果扩展插件有自己的框架，也需要签名
            if [ -d "$appex/Frameworks" ]; then
                find "$appex/Frameworks" -name "*.framework" -type d -o -name "*.dylib" -type f | while read framework; do
                    echo "签名扩展插件框架: $(basename "$framework")"
                    codesign --force --sign "$SIGNING_CERTIFICATE" \
                             --timestamp=none \
                             --preserve-metadata=identifier,entitlements,flags \
                             --verbose "$framework"
                done
            fi
            
            # 签名扩展插件本身
            echo "签名扩展插件: $extension_name"
            codesign --force --sign "$SIGNING_CERTIFICATE" \
                     --entitlements "extension_entitlements.plist" \
                     --timestamp=none \
                     --verbose "$appex"
                     
            # 清理临时文件
            rm -f extension_profile.plist extension_entitlements.plist
        else
            echo "未找到扩展插件 $extension_name 的描述文件，使用主应用描述文件签名"
            codesign --force --sign "$SIGNING_CERTIFICATE" \
                     --entitlements "entitlements.plist" \
                     --timestamp=none \
                     --verbose "$appex"
        fi
    done
else
    echo "未检测到扩展插件，跳过扩展插件签名步骤"
fi

# 签名应用程序
echo "使用证书 '$SIGNING_CERTIFICATE' 签名应用..."
codesign --force --sign "$SIGNING_CERTIFICATE" \
         --entitlements "entitlements.plist" \
         --timestamp=none \
         --verbose \
         "$APP_PATH"

# 验证签名
echo "验证签名..."
codesign -v "$APP_PATH"

if [ $? -eq 0 ]; then
    echo "✅ 签名成功完成！"
    
    # 验证描述文件是否存在
    if [ -f "$APP_PATH/embedded.mobileprovision" ]; then
        echo "✅ 描述文件已正确嵌入到应用中"
        echo "描述文件路径: $APP_PATH/embedded.mobileprovision"
        echo "描述文件大小: $(ls -lh "$APP_PATH/embedded.mobileprovision" | awk '{print $5}')"
    else
        echo "❌ 警告: 描述文件未能正确嵌入到应用中"
        exit 1
    fi
    
    # 验证框架签名
    if [ -d "$APP_PATH/Frameworks" ]; then
        echo "验证框架签名..."
        find "$APP_PATH/Frameworks" -name "*.framework" -o -name "*.dylib" | while read -r framework; do
            echo "验证: $(basename "$framework")"
            codesign -v "$framework" || exit 1
        done
    fi
    
    # 验证扩展插件签名
    if [ -d "$APP_PATH/PlugIns" ]; then
        echo "验证扩展插件签名..."
        find "$APP_PATH/PlugIns" -name "*.appex" | while read -r appex; do
            extension_name=$(basename "$appex" .appex)
            echo "验证扩展插件: $extension_name"
            if [ -f "$appex/embedded.mobileprovision" ]; then
                echo "✅ 扩展插件描述文件已正确嵌入"
            else
                echo "❌ 警告: 扩展插件描述文件未能正确嵌入"
            fi
            codesign -v "$appex" || exit 1
        done
    fi
    
    # 创建压缩包
    echo "创建 IPA 文件..."
    echo "打包以下文件夹: ${FOLDERS_TO_PACK[*]}"
    zip -qr "../$IPA_NAME" "${FOLDERS_TO_PACK[@]}"
    
    # 返回上级目录
    cd ..
    
    echo "✅ IPA 文件已生成: $IPA_NAME"
    echo "包名: $BUNDLE_IDENTIFIER"
    echo "版本: $VERSION (Build $BUILD)"
    echo "包含的文件夹: ${FOLDERS_TO_PACK[*]}"
else
    echo "❌ 签名验证失败！"
    cleanup
    exit 1
fi 