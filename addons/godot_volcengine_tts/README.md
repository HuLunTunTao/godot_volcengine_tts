# Godot Volcengine TTS

An unofficial third-party Godot 4 client SDK for Volcengine Doubao TTS. It was
originally extracted from a tactics RPG project that needed character dialogue,
low-latency streamed speech, and cached voice lines.

> Compliance notes, service terms, and disclaimers are kept in the repository
> root README.

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

## Supported Endpoints

| Endpoint | Class | Use case | SSML | Output |
|---|---|---|---|---|
| `wss://openspeech.bytedance.com/api/v3/tts/bidirection` | `VolcengineTTSBidirectionalClient` | LLM token streaming with incremental text | No | PCM streaming |
| `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream` | `VolcengineTTSUnidirectionalClient` | High-level `speak()` playback and one full text request | Yes | PCM/MP3/WAV/Opus chunks |
| `https://openspeech.bytedance.com/api/v3/tts/unidirectional` | `VolcengineTTSHttpClient` | Pre-generate or cache complete audio | Yes | Complete audio bytes |

`VolcengineStreamingVoicePlayer` owns all three clients and adds Godot playback
on top of them.

Important naming note: in this addon, "one-shot streaming playback" means the
high-level `speak()` helper. It uses the official unidirectional WebSocket
endpoint, sends one full text or SSML request, and streams returned PCM bytes
into `AudioStreamGenerator`. The bidirectional endpoint is reserved for
`start_streaming()` / `feed_text()` / `finish_streaming()` when text arrives
incrementally from an LLM or another generator.

Volcengine updates available voices over time. Check the official voice list
before choosing a `voice_type`:

https://www.volcengine.com/docs/6561/1257544

## Installation

Copy this folder into your project:

```text
addons/godot_volcengine_tts/
```

Then enable **Godot Volcengine TTS** in **Project Settings > Plugins**. The
editor plugin only exists to satisfy Godot's addon format; runtime code uses the
`class_name` scripts directly.

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

## Configuration

Most projects only need to set `api_key`, `resource_id`, and optionally
`default_model` on the clients they use:

```gdscript
for client in [voice.bidi_client, voice.uni_client, voice.http_client]:
	client.api_key = "your-volcengine-api-key"
	client.resource_id = "seed-tts-2.0"
	client.user_uid = "player-or-device-id"
	client.default_model = "seed-tts-2.0-expressive"
```

You can also override the host or API path. This is useful for private gateways,
reverse proxies, compatible endpoints, or future Volcengine path changes:

```gdscript
voice.bidi_client.base_url = "openspeech.bytedance.com"
voice.bidi_client.path = "/api/v3/tts/bidirection"

voice.uni_client.base_url = "your-gateway.example.com"
voice.uni_client.path = "/api/v3/tts/unidirectional/stream"

voice.http_client.base_url = "your-gateway.example.com"
voice.http_client.path = "/api/v3/tts/unidirectional"
```

`base_url` is the host only. Do not include `https://`, `wss://`, or a trailing
path. The clients add the protocol themselves: WebSocket clients use `wss://`,
and the HTTP client connects with TLS on port 443.

Other useful runtime knobs:

| Property | Owner | Default | Notes |
|---|---|---|---|
| `audio_bus` | `VolcengineStreamingVoicePlayer` | `&"Master"` | Godot audio bus for high-level playback |
| `sample_rate` | `VolcengineStreamingVoicePlayer` | `24000` | Default PCM playback sample rate for `speak()` and `start_streaming()` |
| `buffer_length` | `VolcengineStreamingVoicePlayer` | `0.5` | `AudioStreamGenerator` buffer length |
| `auto_context_chain` | `VolcengineStreamingVoicePlayer` | `false` | Reuses the previous session id as `section_id` |
| `connect_timeout_msec` | all clients | `8000` | WebSocket/HTTP connection timeout |
| `session_timeout_msec` | WS clients | `20000` | Inactivity timeout while waiting for WS packets |
| `read_timeout_msec` | HTTP client | `30000` | Inactivity timeout while reading HTTP chunks |

## API Quick Reference

| API | Endpoint | Result |
|---|---|---|
| `voice.speak(text, voice_id, opts)` | Unidirectional WS | Plays streamed PCM; returns `true` on natural completion |
| `voice.start_streaming(voice_id, opts)` / `feed_text(chunk)` / `finish_streaming()` | Bidirectional WS | Plays streamed PCM from incremental text |
| `voice.fetch_audio(text, voice_id, opts)` | HTTP chunked | Returns complete audio bytes |
| `voice.uni_client.synthesize_streaming(text, voice_id, on_chunk, opts, out_session)` | Unidirectional WS | Calls `on_chunk` for every streamed audio chunk |
| `voice.stop()` | Active high-level playback | Cancels playback and wakes waiters with `false` |
| `voice.current_session_id()` | High-level player | Returns the last completed high-level playback session id |

