#!/bin/bash

# Change directory to the folder where this script is located
cd "$(dirname "$0")" || exit 1

# Ensure common paths (Homebrew, /usr/local/bin, node, ffmpeg) are available in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

echo "=========================================="
echo "    Starting Wyze Video Stitcher Server   "
echo "=========================================="
echo ""

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ Error: npm is not found in your PATH."
    echo "Please make sure Node.js is installed."
    echo ""
    read -p "Press [Enter] to close..."
    exit 1
fi

# Check if node_modules exists; if not, run npm install
if [ ! -d "node_modules" ]; then
    echo "📦 Dependencies missing. Running npm install..."
    npm install
    if [ $? -ne 0 ]; then
        echo "❌ npm install failed."
        read -p "Press [Enter] to close..."
        exit 1
    fi
fi

# Open the browser automatically after 2 seconds
(
    sleep 2
    open "http://localhost:5173" 2>/dev/null
) &

echo "🌐 Web interface: http://localhost:5173"
echo "🔌 Backend API:   http://localhost:3001"
echo ""
echo "Press Ctrl+C to stop the server anytime."
echo "------------------------------------------"
echo ""

npm run dev
