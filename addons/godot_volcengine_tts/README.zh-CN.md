# Godot Volcengine TTS

第三方非官方 Godot 4 火山引擎豆包 TTS 调用库。它最初来自一个战棋游戏项目，
用于角色对白、低延迟流式语音和固定台词预生成。

> 合规、服务条款和免责声明见仓库根目录 README。

English documentation: [README.md](README.md)

## 支持端点

| 端点 | 插件类 | 用途 | SSML | 输出 |
|---|---|---|---|---|
| `wss://openspeech.bytedance.com/api/v3/tts/bidirection` | `VolcengineTTSBidirectionalClient` | LLM token streaming 和高层播放 | 否 | PCM 流 |
| `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream` | `VolcengineTTSUnidirectionalClient` | 一次提交整段文本，流式返回音频块 | 是 | PCM/MP3/WAV/Opus 分块 |
| `https://openspeech.bytedance.com/api/v3/tts/unidirectional` | `VolcengineTTSHttpClient` | 预生成、缓存、短提示音 | 是 | 完整音频字节 |

`VolcengineStreamingVoicePlayer` 持有这三个 client，并在它们之上补了一层
Godot 播放能力。

一个维护时最容易误解的点：本文档里的“单句流式播放”指高层 `speak()` 帮助方法。
它当前走的是官方双向 WebSocket 端点，而不是 `/tts/unidirectional/stream`。实现方式是：
启动一个双向 session，一次性喂入全文，发送 `FinishSession`，然后把服务端返回的
PCM 字节流送入 `AudioStreamGenerator` 播放。真正的官方单向流式端点也已实现，
但作为低层 API 暴露：`voice.uni_client.synthesize_streaming(...)`。

这是一个有意选择的维护取舍。`speak()` 和真正的 LLM token streaming 可以共享同一套
双向 session 生命周期、session_id 过滤、陈旧信号保护、取消语义、PCM 队列和背压播放路径。
高层只保留一套播放管线，可以降低“单句播放”和“分段流式”在 stop、重入和播放收尾行为上
出现分叉的概率。单向流式 client 仍作为低层 API 保留，用于 SSML 流式返回和自定义 chunk
处理。

音色列表以火山引擎官方文档为准：

https://www.volcengine.com/docs/6561/1257544

## 安装

复制本目录到项目：

```text
addons/godot_volcengine_tts/
```

然后在 **项目设置 > 插件** 启用 **Godot Volcengine TTS**。`plugin.gd`
只是为了满足 Godot 插件格式要求，运行时业务代码直接使用带 `class_name` 的脚本类。

## 快速开始

```gdscript
extends Node

func _ready() -> void:
	var voice := VolcengineStreamingVoicePlayer.new()
	voice.audio_bus = &"Master"
	add_child(voice)

	for client in [voice.bidi_client, voice.uni_client, voice.http_client]:
		client.api_key = "your-volcengine-api-key"
		client.resource_id = "seed-tts-2.0"
		client.default_model = "seed-tts-2.0-expressive"

	await voice.speak("你好，世界。", "zh_male_dayi_uranus_bigtts")
```

## 配置

大多数项目只需要给实际使用的 client 设置 `api_key`、`resource_id`，以及可选的
`default_model`：

```gdscript
for client in [voice.bidi_client, voice.uni_client, voice.http_client]:
	client.api_key = "your-volcengine-api-key"
	client.resource_id = "seed-tts-2.0"
	client.user_uid = "player-or-device-id"
	client.default_model = "seed-tts-2.0-expressive"
```

也可以自行覆盖 host 或 API path。这个能力适合私有网关、反向代理、兼容端点，或火山后续
调整路径时使用：

```gdscript
voice.bidi_client.base_url = "openspeech.bytedance.com"
voice.bidi_client.path = "/api/v3/tts/bidirection"

voice.uni_client.base_url = "your-gateway.example.com"
voice.uni_client.path = "/api/v3/tts/unidirectional/stream"

voice.http_client.base_url = "your-gateway.example.com"
voice.http_client.path = "/api/v3/tts/unidirectional"
```

