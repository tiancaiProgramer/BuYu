# 不倦 BuJuan 修复版

基于 [2697a/bujuan](https://github.com/2697a/bujuan) 修改，**原作者为 [2697a](https://github.com/2697a) / sixbugs**。原项目版权声明 `Copyright (c) 2023 sixbugs` 与 [MIT 许可证](LICENSE) 保留。本仓库是社区修复版，不代表原作者的官方发布。

## 下载与安装

从 [Releases](https://github.com/tiancaiProgramer/bujuan-fixed/releases/latest) 下载 `bujuan-2.0.5-fixed.apk`。

- 当前版本：2.0.5，内部版本号 2039。
- 精简安装包约 13.24 MB，较此前修复包减少约 53%，小于本次提供的原版约 16.44 MB。
- Android 5.0 及以上，arm64-v8a；在小米 15 / Android 16 / HyperOS 3.0.307.0 上检查。
- 交付 APK 与本次提供的原 2.0.5 APK 签名一致，支持覆盖安装并保留应用数据。
- 自行编译需要自行配置签名，参考 `android/key.properties.example`；源码不包含签名密钥或密码。

## 修改

- 播放地址加载失败与超时重试，停滞后刷新音源，再次停滞时换下一首。
- 防止快速切歌时旧请求覆盖新歌曲，同步歌曲信息、歌词、封面和真实播放状态。
- 补全系统播放、暂停和队列控制，用于通知、锁屏及超级岛媒体入口。
- 恢复作者修改的原侧栏组件，并对照原 APK 还原展开位置、阴影、菜单与本地音乐入口。
- 恢复本地歌曲、歌手、专辑、网易云缓存及歌曲信息页面，适配 Android 音频权限。
- 移除赞助二维码入口、页面和图片。
- 移除未使用的 Rive 原生库，启用代码与资源精简，减少安装包体积。

## 验证范围

18 项播放回归与 1 项侧栏组件检查通过，详见 [FIXES.md](FIXES.md)。真机已检查首页、播放页、原版侧栏展开与本地曲库读取；使用者确认可播放。精简版另在真机检查了系统播放与暂停：状态正确，播放进度推进。超级岛入口和信息更新已观察到，卡片展开与按钮交互尚未全面验证。本地标签写入和缓存解密也未列为已全面通过。

## 编译

验证环境：Flutter 3.24.5 / Dart 3.5.4、JDK 17、Android compileSdk / targetSdk 34。

```sh
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64
```

本仓库保留其他平台源码，但本次交付与验证针对 Android。

## 来源与致谢

- 原项目与原作者：[2697a/bujuan](https://github.com/2697a/bujuan)、[2697a](https://github.com/2697a)。
- 修复基础：上游 `2.0.0` 分支的 `d32b3c3` 提交；原侧栏与本地音乐从上游旧提交恢复。
- 上游说明存档：[UPSTREAM_README.md](UPSTREAM_README.md)。
- 第三方组件与原许可证：[CREDITS.md](CREDITS.md)。
