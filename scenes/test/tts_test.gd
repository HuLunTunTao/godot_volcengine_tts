extends Control

const SAMPLE_TEXT_EN := "Hello from Godot. This scene validates the Volcengine TTS plugin with HTTP synthesis, unidirectional streaming, and bidirectional chunked streaming."
const SAMPLE_TEXT_ZH := "你好，Godot。这个测试场景用于验证火山引擎 TTS 插件的 HTTP 合成、单向流式播放和双向分段流式播放。"
const DEFAULT_VOICE := "zh_male_dayi_uranus_bigtts"
const DEFAULT_SAMPLE_RATE := 24000

var _voice_player: VolcengineStreamingVoicePlayer
var _http_player: AudioStreamPlayer
var _uni_playback: AudioStreamGeneratorPlayback

@onready var api_key_edit: LineEdit = %ApiKeyEdit
@onready var resource_id_edit: LineEdit = %ResourceIdEdit
@onready var model_edit: LineEdit = %ModelEdit
@onready var voice_edit: LineEdit = %VoiceEdit
@onready var sample_rate_spin: SpinBox = %SampleRateSpin
@onready var text_edit: TextEdit = %TextEdit
@onready var title_label: Label = $"Margin/VBox/Title"
@onready var hint_label: Label = $"Margin/VBox/Hint"
@onready var api_key_label: Label = $"Margin/VBox/ApiKeyRow/ApiKeyLabel"
@onready var resource_label: Label = $"Margin/VBox/ConfigRow/ResourceLabel"
@onready var model_label: Label = $"Margin/VBox/ConfigRow/ModelLabel"
@onready var voice_label: Label = $"Margin/VBox/VoiceRow/VoiceLabel"
@onready var rate_label: Label = $"Margin/VBox/VoiceRow/RateLabel"
@onready var text_label: Label = $"Margin/VBox/TextLabel"
@onready var language_button: Button = %LanguageButton
@onready var http_button: Button = %HttpButton
@onready var uni_button: Button = %UniButton
@onready var bidi_button: Button = %BidiButton
@onready var stop_button: Button = %StopButton
@onready var status_label: Label = %StatusLabel

var _language := "en"