`base_url` 只填 host，不要带 `https://`、`wss://`，也不要带路径。各 client 会自己补协议：
WebSocket client 使用 `wss://`，HTTP client 使用 443 端口 TLS 连接。

其他常用运行时配置：

| 属性 | 所属对象 | 默认值 | 说明 |
|---|---|---|---|
| `audio_bus` | `VolcengineStreamingVoicePlayer` | `&"Master"` | 高层播放使用的 Godot 音频总线 |
| `sample_rate` | `VolcengineStreamingVoicePlayer` | `24000` | `speak()` / `start_streaming()` 默认 PCM 播放采样率 |
| `buffer_length` | `VolcengineStreamingVoicePlayer` | `0.5` | `AudioStreamGenerator` 缓冲长度 |
| `auto_context_chain` | `VolcengineStreamingVoicePlayer` | `false` | 自动把上一段 session id 作为下一段 `section_id` |
| `connect_timeout_msec` | 所有 client | `8000` | WebSocket/HTTP 连接超时 |
| `session_timeout_msec` | WS client | `20000` | 等待 WS 包的无活动超时 |
| `read_timeout_msec` | HTTP client | `30000` | 读取 HTTP chunk 的无活动超时 |

## API 速查

| API | 端点 | 结果 |
|---|---|---|
| `voice.speak(text, voice_id, opts)` | 双向 WS | 流式播放 PCM；自然完成时返回 `true` |
| `voice.start_streaming(voice_id, opts)` / `feed_text(chunk)` / `finish_streaming()` | 双向 WS | 播放增量文本生成的 PCM 流 |
| `voice.fetch_audio(text, voice_id, opts)` | HTTP Chunked | 返回完整音频字节 |
| `voice.uni_client.synthesize_streaming(text, voice_id, on_chunk, opts, out_session)` | 单向 WS | 每收到一个音频块就调用 `on_chunk` |
| `voice.stop()` | 当前高层播放任务 | 中断播放，并让等待中的 `speak()` 返回 `false` |
| `voice.current_session_id()` | 高层播放器 | 返回上一段自然完成的双向 session id |

信号：

- `voice.speak_finished`：高层播放自然结束、失败或被停止时都会发出。
- `voice.bidi_client.audio_chunk_received(session_id, chunk)`：低层双向音频块事件。
- `voice.bidi_client.session_finished(session_id)` 和
  `voice.bidi_client.session_failed(session_id, reason)`：低层双向完成/失败事件。

## 用法 A：单句流式播放

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
add_child(voice)

voice.bidi_client.api_key = "..."
voice.bidi_client.resource_id = "seed-tts-2.0"

var ok := await voice.speak("依老朽看，这桥要成。", "zh_male_dayi_uranus_bigtts", {
	"emotion": "happy",
	"emotion_scale": 4,
	"speech_rate": 10,
})
```

`speak()` 返回 `true` 表示自然播完，返回 `false` 表示失败，或者被 `stop()` /
后一次请求中断。

实现细节：

- 使用 `VolcengineTTSBidirectionalClient`。
- 强制 `format = "pcm"`，因为 `AudioStreamGenerator` 消费的是 PCM frame。
- 未传 `sample_rate` 时使用 `voice.sample_rate`。
- 执行顺序是 `start_session(voice, opts)`、`feed_text(text)`、`finish_session()`。
- 收到的 PCM chunk 会先进 FIFO 队列，再带背压写入 `AudioStreamGeneratorPlayback`。

这条路径不支持 SSML，因为它底层使用的是双向流式协议。

## 用法 B：真双向流式

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

for chunk in ["依老朽看，", "这桥要成。", "须得脚下踩稳。"]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.3).timeout

voice.finish_streaming()
await voice.speak_finished
```

这适合 LLM 或其他生成器逐段吐文本的场景。所有 chunk 共享同一个服务端 session，
语调延续通常会比分多次请求更自然。

## 用法 C：官方单向流式

