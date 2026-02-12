# VOX プロジェクト

macOS ローカル音声入力CLIツール。Apple SFSpeechRecognizer（on-device）+ LLM リライト。

## 技術スタック

- Swift 5.10+ / Swift Package Manager
- macOS 14.0+ (Sonoma)
- SFSpeechRecognizer（on-device 音声認識）
- Gemini 2.5 Flash-Lite（リライトLLM、差し替え可能）

## ビルド・テスト

```
make check               # コミット前チェック（テスト + リリースビルド）。コード変更後は必ず実行
make test                # テスト実行
make build               # デバッグビルド
make release             # リリースビルド
make install             # リリースバイナリを ~/.local/bin にインストール
```

**重要**: コードを変更したら、コミット前に必ず `make check` を実行すること。
`make check` は `swift test` と `swift build -c release` を両方実行する。
リリースバイナリを使用しているため、リリースビルドの確認を省略してはならない。

## ディレクトリ構造

```
Sources/
├── VoxLib/              # ライブラリターゲット（ロジック全体）
│   ├── SpeechRecognizer.swift
│   ├── AudioCapture.swift
│   ├── Rewriter.swift
│   ├── RewriterBackend/
│   ├── ClipboardManager.swift
│   └── Config.swift
└── Vox/
    └── Vox.swift        # CLIエントリポイント（VoxLib に依存）

Tests/VoxLibTests/       # テスト（VoxLib をテスト）
```

## 設計原則

迷ったらこちら側に倒す:

- **イミュータブル優先**: struct・let を使う。var・class は理由がある場合のみ
- **冪等性**: 同じ入力に対して同じ出力。何度実行しても同じ結果になること
- **ステートレス**: 状態を持たない設計を優先。状態が必要な場合は局所化し、外部に漏らさない
- **副作用の分離**: 純粋なロジックと副作用（I/O、ネットワーク、クリップボード操作）を分離する。protocol で抽象化し、テスト時にモック可能にする

## チームメイト向けルール

- 自分の担当ファイル以外を勝手に変更しない
- コミット前に `make check` を実行し、テストとリリースビルドの両方が通ることを確認
- public API を変更する場合はリードに確認
