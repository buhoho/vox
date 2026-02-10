# Vox（ヴォクス） — macOS ローカル音声入力ツール

> *Vox* — ラテン語で「声」。声をテキストに、テキストを意思に。

Apple Speech Framework（SFSpeechRecognizer）を使ったオンデバイス音声認識 + LLM によるリライトで、高精度・低コストな音声入力環境を構築する。

## コンセプト

```
[マイク] → [Apple SFSpeechRecognizer (on-device)] → [生テキスト] → [LLM リライト (差し替え可能)] → [クリップボード / stdout]
```

- **音声認識**: Apple の SFSpeechRecognizer をオンデバイスで使用（無料、ネットワーク不要）
- **リライト**: LLM で句読点補正・口語→書き言葉変換（バックエンド選択可能）
- **出力**: クリップボードにコピー &/or stdout に出力

### なぜ Whisper ではなく Apple Speech か

| 項目 | Apple SFSpeechRecognizer | Whisper (local) |
|------|-------------------------|-----------------|
| 速度 | 55%高速（Argmax ベンチマーク, M4） | Large-v3 Turbo でも遅い |
| コスト | 無料（OS組み込み） | モデルDL 1.6GB、GPU/CPU負荷大 |
| 日本語 | on-device対応、Siriと同等精度 | 学習データ偏り（英語65%） |
| セットアップ | Xcode + Swift のみ | Python + 依存地獄 or CoreML変換 |
| プライバシー | 完全ローカル処理可能 | ローカル処理可能 |
| バッテリー | 最適化済み（Neural Engine活用） | CPU/GPU 負荷高い |

**注意**: Apple の新しい SpeechAnalyzer API（iOS 26 / macOS Tahoe）はさらに高速だが、2026年2月現在 macOS Sequoia (15.x) ではまだ使えない。SFSpeechRecognizer で十分な精度が出る。macOS Tahoe リリース後に SpeechAnalyzer へ移行可能な設計にしておく。

### リライト LLM バックエンドの選択

リライト部分は**差し替え可能な設計**とする。以下から選択：

| バックエンド | コスト | 備考 |
|-------------|--------|------|
| **Gemini 2.5 Flash-Lite（推奨）** | 無料枠: 15 RPM / 従量: ~月10円 | Google AI Studio で API キー無料発行。リライト用途に最適 |
| **Gemini（Google AI Studio 経由）** | 無料～従量 | Google One AI Premium（月2,900円）とは別。API キーは無料で別途取得 |
| **Claude API (Haiku)** | 従量: ~月50円 | Claude MAX（月$300）とは別契約。Haiku なら安いが Flash-Lite より割高 |
| **ローカル LLM (Ollama等)** | 無料 | M4 MacBook Air で llama3.2 等を動かす。完全オフライン。精度は劣る |
| **リライトなし** | 無料 | `--no-rewrite` で生認識結果をそのまま出力 |

#### ⚠️ サブスクリプション vs API の違い（重要）

| サービス | 契約種別 | プログラムから使えるか |
|----------|----------|----------------------|
| Google One AI Premium (月2,900円) | チャットUI利用権 | ❌ API アクセス不可 |
| Claude MAX (月$300) | チャットUI利用権 | ❌ API アクセス不可 |
| **Google AI Studio API キー** | **API（無料枠あり）** | **✅ プログラムから呼べる** |
| **Anthropic API** | **API（従量課金）** | **✅ プログラムから呼べる** |
| **Ollama (ローカル)** | **自前サーバー** | **✅ プログラムから呼べる** |

**結論**: 既存のサブスクとは別に、Google AI Studio で無料の API キーを発行するのが最もシンプル。クレジットカード登録不要で即座に使える。

### なぜ Gemini Flash-Lite でリライトするか

SFSpeechRecognizer の生出力は口語的で句読点が不完全なことがある。LLMで以下を補正：

- 句読点・改行の適切な挿入
- 口語表現 → 書き言葉への変換（「えーと」「あのー」の除去等）
- 明らかな誤認識の文脈推定による修正
- 技術用語の正規化（例: 「クロード」→「Claude」）

Gemini 2.5 Flash-Lite のコスト: **$0.10 / 1M input tokens, $0.40 / 1M output tokens**
→ 1回の音声入力が平均500トークンとして、1日100回使っても月額約10円以下。

