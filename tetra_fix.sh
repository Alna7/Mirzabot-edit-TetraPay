#!/usr/bin/env bash
# tetra_fix.sh — ویرایش متن‌ها + جایگزینی دو فایل پرداخت از GitHub
# - بدون وابستگی به Perl/loCALE پیچیده؛ UTF-8-safe
# - با PHP CLI برای ویرایش دقیق متن
set -Ee -o pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ----------------- مسیرهای پیش‌فرض (در صورت نیاز با آرگومان override کن) -----------------
TEXT_FILE="/var/www/html/mirzabotconfig/text.php"
AQAYE_DIR="/var/www/html/mirzabotconfig/payment/aqayepardakht"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

# منبع دریافت فایل‌های جایگزین (پوشه‌ی files/ در ریپو)
SRC_BASE_DEFAULT="https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files"
SRC_BASE="$SRC_BASE_DEFAULT"

# ----------------- پردازش آرگومان‌ها -----------------
for arg in "$@"; do
  case "$arg" in
    --src=*)  SRC_BASE="${arg#--src=}" ;;                           # منبع فایل‌ها
    --text=*) TEXT_FILE="${arg#--text=}" ;;                          # مسیر text.php سفارشی
    --dir=*)  AQAYE_DIR="${arg#--dir=}"
              AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
              AQAYE_BACK="${AQAYE_DIR}/back.php" ;;
    *) echo "⚠️  پارامتر ناشناخته: $arg" ;;
  esac
done

# ----------------- بررسی‌های اولیه -----------------
if [ "$(id -u)" -ne 0 ]; then echo "❌ با sudo/روت اجرا کن."; exit 1; fi
if [ ! -f "$TEXT_FILE" ]; then echo "❌ فایل پیدا نشد: $TEXT_FILE"; exit 1; fi
mkdir -p "$AQAYE_DIR"

# ----------------- توابع کمکی -----------------
ts(){ date +"%Y%m%d-%H%M%S"; }
backup(){ f="$1"; [ -e "$f" ] || return 0; b="${f}.bak.$(ts)"; cp -a -- "$f" "$b" && echo "🗂️  بکاپ: $b"; }

# ----------------- بکاپ -----------------
echo "==> Backup…"
backup "$TEXT_FILE"
[ -f "$AQAYE_MAIN" ] && backup "$AQAYE_MAIN"
[ -f "$AQAYE_BACK" ] && backup "$AQAYE_BACK"

# ----------------- ویرایش متن‌ها (با PHP) -----------------
echo "==> Editing text.php…"
cat >/tmp/tetra_editor.php <<'PHP'
<?php
if ($argc < 2) exit("usage: php tetra_editor.php <file>\n");
$file=$argv[1];
$c=@file_get_contents($file);
if($c===false) exit("cannot read $file\n");
mb_internal_encoding('UTF-8');

/* 1) حذف ZWNJ برای نرمال‌سازی */
$c = str_replace("\xE2\x80\x8C","",$c); // U+200C

/* 2) "🔵 آقای پرداخت" → "💵 تتراپی TetraPay ( هوشمند )" */
$c = preg_replace('/🔵\s*آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u',
                  '💵 تتراپی TetraPay ( هوشمند )',$c);

/* 3) همه‌ی "آقای پرداخت" (با حالت‌های مختلف ی/فاصله) → "تتراپی" */
$c = preg_replace('/آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u','تتراپی',$c);

/* 4) جایگزینی دقیق بلوک aqayepardakht (فقط یک بار، اولین تطبیق) */
$newInner = <<<TXT
✅ فاکتور پرداخت ایجاد شد.
        
🔢 شماره فاکتور : %s
💰 مبلغ فاکتور : %s تومان
    
⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید

⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد
TXT;

$newAssign = '$textbotlang[\'users\'][\'moeny\'][\'aqayepardakht\'] = "'.addcslashes($newInner, "\\\"").'";';

$c = preg_replace(
    '/(\$textbotlang\[\x27users\x27\]\[\x27moeny\x27\]\[\x27aqayepardakht\x27\]\s*=\s*)"(?:\\\"|[^"])*?";/u',
    $newAssign,
    $c,
    1
);

if(@file_put_contents($file,$c)===false) exit("cannot write $file\n");
echo "OK\n";
PHP

php /tmp/tetra_editor.php "$TEXT_FILE"

# ----------------- دانلود و جایگزینی دو فایل پرداخت -----------------
echo "==> Replacing payment files from GitHub…"
TMP_MAIN="$(mktemp)"; TMP_BACK="$(mktemp)"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/aqayepardakht.php" -o "$TMP_MAIN"
curl -fsSL "${SRC_BASE}/payment/aqayepardakht/back.php"          -o "$TMP_BACK"

if [ ! -s "$TMP_MAIN" ] || [ ! -s "$TMP_BACK" ]; then
  echo "❌ دریافت فایل‌ها ناموفق بود. منبع: $SRC_BASE"
  rm -f "$TMP_MAIN" "$TMP_BACK"
  exit 1
fi

install -m 0644 "$TMP_MAIN" "$AQAYE_MAIN"
install -m 0644 "$TMP_BACK" "$AQAYE_BACK"
rm -f "$TMP_MAIN" "$TMP_BACK"

# ----------------- ری‌لود وب‌سرور (اختیاری) -----------------
(systemctl reload apache2 2>/dev/null || systemctl reload nginx 2>/dev/null || true)

echo "✅ همه‌چیز انجام شد:
- متن aqayepardakht جایگزین شد
- «🔵 آقای پرداخت» → «💵 تتراپی TetraPay ( هوشمند )»
- همهٔ «آقای پرداخت» → «تتراپی»
- aqayepardakht.php و back.php از GitHub جایگزین شدند
"
