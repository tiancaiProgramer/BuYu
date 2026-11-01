# 署名与来源

- 应用对外名称统一使用 `BuYu`，TV 显示名使用 `BuYu TV`，后续新安装包文件名使用 `BuYu` 前缀。历史版本名称、原项目来源和许可证按实际记录保留。
- 本地原签名材料位于 `G:\Data\ApkFuture\BuYu\private-signing`：`bujuan.jks` 和 `signing-credentials.properties`。凭据字段为 `KEYSTORE_PATH`、`KEY_ALIAS`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`；签名时读取外部文件，不将私钥或密码写入仓库、日志或补丁。原正式版证书 SHA-256 为 `509c5b1efbd03aeed564a0a3c6072e0c098445596407e28dbfde9b3ddbc7b022`。
- 本维护分支当前维护者为 tiancaiProgramer。后续更新说明和 CHANGELOG 对应版本条目使用“维护与新增功能：tiancaiProgramer”。
- 新编写的第一方源码文件使用注释 `Community maintenance and new features: tiancaiProgramer.` 记录维护署名；不要在未修改的第三方或原始文件上添加独立创作声明。
- README 突出当前维护者。原项目、2697a / sixbugs 及第三方来源集中记录在“来源与致谢”和 CREDITS.md。
- 保留原有源码版权声明、LICENSE 中的 `Copyright (c) 2023 sixbugs`、MIT 全文及随安装包分发的许可。维护署名不替代原作品的版权信息。

# 开发存储位置（2026-11-01 用户指定）

- 项目唯一开发根目录：`G:\Data\ApkFuture\BuYu`；源码直接在本目录。后续读取和保存均从此处进行，不再使用旧 `Dev-Continuations\BuYu`、`bujuan-fixed`、`bujuan-tools`、`BuYu-apk` 或 F 盘签名目录。
- 构建和发布脚本、Flutter 与项目依赖缓存放 `tools`；APK 放 `dist`；实机记录和迁移核验放 `testing`；旧版本及补丁放 `history`。签名材料仅在 `private-signing`，禁止提交或上传。
- Android SDK/JDK 复用 `G:\Data\ApkFuture\Loading\shared-tools\android-build`；项目自己的日志、临时文件和缓存必须留在 BuYu 内。使用 `tools\Set-BuYuEnvironment.ps1` 初始化环境。
- 历史压缩包、原始日志及核验记录中的旧地址保留原样，使用 `testing\migration-20261101` 的迁移清单定位；不将旧日志当作新构建或新实测。
