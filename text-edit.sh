#!/usr/bin/env bash
# text-edit.sh — ویرایش متن‌های آقای پرداخت → تتراپی
set -Ee -o pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

TEXT_FILE="/var/www/html/mirzabotconfig/text.php"

ts(){ date +"%Y%m%d-%H%M%S"; }
backup_file(){ f="$1"; [ -e "$f" ] || return 0; b="${f}.bak.$(ts)"; cp -a -- "$f" "$b" && echo "🗂️  بکاپ گرفت: $b"; }

if [ "$(id -u)" -ne 0 ]; then echo "❌ باید با sudo/روت اجرا شود"; exit 1; fi
[ -f "$TEXT_FILE" ] || { echo "❌ فایل پیدا نشد: $TEXT_FILE"; exit 1; }

echo "==> گرفتن بکاپ…"
backup_file "$TEXT_FILE"

# محتوای جدید برای aqayepardakht (فقط متن داخل گیومه)
NEW_INNER=$'✅ فاکتور پرداخت ایجاد شد.\n\n🔢 شماره فاکتور : %s\n💰 مبلغ فاکتور : %s تومان\n\n⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید\n\n⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد'

echo "==> جایگزینی بلوک aqayepardakht…"
perl -CSDA -0777 -i -pe '
  BEGIN{
    binmode(STDIN,":utf8"); binmode(STDOUT,":utf8");
    my $inner=$ENV{NEW_INNER}//"";
    $inner =~ s/\\/\\\\/g; $inner =~ s/"/\\"/g;
    $::REPL="\"$inner\";";
  }
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

echo "==> جایگزینی نام برند…"
# حذف ZWNJ
perl -CSDA -0777 -i -pe 's/\x{200C}//g' "$TEXT_FILE"
# مورد خاص
perl -CSDA -0777 -i -pe 's/🔵\s*آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/💵 تتراپی TetraPay ( هوشمند )/g' "$TEXT_FILE"
# همهٔ باقی‌ها
perl -CSDA -0777 -i -pe 's/آق(?:ای|ئى|ئ?[\x{064A}\x{06CC}])\s*پرداخت/تتراپی/g' "$TEXT_FILE"

echo "✅ همه تغییرات اعمال شد روی $TEXT_FILE"
