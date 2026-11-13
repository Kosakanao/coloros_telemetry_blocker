# 开发说明

## 结构

```
coloros_telemetry_blocker/
├── module.prop            模块元数据
├── customize.sh           安装时 chcon + 设置权限（无挂载逻辑）
├── system/etc/hosts       屏蔽清单（65 条）
├── webroot/index.html     图形化编辑器（KernelSU WebUI）
├── docs/                  README 截图
├── build.py               打包成 dist/*.zip
└── deploy.ps1             推送到手机（开发用）
```

## 三条硬约束

**不自己挂载。** 模块只提供 `system/etc/hosts`，由 KernelSU metamodule（Hybrid Mount）以 magic mount 覆盖。模块里不应出现任何 `mount` 命令——写了也是重复动作，还会和 metamodule 抢同一个目标。

**保存必须保留 inode。** 挂载绑在宿主文件 inode 上，`sed -i`（写临时文件再 rename）和 `cp` 都会换 inode，挂载继续指向被删的旧 inode，表现为「`cat` 内容正确、解析却走真实 IP」。只能用 `>>` 追加或 `cat > 文件` 原地覆盖。

**文件必须 `chcon system_file`。** `/data/adb` 下新建的文件默认标签是 `adb_data_file`，netd / DNS 解析器读不到，hosts 会被静默忽略——不报错，就是不生效。

## WebUI 桥

`webroot/index.html` 通过管理器的 WebUI 桥执行命令。实测 BakaSU / KernelSU Next 的形态是：

```js
const out = ksu.exec(cmd);   // 单参数，同步返回 stdout 字符串
```

传第二个参数（例如 `{ cwd: "/" }`）会让整个调用返回 `undefined`，页面表现为一直「读取中」。所以封装里只传 `cmd`，返回值再做一次归一化，兼容返回 `{ errno, stdout, stderr }` 的实现：

```js
function sh(cmd) {
  let r = ksu.exec(cmd);
  if (r && typeof r.then === "function") return Promise.resolve(r).then(norm);
  return Promise.resolve(norm(r));
}
```

另外这个桥会吞掉 stdout 末尾的换行，回读比对时要先 `replace(/\n+$/, "")`。

## 构建

```sh
python build.py
```

产物 `dist/coloros_telemetry_blocker-v<version>.zip`，zip 根目录即 `module.prop`，`customize.sh` 保留 0755。

## 部署

```powershell
.\deploy.ps1          # 同步文件到已安装的模块目录（不重启）
.\deploy.ps1 -Zip     # 打包 + ksud 安装（需重启）
```

`adb` 默认从 `PATH` 找，也可以 `-Adb "C:\...\adb.exe"` 指定；多设备时用 `-Device <serial>`。

hosts 走「推到 `/data/local/tmp` 再 `cat >`」保留 inode，最后统一 `chmod` + `chcon`。

## 验收

1. 管理器里长按模块卡片 → 顶部 `Hybrid Mount ✓`
2. 改一行保存 → 提示「已保存，立即生效」
3. `ping -c1 adx.ads.heytapmobi.com` → `127.0.0.1`
4. `md5sum` 模块里的 hosts 与 `/system/etc/hosts` 一致（挂载没断）

## 版本

| 版本 | 变更 |
|---|---|
| v2.0 | 由 `noir_hosts` 改名 |
| v2.1 | 挂载交给 metamodule，去掉自己 mount |
| v2.2 | 去掉 boot 脚本与 ctb CLI，改为模块 WebUI 图形编辑器 |
| v2.3 | 修正 WebUI 桥调用，保存后回读校验 |
