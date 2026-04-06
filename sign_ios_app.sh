#!/bin/bash

set -euo pipefail

SCRIPT_VERSION="1.0.20260406a"

# ── 全局变量 ────────────────────────────────────────────────────────────────
CURRENT_DIR="$(pwd)"
TEMP_DIR=""
CURRENT_TIME=$(date "+%Y%m%d_%H%M%S")
PROFILE_PLIST=""
MAIN_ENTITLEMENTS=""
SIGNING_CERTIFICATE=""
TEAM_ID=""
BUNDLE_IDENTIFIER=""
IPHONE_ONLY=false
IPAD_MULTITASKING_ORIENTATIONS="auto"
APPLIED_IPAD_MULTITASKING_PATCH=false
OVERRIDE_CERTIFICATE=""
DISPLAY_NAME=""

# 可选：LOG_TIMESTAMPS=true ./sign_ios_app.sh ... 在 CI 日志中显示时间戳
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-false}"

# ── 帮助信息 ────────────────────────────────────────────────────────────────
show_usage() {
    local exit_code="${1:-1}"
    echo "iOS App Resign Tool v${SCRIPT_VERSION}"
    echo "使用方法 / Usage: $0 [选项/options]"
    echo "选项 / Options:"
    echo "  -f, --file <ipa文件/file>                要签名的IPA文件 / IPA file to sign (必需/required)"
    echo "  -p, --profile <描述文件/profile>         主描述文件路径 / Main provisioning profile path (必需/required)"
    echo "  -v, --version <版本号/version>           版本号 / Version number (必需/required)"
    echo "  -b, --build <构建号/build>               构建号 / Build number (必需/required)"
    echo "  -n, --name <应用显示名/name>             修改应用显示名称 / Override app display name (可选/optional)"
    echo "  -c, --certificate <证书名称/certificate> 指定签名证书 / Override signing certificate (可选/optional)"
    echo "      --iphone-only                        移除 iPad 声明，仅保留 iPhone 设备族 / Strip iPad support metadata"
    echo "      --ipad-multitasking-orientations     强制写入四方向，满足特定 iPad 多任务校验 / Force 4 orientations for iPad multitasking"
    echo "      --no-ipad-multitasking-orientations  禁止自动补齐四方向，完全保留 IPA 原值 / Disable auto orientation patching"
    echo "  -h, --help                               显示此帮助信息 / Show this help message"
    echo
    echo "示例 / Example:"
    echo "  $0 -f app.ipa -p profile.mobileprovision -v 1.0 -b 1"
    echo "  $0 -f app.ipa -p profile.mobileprovision -v 1.0 -b 1 -n 新应用名称"
    echo "  $0 -f app.ipa -p profile.mobileprovision -v 1.0 -b 1 --iphone-only"
    echo "  $0 -f app.ipa -p profile.mobileprovision -v 1.0 -b 1 --ipad-multitasking-orientations"
    echo "  $0 -f app.ipa -p profile.mobileprovision -v 1.0 -b 1 --no-ipad-multitasking-orientations"
    exit "$exit_code"
}

# ── 日志 & 错误 ─────────────────────────────────────────────────────────────

# [优化 #9] log() 支持可选时间戳，通过环境变量 LOG_TIMESTAMPS=true 开启
log() {
    if [ "$LOG_TIMESTAMPS" = "true" ]; then
        echo "[$(date '+%H:%M:%S')] $1"
    else
        echo "$1"
    fi
}

# [优化 #5] 错误信息输出到 stderr，避免污染管道
fail() {
    echo "错误: $1" >&2
    exit 1
}

# ── 清理 ────────────────────────────────────────────────────────────────────
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# ── 参数解析 ────────────────────────────────────────────────────────────────
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
        -n|--name)
            DISPLAY_NAME="$2"
            shift 2
            ;;
        -c|--certificate)
            OVERRIDE_CERTIFICATE="$2"
            shift 2
            ;;
        --iphone-only)
            IPHONE_ONLY=true
            shift
            ;;
        --ipad-multitasking-orientations)
            IPAD_MULTITASKING_ORIENTATIONS=true
            shift
            ;;
        --no-ipad-multitasking-orientations)
            IPAD_MULTITASKING_ORIENTATIONS=false
            shift
            ;;
        -h|--help)
            show_usage 0
            ;;
        *)
            fail "未知参数 / Unknown argument: $1"
            ;;
    esac
