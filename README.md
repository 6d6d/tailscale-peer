# tailscale-peer-relay

在 `6d6d/tailscale-peer` 的 `relay-server` 分支上用 GitHub Actions 构建带
peer relay server 支持的 Tailscale 容器镜像。

## 分支内容

branch `relay-server`（已推送）：

- `46596c8` `cmd/containerboot: support peer relay server configuration`
  （取自 `truppelito/tailscale` 的分支，原样保留，含 435 行新增测试）
  - 新增环境变量 `TS_RELAY_SERVER_PORT`、`TS_RELAY_SERVER_STATIC_ENDPOINTS`
  - 新增 `appendRelayServerSetArgs` / `tailscaleSetRelayServer`，把这两个
    set-only 参数用 `tailscale set` 下发（`tailscale up` 不接受它们）
  - `TS_EXTRA_ARGS` 里若混入了这两个参数，会被摘出来单独处理
- `c522d42` `ci: build a container image with containerboot peer relay server support`
  - `Dockerfile.relay`
  - `.github/workflows/build-relay-image.yml`

## 镜像

- `ghcr.io/6d6d/tailscale-peer:relay-latest`
- `ghcr.io/6d6d/tailscale-peer:relay-1.103.0`
- `ghcr.io/6d6d/tailscale-peer:relay-1.103.0-relay.<短 SHA>`

平台：`linux/amd64`、`linux/arm64`（`workflow_dispatch` 的 `platforms` 输入可改）。

与官方 `tailscale/tailscale` 镜像一致的部分：三个二进制（`tailscale`、
`tailscaled`、`containerboot`）、同样的 ldflags 版本戳、
`-tags=ts_kube,ts_package_container`、同样的基础包（含 legacy iptables 链接）、
入口点 `/usr/local/bin/containerboot`。

`Dockerfile.relay` 相对官方构建方式的唯一差别：Go 构建阶段固定在
`$BUILDPLATFORM` 并交叉编译 `$TARGETARCH`（多架构不走 QEMU 全量模拟），
显式 `CGO_ENABLED=0`。

## 触发方式

- 向 `relay-server` 分支 push 自动触发
- 或手动：Actions → Build relay-server image → Run workflow

工作流包含三个作业：

| 作业 | 作用 |
| --- | --- |
| `containerboot-test` | `go vet` + `go test ./cmd/containerboot`（信息性，`continue-on-error`，不挡镜像） |
| `image` | 构建并推送多架构镜像，写入 run summary 摘要 |
| `verify` | 拉回已发布镜像：跑 `tailscaled --version`、`tailscale version`，并检查 `containerboot` 里确实编进了 `TS_RELAY_SERVER_PORT`、`TS_RELAY_SERVER_STATIC_ENDPOINTS` |

前置设置（已完成）：仓库 Actions 的 workflow 默认令牌权限需要 write，
否则 `GITHUB_TOKEN` 无法推送 GHCR 包。

## 在容器里跑 peer relay server

```yaml
services:
  tailscale-relay:
    image: ghcr.io/6d6d/tailscale-peer:relay-latest
    restart: unless-stopped
    network_mode: host            # 或显式映射 UDP 端口
    environment:
      TS_AUTHKEY: tskey-auth-xxxx  # 或用 TS_CLIENT_ID/TS_CLIENT_SECRET 等
      TS_STATE_DIR: /var/lib/tailscale
      TS_HOSTNAME: relay-1
      TS_RELAY_SERVER_PORT: "41641"   # UDP 端口，0 表示随机；设置了才启用 relay
      # TS_RELAY_SERVER_STATIC_ENDPOINTS: "203.0.113.10:41641"  # 静态候选端点
    volumes:
      - ./tailscale-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add: [NET_ADMIN]
```

说明：

- `TS_RELAY_SERVER_PORT` 一旦设置就启用 relay 功能，端口绑在所有接口的 UDP 上；
  容器外部必须能访问该 UDP 端口（`network_mode: host` 或映射 `41641/udp`）。
- `TS_RELAY_SERVER_STATIC_ENDPOINTS` 用于 relay 位于 NAT 后、需要对外宣告
  `IP:端口` 候选的情况，多个用逗号分隔，IPv6 要写成 `[2001:db8::1]:41641`。
- 把参数写进 `TS_EXTRA_ARGS` 也可以，containerboot 会把它们摘出来、改用
  `tailscale set` 下发（`tailscale up` 不接受这两个参数）。
- 非 `TS_AUTH_ONCE` 模式下，这两个设置在节点进入 Running 之后才应用；
  `TS_AUTH_ONCE=true` 时随 `tailscale set` 一起下发。

节点上核对：

```sh
tailscale get relay-server-port
tailscale get relay-server-static-endpoints
tailscale debug peer-relay-sessions     # 当前 relay 会话
tailscale debug peer-relay-servers      # 已知的 relay 服务器
tailscale status                        # 走 relay 的连接会标 peer-relay
```

## 本地文件

- `tailscale-peer-relay/`：仓库克隆（`origin` = 你的 fork，`truppelito` = 上游分支来源，
  `upstream` = tailscale/tailscale）
- `poll_runs.sh`：轮询 Actions 运行状态的脚本
