extends Control

const SAMPLE_TEXT_EN := "Hello from Godot. This scene validates the Volcengine TTS plugin with HTTP synthesis, unidirectional streaming, and bidirectional chunked streaming."
const SAMPLE_TEXT_ZH := "你好，Godot。这个测试场景用于验证火山引擎 TTS 插件的 HTTP 合成、单向流式播放和双向分段流式播放。"
const DEFAULT_VOICE := "zh_male_dayi_uranus_bigtts"
const DEFAULT_SAMPLE_RATE := 24000
const MODE_HTTP_MP3 := 0
const MODE_UNI_WS_PCM := 1
const MODE_BIDI_WS_CHUNKS := 2
const MODE_SAVE_MP3 := 3

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
@onready var mode_label: Label = $"Margin/VBox/ModeRow/ModeLabel"
@onready var mode_option: OptionButton = %ModeOption
@onready var run_button: Button = %RunButton
@onready var stop_button: Button = %StopButton
@onready var save_options_box: VBoxContainer = %SaveOptionsBox
@onready var save_dir_label: Label = %SaveDirLabel
@onready var save_dir_edit: LineEdit = %SaveDirEdit
@onready var save_dir_button: Button = %SaveDirButton
@onready var filename_label: Label = %FilenameLabel
@onready var filename_template_edit: LineEdit = %FilenameTemplateEdit
@onready var index_label: Label = %IndexLabel
@onready var index_spin: SpinBox = %IndexSpin
@onready var auto_increment_check: CheckBox = %AutoIncrementCheck
@onready var placeholder_hint: Label = %PlaceholderHint
@onready var replay_saved_button: Button = %ReplaySavedButton
@onready var save_dir_dialog: FileDialog = %SaveDirDialog
@onready var status_label: Label = %StatusLabel

var _language := "en"
var _last_saved_audio := PackedByteArray()


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
	mode_option.item_selected.connect(_on_mode_selected)
	run_button.pressed.connect(_on_run_pressed)
	save_dir_button.pressed.connect(_on_save_dir_pressed)
	replay_saved_button.pressed.connect(_on_replay_saved_pressed)
	save_dir_dialog.dir_selected.connect(_on_save_dir_selected)
	stop_button.pressed.connect(_on_stop_pressed)
	_apply_language()
	_update_save_options_visibility()
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


func _validate_save_inputs() -> bool:
	if save_dir_edit.text.strip_edges().is_empty():
		_set_status(_t("status_save_dir_required"))
		return false
	if not DirAccess.dir_exists_absolute(save_dir_edit.text.strip_edges()):
		_set_status(_t("status_save_dir_invalid"))
		return false
	if filename_template_edit.text.strip_edges().is_empty():
		_set_status(_t("status_filename_required"))
		return false
	return true


func _on_run_pressed() -> void:
	match mode_option.get_selected_id():
		MODE_HTTP_MP3:
			await _on_http_pressed()
		MODE_UNI_WS_PCM:
			await _on_uni_pressed()
		MODE_BIDI_WS_CHUNKS:
			await _on_bidi_pressed()
		MODE_SAVE_MP3:
			await _on_save_audio_pressed()


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


