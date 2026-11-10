#!/usr/bin/env bash
# 云Mac 重编 TAP1 系实验固件（2026-10 版：导航路况扩展 + 12 项菜单 + 容器探查）。
# 零参数即可跑：自动找 DevEco 的 OHOS LLVM、自动找原厂 rollback ZIP、自动起时间戳输出目录。
# 也可显式指定：
#   bash firmware-research/strix-1.0.4.12/tap1/build-tap1.sh [OHOS_LLVM_BIN] [原厂rollback.zip] [输出目录]
# 只离线构建+审计，不触碰眼镜、不授权刷写。输出目录必须不存在（时间戳默认值保证）。
set -euo pipefail
cd "$(dirname "$0")/../../.."   # 仓库根
REPO_ROOT="$PWD"
TAP1_DIR="$REPO_ROOT/firmware-research/strix-1.0.4.12/tap1"

# ---- 参数解析：0~3 个，全部可省 ----
LLVM_BIN="${1:-${TAP1_LLVM_BIN:-}}"
STOCK="${2:-${TAP1_STOCK_ZIP:-}}"
OUT="${3:-}"

if [ -z "$LLVM_BIN" ]; then
  for d in "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin" \
           /Applications/DevEco-Studio.app/Contents/sdk/*/openharmony/native/llvm/bin; do
    [ -x "$d/clang" ] && LLVM_BIN="$d" && break
  done
  [ -n "$LLVM_BIN" ] || { echo "未找到 OHOS LLVM（clang）。装好 DevEco Studio，或: export TAP1_LLVM_BIN=<llvm/bin 绝对路径>"; exit 1; }
  echo "[自动] LLVM: $LLVM_BIN"
fi
if [ -z "$STOCK" ]; then
  STOCK="$(ls -t "$REPO_ROOT"/*[Rr]ollback*.zip "$HOME/Downloads"/*[Rr]ollback*.zip \
                   "$REPO_ROOT"/*1.0.4.12*.zip "$HOME/Downloads"/*1.0.4.12*.zip 2>/dev/null | head -1 || true)"
  [ -n "$STOCK" ] || { echo "未找到原厂 rollback ZIP（strix 1.0.4.12 Release 附件）。放到仓库根或 ~/Downloads，或: export TAP1_STOCK_ZIP=<zip 路径>"; exit 1; }
  echo "[自动] 原厂 ZIP: $STOCK"
fi
if [ -z "$OUT" ]; then
  OUT="$TAP1_DIR/out/candidate-$(date +%Y%m%d-%H%M%S)"
  echo "[自动] 输出目录: $OUT"
fi
[ -d "$LLVM_BIN" ] || { echo "LLVM bin 目录不存在: $LLVM_BIN"; exit 1; }
[ -f "$STOCK" ] || { echo "原厂 rollback ZIP 不存在: $STOCK"; exit 1; }
[ ! -e "$OUT" ] || { echo "输出目录已存在，换新目录: $OUT"; exit 1; }
export PATH="$LLVM_BIN:$PATH"   # 工具检查前先注入，避免撞上系统 /usr/bin/clang
for t in clang ld.lld llvm-nm llvm-objcopy node; do command -v "$t" >/dev/null || { echo "缺少 ${t}（LLVM_BIN=${LLVM_BIN}）"; exit 1; }; done

# 1) 共享 venv（capstone/unicorn）
SHARED=firmware-research/strix-1.0.4.12
[ -d "$SHARED/.venv" ] || { python3 -m venv "$SHARED/.venv"; "$SHARED/.venv/bin/pip" install -r "$SHARED/requirements.txt"; }

# 2) 复制源快照 + 准备基线 + 放置 PNG
mkdir -p "$OUT"
cp -R "$TAP1_DIR/source/." "$OUT/"
"$SHARED/.venv/bin/python" "$SHARED/src/prepare-baseline.py" "$STOCK" --output "$OUT/firmware-inspection/StrixOS-1.0.4.12"
# TAP1 用 focus 研究树的全量符号表（35062 条，含 libc/tap_fs_* 符号）；
# prepare-baseline 默认装的 metadata/symbols.json 只有 35 条（R3 小表），解析不了 tap_fs_*。
cp "$REPO_ROOT/firmware-research/strix-1.0.4.12/native-navigation/focus/symbols.json" \
   "$OUT/firmware-inspection/StrixOS-1.0.4.12/symbols.json"
PNG_DIR="$OUT/official-addon/build/turbo-photo-png-10412-20260921"
mkdir -p "$PNG_DIR"
cp "$SHARED/assets/turbo-photo-firmware.png" "$PNG_DIR/turbo-photo-gray16-rgba-88x98.png"
# 动画资产：快照不带 405KB 二进制，构建时从 src 树拷入（哈希由构建器钉值校验）
ANIM_DIR="$OUT/official-addon/research/animation-runtime-v1/assets/encoded-v1"
mkdir -p "$ANIM_DIR"
cp "$REPO_ROOT/firmware-research/strix-1.0.4.12/native-navigation/src/official-addon/research/animation-runtime-v1/assets/encoded-v1/anime-idle-192x176-l8.bin" "$ANIM_DIR/"

# 3) 以全运行时组合驱动快照构建器（wide + native-eight + display + navigation + animation + music）
export PATH="$LLVM_BIN:$PATH"
cd "$OUT/official-addon/research"
PYTHONPATH="$PWD:$PWD/music-runtime-v1:$PWD/navigation-runtime-v1" "$REPO_ROOT/$SHARED/.venv/bin/python" - <<'PY'
import importlib.util, json, hashlib
from pathlib import Path
spec = importlib.util.spec_from_file_location("bir", "build-image-rx-candidate.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
import menu10_profile
mod.native_menu = menu10_profile  # nav_* aliases + vm_event wrapper (author's build_candidate.py pattern)
report = mod.build(Path("candidate"), True, True, True, True, True, True)
ap = Path("candidate/payload/nuttx_ap.bin").read_bytes()
print(json.dumps({"candidateAP": hashlib.sha256(ap).hexdigest(), "candidateAPBytes": len(ap), "archive": report["archive"]["name"]}, indent=2))
PY

# 4) 独立字节级审计（REBUILD-2026-10.md 第8条；只读，不授权刷写）
PYTHONPATH="$PWD:$PWD/music-runtime-v1:$PWD/navigation-runtime-v1" "$REPO_ROOT/$SHARED/.venv/bin/python" \
  audit-tap1-candidate.py candidate --out candidate-audit.json

# 4.5) 生成手机端 OTA 候选描述（刷机链路用：dylib 门禁只认这个 JSON 描述的 ZIP）
"$REPO_ROOT/$SHARED/.venv/bin/python" "$TAP1_DIR/make-ota-candidate.py" \
  candidate "$OUT/candidate-ota.json" --code TAP1-2026-10
CAND_JSON="$OUT/candidate-ota.json"

# 5) 刷机三步卡
ZIP_PATH="$(cd candidate && pwd)/$(python3 -c "import json;print(json.load(open('candidate/report.json'))['archive']['name'])")"
cat <<CARD

================= 构建完成 · 刷机三步 =================
① 云Mac 出新 IPA（一条命令，自动嵌入本固件与候选描述）：
   TAP1_FW="$ZIP_PATH" TAP1_CANDIDATE="$CAND_JSON" bash build-local.sh
   → IPA/TurboIO-merged-adhoc.ipa 回 Windows 爱思安装到手机（先装 IPA 顺序红线）
② 眼镜刷: 手机 App 实验刷机页导入 $ZIP_PATH
   （或直接用 ① 产物内嵌候选走官方页流程；电量>50%；手机停掉导航/字幕/音乐/番茄全部会话；刷时贴近静止）
③ 刷后看四样: 菜单12项无滴滴/我的应用 · 模拟导航有路况柱与三类标记 · 开全天智记再进导航 · TCE1仪表盘正常
   异常 → 立刻回滚重刷原版 ZIP，不带病调试
审计: candidate-audit.json 已生成（PASS 才继续②）
======================================================
CARD
