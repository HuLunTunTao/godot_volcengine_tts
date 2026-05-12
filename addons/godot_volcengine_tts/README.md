# Godot Volcengine TTS

An unofficial third-party Godot 4 client SDK for Volcengine Doubao TTS. It was
originally extracted from a tactics RPG project that needed character dialogue,
low-latency streamed speech, and cached voice lines.

> Compliance notes, service terms, and disclaimers are kept in the repository
> root README.

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

## Supported Endpoints

| Endpoint | Use case | SSML | Output |
|---|---|---|---|
| Bidirectional WebSocket | LLM token streaming and low-latency playback | No | PCM streaming |
| Unidirectional WebSocket | One request, streamed audio chunks | Yes | PCM/MP3/WAV/Opus |
| HTTP chunked synthesis | Pre-generate or cache complete audio files | Yes | Complete audio bytes |

Volcengine updates available voices over time. Check the official voice list
before choosing a `voice_type`:

https://www.volcengine.com/docs/6561/1257544

## Installation

Copy this folder into your project:

```text
addons/godot_volcengine_tts/
```

Then enable **Godot Volcengine TTS** in **Project Settings > Plugins**.

## Quick Start

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

	await voice.speak("Hello from Godot.", "zh_male_dayi_uranus_bigtts")
```

## Use Case A: One-Shot Streaming Playback

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
add_child(voice)

voice.bidi_client.api_key = "..."
voice.bidi_client.resource_id = "seed-tts-2.0"

var ok := await voice.speak("Hold the bridge.", "zh_male_dayi_uranus_bigtts")
```

`speak()` uses the bidirectional WebSocket client internally: it starts one
session, feeds the full text, finishes the session, and streams PCM audio into
Godot playback.

`speak()` returns `true` when playback completes naturally and `false` when it
fails or is interrupted by `stop()` or a later request.

## Use Case B: Bidirectional Streaming

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

for chunk in ["The bridge is ready. ", "Hold the line."]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.3).timeout

voice.finish_streaming()
await voice.speak_finished
```

Bidirectional streaming is useful when text arrives incrementally from an LLM.
This endpoint does not support SSML.

## Use Case C: Complete Audio Bytes

```gdscript
var mp3 := await voice.fetch_audio("Welcome back, commander.", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

The HTTP path is useful for pre-generated dialogue, persistent caches,
cutscenes, and UI prompts.

## Context Chaining

```gdscript
voice.auto_context_chain = true
await voice.speak("First line.", voice_id)
await voice.speak("Second line.", voice_id)
voice.reset_context_chain()
```

When `auto_context_chain` is enabled, consecutive `speak()` calls reuse the
previous `session_id` as `section_id` for smoother TTS 2.0 continuity. Call
`reset_context_chain()` when the speaker or scene changes.

## Common Options

| Key | Type | Notes |
|---|---|---|
| `format` | String | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"` |
| `sample_rate` | int | 8000 to 48000, default 24000 |
| `emotion` | String | Emotion for supported voices |
| `emotion_scale` | int | Commonly 1-5 |
| `speech_rate` | int | Commonly -50 to 100 |
| `loudness_rate` | int | Commonly -50 to 100 |
| `model` | String | For example `"seed-tts-2.0-expressive"` |
| `ssml` | String | Full `<speak>...</speak>`, uni/HTTP only |
| `context_texts` | Array[String] | TTS 2.0 context hints |
| `section_id` | String | Previous session id |

See `tts_options.gd` for the full request parameter merge behavior.

## Interruptions And Concurrency

`VolcengineStreamingVoicePlayer` runs one playback task at a time. A new
`speak()` or `start_streaming()` interrupts the previous task before starting.
You can stop playback explicitly:

```gdscript
voice.stop()
```

Any coroutine waiting on the interrupted `speak()` call wakes up and returns
`false`.

## Limitations

- SSE endpoint support is not implemented.
- Subtitle/timestamp callbacks are not exposed yet.
- Voice lists are not bundled. The caller owns the `voice_type` string.
- System TTS fallback is not built in. Handle failures in your own game code.

## License

MIT. See `LICENSE`.
