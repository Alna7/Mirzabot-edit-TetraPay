#!/usr/bin/env bash
# tetra_fix.sh — ویرایش متن‌های "آقای پرداخت" → "تتراپی" و اصلاح بلوک aqayepardakht
set -Ee -o pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

TEXT_FILE="/var/www/html/mirzabotconfig/text.php"

ts(){ date +"%Y%m%d-%H%M%S"; }
backup(){ f="$1"; [ -e "$f" ] || return 0; b="${f}.bak.$(ts)"; cp -a -- "$f" "$b" && echo "🗂️  بکاپ: $b"; }

if [ "$(id -u)" -ne 0 ]; then echo "❌ با sudo/روت اجرا کن."; exit 1; fi
[ -f "$TEXT_FILE" ] || { echo "❌ فایل نیست: $TEXT_FILE"; exit 1; }

echo "==> Backup…"; backup "$TEXT_FILE"

cat >/tmp/tetra_editor.php <<'PHP'
<?php
if ($argc < 2) exit("usage: php tetra_editor.php <file>\n");
$file=$argv[1];
$c=@file_get_contents($file);
if($c===false) exit("cannot read $file\n");
mb_internal_encoding('UTF-8');

/* 1) حذف ZWNJ */
$c = str_replace("\xE2\x80\x8C","",$c);

/* 2) جایگزینی برند خاص */
$c = preg_replace('/🔵\s*آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u',
                  '💵 تتراپی TetraPay ( هوشمند )',$c);

/* 3) همهٔ رخدادهای آقای پرداخت → تتراپی */
$c = preg_replace('/آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/u','تتراپی',$c);

/* 4) جایگزینی دقیق بلوک aqayepardakht */
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
echo "✅ انجام شد روی: $TEXT_FILE"
