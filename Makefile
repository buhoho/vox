.PHONY: test build release check install

# デバッグビルド
build:
	swift build

# リリースビルド
release:
	swift build -c release

# テスト実行
test:
	swift test

# コミット前チェック（テスト + リリースビルド）
# コード変更後は必ずこれを実行すること
check: test release

# リリースバイナリを ~/.local/bin にインストール
install: release
	mkdir -p ~/.local/bin
	cp .build/release/vox ~/.local/bin/vox
