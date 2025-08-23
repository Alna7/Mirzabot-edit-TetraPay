# 1) مسیرها
TEXT_FILE="/var/www/html/mirzabotconfig/text.php"
AQAYE_DIR="/var/www/html/mirzabotconfig/payment/aqayepardakht"
AQAYE_MAIN="${AQAYE_DIR}/aqayepardakht.php"
AQAYE_BACK="${AQAYE_DIR}/back.php"

# 2) ایجاد متن جدیدِ بلوک aqayepardakht در یک فایل موقت
cat > /tmp/new_block.txt <<'PHPNEW'
$textbotlang['users']['moeny']['aqayepardakht'] = "
✅ فاکتور پرداخت ایجاد شد.
        
🔢 شماره فاکتور : %s
💰 مبلغ فاکتور : %s تومان
    
⚠️با زدن دکمه زیر وارد صفحه پرداخت شوید و مبلغ ذکر شده را دقیق بدون حتی یک ریال کم یا زیاد به شماره کارت اعلام شده واریز کنید

⚡️سفارش شما بصورت اتوماتیک و لحظه ای تایید خواهد شد";
PHPNEW

# 3) جایگزینی خودِ بلوک (رویکرد دو مرحله‌ای: اول جایگزینی با توکن، بعد تزریق متن دقیق)
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

perl -CSDA -0777 -i -pe '
  BEGIN{
    open F,"/tmp/new_block.txt" or die $!;
    $r=join"",<F>; close F;
    $r =~ s/\\/\\\\/g; $r =~ s/"/\\"/g; $r =~ s/\n/\\n/g;
  }
  s/"__REPL__";/"$r";/s
' "$TEXT_FILE"

# 4) جایگزینی عنوان ایموجی‌دار و همه رخدادهای «آقای پرداخت»
perl -CSDA -0777 -i -pe 's/🔵\s*آقای پرداخت/💵 تتراپی TetraPay ( هوشمند )/g; s/آقای پرداخت/تتراپی/g' "$TEXT_FILE"

# 5) دانلود و جایگزینی دو فایل PHP از ریپو شما
curl -fsSL "https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files/payment/aqayepardakht/aqayepardakht.php" -o "${AQAYE_MAIN}"
curl -fsSL "https://raw.githubusercontent.com/Alna7/Mirzabot-edit-TetraPay/main/files/payment/aqayepardakht/back.php"          -o "${AQAYE_BACK}"

# 6) (اختیاری) ری‌لود آپاچی
systemctl reload apache2 2>/dev/null || true

echo "✅ Hotfix انجام شد."