done

# ── 必填参数校验 ────────────────────────────────────────────────────────────
[ -n "${SOURCE_IPA:-}" ]             || show_usage 1
[ -n "${PROVISIONING_PROFILE:-}" ]   || show_usage 1
[ -n "${VERSION:-}" ]                || show_usage 1
[ -n "${BUILD:-}" ]                  || show_usage 1

[ -f "$SOURCE_IPA" ]             || fail "找不到源 IPA 文件 / Source IPA file not found: $SOURCE_IPA"
[ -f "$PROVISIONING_PROFILE" ]   || fail "找不到描述文件 / Profile file not found: $PROVISIONING_PROFILE"

SOURCE_IPA_ABS="$(cd "$(dirname "$SOURCE_IPA")" && pwd)/$(basename "$SOURCE_IPA")"
PROVISIONING_PROFILE_ABS="$(cd "$(dirname "$PROVISIONING_PROFILE")" && pwd)/$(basename "$PROVISIONING_PROFILE")"

IPA_NAME="${VERSION}-${BUILD}-${CURRENT_TIME}.ipa"
TEMP_DIR="$(mktemp -d "${CURRENT_DIR}/temp_signing.XXXXXX")"
PROFILE_PLIST="$TEMP_DIR/profile.plist"
MAIN_ENTITLEMENTS="$TEMP_DIR/entitlements.plist"

# ── 工具函数 ────────────────────────────────────────────────────────────────

