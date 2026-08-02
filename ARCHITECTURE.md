# 《聲畫合鳴》EchoEtch 项目架构设计文档 v1.0

> 文档定位：从 Demo 到生产级产品的完整技术架构蓝图，按此文档可直接推进开发

---

## 目录

1. [系统概述与设计目标](#1-系统概述与设计目标)
2. [技术选型决策](#2-技术选型决策)
3. [整体架构总览](#3-整体架构总览)
4. [TTS 子系统设计（核心专项）](#4-tts-子系统设计核心专项)
5. [后端架构设计](#5-后端架构设计)
6. [前端架构设计](#6-前端架构设计)
7. [数据模型与存储设计](#7-数据模型与存储设计)
8. [API 接口设计](#8-api-接口设计)
9. [安全与合规设计](#9-安全与合规设计)
10. [部署架构设计](#10-部署架构设计)
11. [性能优化策略](#11-性能优化策略)
12. [开发路线图与里程碑](#12-开发路线图与里程碑)

---

## 1. 系统概述与设计目标

### 1.1 产品核心价值链

```
用户随手记录（文字/图片/语音）
        ↓
   AI 叙事转译（LLM 生成 100-200 字冥想式文本）
        ↓
   语音合成（TTS 流式生成治愈系音频）
        ↓
   回声卡片（图文 + 音频 + 归档）
        ↓
   情绪日记（日历视图 + 历史回放）
```

### 1.2 设计目标

| 维度 | 目标 | 指标 |
|------|------|------|
| **TTS 首包延迟** | 用户点击「合鳴」后听到第一个音节 | < 800ms（豆包 V3 流式） |
| **端到端生成** | 从提交到回声卡片完整展示 | < 5s（文字）/ < 8s（图片/语音） |
| **并发能力** | 同时处理生成请求 | ≥ 50 并发 |
| **可用性** | 服务正常运行时间 | ≥ 99.5% |
| **音频缓存命中率** | 相同内容重复播放 | ≥ 90%（本地缓存） |

### 1.3 设计原则

1. **渐进式演进** - Demo -> Phase 1 -> Phase 2，每阶段可独立上线
2. **TTS 优先** - 语音体验是核心卖点，TTS 子系统单独设计、可插拔
3. **前后端分离** - 后端 API + 前端 SPA，独立部署、独立迭代
4. **适配器模式** - LLM 和 TTS 均通过适配器接口接入，可随时切换供应商

---

## 2. 技术选型决策

### 2.1 技术栈总览

| 层级 | 技术 | 选型理由 |
|------|------|---------|
| 前端框架 | Vue 3 + Vite | 渐进式、轻量、单文件组件、移动端生态好 |
| UI 组件 | 自研组件 + UnoCSS | 疗愈产品需高度定制视觉，组件库反而限制 |
| 后端框架 | FastAPI (Python) | 原生 async、WebSocket 内置、自动 OpenAPI 文档 |
| 数据库 | PostgreSQL | 关系型、JSONB 支持、全文搜索、成熟稳定 |
| 缓存 | Redis | TTS 音频缓存、会话、速率限制 |
| 对象存储 | MinIO / 阿里云 OSS | 音频文件存储 |
| TTS 引擎 | 火山引擎豆包 TTS V3 | 流式输出、低延迟、多情感音色、中文最优 |
| LLM 引擎 | DeepSeek / Qwen (可切换) | 通过适配器接口，支持 OpenAI 兼容协议 |
| 部署 | Docker + Nginx | 容器化部署，Nginx 反向代理 + 静态资源 |

### 2.2 为什么选 FastAPI 而非继续用 Flask

| 对比项 | Flask (当前) | FastAPI (目标) |
|--------|-------------|---------------|
| 异步支持 | 需 gevent/werkzeug hack | 原生 async/await |
| WebSocket | 需 flask-socketio | 内置 WebSocket |
| TTS 流式推送 | 需 SSE 或轮询 | 原生 WebSocket 流式推送 |
| 类型校验 | 手动 | Pydantic 自动校验 |
| API 文档 | 需 flasgger | 自动 OpenAPI 3.0 |
| 性能 | 中等 | 接近 Go（基于 Starlette） |

**关键原因**：TTS 流式推送需要 WebSocket，FastAPI 原生支持，Flask 需要 socketio 层，且异步 TTS 调用与同步 Flask 混用（当前 `asyncio.run()` 在请求线程中阻塞）是严重架构缺陷。

### 2.3 TTS 方案选型深度对比

| 方案 | 首包延迟 | 音质 | 成本 | 流式 | 情感音色 | 稳定性 | 结论 |
|------|---------|------|------|------|---------|--------|------|
| **edge-tts** (当前) | 2-5s | 中 | 免费 | 否(整段) | 否 | 低(非官方API) | 仅适合 Demo |
| **火山引擎豆包 V3** | **200-500ms** | 高 | ¥0.2/万字 | **是(WebSocket)** | **是(多情感)** | 高(官方SLA) | **首选** |
| Azure TTS | 500ms-1s | 高 | ¥1/万字 | 是 | 部分 | 高 | 备选 |
| 阿里云 TTS | 300-800ms | 中高 | ¥0.4/万字 | 是 | 部分 | 高 | 备选 |
| 本地 ChatTTS | 1-3s | 高 | GPU成本 | 否 | 是 | 中 | 隐私敏感场景 |

**选型结论：火山引擎豆包 TTS V3 作为主引擎，edge-tts 作为降级备选。**

豆包 V3 核心优势：
- **流式输出**：文本一次性送入，后端边合成边返回，首包延迟 200-500ms
- **多情感音色**：支持 happy/sad/angry/surprised 等情感，适配疗愈场景
- **服务端缓存**：`cache_config` 参数开启后，相同文本秒级返回
- **V3 接口**：单向流式 `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream`
- **SSML 支持**：可控制停顿、语速、情感强度

---

## 3. 整体架构总览

### 3.1 架构拓扑图

```
                          ┌─────────────────────────────────────────────┐
                          │                   Nginx                      │
                          │  (反向代理 / TLS / 静态资源 / WebSocket 转发) │
                          └──────┬──────────────────────────┬───────────┘
                                 │ HTTP/WS                   │ 静态文件
                                 ↓                           ↓
                    ┌────────────────────────┐    ┌──────────────────┐
                    │    FastAPI Backend      │    │   Vue 3 SPA      │
                    │                        │    │   (前端应用)      │
                    │  ┌──────────────────┐  │    │                  │
                    │  │   API Router      │  │    │  - 首页/记录     │
                    │  │   (REST + WS)     │  │    │  - 等待页        │
                    │  └────────┬─────────┘  │    │  - 回声卡片      │
                    │           │            │    │  - 日记日历      │
                    │  ┌────────↓─────────┐  │    └──────────────────┘
                    │  │  Echo Pipeline    │  │
                    │  │  (生成管线编排)    │  │
                    │  └──┬─────┬─────┬───┘  │
                    │     │     │     │      │
                    │  ┌──↓──┐┌─↓──┐┌─↓───┐  │
                    │  │LLM  ││TTS ││Image│  │
                    │  │Adapt││Adapt││Adapt│  │
                    │  └──┬──┘└─┬──┘└─┬───┘  │
                    └─────┼─────┼─────┼──────┘
                          │     │     │
              ┌───────────┼─────┼─────┼──────────────┐
              │           │     │     │              │
              ↓           ↓     ↓     ↓              ↓
        ┌──────────┐ ┌──────┐ ┌───┐ ┌────────┐ ┌────────┐
        │PostgreSQL│ │Redis │ │OSS│ │豆包TTS │ │LLM API │
        │(用户/日记)│ │(缓存)│ │音频│ │(火山引擎)│ │(DeepSeek)│
        └──────────┘ └──────┘ └───┘ └────────┘ └────────┘
```

### 3.2 请求流转全链路

```
用户点击「合鳴」
    │
    ├─→ POST /api/echo/generate (提交文字/图片/语音)
    │       │
    │       ├─→ [文字模式] → LLM 适配器 → 生成叙事文本
    │       ├─→ [图片模式] → Vision LLM → 图片描述 → LLM → 叙事文本
    │       ├─→ [语音模式] → Whisper ASR → 转文字 → LLM → 叙事文本
    │       │
    │       ├─→ 叙事文本存入 PostgreSQL
    │       │
    │       └─→ 返回 echo_id + narrative（响应结束，不等待 TTS）
    │
    ├─→ 前端展示回声卡片（文字先出）
    │
    └─→ WebSocket /api/tts/stream/{echo_id} (并行发起 TTS)
            │
            ├─→ 检查 Redis 缓存（hash(文本+音色+参数) → audio_key）
            │     ├─ 命中 → 直接推送缓存的音频分片
            │     └─ 未命中 → 调用豆包 V3 WebSocket 流式 TTS
            │
            ├─→ 逐帧推送音频 binary 分片到前端
            │     前端用 MediaSource API 边收边播
            │
            └─→ TTS 完成后将完整音频存入 OSS，元数据存 Redis 缓存
```

**关键设计：叙事生成与 TTS 解耦。** 文字结果先返回，TTS 通过 WebSocket 异步推送，用户先看到文字、几乎同时听到声音，体感延迟大幅降低。

---

## 4. TTS 子系统设计（核心专项）

### 4.1 TTS 子系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    TTS Subsystem                        │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              TTS Service Layer                    │   │
│  │                                                  │   │
│  │  synthesize(text, voice, emotion) → AudioStream  │   │
│  └──────────┬───────────────────┬───────────────────┘   │
│             │                   │                       │
│   ┌─────────↓─────────┐  ┌──────↓──────────┐            │
│   │   Cache Manager    │  │  Engine Router  │            │
│   │                    │  │                  │            │
│   │  - Redis hash 查询  │  │  优先级:         │            │
│   │  - 命中→返回分片    │  │  1. 豆包V3(主)   │            │
│   │  - 未命中→引擎合成  │  │  2. edge-tts(备) │            │
│   └────────────────────┘  └──────┬──────────┘            │
│                                  │                       │
│                    ┌─────────────┼─────────────┐         │
│                    │             │             │         │
│              ┌─────↓─────┐ ┌────↓─────┐ ┌────↓─────┐    │
│              │ 豆包 V3    │ │ edge-tts │ │ Azure    │    │
│              │ WebSocket │ │ Adapter  │ │ Adapter  │    │
│              │ Adapter   │ │          │ │ (预留)   │    │
│              └───────────┘ └──────────┘ └──────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Audio Storage Layer                  │   │
│  │  - OSS/MinIO: 完整音频文件持久化                   │   │
│  │  - Redis: 音频分片缓存 (TTL 1h) + 元数据索引      │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 4.2 豆包 V3 流式 TTS 适配器设计

```python
# tts/adapters/volcengine_v3.py

import asyncio
import json
import uuid
import struct
import websockets
from typing import AsyncGenerator

class VolcEngineTTSAdapter:
    """
    火山引擎豆包 TTS V3 单向流式适配器
    接口: wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream
    """

    def __init__(self, appid: str, access_token: str, cluster: str = "volcano_tts"):
        self.appid = appid
        self.access_token = access_token
        self.cluster = cluster
        self.ws_url = "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream"

    async def synthesize_stream(
        self,
        text: str,
        voice_type: str = "zh_female_cancan_mars_bigtts",
        emotion: str | None = None,
        speed_ratio: float = 1.0,
        encoding: str = "mp3",
    ) -> AsyncGenerator[bytes, None]:
        """
        流式合成，逐帧 yield 音频二进制分片
        首包延迟: 200-500ms
        """
        reqid = str(uuid.uuid4())
        headers = {"Authorization": f"Bearer; {self.access_token}"}

        payload = {
            "app": {"appid": self.appid, "token": "any", "cluster": self.cluster},
            "user": {"uid": "echoetch_user"},
            "audio": {
                "voice_type": voice_type,
                "encoding": encoding,
                "speed_ratio": speed_ratio,
                **({"emotion": emotion, "enable_emotion": True} if emotion else {}),
            },
            "request": {
                "reqid": reqid,
                "text": text,
                "operation": "submit",  # submit = 流式返回
                "model": "seed-tts-1.1",  # 1.1 版本延时更优
            },
            "extra_param": json.dumps({
                "cache_config": {"text_type": 1, "use_cache": True}  # 服务端缓存
            }),
        }

        async with websockets.connect(self.ws_url, additional_headers=headers) as ws:
            await ws.send(json.dumps(payload))

            while True:
                response = await ws.recv()
                if isinstance(response, bytes):
                    # 解析二进制协议: 4字节header + payload
                    header = response[:4]
                    msg_type = (header[0] >> 4) & 0x0F
                    msg_flags = header[0] & 0x0F

                    if msg_type == 0x0B:  # Audio-only response
                        audio_data = response[4:]
                        if len(audio_data) > 0:
                            yield audio_data
                        # msg_flags >= 0x02 表示最后一帧
                        if msg_flags in (0x02, 0x03):
                            break
                    elif msg_type == 0x0F:  # Error
                        error_json = json.loads(response[4:])
                        raise Exception(f"TTS error: {error_json}")
                else:
                    # JSON 控制消息
                    msg = json.loads(response)
                    if msg.get("code", 0) != 0:
                        raise Exception(f"TTS error: {msg}")
```

### 4.3 TTS 缓存策略（三层缓存）

```
用户请求 TTS
    │
    ├─ L1: Redis 音频分片缓存
    │   key: tts:audio:{md5(text+voice+emotion+speed)}
    │   value: 完整音频 bytes (TTL: 24h)
    │   命中率: ~30%（不同用户不同文本）
    │
    ├─ L2: 豆包服务端缓存
    │   通过 cache_config 参数开启，TTL: 1h
    │   命中率: ~15%（短时间内相同文本）
    │
    └─ L3: 本地音频文件
    │   存入 OSS，永久保存用户生成过的所有音频
    │   用于日记回放，无需重新合成
    │
    └─ 前端 MediaSource 缓存
        已播放过的音频缓存在浏览器内存中
        日记回放直接使用，不再请求后端
```

### 4.4 TTS 降级策略

```python
# tts/engine_router.py

class TTSEngineRouter:
    """
    TTS 引擎路由器: 优先级降级策略
    """

    ENGINES = [
        ("volcengine", VolcEngineTTSAdapter),   # 主引擎: 低延迟、高质量
        ("edge_tts", EdgeTTSAdapter),            # 备用: 免费、但慢
        # ("azure", AzureTTSAdapter),            # 预留: 付费稳定
    ]

    async def synthesize_stream(self, text: str, **kwargs) -> AsyncGenerator[bytes, None]:
        for engine_name, engine_cls in self.ENGINES:
            try:
                engine = engine_cls()
                async for chunk in engine.synthesize_stream(text, **kwargs):
                    yield chunk
                return  # 成功则不降级
            except Exception as e:
                logger.warning(f"TTS engine '{engine_name}' failed: {e}, falling back...")
                continue

        # 所有引擎都失败，返回空音频
        raise TTSAllEnginesFailedError("所有 TTS 引擎均不可用")
```

### 4.5 音色配置矩阵

| 模式 | voice_type | 情感 | 语速 | 适用场景 |
|------|-----------|------|------|---------|
| 成人·深夜冥想 | `zh_female_cancan_mars_bigtts` | sad/happy | 0.9 | 温柔女声、慢速 |
| 成人·日常治愈 | `zh_female_cancan_mars_bigtts` | happy | 1.0 | 温暖女声 |
| 成人·男声独白 | `zh_male_M392_conversation_wvae_bigtts` | neutral | 0.95 | 低沉男声 |
| 青少年·元气 | `zh_female_ddjdxbj_mars_bigtts` | happy | 1.1 | 活泼女声 |
| 老年·舒缓 | `zh_female_cancan_mars_bigtts` | neutral | 0.85 | 慢速平缓 |
| 故事·旁白 | `zh_male_M392_conversation_wvae_bigtts` | neutral | 1.0 | 叙事感 |

> 音色 ID 需在火山引擎控制台申请后替换为实际值，以上为文档参考值

### 4.6 前端流式播放设计

```javascript
// 前端 WebSocket 接收 + MediaSource API 边收边播

class TTSStreamPlayer {
  constructor(echoId) {
    this.echoId = echoId
    this.audioContext = new AudioContext()
    this.mediaSource = new MediaSource()
    this.sourceBuffer = null
    this.audio = new Audio()
    this.audio.src = URL.createObjectURL(this.mediaSource)
    this.ws = null
  }

  async start() {
    this.mediaSource.addEventListener('sourceopen', () => {
      this.sourceBuffer = this.mediaSource.addSourceBuffer('audio/mpeg')
      this.sourceBuffer.mode = 'sequence'
    })

    // 连接 WebSocket
    const wsUrl = `${wsBase}/api/tts/stream/${this.echoId}`
    this.ws = new WebSocket(wsUrl)
    this.ws.binaryType = 'arraybuffer'

    this.ws.onmessage = async (event) => {
      if (event.data instanceof ArrayBuffer) {
        // 收到音频分片，追加到 sourceBuffer
        if (!this.sourceBuffer.updating) {
          this.sourceBuffer.appendBuffer(event.data)
        }
        // 首包到达即可播放
        if (this.audio.paused) {
          this.audio.play()
        }
      }
    }

    this.ws.onclose = () => {
      // TTS 流结束
      this.mediaSource.endOfStream()
    }
  }

  stop() {
    if (this.ws) this.ws.close()
    this.audio.pause()
  }
}
```

---

## 5. 后端架构设计

### 5.1 目录结构

```
backend/
├── app/
│   ├── main.py                 # FastAPI 入口，挂载路由
│   ├── config.py               # 配置管理 (Pydantic Settings)
│   ├── deps.py                 # 依赖注入 (DB session, 当前用户)
│   │
│   ├── api/                    # API 路由层
│   │   ├── v1/
│   │   │   ├── echo.py         # 回声生成
│   │   │   ├── tts.py          # TTS WebSocket 流式
│   │   │   ├── diary.py        # 日记 CRUD
│   │   │   ├── theme.py        # 每日主题
│   │   │   └── auth.py         # 用户认证
│   │   └── ws/
│   │       └── tts_stream.py   # TTS WebSocket handler
│   │
│   ├── core/                   # 核心业务逻辑
│   │   ├── echo_pipeline.py    # 生成管线编排
│   │   ├── prompt_manager.py   # Prompt 模板管理
│   │   └── content_filter.py   # 内容安全过滤
│   │
│   ├── adapters/               # 外部服务适配器
│   │   ├── llm/
│   │   │   ├── base.py         # LLM 抽象接口
│   │   │   ├── openai_compat.py # OpenAI 兼容 (DeepSeek/Qwen)
│   │   │   └── vision.py       # 视觉模型适配
│   │   ├── tts/
│   │   │   ├── base.py         # TTS 抽象接口
│   │   │   ├── volcengine_v3.py # 豆包 V3 流式
│   │   │   ├── edge_tts.py     # edge-tts 降级
│   │   │   └── router.py       # 引擎路由器
│   │   └── asr/
│   │       ├── base.py         # ASR 抽象接口
│   │       └── whisper.py      # Whisper 语音转文字
│   │
│   ├── models/                 # 数据模型 (SQLAlchemy)
│   │   ├── user.py
│   │   ├── echo.py
│   │   └── diary.py
│   │
│   ├── schemas/                # Pydantic 请求/响应模型
│   │   ├── echo.py
│   │   ├── diary.py
│   │   └── tts.py
│   │
│   └── utils/
│       ├── security.py         # JWT、密码哈希
│       └── rate_limit.py       # 速率限制
│
├── alembic/                    # 数据库迁移
├── tests/
├── requirements.txt
├── Dockerfile
└── .env.example
```

### 5.2 生成管线编排（Echo Pipeline）

```python
# app/core/echo_pipeline.py

from typing import Optional
import asyncio

class EchoPipeline:
    """
    回声生成管线: 编排 LLM + TTS + 存储
    核心设计: 叙事生成与 TTS 并行解耦
    """

    async def generate(
        self,
        user_input: str,
        input_type: str,        # text | image | voice
        image_data: bytes = None,
        audio_data: bytes = None,
        theme: str = "",
        mode: str = "adult",    # adult | youth | senior
    ) -> EchoResult:
        # Step 1: 输入预处理 (图片/语音转文字)
        processed_input = await self._preprocess_input(
            input_type, user_input, image_data, audio_data
        )

        # Step 2: 内容安全过滤
        filtered = self.content_filter.check(processed_input)
        if filtered.blocked:
            raise ContentBlockedError(filtered.reason)

        # Step 3: 选择 Prompt 模板 (按模式)
        prompt = self.prompt_manager.get_prompt(mode, processed_input)

        # Step 4: LLM 叙事生成
        narrative = await self.llm_adapter.chat(prompt)

        # Step 5: 二次内容安全检查 (对生成内容)
        filtered_output = self.content_filter.check_output(narrative)
        if filtered_output.blocked:
            narrative = "今天你留下的痕迹，值得被温柔对待。"

        # Step 6: 持久化 (不等待 TTS)
        echo = await self.echo_repo.create(
            user_id=current_user.id,
            user_input=processed_input,
            narrative=narrative,
            theme=theme,
            input_type=input_type,
        )

        # Step 7: TTS 异步触发 (通过任务队列, 不阻塞响应)
        asyncio.create_task(
            self._generate_and_store_tts(echo.id, narrative, mode)
        )

        return EchoResult(
            echo_id=echo.id,
            narrative=narrative,
            audio_status="generating",  # 前端据此发起 WebSocket
        )

    async def _generate_and_store_tts(self, echo_id: str, text: str, mode: str):
        """后台 TTS 生成 + 存储"""
        voice_config = VOICE_MATRIX[mode]
        audio_key = f"tts:audio:{hashlib.md5(text.encode()).hexdigest()}"

        # 检查缓存
        cached = await redis.get(audio_key)
        if cached:
            await self.echo_repo.update_audio(echo_id, cached)
            return

        # 调用 TTS 引擎
        audio_bytes = await self.tts_router.synthesize(
            text=text, **voice_config
        )

        # 存入 OSS
        oss_key = f"audio/{echo_id}.mp3"
        await self.oss.upload(oss_key, audio_bytes)

        # 缓存到 Redis
        await redis.setex(audio_key, 86400, oss_key)

        # 更新数据库
        await self.echo_repo.update_audio(echo_id, f"/api/audio/{echo_id}.mp3")
```

### 5.3 Prompt 分层管理

```python
# app/core/prompt_manager.py

class PromptManager:
    """
    按用户模式调度不同叙事风格
    不改动底层 LLM 调用链路，仅切换 system prompt
    """

    PROMPTS = {
        "adult": {
            "system": "你是一位温暖、细腻的倾听者与陪伴者。生成100-150字冥想式叙事。语气温柔平静，像深夜电台独白。",
            "temperature": 0.85,
            "max_tokens": 300,
        },
        "youth": {
            "system": "你是一个元气满满的创意伙伴。生成80-120字活泼温暖的文字。语气轻快有活力，像朋友间的鼓励。",
            "temperature": 0.9,
            "max_tokens": 250,
        },
        "senior": {
            "system": "你是一位耐心、温和的老朋友。生成100-150字平缓舒缓的文字。语气朴实温暖，语速感慢，像午后闲谈。",
            "temperature": 0.7,
            "max_tokens": 300,
        },
    }

    def get_prompt(self, mode: str, user_input: str) -> list[dict]:
        config = self.PROMPTS.get(mode, self.PROMPTS["adult"])
        return [
            {"role": "system", "content": config["system"]},
            {"role": "user", "content": f"素材：{user_input}\n\n叙事文本："},
        ]
```

---

## 6. 前端架构设计

### 6.1 目录结构

```
frontend/
├── src/
│   ├── main.ts                 # Vue 入口
│   ├── App.vue
│   ├── router/                 # Vue Router
│   │   └── index.ts
│   ├── stores/                 # Pinia 状态管理
│   │   ├── echo.ts             # 回声状态
│   │   ├── diary.ts            # 日记状态
│   │   └── user.ts             # 用户状态
│   ├── views/                  # 页面组件
│   │   ├── HomeView.vue        # 首页
│   │   ├── WaitingView.vue     # 等待页
│   │   ├── EchoCardView.vue    # 回声卡片
│   │   └── DiaryView.vue       # 日记页
│   ├── components/             # 可复用组件
│   │   ├── ThemeCard.vue       # 今日主题
│   │   ├── InputArea.vue       # 输入区
│   │   ├── AudioPlayer.vue     # 音频播放器
│   │   ├── InkLoader.vue       # 水墨 loading
│   │   ├── DiaryCalendar.vue   # 日记日历
│   │   └── BottomNav.vue       # 底部导航
│   ├── composables/            # 组合式函数
│   │   ├── useTTSStream.ts     # TTS WebSocket 流式播放
│   │   ├── useVoiceRecorder.ts # 语音录制
│   │   └── useImageUpload.ts   # 图片上传
│   ├── api/                    # API 调用层
│   │   ├── client.ts           # axios 实例
│   │   ├── echo.ts
│   │   ├── diary.ts
│   │   └── tts.ts
│   ├── styles/                 # 样式
│   │   ├── variables.css       # CSS 变量 (复用当前色板)
│   │   ├── themes/             # 分层视觉主题
│   │   │   ├── adult.css
│   │   │   ├── youth.css
│   │   │   └── senior.css
│   │   └── base.css
│   └── utils/
│       └── format.ts
├── index.html
├── vite.config.ts
├── tsconfig.json
└── package.json
```

### 6.2 关键改进点（对比当前 Demo）

| 当前 Demo 问题 | 重构方案 |
|---------------|---------|
| 855 行单文件 HTML | Vue SFC 拆分，每个组件 < 200 行 |
| innerHTML XSS 风险 | Vue 模板自动转义，`v-text` 替代 innerHTML |
| 无路由管理 | Vue Router，支持浏览器前进/后退 |
| 无状态管理 | Pinia stores 管理回声/日记状态 |
| 无错误处理 | axios 拦截器 + 全局 Toast |
| 无加载骨架屏 | Skeleton 组件 |
| 日历仅当月 | DiaryCalendar 支持月份切换 |
| 固定单主题 | CSS 变量 + 主题切换 |

---

## 7. 数据模型与存储设计

### 7.1 PostgreSQL 表结构

```sql
-- 用户表
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username    VARCHAR(50) UNIQUE NOT NULL,
    email       VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    mode        VARCHAR(20) DEFAULT 'adult',  -- adult|youth|senior
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 回声表 (替代当前 diary.json)
CREATE TABLE echoes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    theme       VARCHAR(200),
    user_input  TEXT NOT NULL,
    input_type  VARCHAR(20) NOT NULL,          -- text|image|voice
    narrative   TEXT NOT NULL,
    audio_url   VARCHAR(500),                   -- OSS 路径
    audio_status VARCHAR(20) DEFAULT 'pending', -- pending|ready|failed
    oss_key     VARCHAR(500),                   -- OSS 对象 key
    tts_engine  VARCHAR(50),                    -- volcengine|edge_tts
    tts_voice   VARCHAR(100),                   -- 使用的音色
    created_at  TIMESTAMPTZ DEFAULT NOW(),

    INDEX idx_echoes_user_date (user_id, created_at DESC)
);

-- 每日主题表
CREATE TABLE daily_themes (
    id          SERIAL PRIMARY KEY,
    theme_type  VARCHAR(50) NOT NULL,
    theme_text  VARCHAR(500) NOT NULL,
    day_offset  INT NOT NULL,   -- 在年中的第几天
    UNIQUE(day_offset)
);

-- TTS 缓存索引 (Redis 辅助, PG 持久化元数据)
CREATE TABLE tts_cache (
    cache_key   VARCHAR(64) PRIMARY KEY,       -- md5(text+voice+params)
    text_hash   VARCHAR(64) NOT NULL,
    voice_type  VARCHAR(100) NOT NULL,
    oss_key     VARCHAR(500) NOT NULL,
    duration_ms INT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    hit_count   INT DEFAULT 0
);
```

### 7.2 Redis Key 设计

```
# TTS 音频缓存
tts:audio:{md5}          → oss_key (STRING, TTL 24h)

# 速率限制
ratelimit:{user_id}      → count (STRING, TTL 60s, 限制 10次/分钟)

# 会话
session:{token}          → user_id (STRING, TTL 7d)

# 每日主题缓存
theme:today              → JSON (STRING, TTL 到当日 23:59)
```

---

## 8. API 接口设计

### 8.1 REST API

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| POST | `/api/v1/auth/register` | 用户注册 | 否 |
| POST | `/api/v1/auth/login` | 用户登录 | 否 |
| GET | `/api/v1/theme/today` | 获取今日主题 | 是 |
| POST | `/api/v1/echo/generate` | 提交生成请求 | 是 |
| GET | `/api/v1/echo/{id}` | 获取单个回声 | 是 |
| GET | `/api/v1/diary` | 获取全部日记 | 是 |
| GET | `/api/v1/diary/{date}` | 获取某日日记 | 是 |
| GET | `/api/v1/audio/{echo_id}` | 获取音频文件 | 是 |
| PUT | `/api/v1/user/mode` | 切换用户模式 | 是 |

### 8.2 WebSocket API

```
GET /api/v1/tts/stream/{echo_id}

# 连接后服务端流程:
1. 根据 echo_id 查询 narrative 文本和音色配置
2. 检查 Redis 缓存
3. 缓存命中 → 推送完整音频分片 → 关闭
4. 缓存未命中 → 调用豆包 V3 流式 TTS → 逐帧推送 → 存 OSS → 关闭

# 消息格式:
- 二进制帧: 音频 MP3 分片 (前端 MediaSource 播放)
- JSON 帧: { "type": "status", "status": "ready"|"error", "message": "..." }
```

### 8.3 关键接口示例

```python
# app/api/v1/echo.py

@router.post("/echo/generate", response_model=EchoResponse)
async def generate_echo(
    request: EchoRequest,
    current_user: User = Depends(get_current_user),
    pipeline: EchoPipeline = Depends(get_pipeline),
):
    """
    生成回声 - 叙事与 TTS 解耦
    返回叙事文本，TTS 通过 WebSocket 异步推送
    """
    result = await pipeline.generate(
        user_input=request.content,
        input_type=request.type,
        image_data=request.image_base64,
        theme=request.theme,
        mode=current_user.mode,
    )
    return EchoResponse(
        echo_id=result.echo_id,
        narrative=result.narrative,
        audio_status=result.audio_status,  # "generating"
    )
```

---

## 9. 安全与合规设计

### 9.1 认证与授权

```
认证流程:
用户登录 → JWT Token (access 30min + refresh 7d)
    ↓
请求 Header: Authorization: Bearer {access_token}
    ↓
FastAPI 依赖注入: get_current_user() 解析 JWT
```

### 9.2 内容安全

```python
# app/core/content_filter.py

class ContentFilter:
    """
    双向内容过滤: 输入侧 + 输出侧
    """

    # 输入侧: 敏感词黑名单 (基础过滤)
    INPUT_BLOCKLIST = [
        # 自伤、暴力、违法等关键词
    ]

    # 输出侧: LLM 生成内容二次审核
    async def check_output(self, text: str) -> bool:
        """
        对 LLM 生成内容做安全审核
        方案1: 关键词过滤 (快速、基础)
        方案2: 调用内容安全 API (准确、成本)
        """
        # 基础: 关键词过滤
        for word in self.INPUT_BLOCKLIST:
            if word in text:
                return False
        # 进阶: 可接入百度云/阿里云内容安全 API
        return True
```

### 9.3 安全清单

| 项目 | 当前 Demo | 目标架构 |
|------|----------|---------|
| debug 模式 | `debug=True` (严重) | 生产关闭，仅开发环境开启 |
| CORS | `CORS(app)` 全开 | 白名单域名，仅允许前端域名 |
| 密码存储 | 无用户系统 | bcrypt 哈希 |
| API 认证 | 无 | JWT Bearer Token |
| 速率限制 | 无 | Redis 计数，10次/分钟/用户 |
| 输入校验 | 无 | Pydantic schema 自动校验 |
| SQL 注入 | N/A (JSON) | SQLAlchemy ORM 参数化查询 |
| XSS | innerHTML 拼接 | Vue 模板自动转义 |
| HTTPS | 无 | Nginx TLS (Let's Encrypt) |
| 环境变量 | 硬编码默认值 | .env 文件 + Pydantic Settings |

---

## 10. 部署架构设计

### 10.1 Docker Compose 部署方案

```yaml
# docker-compose.yml
version: '3.8'

services:
  # Nginx 反向代理
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
      - frontend_dist:/usr/share/nginx/html  # Vue 构建产物
    depends_on:
      - backend

  # FastAPI 后端
  backend:
    build: ./backend
    environment:
      - DATABASE_URL=postgresql://echoetch:password@db:5432/echoetch
      - REDIS_URL=redis://redis:6379/0
      - VOLCENGINE_TTS_APPID=${VOLCENGINE_TTS_APPID}
      - VOLCENGINE_TTS_TOKEN=${VOLCENGINE_TTS_TOKEN}
      - LLM_API_KEY=${LLM_API_KEY}
      - LLM_BASE_URL=${LLM_BASE_URL}
    depends_on:
      - db
      - redis
    restart: unless-stopped

  # PostgreSQL
  db:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=echoetch
      - POSTGRES_USER=echoetch
      - POSTGRES_PASSWORD=password
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  # Redis
  redis:
    image: redis:7-alpine
    volumes:
      - redisdata:/data
    restart: unless-stopped

volumes:
  frontend_dist:
  pgdata:
  redisdata:
```

### 10.2 Nginx 配置要点

```nginx
server {
    listen 443 ssl;
    server_name echoetch.example.com;

    # 前端静态资源
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    # API 反向代理
    location /api/ {
        proxy_pass http://backend:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket 代理 (TTS 流式)
    location /api/v1/tts/stream/ {
        proxy_pass http://backend:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;  # TTS 可能需要较长时间
    }

    # 音频文件代理 (带缓存)
    location /api/audio/ {
        proxy_pass http://backend:8000;
        proxy_cache_valid 200 24h;
        expires 24h;
    }
}
```

### 10.3 服务器硬件建议

| 阶段 | 配置 | 适用场景 | 月成本估算 |
|------|------|---------|-----------|
| Phase 1 | 2C4G 云主机 | 低并发开发测试 | ¥60-100 |
| Phase 2 | 4C8G + Redis + PG | 小规模用户 (100-500) | ¥200-400 |
| Phase 3 | 8C16G + 负载均衡 | 正式运营 (1k+) | ¥500-1000 |

> TTS 和 LLM 均为云端 API 调用，不需要本地 GPU

---

## 11. 性能优化策略

### 11.1 端到端延迟优化

```
当前 Demo (文字模式):
  用户提交 → LLM (3-5s) → TTS 整段生成 (2-5s) → 前端展示
  总延迟: 5-10s

目标架构 (文字模式):
  用户提交 → LLM (2-3s) → 返回叙事文本 → 前端立即展示文字
                    ↓ (并行)
              TTS WebSocket 流式推送 (首包 300ms)
              前端边收边播
  体感延迟: 2-3s 看到文字, +0.3s 听到声音
```

### 11.2 优化措施清单

| 优化项 | 方法 | 预期效果 |
|--------|------|---------|
| TTS 流式 | 豆包 V3 WebSocket + 前端 MediaSource | 首音 < 500ms |
| TTS 缓存 | Redis 缓存 + 豆包服务端缓存 | 重复内容 < 100ms |
| LLM 流式 | SSE 流式返回叙事文本 | 首字 < 500ms |
| 叙事/TTS 解耦 | 叙事返回后异步 TTS | 文字先出，不等待音频 |
| 音频 CDN | Nginx 缓存 + OSS | 回放 < 100ms |
| 图片压缩 | 前端压缩后上传 | 上传时间减半 |
| DB 索引 | user_id + created_at 复合索引 | 日记查询 < 50ms |
| 连接池 | SQLAlchemy async pool | 并发不阻塞 |

### 11.3 TTS 成本控制

| 策略 | 说明 |
|------|------|
| Redis 缓存 | 相同文本+音色 24h 内不重复调用 |
| 豆包服务端缓存 | 短时间相同文本秒级返回 |
| 限速 | 每用户 10 次/分钟，防止滥用 |
| 文本长度限制 | 叙事限制 200 字内，控制单次成本 |
| 降级策略 | 非高峰时段可降级到 edge-tts |

> 豆包 TTS 定价约 ¥0.2/万字，按 200 字/次、日均 1000 次计算，日成本约 ¥4，月成本约 ¥120

---

## 12. 开发路线图与里程碑

### Phase 0: 基础修复（1 周）

> 目标：修复 Demo 安全和结构问题，不改技术栈

- [ ] 关闭 debug=True，用 waitress 部署
- [ ] CORS 收紧为白名单
- [ ] requirements.txt 补全 Pillow
- [ ] 前端修复 XSS (innerHTML → textContent)
- [ ] 添加基础错误处理和 Toast
- [ ] JSON 存储加文件锁

### Phase 1: 架构重构 + TTS 升级（3 周）

> 目标：FastAPI + Vue 3 + 豆包 TTS，核心体验质变

**Week 1: 后端重构**
- [ ] FastAPI 项目搭建 + 配置管理
- [ ] PostgreSQL + SQLAlchemy 模型
- [ ] Redis 集成 + 速率限制
- [ ] LLM 适配器 (OpenAI 兼容接口)
- [ ] 用户认证 (JWT)

**Week 2: TTS 子系统**
- [ ] 豆包 V3 WebSocket 适配器
- [ ] TTS 引擎路由器 + 降级策略
- [ ] TTS 三层缓存实现
- [ ] TTS WebSocket API (前端流式推送)
- [ ] 音色配置矩阵

**Week 3: 前端重构**
- [ ] Vue 3 + Vite 项目搭建
- [ ] 页面组件拆分
- [ ] TTS 流式播放 (MediaSource API)
- [ ] Pinia 状态管理
- [ ] 视觉迁移 + 暗色模式

### Phase 2: 体验深化（2 周）

> 目标：核心用户（成人）体验打磨

- [ ] LLM 流式 SSE (叙事文本逐字返回)
- [ ] 多音色选择
- [ ] 日记月份切换 + 搜索
- [ ] 分享卡片生成
- [ ] 加载骨架屏 + 错误重试
- [ ] 移动端 PWA 适配

### Phase 3: 分层适配（2 周）

> 目标：青少年模式 + 老年简化模式

- [ ] 模式切换 + CSS 主题
- [ ] Prompt 分层调度
- [ ] 老年大字体 + 极简交互
- [ ] 内容安全过滤管线
- [ ] 基础无障碍 (ARIA)

---

## 附录 A: 环境变量清单

```env
# .env.example

# Database
DATABASE_URL=postgresql://echoetch:password@localhost:5432/echoetch

# Redis
REDIS_URL=redis://localhost:6379/0

# JWT
JWT_SECRET=your-secret-key-here
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# LLM (OpenAI 兼容)
LLM_API_KEY=sk-xxx
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_MODEL=deepseek-chat
LLM_VISION_MODEL=qwen-vl-plus

# ASR (Whisper)
WHISPER_API_KEY=sk-xxx
WHISPER_URL=https://api.siliconflow.cn/v1

# TTS - 火山引擎豆包
VOLCENGINE_TTS_APPID=xxx
VOLCENGINE_TTS_TOKEN=xxx
VOLCENGINE_TTS_CLUSTER=volcano_tts

# OSS / MinIO
OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
OSS_ACCESS_KEY=xxx
OSS_SECRET_KEY=xxx
OSS_BUCKET=echoetch-audio

# CORS
CORS_ORIGINS=https://echoetch.example.com

# TTS Engine Selection
TTS_PRIMARY_ENGINE=volcengine
TTS_FALLBACK_ENGINE=edge_tts
```

## 附录 B: 依赖清单

### 后端 (requirements.txt)

```
fastapi>=0.110.0
uvicorn[standard]>=0.27.0
sqlalchemy[asyncio]>=2.0.0
asyncpg>=0.29.0
alembic>=1.13.0
redis[hiredis]>=5.0.0
pydantic-settings>=2.1.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
python-multipart>=0.0.6
websockets>=12.0
httpx>=0.27.0
edge-tts>=6.1.0
Pillow>=10.0.0
oss2>=2.18.0
```

### 前端 (package.json)

```json
{
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.3.0",
    "pinia": "^2.1.0",
    "axios": "^1.7.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "vite": "^5.2.0",
    "typescript": "^5.4.0",
    "unocss": "^0.59.0"
  }
}
```

---

> 文档版本: v1.0 | 更新日期: 2026-08-01
> 适用项目: 《聲畫合鳴》EchoEtch
> 仓库: https://github.com/rfdiosuao/EchoEtch
