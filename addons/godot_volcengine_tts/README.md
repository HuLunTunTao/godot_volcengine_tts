# Godot Volcengine TTS

An unofficial third-party Godot 4 client SDK for Volcengine Doubao TTS. It was originally extracted from a tactics RPG project that needed character dialogue, low-latency streamed speech, and cached voice lines.

> Compliance notes, service terms, and disclaimers are kept in the repository root README.

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

Volcengine updates available voices over time. Check the official voice list before choosing a `voice_type`:

https://www.volcengine.com/docs/6561/1257544

## Which API Should I Use?

Most projects should start with `VolcengineStreamingVoicePlayer`. It manages configuration, playback state, and the three lower-level clients.

| Need | Recommended API | Endpoint | Notes |
|---|---|---|---|
| Play one complete text string in real time | `voice.speak(text, voice_id, opts)` | Unidirectional WS | Most common path; streams PCM into Godot playback |
| Play one complete SSML string in real time | `voice.speak_ssml(ssml, voice_id, opts)` | Unidirectional WS | High-level SSML playback; no need to put content in `opts["ssml"]` |
| Stream incremental text from an LLM or generator | `start_streaming()` / `feed_text()` / `finish_streaming()` | Bidirectional WS | Multiple text chunks share one server session |
| Pre-generate, cache, or save an audio file | `voice.fetch_audio(text, voice_id, opts)` | HTTP chunked | Returns a complete `PackedByteArray` |
| Own audio chunks, buffering, or protocol handling | Lower-level clients | Unidirectional WS / Bidirectional WS / HTTP | Advanced usage; not the first choice for normal gameplay code |

Endpoint and client mapping:

| Endpoint | Class | SSML | Output |
|---|---|---|---|
| `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream` | `VolcengineTTSUnidirectionalClient` | Yes | PCM/MP3/WAV/Opus chunks |
| `wss://openspeech.bytedance.com/api/v3/tts/bidirection` | `VolcengineTTSBidirectionalClient` | No | High-level playback only supports PCM; lower-level clients can request the format specified by `opts["format"]` |
| `https://openspeech.bytedance.com/api/v3/tts/unidirectional` | `VolcengineTTSHttpClient` | Yes | Complete audio bytes |

## Installation

Copy this folder into your project:

```text
addons/godot_volcengine_tts/
```

Then enable **Godot Volcengine TTS** in **Project Settings > Plugins**. The editor plugin only exists to satisfy Godot's addon format; runtime code uses the `class_name` scripts directly.

## Quick Start

This is the smallest runnable example. `api_key` is required; the other fields either have defaults or are only needed for specific cases.

```gdscript
extends Node

func _ready() -> void:
	var voice := VolcengineStreamingVoicePlayer.new()
	voice.api_key = "your-volcengine-api-key"
	add_child(voice)

	var ok := await voice.speak("Hello from Godot.", "zh_male_dayi_uranus_bigtts")
	if not ok:
		push_warning("TTS playback failed or was interrupted")
```

The two required `speak()` arguments are the text content and the Volcengine voice string.

## Configuration

Configure authentication and model fields on the high-level `voice` node. `voice` copies these values to the bidirectional, unidirectional, and HTTP clients.

```gdscript
voice.api_key = "your-volcengine-api-key"
voice.resource_id = "seed-tts-2.0"
voice.user_uid = "player-or-device-id"
voice.default_model = "seed-tts-2.0-expressive"
```

Useful runtime properties:

| Property | Owner | Default | Notes |
|---|---|---|---|
| `api_key` | `voice` and all lower-level clients | `""` | Volcengine API key; requests fail if it is not configured |
| `resource_id` | `voice` and all lower-level clients | `"seed-tts-2.0"` | Volcengine resource id |
| `user_uid` | `voice` and all lower-level clients | `"default"` | User/device id sent in requests |
| `default_model` | `voice` and all lower-level clients | `""` | Default model injected for supported `saturn_` voices |
| `audio_bus` | `voice` | `&"Master"` | Godot audio bus for high-level playback |
| `sample_rate` | `voice` | `24000` | Default PCM playback sample rate for `speak()` and `start_streaming()` |
| `buffer_length` | `voice` | `0.5` | `AudioStreamGenerator` buffer length |
| `auto_context_chain` | `voice` | `false` | Reuses the previous session id as `section_id` |
| `connect_timeout_msec` | all lower-level clients | `8000` | WebSocket/HTTP connection timeout |
| `session_timeout_msec` | WebSocket clients | `20000` | WebSocket inactivity timeout while waiting for packets |
| `read_timeout_msec` | HTTP client | `30000` | HTTP inactivity timeout while reading chunks |