```gdscript
var rate := 24000
var generator := AudioStreamGenerator.new()
generator.mix_rate = float(rate)
generator.buffer_length = 0.5

var player := AudioStreamPlayer.new()
add_child(player)
player.stream = generator
player.play()
var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback

var out_session := {}
var ok := await voice.uni_client.synthesize_streaming(
	"这是官方单向流式端点。",
	"zh_male_dayi_uranus_bigtts",
	func(chunk: PackedByteArray) -> void:
		# 这里把 signed 16-bit little-endian PCM 转成 Vector2 frame 再写入 playback。
		pass,
	{"format": "pcm", "sample_rate": rate},
	out_session,
)
```

这是官方 `/api/v3/tts/unidirectional/stream` 路径。它发送一个包含完整请求 JSON 的
`SendText` 包，然后接收 `TTSResponse` 音频帧，直到 `SessionFinished`。

如果需要“SSML + 流式返回音频”，或者你想自己管理播放、缓冲和原始字节处理，
就直接调用这条低层 API。

## 用法 D：拿完整音频字节

```gdscript
var mp3 := await voice.fetch_audio("欢迎光临", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

`fetch_audio()` 调用 HTTP Chunked 端点，返回一个完整的 `PackedByteArray`。适合预合成
固定台词、持久化缓存、cutscene 和 UI 提示音。

## 上下文支持

```gdscript
voice.auto_context_chain = true
await voice.speak("第一句", voice_id)
await voice.speak("第二句", voice_id)
voice.reset_context_chain()
```

开启 `auto_context_chain` 后，连续 `speak()` 或 `finish_streaming()` 完成时会保存返回的
双向 `session_id`。下一次请求如果没有显式传 `section_id`，插件会自动把上一段
`session_id` 作为 `section_id` 传入。这个能力主要用于 TTS 2.0 的上下文延续。
换角色、换场景或需要断开语境时调用 `reset_context_chain()`。

也可以手动传上下文：

```gdscript
await voice.speak("第二句", voice_id, {
	"context_texts": ["用骄傲但克制的语气说话。"],
	"section_id": previous_session_id,
})
```

## opts 参数

`opts` 是一层扁平 `Dictionary`。`TtsOptions.build_req_params()` 会把各字段归位到火山协议
需要的 `req_params` 结构。

| 键 | 类型 | 说明 |
|---|---|---|
| `format` | String | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"` |
| `sample_rate` | int | 常用 16000、24000、44100、48000 |
| `bit_rate` | int | 仅 MP3 生效 |
| `emotion` | String | 多情感音色的情绪 |
| `emotion_scale` | int | 常用 1-5 |
| `speech_rate` | int | 常用 -50 到 100 |
| `loudness_rate` | int | 常用 -50 到 100 |
| `model` | String | 例如 `"seed-tts-2.0-expressive"` |
| `ssml` | String | 完整 `<speak>...</speak>`，仅单向/HTTP |
| `context_texts` | Array[String] | TTS 2.0 上下文提示 |
| `section_id` | String | 上一段 session id |
| `silence_duration` | int | 句尾静音，单位毫秒 |
| `disable_markdown_filter` | bool | 透传到火山 `additions` |
| `explicit_language` | String | 例如 `"zh-cn"` / `"en"` / `"ja"` |
| `enable_subtitle` | bool | 服务端可能返回字幕/时间戳帧，但当前插件还没有暴露回调 |

逃生口：

```gdscript
await voice.speak("台词。", voice_id, {
	"audio_params_extra": {"future_audio_field": "value"},
	"additions_extra": {"with_frontend_text": true},
	"raw_req_params": {
		"speaker": voice_id,
		"audio_params": {"format": "pcm", "sample_rate": 24000},
	},
})
```

`raw_req_params` 会绕过所有合并逻辑。只有在火山新增字段、插件还没有命名支持时才建议使用。
对双向 `speak()` 来说，文本仍然会在后续通过 `feed_text()` 发送，所以 start-session 的
`raw_req_params` 通常不应该包含 `text`。

## 协议细节

通用请求头：

- `X-Api-Key: <api_key>`
- `X-Api-Resource-Id: <resource_id>`
- `X-Api-Connect-Id: <uuid>`，WebSocket 使用
- `X-Api-Request-Id: <uuid>`，HTTP 使用
- `X-Control-Require-Usage-Tokens-Return: *`

