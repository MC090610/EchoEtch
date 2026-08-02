# 《聲畫合鳴》Echo & Etch — Demo 使用说明

## 快速启动

### macOS / Linux
```bash
cd /Users/monica/Documents/Echo\ Etch/demo
chmod +x start.sh
./start.sh
```

### Windows
```cmd
cd Documents\Echo Etch\demo\backend
pip install -r requirements.txt
python app.py
```

### 或者直接运行
```bash
cd /Users/monica/Documents/Echo Etch/demo/backend
pip install -r requirements.txt
python app.py
```

## 访问地址

打开浏览器访问：**http://localhost:8721**

（手机访问：把 `localhost` 换成你电脑的局域网IP，比如 `http://192.168.x.x:8721`）

---

## 配置 API Key（可选）

后端默认走 **Demo 模式**，不需要 API Key，会返回预设回声。

如需真实 AI 生成，在 `backend/app.py` 顶部设置环境变量：

```bash
# OpenAI
export OPENAI_API_KEY="sk-xxxx"
export OPENAI_BASE_URL="https://api.openai.com/v1"

# 或硅基流动（国内）
export OPENAI_API_KEY="sk-xxxx"
export OPENAI_BASE_URL="https://api.siliconflow.cn/v1"
export OPENAI_MODEL="deepseek-ai/DeepSeek-V2.5"
```

## 功能说明

| 功能 | 状态 | 说明 |
|------|------|------|
| 今日主题 | ✅ | 每天自动更新 |
| 文字输入 | ✅ | 核心输入方式 |
| 拍照上传 | ⚠️ | Demo阶段仅标记，不处理图片 |
| 语音输入 | ⚠️ | Demo阶段录音不转文字 |
| AI叙事生成 | ✅ | 配置API后真实生成，否则走预设 |
| TTS音频 | ✅ | edge-tts 实时生成，无需额外配置 |
| 回声卡片 | ✅ | 展示 + 播放 |
| 回声日记 | ✅ | 日历 + 列表 |
| 每日推送 | ❌ | 待接入微信小程序 |

---

## 技术说明

- **后端**：Python Flask，单文件，无数据库（JSON文件存储）
- **前端**：纯HTML/CSS/JS，移动端优先
- **TTS**：edge-tts（微软Edge同款语音，完全免费）
- **AI生成**：需配置 OpenAI API 或国内模型 API

## 目录结构

```
demo/
├── backend/
│   ├── app.py          # 后端主程序
│   └── requirements.txt
├── frontend/
│   └── index.html      # 前端页面
├── data/               # 自动创建，存放音频和日记数据
│   ├── audio/          # TTS生成的音频文件
│   └── diary.json      # 回声日记
└── start.sh            # 启动脚本
```

## 下一步

1. 配置 API Key，跑通真实 AI 生成
2. 用真实素材（手写笔记、涂鸦照片）测试完整流程
3. 迭代 Prompt，优化回声质量
4. 接入微信小程序，实现每日推送
