#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
RESULTS="$PROJECT_ROOT/验证结果/$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$RESULTS"
if ! xcodebuild -version > "$RESULTS/Xcode版本.txt" 2>&1; then
  echo "请先安装完整 Xcode，并在 Xcode 设置中选择 Command Line Tools。"
  exit 1
fi
python3 "$PROJECT_ROOT/工具/生成工程.py" > "$RESULTS/工程引用检查.json"
swift test --package-path "$PROJECT_ROOT" 2>&1 | tee "$RESULTS/核心测试.log"
xcodebuild -project "$PROJECT_ROOT/菠萝单词.xcodeproj" -scheme '菠萝单词' \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$RESULTS/DerivedData" CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$RESULTS/模拟器编译.log"
xcrun simctl list devices available -j > "$RESULTS/可用模拟器.json"
for DEVICE in iPad iPhone; do
  DEVICE_ID="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); a=[x for k,vs in d["devices"].items() if ".iOS-" in k for x in vs if x.get("isAvailable") and sys.argv[2] in x["name"]]; print(a[0]["udid"] if a else "")' "$RESULTS/可用模拟器.json" "$DEVICE")"
  if [ -z "$DEVICE_ID" ]; then
    echo "没有可用的 $DEVICE 模拟器，请在 Xcode 下载 iOS Simulator Runtime 并创建对应设备。"
    exit 1
  fi
  xcodebuild -project "$PROJECT_ROOT/菠萝单词.xcodeproj" -scheme '菠萝单词' \
    -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -derivedDataPath "$RESULTS/DerivedData" -resultBundlePath "$RESULTS/$DEVICE.xcresult" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$RESULTS/$DEVICE测试.log"
done
echo "编译与自动测试完成。结果在：$RESULTS"
echo "请继续执行《测试与验收.md》中的真机、英音、分屏和迁移验收。"