You can configure a lower-level client directly, but that only affects that client. If you later set `voice.api_key`, `voice.resource_id`, `voice.user_uid`, or `voice.default_model`, the value is copied over all three clients again.

```gdscript
voice.bidi_client.api_key = "your-volcengine-api-key"
voice.bidi_client.resource_id = "seed-tts-2.0"
voice.bidi_client.user_uid = "player-or-device-id"
voice.bidi_client.default_model = "seed-tts-2.0-expressive"
```

Private gateways, reverse proxies, or compatible endpoints can override the lower-level clients' host, API path, and timeouts:

```gdscript
voice.uni_client.base_url = "your-gateway.example.com"
voice.uni_client.path = "/api/v3/tts/unidirectional/stream"
voice.http_client.base_url = "your-gateway.example.com"
voice.http_client.path = "/api/v3/tts/unidirectional"
```

`base_url` is the host only. Do not include `https://`, `wss://`, or a path. WebSocket clients use `wss://`; the HTTP client connects with TLS on port 443.

## High-Level API

`VolcengineStreamingVoicePlayer` is the recommended entry point. It synchronizes configuration to the lower-level clients and connects returned PCM bytes to Godot's `AudioStreamGenerator`.

Signal:

- `voice.speak_finished`: emitted when high-level playback completes, fails, or is stopped.

Examples below assume this setup has already run:

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
voice.api_key = "your-volcengine-api-key"
add_child(voice)
```

### `speak(text, voice_id, opts := {})`

Purpose: submit one complete plain-text request and play the returned PCM in real time.

| Item | Details |
|---|---|
| Required arguments | `text`, `voice_id` |
| Optional arguments | `opts`; see `Options Reference` |
| Return value | `bool`; `true` on natural completion, `false` on failure or interruption |
| Endpoint | Unidirectional WebSocket |
| Defaults | Uses `pcm` if `format` is omitted; uses `voice.sample_rate` if `sample_rate` is omitted |

```gdscript
var ok := await voice.speak("Hold the bridge.", "zh_male_dayi_uranus_bigtts", {
	"emotion": "happy",
	"emotion_scale": 4,
	"speech_rate": 10,
})
```

`speak()` forces PCM because live Godot playback consumes PCM frames through `AudioStreamGenerator`. Even if you pass `"format": "mp3"`, it is changed to `"pcm"`; use `fetch_audio()` when you need MP3 bytes.

If another `speak()` or `start_streaming()` task is already running, the new call interrupts the old task first. The old `await voice.speak(...)` returns `false`.

### `speak_ssml(ssml, voice_id, opts := {})`

Purpose: submit one complete SSML request and play the returned PCM in real time.

| Item | Details |
|---|---|
| Required arguments | `ssml`, `voice_id` |
| Optional arguments | `opts`; see `Options Reference` |
| Return value | `bool`; `true` on natural completion, `false` on failure or interruption |
| Endpoint | Unidirectional WebSocket |
| Defaults | Reuses the `speak()` playback flow and forces PCM |

```gdscript
var ok := await voice.speak_ssml(
	"<speak>Hold the bridge.<break time=\"300ms\"/>Stand firm.</speak>",
	"zh_male_dayi_uranus_bigtts"
)
```

For high-level SSML playback, prefer `speak_ssml()`. `opts["ssml"]` remains available for lower-level compatibility and advanced usage.

### `start_streaming(voice_id, opts := {})` / `feed_text(chunk)` / `finish_streaming()`

Purpose: open a bidirectional streaming session for text that arrives incrementally from an LLM or another generator. Multiple text chunks share one server session, which can preserve prosody better than separate requests. When the server returns audio chunks before the final text is sent, playback also has a chance to begin earlier.

| API | Required arguments | Optional arguments | Return value |
|---|---|---|---|
| `start_streaming(voice_id, opts := {})` | `voice_id` | `opts` | `bool`; `true` when the session starts successfully |
| `feed_text(chunk)` | `chunk` | none | `bool`; `true` when the text packet is sent |
| `finish_streaming()` | none | none | No return value |

```gdscript
var ok := await voice.start_streaming("zh_male_dayi_uranus_bigtts")
if not ok:
	return