## アーキテクチャ

```
vox/
├── Sources/
│   ├── Vox/
│   │   ├── main.swift              # エントリポイント・CLI引数解析
│   │   ├── SpeechRecognizer.swift   # SFSpeechRecognizer ラッパー
│   │   ├── AudioCapture.swift       # AVAudioEngine マイク入力
│   │   ├── Rewriter.swift           # LLM リライト処理（バックエンド抽象化）
│   │   ├── RewriterBackend/
│   │   │   ├── GeminiBackend.swift  # Gemini Flash-Lite
│   │   │   ├── ClaudeBackend.swift  # Claude API (Haiku)
│   │   │   ├── OllamaBackend.swift  # ローカル LLM
│   │   │   └── NoopBackend.swift    # リライトなし（パススルー）
│   │   ├── ClipboardManager.swift   # pbcopy 連携
│   │   └── Config.swift             # 設定管理
├── Package.swift                    # Swift Package Manager
├── config.example.json              # 設定ファイルテンプレート
├── install.sh                       # インストールスクリプト
└── README.md
```

### Swift Package Manager で構築する理由

- Xcode プロジェクトファイル不要（`swift build` のみ）
- CLI ツールとして `/usr/local/bin/` に配置可能
- 依存関係が最小限（Apple フレームワークのみ + HTTP クライアント）

## 技術仕様

### 1. 音声認識部（SFSpeechRecognizer）

```swift
import Speech
import AVFoundation

// キーポイント:
// - SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")) で日本語指定
// - requiresOnDeviceRecognition = true でオンデバイス強制
// - shouldReportPartialResults = true でリアルタイム途中結果表示
// - AVAudioEngine で PCM 16kHz mono キャプチャ
```

**必要な権限**:
- マイクアクセス（Info.plist: `NSMicrophoneUsageDescription`）
- 音声認識（Info.plist: `NSSpeechRecognitionUsageDescription`）
- CLI ツールの場合: システム環境設定 > プライバシーとセキュリティ > マイク で許可

**制約事項**:
- on-device 認識はデバイスごとに 1000 req/hour（実質無制限）
- 1リクエストあたり最大約1分の音声（長い発話は分割が必要）
- macOS Sequoia (15.x) では SFSpeechRecognizer を使用
- macOS Tahoe (26) 以降は SpeechAnalyzer への移行を検討

### 2. リライト部（Gemini API）

```python
# リライト用プロンプト例（これをシステムプロンプトとして使う）
"""
あなたは音声入力のテキスト修正アシスタントです。
以下のルールに従って入力テキストを修正してください：

1. 句読点（。、）を適切に挿入する
2. フィラー（えーと、あのー、うーん等）を除去する
3. 口語表現を自然な書き言葉に変換する
4. 明らかな誤認識を文脈から推定して修正する
5. 技術用語は正式な表記にする（例: くろーど→Claude, ぱいそん→Python）
6. 原文の意味を変えない
7. 修正後のテキストのみを出力する（説明不要）
"""
```

**API 呼び出し**:

```bash
# Gemini API (Google AI Studio) を使用
# エンドポイント: https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent
# 認証: API キー（環境変数 GEMINI_API_KEY）
```

**Swift での HTTP リクエスト実装**:
- Foundation の `URLSession` を使用（外部依存なし）
- または `swift-openai` 等の軽量クライアント（Gemini は OpenAI 互換エンドポイントあり）

### 3. 出力部

- **クリップボード**: `NSPasteboard` / `pbcopy` でシステムクリップボードに書き込み
- **stdout**: パイプ連携用（`vox | pbcopy` 等）
- **ファイル出力**: オプションで指定パスに追記

## CLI インターフェース

