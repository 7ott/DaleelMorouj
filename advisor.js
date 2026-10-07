// المستشار الذكي — دالة Vercel
// بتتأكد إن الطلب جاي من مستخدم مسجّل دخول في النظام، وبعدين بتبعت أرقام الأداء لـ Claude وترجّع الرد أول بأول.
// المفتاح بيتحط في Vercel ← Settings ← Environment Variables باسم ANTHROPIC_API_KEY (مش في الكود).

const SUPABASE_URL = process.env.SUPABASE_URL || "https://tvinmbnnkxdgignxnbeu.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || "sb_publishable_rDHiaejicl4LcO4W_CCSKw_gHFjoFMD";
const MODEL = process.env.ANTHROPIC_MODEL || "claude-sonnet-5-5";

const SYSTEM = `إنت مستشار مبيعات عقارية خبير، شغال مع شركة "مروج العقارية" في بني سويف، مصر. الشركة بتسوّق وحدات (شقق، فيلات، أراضي، محلات) لملاك، وبتتعامل مع مشترين وتجار ومكاتب عقارية.

بيوصلك ملخص أرقام حقيقي من نظام الـ CRM بتاعهم (JSON). شغلك إنك تحلل الأرقام دي بعمق وتقول لصاحب الشركة يعمل إيه بالظبط عشان يزوّد المبيعات ويحسّن جودة الصفقات ويعالج نقط الضعف.

قواعد لازم تلتزم بيها:
- اكتب بالعامية المصرية المهنية، واضح ومباشر، من غير مقدمات ولا مجاملات.
- كل كلام لازم يكون مبني على رقم من البيانات، واذكر الرقم. متخترعش أرقام أو أسماء مش موجودة.
- لو البيانات قليلة أو ناقصة في نقطة معينة، قول ده صراحة وقول يسجّلوا إيه عشان التحليل يبقى أدق.
- فرّق بين السبب والعَرَض: مثلاً نسبة إغلاق قليلة ممكن سببها بطء الرد أو مصدر عملاء ضعيف أو مخزون مش مناسب. استنتج السبب الأرجح من الأرقام ووضّح إزاي وصلتله.
- التوصيات لازم تكون عملية وقابلة للتنفيذ في السوق المصري: مين يعمل إيه، إمتى، وإزاي هيقيسوا النتيجة.
- رتّب كل حاجة حسب التأثير على المبيعات، الأهم الأول.
- التنسيق: عناوين بـ ##، نقاط بـ -، ترقيم بـ 1. 2. 3.، وتقدر تستخدم **خط عريض** للأرقام المهمة. متستخدمش جداول. استخدم الأرقام الإنجليزي 0-9.`;

const REPORT = `اعمل تقرير تشخيص كامل بالترتيب ده:

## الخلاصة في 3 سطور
الوضع العام، أهم مشكلة، وأهم فرصة.

## نقط القوة
الحاجات اللي شغالة كويس وإزاي يحافظوا عليها (باختصار).

## المشاكل والعيوب بالترتيب
لكل مشكلة: إيه هي، الدليل بالأرقام، السبب الأرجح، وتأثيرها على المبيعات أو الفلوس.

## جودة الصفقات
الخصومات، العمولات، مدة التفاوض، أسباب الخسارة، وإزاي تتحسن.

## الفرص
مناطق أو أنواع وحدات أو شرايح أسعار أو مصادر عملاء يستغلوها.

## الفريق
مين محتاج دعم وفي إيه (لو البيانات فيها أكتر من موظف).

## خطة العمل
### الأسبوع ده
خطوات محددة (مين، إيه، إمتى).
### الشهر ده
خطوات أكبر.

## الأهداف اللي تقيسوها
3 إلى 6 مؤشرات، لكل واحد الرقم الحالي والرقم المستهدف بعد 30 يوم.`;