Signals:

- `voice.speak_finished`: emitted when high-level playback ends, fails, or is
  stopped.
- `voice.bidi_client.audio_chunk_received(session_id, chunk)`: lower-level
  bidirectional audio event.
- `voice.bidi_client.session_finished(session_id)` and
  `voice.bidi_client.session_failed(session_id, reason)`: lower-level
  bidirectional completion events.

## Use Case A: One-Shot Streaming Playback

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
add_child(voice)

voice.uni_client.api_key = "..."
voice.uni_client.resource_id = "seed-tts-2.0"

var ok := await voice.speak("Hold the bridge.", "zh_male_dayi_uranus_bigtts", {
	"emotion": "happy",
	"emotion_scale": 4,
	"speech_rate": 10,
})
```

`speak()` returns `true` when playback completes naturally and `false` when it
fails or is interrupted by `stop()` or a later request.

Implementation details:

- Uses `VolcengineTTSUnidirectionalClient`.
- Forces `format = "pcm"` because `AudioStreamGenerator` consumes PCM frames.
- Uses `sample_rate = voice.sample_rate` unless overridden in `opts`.
- Sends one full text or SSML request through the official unidirectional endpoint.
- Queues PCM chunks and pushes them with backpressure into
  `AudioStreamGeneratorPlayback`.

This path supports SSML through `opts["ssml"]`, while live Godot playback still
forces PCM output.

## Use Case B: True Bidirectional Streaming

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

for chunk in ["The bridge is ready. ", "Hold the line."]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.3).timeout

voice.finish_streaming()
await voice.speak_finished
```

Use this when text arrives incrementally from an LLM or other generator. All
chunks share one server session, so prosody can remain more continuous than
separate requests.