```bash
# 基本使用（マイクから録音 → 認識 → リライト → クリップボード）
vox

# 日本語モード（デフォルト）
vox --lang ja-JP

# 英語モード
vox --lang en-US

# リライトなし（生の認識結果のみ）
vox --no-rewrite

# リライトバックエンド指定
vox --backend gemini     # Gemini Flash-Lite（デフォルト）
vox --backend claude     # Claude API (Haiku)
vox --backend ollama     # ローカル LLM
vox --backend none       # = --no-rewrite

# stdout 出力（クリップボードにコピーしない）
vox --stdout

# 録音時間指定（秒）
vox --duration 30

# Push-to-talk モード（Enterキーで開始/停止）
vox --ptt

# 継続モード（停止するまで繰り返し認識）
vox --continuous

# カスタム用語辞書指定
vox --vocab ./my_vocab.json

# デバッグモード（生認識結果とリライト結果を両方表示）
vox --debug
```

## 設定ファイル

```json
// ~/.config/vox/config.json
{
  "language": "ja-JP",
  "on_device_only": true,
  "rewriter": {
    "backend": "gemini",
    "gemini": {
      "api_key_env": "GEMINI_API_KEY",
      "model": "gemini-2.5-flash-lite",
      "endpoint": "https://generativelanguage.googleapis.com/v1beta"
    },
    "claude": {
      "api_key_env": "ANTHROPIC_API_KEY",
      "model": "claude-haiku-4-5-20251001"
    },
    "ollama": {
      "endpoint": "http://localhost:11434",
      "model": "llama3.2"
    },
    "system_prompt_path": "~/.config/vox/rewrite_prompt.txt",
    "max_tokens": 2048
  },
  "output": {
    "clipboard": true,
    "stdout": false,
    "file": null
  },
  "recognition": {
    "partial_results": true,
    "duration_limit": 60,
    "silence_timeout": 3.0
  },
  "vocabulary": {
    "custom_terms": {
      "くろーど": "Claude",
      "じぇみない": "Gemini",
      "ぱいそん": "Python",
      "すうぃふと": "Swift",
      "あーちりなっくす": "Arch Linux",
      "きーぱす": "KeePassXC",
      "てざりんぐ": "テザリング",
      "ぶるーすかい": "Bluesky"
    }
  }
}
```

## セットアップ手順

### 前提条件

