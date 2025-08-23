#!/usr/bin/env bash
# install.sh — Mirzabot → TetraPay edits and file replacements (UTF-8 safe)
set -Ee -o pipefail

trap 'echo "❌ خطا در خط ${LINENO}. اجرای اسکریپت متوقف شد." >&2' ERR

# محیط UTF-8 برای جلوگیری از موژی‌بِیک
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ------------------------- Config -------------------------
TEXT_FILE="${TEXT_FILE:-/var/www/html/mirzabotconfig/text.php}"
AQAYE_DIR="${AQAYE_DIR:-/var/www/html/mirzabotconfig/payment/aqayepardakht}"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

DEFAULT_SRC="https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files"
SRC_BASE="${SRC_BASE:-$DEFAULT_SRC}"

# ------------------------- Args -------------------------
for arg in "$@"; do
  case "$arg" in
    --src=*)  SRC_BASE="${arg#--src=}" ;;
    --text=*) TEXT_FILE="${arg#--text=}" ;;
    --dir=*)  AQAYE_DIR="${arg#--dir=}"
              AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
              AQAYE_BACK="${AQAYE_DIR}/back.php" ;;
    *) echo "⚠️  پارامتر ناشناخته: $arg" ;;
  esac
done

# ------------------------- Checks -------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ لطفاً با sudo/روت اجرا کنید." >&2; exit 1
fi
if [ -z "$TEXT_FILE" ] || [ ! -f "$TEXT_FILE" ]; then
  echo "❌ فایل پیدا نشد: ${TEXT_FILE:-<unset>}" >&2; exit 1
fi
mkdir -p "$AQAYE_DIR"

# ------------------------- Helpers -------------------------
ts(){ date +"%Y%m%d-%H%M%S"; }
backup_file(){ f="$1"; [ -e "$f" ] || return 0; b="${f}.bak.$(ts)"; cp -a -- "$f" "$b" && echo "🗂️  بکاپ گرفت: $b"; }
inplace_perl(){
  expr="$1"; tgt="$2"
  [ -f "$tgt" ] || return 0
  perl -CSDA -0777 -i -pe "$expr" "$tgt"
}

# ------------------------- Backups -------------------------
echo "==> گرفتن بکاپ‌ها…"
backup_file "$TEXT_FILE"
[ -f "$AQAYE_MAIN" ] && backup_file "$AQAYE_MAIN"
[ -f "$AQAYE_BACK" ] && backup_file "$AQAYE_BACK"

# ------------------------- New inner string (ONLY the quoted text) -------------------------
read -r -d '' NEW_INNER || true
NEW_INNER=$'$'"(
✅ فاکتور پرداخت ایجاد شد.

🔢 شماره فاکتور : %s
💰 مبلغ فاکتور : %s تومان

⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید

⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد
)"$'\n'

# ------------------------- Step 1: Replace WHOLE assignment safely -------------------------
# - می‌خوانیم NEW_INNER را، فرار می‌دهیم، و کل انتساب را عوض می‌کنیم
perl -CSDA -0777 -i -pe '
  BEGIN{
    binmode(STDIN,  ":utf8"); binmode(STDOUT, ":utf8");
    my $inner = $ENV{NEW_INNER} // "";
    # trim یک \n انتهایی اضافه‌ی ساختاری
    $inner =~ s/\R\z//;
    # escape برای گذاشتن داخل دابل‌کوت
    $inner =~ s/\\/\\\\/g;
    $inner =~ s/"/\\"/g;
    $inner =~ s/\r//g;
    # نگه می‌داریم
    $::REPL = "\"$inner\";";
  }
  # کل انتساب را (از = تا ; پایانی) با مقدار جدید می‌نشانیم
  s~
    (\$textbotlang\[\x27users\x27\]\[\x27moeny\x27\]\[\x27aqayepardakht\x27\]\s*=\s*)
    "
    (?:
      \\\"
      | [^"]
    )*?
    ";
  ~$1 . $::REPL~gsx;
' "$TEXT_FILE"

# ------------------------- Step 2 & 3: Brand renames (robust) -------------------------
# حذف ZWNJ برای ساده‌سازی
inplace_perl 's/\x{200C}//g' "$TEXT_FILE"

# مورد خاص: 🔵 آقای پرداخت → 💵 تتراپی TetraPay ( هوشمند )
# (آقای/آئى/آقئ/با فاصله‌های مختلف)
inplace_perl 's/🔵\s*آق(?:ای|ئى|ئ?ی)\s*پرداخت/💵 تتراپی TetraPay ( هوشمند )/g' "$TEXT_FILE"

# باقی رخدادها: هر نوع «آقای پرداخت» → «تتراپی»
# پوشش انواع «ی» عربی/فارسی و فاصله‌های احتمالی
inplace_perl 's/آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/تتراپی/g' "$TEXT_FILE"

# ------------------------- Step 4: Download/replace PHP files -------------------------
echo "==> دانلود و جایگزینی فایل‌های پرداخت از گیت‌هاب…"
TMP_MAIN="$(mktemp)"; TMP_BACK="$(mktemp)"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/aqayepardakht.php" -o "$TMP_MAIN"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/back.php"          -o "$TMP_BACK"

if [ ! -s "$TMP_MAIN" ] || [ ! -s "$TMP_BACK" ]; then
  echo "❌ دریافت فایل‌ها ناموفق بود. آدرس منبع: $SRC_BASE" >&2
  rm -f "$TMP_MAIN" "$TMP_BACK"; exit 1
fi
install -m 0644 "$TMP_MAIN" "$AQAYE_MAIN"
install -m 0644 "$TMP_BACK" "$AQAYE_BACK"
rm -f "$TMP_MAIN" "$TMP_BACK"

# ------------------------- Finalize -------------------------
(systemctl reload apache2 2>/dev/null || systemctl reload nginx 2>/dev/null || true)

echo "✅ همه‌چیز با موفقیت انجام شد.
- متن بلوک aqayepardakht کاملاً و با UTF-8 سالم جایگزین شد.
- «🔵 آقای پرداخت» → «💵 تتراپی TetraPay ( هوشمند )»
- همهٔ حالت‌های «آقای پرداخت» → «تتراپی»
- دو فایل پرداخت هم جایگزین شدند.
"