## Use Case C: Official Unidirectional Streaming

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
	"Hello from the unidirectional endpoint.",
	"zh_male_dayi_uranus_bigtts",
	func(chunk: PackedByteArray) -> void:
		# Convert signed 16-bit little-endian PCM into Vector2 frames here.
		pass,
	{"format": "pcm", "sample_rate": rate},
	out_session,
)
```

This is the official `/api/v3/tts/unidirectional/stream` path. It sends one
`SendText` packet containing the full request JSON, then receives
`TTSResponse` audio frames until `SessionFinished`.

Use this lower-level path directly when you want to own playback, buffering, or
byte handling yourself.

## Use Case D: Complete Audio Bytes

```gdscript
var mp3 := await voice.fetch_audio("Welcome back, commander.", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

`fetch_audio()` calls the HTTP chunked endpoint and returns one
`PackedByteArray`. The HTTP path is useful for pre-generated dialogue,
persistent caches, cutscenes, and UI prompts.

## Context Chaining

```gdscript
voice.auto_context_chain = true
await voice.speak("First line.", voice_id)
await voice.speak("Second line.", voice_id)
voice.reset_context_chain()
```

When `auto_context_chain` is enabled, consecutive `speak()` or
`finish_streaming()` completions save the returned `session_id`.
The next request passes it as `section_id` unless you already provided one.
This is intended for TTS 2.0 continuity. Call `reset_context_chain()` when the
speaker, scene, or dialogue context changes.

You can also pass context manually:

```gdscript
await voice.speak("Second line.", voice_id, {
	"context_texts": ["Speak with a proud but restrained tone."],
	"section_id": previous_session_id,
})
```

## Options

`opts` is a flat `Dictionary`. `TtsOptions.build_req_params()` moves each key
into the Volcengine `req_params` structure.

| Key | Type | Notes |
|---|---|---|
| `format` | String | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"` |
| `sample_rate` | int | Common values include 16000, 24000, 44100, 48000 |
| `bit_rate` | int | MP3 only |
| `emotion` | String | Emotion for supported voices |
| `emotion_scale` | int | Commonly 1-5 |
| `speech_rate` | int | Commonly -50 to 100 |
| `loudness_rate` | int | Commonly -50 to 100 |
| `model` | String | For example `"seed-tts-2.0-expressive"` |
| `ssml` | String | Full `<speak>...</speak>`, supported by `speak()`, uni, and HTTP |
| `context_texts` | Array[String] | TTS 2.0 context hints |
| `section_id` | String | Previous session id for context continuation |
| `silence_duration` | int | Tail silence in milliseconds |
| `disable_markdown_filter` | bool | Passes through Volcengine `additions` |
| `explicit_language` | String | For example `"zh-cn"` / `"en"` / `"ja"` |
| `enable_subtitle` | bool | Server may send subtitle/timestamp frames, but this addon does not expose callbacks yet |

Escape hatches:

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

`raw_req_params` bypasses all merging. Use it only when Volcengine adds fields
before this addon has first-class names for them. For high-level `speak()`, the
raw request is sent directly to the unidirectional endpoint, so include the text
or SSML fields required by the service when bypassing the normal option builder.

## Protocol Notes

Common request headers:

- `X-Api-Key: <api_key>`
- `X-Api-Resource-Id: <resource_id>`
- `X-Api-Connect-Id: <uuid>` for WebSocket connections
- `X-Api-Request-Id: <uuid>` for HTTP requests
- `X-Control-Require-Usage-Tokens-Return: *`

Bidirectional WebSocket flow:

1. Connect to `wss://<base_url>/api/v3/tts/bidirection`.
2. Send `StartConnection` event `1`; wait for `ConnectionStarted` event `50`.
3. Send `StartSession` event `100` with `namespace = "BidirectionalTTS"` and
   `req_params`.
4. Send one or more `TaskRequest` event `200` packets with text chunks.
5. Send `FinishSession` event `102`.
6. Receive audio frames, then `SessionFinished` event `152`, or
   `SessionFailed` event `153`.
7. Send `FinishConnection` event `2` best-effort and close.

Bidirectional client packets use a binary frame header
`[0x11, 0x14, 0x10, 0x00]`, followed by an event number, optional session id,
and JSON payload.

Unidirectional WebSocket flow:

1. Connect to `wss://<base_url>/api/v3/tts/unidirectional/stream`.
2. Send one `SendText` packet with header `[0x11, 0x10, 0x10, 0x00]`. This
   packet has no event number and contains the full request JSON.
3. Receive sentence start `350`, audio response `352`, sentence end `351`, and
   session finished `152` events.
4. Send `FinishConnection` event `2` with header `[0x11, 0x14, 0x10, 0x00]`
   and close.

HTTP flow:

1. POST JSON to `https://<base_url>/api/v3/tts/unidirectional`.
2. Read a chunked response where each line is JSON.
3. Append base64-decoded `data` from `code == 0` lines.
4. Stop when `code == 20000000`.

## Interruptions And Concurrency

`VolcengineStreamingVoicePlayer` runs one playback task at a time. A new
`speak()` or `start_streaming()` interrupts the previous playback task before
starting.

```gdscript
voice.speak("First line.", voice_id)  # not awaited
voice.speak("Second line.", voice_id) # interrupts the first line
```

The interrupted `await voice.speak(...)` wakes up and returns `false`.

Explicit stop:

```gdscript
voice.stop()
```

`stop()` closes active WebSockets, clears pending PCM chunks, stops the
`AudioStreamPlayer`, emits `speak_finished` if something was active, and makes
the waiting `speak()` return `false`. Calling `stop()` while idle is safe.

`speak_finished` means "no more audio will continue" for success, failure, or
interruption. Use the `speak()` return value to distinguish natural completion
from failure/interruption.

## Gotchas

- For live Godot playback, prefer PCM. Streaming MP3 chunks are not directly
  pushed into `AudioStreamGenerator`.
- `speak()` forces PCM even if you pass `"format": "mp3"`. Use `fetch_audio()`
  for MP3 bytes.
- `speak()` supports SSML because it uses the unidirectional endpoint.
- Bidirectional streaming does not support SSML. Use `speak()`, `uni_client`, or
  `fetch_audio()` for SSML.
- Some `saturn_` and `_saturn_bigtts` voices do not support SSML; the addon
  warns but lets the server decide.
- `default_model` is only injected automatically for `saturn_` voices. Passing
  model values to incompatible voices can trigger resource/speaker mismatch
  errors on stricter endpoints.
- Timeouts are inactivity timeouts. Receiving any packet extends the deadline.
- HTTP response chunks are not guaranteed to align with JSON line boundaries;
  the HTTP client buffers text until newline before decoding.
- Subtitle/timestamp frames may be returned by the server, but this addon
  currently ignores them.

## Limitations

- SSE endpoint support is not implemented.
- Subtitle/timestamp callbacks are not exposed yet.
- Voice lists are not bundled. The caller owns the `voice_type` string.
- System TTS fallback is not built in. Handle failures in your own game code.

## License

MIT. See `LICENSE`.