双向 WebSocket 流程：

1. 连接 `wss://<base_url>/api/v3/tts/bidirection`。
2. 发送 `StartConnection` 事件 `1`，等待 `ConnectionStarted` 事件 `50`。
3. 发送 `StartSession` 事件 `100`，payload 包含 `namespace = "BidirectionalTTS"` 和
   `req_params`。
4. 发送一个或多个 `TaskRequest` 事件 `200` 文本包。
5. 发送 `FinishSession` 事件 `102`。
6. 接收音频帧，直到 `SessionFinished` 事件 `152`；失败时可能收到
   `SessionFailed` 事件 `153`。
7. 尽力发送 `FinishConnection` 事件 `2` 并关闭连接。

双向 client 包使用二进制帧头 `[0x11, 0x14, 0x10, 0x00]`，后面依次是事件号、
可选 session id 和 JSON payload。

单向 WebSocket 流程：

1. 连接 `wss://<base_url>/api/v3/tts/unidirectional/stream`。
2. 发送一个 `SendText` 包，帧头 `[0x11, 0x10, 0x10, 0x00]`。这个包没有事件号，
   payload 是完整请求 JSON。
3. 接收句首 `350`、音频响应 `352`、句尾 `351`、session 结束 `152` 等事件。
4. 发送 `FinishConnection` 事件 `2`，帧头 `[0x11, 0x14, 0x10, 0x00]`，然后关闭。

HTTP 流程：

1. POST JSON 到 `https://<base_url>/api/v3/tts/unidirectional`。
2. 读取 HTTP Chunked 响应；响应体每行是一个 JSON。
3. 对 `code == 0` 且 `data` 为字符串的行做 base64 解码并 append。
4. 遇到 `code == 20000000` 视为正常结束。

## 中断与并发

`VolcengineStreamingVoicePlayer` 同一时间只跑一个播放任务。新的 `speak()` 或
`start_streaming()` 会先中断旧任务，再启动新任务。

```gdscript
voice.speak("第一句", voice_id)   # 不 await
voice.speak("第二句", voice_id)   # 会中断第一句
```

被中断的 `await voice.speak(...)` 会醒来并返回 `false`。

主动停止：

```gdscript
voice.stop()
```

`stop()` 会关闭活跃 WebSocket、清空待播放 PCM 队列、停止 `AudioStreamPlayer`，
如果当时确实在播放则 emit `speak_finished`，并让等待中的 `speak()` 返回 `false`。
空闲时调用 `stop()` 是安全的。

`speak_finished` 的语义是“不会再继续出声”，包括成功、失败和中断。要区分自然完成与失败/
中断，请看 `speak()` 的返回值。

## 踩坑笔记

- Godot 实时播放优先用 PCM。流式 MP3 分块不能直接写入 `AudioStreamGenerator`。
- `speak()` 即使传入 `"format": "mp3"` 也会强制改成 PCM。需要 MP3 字节请用
  `fetch_audio()`。
- 双向流式不支持 SSML。需要 SSML 请走 `uni_client` 或 `fetch_audio()`。
- 部分 `saturn_` 和 `_saturn_bigtts` 音色不支持 SSML；插件只警告，最终由服务端决定。
- `default_model` 目前只会自动注入到 `saturn_` 音色。给不兼容音色乱传 model，
  在较严格端点上可能触发 resource/speaker mismatch。
- 超时是“无活动”超时：每收到一个包都会刷新 deadline。
- HTTP 返回的 chunk 不一定按 JSON 行对齐；HTTP client 会先缓存文本，遇到换行再解析。
- 服务端可能返回字幕/时间戳帧，但当前插件会忽略，尚未提供 `subtitle_received` 回调。

## 限制

- 暂不支持 SSE 端点。
- 暂不提供字幕/时间戳回调。
- 不内置音色清单，`voice` 是由调用方维护的 `voice_type` 字符串。
- 不内置系统 TTS 兜底，失败处理由调用方决定。

## 许可证

MIT。详见 `LICENSE`。
