# 压力测试

## 启动

1. 以 **debug 模式** 运行 Asmote App
2. 内嵌 HTTP 服务器自动监听 `localhost:9876`

## 运行测试

```powershell
# 一键跑全套
./test_stress/run_stress.ps1

# 或手动 curl
curl http://localhost:9876/stats                                  # 查看状态
curl -X POST http://localhost:9876/stage/storm -d '{"create":50,"switch":500}'  # 创建50个stage并切换500次
curl -X POST http://localhost:9876/stage/switch-storm -d '{"count":1000}'       # 切换1000次
curl -X POST http://localhost:9876/stage/create -d '{"count":30}'               # 创建30个stage
curl -X POST http://localhost:9876/stage/switch -d '{"index":0}'                # 切换到stage 0
curl -X POST http://localhost:9876/stage/delete -d '{"id":"all"}'               # 删除所有stage（保留1个）
```

## API 端点

| 方法 | 路径 | 参数 | 说明 |
|------|------|------|------|
| GET | `/stats` | - | 当前状态快照 |
| POST | `/stage/create` | `{count, name}` | 创建 N 个 stage |
| POST | `/stage/delete` | `{id}` / `{id:"all"}` | 删除 stage |
| POST | `/stage/switch` | `{index}` / `{id}` | 切换 stage |
| POST | `/stage/switch-storm` | `{count}` | 快速切换 N 次 |
| POST | `/stage/set-bg` | `{index, bgId}` | 设置背景 |
| POST | `/stage/storm` | `{create, switch, bg}` | 全流程压力测试 |

## 观察项

- UI 帧率是否下降（检查 `Flutter DevTools`）
- 切换时是否闪白/报错（控制台输出）
- 内存是否持续增长（任务管理器）
