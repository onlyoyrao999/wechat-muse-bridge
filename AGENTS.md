# AGENTS.md — 给接手这个仓库的 Agent

## 这是什么

把微信接到 Muse 的一整套：官方登录（`scripts/official_login.py`）+ 传输桥
（`bridge/`，vendored 自 Mango123-oss/WeChat-bridge，MIT）+ Muse 分拣
（`scripts/hooks/`，5 秒触发）。详见 `README.md` 和 `docs/lessons.md`。

## 三条铁律

1. **登录只走官方 CLI**（`openclaw channels login --channel openclaw-weixin`）。
   第三方桥的 `bridge/login.py` 和 wx-bot 的扫码在 2026-11-10 实测全部立刻过期，
   不要再用它们登录。`bridge/login.py` 留在仓库里只作参考。
2. **同一时间只能有一个客户端轮询同一个会话**。桥的 daemon 跑起来之前，
   必须先停掉 OpenClaw 网关（`scripts/connect_muse.py` 会做），否则两个客户端
   抢消息、游标打架。
3. **仓库里永远不能出现密钥、token、账号 id、二维码图片**。凭证只在
   `bridge/state/credentials.json`（0600）。见 `.gitignore`。

## 部署顺序

`scripts/install.sh` → `scripts/official_login.py`（扫码）→
`scripts/connect_muse.py`（接进桥、起 daemon）→ 装 hook
（`scripts/hooks/wechat-bridge-triage.sh` + `triage-prompt.md`，见 README）。

## 分拣契约

- 入站 `bridge/inbox/<ts>-<id>.json`：`{id, from_user_id, kind, text, ts}`，
  带媒体时多 `media_paths`。
- 出站 `bridge/outbox/<任意名>.json`：`{to_user_id, text}`，可选 `media_path`。
- 处理完必须把收件移入 `bridge/state/processed/`，绝不重复回复。
- 回复只发纯文本，不要 Markdown（微信不渲染）。
- 判 daemon 健康看三样：`state/cursor.txt` 最近几分钟更新、3 个线程、日志滚动；
  不要只看进程存活（会话已死但进程还在的“假活”存在）。
