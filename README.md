# 长须鲸手机工具 iOS版 - 云编译指南

## 🚀 方案一：GitHub Actions 免费编译（推荐）

### 优点
- ✅ 完全免费（每月200分钟macOS编译时间）
- ✅ 不需要Mac电脑
- ✅ 不需要安装任何软件
- ✅ 自动编译，下载即用

### 使用步骤

#### 1. 注册GitHub账号
- 访问 https://github.com
- 注册一个免费账号

#### 2. 创建新仓库
- 点击右上角 "+" → "New repository"
- 仓库名：`changxuijing-mobile-tool-ios`
- 选择 Public（公开仓库免费额度更多）
- 点击 "Create repository"

#### 3. 上传代码
将本目录下的所有文件上传到GitHub仓库：
```
长须鲸手机工具.xcodeproj/
长须鲸手机工具/
.github/
build.sh
```

**方法A：网页上传**
- 打开仓库页面
- 点击 "Add file" → "Upload files"
- 拖拽所有文件和文件夹到网页
- 点击 "Commit changes"

**方法B：使用Git命令**
```bash
git init
git add .
git commit -m "初始提交"
git branch -M main
git remote add origin https://github.com/你的用户名/changxuijing-mobile-tool-ios.git
git push -u origin main
```

#### 4. 触发编译
- 打开仓库页面
- 点击顶部 "Actions" 标签
- 左侧选择 "编译iOS IPA"
- 点击 "Run workflow" → 选择main分支 → "Run workflow"
- 等待编译完成（约5-10分钟）

#### 5. 下载IPA
- 编译完成后，点击对应的工作流运行记录
- 页面底部 "Artifacts" 区域
- 点击 "mobile_tool.ipa" 下载
- 解压下载的zip文件，得到 `mobile_tool.ipa`

#### 6. 使用IPA
- 将 `mobile_tool.ipa` 放到电脑端程序目录：
  `E:\其他文件\C++\新建文件夹\Python脚本迁移\Python脚本迁移\x64\Debug\`
- 在电脑端点击"安装移动端"
- 使用FaceID自签名功能安装到iPhone

---

## ☁️ 方案二：Codemagic 云编译（备选）

### 优点
- 专门针对移动应用优化
- 免费额度：每月500分钟
- 支持自动签名

### 使用步骤
1. 访问 https://codemagic.io
2. 使用GitHub账号登录
3. 导入你的仓库
4. 选择iOS平台
5. 点击 "Start new build"
6. 编译完成后下载IPA

---

## 💻 方案三：虚拟机安装macOS（适合折腾）

### 硬件要求
- CPU支持虚拟化（需在BIOS开启VT-x/AMD-V）
- 内存至少8GB（推荐16GB）
- 磁盘至少100GB空闲

### 软件准备
- VMware Workstation Pro 17（下载：https://www.vmware.com）
- macOS镜像（macOS Ventura或Sonoma）
- Unlocker工具（解锁VMware的macOS支持）

### 安装步骤
1. 安装VMware Workstation
2. 运行Unlocker解锁macOS支持
3. 创建虚拟机，选择macOS
4. 分配4核CPU + 8GB内存 + 100GB硬盘
5. 挂载macOS镜像，启动安装
6. 安装完成后，在虚拟机内安装Xcode（App Store下载）
7. 打开本项目，点击运行编译

### 注意事项
- ⚠️ 在非苹果硬件上运行macOS可能违反苹果许可协议
- ⚠️ 虚拟机性能约为真机的50-70%
- ⚠️ 首次编译可能需要30分钟以上

---

## 📱 方案四：租用云Mac（最省心）

### 推荐服务
| 服务 | 价格 | 特点 |
|------|------|------|
| MacInCloud | $20/月起 | 按需付费，支持远程桌面 |
| MacStadium | $79/月起 | 企业级，性能好 |
| 腾讯云Mac | 约¥50/天 | 国内访问快 |
| 阿里云Mac | 约¥50/天 | 国内访问快 |

### 使用方法
1. 租用云Mac实例
2. 通过远程桌面连接
3. 下载本项目代码
4. 用Xcode打开并编译
5. 导出IPA后下载到本地

---

## ❓ 常见问题

### Q: GitHub Actions编译失败怎么办？
A: 查看Actions日志，常见原因：
- 项目文件路径错误
- Xcode版本不兼容
- 代码有语法错误

### Q: 编译的IPA可以直接安装吗？
A: 不能直接安装，需要签名。使用电脑端的"FaceID自签名"功能进行签名后安装。

### Q: 免费额度够用吗？
A: GitHub免费账户每月2000分钟总时长，macOS按10倍计算，即每月200分钟macOS时间。编译一次约5-10分钟，足够用。

### Q: 可以自动签名吗？
A: 可以，但需要配置Apple开发者账号和证书。当前工作流使用无签名编译，后续用电脑端自签名。

---

## 📁 项目结构
```
长须鲸手机工具/
├── .github/
│   └── workflows/
│       └── build-ios.yml      # GitHub Actions编译配置
├── 长须鲸手机工具.xcodeproj/
│   └── project.pbxproj        # Xcode项目配置
├── 长须鲸手机工具/
│   ├── 长须鲸手机工具App.swift  # 应用入口
│   ├── ContentView.swift       # 主界面
│   ├── Info.plist              # 应用配置
│   └── Assets.xcassets/        # 资源文件
├── build.sh                    # 本地编译脚本（Mac用）
└── README.md                   # 本说明文件
```