func _on_save_audio_pressed() -> void:
	if not _validate_inputs():
		return
	if not _validate_save_inputs():
		return
	_set_busy(true)
	_apply_client_config()
	_http_player.stop()
	_voice_player.stop()
	_clear_last_saved_audio()
	_set_status(_t("status_save_waiting"))

	var started_at := Time.get_ticks_msec()
	var audio := await _voice_player.fetch_audio(text_edit.text.strip_edges(), voice_edit.text.strip_edges(), {"format": "mp3"})
	var elapsed := (Time.get_ticks_msec() - started_at) / 1000.0

	if audio.is_empty():
		_set_status(_t("status_save_failed"))
		_set_busy(false)
		return

	var filename := _build_filename()
	var path := _join_path(save_dir_edit.text.strip_edges(), filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status(_t("status_save_open_failed") % FileAccess.get_open_error())
		_set_busy(false)
		return
	file.store_buffer(audio)
	file.close()

	_last_saved_audio = audio
	_play_mp3(audio)
	_update_replay_saved_button()

	if auto_increment_check.button_pressed:
		index_spin.value += 1.0
	_set_status(_t("status_save_ok") % [path, audio.size(), elapsed])
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
	_update_save_options_visibility()
	_set_status(_t("status_language_changed"))


func _on_mode_selected(_index: int) -> void:
	if mode_option.get_selected_id() != MODE_SAVE_MP3:
		_clear_last_saved_audio()
	_update_save_options_visibility()


func _on_save_dir_pressed() -> void:
	save_dir_dialog.current_dir = save_dir_edit.text.strip_edges()
	save_dir_dialog.popup_centered_ratio(0.75)


func _on_save_dir_selected(dir: String) -> void:
	save_dir_edit.text = dir


func _on_replay_saved_pressed() -> void:
	if _last_saved_audio.is_empty():
		replay_saved_button.visible = false
		return
	_play_mp3(_last_saved_audio)
	_set_status(_t("status_replay_saved"))


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
	mode_option.disabled = busy
	run_button.disabled = busy
	save_dir_button.disabled = busy
	replay_saved_button.disabled = busy


func _set_status(message: String) -> void:
	status_label.text = message


func _update_mode_options() -> void:
	var selected_id := mode_option.get_selected_id()
	if selected_id < 0:
		selected_id = MODE_HTTP_MP3
	mode_option.clear()
	mode_option.add_item(_t("mode_http_mp3"), MODE_HTTP_MP3)
	mode_option.add_item(_t("mode_uni_ws_pcm"), MODE_UNI_WS_PCM)
	mode_option.add_item(_t("mode_bidi_ws_chunks"), MODE_BIDI_WS_CHUNKS)
	mode_option.add_item(_t("mode_save_mp3"), MODE_SAVE_MP3)
	for item_index in mode_option.item_count:
		if mode_option.get_item_id(item_index) == selected_id:
			mode_option.select(item_index)
			return
	mode_option.select(0)


func _update_save_options_visibility() -> void:
	save_options_box.visible = mode_option.get_selected_id() == MODE_SAVE_MP3
	_update_replay_saved_button()


func _update_replay_saved_button() -> void:
	replay_saved_button.visible = save_options_box.visible and not _last_saved_audio.is_empty()


func _clear_last_saved_audio() -> void:
	_last_saved_audio.clear()
	_update_replay_saved_button()


func _play_mp3(audio: PackedByteArray) -> void:
	var stream := AudioStreamMP3.new()
	stream.data = audio
	_http_player.stream = stream
	_http_player.play()


func _build_filename() -> String:
	var filename := filename_template_edit.text.strip_edges()
	var replacements := {
		"{voice}": voice_edit.text.strip_edges(),
		"{model}": model_edit.text.strip_edges(),
		"{resource}": resource_id_edit.text.strip_edges(),
		"{index}": str(int(index_spin.value)),
	}
	for key in replacements:
		filename = filename.replace(key, String(replacements[key]))
	filename = _sanitize_filename(filename)
	if filename.get_extension().is_empty():
		filename += ".mp3"
	return filename


func _sanitize_filename(filename: String) -> String:
	var result := filename
	for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		result = result.replace(invalid, "_")
	return result


func _join_path(dir: String, filename: String) -> String:
	if dir.ends_with("/") or dir.ends_with("\\"):
		return dir + filename
	return dir + "/" + filename


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
	mode_label.text = _t("mode")
	_update_mode_options()
	run_button.text = _t("run_button")
	stop_button.text = _t("stop_button")
	save_dir_label.text = _t("save_dir")
	save_dir_edit.placeholder_text = _t("save_dir_placeholder")
	save_dir_button.text = _t("browse_button")
	filename_label.text = _t("filename")
	index_label.text = _t("index")
	auto_increment_check.text = _t("auto_increment")
	placeholder_hint.text = _t("placeholder_hint")
	replay_saved_button.text = _t("replay_saved_button")
	save_dir_dialog.title = _t("save_dir_dialog_title")


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
		"mode": "模式",
		"mode_http_mp3": "HTTP MP3 试听",
		"mode_uni_ws_pcm": "单向 WS PCM",
		"mode_bidi_ws_chunks": "双向 WS 分段",
		"mode_save_mp3": "保存音频到本地",
		"run_button": "运行",
		"stop_button": "停止",
		"save_dir": "目录",
		"save_dir_placeholder": "选择用于保存 MP3 的本地目录",
		"browse_button": "选择",
		"filename": "文件名",
		"index": "Index",
		"auto_increment": "保存成功后自增",
		"placeholder_hint": "文件名占位符：{voice} 音色，{model} 模型，{resource} 资源，{index} 当前序号。示例：{voice}_{model}_{index}.mp3",
		"replay_saved_button": "试听上次音频",
		"save_dir_dialog_title": "选择保存目录",
		"status_ready": "就绪。粘贴 API Key，保留或修改音色，然后选择一条合成路径。",
		"status_api_key_required": "需要填写 API Key。",
		"status_voice_required": "需要填写 voice_type。",
		"status_text_required": "需要填写测试文本。",
		"status_save_dir_required": "保存模式需要选择本地目录。",
		"status_save_dir_invalid": "保存目录不存在或不可访问。",
		"status_filename_required": "保存模式需要填写文件名模板。",
		"status_http_waiting": "HTTP 合成：等待完整 MP3 响应...",
		"status_http_failed": "HTTP 合成失败。请查看输出面板里的 TTS-HTTP 警告。",
		"status_http_ok": "HTTP 合成成功：%d 字节，请求耗时 %.1f 秒。正在播放 MP3。",
		"status_save_waiting": "保存模式：正在生成完整 MP3...",
		"status_save_failed": "保存模式生成失败。请查看输出面板里的 TTS-HTTP 警告。",
		"status_save_open_failed": "无法打开目标文件，错误码=%d。",
		"status_save_ok": "已保存到 %s（%d 字节，%.1f 秒）。正在试听 MP3。",
		"status_replay_saved": "正在重新试听上次保存成功的音频。",
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
		"mode": "Mode",
		"mode_http_mp3": "HTTP MP3 Preview",
		"mode_uni_ws_pcm": "Uni WS PCM",
		"mode_bidi_ws_chunks": "Bidi WS Chunks",
		"mode_save_mp3": "Save Audio Locally",
		"run_button": "Run",
		"stop_button": "Stop",
		"save_dir": "Directory",
		"save_dir_placeholder": "Choose a local directory for MP3 files",
		"browse_button": "Browse",
		"filename": "Filename",
		"index": "Index",
		"auto_increment": "Auto increment after save",
		"placeholder_hint": "Filename placeholders: {voice} voice type, {model} model, {resource} resource ID, {index} current index. Example: {voice}_{model}_{index}.mp3",
		"replay_saved_button": "Replay Last Audio",
		"save_dir_dialog_title": "Choose Save Directory",
		"status_ready": "Ready. Paste an API key, keep or change the voice type, then run a synthesis path.",
		"status_api_key_required": "API key is required.",
		"status_voice_required": "Voice type is required.",
		"status_text_required": "Text is required.",
		"status_save_dir_required": "Save mode requires a local directory.",
		"status_save_dir_invalid": "Save directory does not exist or is not accessible.",
		"status_filename_required": "Save mode requires a filename template.",
		"status_http_waiting": "HTTP synthesis: waiting for a complete MP3 response...",
		"status_http_failed": "HTTP synthesis failed. Check the Output panel for TTS-HTTP warnings.",
		"status_http_ok": "HTTP synthesis OK: %d bytes, %.1fs request time. Playing MP3.",
		"status_save_waiting": "Save mode: generating a complete MP3...",
		"status_save_failed": "Save mode failed. Check the Output panel for TTS-HTTP warnings.",
		"status_save_open_failed": "Could not open the target file. error=%d.",
		"status_save_ok": "Saved to %s (%d bytes, %.1fs). Playing MP3 preview.",
		"status_replay_saved": "Replaying the last successfully saved audio.",
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
