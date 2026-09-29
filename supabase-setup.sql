-- دليل مكاتب العقارات — مروج
-- الصق الملف ده كله في Supabase > SQL Editor واضغط Run (مرة واحدة بس)

create table if not exists public.offices (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  area text default '',
  phone text default '',
  contact text default '',
  status text default '',
  notes text default '',
  rating smallint not null default 0 check (rating between 0 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- تحديث وقت التعديل تلقائياً
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists offices_touch on public.offices;
create trigger offices_touch before update on public.offices
for each row execute function public.touch_updated_at();

-- الحماية: محدش يقرأ أو يعدّل غير اللي عامل تسجيل دخول
alter table public.offices enable row level security;
drop policy if exists "signed-in users full access" on public.offices;
create policy "signed-in users full access" on public.offices
  for all to authenticated using (true) with check (true);

-- تفعيل المزامنة اللحظية
do $$ begin
  alter publication supabase_realtime add table public.offices;
exception when duplicate_object then null; end $$;
