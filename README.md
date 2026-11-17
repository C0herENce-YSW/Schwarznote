# Schwarznote

一个运行在 Apple TV 上的**非官方**小红书 / rednote 客户端，用遥控器在电视上刷笔记。

> ⚠️ 本项目与小红书（行吟信息科技）没有任何关系，仅供个人学习和研究使用。
> 它通过小红书网页版的接口工作，平台随时可能改动接口导致无法使用，也可能对使用非官方客户端的账号进行风控。使用风险请自行承担。

## 功能

- **扫码登录**：在电视上显示二维码，用手机小红书 App 扫码登录；登录过期会自动回到扫码页
- **国内 / 海外两个站点**：小红书（xiaohongshu.com）和 rednote（rednote.com）
- **发现**：浏览推荐笔记，查看图文和视频笔记详情、全屏看图
- **搜索**、**消息**（私信、通知）、**个人主页**
- **遥控器快捷键**：在笔记详情页用遥控器按键点赞、收藏、评论，按键可在设置里自定义

## 分支说明

| 分支 | 签名方式 | 说明 |
|---|---|---|
| `feature/tvos-webkit`（默认） | 在 Apple TV 上用系统自带的网页引擎签名 | 不需要额外的服务，装上就能用 |
| `feature/qr-login` | 由 Mac 上运行的签名服务（`signer/`）签名 | 需要一台和 Apple TV 在同一局域网、一直开着的 Mac |

> 已知问题：国内账号在海外网络下可能无法登录（错误码 300012，被平台识别为自动化浏览器）。这是平台的限制，本项目不会尝试绕过。

## 安装

tvOS 不能直接安装别人打包好的安装包，需要你用自己的 Apple ID 编译安装。免费的 Apple ID 就可以。

### 需要准备

- 一台 Mac，安装 **Xcode 27.2 或更新版本**（项目使用 Xcode 27 的新项目格式）
- 一台 Apple TV（tvOS 17.6 或更新版本），和 Mac 连在同一个网络
- 一个 Apple ID

### 步骤

1. 克隆仓库并用 Xcode 打开：
   ```bash
   git clone https://github.com/C0herENce-YSW/Schwarznote.git
   open Schwarznote/Schwarznote.xcodeproj
   ```
2. 配对 Apple TV：在 Apple TV 上打开 **设置 → 遥控器与设备 → 远程 App 与设备**，然后在 Xcode 的 **Window → Devices and Simulators** 里选中它并配对。
3. 设置签名：在 Xcode 左侧选中项目 → Target **Schwarznote** → **Signing & Capabilities**：
   - **Team**：选你自己的 Apple ID（没有的话在 Xcode → Settings → Accounts 里登录）
   - **Bundle Identifier**：改成你自己的，比如 `com.你的名字.Schwarznote`。默认的 ID 已经被注册，不能重复使用
4. 在 Xcode 顶部选择你的 Apple TV 作为运行目标，按 **⌘R** 编译并安装。
5. 第一次打开时，如果 Apple TV 提示“不受信任的开发者”，到 Apple TV 的设置里找到你的开发者证书并选择信任。

### 关于有效期

- **免费 Apple ID**：安装的 App 7 天后会打不开，重新连上 Xcode 按一次 ⌘R 即可续期，登录状态和数据不会丢。
- **付费开发者账号**（Apple Developer Program）：有效期 1 年。

### 使用 `feature/qr-login` 分支时

还需要在 Mac 上运行签名服务（需要 Python 3）：

```bash
git checkout feature/qr-login
./signer/run.sh
```

第一次运行会自动安装依赖和 Chromium。服务默认监听 `8790` 端口；在 App 的登录页填入 Mac 的局域网地址，例如 `http://192.168.1.10:8790`。

如果不想让局域网里的其他设备使用你的签名服务，可以设置一个口令，并在 App 里填入同样的口令：

```bash
SIGNER_TOKEN=你的口令 ./signer/run.sh
```

## 许可证

[MIT](LICENSE)