decode_profile() {
    local profile_path="$1"
    local output_path="$2"

    if security cms -D -i "$profile_path" > "$output_path" 2>/dev/null; then
        return 0
    fi

    if openssl cms -inform DER -verify -noverify -in "$profile_path" -out "$output_path" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

plist_has_key() {
    local plist_path="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print $key" "$plist_path" >/dev/null 2>&1
}

# [优化 #3] 值用单引号包裹，支持含空格的字符串（如 "My App Name"）
plist_set_string() {
    local plist_path="$1"
    local key="$2"
    local value="$3"

    if plist_has_key "$plist_path" "$key"; then
        /usr/libexec/PlistBuddy -c "Set $key '$value'" "$plist_path"
    else
        /usr/libexec/PlistBuddy -c "Add $key string '$value'" "$plist_path"
    fi
}

plist_set_integer() {
    local plist_path="$1"
    local key="$2"
    local value="$3"

    if plist_has_key "$plist_path" "$key"; then
        /usr/libexec/PlistBuddy -c "Set $key '$value'" "$plist_path"
    else
        /usr/libexec/PlistBuddy -c "Add $key integer '$value'" "$plist_path"
    fi
}

profile_bundle_id() {
    local profile_plist="$1"
    local profile_team_id="$2"
    local app_identifier=""

    app_identifier=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$profile_plist")
    echo "${app_identifier#${profile_team_id}.}"
}

escape_regex() {
    printf '%s' "$1" | sed 's/[][(){}.^$+*?|\\]/\\&/g'
}

# [优化 #2] 合并证书提取逻辑，每个证书只做一次 PlistBuddy + DER 写入
# SHA1 匹配和 CommonName 回退均复用同一个 .der 临时文件
find_identity_from_profile() {
    local profile_plist="$1"
    local cert_index=0
    local cert_tmp cert_sha1 identity

    while true; do
        cert_tmp="$TEMP_DIR/profile-cert-$cert_index.der"

        /usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:$cert_index" \
            "$profile_plist" > "$cert_tmp" 2>/dev/null || break

        cert_sha1=$(openssl x509 -inform DER -in "$cert_tmp" -noout \
            -fingerprint -sha1 2>/dev/null | sed 's/.*=//' | tr -d ':')

        identity=""
        if [ -n "$cert_sha1" ]; then
            identity=$(security find-identity -v -p codesigning 2>&1 \
                | grep "$cert_sha1" \
                | sed -E 's/.*"([^"]+)".*/\1/' \
                | head -n 1 || true)
        fi

        # SHA1 未命中则回退 CommonName
        if [ -z "$identity" ]; then
            identity=$(openssl x509 -inform DER -in "$cert_tmp" -noout -subject 2>/dev/null \
                | sed -n 's/.*CN=\(.*\), OU=.*/\1/p' || true)
        fi

        if [ -n "$identity" ]; then
            echo "$identity"
            return 0
        fi

        cert_index=$((cert_index + 1))
    done

    return 1
}

warn_if_identity_precheck_unavailable() {
    local identity="$1"
    local pattern

    pattern="$(escape_regex "$identity")"
    if ! security find-identity -v -p codesigning 2>&1 | grep -E "\"${pattern}\"" >/dev/null 2>&1; then
        log "警告: 当前环境无法通过 security 预校验签名证书，将继续交由 codesign 实际校验 / Warning: security precheck could not confirm identity, continuing with codesign"
    fi
}

remove_old_signature() {
    local target="$1"
    rm -rf "$target/_CodeSignature"
    [ -f "$target/CodeResources" ] && rm -f "$target/CodeResources"
    find "$target" -name ".DS_Store" -type f -delete 2>/dev/null || true
}

prune_non_payload_content() {
    local temp_root="$1"
    local entry=""

    log "清理 Payload 之外的内容 / Removing content outside Payload..."
    while IFS= read -r entry; do
        if [ -e "$entry" ]; then
            log "删除 / Removing: $(basename "$entry")"
            rm -rf "$entry"
        fi
    done < <(find "$temp_root" -mindepth 1 -maxdepth 1 ! -name "Payload")
}

remove_plugins_directory() {
    local app_path="$1"
    local plugins_dir="$app_path/PlugIns"

    if [ -d "$plugins_dir" ]; then
        log "删除扩展目录 / Removing PlugIns directory..."
        rm -rf "$plugins_dir"
    else
        log "未发现扩展目录 / PlugIns directory not found, skipping"
    fi
}

remove_swift_runtime_dylibs() {
    local frameworks_dir="$1"
    local dylib_path=""
    local found_any=false

    if [ ! -d "$frameworks_dir" ]; then
        log "未发现 Frameworks 目录 / Frameworks directory not found, skipping libswift cleanup"
        return 0
    fi

    while IFS= read -r dylib_path; do
        found_any=true
        if [ -f "$dylib_path" ]; then
            log "删除 Swift 运行库 / Removing Swift runtime dylib: $(basename "$dylib_path")"
            rm -f "$dylib_path"
        fi
    done < <(find "$frameworks_dir" -maxdepth 1 -type f -name "libswift*.dylib")

    if [ "$found_any" = false ]; then
        log "未发现 libswift 动态库 / No libswift dylibs found, skipping"
    fi
}

collect_icon_basenames_from_plist() {
    local app_plist="$1"
    local temp_output="$2"
    local icon_key=""
    local index=0
    local icon_name=""

    : > "$temp_output"

    for icon_key in ":CFBundleIcons" ":CFBundleIcons~ipad"; do
        index=0
        while true; do
            icon_name=$(/usr/libexec/PlistBuddy -c "Print ${icon_key}:CFBundlePrimaryIcon:CFBundleIconFiles:${index}" "$app_plist" 2>/dev/null || true)
            [ -n "$icon_name" ] || break
            printf '%s\n' "$icon_name" >> "$temp_output"
            index=$((index + 1))
        done
    done

    sort -u "$temp_output" -o "$temp_output"
}

check_app_icons_for_alpha() {
    local app_path="$1"
    local app_plist="$app_path/Info.plist"
    local icon_names_file="$TEMP_DIR/icon_names.txt"
    local matched_icons_file="$TEMP_DIR/matched_icons.txt"
    local icon_base=""
    local icon_file=""
    local found_any=false
    local has_alpha=""

    collect_icon_basenames_from_plist "$app_plist" "$icon_names_file"
    : > "$matched_icons_file"

    while IFS= read -r icon_base; do
        [ -n "$icon_base" ] || continue
        while IFS= read -r icon_file; do
            [ -f "$icon_file" ] || continue
            printf '%s\n' "$icon_file" >> "$matched_icons_file"
        done < <(find "$app_path" -maxdepth 1 -type f \( -name "${icon_base}.png" -o -name "${icon_base}@*.png" -o -name "${icon_base}~*.png" -o -name "${icon_base}@*~*.png" \))
    done < "$icon_names_file"

    sort -u "$matched_icons_file" -o "$matched_icons_file"

    while IFS= read -r icon_file; do
        [ -f "$icon_file" ] || continue
        found_any=true
        has_alpha="$(sips -g hasAlpha "$icon_file" 2>/dev/null | awk -F': ' '/hasAlpha/ {print $2}')"
        if [ "$has_alpha" = "yes" ]; then
            fail "检测到 AppIcon 存在透明度，不符合 App Store 要求，请先修改图标后重新签名: $icon_file"
        fi
    done < "$matched_icons_file"

    if [ "$found_any" = false ]; then
        log "未找到可检测的 AppIcon PNG 文件 / No AppIcon PNG files found, skipping alpha check"
    else
        log "AppIcon 透明度检查通过 / AppIcon alpha check passed"
    fi
}

# App Store ContentDelivery 409：支持 iPad 多任务时需在 Info.plist 中声明四种界面方向
apply_ipad_multitasking_orientations() {
    local app_plist="$1"
    local key=""

    log "写入 iPad 多任务四方向 (UISupportedInterfaceOrientations) / iPad multitasking orientations for App Store validation..."
    APPLIED_IPAD_MULTITASKING_PATCH=true

    for key in ":UISupportedInterfaceOrientations" ":UISupportedInterfaceOrientations~ipad"; do
        /usr/libexec/PlistBuddy -c "Delete $key" "$app_plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add $key array" "$app_plist"
        /usr/libexec/PlistBuddy -c "Add ${key}:0 string UIInterfaceOrientationPortrait" "$app_plist"
        /usr/libexec/PlistBuddy -c "Add ${key}:1 string UIInterfaceOrientationPortraitUpsideDown" "$app_plist"
        /usr/libexec/PlistBuddy -c "Add ${key}:2 string UIInterfaceOrientationLandscapeLeft" "$app_plist"
        /usr/libexec/PlistBuddy -c "Add ${key}:3 string UIInterfaceOrientationLandscapeRight" "$app_plist"
    done
}

plist_array_contains_value() {
    local plist_path="$1"
    local key="$2"
    local expected="$3"
    local index=0
    local actual=""

    while true; do
        actual=$(/usr/libexec/PlistBuddy -c "Print ${key}:${index}" "$plist_path" 2>/dev/null || true)
        [ -n "$actual" ] || break
        [ "$actual" = "$expected" ] && return 0
        index=$((index + 1))
    done

    return 1
}

app_supports_ipad() {
    local app_plist="$1"
    plist_array_contains_value "$app_plist" ":UIDeviceFamily" "2"
}

app_requires_full_screen() {
    local app_plist="$1"
    local full_screen=""

    full_screen=$(/usr/libexec/PlistBuddy -c "Print :UIRequiresFullScreen" "$app_plist" 2>/dev/null || true)
    [ "$full_screen" = "true" ]
}

orientation_key_has_all_multitasking_values() {
    local app_plist="$1"
    local key="$2"
    local orientation=""

    for orientation in \
        "UIInterfaceOrientationPortrait" \
        "UIInterfaceOrientationPortraitUpsideDown" \
        "UIInterfaceOrientationLandscapeLeft" \
        "UIInterfaceOrientationLandscapeRight"; do
        plist_array_contains_value "$app_plist" "$key" "$orientation" || return 1
    done

    return 0
}

should_apply_ipad_multitasking_orientations() {
    local app_plist="$1"

    if [ "$IPAD_MULTITASKING_ORIENTATIONS" = true ]; then
        return 0
    fi

    if [ "$IPAD_MULTITASKING_ORIENTATIONS" = false ]; then
        return 1
    fi

    if ! app_supports_ipad "$app_plist"; then
        log "未声明 iPad 设备族，保留原有方向键 / No iPad device family declared, keeping original orientations"
        return 1
    fi

    if app_requires_full_screen "$app_plist"; then
        log "应用要求全屏，保留原有方向键 / UIRequiresFullScreen=true, keeping original orientations"
        return 1
    fi

    if orientation_key_has_all_multitasking_values "$app_plist" ":UISupportedInterfaceOrientations" && \
       orientation_key_has_all_multitasking_values "$app_plist" ":UISupportedInterfaceOrientations~ipad"; then
        log "已满足 iPad 多任务四方向要求，保留原有方向键 / iPad multitasking orientations already satisfied"
        return 1
    fi

    log "检测到 iPad 多任务方向键不完整，将自动补齐四方向 / Incomplete iPad multitasking orientations detected, patching to all four"
    return 0
}

apply_main_app_metadata_overrides() {
    local app_plist="$1"

    log "更新主应用元数据 / Updating main app metadata..."
    plist_set_string "$app_plist" ":CFBundleIdentifier" "$BUNDLE_IDENTIFIER"
    plist_set_string "$app_plist" ":CFBundleShortVersionString" "$VERSION"
    plist_set_string "$app_plist" ":CFBundleVersion" "$BUILD"

    if [ -n "$DISPLAY_NAME" ]; then
        log "更新应用显示名称 / Updating app display name..."
        plist_set_string "$app_plist" ":CFBundleDisplayName" "$DISPLAY_NAME"
        plist_set_string "$app_plist" ":CFBundleName" "$DISPLAY_NAME"
    fi

    if [ "$IPHONE_ONLY" = true ]; then
        log "应用 iPhone-only 修补 / Applying iPhone-only metadata patch..."
        /usr/libexec/PlistBuddy -c "Delete :UIDeviceFamily" "$app_plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$app_plist"
        /usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" "$app_plist"
        /usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations~ipad" "$app_plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Delete :UIDeviceFamily~ipad" "$app_plist" >/dev/null 2>&1 || true
    elif should_apply_ipad_multitasking_orientations "$app_plist"; then
        apply_ipad_multitasking_orientations "$app_plist"
    fi
}

# [优化 #7] 补充对 .xpc 扩展名的剥离，保证 XPC extension 能正确查找专用 Profile
find_profile_for_bundle() {
    local bundle_path="$1"
    local bundle_name bundle_id direct_profile sibling_profile maybe_profile

    bundle_name="$(basename "$bundle_path")"
    bundle_name="${bundle_name%.appex}"
    bundle_name="${bundle_name%.app}"
    bundle_name="${bundle_name%.xpc}"

    bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle_path/Info.plist" 2>/dev/null || true)

    direct_profile="$CURRENT_DIR/${bundle_name}.mobileprovision"
    [ -f "$direct_profile" ] && echo "$direct_profile" && return 0

    sibling_profile="$(dirname "$PROVISIONING_PROFILE_ABS")/${bundle_name}.mobileprovision"
    [ -f "$sibling_profile" ] && echo "$sibling_profile" && return 0

    if [ -n "$bundle_id" ]; then
        maybe_profile="$CURRENT_DIR/${bundle_id}.mobileprovision"
        [ -f "$maybe_profile" ] && echo "$maybe_profile" && return 0

        maybe_profile="$(dirname "$PROVISIONING_PROFILE_ABS")/${bundle_id}.mobileprovision"
        [ -f "$maybe_profile" ] && echo "$maybe_profile" && return 0
    fi

    return 1
}

prepare_entitlements_from_profile() {
    local profile_path="$1"
    local plist_path="$2"
    local entitlements_path="$3"

    decode_profile "$profile_path" "$plist_path" || fail "无法解析描述文件 / Failed to decode profile: $profile_path"
    /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$plist_path" > "$entitlements_path"
}

verify_bundle_matches_profile() {
    local bundle_path="$1"
    local profile_plist="$2"
    local expected_team_id="$3"
    local bundle_identifier_from_profile expected_bundle_identifier actual_bundle_identifier

    bundle_identifier_from_profile="$(profile_bundle_id "$profile_plist" "$expected_team_id")"
    actual_bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle_path/Info.plist")

    expected_bundle_identifier="$(escape_regex "$bundle_identifier_from_profile")"
    expected_bundle_identifier="${expected_bundle_identifier//\\*/.*}"
    if ! printf '%s\n' "$actual_bundle_identifier" | grep -Eq "^${expected_bundle_identifier}$"; then
        fail "Bundle ID 与描述文件不匹配 / Bundle ID does not match profile: $actual_bundle_identifier vs $bundle_identifier_from_profile"
    fi
}

# [优化 #1] 调整顺序：先清理旧签名，再嵌入新 Profile，语义更清晰
sign_bundle() {
    local bundle_path="$1"
    local profile_path="$2"
    local profile_plist="$3"
    local entitlements_path="$4"
    local bundle_type="$5"

    log "签名 ${bundle_type}: $(basename "$bundle_path")"

    remove_old_signature "$bundle_path"
    cp "$profile_path" "$bundle_path/embedded.mobileprovision"
    verify_bundle_matches_profile "$bundle_path" "$profile_plist" "$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$profile_plist")"

    codesign --force --sign "$SIGNING_CERTIFICATE" \
             --entitlements "$entitlements_path" \
             --timestamp=none \
             --verbose \
             "$bundle_path"
}

