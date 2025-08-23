#!/usr/bin/env bash
set -euo pipefail

# ------------- Config -------------
# مسیر فایل‌ها (در صورت نیاز تغییر بده)
TEXT_FILE="/var/www/html/mirzabotconfig/text.php"
AQAYE_DIR="/var/www/html/mirzabotconfig/payment/aqayepardakht"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

# منبع دریافت فایل‌های جایگزین از گیت‌هاب (raw)
# می‌تونی با --src=... در زمان اجرا بدهی یا اینجا پیشفرض را ثابت کنی.
SRC_BASE="${SRC_BASE:-}"
for arg in "$@"; do
  case "$arg" in
    --src=*) SRC_BASE="${arg#--src=}" ;;
    *) echo "Unknown arg: $arg" ;;
  esac
done

if [[ -z "${SRC_BASE}" ]]; then
  echo "❌ لطفاً آدرس RAW گیت‌هاب را با پارامتر --src بده:
  مثال:
    --src=https://raw.githubusercontent.com/<user>/<repo>/<branch>/files
  که داخلش مسیرهای:
    payment/aqayepardakht/aqayepardakht.php
    payment/aqayepardakht/back.php
  موجود باشند."
  exit 1
fi

# ------------- Checks -------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ این اسکریپت باید با دسترسی روت اجرا شود (sudo)."
  exit 1
fi

if [[ ! -f "$TEXT_FILE" ]]; then
  echo "❌ فایل پیدا نشد: $TEXT_FILE"
  exit 1
fi

# ------------- Helpers -------------
ts() { date +"%Y%m%d-%H%M%S"; }
backup_file() {
  local f="$1"
  cp -a "$f" "${f}.bak.$(ts)"
  echo "🗂️  بکاپ گرفت: ${f}.bak.$(ts)"
}

inplace_perl() {
  # ویرایش امن با Perl (یونیکد/چندخطی)
  perl -CSDA -0777 -i -pe "$1" "$2"
}

# ------------- Step 0: Backups -------------
echo "==> گرفتن بکاپ‌ها…"
backup_file "$TEXT_FILE"
[[ -f "$AQAYE_MAIN" ]] && backup_file "$AQAYE_MAIN"
[[ -f "$AQAYE_BACK" ]] && backup_file "$AQAYE_BACK"

# ------------- Step 1: جایگزینی متن aqayepardakht در text.php -------------

# متن جدید (به صورت رشتهٔ escape شده برای Perl)
NEW_BLOCK=$(cat <<'PHPNEW'
$textbotlang['users']['moeny']['aqayepardakht'] = "
✅ فاکتور پرداخت ایجاد شد.
        
🔢 شماره فاکتور : %s
💰 مبلغ فاکتور : %s تومان
    
⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید

⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد";
PHPNEW
)

# الگوی یافتن کل مقدار رشتهٔ aqayepardakht (بدون تکیه بر متن قبلی)
# هر چیزی بین اولین " تا " قبل از ; را تعویض می‌کنیم.
echo "==> اصلاح بلوک aqayepardakht در text.php …"
perl -CSDA -0777 -i -pe '
  s/
    (\$textbotlang\[\x27users\x27\]\[\x27moeny\x27\]\[\x27aqayepardakht\x27\]\s*=\s*)
    "
    (?:
      \\"|[^"]
    )*?
    ";
  /$1"__REPL__";/gsx
' "$TEXT_FILE"

# حالا __REPL__ را با متن دقیق جایگزین کن (فرارِ کارکترها برای Perl):
ESCAPED=$(printf "%s" "$NEW_BLOCK" | perl -CSDA -pe 's/\\/\\\\/g; s/\$/\\\$/g; s/@/\\@/g; s/\n/\\n/g; s/"/\\"/g;')
perl -CSDA -0777 -i -pe "s/\"__REPL__\";/\"$ESCAPED\";/s" "$TEXT_FILE"

# ------------- Step 2: "🔵 آقای پرداخت" → "💵 تتراپی TetraPay ( هوشمند )" -------------
echo "==> جایگزینی عنوان برند با ایموجی جدید…"
inplace_perl 's/🔵\s*آقای پرداخت/💵 تتراپی TetraPay ( هوشمند )/g' "$TEXT_FILE"

# ------------- Step 3: همهٔ «آقای پرداخت» → «تتراپی» -------------
echo "==> جایگزینی تمام رخدادهای «آقای پرداخت» به «تتراپی» …"
inplace_perl 's/آقای پرداخت/تتراپی/g' "$TEXT_FILE"

# ------------- Step 4: دریافت و جایگزینی دو فایل PHP از گیت‌هاب -------------
echo "==> دانلود و جایگزینی فایل‌های پرداخت از گیت‌هاب…"
mkdir -p "$AQAYE_DIR"

curl -fsSL "${SRC_BASE}/payment/aqayepardakht/aqayepardakht.php" -o "${AQAYE_MAIN}.new"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/back.php"          -o "${AQAYE_BACK}.new"

# کنترل سادهٔ اعتبار دریافت
if [[ ! -s "${AQAYE_MAIN}.new" || ! -s "${AQAYE_BACK}.new" ]]; then
  echo "❌ دریافت فایل‌های جایگزین ناموفق بود. آدرس --src را بررسی کن."
  rm -f "${AQAYE_MAIN}.new" "${AQAYE_BACK}.new"
  exit 1
fi

# جایگزینی اتمیک
mv -f "${AQAYE_MAIN}.new" "$AQAYE_MAIN"
mv -f "${AQAYE_BACK}.new" "$AQAYE_BACK"

# ------------- Done -------------
echo "✅ انجام شد.
- فایل‌های اصلی بکاپ شدند.
- text.php ویرایش شد.
- فایل‌های aqayepardakht.php و back.php جایگزین شدند.

ℹ️ در صورت نیاز، سرویس وب‌سرورت را ری‌لود کن:
  sudo systemctl reload apache2  || true
"
