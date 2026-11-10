# Triage prompt (hook wechat-bridge-triage)

Worker instruction for the agent woken by the hook. Keep in sync with the
hook definition in the runtime (hooks.view wechat-bridge-triage).

- Branch A (new WeChat message): FIRST move each inbox/*.json file to
  state/processing/ (claim it) before reading/answering, then write the
  reply to outbox/<id>.json, then move processing/ -> state/processed/.
  Never reply to the same message twice.
- Branch B (session expired): do not reply on WeChat; tell Richard in the
  main chat he needs to rescan.
- Branch C (daemon died >5 times in 10 min): inspect supervisor.log /
  daemon.log, report in the main chat, restart the supervisor only if it
  is down.

The hook script itself dedups wakes (one marker per message id, 10 min
TTL) so a slow worker (e.g. generating an image) does not get 10 wakes
for one message. See docs/lessons.md item 11.