- macOS 14.0 (Sonoma) 以上（推奨: macOS 15.x Sequoia）
- Xcode Command Line Tools（`xcode-select --install`）
- Gemini API キー（[Google AI Studio](https://aistudio.google.com/apikey) で無料取得）

### インストール

```bash
# 1. リポジトリクローン
git clone <repo-url>
cd vox

# 2. ビルド
swift build -c release

# 3. バイナリをパスに配置
cp .build/release/vox /usr/local/bin/

# 4. 設定ファイル作成
mkdir -p ~/.config/vox
cp config.example.json ~/.config/vox/config.json

# 5. Gemini API キー設定
export GEMINI_API_KEY="your-api-key-here"
# ~/.zshrc に追記推奨

# 6. マイク権限の付与
# 初回実行時にシステムダイアログが出る
# または: システム環境設定 > プライバシーとセキュリティ > マイク で手動許可

# 7. 音声認識の有効化
# システム環境設定 > キーボード > 音声入力 を有効にする（Siri不要）
# これにより SFSpeechRecognizer の on-device モデルがダウンロードされる
```

### 権限周りの注意点（CLI ツール特有）

macOS の CLI ツールで SFSpeechRecognizer を使う場合、以下が必要:

1. **Code Signing**: `codesign --force --sign - .build/release/vox`
2. **TCC (Transparency, Consent, and Control)**: 初回実行でマイク・音声認識のダイアログが出る
3. **Info.plist の埋め込み**: Swift Package で CLI ツールにする場合、Info.plist を別途配置するか、`--info-plist-path` でビルド時に指定
4. **Entitlements**: サンドボックス外で実行するため、`com.apple.security.device.audio-input` は不要（非サンドボックス）

## 参考実装・リファレンス

### Apple 公式ドキュメント

- [Speech Framework](https://developer.apple.com/documentation/speech)
- [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [Recognizing Speech in Live Audio](https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio)
- [WWDC25: SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) — 将来の移行先

### 既存の CLI 実装（参考）

- [sveinbjornt/hear](https://github.com/sveinbjornt/hear) — macOS CLI 音声認識ツール（SFSpeechRecognizer ベース、592★）
  - Objective-C 実装。構造の参考になる
  - ライブ音声 & ファイル入力対応
  - 言語指定、on-device モードサポート

- [dtinth/transcribe](https://github.com/dtinth/transcribe) — SFSpeechRecognizer の最小 CLI 実装
  - stdin から PCM 16-bit 16kHz mono を受け取る
  - JSON 出力
  - 言語指定、on-device モード対応
  - `TRANSCRIBE_ON_DEVICE_ONLY=1` 環境変数

### Gemini API

- [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
  - Flash-Lite: $0.10 / 1M input tokens, $0.40 / 1M output tokens
  - 無料枠: 15 RPM（テスト用に十分）
- [Gemini API Quickstart](https://ai.google.dev/gemini-api/docs/quickstart)
- [Google AI Studio - API Key 発行](https://aistudio.google.com/apikey)

### Apple Speech vs Whisper ベンチマーク

- [Argmax: Apple SpeechAnalyzer and WhisperKit 比較](https://www.argmaxinc.com/blog/apple-and-argmax)
  - Apple は mid-tier Whisper モデルと同等精度
  - M4 Mac mini でベンチマーク済み
- [MacRumors: Apple API 55% faster than Whisper](https://www.macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper/)
  - 34分動画: Apple 45秒 vs Whisper 101秒

### その他ツール（比較用）

- [WhisperKit (argmaxinc)](https://github.com/argmaxinc/WhisperKit) — Apple Silicon 最適化 Whisper
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) — GUI アプリ（有料）
- [Voibe](https://www.getvoibe.com/) — Push-to-talk 型（有料）

## 発展的な機能（Phase 2）

### グローバルホットキー

```
Option + Space（or カスタム） → 録音開始
もう一度押す → 録音停止 → 認識 → リライト → クリップボード → 自動ペースト
```

実装: `CGEvent` / `NSEvent.addGlobalMonitorForEvents` を使用

### tmux / ターミナル統合

```bash
# tmux のキーバインドに組み込む例
bind-key v run-shell "vox --stdout | tmux load-buffer - && tmux paste-buffer"
```

### 履歴管理

```bash
# ~/.local/share/vox/history/
# YYYY-MM-DD_HHMMSS_raw.txt  — 生認識結果
# YYYY-MM-DD_HHMMSS_rewritten.txt — リライト後
```

### カスタムリライトプロンプト

用途に応じてプロンプトを切り替え可能:

```bash
vox --prompt coding    # コード関連用語重視
vox --prompt casual    # カジュアルな文体維持
vox --prompt formal    # ビジネス文書向け
vox --prompt tweet     # SNS投稿用（短縮）
```

## 実装時の注意点

### SFSpeechRecognizer の罠

1. **RunLoop 必要**: CLI ツールでは `RunLoop.main.run()` を明示的に呼ばないとコールバックが来ない
2. **権限ダイアログ**: 初回実行時に出る。CI/CD では事前に `tccutil` で許可が必要
3. **on-device モデルの事前DL**: 「キーボード > 音声入力」を有効にしておくとモデルが事前DLされる
4. **1分制限**: 長い発話は VAD（Voice Activity Detection）で区切って複数リクエストに分割
5. **locale 指定必須**: デフォルトはシステム言語。明示的に `Locale(identifier: "ja-JP")` を指定すること

### Gemini API の罠

1. **レートリミット**: 無料枠は 15 RPM。連続使用時は適切なバックオフ
2. **レスポンス形式**: `candidates[0].content.parts[0].text` でテキスト取得
3. **空レスポンス対策**: たまに空が返る。リトライロジック必須
4. **APIキー管理**: 環境変数 or Keychain。設定ファイルに直書き厳禁

### ビルド・配布

1. **Universal Binary**: `swift build -c release --arch arm64 --arch x86_64`（Intel Mac 対応する場合）
2. **Code Signing**: Ad-hoc 署名で十分: `codesign --force --sign - <binary>`
3. **Notarization**: 配布する場合は Apple Developer ID が必要（個人利用なら不要）

## ライセンス

MIT

## 謝辞

- ノウチ (@ouchi) さんのツイートからインスピレーション
- [sveinbjornt/hear](https://github.com/sveinbjornt/hear) — CLI 設計の参考
- [dtinth/transcribe](https://github.com/dtinth/transcribe) — 最小実装の参考
