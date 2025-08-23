#!/usr/bin/env bash
# install.sh — Mirzabot → TetraPay edits and file replacements
# - Backs up originals safely
# - Edits text.php (block + brand renames)
# - Replaces aqayepardakht.php & back.php from GitHub raw
# - UTF-8 safe; multi-line aware
set -Eeuo pipefail

trap 'echo "❌ خطا در خط ${LINENO}. اجرای اسکریپت متوقف شد." >&2' ERR

# ------------------------- Config (change if needed) -------------------------
TEXT_FILE="${TEXT_FILE:-/var/www/html/mirzabotconfig/text.php}"
AQAYE_DIR="${AQAYE_DIR:-/var/www/html/mirzabotconfig/payment/aqayepardakht}"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

# Default source (can be overridden with --src=...)
DEFAULT_SRC="https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files"
SRC_BASE="${SRC_BASE:-$DEFAULT_SRC}"

# ------------------------- Args -------------------------
for arg in "$@"; do
  case "$arg" in
    --src=*) SRC_BASE="${arg#--src=}" ;;
    --text=*) TEXT_FILE="${arg#--text=}" ;;
    --dir=*)  AQAYE_DIR="${arg#--dir=}"
              AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
              AQAYE_BACK="${AQAYE_DIR}/back.php"
              ;;
    *) echo "⚠️  پارامتر ناشناخته: $arg" ;;
  esac
done

# ------------------------- Checks -------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ لطفاً با sudo/روت اجرا کنید." >&2
  exit 1
fi
if [[ -z "${TEXT_FILE:-}" || ! -f "$TEXT_FILE" ]]; then
  echo "❌ فایل پیدا نشد: ${TEXT_FILE:-<unset>}" >&2
  exit 1
fi

mkdir -p "$AQAYE_DIR"

# ------------------------- Helpers -------------------------
ts() { date +"%Y%m%d-%H%M%S"; }

backup_file() {
  local f="${1:-}"
  if [[ -z "$f" || ! -e "$f" ]]; then
    echo "⚠️  backup_file: مسیر معتبر نیست: ${f:-<unset>}" >&2
    return 1
  fi
  local b="${f}.bak.$(ts)"
  cp -a -- "$f" "$b"
  echo "🗂️  بکاپ گرفت: $b"
}

inplace_perl() {
  local expr="${1:-}"
  local tgt="${2:-}"
  if [[ -z "$expr" || -z "$tgt" || ! -f "$tgt" ]]; then
    echo "⚠️  inplace_perl: ورودی نامعتبر یا فایل وجود ندارد: ${tgt:-<unset>}" >&2
    return 1
  fi
  perl -CSDA -0777 -i -pe "$expr" "$tgt"
}

# ------------------------- Backups -------------------------
echo "==> گرفتن بکاپ‌ها…"
backup_file "$TEXT_FILE" || true
[[ -f "$AQAYE_MAIN" ]] && backup_file "$AQAYE_MAIN" || true
[[ -f "$AQAYE_BACK" ]] && backup_file "$AQAYE_BACK" || true

# ------------------------- New block content -------------------------
NEW_BLOCK=$(cat <<'PHPNEW'
$textbotlang['users']['moeny']['aqayepardakht'] = "
✅ فاکتور پرداخت ایجاد شد.
        
🔢 شماره فاکتور : %s
💰 مبلغ فاکتور : %s تومان
    
⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید

⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد";
PHPNEW
)

# ------------------------- Step 1: Replace the whole aqayepardakht string value -------------------------
echo "==> اصلاح بلوک aqayepardakht در text.php …"
# First pass: replace the value with a token to avoid escaping hell
inplace_perl '
  s/
    (\$textbotlang\[\x27users\x27\]\[\x27moeny\x27\]\[\x27aqayepardakht\x27\]\s*=\s*)
    "
    (?:
      \\"|[^"]
    )*?
    ";
  /$1"__REPL__";/gsx
' "$TEXT_FILE"

# Second pass: inject our exact multi-line content
# Escape for Perl string literal
ESCAPED=$(printf "%s" "$NEW_BLOCK" | perl -CSDA -pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g;')
inplace_perl "s/\"__REPL__\";/\"$ESCAPED\";/s" "$TEXT_FILE"

# ------------------------- Step 2 & 3: Brand renames -------------------------
echo "==> جایگزینی عنوان برند و نام‌ها…"
# Specific emoji-title replacement
inplace_perl 's/🔵\s*آقای پرداخت/💵 تتراپی TetraPay ( هوشمند )/g' "$TEXT_FILE"
# All remaining occurrences
inplace_perl 's/آقای پرداخت/تتراپی/g' "$TEXT_FILE"

# ------------------------- Step 4: Download/replace PHP files -------------------------
echo "==> دانلود و جایگزینی فایل‌های پرداخت از گیت‌هاب…"
TMP_MAIN="$(mktemp)"; TMP_BACK="$(mktemp)"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/aqayepardakht.php" -o "$TMP_MAIN"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/back.php"          -o "$TMP_BACK"

if [[ ! -s "$TMP_MAIN" || ! -s "$TMP_BACK" ]]; then
  echo "❌ دریافت فایل‌ها ناموفق بود. آدرس منبع را بررسی کنید: $SRC_BASE" >&2
  rm -f "$TMP_MAIN" "$TMP_BACK"
  exit 1
fi

install -m 0644 "$TMP_MAIN" "$AQAYE_MAIN"
install -m 0644 "$TMP_BACK" "$AQAYE_BACK"
rm -f "$TMP_MAIN" "$TMP_BACK"

# ------------------------- Finalize -------------------------
(systemctl reload apache2 2>/dev/null || systemctl reload nginx 2>/dev/null || true)

echo "✅ همه‌چیز با موفقیت انجام شد.
- text.php ویرایش شد.
- «🔵 آقای پرداخت» → «💵 تتراپی TetraPay ( هوشمند )»
- همهٔ «آقای پرداخت» → «تتراپی»
- aqayepardakht.php و back.php از گیت‌هاب جایگزین شدند.
"