# [优化 #8] awk+sort+cut 中 sort key 更明确，行为完全一致
sign_frameworks_in_dir() {
    local search_dir="$1"
    local framework_path=""

    [ -d "$search_dir" ] || return 0

    while IFS= read -r framework_path; do
        log "签名框架 / Signing framework: $(basename "$framework_path")"
        remove_old_signature "$framework_path"
        codesign --force --sign "$SIGNING_CERTIFICATE" \
                 --timestamp=none \
                 --preserve-metadata=identifier,flags \
                 --verbose \
                 "$framework_path"
    done < <(find "$search_dir" -type d -name "*.framework" | awk '{ print length, $0 }' | sort -k1,1rn | cut -d" " -f2-)

    while IFS= read -r framework_path; do
        log "签名动态库 / Signing dylib: $(basename "$framework_path")"
        codesign --force --sign "$SIGNING_CERTIFICATE" \
                 --timestamp=none \
                 --preserve-metadata=identifier,flags \
                 --verbose \
                 "$framework_path"
    done < <(find "$search_dir" -type f -name "*.dylib" | awk '{ print length, $0 }' | sort -k1,1rn | cut -d" " -f2-)
}

sign_nested_bundles() {
    local app_path="$1"
    local nested_bundle=""
    local profile_path=""
    local nested_profile_plist=""
    local nested_entitlements=""

    while IFS= read -r nested_bundle; do
        profile_path="$(find_profile_for_bundle "$nested_bundle" || true)"
        if [ -n "$profile_path" ]; then
            nested_profile_plist="$TEMP_DIR/$(basename "$nested_bundle").profile.plist"
            nested_entitlements="$TEMP_DIR/$(basename "$nested_bundle").entitlements.plist"
            prepare_entitlements_from_profile "$profile_path" "$nested_profile_plist" "$nested_entitlements"
            sign_frameworks_in_dir "$nested_bundle/Frameworks"
            sign_bundle "$nested_bundle" "$profile_path" "$nested_profile_plist" "$nested_entitlements" "嵌套 Bundle / Nested bundle"
        else
            log "未找到 $(basename "$nested_bundle") 对应描述文件，回退主描述文件 / Missing dedicated profile, falling back to main profile"
            sign_frameworks_in_dir "$nested_bundle/Frameworks"
            sign_bundle "$nested_bundle" "$PROVISIONING_PROFILE_ABS" "$PROFILE_PLIST" "$MAIN_ENTITLEMENTS" "嵌套 Bundle / Nested bundle"
        fi
    done < <(find "$app_path" -type d \( -name "*.appex" -o -name "*.app" -o -name "*.xpc" \) ! -path "$app_path" | awk '{ print length, $0 }' | sort -k1,1rn | cut -d" " -f2-)
}

