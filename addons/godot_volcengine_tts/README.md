# Godot Volcengine TTS

第三方非官方 Godot 4 火山引擎豆包 TTS 调用库。它最初来自一个战棋游戏项目，用于角色对白、低延迟流式语音和固定台词预生成。

> 合规、服务条款和免责声明见仓库根目录 README。

English documentation: [README.en.md](README.en.md)

音色列表以火山引擎官方文档为准：

https://www.volcengine.com/docs/6561/1257544

## 什么时候用哪个 API

大多数项目应该优先使用 `VolcengineStreamingVoicePlayer`。它统一管理配置、播放状态和三个底层 client。

| 需求 | 推荐 API | 端点 | 说明 |
|---|---|---|---|
| 已有完整文本，直接实时播放 | `voice.speak(text, voice_id, opts)` | 单向 WS | 最常用路径；返回 PCM 并通过 Godot 播放 |
| 已有完整 SSML，直接实时播放 | `voice.speak_ssml(ssml, voice_id, opts)` | 单向 WS | 高层 SSML 播放；不需要把内容塞进 `opts["ssml"]` |
| LLM 或生成器逐段吐文本 | `start_streaming()` / `feed_text()` / `finish_streaming()` | 双向 WS | 多个文本 chunk 共享同一个 session |
| 预生成、缓存或保存音频文件 | `voice.fetch_audio(text, voice_id, opts)` | HTTP Chunked | 返回完整 `PackedByteArray` |
| 自己处理音频 chunk、缓冲或协议 | 底层 client | 单向 WS / 双向 WS / HTTP | 高级用法；普通业务不建议优先使用 |

端点和 client 对应关系：

| 端点 | 插件类 | SSML | 输出 |
|---|---|---|---|
| `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream` | `VolcengineTTSUnidirectionalClient` | 是 | PCM/MP3/WAV/Opus 分块 |
| `wss://openspeech.bytedance.com/api/v3/tts/bidirection` | `VolcengineTTSBidirectionalClient` | 否 | 高层播放管线仅支持 PCM；底层 client 可请求 `opts["format"]` 指定的格式 |
| `https://openspeech.bytedance.com/api/v3/tts/unidirectional` | `VolcengineTTSHttpClient` | 是 | 完整音频字节 |

## 安装

复制本目录到项目：

```text
addons/godot_volcengine_tts/
```

然后在 **项目设置 > 插件** 启用 **Godot Volcengine TTS**。`plugin.gd` 只是为了满足 Godot 插件格式要求，运行时业务代码直接使用带 `class_name` 的脚本类。

## 快速开始

下面是最小可运行示例。`api_key` 是必填配置，其它字段都有默认值或只在特定场景需要设置。

```gdscript
extends Node

func _ready() -> void:
	var voice := VolcengineStreamingVoicePlayer.new()
	voice.api_key = "your-volcengine-api-key"
	add_child(voice)

	var ok := await voice.speak("你好，世界。", "zh_male_dayi_uranus_bigtts")
	if not ok:
		push_warning("TTS 播放失败或被中断")
```

`speak()` 的两个必填参数分别是文本内容和火山引擎音色字符串。

## 配置

推荐在高层 `voice` 节点上配置鉴权和模型参数。`voice` 会把这些值同步到双向、单向和 HTTP 三个底层 client。

```gdscript
voice.api_key = "your-volcengine-api-key"
voice.resource_id = "seed-tts-2.0"
voice.user_uid = "player-or-device-id"
voice.default_model = "seed-tts-2.0-expressive"
```

常用运行时属性：

| 属性 | 所属对象 | 默认值 | 说明 |
|---|---|---|---|
| `api_key` | `voice` 和所有底层 client | `""` | 火山 API key；未配置时请求会失败 |
| `resource_id` | `voice` 和所有底层 client | `"seed-tts-2.0"` | 火山 resource id |
| `user_uid` | `voice` 和所有底层 client | `"default"` | 请求中的用户/设备 id |
| `default_model` | `voice` 和所有底层 client | `""` | 支持的 `saturn_` 音色会自动注入的默认 model |
| `audio_bus` | `voice` | `&"Master"` | 高层播放使用的 Godot 音频总线 |
| `sample_rate` | `voice` | `24000` | `speak()` / `start_streaming()` 默认 PCM 播放采样率 |
| `buffer_length` | `voice` | `0.5` | `AudioStreamGenerator` 缓冲长度 |
| `auto_context_chain` | `voice` | `false` | 自动把上一段 session id 作为下一段 `section_id` |
| `connect_timeout_msec` | 所有底层 client | `8000` | WebSocket/HTTP 连接超时 |
| `session_timeout_msec` | WebSocket client | `20000` | WebSocket 等待包的无活动超时 |
| `read_timeout_msec` | HTTP client | `30000` | HTTP 读取 chunk 的无活动超时 |

