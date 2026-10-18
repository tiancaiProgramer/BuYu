# BuYu 2.0.6（2063）登录方式

维护与新增功能：**tiancaiProgramer**。日期：2026-10-18。

本说明保留 2063 历史实现。用户随后确认密码、短信直连均受到平台风险限制，因此入口已在 2066 移除；请参阅 [当前网页登录流程](login-methods-2066.md)。以下测试结果不代表真实账号认证成功。

## 当时提供的入口

- **短信验证码**：默认入口，支持中国大陆手机号（+86）。输入手机号后点击“获取验证码”，收到短信后输入 4 至 6 位验证码，再点击“立即登录”。
- **账号密码**：切换到“账号密码”，输入手机号或网易邮箱及密码。
- **二维码**：保留网易云音乐 App 扫码及手机确认流程。

登录表单限制最大宽度并支持滚动，适配手机及平板。获取验证码有请求防重及 60 秒重发间隔；页面加载、切换模式和点击“立即登录”都不会自动发送短信。账号、密码及短信验证码不写入日志。

## 接口修正

原代码的手机号及邮箱密码请求仍使用旧 `/login` 系列路径。根据维护中的 API 实现，当前请求采用 `/weapi/w/login/cellphone` 及 `/weapi/w/login`，补齐登录类型、HTTPS、默认区号和保持登录字段；短信发送补齐 `secrete` 参数。短信登录直接提交验证码，不发送密码。

参考来源：[手机号登录实现](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/master/module/login_cellphone.js)、[邮箱登录实现](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/master/module/login.js)、[发送验证码实现](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/master/module/captcha_sent.js)、[接口文档](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/master/public/docs/home.md)。

平台要求行为验证或限制请求频率时，页面显示实际原因，并提示完成官方验证或切换扫码。没有实现滑块代解、验证码绕过或对第三方账号进行反复尝试。

## 验证与交付

- 完整回归：**128 项通过**，默认跳过 2 项联网检查。
- 联网检查单独执行：**2 项通过**。官方二维码密钥及待扫码状态正常；使用空参数请求确认新的手机号及邮箱接口能返回业务校验响应。该检查不发送短信，也不验证真实账号认证成功。
- 新增回归覆盖短信显式发送、请求防重、重发间隔、号码和验证码校验、前导零、成功后账号同步、退出后的旧响应、安全验证提示，以及手机 / 平板横竖屏布局。
- 修改的登录页面及测试文件静态分析无问题。
- ARM64 / ARM32 release 构建均使用原正式版证书签名，包名 `com.sixbugs.bujuan`，版本 `2.0.6`（2063）。签名、应用显示名、版本及 ZIP 对齐检查通过。
- ARM64 构建已通过 `adb install -r` 更新到连接的 `25091RP04C` 设备，安装成功，应用启动并恢复既有账号首页；未退出账号或清除数据。

最新文件位于 `G:\Data\BuYu-apk`：`BuYu-2.0.6-2063-arm64.apk`、`BuYu-2.0.6-2063-arm32.apk`。SHA-256 见同目录 `checksums-2063.json`。本次没有请求向真实手机号发送短信，完整验证码收发和账号密码认证需用户自行在设备上确认。