# [优化 #6] 新增描述文件到期日期打印，便于排查签名后安装失败问题
validate_final_bundle() {
    local app_path="$1"
    log "验证签名 / Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$app_path"

    local expiry
    expiry=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$PROFILE_PLIST" 2>/dev/null || true)
    if [ -n "$expiry" ]; then
        log "描述文件到期时间 / Profile expiry date: $expiry"
    fi

    if [ "$IPHONE_ONLY" = true ]; then
        log "验证 iPhone-only 元数据 / Verifying iPhone-only metadata..."
        /usr/libexec/PlistBuddy -c "Print :UIDeviceFamily" "$app_path/Info.plist"
    fi

    if [ "$APPLIED_IPAD_MULTITASKING_PATCH" = true ] && [ "$IPHONE_ONLY" != true ]; then
        log "验证 iPad 多任务方向键 / Verifying iPad multitasking orientation keys..."
        /usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations" "$app_path/Info.plist"
        /usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations~ipad" "$app_path/Info.plist" 2>/dev/null || true
    fi

    log "验证嵌入描述文件 / Verifying embedded profile..."
    [ -f "$app_path/embedded.mobileprovision" ] || fail "主应用缺少 embedded.mobileprovision"
}

# ── 主流程 ──────────────────────────────────────────────────────────────────

