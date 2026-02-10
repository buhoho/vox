#!/bin/bash
set -euo pipefail

echo "Building vox..."
swift build -c release

echo "Signing binary..."
codesign --force --sign - .build/release/vox

echo "Installing to /usr/local/bin/ (requires sudo)..."
sudo cp .build/release/vox /usr/local/bin/vox

echo "Creating config directory..."
mkdir -p ~/.config/vox

if [ ! -f ~/.config/vox/config.json ]; then
    cp config.example.json ~/.config/vox/config.json
    echo "Config file created at ~/.config/vox/config.json"
else
    echo "Config file already exists, skipping."
fi

echo "Done! Run 'vox --help' to get started."
