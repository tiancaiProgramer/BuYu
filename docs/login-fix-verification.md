# 登录修复验证

维护与新增功能：**tiancaiProgramer**。

日期：2026-10-17。基于 `main` 的 `a5f5c4c`，Flutter 3.24.5 / Dart 3.5.4，Windows。使用仓库原始 `pubspec.lock`，未升级依赖。

## 问题与修复

首页头像和侧栏通过 `/login` 打开登录，但路由声明及生成文件均缺失该入口。现在注册 `LoginViewPage` 并重新生成路由；生成器同时同步了现有歌手页的参数声明，两处调用改用对应的类型参数。

密码登录原来打开加载对话框后未关闭，成功时只写缓存，未更新首页账号状态。现在以页面内的登录进度及错误提示替代阻塞对话框，并等待 `UserController.getUserState()` 同步账号、首页状态及 Hive 缓存后返回。账号输入去除首尾空白，保留密码原文，邮箱使用邮箱接口。

二维码轮询现在区分 800 / 801 / 802 / 803 状态；提供刷新、过期、网络失败及待确认提示，避免请求重叠。刷新、关闭或页面销毁后，旧请求不能再更新页面或跳转。授权后等待资料同步，资料获取失败时保留二维码并重试。

API 仅将成功且带用户资料的响应持久化为已登录；错误及匿名响应不能覆盖有效账号。初始化完成后才继续，避免初始化清理与新登录竞争；旧版保存的失败响应被视为无效缓存。

## 自动验证

```sh
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs --build-filter=lib/routes/router.gr.dart
flutter test --no-pub --reporter expanded
flutter test --no-pub test/login_live_smoke_test.dart --dart-define=BUJUAN_LIVE_LOGIN=true --reporter expanded
```

- 全量回归：**120 项通过**，默认跳过 1 项联网测试。
- 新增 15 项登录回归：路由匹配、错误及匿名响应、无效缓存恢复、初始化与持久化、手机号及邮箱 API 失败、密码错误、资料同步、网络重试、重复点击、二维码展示及状态、过期与刷新、关闭后的旧请求、轮询重叠，以及两种横屏尺寸。
- 联网测试单独执行：**1 项通过**。官方接口成功返回二维码密钥（200）及等待扫码状态（801）。测试使用临时空会话，不记录二维码密钥或账号凭据。
- 两处原封面测试的路径断言改为适应 Windows；产品封面逻辑未更改。

账号密码正确登录及扫码后手机确认的完整链路由可控替身验证，尚未使用真实个人账号或 Android 真机确认。

## 本地 APK（测试签名）

2026-10-17 已成功执行以下构建，未发布到 GitHub Releases：

```sh
flutter build apk --no-pub --release --flavor mobile --split-per-abi --target-platform android-arm,android-arm64
```

交付目录为 `G:\Data\bujuan-apk`：

- `bujuan-2.0.6-loginfix-arm64-test.apk`：13,450,725 字节，ARM64。
- `bujuan-2.0.6-loginfix-arm32-test.apk`：13,177,624 字节，ARM32。

两个文件均通过 `apksigner verify`，包名 `com.sixbugs.bujuan`，版本 `2.0.6` / `2062`，最低 Android API 21，目标 API 34。架构已通过 `aapt dump badging` 核验，交付目录包含 SHA-256 校验记录。

这是 release 构建，但使用 Android 测试签名：证书 SHA-256 为 `401bae41cd07757b965bb4dc2e7c0820a7af8cbfc67acf958de3770e8cbe8545`，与仓库记录的正式版证书 `509c5b1efbd03aeed564a0a3c6072e0c098445596407e28dbfde9b3ddbc7b022` 不同。因此不能直接覆盖已安装的正式版；保留现有正式版，覆盖升级需要原签名密钥重新签名。

改名为 Tianlai 后已重新编译两个安装包，位于 `G:\Data\Tianlai-apk`，分别为 `Tianlai-2.0.6-loginfix-arm64-test.apk`（13,450,753 字节）和 `Tianlai-2.0.6-loginfix-arm32-test.apk`（13,177,598 字节）。两个文件的签名校验通过，`aapt` 验证应用显示名均为 `Tianlai`。签名及覆盖安装限制与上述测试包相同。TV、横屏和更新检查共 31 项回归通过；其他平台的名称声明已同步，但本次仅编译 Android。

## 原签名安装包（2026-10-18）

使用维护者提供的外部原签名材料重签，当前应使用以下文件，目录为 `G:\Data\Tianlai-apk`：

- `Tianlai-2.0.6-loginfix-arm64.apk`：13,447,997 字节。
- `Tianlai-2.0.6-loginfix-arm32.apk`：13,173,569 字节。

两个文件均通过 `apksigner verify`，v1 / v2 / v3 签名有效，签名证书 SHA-256 与原正式版一致：`509c5b1efbd03aeed564a0a3c6072e0c098445596407e28dbfde9b3ddbc7b022`。包名 `com.sixbugs.bujuan`，版本 `2.0.6` / `2062`，显示名 `Tianlai`，满足覆盖原 2062 正式版的包名、版本及证书条件。未在真实设备执行覆盖安装。

两种架构均通过 ZIP 对齐检查；除签名元数据外，对重签前后的 790 个文件逐项计算 SHA-256，内容全部一致。签名不会改变此前通过回归的应用代码及资源。校验值和校验记录位于交付目录的 `original-signed-checksums.json` 及对应签名、清单文本文件。私钥及密码未复制到仓库或交付目录。

## 当前名称 BuYu（2026-10-18）

按维护者最新要求，应用名称及后续安装包前缀改为 `BuYu`，TV 显示名为 `BuYu TV`。欢迎页、各平台显示名和项目维护约定已同步；上述 Tianlai 文件保留为历史产物。

当前安装包位于 `G:\Data\BuYu-apk`：

- `BuYu-2.0.6-loginfix-arm64.apk`：13,447,997 字节。
- `BuYu-2.0.6-loginfix-arm32.apk`：13,173,569 字节。

重新编译后用原正式版密钥签名，两种架构均通过签名、ZIP 对齐及包清单校验，应用显示名为 `BuYu`，证书 SHA-256 与原正式版一致。包名和版本保持 `com.sixbugs.bujuan` / `2.0.6`（2062）；TV、横屏和更新检查共 31 项回归通过。SHA-256、签名及清单记录保存在同一交付目录。

## 真机覆盖更新（2026-10-18）

已在连接的 `25091RP04C`（piano，ARM64）设备上完成更新。先备份设备原安装包，并确认其证书与更新包一致；随后执行 `adb install -r`，返回 `Success`，设备版本由 `2.0.5`（2026）更新为 `2.0.6`（2062）。未卸载或清除应用数据。

显式启动 `MainActivity` 返回 `Status: ok`，应用进程持续运行，Flutter 路由日志确认进入 `HomeView`、`UserView` 及 `LoginViewRoute`。安装与启动验证通过；完整账号授权及登录后的业务流程尚未验证。安装前 APK 及校验记录保存在 `G:\Data\QA_Evidence\BuYu-device-update-20261018`。

## GitHub 交付状态

本地已完成修复与验证。2026-10-17 的非交互推送权限检查返回无法读取 GitHub 用户名；截至本地交付记录，尚未推送、创建 PR 或修改远程主分支。
