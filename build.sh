#!/usr/bin/env sh
# Build the Electric Loom site into $OUT (default: dist/).
#
# This is the single source of truth for the build: the Nix derivation calls
# this same script, so what CI and the flake produce is what you get locally.
# It needs nothing but a POSIX shell, awk and (optionally) gzip/brotli.
#
#   OUT=dist                 output directory
#   SITE_URL=https://x.tld   absolute base for the social-card tags
#   HEAD_SNIPPET=file        HTML injected just before </head>
#   AD_SNIPPET=file          HTML injected into the sponsored rail
#   BODY_SNIPPET=file        HTML injected at the end of <body>
#   PRECOMPRESS=1            also emit .gz / .br next to each file
#   SINGLE_FILE=1            only write index.html, no extras, no compression
#                            (this is how the committed index.html is made)
#
# The snippets are the only supported way to add third-party code. Leaving
# them unset produces a build that makes no network requests at all.
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-dist}"
SITE_URL="${SITE_URL:-}"
PRECOMPRESS="${PRECOMPRESS:-1}"

mkdir -p "$OUT"

# ---- 1. concatenate the numbered parts ------------------------------------
cat "$SRC/build/p01_head.txt" \
    "$SRC/build/p02_body.txt" \
    "$SRC/build/p03_util.txt" \
    "$SRC/build/p04_shaders.txt" \
    "$SRC/build/p05_flame.txt" \
    "$SRC/build/p06_engine.txt" \
    "$SRC/build/p07_ui.txt" \
    "$SRC/build/p08_gif.txt" \
    "$SRC/build/p09_export.txt" \
    "$SRC/build/p10_boot.txt" > "$OUT/index.html"

# ---- 2. operator injection points -----------------------------------------
# Each marker sits alone on its line; the line is replaced wholesale by the
# contents of the snippet file, or removed if no snippet was given.
inject() {
    marker="$1"
    file="${2:-}"
    if [ -n "$file" ] && [ ! -f "$file" ]; then
        echo "build.sh: snippet file not found: $file" >&2
        exit 1
    fi
    awk -v m="$marker" -v f="$file" '
        index($0, m) {
            if (f != "") { while ((getline line < f) > 0) print line }
            next
        }
        { print }
    ' "$OUT/index.html" > "$OUT/.build.tmp"
    mv "$OUT/.build.tmp" "$OUT/index.html"
}
inject '<!--EL_HEAD-->'     "${HEAD_SNIPPET:-}"
inject '<!--EL_AD_RAIL-->'  "${AD_SNIPPET:-}"
inject '<!--EL_BODY_END-->' "${BODY_SNIPPET:-}"

# ---- 3. absolute URLs for the social cards ---------------------------------
# Unset leaves them relative, which every modern scraper resolves anyway.
SITE_URL="${SITE_URL%/}"
sed "s|__SITE_URL__|${SITE_URL}|g" "$OUT/index.html" > "$OUT/.build.tmp"
mv "$OUT/.build.tmp" "$OUT/index.html"

if [ "${SINGLE_FILE:-0}" = "1" ]; then
    echo "built $OUT/index.html  ($(wc -c < "$OUT/index.html") bytes, single file)"
    exit 0
fi

# ---- 4. static extras ------------------------------------------------------
[ -f "$SRC/patterns.jpg" ] && cp "$SRC/patterns.jpg" "$OUT/"
[ -f "$SRC/motion.jpg" ]   && cp "$SRC/motion.jpg"   "$OUT/"
if [ -f "$SRC/robots.txt" ]; then
    cp "$SRC/robots.txt" "$OUT/"
else
    printf 'User-agent: *\nAllow: /\n' > "$OUT/robots.txt"
fi

# ---- 5. precompress so nginx can serve without spending CPU ---------------
if [ "$PRECOMPRESS" = "1" ]; then
    for f in "$OUT"/index.html "$OUT"/robots.txt; do
        [ -f "$f" ] || continue
        command -v gzip    >/dev/null 2>&1 && gzip -9kf "$f"
        command -v brotli  >/dev/null 2>&1 && brotli -fZ "$f" -o "$f.br"
    done
fi

echo "built $OUT/index.html  ($(wc -c < "$OUT/index.html") bytes)"
