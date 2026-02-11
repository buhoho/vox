# Vox — macOS ローカル音声入力ツール

macOS 上で動作する CLI ベースの音声入力ツール。音声認識 + LLM リライトで、口語をそのまま書き言葉に変換してクリップボードへ出力する。

## 特徴

- **2つの音声認識エンジン**: Apple SFSpeechRecognizer（ストリーミング）/ WhisperKit（バッチ、ANE/CoreML）
- **LLM リライト**: Gemini API でフィラー除去・句読点補正・技術用語正規化（バックエンド差し替え可能）
- **デーモンモード**: バックグラウンド常駐、fn ダブルタップで録音トグル（Karabiner-Elements 連携）
- **Bluetooth 対応**: A2DP/HFP プロファイル切替を考慮した SE 再生タイミング制御
- **コンテキストキャッシュ**: WhisperKit 使用時、直前の認識結果を次回推論の promptTokens として渡し精度向上

## 動作環境

- macOS 13.0 (Ventura) 以上
- Xcode Command Line Tools（`xcode-select --install`）
- Apple Silicon 推奨（WhisperKit は ANE/CoreML を使用）

## セットアップ

```bash
# クローン & ビルド
git clone https://github.com/<your-username>/vox.git
cd vox
swift build -c release

# バイナリ配置
cp .build/release/vox /usr/local/bin/

# 設定ファイル作成
mkdir -p ~/.config/vox
cp config.example.json ~/.config/vox/config.json
# config.json を環境に合わせて編集

# Gemini API キー（リライト機能を使う場合）
# https://aistudio.google.com/apikey で無料取得
export GEMINI_API_KEY="your-api-key"
# ↑ ~/.zshrc に追記推奨
```

初回実行時にマイク・音声認識の権限ダイアログが表示される。

## 使い方

### インタラクティブモード

```bash
vox
# Enter: 録音開始/停止
# Escape: 録音キャンセル
# Ctrl+C: 終了
```

### デーモンモード（常駐）

```bash
vox --daemon
# SIGUSR1 で録音トグル: kill -USR1 $(cat ~/.config/vox/vox.pid)
# Karabiner-Elements で fn ダブルタップに割り当てると便利（後述）
```

### オプション

```bash
vox --no-rewrite          # リライトなし（生テキスト出力）
vox --engine whisper      # WhisperKit エンジンを使用
vox --lang en-US          # 言語指定
vox --stdout              # 標準出力（クリップボードにコピーしない）
vox --config /path/to.json  # 設定ファイルパス指定
```

## 設定ファイル

`~/.config/vox/config.json`（[config.example.json](config.example.json) を参照）

主要な設定項目:

| キー | 説明 | デフォルト |
|------|------|-----------|
| `language` | 認識言語 | `"ja-JP"` |
| `recognition.engine` | `"system"` or `"whisper"` | `"system"` |
| `recognition.silence_timeout` | 無音タイムアウト（秒、0で無効） | `5.0` |
| `recognition.whisper.model` | WhisperKit モデル名 | `"base"` |
| `rewriter.backend` | `"gemini"` / `"claude"` / `"ollama"` / `"none"` | `"gemini"` |
| `output.clipboard` | クリップボードにコピー | `true` |
| `output.auto_paste` | 自動ペースト（アクセシビリティ権限必要） | `false` |

## Karabiner-Elements 連携（fn ダブルタップ）

デーモンモードと組み合わせて、fn キーのダブルタップで音声入力をトグルできる。

### セットアップ

1. [Karabiner-Elements](https://karabiner-elements.pqrs.org/) をインストール
2. ルールファイルをコピー:

```bash
cp extras/karabiner/vox-fn-double-tap.json \
   ~/.config/karabiner/assets/complex_modifications/
```

3. Karabiner-Elements の設定画面 → Complex Modifications → Add rule → "fn ダブルタップ → SIGUSR1" を有効化

### 仕組み

- fn ダブルタップ（300ms 以内）→ vox デーモンに SIGUSR1 送信 → 録音トグル
- fn + F1〜F12 → macOS 特殊機能キー（明るさ・音量等）を Karabiner 側で直接発行
- fn キーを Karabiner が消費するため、`vox_fn_held` 変数で F-key との組み合わせを追跡

caps_lock → left_option のリマップも含まれている（不要なら karabiner.json から削除）。

## アーキテクチャ

```
Sources/
├── Vox/Vox.swift                    # CLI エントリポイント（daemon + interactive）
└── VoxLib/
    ├── VoxSession.swift             # 3状態オーケストレータ（idle/listening/processing）
    ├── SpeechRecognizer.swift       # SFSpeechRecognizer ラッパー + Protocol
    ├── WhisperRecognizer.swift      # WhisperKit ラッパー（バッチ、ANE/CoreML）
    ├── TranscriptionCache.swift     # コンテキストキャッシュ（WhisperKit 用 promptTokens）
    ├── AudioCapture.swift           # AVAudioEngine マイクキャプチャ
    ├── SoundPlayer.swift            # AVAudioPlayer SE 再生（Bluetooth 対応）
    ├── SilenceDetector.swift        # テキスト変化ベース無音検出
    ├── OutputManager.swift          # クリップボード + auto-paste 出力
    ├── Config.swift                 # JSON 設定（snake_case → camelCase）
    ├── Rewriter.swift               # リライトバックエンド抽象化
    └── RewriterBackend/
        ├── GeminiBackend.swift      # Gemini API
        ├── ClaudeBackend.swift      # Claude API
        ├── OllamaBackend.swift      # ローカル LLM
        └── NoopBackend.swift        # パススルー

Tests/VoxLibTests/                   # ユニットテスト（50テスト）
extras/karabiner/                    # Karabiner-Elements 設定ファイル
```

## テスト

```bash
swift test
```

## ライセンス

MIT