function readBody(req) {
  if (req.body && typeof req.body === "object") return Promise.resolve(req.body);
  if (typeof req.body === "string") { try { return Promise.resolve(JSON.parse(req.body)); } catch { return Promise.resolve({}); } }
  return new Promise((resolve) => {
    let d = "";
    req.on("data", (c) => { d += c; if (d.length > 400000) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(d || "{}")); } catch { resolve({}); } });
    req.on("error", () => resolve({}));
  });
}

module.exports = async (req, res) => {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) { res.status(503).json({ error: "not_configured" }); return; }

  // لازم المستخدم يكون مسجّل دخول في النظام
  const token = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!token) { res.status(401).json({ error: "auth" }); return; }
  try {
    const u = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}` } });
    if (!u.ok) { res.status(401).json({ error: "auth" }); return; }
    // المستشار للمدير بس
    const me = await u.json();
    const pr = await fetch(`${SUPABASE_URL}/rest/v1/profiles?select=role&user_id=eq.${encodeURIComponent(me.id || "")}`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}` } });
    if (pr.ok) {
      const rows = await pr.json();
      if (!Array.isArray(rows) || !rows[0] || rows[0].role !== "admin") { res.status(403).json({ error: "forbidden" }); return; }
    }
  } catch { res.status(502).json({ error: "auth_check_failed" }); return; }

  const body = await readBody(req);
  const mode = body.mode === "chat" ? "chat" : "report";
  const ctx = JSON.stringify(body.context || {});
  if (ctx.length > 150000) { res.status(413).json({ error: "too_large" }); return; }
  const intro = "دي أرقام الأداء من النظام (JSON):\n```json\n" + ctx + "\n```";

  let messages;
  if (mode === "report") {
    messages = [{ role: "user", content: intro + "\n\n" + REPORT }];
  } else {
    const report = String(body.report || "").slice(0, 30000);
    const hist = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim())
      .slice(-12)
      .map((m) => ({ role: m.role, content: m.content.slice(0, 6000) }));
    while (hist.length && hist[0].role !== "user") hist.shift();
    if (!hist.length || hist[hist.length - 1].role !== "user") { res.status(400).json({ error: "bad_messages" }); return; }
    messages = [
      { role: "user", content: intro + "\n\n" + (report ? "اعمل تقرير تشخيص كامل." : "هسألك أسئلة عن الأرقام دي. جاوب باختصار ودقة ومن الأرقام.") },
      { role: "assistant", content: report || "تمام، الأرقام قدامي. اسأل." },
    ];
    // لازم الرسايل تتبادل بين المستخدم والمستشار
    for (const m of hist) {
      const last = messages[messages.length - 1];
      if (last.role === m.role) last.content += "\n\n" + m.content; else messages.push(m);
    }
  }

  let up;
  try {
    up = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: mode === "report" ? 8000 : 3000, system: SYSTEM, messages, stream: true }),
    });
  } catch (e) { res.status(502).json({ error: "upstream", detail: String(e && e.message || e) }); return; }
  if (!up.ok || !up.body) {
    let detail = ""; try { detail = await up.text(); } catch {}
    res.status(502).json({ error: "upstream", status: up.status, detail: detail.slice(0, 600) }); return;
  }

  res.statusCode = 200;
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("X-Accel-Buffering", "no");

  const reader = up.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (!line.startsWith("data:")) continue;
        try {
          const ev = JSON.parse(line.slice(5).trim());
          if (ev.type === "content_block_delta" && ev.delta && ev.delta.type === "text_delta") res.write(ev.delta.text);
          else if (ev.type === "error") res.write("\n\n[حصل خطأ من خدمة الذكاء الاصطناعي: " + ((ev.error && ev.error.message) || "") + "]");
        } catch {}
      }
    }
  } catch (e) {
    res.write("\n\n[الاتصال اتقطع قبل ما الرد يكمل]");
  }
  res.end();
};

// أقصى مدة للرد (بدل ملف vercel.json)
module.exports.config = { maxDuration: 60 };
