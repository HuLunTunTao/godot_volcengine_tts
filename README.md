<div align="right">
  [<a href="./README.md">English</a>] [<a href="./README_CN.md">简体中文</a>]
</div>

<div align="center">
  <img src="./docs/images/icon-256.png" alt="Godot Volcengine TTS logo" height="96">
  <h1>Godot Volcengine TTS</h1>
  <p>Stream and generate Volcengine Doubao TTS audio directly inside Godot 4.</p>
</div>

Godot Volcengine TTS is an unofficial Godot 4 addon for integrating Volcengine
Doubao text-to-speech into games and interactive projects. It provides a
high-level playback node plus lower-level clients for bidirectional WebSocket
streaming, unidirectional streaming, and HTTP synthesis, so you can use the same
addon for live character dialogue, LLM-generated speech, UI prompts, cutscenes,
and cached voice lines.

The addon was originally extracted from a tactics RPG project that needed
low-latency voiced dialogue and pre-generated narration.

Detailed plugin documentation:

- [English addon README](addons/godot_volcengine_tts/README.md)
- [中文插件文档](addons/godot_volcengine_tts/README.zh-CN.md)

## Features

It supports the three common synthesis paths:

| Endpoint | Addon class | Use case | SSML | Output |
|---|---|---|---|---|
| `wss://openspeech.bytedance.com/api/v3/tts/bidirection` | `VolcengineTTSBidirectionalClient` | LLM token streaming and high-level `speak()` playback | No | PCM streaming for playback |
| `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream` | `VolcengineTTSUnidirectionalClient` | One request, streamed audio chunks | Yes | PCM/MP3/WAV/Opus chunks |
| `https://openspeech.bytedance.com/api/v3/tts/unidirectional` | `VolcengineTTSHttpClient` | Pre-generate or cache complete audio files | Yes | Complete audio bytes |

Important implementation detail: the high-level `VolcengineStreamingVoicePlayer.speak()`
method currently uses the official bidirectional WebSocket endpoint. It starts
one session, feeds the full text once, sends `FinishSession`, and plays the PCM
audio chunks as they arrive. The official unidirectional streaming endpoint is
still implemented, but it is exposed as the lower-level
`voice.uni_client.synthesize_streaming(...)` API.

## Installation

Copy the plugin folder into your project:

```text
addons/godot_volcengine_tts/
```

Then enable **Godot Volcengine TTS** in **Project Settings > Plugins**.

The Asset Library download archive is intentionally limited to `addons/` via
`.gitattributes`, so demo scenes, screenshots, and repository documentation do
not pollute user projects.

## Quick Examples

### One-Shot Streaming Playback

```gdscript
extends Node

func _ready() -> void:
	var voice := VolcengineStreamingVoicePlayer.new()
	add_child(voice)

	for client in [voice.bidi_client, voice.uni_client, voice.http_client]:
		client.api_key = "your-volcengine-api-key"
		client.resource_id = "seed-tts-2.0"
		client.default_model = "seed-tts-2.0-expressive"

	await voice.speak("Hello from Godot.", "zh_male_dayi_uranus_bigtts")
```

`speak()` uses the bidirectional WebSocket client internally: it starts one
session, feeds the full text, finishes the session, and streams PCM audio into
Godot playback.

Under the hood, all clients send Volcengine headers including `X-Api-Key`,
`X-Api-Resource-Id`, `X-Api-Connect-Id` or `X-Api-Request-Id`, and
`X-Control-Require-Usage-Tokens-Return: *`. Request options are built by
`TtsOptions.build_req_params()`, which maps flat Godot dictionaries such as
`{"format": "pcm", "speech_rate": 10}` into Volcengine `req_params`.

### Bidirectional Streaming

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

for chunk in ["The bridge is ready. ", "Hold the line."]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.25).timeout

voice.finish_streaming()
await voice.speak_finished
```

### Pre-Generate an MP3

```gdscript
var mp3 := await voice.fetch_audio("Welcome back, commander.", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

## Test Scene

This repository includes a local test scene at `scenes/test/tts_test.tscn`.
It is a bilingual validation UI for entering a Volcengine API key, resource ID,
model, voice type, sample rate, and sample text, then testing HTTP MP3
synthesis, unidirectional WebSocket PCM streaming, bidirectional chunked
streaming, and stop behavior.

The test scene intentionally exercises both layers: the HTTP button calls
`voice.fetch_audio()`, the unidirectional button calls
`voice.uni_client.synthesize_streaming()` directly and pushes PCM into
`AudioStreamGenerator`, and the bidirectional button calls
`voice.start_streaming()`, `voice.feed_text()`, and `voice.finish_streaming()`.

![Volcengine TTS test scene showing API, model, voice, text, HTTP, unidirectional streaming, bidirectional streaming, and stop controls](docs/images/screenshot_0.png)

The scene is for repository testing only and is excluded from Asset Library
downloads.

## Voices

Volcengine updates available voices over time. Check the official voice list
before choosing a `voice_type`:

- https://www.volcengine.com/docs/6561/1257544

## Compliance And Service Notes

This project is a third-party, unofficial Godot integration built from public
Volcengine interface documentation. It is not affiliated with, endorsed by, or
sponsored by ByteDance, Volcengine, or Doubao.

Users must provide their own Volcengine API credentials and are responsible for
complying with the relevant service terms, pricing rules, call limits, privacy
requirements, and content policies.

Product names, service names, and trademarks mentioned in this repository
belong to their respective owners.

Useful official references:

- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1598757
- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1719100
- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1329505
- Volcengine SDK compliance and privacy notes: https://www.volcengine.com/docs/6561/116711
- Volcengine service terms: https://www.volcengine.com/docs/6256/64903

## License

MIT. See `LICENSE`.
