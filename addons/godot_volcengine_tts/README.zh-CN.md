# Godot Volcengine TTS

第三方非官方 Godot 4 火山引擎豆包 TTS 调用库。它最初来自一个战棋游戏项目，
用于角色对白、低延迟流式语音和固定台词预生成。

> 合规、服务条款和免责声明见仓库根目录 README。

## 支持端点

| 端点 | 用途 | SSML | 输出 |
|---|---|---|---|
| 双向 WebSocket | LLM token streaming，边喂文字边出音频 | 否 | PCM 流 |
| 单向 WebSocket | 一次提交文本，流式返回音频块 | 是 | PCM/MP3/WAV/Opus |
| HTTP Chunked | 预生成、缓存、短提示音 | 是 | 完整音频字节 |

音色列表以火山引擎官方文档为准：

https://www.volcengine.com/docs/6561/1257544

## 安装

复制本目录到项目：

```text
addons/godot_volcengine_tts/
```

然后在 **项目设置 > 插件** 启用 **Godot Volcengine TTS**。

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

## 用法 A：单句流式播放

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
add_child(voice)

voice.bidi_client.api_key = "..."
voice.bidi_client.resource_id = "seed-tts-2.0"

var ok := await voice.speak("依老朽看，这桥要成。", "zh_male_dayi_uranus_bigtts")
```

`speak()` 内部使用双向 WebSocket：启动一个 session，喂入整段文本，结束 session，
并把返回的 PCM 音频流式送入 Godot 播放。

`speak()` 返回 `true` 表示自然完成，返回 `false` 表示失败或被 `stop()`/重入中断。

## 用法 B：双向流式

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

for chunk in ["依老朽看，", "这桥要成。", "须得脚下踩稳。"]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.3).timeout

voice.finish_streaming()
await voice.speak_finished
```

双向流式适合 LLM 逐 token 输出的对白。协议层不支持 SSML。

## 用法 C：拿完整音频字节

```gdscript
var mp3 := await voice.fetch_audio("欢迎光临", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

HTTP 路径适合预合成固定台词、缓存、cutscene 或 UI 提示音。

## 上下文支持

```gdscript
voice.auto_context_chain = true
await voice.speak("第一句", voice_id)
await voice.speak("第二句", voice_id)
voice.reset_context_chain()
```

开启 `auto_context_chain` 后，连续 `speak()` 会自动把上一段 `session_id` 作为下一段的
`section_id`，让 TTS 2.0 的上下文语气更连贯。换角色或换场景时应调用
`reset_context_chain()`。

## 常用 opts

| 键 | 类型 | 说明 |
|---|---|---|
| `format` | String | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"` |
| `sample_rate` | int | 8000 到 48000，默认 24000 |
| `emotion` | String | 多情感音色的情绪参数 |
| `emotion_scale` | int | 情绪强度，常用 1-5 |
| `speech_rate` | int | 语速，常用 -50 到 100 |
| `loudness_rate` | int | 音量，常用 -50 到 100 |
| `model` | String | 例如 `"seed-tts-2.0-expressive"` |
| `ssml` | String | 完整 `<speak>...</speak>`，仅单向/HTTP 路径 |
| `context_texts` | Array[String] | TTS 2.0 上下文提示 |
| `section_id` | String | 上一段 session id |

完整字段合并逻辑见 `tts_options.gd`。

## 中断与并发

`VolcengineStreamingVoicePlayer` 同一时间只跑一个播放任务。新的 `speak()` 或
`start_streaming()` 会先中断旧任务，再启动新任务。主动中断可调用：

```gdscript
voice.stop()
```

旧的 `await voice.speak(...)` 会醒来并返回 `false`。

## 限制

- 暂不支持 SSE 端点。
- 暂不提供字幕/时间戳回调。
- 不内置音色清单，`voice` 是由调用方维护的 `voice_type` 字符串。
- 不内置系统 TTS 兜底，失败处理由调用方决定。

## 许可证

MIT。详见 `LICENSE`。
