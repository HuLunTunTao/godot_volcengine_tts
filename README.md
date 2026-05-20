<div align="right">
  [<a href="./README.md">简体中文</a>] [<a href="./README.en.md">English</a>]
</div>

<div align="center">
  <img src="./docs/images/icon-256.png" alt="Godot Volcengine TTS logo" height="96">
  <h1>Godot Volcengine TTS</h1>
  <p>在 Godot 4.4+ 中直接流式播放、生成和预保存火山引擎豆包 TTS 音频</p>
</div>


Godot Volcengine TTS 是一个面向 Godot 4.4+ 的第三方火山引擎语音合成大模型 SDK，封装了火山引擎语音合成大模型的公开 API。

本项目用于在游戏和交互项目中接入火山引擎豆包语音合成。它提供**高度封装的、使用简便**的播放节点，也保留了双向 WebSocket、单向流式和 HTTP 合成三个底层 Client。既可以用于实时角色对白、LLM 生成语音，也可以用于 UI 提示音、过场动画和固定台词缓存。

本项目的测试场景也提供将合成语音保存到本地的模式。开发者只需将项目 clone 到本地并使用 Godot 引擎打开，即可直接测试接口，并为游戏预生成语音，从而减少运行期重复合成带来的成本开销。

该项目最初是一个战棋游戏的副产品，被用于在该游戏中实时合成由 LLM 实时生成的文本。

## 建议

> 由于实时合成文本的成本较高，建议实际游戏项目中只对少量动态生成的文本采用实时合成，例如由 LLM 动态生成的角色台词；对于剧情对白、UI 文案、旁白等静态文本，建议在游戏开发阶段预合成并缓存。

插件详细文档：

- [中文插件文档](addons/godot_volcengine_tts/README.md)
- [英文插件文档](addons/godot_volcengine_tts/README.en.md)

详细文档有意放在 `addons/godot_volcengine_tts/` 目录内。Asset Library 导出包只包含
`addons/` 目录，因此用户通过插件包安装后仍能拿到使用说明和协议细节。文档和脚本放在一起，
也方便 Coding Agent、IDE 助手或维护者在阅读插件源码时直接发现相关上下文。

## 功能

该插件封装了火山引擎官方提供的三个端点：

- `wss://openspeech.bytedance.com/api/v3/tts/bidirection`
- `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream`
- `https://openspeech.bytedance.com/api/v3/tts/unidirectional`

并提供了以下三种底层封装：

- `VolcengineTTSBidirectionalClient`
- `VolcengineTTSUnidirectionalClient`
- `VolcengineTTSHttpClient`

和以下几种高层封装：

- `speak() `单向流式播放
- `speak_ssml() `使用SSML的单向流式播放
- `start_streaming()` 双向流式播放，适用于流式获取 LLM 的输出并流式合成音频的使用场景
- `fetch_audio()` 一次性获取完整音频

## 安装

**通过Godot资源库（Godot Asset Library）安装**

本插件已经上传到 Godot Asset Library ，地址如下：

```
https://godotengine.org/asset-library/asset/5153
```

您可以直接打开 Godot 引擎，并在资源库搜索`Godot Volcengine TTS`来安装本插件，

然后在 **项目设置 > 插件** 启用 **Godot Volcengine TTS**。

> 注意：
>
> - 由于 Godot Asset Library 审核原因，因此其版本可能会滞后于Github仓库，请在安装时留意
>
> - Asset Library 下载包通过 `.gitattributes` 限制为只包含 `addons/`，因此测试场景、截图和仓库文档不会污染用户项目。

**通过Github仓库安装**：

1. 克隆仓库到本地
2. 复制插件目录到你的项目：

```text
addons/godot_volcengine_tts/
```

然后在 **项目设置 > 插件** 启用 **Godot Volcengine TTS**。

## 简短示例

## 初始化voice节点

```gdscript
# 初始化节点
var voice := VolcengineStreamingVoicePlayer.new()

# 配置参数
voice.api_key = "your-volcengine-api-key"
voice.resource_id = "seed-tts-2.0"
voice.user_uid = "player-or-device-id"
voice.default_model = "seed-tts-2.0-expressive"

# 添加到场景
add_child(voice)
```

### 单向流式播放

```gdscript
await voice.speak("你好，Godot。", "zh_male_dayi_uranus_bigtts") # 普通的单向流式播放

await voice.speak_ssml("<speak>你好，Godot。</speak>", "zh_male_dayi_uranus_bigtts") # 使用SSML的单向流式播放
```

### 双向流式播放

```gdscript
await voice.start_streaming("zh_male_dayi_uranus_bigtts")

# ... 等待文本

voice.feed_text(chunk_0) # 获得第0段文本，并传输给TTS服务

# ... 等待文本

voice.feed_text(chunk_1)  # 获得第1段文本，并传输给TTS服务

# ... 等待文本

voice.feed_text(chunk_2)  # 获得第2段文本，并传输给TTS服务

voice.finish_streaming()
await voice.speak_finished
```

### 预生成 MP3

```gdscript
var mp3 := await voice.fetch_audio("欢迎回来，主公。", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})

var file := FileAccess.open("user://welcome.mp3", FileAccess.WRITE)
file.store_buffer(mp3)
```

## 测试场景

仓库包含本地测试场景 `scenes/test/tts_test.tscn`，您可以将仓库clone到本地并使用Godot引擎打开来使用。

它是一个中英文双语验证界面，可以输入火山引擎 API Key、resource ID、model、voice type、sample rate 和测试文本，并验证单向流式、双向流式、一次获取完整音频和停止行为。

![Volcengine TTS 测试场景，展示 API、模型、音色、文本、HTTP、单向流式、双向流式和停止控制](docs/images/screenshot_0.png)

>  **注意：为了方便开发者使用火山引擎“预制”游戏音频，该测试场景中提供了将音频保存到本地的功能。**

可将 HTTP 合成得到的音频直接保存到指定目录。保存界面支持选择输出目录、配置文件名模板、设置当前索引，并可在每次保存后自动递增索引，适合在开发阶段批量预生成固定台词音频。

![Volcengine TTS 测试场景的本地保存模式，展示保存目录、文件名模板、索引和自动递增选项](docs/images/screenshot_1.png)

测试场景不会进入 Asset Library 下载包。

## 音色

火山引擎会持续更新可用音色。选择 `voice_type` 前请查看官方音色列表：

- https://www.volcengine.com/docs/6561/1257544

## 合规与服务说明

本项目是基于火山引擎公开接口文档实现的第三方非官方 Godot 集成，不隶属于字节跳动、火山引擎或豆包，也未获得其官方背书或赞助。

使用者需要自行提供火山引擎 API 凭证，并自行遵守相关服务条款、计费规则、调用限制、隐私要求和内容合规要求。

本文档中提到的产品名、服务名和商标归各自权利人所有。

有用的官方参考：

- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1598757
- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1719100
- 火山引擎 TTS 接口文档：https://www.volcengine.com/docs/6561/1329505
- 火山引擎 SDK 合规 / 隐私相关文档：https://www.volcengine.com/docs/6561/116711
- 火山引擎服务条款：https://www.volcengine.com/docs/6256/64903

## 许可证

MIT。详见 `LICENSE`。
