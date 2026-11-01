#!/bin/bash
#
# 把录屏/成片转成 GIF，走两趟调色板，质量比一把梭好得多。
#
#   ./mov2gif.sh prototype.mov               → prototype.gif（原生宽度，30fps）
#   ./mov2gif.sh prototype.mov 20            → 20fps
#   ./mov2gif.sh prototype.mov 30 600        → 30fps，缩到宽 600
#   ./mov2gif.sh prototype.mov 30 600 out.gif
#
#   FROM=2.3 LEN=4.0 ./mov2gif.sh main.mp4   → 只截 2.3s 起的 4 秒
#
# ── 为什么要两趟 ────────────────────────────────────────────────
#
# GIF 每帧最多 256 色。直接 `ffmpeg -i in.mov out.gif` 会用一张固定的通用调色板，
# 于是渐变背景糊成一团色块。两趟的做法是：第一趟 palettegen 扫完整条片子、按这
# 条片子实际用到的颜色算出一张专属调色板，第二趟 paletteuse 拿它来映射。
#
# `stats_mode=diff` 让调色板偏向「帧间变化的区域」而不是整幅画面的平均——动的
# 地方才是眼睛盯着的地方，静止的背景少分几个色位无所谓。
#
# `dither=bayer` 而不是默认的误差扩散（floyd_steinberg）：误差扩散在单张静态图
# 上更好看，但逐帧独立计算，于是相邻两帧的噪点图案完全不同，连起来看整片平坦
# 区域都在「沸腾」。bayer 用固定的有序矩阵，图案在帧间稳定，动态下干净得多。
# `bayer_scale` 越小图案越细越密，3 是画质和体积的折中。
#
# ── 体积怎么估 ──────────────────────────────────────────────────
#
# 大致随「像素数 × 帧数」走。实测这个项目的素材：600px/20fps 大约 48 KB/帧。
# 所以宽度减半 ≈ 体积降到 1/4，是比降帧率有效得多的杠杆。
#
# ⚠️ GIF 很贵。1024×1024/60fps 的 24MB mp4，转成 600px/20fps 的 GIF 要 13MB——
# 四分之一的像素、三分之一的帧率，体积只省了一半。要放进 git 仓库的话先想清楚，
# 它会永久留在历史里。超过 10MB 建议走 Release 附件或者干脆只放封面图加链接。

set -euo pipefail

INPUT="${1:?用法: ./mov2gif.sh <输入文件> [fps] [宽度] [输出文件]}"
FPS="${2:-30}"
WIDTH="${3:-0}"            # 0 = 保持原生宽度
OUTPUT="${4:-${INPUT%.*}.gif}"

FROM="${FROM:-}"           # 起始秒数，空 = 从头
LEN="${LEN:-}"             # 截取长度，空 = 到结尾

command -v ffmpeg >/dev/null || { echo "没装 ffmpeg"; exit 1; }
[ -f "$INPUT" ] || { echo "文件不存在: $INPUT"; exit 1; }

# -ss 放在 -i 前面是输入端定位：先跳到最近的关键帧再解码到精确点，
# 比放在后面从头解码快得多，而且 accurate_seek 默认开着，仍然是帧准的。
# macOS 自带 bash 3.2：set -u 下空数组展开会报 unbound variable，
# 所以统一用 ${TRIM[@]+"${TRIM[@]}"} 这种安全展开。
TRIM=()
[ -n "$FROM" ] && TRIM+=(-ss "$FROM")
[ -n "$LEN" ]  && TRIM+=(-t "$LEN")
SAFE_TRIM=(${TRIM[@]+"${TRIM[@]}"})

if [ "$WIDTH" = "0" ]; then
    SCALE="scale=iw:-1:flags=lanczos"
else
    SCALE="scale=${WIDTH}:-1:flags=lanczos"
fi
CHAIN="fps=${FPS},${SCALE}"

PALETTE="$(mktemp -t mov2gif).png"
trap 'rm -f "$PALETTE"' EXIT

echo "═══ 源 ═══"
ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,nb_frames \
    -show_entries format=duration -of default=nw=1 "$INPUT" | sed 's/^/  /'

echo "═══ 第一趟：生成专属调色板 ═══"
ffmpeg -v error -y ${SAFE_TRIM[@]+"${SAFE_TRIM[@]}"} -i "$INPUT" \
    -vf "${CHAIN},palettegen=stats_mode=diff" "$PALETTE"

echo "═══ 第二趟：映射并编码 ═══"
ffmpeg -v error -stats -y ${SAFE_TRIM[@]+"${SAFE_TRIM[@]}"} -i "$INPUT" -i "$PALETTE" \
    -lavfi "${CHAIN}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUTPUT"

echo "═══ 结果 ═══"
FRAMES=$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of csv=p=0 "$OUTPUT" 2>/dev/null || echo "?")
DIMS=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0:s=x "$OUTPUT" 2>/dev/null || echo "?")
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "  ${DIMS}  ${FPS}fps  ${FRAMES} 帧  ${SIZE}  →  $OUTPUT"
