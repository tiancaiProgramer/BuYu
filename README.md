# 不倦 BuJuan 修复版

基于 [2697a/bujuan](https://github.com/2697a/bujuan) 修改，**原作者为 [2697a](https://github.com/2697a) / sixbugs**。原项目版权声明 `Copyright (c) 2023 sixbugs` 与 [MIT 许可证](LICENSE) 保留。本仓库是社区修复版，不代表原作者的官方发布。

## 下载与安装

当前版本 **2.0.6（2062）**：[下载发布版](https://github.com/tiancaiProgramer/bujuan-fixed/releases/tag/v2.0.6.2062)。

| 安装包 | 适用设备 | 大小 |
| --- | --- | --- |
| `bujuan-2.0.6-2062-arm64.apk` | 小米 15 等 ARM 64 位安卓手机 | 约 13.4 MB |
| `bujuan-2.0.6-2062-arm32.apk` | 运行 32 位 ARM 系统的旧设备 | 约 13.1 MB |

- 最低 Android 5.0；Android 4.4 尚未支持。
- 交付 APK 与本次修复所用原 2.0.5 APK 签名一致，可覆盖升级并保留数据。
- 手机版本随重力感应切换横竖屏；设置中的“适配横屏”可开关此行为。
- 首次下载如出现通知权限提示，请允许；下载管理入口为“本地音乐 → 下载管理”。
- 播放和下载音质分别设置，下载时也可单独选择；保存目录可在设置内修改。
- 更新检查已关联本仓库 Releases，按应用版本及内部版本号判断更新。

完整迭代说明见 [CHANGELOG.md](CHANGELOG.md)，本版细节与验证见 [2.0.6 发布说明](docs/releases/2.0.6-2062.md)。

## 2.0.6 更新

- 完善手机横屏首页、头像侧栏、每日推荐、云盘、本地音乐、查看/管理及设置页；保留原版按钮和主题。
- 横屏播放页采用封面与播放控制、歌词、侧边功能分区，处理两侧摄像头安全区、状态栏对比度、封面与专辑渐变背景。
- 修复横屏首次进入每日推荐后无法返回、搜索转场残影，以及竖屏上一首和播放模式按钮无响应。
- 修复歌手页空白和头像加载，横屏显示两列歌手歌曲推荐，播放队列适配横屏。
- 自定义启动图、背景支持竖图自动适应横屏，也可分别设置横竖屏图片。
- 增加独立播放音质与下载音质选项，下载弹窗查询官方资源规格和账号下载权限。
- 歌曲三点菜单及播放页歌手入口均可下载，支持自选文件夹、进度和结果通知、失败重试及已下载歌曲离线播放。
- 修复默认选中“极高”时再次点击无法提交下载，以及部分主题下下载选项文字不可见。
- 继承 2.0.5 的播放稳定性、歌曲信息同步、系统媒体控制、本地曲库、二维码赞助移除和安装包精简修复。

音源使用当前网易云账号可获取的资源，不绕过账号下载权限。请求档位可能与官方实际返回格式不同，完成后显示文件的真实格式、采样率和位深；没有对应资源时按现有优先级回退。下载中断后可在下载管理重试，尚不保证应用被系统结束后持续下载或自动断点续传。

## 验证范围

105 项自动检查通过，覆盖播放、横竖屏、导航、图片适配、歌手页、下载与更新版本判断。小米 15 / HyperOS 3.0.307.0 真机已覆盖安装并检查多个页面；使用者确认“极高”默认选中项可触发下载，通知栏完成提示正常。自选 `Download/music` 目录保存已验证，MP3 标准与极高文件分别核验为 128 / 320 kbps，FLAC 文件规格也已通过文件头核验。

超级岛信息与系统媒体状态已观察到，但所有系统版本、超级岛交互、本地标签写入和缓存解密未全面验证。自动检查包含可控播放器和网络替身，不等同全部真实设备验证。原始播放修复说明保留在 [FIXES.md](FIXES.md)。

## TV / 车机

本次 2.0.6 发布提供手机 APK。TV 界面与方向键支持仍在试用阶段，历史独立 TV 包见 [2040 预发布](https://github.com/tiancaiProgramer/bujuan-fixed/releases/tag/v2.0.5-wide-tv-preview.2040) 和 [TV_PREVIEW.md](TV_PREVIEW.md)；其中截图、操作范围和验证记录对应当时版本。本次没有新的 TV 安装包，也没有在小米电视、Chromecast 4K 或比亚迪车机上完成真机验证。

## 编译

验证环境：Flutter 3.24.5 / Dart 3.5.4、JDK 17、Android compileSdk / targetSdk 34。

```sh
flutter pub get
flutter test
# 手机，32 位与 64 位分包
flutter build apk --release --flavor mobile --split-per-abi --target-platform android-arm,android-arm64
# TV：必须同时指定 flavor 与 Dart define
flutter build apk --release --flavor tv --dart-define=BUJUAN_TV=true --split-per-abi --target-platform android-arm,android-arm64
```

本仓库保留其他平台源码，但本次交付与验证针对 Android。

## 来源与致谢

- 原项目与原作者：[2697a/bujuan](https://github.com/2697a/bujuan)、[2697a](https://github.com/2697a)。
- 修复基础：上游 `2.0.0` 分支的 `d32b3c3` 提交；原侧栏与本地音乐从上游旧提交恢复。
- 上游说明存档：[UPSTREAM_README.md](UPSTREAM_README.md)。
- 第三方组件与原许可证：[CREDITS.md](CREDITS.md)。