log "创建临时工作目录 / Creating temporary directory: $TEMP_DIR"
log "解压 IPA 文件 / Extracting IPA file..."
unzip -q "$SOURCE_IPA_ABS" -d "$TEMP_DIR"
prune_non_payload_content "$TEMP_DIR"

log "检查解压后的文件夹结构 / Checking extracted folder structure..."
FOLDERS_TO_PACK=()
while IFS= read -r folder; do
    folder_name="$(basename "$folder")"
    log "发现文件夹 / Found folder: $folder_name"
    FOLDERS_TO_PACK+=("$folder_name")
done < <(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

[ ${#FOLDERS_TO_PACK[@]} -gt 0 ] || fail "解压后没有找到任何文件夹 / No folders found after extraction"

APP_PATH="$(find "$TEMP_DIR/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
[ -n "$APP_PATH" ] || fail "在 IPA 中找不到 .app 文件 / .app bundle not found"

log "找到应用程序包 / Found application bundle: $APP_PATH"
decode_profile "$PROVISIONING_PROFILE_ABS" "$PROFILE_PLIST" || fail "无法解析主描述文件 / Failed to decode main profile"

TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST")
BUNDLE_IDENTIFIER="$(profile_bundle_id "$PROFILE_PLIST" "$TEAM_ID")"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$PROFILE_PLIST" > "$MAIN_ENTITLEMENTS"

if [ -n "$OVERRIDE_CERTIFICATE" ]; then
    SIGNING_CERTIFICATE="$OVERRIDE_CERTIFICATE"
else
    SIGNING_CERTIFICATE="$(find_identity_from_profile "$PROFILE_PLIST" || true)"
fi

[ -n "$SIGNING_CERTIFICATE" ] || fail "无法根据描述文件匹配本地证书 / Failed to match signing identity from profile"
warn_if_identity_precheck_unavailable "$SIGNING_CERTIFICATE"

log "获取到的信息 / Retrieved information:"
log "团队 ID / Team ID: $TEAM_ID"
log "Bundle ID: $BUNDLE_IDENTIFIER"
log "签名证书 / Signing certificate: $SIGNING_CERTIFICATE"

MAIN_APP_PLIST="$APP_PATH/Info.plist"
check_app_icons_for_alpha "$APP_PATH"
apply_main_app_metadata_overrides "$MAIN_APP_PLIST"
verify_bundle_matches_profile "$APP_PATH" "$PROFILE_PLIST" "$TEAM_ID"

remove_plugins_directory "$APP_PATH"
remove_swift_runtime_dylibs "$APP_PATH/Frameworks"

sign_frameworks_in_dir "$APP_PATH/Frameworks"
sign_nested_bundles "$APP_PATH"
sign_bundle "$APP_PATH" "$PROVISIONING_PROFILE_ABS" "$PROFILE_PLIST" "$MAIN_ENTITLEMENTS" "主应用 / Main app"
validate_final_bundle "$APP_PATH"

log "创建 IPA 文件 / Creating IPA..."
(
    cd "$TEMP_DIR"
    zip -qr "$CURRENT_DIR/$IPA_NAME" "${FOLDERS_TO_PACK[@]}"
)

log "✅ IPA 文件已生成 / Generated IPA: $IPA_NAME"
log "包名 / Bundle ID: $BUNDLE_IDENTIFIER"
log "版本 / Version: $VERSION (Build $BUILD)"
log "包含的文件夹 / Included folders: ${FOLDERS_TO_PACK[*]}"
