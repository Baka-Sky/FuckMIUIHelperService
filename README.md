# FuckMIUIHelperService!

一个面向小米 HyperOS / MIUI 的 Magisk / KernelSU / SukiSU 通用模块，用于彻底移除并持续压制以下预置组件：

| 显示名 | 包名 | 说明 |
|---|---|---|
| SystemHelper | `com.mobiletools.systemhelper` | 非小米常规命名的预装组件，内含百度定位 SDK（精确定位、基站/WiFi 指纹、设备标识） |
| MIUIGuardProvider | `com.miui.guardprovider` | 小米安全组件，带 OneTrack 统计与云查上报，权限极大（录音、录屏、全部文件） |
| MIUI 安全键盘 | `com.miui.securityinputmethod` | 系统密码安全输入法（本身无网络权限，可选移除） |
| MiTrustService | `com.xiaomi.trustservice` | 小米互信/互联服务，带 INTERNET，会访问 `micloud.xiaomi.net` 设备与查找接口 |

---

## 工作原理

模块采用四层机制，不依赖“冻结/禁用”（MIUI 会通过系统应用恢复、应用商店更新、OTA 重新启用）：

### 1. 开机扫描前抹除（post-fs-data）

在 PackageManager 扫描应用之前，把目标 APK 所在目录 bind-mount 成一个空目录：

```
/system/priv-app/SystemHelper
/product/app/MIUIGuardProvider
/product/pangu/system/priv-app/SystemHelper
/product/app/MIUISecurityInputMethod
/product/app/MiTrustService
```

同时动态扫描 `/system`、`/system_ext`、`/product`、`/vendor`、`/odm` 下所有匹配目录，一并覆盖。系统启动后**根本看不到这些包**。

### 2. 低开销看门狗（service）

每 10 秒做一次纯文件系统检查（`/data/app/*/*` 目录名匹配），不经过 PackageManager，CPU 占用接近 0。

一旦发现目标包被任何途径装回（应用商店更新、系统恢复、手动安装），立即执行：

```
force-stop → appops 拒绝后台/前台 → pm suspend → pm disable-user
→ pm uninstall → 删除 /data/app、/data/data、/data/user* 残留
→ 重新 bind-mount
```

### 3. netfilter 全协议封禁

拿到目标包 UID 后，在 `iptables` / `ip6tables` 的 OUTPUT / INPUT 链插入：

```
-m owner --uid-owner <uid> -j DROP
```

TCP / UDP / QUIC / DNS / HTTP / HTTPS 全部阻断，进程连域名都解析不了。

### 4. 自动回收与自我保护

- 包被清除 60 秒后，自动删除对应 UID 的 netfilter 规则，避免 UID 复用误伤新应用
- 所有系统调用带 `timeout 5`，查不到 UID / 包体时直接跳过，主循环永不卡死
- 日志超过 64 KB 自动截断，只保留最近 100 行
- 检测日志 60 秒去重，不会刷屏

---

## 安装

1. 下载 Release 中的 `FuckMIUIHelperService-*.zip`
2. 在 Magisk / KernelSU / SukiSU 管理器中「从本地安装」
3. 重启设备

重启后可在模块列表确认模块已启用。

## 卸载

删除模块并重启即可。`uninstall.sh` 会顺带清理 netfilter 规则；即使残留，重启后也会全部消失。

## 日志

```
/data/local/tmp/FuckMIUIHelperService.log
```

正常只记录开机、检测、清理三类事件，体积封顶 64 KB。

## 兼容性

- Android 9 ~ 17（依赖动态分区 + root 方案）
- Magisk / KernelSU / SukiSU（LKM 或 GKI 均可）
- 需要 root 与可用的 `iptables` / `ip6tables`

## 已知影响

- 移除 `MIUIGuardProvider` 后，小米安全中心的部分云查/支付保护功能不可用
- 移除 `MIUISecurityInputMethod` 后，密码框将回落到普通输入法，个别银行类 App 可能提示未使用安全键盘
- 移除 `MiTrustService` 后，小米互联/多设备协同、查找设备等依赖互信服务的功能可能不可用
- 系统 OTA 升级后模块仍然生效，但若 OTA 改动了分区路径，可能需要更新目录规则

---

## 免责协议 / Disclaimer

**使用本模块即表示你已阅读并同意以下全部内容：**

1. 本模块仅用于**个人自有设备**的系统精简与隐私防护，不得用于任何商业用途或非法目的。
2. 修改系统分区、隐藏/卸载系统应用、修改 netfilter 规则均属于**高风险操作**，可能导致系统功能异常、应用崩溃、无法开机或数据丢失。
3. 使用前请自行备份重要数据与 boot / init_boot 镜像。因使用本模块造成的任何直接或间接损失，**作者与贡献者不承担任何责任**。
4. 本模块按“现状”提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性及不侵权担保。
5. 本模块与小米、Redmi、POCO、Google 及其关联公司**没有任何隶属或合作关系**，所有商标归其各自所有者。
6. 若你所在地区法律法规禁止此类系统修改行为，请立即停止使用。
7. 你可以自由修改与分发本模块，但需保留 GPL-3.0 许可证，并自行承担分发带来的全部责任。

**如果你不同意上述任何条款，请立即删除本模块并恢复系统。**

---

## 许可证

[GPL-3.0](LICENSE)