可以直接配置底层 client，但只会影响对应 client。之后如果再次设置 `voice.api_key`、`voice.resource_id`、`voice.user_uid` 或 `voice.default_model`，会覆盖三个 client 上的对应值。

```gdscript
voice.bidi_client.api_key = "your-volcengine-api-key"
voice.bidi_client.resource_id = "seed-tts-2.0"
voice.bidi_client.user_uid = "player-or-device-id"
voice.bidi_client.default_model = "seed-tts-2.0-expressive"
```

如果在使用私有网关、反向代理或兼容端点时，可以覆盖底层 client 的 host、API path 和 timeout：

```gdscript
voice.uni_client.base_url = "your-gateway.example.com"
voice.uni_client.path = "/api/v3/tts/unidirectional/stream"
voice.http_client.base_url = "your-gateway.example.com"
voice.http_client.path = "/api/v3/tts/unidirectional"
```

`base_url` 只填 host，不要带 `https://`、`wss://` 或路径。WebSocket client 会使用 `wss://`，HTTP client 会使用 443 端口 TLS 连接。

## 高层 API

`VolcengineStreamingVoicePlayer` 是推荐入口。它负责同步配置到底层 client，并把 WebSocket 返回的 PCM 数据接入 Godot 的 `AudioStreamGenerator`。

信号：

- `voice.speak_finished`：高层播放自然结束、失败或被停止时都会发出。

下面示例默认已经完成初始化：

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
voice.api_key = "your-volcengine-api-key"
add_child(voice)
```

### `单向流式播放speak(text, voice_id, opts := {})`

用途：单次提交完整普通文本，并实时播放返回的 PCM。这是一种单向流式的做法。

| 项 | 说明 |
|---|---|
| 必填参数 | `text`、`voice_id` |
| 可选参数 | `opts`，见 `opts 参数参考` |
| 返回值 | `bool`；自然播完为 `true`，失败或被中断为 `false` |
| 使用端点 | 单向 WebSocket |
| 默认行为 | 未传 `format` 时使用 `pcm`；未传 `sample_rate` 时使用 `voice.sample_rate` |

```gdscript
var ok := await voice.speak("依老朽看，这桥要成。", "zh_male_dayi_uranus_bigtts", {
	"emotion": "happy",
	"emotion_scale": 4,
	"speech_rate": 10,
})
```

`speak()` 会强制使用 PCM，因为 Godot 实时播放依赖 `AudioStreamGenerator` 消费 PCM frame。即使传入 `"format": "mp3"`，也会被改为 `"pcm"`；需要 MP3 字节时请使用 `fetch_audio()`。

如果上一个 `speak()` 或 `start_streaming()` 还在运行，新调用会先中断旧任务。旧的 `await voice.speak(...)` 会返回 `false`。

### `SSML单向流式播放speak_ssml(ssml, voice_id, opts := {})`

用途：单次提交完整 SSML，并实时播放返回的 PCM。这是一种单向流式的做法。

| 项 | 说明 |
|---|---|
| 必填参数 | `ssml`、`voice_id` |
| 可选参数 | `opts`，见 `opts 参数参考` |
| 返回值 | `bool`；自然播完为 `true`，失败或被中断为 `false` |
| 使用端点 | 单向 WebSocket |
| 默认行为 | 复用 `speak()` 播放流程，强制使用 PCM |

```gdscript
var ok := await voice.speak_ssml(
	"<speak>依老朽看，<break time=\"300ms\"/>这桥要成。</speak>",
	"zh_male_dayi_uranus_bigtts"
)
```

仍然可以使用`speak()`，将`text`留空，并在`opts["ssml"]`传入SSML文本，来实现SSML的单向流式播放。

但是在使用SSML时，更推荐使用 `speak_ssml()`。

### `双向流式播放start_streaming(voice_id, opts := {})` / `feed_text(chunk)` / `finish_streaming()`

用途：开启一个双向流式 session，适合 LLM 或其它生成器逐段产生文本的场景。多个文本 chunk 共享同一个服务端 session，语调延续通常会比分多次请求更自然；在服务端提前返回音频 chunk 时，也通常有机会更早开始播放。

| API | 必填参数 | 可选参数 | 返回值 |
|---|---|---|---|
| `start_streaming(voice_id, opts := {})` | `voice_id` | `opts` | `bool`；session 启动成功为 `true` |
| `feed_text(chunk)` | `chunk` | 无 | `bool`；文本包发送成功为 `true` |
| `finish_streaming()` | 无 | 无 | 无返回值 |

```gdscript
var ok := await voice.start_streaming("zh_male_dayi_uranus_bigtts")
if not ok:
	return

