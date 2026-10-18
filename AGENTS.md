# 署名与来源

- 应用对外名称统一使用 `BuYu`，TV 显示名使用 `BuYu TV`，后续新安装包文件名使用 `BuYu` 前缀。历史版本名称、原项目来源和许可证按实际记录保留。
- 本地原签名材料位于 `F:\apk\Tianlai`：`bujuan.jks` 和 `signing-credentials.properties`。凭据字段为 `KEYSTORE_PATH`、`KEY_ALIAS`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`；签名时读取外部文件，不将私钥或密码写入仓库、日志或补丁。原正式版证书 SHA-256 为 `509c5b1efbd03aeed564a0a3c6072e0c098445596407e28dbfde9b3ddbc7b022`。
- 本维护分支当前维护者为 tiancaiProgramer。后续更新说明和 CHANGELOG 对应版本条目使用“维护与新增功能：tiancaiProgramer”。
- 新编写的第一方源码文件使用注释 `Community maintenance and new features: tiancaiProgramer.` 记录维护署名；不要在未修改的第三方或原始文件上添加独立创作声明。
- README 突出当前维护者。原项目、2697a / sixbugs 及第三方来源集中记录在“来源与致谢”和 CREDITS.md。
- 保留原有源码版权声明、LICENSE 中的 `Copyright (c) 2023 sixbugs`、MIT 全文及随安装包分发的许可。维护署名不替代原作品的版权信息。