func _ready() -> void:
	_voice_player = VolcengineStreamingVoicePlayer.new()
	_voice_player.audio_bus = &"Master"
	add_child(_voice_player)

	_http_player = AudioStreamPlayer.new()
	_http_player.bus = &"Master"
	add_child(_http_player)

	resource_id_edit.text = "seed-tts-2.0"
	model_edit.text = "seed-tts-2.0-expressive"
	voice_edit.text = DEFAULT_VOICE
	sample_rate_spin.value = DEFAULT_SAMPLE_RATE
	text_edit.text = SAMPLE_TEXT_EN

	language_button.pressed.connect(_on_language_pressed)
	http_button.pressed.connect(_on_http_pressed)
	uni_button.pressed.connect(_on_uni_pressed)
	bidi_button.pressed.connect(_on_bidi_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	_apply_language()
	_set_status(_t("status_ready"))


func _apply_client_config() -> void:
	var clients := [_voice_player.bidi_client, _voice_player.uni_client, _voice_player.http_client]
	for client in clients:
		client.api_key = api_key_edit.text.strip_edges()
		client.resource_id = resource_id_edit.text.strip_edges()
		client.default_model = model_edit.text.strip_edges()


func _validate_inputs() -> bool:
	if api_key_edit.text.strip_edges().is_empty():
		_set_status(_t("status_api_key_required"))
		return false
	if voice_edit.text.strip_edges().is_empty():
		_set_status(_t("status_voice_required"))
		return false
	if text_edit.text.strip_edges().is_empty():
		_set_status(_t("status_text_required"))
		return false
	return true


func _on_http_pressed() -> void:
	if not _validate_inputs():
		return
	_set_busy(true)
	_apply_client_config()
	_http_player.stop()
	_set_status(_t("status_http_waiting"))

	var started_at := Time.get_ticks_msec()
	var audio := await _voice_player.fetch_audio(text_edit.text.strip_edges(), voice_edit.text.strip_edges(), {"format": "mp3"})
	var elapsed := (Time.get_ticks_msec() - started_at) / 1000.0

	if audio.is_empty():
		_set_status(_t("status_http_failed"))
		_set_busy(false)
		return

	var stream := AudioStreamMP3.new()
	stream.data = audio
	_http_player.stream = stream
	_http_player.play()
	_set_status(_t("status_http_ok") % [audio.size(), elapsed])
	_set_busy(false)


func _on_uni_pressed() -> void:
	if not _validate_inputs():
		return
	_set_busy(true)
	_apply_client_config()
	_http_player.stop()
	_voice_player.stop()
	_set_status(_t("status_uni_waiting"))

	var rate := int(sample_rate_spin.value)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(rate)
	generator.buffer_length = 0.5
	_http_player.stream = generator
	_http_player.play()
	_uni_playback = _http_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _uni_playback == null:
		_set_status(_t("status_playback_missing"))
		_set_busy(false)
		return

	var out_session := {}
	var started_at := Time.get_ticks_msec()
	var ok: bool = await _voice_player.uni_client.synthesize_streaming(
		text_edit.text.strip_edges(),
		voice_edit.text.strip_edges(),
		func(chunk: PackedByteArray) -> void:
			await _push_pcm(_uni_playback, chunk),
		{"format": "pcm", "sample_rate": rate},
		out_session,
	)
	var elapsed := (Time.get_ticks_msec() - started_at) / 1000.0
	if ok:
		_set_status(_t("status_uni_ok") % [elapsed, out_session.get("session_id", "")])
	else:
		_set_status(_t("status_uni_failed"))
	_set_busy(false)


func _on_bidi_pressed() -> void:
	if not _validate_inputs():
		return
	_set_busy(true)
	_apply_client_config()
	_http_player.stop()
	_voice_player.stop()
	_set_status(_t("status_bidi_starting"))

	var rate := int(sample_rate_spin.value)
	_voice_player.sample_rate = rate
	var ok := await _voice_player.start_streaming(voice_edit.text.strip_edges(), {"format": "pcm", "sample_rate": rate})
	if not ok:
		_set_status(_t("status_bidi_failed"))
		_set_busy(false)
		return

	var chunks := _split_text(text_edit.text.strip_edges(), 36)
	for index in chunks.size():
		_voice_player.feed_text(chunks[index])
		_set_status(_t("status_bidi_chunk") % [index + 1, chunks.size()])
		await get_tree().create_timer(0.35).timeout

	_voice_player.finish_streaming()
	await _voice_player.speak_finished
	_set_status(_t("status_bidi_finished") % _voice_player.current_session_id())
	_set_busy(false)


func _on_stop_pressed() -> void:
	_voice_player.stop()
	if _http_player != null:
		_http_player.stop()
	_set_busy(false)
	_set_status(_t("status_stopped"))


func _on_language_pressed() -> void:
	var current_text := text_edit.text.strip_edges()
	_language = "zh" if _language == "en" else "en"
	if current_text == SAMPLE_TEXT_EN or current_text == SAMPLE_TEXT_ZH:
		text_edit.text = _sample_text()
	_apply_language()
	_set_status(_t("status_language_changed"))


func _push_pcm(playback: AudioStreamGeneratorPlayback, bytes: PackedByteArray) -> void:
	var frames := _pcm_to_frames(bytes)
	var index := 0
	while index < frames.size():
		if playback == null:
			return
		var can_push := playback.get_frames_available()
		if can_push <= 0:
			await get_tree().process_frame
			continue
		var end := mini(index + can_push, frames.size())
		while index < end:
			playback.push_frame(frames[index])
			index += 1


func _pcm_to_frames(bytes: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(bytes.size() / 2)
	var frame_index := 0
	for byte_index in range(0, bytes.size() - 1, 2):
		var sample := int(bytes[byte_index]) | (int(bytes[byte_index + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var value: float = clamp(float(sample) / 32768.0, -1.0, 1.0)
		frames[frame_index] = Vector2(value, value)
		frame_index += 1
	return frames


func _split_text(text: String, chunk_size: int) -> Array[String]:
	var chunks: Array[String] = []
	var index := 0
	while index < text.length():
		chunks.append(text.substr(index, chunk_size))
		index += chunk_size
	return chunks


func _set_busy(busy: bool) -> void:
	http_button.disabled = busy
	uni_button.disabled = busy
	bidi_button.disabled = busy


func _set_status(message: String) -> void:
	status_label.text = message


func _apply_language() -> void:
	title_label.text = _t("title")
	hint_label.text = _t("hint")
	api_key_label.text = _t("api_key")
	api_key_edit.placeholder_text = _t("api_key_placeholder")
	resource_label.text = _t("resource")
	model_label.text = _t("model")
	voice_label.text = _t("voice")
	voice_edit.placeholder_text = _t("voice_placeholder")
	rate_label.text = _t("sample_rate")
	text_label.text = _t("text")
	language_button.text = _t("language_button")
	http_button.text = _t("http_button")
	uni_button.text = _t("uni_button")
	bidi_button.text = _t("bidi_button")
	stop_button.text = _t("stop_button")


func _sample_text() -> String:
	return SAMPLE_TEXT_ZH if _language == "zh" else SAMPLE_TEXT_EN


func _t(key: String) -> String:
	var zh := {
		"title": "Godot 火山引擎 TTS 测试",
		"hint": "粘贴火山引擎 API Key，填写音色，然后测试 HTTP 合成、单向流式或双向分段流式。凭证只保存在内存中。",
		"api_key": "API Key",
		"api_key_placeholder": "火山引擎 API Key",
		"resource": "资源",
		"model": "模型",
		"voice": "音色",
		"voice_placeholder": "voice_type，例如 zh_male_dayi_uranus_bigtts",
		"sample_rate": "采样率",
		"text": "文本",
		"language_button": "English/简体中文",
		"http_button": "HTTP MP3",
		"uni_button": "单向 WS PCM",
		"bidi_button": "双向 WS 分段",
		"stop_button": "停止",
		"status_ready": "就绪。粘贴 API Key，保留或修改音色，然后选择一条合成路径。",
		"status_api_key_required": "需要填写 API Key。",
		"status_voice_required": "需要填写 voice_type。",
		"status_text_required": "需要填写测试文本。",
		"status_http_waiting": "HTTP 合成：等待完整 MP3 响应...",
		"status_http_failed": "HTTP 合成失败。请查看输出面板里的 TTS-HTTP 警告。",
		"status_http_ok": "HTTP 合成成功：%d 字节，请求耗时 %.1f 秒。正在播放 MP3。",
		"status_uni_waiting": "单向 WebSocket：等待流式 PCM 音频块...",
		"status_playback_missing": "无法获取 AudioStreamGeneratorPlayback。",
		"status_uni_ok": "单向流式成功：%.1f 秒，session_id=%s。",
		"status_uni_failed": "单向流式失败。请查看输出面板里的 TTS-Uni 警告。",
		"status_bidi_starting": "双向 WebSocket：正在启动 session 并分段喂入文本...",
		"status_bidi_failed": "双向 start_session 失败。请查看输出面板里的 TTS-Bidi 警告。",
		"status_bidi_chunk": "双向流式：已发送分段 %d/%d。",
		"status_bidi_finished": "双向流式完成。session_id=%s。",
		"status_stopped": "已停止。",
		"status_language_changed": "语言已切换。"
	}
	var en := {
		"title": "Godot Volcengine TTS Test",
		"hint": "Paste a Volcengine API key, choose a voice type, then test HTTP synthesis, unidirectional streaming, or bidirectional chunked streaming. Credentials stay in memory only.",
		"api_key": "API Key",
		"api_key_placeholder": "Volcengine API key",
		"resource": "Resource",
		"model": "Model",
		"voice": "Voice",
		"voice_placeholder": "voice_type, for example zh_male_dayi_uranus_bigtts",
		"sample_rate": "Sample rate",
		"text": "Text",
		"language_button": "English/简体中文",
		"http_button": "HTTP MP3",
		"uni_button": "Uni WS PCM",
		"bidi_button": "Bidi WS Chunks",
		"stop_button": "Stop",
		"status_ready": "Ready. Paste an API key, keep or change the voice type, then run a synthesis path.",
		"status_api_key_required": "API key is required.",
		"status_voice_required": "Voice type is required.",
		"status_text_required": "Text is required.",
		"status_http_waiting": "HTTP synthesis: waiting for a complete MP3 response...",
		"status_http_failed": "HTTP synthesis failed. Check the Output panel for TTS-HTTP warnings.",
		"status_http_ok": "HTTP synthesis OK: %d bytes, %.1fs request time. Playing MP3.",
		"status_uni_waiting": "Unidirectional WebSocket: waiting for streamed PCM chunks...",
		"status_playback_missing": "Could not get AudioStreamGeneratorPlayback.",
		"status_uni_ok": "Unidirectional streaming OK: %.1fs, session_id=%s.",
		"status_uni_failed": "Unidirectional streaming failed. Check the Output panel for TTS-Uni warnings.",
		"status_bidi_starting": "Bidirectional WebSocket: starting session and feeding text chunks...",
		"status_bidi_failed": "Bidirectional start_session failed. Check the Output panel for TTS-Bidi warnings.",
		"status_bidi_chunk": "Bidirectional streaming: fed chunk %d/%d.",
		"status_bidi_finished": "Bidirectional streaming finished. session_id=%s.",
		"status_stopped": "Stopped.",
		"status_language_changed": "Language switched."
	}
	var table: Dictionary = zh if _language == "zh" else en
	return String(table.get(key, key))
