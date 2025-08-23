#!/usr/bin/env bash
# tetra_fix.sh — ویرایش متن‌ها + جایگزینی دو فایل پرداخت از GitHub (با لاگ واضح)
set -Ee -o pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ----------------- مسیرهای پیش‌فرض -----------------
TEXT_FILE="/var/www/html/mirzabotconfig/text.php"
AQAYE_DIR="/var/www/html/mirzabotconfig/payment/aqayepardakht"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

# منبع (قابل override با --src)
SRC_BASE_DEFAULT="https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files"
SRC_BASE="$SRC_BASE_DEFAULT"

# ----------------- آرگومان‌ها -----------------
for arg in "$@"; do
  case "$arg" in
    --src=*)  SRC_BASE="${arg#--src=}" ;;
    --text=*) TEXT_FILE="${arg#--text=}" ;;
    --dir=*)  AQAYE_DIR="${arg#--dir=}"; AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"; AQAYE_BACK="${AQAYE_DIR}/back.php" ;;
    *) echo "⚠️  پارامتر ناشناخته: $arg" ;;
  esac
done

# ----------------- بررسی‌ها -----------------
[ "$(id -u)" -eq 0 ] || { echo "❌ با sudo/روت اجرا کن."; exit 1; }
[ -f "$TEXT_FILE" ]  || { echo "❌ فایل پیدا نشد: $TEXT_FILE"; exit 1; }
mkdir -p "$AQAYE_DIR"

# ----------------- توابع -----------------
ts(){ date +"%Y%m%d-%H%M%S"; }
backup(){ f="$1"; [ -e "$f" ] || return 0; b="${f}.bak.$(ts)"; cp -a -- "$f" "$b" && echo "🗂️  بکاپ: $b"; }

step(){ echo -e "\n==== $1 ===="; }

# ----------------- مرحله 1: بکاپ -----------------
step "Backup"
backup "$TEXT_FILE"
[ -f "$AQAYE_MAIN" ] && backup "$AQAYE_MAIN"
[ -f "$AQAYE_BACK" ] && backup "$AQAYE_BACK"

# ----------------- مرحله 2: ادیت text.php (PHP CLI) -----------------
step "Editing text.php"
cat >/tmp/tetra_editor.php <<'PHP'
<?php
if ($argc < 2) exit("usage: php tetra_editor.php <file>\n");
$file=$argv[1];
$c=@file_get_contents($file);
if($c===false) exit("cannot read $file\n");
mb_internal_encoding('UTF-8');

/* حذف ZWNJ */
$c = str_replace("\xE2\x80\x8C","",$c);

/* "🔵 آقای پرداخت" → "💵 تتراپی TetraPay ( هوشمند )" */
$c = preg_replace('/🔵\s*آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u',
                  '💵 تتراپی TetraPay ( هوشمند )',$c);

/* همهٔ «آقای پرداخت» → «تتراپی» */
$c = preg_replace('/آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u','تتراپی',$c);

/* جایگزینی دقیق بلوک aqayepardakht */
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
echo "✅ text.php edited."

# ----------------- مرحله 3: جایگزینی دو فایل از GitHub -----------------
step "Replacing payment files from GitHub"
TMP_MAIN="$(mktemp)"; TMP_BACK="$(mktemp)"
URL_MAIN="${SRC_BASE}/payment/aqayepardakht/aqayepardakht.php"
URL_BACK="${SRC_BASE}/payment/aqayepardakht/back.php"

echo "دانلود: $URL_MAIN"
curl -fsSLo "$TMP_MAIN" "$URL_MAIN"
echo "دانلود: $URL_BACK"
curl -fsSLo "$TMP_BACK" "$URL_BACK"

# حفظ مالکیت قبلی اگر وجود داشته باشد
[ -f "$AQAYE_MAIN" ] && OWN_MAIN="$(stat -c '%U:%G' "$AQAYE_MAIN")" || OWN_MAIN=""
[ -f "$AQAYE_BACK" ] && OWN_BACK="$(stat -c '%U:%G' "$AQAYE_BACK")" || OWN_BACK=""

# نصب
install -m 0644 "$TMP_MAIN" "$AQAYE_MAIN"
install -m 0644 "$TMP_BACK" "$AQAYE_BACK"

# برگرداندن مالکیت قبلی (اگر موجود بود)
[ -n "$OWN_MAIN" ] && chown "$OWN_MAIN" "$AQAYE_MAIN"
[ -n "$OWN_BACK" ] && chown "$OWN_BACK" "$AQAYE_BACK"

# تست نحو PHP
php -l "$AQAYE_MAIN"
php -l "$AQAYE_BACK"
echo "✅ payment files replaced."

# ----------------- مرحله 4: ری‌لود وب‌سرور -----------------
step "Reload web server (if any)"
(systemctl reload apache2 2>/dev/null || systemctl reload nginx 2>/dev/null || true)
echo "✅ all done."
