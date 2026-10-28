# 来源与许可

## 当前维护与新增功能

- 当前维护者：[tiancaiProgramer](https://github.com/tiancaiProgramer)。
- 本维护分支的后续开发、新增功能、横屏适配、问题修复及版本维护署名 tiancaiProgramer。
- 新增内容的维护署名与上游原始作品的作者署名分别说明，不将上游作者标为本分支新增功能的作者。
- 后续发布说明和迭代条目继续注明维护者；新编写的源码文件可添加维护署名，保留原有文件中的版权声明和第三方许可。

## 不倦 BuJuan

- 原项目：https://github.com/2697a/bujuan
- 原作者：https://github.com/2697a ，项目许可证署名 sixbugs。
- 原版权：Copyright (c) 2023 sixbugs。
- 原许可：MIT，全文保留在 [LICENSE](LICENSE)，亦随 APK 打包于 `assets/BUJUAN_LICENSE.txt`。
- 本仓库为该项目的修复与维护，不声称独立创作原播放器，也不代表原作者官方发布。

## 恢复的组件

- flutter_zoom_drawer：https://github.com/medyas/flutter_zoom_drawer 。恢复了 BuJuan 上游维护的定制版本，原许可见 [插件 LICENSE](plugins/flutter_zoom_drawer/LICENSE)。
- on_audio_edit：https://github.com/LucJosin/on_audio_edit 。恢复了 BuJuan 上游版本并适配构建环境，原许可见 [插件 LICENSE](plugins/on_audio_edit/LICENSE)。

## 上游列出的参考项目

原项目 README 同时致谢 [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)、[UnblockNeteaseMusic/server-rust](https://github.com/UnblockNeteaseMusic/server-rust) 和 [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)。上游原文保留于 [UPSTREAM_README.md](UPSTREAM_README.md)；此处记录来源，不声明本 Android 修复包启用了所有上游历史功能。

其余 Flutter / Android 依赖遵循各自许可证，Flutter 依赖许可通知随安装包提供。

## 双音源连接研究

新增 QQ音乐适配由本维护分支编写，协议研究参考了 [jsososo/QQMusicApi](https://github.com/jsososo/QQMusicApi) 与 [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi) 的接口说明和实现行为。这两个参考项目使用 GPL-3.0，未将其源码、模块或服务端打包进本应用；本应用没有内置或依赖公共代理服务。QQ音乐名称、页面及音乐内容归对应权利方，接口可用性和账号权限由平台决定。

云端歌单协议字段另参考 [Yyyangshenghao/simple-music 的 QQ音乐 API 文档](https://github.com/Yyyangshenghao/simple-music/blob/master/docs/qq-music-api.md)；用于核对接口事实，未复制或打包其源码。