voice.feed_text("依老朽看，")
voice.feed_text("这桥要成。")
voice.feed_text("须得脚下踩稳。")

voice.finish_streaming()
await voice.speak_finished
```

双向播放不是从 `finish_streaming()` 开始。`start_streaming()` 会先准备播放器，随后每次 `feed_text()` 都会把文本发给服务端；只要服务端返回第一个音频 chunk，插件就会立即写入 Godot 播放缓冲并开始出声。`finish_streaming()` 只表示“不会再继续喂文本”。

双向流式不支持 SSML。如果你已经有完整文本，优先使用 `speak()`。

### `一次获取完整音频fetch_audio(text, voice_id, opts := {})`

用途：通过 HTTP Chunked 端点获取完整音频字节，适合预合成固定台词、持久化缓存、cutscene 和 UI 提示音。

| 项 | 说明 |
|---|---|
| 必填参数 | `text`、`voice_id` |
| 可选参数 | `opts`，通常显式传入 `"format"` |
| 返回值 | `PackedByteArray`；失败时返回空字节数组 |
| 使用端点 | HTTP Chunked |
| 默认行为 | 不强制 PCM；输出格式按 `opts["format"]` 和服务端默认值决定 |

```gdscript
var mp3 := await voice.fetch_audio("欢迎光临", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

传入 `opts["ssml"]` 时，`text` 可以为空字符串。

下面是一个缓存音频的使用场景：

```gdscript
var name = Global.player_name
var audio_path = "user://welcome.mp3"

# 准备 AudioStreamPlayer 节点
var player = AudioStreamPlayer.new()
add_child(player)

# 检查文件是否存在
if not FileAccess.file_exists(audio_path):
    # 文件不存在，则合成音频
    var mp3 := await voice.fetch_audio(
        "欢迎回来，尊敬的%s。" % name,
        "zh_male_dayi_uranus_bigtts",
        {"format": "mp3"}
    )
    var file := FileAccess.open(audio_path, FileAccess.WRITE)
    file.store_buffer(mp3)
    file.close()
    print("音频已生成")
else:
    print("音频已存在，无需合成")

# 播放音频
var stream := AudioStreamMP3.load_from_file(audio_path)
player.stream = stream
player.play()
```



### `stop()`、`current_session_id()` 和 `is_speaking()`

| API | 说明 |
|---|---|
| `stop()` | 中断当前高层播放任务，关闭活跃 WebSocket，清空待播放 PCM 队列 |
| `current_session_id()` | 返回上一段自然完成的高层播放 session id |
| `is_speaking()` | 返回当前是否有高层播放任务在运行 |

`stop()` 会让等待中的 `speak()` 返回 `false`，并在确实有播放任务时发出 `speak_finished`。空闲时调用 `stop()` 是安全的。

## `opts` 参数参考

`opts` 是一层扁平 `Dictionary`。`TtsOptions.build_req_params()` 会把各字段归位到火山协议需要的 `req_params` 结构。

| 键 | 类型 | 适用 API | 说明 |
|---|---|---|---|
| `format` | String | `speak` / `start_streaming` / `fetch_audio` / 底层 client | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"`；高层实时播放只支持 PCM，底层 client 和 `fetch_audio()` 可请求其它格式 |
| `sample_rate` | int | 所有合成 API | 常用 16000、24000、44100、48000 |
| `bit_rate` | int | `fetch_audio` / 底层 client | 仅 MP3 生效 |
| `emotion` | String | 所有合成 API | 多情感音色的情绪 |
| `emotion_scale` | int | 所有合成 API | 常用 1-5 |
| `speech_rate` | int | 所有合成 API | 常用 -50 到 100 |
| `loudness_rate` | int | 所有合成 API | 常用 -50 到 100 |
| `model` | String | 所有合成 API | 例如 `"seed-tts-2.0-expressive"` |
| `ssml` | String | `speak_ssml` / `speak` / 单向 WS / HTTP | 完整 `<speak>...</speak>`；双向流式不支持；高层推荐用 `speak_ssml()` |
| `context_texts` | Array[String] | 所有合成 API | TTS 2.0 上下文提示 |
| `section_id` | String | 所有合成 API | 上一段 session id，用于上下文延续 |
| `silence_duration` | int | 所有合成 API | 句尾静音，单位毫秒 |
| `disable_markdown_filter` | bool | 所有合成 API | 透传到火山 `additions` |
| `explicit_language` | String | 所有合成 API | 例如 `"zh-cn"` / `"en"` / `"ja"` |
| `enable_subtitle` | bool | 底层协议兼容 | 服务端可能返回字幕/时间戳帧；当前插件尚未暴露回调 |

高级逃生口：

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

`audio_params_extra` 和 `additions_extra` 会合并进对应协议字段。`raw_req_params` 会绕过所有合并逻辑，只有在火山新增字段、插件还没有命名支持时才建议使用。对高层 `speak()` 来说，`raw_req_params` 会直接发给单向端点；绕过普通参数构造时，需要自行包含服务端要求的 `text` 或 `ssml` 字段。

## 底层 Client

高层 `voice` 会公开三个底层 client。它们适合自定义播放、缓存、网关接入、协议调试或处理原始音频 chunk。普通业务优先使用高层 API。

### `voice.uni_client`

`VolcengineTTSUnidirectionalClient` 调用官方 `/api/v3/tts/unidirectional/stream` WebSocket 端点，这是官方的单向流式端点的一层封装，支持一次提交完整文本或 SSML，然后流式返回音频 chunk。

| API | 说明 |
|---|---|
| `synthesize_streaming(text, voice_id, on_chunk, opts := {}, out_session := {})` | 每收到一个音频块就调用 `on_chunk`；自然结束返回 `true` |
| `cancel()` | 关闭当前单向 WebSocket 请求 |

```gdscript
var out_session := {}
var ok := await voice.uni_client.synthesize_streaming(
	"这是官方单向流式端点。",
	"zh_male_dayi_uranus_bigtts",
	func(chunk: PackedByteArray) -> void:
		pass,
	{"format": "pcm", "sample_rate": 24000},
	out_session,
)
```

### `voice.bidi_client`

`VolcengineTTSBidirectionalClient` 调用官方 `/api/v3/tts/bidirection` WebSocket 端点。它适合逐段提交文本，并在同一个 session 中接收音频；底层音频格式由 `start_session()` 的 `opts["format"]` 决定。

| API / 信号 | 说明 |
|---|---|
| `start_session(voice_id, opts := {})` | 建立连接并启动 session |
| `feed_text(chunk)` | 向当前 session 发送文本 chunk |
| `finish_session()` | 通知服务端文本已发送完毕 |
| `cancel()` | 强制关闭当前 session |
| `audio_chunk_received(session_id, chunk)` | 收到音频块时发出 |
| `session_finished(session_id)` | session 自然完成时发出 |
| `session_failed(session_id, reason)` | session 失败时发出 |

### `voice.http_client`

`VolcengineTTSHttpClient` 调用官方 `/api/v3/tts/unidirectional` HTTP Chunked 端点。它适合获取完整音频字节后保存、缓存或交给其它播放器。

| API | 说明 |
|---|---|
| `synthesize(text, voice_id, opts := {}, out_session := {})` | 阻塞直到拿到完整音频字节；返回 `PackedByteArray` |

## 上下文、并发与中断

### 上下文延续

```gdscript
voice.auto_context_chain = true
await voice.speak("第一句", voice_id)
await voice.speak("第二句", voice_id)
voice.reset_context_chain()
```

开启 `auto_context_chain` 后，连续 `speak()` 或 `finish_streaming()` 完成时会保存返回的 `session_id`。下一次请求如果没有显式传 `section_id`，插件会自动把上一段 `session_id` 作为 `section_id` 传入。这个能力主要用于 TTS 2.0 的上下文延续。换角色、换场景或需要断开语境时调用 `reset_context_chain()`。

也可以手动传上下文：

```gdscript
await voice.speak("第二句", voice_id, {
	"context_texts": ["用骄傲但克制的语气说话。"],
	"section_id": previous_session_id,
})
```

### 并发与中断

`VolcengineStreamingVoicePlayer` 同一时间只跑一个播放任务。新的 `speak()` 或 `start_streaming()` 会先中断旧任务，再启动新任务。

```gdscript
voice.speak("第一句", voice_id)
voice.speak("第二句", voice_id)
```

被中断的 `await voice.speak(...)` 会醒来并返回 `false`。

主动停止：

```gdscript
voice.stop()
```

`speak_finished` 的语义是“不会再继续出声”，包括成功、失败和中断。要区分自然完成与失败/中断，请看 `speak()` 的返回值。

## 协议细节

这一节面向维护者和需要调试协议的人。普通业务开发通常不需要阅读。

通用请求头：

- `X-Api-Key: <api_key>`
- `X-Api-Resource-Id: <resource_id>`
- `X-Api-Connect-Id: <uuid>`，WebSocket 使用
- `X-Api-Request-Id: <uuid>`，HTTP 使用
- `X-Control-Require-Usage-Tokens-Return: *`

双向 WebSocket 流程：

1. 连接 `wss://<base_url>/api/v3/tts/bidirection`。
2. 发送 `StartConnection` 事件 `1`，等待 `ConnectionStarted` 事件 `50`。
3. 发送 `StartSession` 事件 `100`，payload 包含 `namespace = "BidirectionalTTS"` 和 `req_params`。
4. 发送一个或多个 `TaskRequest` 事件 `200` 文本包。
5. 发送 `FinishSession` 事件 `102`。
6. 接收音频帧，直到 `SessionFinished` 事件 `152`；失败时可能收到 `SessionFailed` 事件 `153`。
7. 尽力发送 `FinishConnection` 事件 `2` 并关闭连接。

双向 client 包使用二进制帧头 `[0x11, 0x14, 0x10, 0x00]`，后面依次是事件号、可选 session id 和 JSON payload。

单向 WebSocket 流程：

1. 连接 `wss://<base_url>/api/v3/tts/unidirectional/stream`。
2. 发送一个 `SendText` 包，帧头 `[0x11, 0x10, 0x10, 0x00]`。这个包没有事件号，payload 是完整请求 JSON。
3. 接收句首 `350`、音频响应 `352`、句尾 `351`、session 结束 `152` 等事件。
4. 发送 `FinishConnection` 事件 `2`，帧头 `[0x11, 0x14, 0x10, 0x00]`，然后关闭。

HTTP 流程：

1. POST JSON 到 `https://<base_url>/api/v3/tts/unidirectional`。
2. 读取 HTTP Chunked 响应；响应体每行是一个 JSON。
3. 对 `code == 0` 且 `data` 为字符串的行做 base64 解码并 append。
4. 遇到 `code == 20000000` 视为正常结束。

## 注意事项与限制

注意事项：

- Godot 高层实时播放只支持 PCM。流式 MP3/Opus 分块不能直接写入 `AudioStreamGenerator`。
- `speak()` 即使传入 `"format": "mp3"` 也会强制改成 PCM；`start_streaming()` 当前没有拦截非 PCM，但高层播放管线仍然只适合 PCM。需要 MP3 字节请用 `fetch_audio()` 或底层 client 自行处理。
- `speak()` 和 `speak_ssml()` 支持 SSML，因为它们使用单向端点。
- 双向流式不支持 SSML。需要 SSML 请走 `speak_ssml()`、`uni_client` 或 `fetch_audio()`。
- 部分 `saturn_` 和 `_saturn_bigtts` 音色不支持 SSML；插件只警告，最终由服务端决定。
- `default_model` 目前只会自动注入到 `saturn_` 音色。给不兼容音色乱传 model，在较严格端点上可能触发 resource/speaker mismatch。
- 超时是“无活动”超时：每收到一个包都会刷新 deadline。
- HTTP 返回的 chunk 不一定按 JSON 行对齐；HTTP client 会先缓存文本，遇到换行再解析。
- 服务端可能返回字幕/时间戳帧，但当前插件会忽略，尚未提供 `subtitle_received` 回调。

限制：

- 暂不支持 SSE 端点。
- 暂不提供字幕/时间戳回调。
- 不内置音色清单，`voice_id` 是由调用方维护的 `voice_type` 字符串。
- 不内置系统 TTS 兜底，失败处理由调用方决定。

# 参考

- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1598757
- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1719100
- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1329505
- 火山引擎语音合成大模型音色列表：https://www.volcengine.com/docs/6561/1257544
- 火山引擎 SDK 合规 / 隐私相关文档：https://www.volcengine.com/docs/6561/116711
- 火山引擎服务条款：https://www.volcengine.com/docs/6256/64903

## 许可证

本项目使用MIT许可证。详见 `LICENSE`。