voice.feed_text("Hold the bridge. ")
voice.feed_text("The line must stand. ")
voice.feed_text("No one falls back.")

voice.finish_streaming()
await voice.speak_finished
```

Bidirectional playback does not start at `finish_streaming()`. `start_streaming()` prepares the player, and each `feed_text()` sends text to the server. As soon as the server returns the first audio chunk, the addon writes it into Godot's playback buffer and audio begins. `finish_streaming()` only means that no more text will be fed.

Bidirectional streaming does not support SSML. If you already have complete text, prefer `speak()`.

### `fetch_audio(text, voice_id, opts := {})`

Purpose: call the HTTP chunked endpoint and return complete audio bytes. This is useful for pre-generated dialogue, persistent caches, cutscenes, and UI prompts.

| Item | Details |
|---|---|
| Required arguments | `text`, `voice_id` |
| Optional arguments | `opts`; usually pass `"format"` explicitly |
| Return value | `PackedByteArray`; empty on failure |
| Endpoint | HTTP chunked |
| Defaults | Does not force PCM; output format follows `opts["format"]` and server defaults |

```gdscript
var mp3 := await voice.fetch_audio("Welcome back, commander.", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

When `opts["ssml"]` is provided, `text` may be an empty string.

Here is a typical cached-audio use case:

```gdscript
var name = Global.player_name
var audio_path = "user://welcome.mp3"

var player = AudioStreamPlayer.new()
add_child(player)

if not FileAccess.file_exists(audio_path):
	var mp3 := await voice.fetch_audio(
		"Welcome back, %s." % name,
		"zh_male_dayi_uranus_bigtts",
		{"format": "mp3"}
	)
	var file := FileAccess.open(audio_path, FileAccess.WRITE)
	file.store_buffer(mp3)
	file.close()
	print("Audio generated")
else:
	print("Audio already exists")

var stream := AudioStreamMP3.load_from_file(audio_path)
player.stream = stream
player.play()
```

### `stop()`, `current_session_id()`, and `is_speaking()`

| API | Details |
|---|---|
| `stop()` | Interrupts the current high-level playback task, closes active WebSockets, and clears pending PCM chunks |
| `current_session_id()` | Returns the last naturally completed high-level playback session id |
| `is_speaking()` | Returns whether a high-level playback task is currently active |

`stop()` makes any waiting `speak()` return `false` and emits `speak_finished` if a playback task was active. Calling `stop()` while idle is safe.

## Options Reference

`opts` is a flat `Dictionary`. `TtsOptions.build_req_params()` moves each key into the Volcengine `req_params` structure.

| Key | Type | Applies to | Notes |
|---|---|---|---|
| `format` | String | `speak` / `start_streaming` / `fetch_audio` / lower-level clients | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"`; high-level real-time playback only supports PCM, while lower-level clients and `fetch_audio()` can request other formats |
| `sample_rate` | int | All synthesis APIs | Common values include 16000, 24000, 44100, 48000 |
| `bit_rate` | int | `fetch_audio` / lower-level clients | MP3 only |
| `emotion` | String | All synthesis APIs | Emotion for supported voices |
| `emotion_scale` | int | All synthesis APIs | Commonly 1-5 |
| `speech_rate` | int | All synthesis APIs | Commonly -50 to 100 |
| `loudness_rate` | int | All synthesis APIs | Commonly -50 to 100 |
| `model` | String | All synthesis APIs | For example `"seed-tts-2.0-expressive"` |
| `ssml` | String | `speak_ssml` / `speak` / unidirectional WS / HTTP | Full `<speak>...</speak>`; bidirectional streaming does not support it; high-level code should prefer `speak_ssml()` |
| `context_texts` | Array[String] | All synthesis APIs | TTS 2.0 context hints |
| `section_id` | String | All synthesis APIs | Previous session id for context continuation |
| `silence_duration` | int | All synthesis APIs | Tail silence in milliseconds |
| `disable_markdown_filter` | bool | All synthesis APIs | Passes through Volcengine `additions` |
| `explicit_language` | String | All synthesis APIs | For example `"zh-cn"` / `"en"` / `"ja"` |
| `enable_subtitle` | bool | Protocol compatibility | Server may send subtitle/timestamp frames; this addon does not expose callbacks yet |

Advanced escape hatches:

```gdscript
await voice.speak("Line.", voice_id, {
	"audio_params_extra": {"future_audio_field": "value"},
	"additions_extra": {"with_frontend_text": true},
	"raw_req_params": {
		"speaker": voice_id,
		"audio_params": {"format": "pcm", "sample_rate": 24000},
	},
})
```

`audio_params_extra` and `additions_extra` are merged into the corresponding protocol fields. `raw_req_params` bypasses all merging and should only be used when Volcengine adds fields before this addon has first-class names for them. For high-level `speak()`, the raw request is sent directly to the unidirectional endpoint, so include the service-required `text` or `ssml` fields yourself.

## Lower-Level Clients

The high-level `voice` object exposes three lower-level clients. Use them for custom playback, caching, gateway integration, protocol debugging, or raw audio chunk handling. Normal gameplay code should prefer the high-level API.

### `voice.uni_client`

`VolcengineTTSUnidirectionalClient` calls the official `/api/v3/tts/unidirectional/stream` WebSocket endpoint. It submits one complete text or SSML request and streams audio chunks back.

| API | Details |
|---|---|
| `synthesize_streaming(text, voice_id, on_chunk, opts := {}, out_session := {})` | Calls `on_chunk` for every audio chunk; returns `true` on natural completion |
| `cancel()` | Closes the current unidirectional WebSocket request |

```gdscript
var out_session := {}
var ok := await voice.uni_client.synthesize_streaming(
	"Hello from the unidirectional endpoint.",
	"zh_male_dayi_uranus_bigtts",
	func(chunk: PackedByteArray) -> void:
		pass,
	{"format": "pcm", "sample_rate": 24000},
	out_session,
)
```

### `voice.bidi_client`

`VolcengineTTSBidirectionalClient` calls the official `/api/v3/tts/bidirection` WebSocket endpoint. It is useful when you need to submit text chunks and receive audio in the same session; the lower-level audio format follows `opts["format"]` passed to `start_session()`.

| API / Signal | Details |
|---|---|
| `start_session(voice_id, opts := {})` | Connects and starts a session |
| `feed_text(chunk)` | Sends a text chunk to the current session |
| `finish_session()` | Tells the server that all text has been sent |
| `cancel()` | Force-closes the current session |
| `audio_chunk_received(session_id, chunk)` | Emitted when an audio chunk arrives |
| `session_finished(session_id)` | Emitted when the session completes naturally |
| `session_failed(session_id, reason)` | Emitted when the session fails |

### `voice.http_client`

`VolcengineTTSHttpClient` calls the official `/api/v3/tts/unidirectional` HTTP chunked endpoint. It is useful when you want complete audio bytes for saving, caching, or playback through another system.

| API | Details |
|---|---|
| `synthesize(text, voice_id, opts := {}, out_session := {})` | Waits until complete audio bytes are available; returns `PackedByteArray` |

## Context, Concurrency, And Interruptions

### Context Chaining

```gdscript
voice.auto_context_chain = true
await voice.speak("First line.", voice_id)
await voice.speak("Second line.", voice_id)
voice.reset_context_chain()
```

When `auto_context_chain` is enabled, consecutive `speak()` or `finish_streaming()` completions save the returned `session_id`. The next request passes it as `section_id` unless you already provided one. This is intended for TTS 2.0 continuity. Call `reset_context_chain()` when the speaker, scene, or dialogue context changes.

You can also pass context manually:

```gdscript
await voice.speak("Second line.", voice_id, {
	"context_texts": ["Speak with a proud but restrained tone."],
	"section_id": previous_session_id,
})
```

### Concurrency And Interruptions

`VolcengineStreamingVoicePlayer` runs one playback task at a time. A new `speak()` or `start_streaming()` interrupts the previous playback task before starting.

```gdscript
voice.speak("First line.", voice_id)
voice.speak("Second line.", voice_id)
```

The interrupted `await voice.speak(...)` wakes up and returns `false`.

Explicit stop:

```gdscript
voice.stop()
```

`speak_finished` means "no more audio will continue" for success, failure, or interruption. Use the `speak()` return value to distinguish natural completion from failure or interruption.

## Protocol Notes

This section is for maintainers and protocol debugging. Normal gameplay code usually does not need it.

Common request headers:

- `X-Api-Key: <api_key>`
- `X-Api-Resource-Id: <resource_id>`
- `X-Api-Connect-Id: <uuid>` for WebSocket connections
- `X-Api-Request-Id: <uuid>` for HTTP requests
- `X-Control-Require-Usage-Tokens-Return: *`

Bidirectional WebSocket flow:

1. Connect to `wss://<base_url>/api/v3/tts/bidirection`.
2. Send `StartConnection` event `1`; wait for `ConnectionStarted` event `50`.
3. Send `StartSession` event `100` with `namespace = "BidirectionalTTS"` and `req_params`.
4. Send one or more `TaskRequest` event `200` packets with text chunks.
5. Send `FinishSession` event `102`.
6. Receive audio frames, then `SessionFinished` event `152`, or `SessionFailed` event `153`.
7. Send `FinishConnection` event `2` best-effort and close.

Bidirectional client packets use binary frame header `[0x11, 0x14, 0x10, 0x00]`, followed by an event number, optional session id, and JSON payload.

Unidirectional WebSocket flow:

1. Connect to `wss://<base_url>/api/v3/tts/unidirectional/stream`.
2. Send one `SendText` packet with header `[0x11, 0x10, 0x10, 0x00]`. This packet has no event number and contains the full request JSON.
3. Receive sentence start `350`, audio response `352`, sentence end `351`, and session finished `152` events.
4. Send `FinishConnection` event `2` with header `[0x11, 0x14, 0x10, 0x00]` and close.

HTTP flow:

1. POST JSON to `https://<base_url>/api/v3/tts/unidirectional`.
2. Read a chunked response where each line is JSON.
3. Append base64-decoded `data` from `code == 0` lines.
4. Stop when `code == 20000000`.

## Notes And Limitations

Notes:

- High-level real-time Godot playback only supports PCM. Streaming MP3/Opus chunks cannot be pushed directly into `AudioStreamGenerator`.
- `speak()` forces PCM even if you pass `"format": "mp3"`; `start_streaming()` currently does not reject non-PCM formats, but its high-level playback pipeline is still only suitable for PCM. Use `fetch_audio()` or lower-level clients when you need to handle MP3 bytes yourself.
- `speak()` and `speak_ssml()` support SSML because they use the unidirectional endpoint.
- Bidirectional streaming does not support SSML. Use `speak_ssml()`, `uni_client`, or `fetch_audio()` for SSML.
- Some `saturn_` and `_saturn_bigtts` voices do not support SSML; the addon warns but lets the server decide.
- `default_model` is only injected automatically for `saturn_` voices. Passing model values to incompatible voices can trigger resource/speaker mismatch errors on stricter endpoints.
- Timeouts are inactivity timeouts. Receiving any packet extends the deadline.
- HTTP response chunks are not guaranteed to align with JSON line boundaries; the HTTP client buffers text until newline before decoding.
- Subtitle/timestamp frames may be returned by the server, but this addon currently ignores them and does not expose `subtitle_received`.

Limitations:

- SSE endpoint support is not implemented.
- Subtitle/timestamp callbacks are not exposed yet.
- Voice lists are not bundled. The caller owns the `voice_type` string.
- System TTS fallback is not built in. Handle failures in your own game code.

## References

- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1598757
- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1719100
- Volcengine TTS API documentation: https://www.volcengine.com/docs/6561/1329505
- Volcengine speech synthesis voice list: https://www.volcengine.com/docs/6561/1257544
- Volcengine SDK compliance / privacy documentation: https://www.volcengine.com/docs/6561/116711
- Volcengine terms of service: https://www.volcengine.com/docs/6256/64903

## License

MIT. See `LICENSE`.
