# wechat-muse-bridge

**把微信接到 Muse：腾讯官方 iLink 登录 + 文件队列桥 + Muse 分拣回复。**

微信消息经腾讯官方 iLink Bot 通道（ClawBot）进入本机桥，转成 JSON 落盘到 `inbox/`；Muse 读取、理解、组织回复后写入 `outbox/`，daemon 发回微信。只出站长轮询，不对外开任何端口。

```
WeChat ──iLink──▶ bridge daemon ──▶ inbox/*.json ──▶ Muse（hook，5 秒触发）
       ◀────────────────────────── outbox/*.json ◀── Muse 回复
```

## 为什么是这一套

2026-11-10 实测：第三方桥（本仓库 `bridge/login.py`）和 wx-bot 的扫码登录连续失败——微信扫码后立刻提示“二维码已过期”，换了 7 张码、两种请求参数都不行；而腾讯官方 `openclaw channels login` 出的码一次就扫上了。结论：**登录必须走官方 CLI**，桥只负责传输和收发。完整经过和测量数据见 [`docs/lessons.md`](docs/lessons.md)。

## 组成部分

| 部分 | 作用 |
| --- | --- |
| `bridge/` | 传输层（vendored 自 [Mango123-oss/WeChat-bridge](https://github.com/Mango123-oss/WeChat-bridge)，MIT）：daemon 长轮询收发、媒体加解密、文件队列 |
| `scripts/official_login.py` | 官方登录的改装：跑 `openclaw channels login`，把终端二维码转成带编号的图片发给用户扫 |
| `scripts/connect_muse.py` | 把官方登录的新凭证接进桥：停网关、写凭证、起 daemon、验游标 |
| `scripts/supervise-daemon.sh` | daemon 的 supervisor：setsid 脱离会话启动，死了 2 秒内自动重启，退出码记进 `logs/supervisor.log`；登录过期时不重启 |
| `scripts/hooks/wechat-bridge-triage.sh` + `scripts/hooks/triage-prompt.md` | 5 秒触发的分拣：收件箱有消息就唤醒 Muse 回复；daemon 掉了自己拉起 supervisor；只有登录过期或反复掉线才唤醒告警 |

## 快速开始

```bash
git clone https://github.com/onlyoyrao999/wechat-muse-bridge
cd wechat-muse-bridge
./scripts/install.sh        # 装 openclaw + 插件 + 桥的 venv、配置
python3 scripts/official_login.py   # 官方登录，按提示扫码（码 2 分钟有效）
python3 scripts/connect_muse.py     # 接进桥并启动 daemon
```

装好后先用自己的微信给 ClawBot 发一条消息，Muse 才能回复你（微信规定：机器人不能主动发起会话）。

各步细节和排障见 [`docs/lessons.md`](docs/lessons.md)。

## 回复是怎么工作的

- `bridge/daemon.py` 常驻：长轮询 iLink 收消息 → `bridge/inbox/<ts>-<id>.json`；`bridge/outbox/*.json` → `sendmessage` 发回微信。
- `scripts/supervise-daemon.sh` 托管 daemon：setsid 脱离会话启动，退出后 2 秒内自动重启，退出码记进 `logs/supervisor.log`；登录过期（`state/flags/session_expired`）时不重启，等用户重新扫码。
- `scripts/hooks/wechat-bridge-triage.sh` 每 5 秒检查一次：收件箱有消息就唤醒 Muse；daemon 掉了就自己拉起 supervisor，不用等 Agent；只有登录过期、或 daemon 10 分钟内掉超过 5 次才唤醒告警。
- Muse 按 `scripts/hooks/triage-prompt.md` 处理：读消息（含媒体）、写纯文本回复到 `outbox/`、把处理过的收件移入 `state/processed/`，绝不重复回复。带媒体的回复可加 `media_path`（视频/图片 100MB 以内）。
- 只接扫码本人的微信号：`bridge/config.json` 的 `allowed_users` 留空时，首个发信人自动配对锁定。

## 限制（微信官方）

- 仅一对一私聊，不支持群聊；机器人号进不了群。
- 用户必须先发消息（context_token 机制），助手不能主动发起会话。
- 连续约 10 条不回复会被限流，用户回一句重置。
- 登录态约 30 天过期（错误码 -14），过期后重新扫码。
- 长轮询连接被网关周期性断开是正常现象，daemon 自动重试；判健康看三样：`state/cursor.txt` 最近几分钟有更新、daemon 保持 3 个线程、日志持续滚动。

## 安全

- 仓库里没有任何密钥、token、账号 id：`bridge/state/`（凭证、游标、context）、`inbox/`、`outbox/`、`qr/`、日志、二维码图片都在 `.gitignore` 里。
- 登录凭证只存在本机 `bridge/state/credentials.json`，权限 0600。
- 代理密码（如有）只写进本机 `~/.config/wx-bot/env` 或系统环境变量，绝不进仓库。

## 致谢

- 传输层 `bridge/` 来自 [Mango123-oss/WeChat-bridge](https://github.com/Mango123-oss/WeChat-bridge)（MIT）。
- 登录走腾讯官方 [@tencent-weixin/openclaw-weixin](https://www.npmjs.com/package/@tencent-weixin/openclaw-weixin)（`openclaw channels login`）。
