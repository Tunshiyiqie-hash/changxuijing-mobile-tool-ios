#!/bin/bash
# 长须鲸手机工具 iOS版 一键编译脚本
# 使用方法：在Mac终端中运行 ./build.sh

set -e

echo "=========================================="
echo "  长须鲸手机工具 iOS版 编译脚本"
echo "=========================================="
echo ""

# 检查是否安装了Xcode命令行工具
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 未检测到Xcode，请先安装Xcode"
    echo "下载地址：https://developer.apple.com/xcode/"
    exit 1
fi

# 项目目录
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="长须鲸手机工具"
SCHEME="长须鲸手机工具"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_DIR="$PROJECT_DIR/export"

echo "📁 项目目录: $PROJECT_DIR"
echo "🔨 开始编译..."
echo ""

# 清理旧的构建
rm -rf "$BUILD_DIR"
rm -rf "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

# 编译Archive
echo "📦 正在编译Archive..."
xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$BUILD_DIR/$PROJECT_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo ""
echo "✅ Archive编译成功"
echo ""

# 创建exportOptions.plist
cat > "$EXPORT_DIR/exportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

# 导出IPA
echo "📤 正在导出IPA..."
xcodebuild \
    -exportArchive \
    -archivePath "$BUILD_DIR/$PROJECT_NAME.xcarchive" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_DIR/exportOptions.plist" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo "❌ IPA导出失败"
    exit 1
fi

echo ""
echo "=========================================="
echo "  ✅ 编译成功！"
echo "=========================================="
echo ""
echo "📱 IPA文件位置: $EXPORT_DIR/$PROJECT_NAME.ipa"
echo ""

# 复制到电脑端程序目录（如果存在）
DEST_DIR="/Volumes/其他文件/C++/新建文件夹/Python脚本迁移/Python脚本迁移/x64/Debug"
if [ -d "$DEST_DIR" ]; then
    cp "$EXPORT_DIR/$PROJECT_NAME.ipa" "$DEST_DIR/mobile_tool.ipa"
    echo "📋 已复制到电脑端程序目录: $DEST_DIR/mobile_tool.ipa"
fi

echo ""
echo "下一步："
echo "1. 将IPA文件传到Windows电脑"
echo "2. 放到电脑端程序目录（x64/Debug/mobile_tool.ipa）"
echo "3. 在电脑端点击'安装移动端'进行FaceID自签名安装"
echo ""
