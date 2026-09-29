-- ================================================================
-- CRM مروج العقارية — تجهيز قاعدة البيانات
-- الصق الملف كله في Supabase > SQL Editor واضغط Run.
-- آمن تشغّله أكتر من مرة، ومش بيمسح أي داتا موجودة (المكاتب زي ما هي).
-- ================================================================

create extension if not exists pgcrypto;

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

-- المكاتب العقارية (موجود من قبل — بنضيف بس عمود جديد)
create table if not exists public.offices (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  area text default '', phone text default '', contact text default '',
  status text default '', notes text default '',
  rating smallint not null default 0 check (rating between 0 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.offices add column if not exists created_by text;

-- العملاء: مشتري / مالك / تاجر
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('buyer','owner','trader')),
  name text not null,
  phone text, phone2 text, email text, area text, source text,
  temp text, assigned_to text,
  office_id uuid references public.offices(id) on delete set null,
  budget_min numeric, budget_max numeric, prop_type text, pref_areas text,
  rooms int, payment text, purpose text,
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- الوحدات العقارية
create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  code text, title text not null, prop_type text, deal_kind text default 'بيع',
  area text, address text, size numeric, rooms int, baths int, floor text,
  finishing text, price numeric, commission_pct numeric,
  status text not null default 'available',
  owner_id uuid references public.contacts(id) on delete set null,
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- الصفقات ومراحلها
create table if not exists public.deals (
  id uuid primary key default gen_random_uuid(),
  title text,
  stage text not null default 'new',
  buyer_id uuid references public.contacts(id) on delete set null,
  property_id uuid references public.properties(id) on delete set null,
  trader_id uuid references public.contacts(id) on delete set null,
  office_id uuid references public.offices(id) on delete set null,
  value numeric, commission numeric, expected_close date,
  source text, assigned_to text, lost_reason text,
  won_at timestamptz, stage_changed_at timestamptz default now(),
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- سجل التواصل (مكالمات، واتساب، معاينات، ملاحظات، تغيير مراحل)
create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'note',
  body text,
  contact_id uuid references public.contacts(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  property_id uuid references public.properties(id) on delete set null,
  office_id uuid references public.offices(id) on delete set null,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- المتابعات والمهام
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  due_at timestamptz,
  done boolean not null default false,
  done_at timestamptz,
  priority text default 'normal',
  assigned_to text,
  contact_id uuid references public.contacts(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  property_id uuid references public.properties(id) on delete set null,
  office_id uuid references public.offices(id) on delete set null,
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists deals_buyer_idx on public.deals(buyer_id);
create index if not exists deals_property_idx on public.deals(property_id);
create index if not exists acts_contact_idx on public.activities(contact_id);
create index if not exists acts_deal_idx on public.activities(deal_id);
create index if not exists tasks_due_idx on public.tasks(due_at) where not done;

-- تحديث وقت التعديل + الحماية (محدش يدخل غير اللي مسجّل) + المزامنة اللحظية
do $$
declare t text;
begin
  foreach t in array array['offices','contacts','properties','deals','activities','tasks'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_updated_at()', t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "signed-in users full access" on public.%I', t);
    execute format('create policy "signed-in users full access" on public.%I for all to authenticated using (true) with check (true)', t);
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
