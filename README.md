# دليل مكاتب العقارات — مروج
## خطوات التشغيل على murujdaleel.online

الملفات اللي في الفولدر:
- `index.html` — الأداة نفسها
- `logo.png` — لوجو مروج
- `supabase-setup.sql` — تجهيز قاعدة البيانات

---

### 1) قاعدة البيانات (Supabase) — حوالي 5 دقايق
1. ادخل على supabase.com واعمل حساب مجاني، وبعدين **New project**. اختار أي اسم وباسورد، والمنطقة الأقرب ليك (مثلاً Frankfurt).
2. من القائمة الجانبية افتح **SQL Editor**، والصق محتوى ملف `supabase-setup.sql` كله، واضغط **Run**.
3. افتح **Project Settings ← API** وانسخ حاجتين:
   - **Project URL**
   - **anon public key**
4. افتح `index.html` بأي محرر نصوص (حتى Notepad)، وهتلاقي في بداية الكود السطرين دول:
   ```
   const SUPABASE_URL = "PASTE_SUPABASE_URL_HERE";
   const SUPABASE_ANON_KEY = "PASTE_SUPABASE_ANON_KEY_HERE";
   ```
   حط الـ URL والـ key مكان النص، وخلّي علامات التنصيص زي ما هي، واحفظ الملف.

### 2) حسابات الدخول
1. في Supabase افتح **Authentication ← Sign In / Providers**، وقفّل **Allow new users to sign up**. كده محدش غريب يقدر يعمل لنفسه حساب.
2. افتح **Authentication ← Users ← Add user ← Create new user**، واكتب:
   - Email: `muruj@murujdaleel.online`
   - Password: `mj.admin`
   - علّم على **Auto Confirm User**
   
   بعد كده تدخل الأداة باسم المستخدم **muruj** وكلمة المرور **mj.admin**. الإيميل ده مش لازم يكون حقيقي، ده بس الطريقة اللي Supabase بيحفظ بيها المستخدم.
3. لو عايز تضيف مستخدم تاني، مثلاً `ahmed`، اعمله بإيميل `ahmed@murujdaleel.online` بنفس الطريقة، ويدخل باسم `ahmed`.
4. لو حبيت تغيّر كلمة المرور بعدين: من نفس صفحة Users، اضغط على المستخدم واختار تغيير الباسورد.

### 3) الرفع على Vercel وربط الدومين
1. اعمل حساب على github.com، وبعدين **New repository** باسم `murujdaleel`.
2. جوه الـ repo اضغط **uploading an existing file**، واسحب الـ 3 ملفات، وبعدين **Commit changes**.
3. في Vercel: **Add New ← Project**، واختار الـ repo ده، وسيب كل الإعدادات زي ما هي، واضغط **Deploy**.
4. من المشروع افتح **Settings ← Domains**، واكتب `murujdaleel.online`، واضغط **Add**. بما إن الدومين محجوز من Vercel، الربط بيتم تلقائي.

خلاص كده. افتح murujdaleel.online وسجّل دخول.

---

### ملاحظات
- **لو عندك داتا في النسخة القديمة** (اللي على claude.ai): اضغط هناك "نسخ CSV"، وبعدين هنا "استيراد قائمة" والصق.
- **تعديل الأداة بعدين**: عدّل الملف على GitHub، وVercel هيحدّث الموقع لوحده في ثواني.
- **الـ anon key** معمول عشان يتحط في الصفحة، ومفيش خطر من إنه يبان، لأن الحماية معمولة جوه قاعدة البيانات نفسها. إوعى تحط الـ **service_role key** في الصفحة أبداً.
- **الخطة المجانية في Supabase** بتوقف المشروع لو فضل أسبوع من غير ما حد يستخدمه. تقدر ترجّعه بضغطة من لوحة التحكم، والداتا مابتضيعش.
