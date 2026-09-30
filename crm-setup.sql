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

-- تحديث وقت التعديل + تفعيل الحماية + المزامنة اللحظية
do $$
declare t text;
begin
  foreach t in array array['offices','contacts','properties','deals','activities','tasks'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_updated_at()', t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "signed-in users full access" on public.%I', t);
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- تاريخ المراحل: عشان قمع البيع ومدة كل مرحلة يتحسبوا بدقة
alter table public.activities add column if not exists from_stage text;
alter table public.activities add column if not exists to_stage text;

-- تقارير المستشار الذكي المحفوظة
create table if not exists public.ai_reports (
  id uuid primary key default gen_random_uuid(),
  content text not null,
  period text,
  health int,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.ai_reports enable row level security;
drop policy if exists "signed-in users full access" on public.ai_reports;

-- ================================================================
-- الصلاحيات: مدير (admin) / سيلز (sales) / موقوف (disabled)
-- ================================================================
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  username text,
  role text not null default 'sales' check (role in ('admin','sales','disabled')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- اسم المستخدم الحالي (الجزء قبل @ في الإيميل)
create or replace function public.me_name() returns text
language sql stable as $$ select split_part(lower(coalesce(auth.jwt()->>'email','')),'@',1) $$;

-- دور المستخدم الحالي (أي حد مالوش ملف بيتعامل كموقوف)
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where user_id = auth.uid()), 'disabled') $$;

create or replace function public.is_admin() returns boolean
language sql stable as $$ select public.my_role() = 'admin' $$;

-- كل مستخدم جديد بيتعمله ملف تلقائي كـ"سيلز"، وmuruj مدير
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, email, username, role)
  values (new.id, lower(new.email), split_part(lower(new.email),'@',1),
          case when lower(new.email) = 'muruj@murujdaleel.online' then 'admin' else 'sales' end)
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (user_id, email, username, role)
select id, lower(email), split_part(lower(email),'@',1),
       case when lower(email) = 'muruj@murujdaleel.online' then 'admin' else 'sales' end
from auth.users on conflict (user_id) do nothing;
update public.profiles set role = 'admin' where email = 'muruj@murujdaleel.online';

-- ---------- السياسات ----------
-- قاعدة عامة: المدير يشوف ويعمل كل حاجة. السيلز يشوف ويعدّل اللي باسمه بس، ومايقدرش يحذف أي حاجة.
do $$
declare t text; p record;
begin
  -- امسح أي سياسات قديمة على الجداول دي
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in ('offices','contacts','properties','deals','activities','tasks','ai_reports','profiles')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;

  -- العملاء والصفقات والمتابعات: ملكية بالمسؤول (أو اللي أضافه لو مفيش مسؤول)
  foreach t in array array['contacts','deals','tasks'] loop
    execute format($f$create policy "view own or admin" on public.%I for select to authenticated
      using (public.is_admin() or (public.my_role() = 'sales' and coalesce(assigned_to, created_by) = public.me_name()))$f$, t);
    execute format($f$create policy "edit own or admin" on public.%I for update to authenticated
      using (public.is_admin() or (public.my_role() = 'sales' and coalesce(assigned_to, created_by) = public.me_name()))
      with check (public.is_admin() or (public.my_role() = 'sales' and coalesce(assigned_to, created_by) = public.me_name()))$f$, t);
    execute format($f$create policy "delete admin only" on public.%I for delete to authenticated using (public.is_admin())$f$, t);
  end loop;

  create policy "add own or admin" on public.contacts for insert to authenticated
    with check (public.is_admin() or (public.my_role() = 'sales' and created_by = public.me_name() and coalesce(assigned_to, created_by) = public.me_name()));
  create policy "add own or admin" on public.deals for insert to authenticated
    with check (public.is_admin() or (public.my_role() = 'sales' and created_by = public.me_name() and coalesce(assigned_to, created_by) = public.me_name()
      and (buyer_id is null or exists (select 1 from public.contacts c where c.id = buyer_id))));
  create policy "add own or admin" on public.tasks for insert to authenticated
    with check (public.is_admin() or (public.my_role() = 'sales' and created_by = public.me_name() and coalesce(assigned_to, created_by) = public.me_name()));

  -- سجل التواصل: السيلز يشوف ويضيف على عملاؤه وصفقاته، ومايعدّلش ولا يحذف
  create policy "view linked or admin" on public.activities for select to authenticated
    using (public.is_admin() or (public.my_role() = 'sales' and (created_by = public.me_name()
      or exists (select 1 from public.contacts c where c.id = contact_id)
      or exists (select 1 from public.deals d where d.id = deal_id))));
  create policy "add linked or admin" on public.activities for insert to authenticated
    with check (public.is_admin() or (public.my_role() = 'sales' and created_by = public.me_name()
      and (contact_id is not null or deal_id is not null)
      and (contact_id is null or exists (select 1 from public.contacts c where c.id = contact_id))
      and (deal_id is null or exists (select 1 from public.deals d where d.id = deal_id))));
  create policy "edit admin only" on public.activities for update to authenticated using (public.is_admin()) with check (public.is_admin());
  create policy "delete admin only" on public.activities for delete to authenticated using (public.is_admin());

  -- الوحدات والمكاتب: السيلز يشوف بس، والمدير يعدّل
  foreach t in array array['properties','offices'] loop
    execute format($f$create policy "view team" on public.%I for select to authenticated using (public.my_role() in ('admin','sales'))$f$, t);
    execute format($f$create policy "add admin only" on public.%I for insert to authenticated with check (public.is_admin())$f$, t);
    execute format($f$create policy "edit admin only" on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())$f$, t);
    execute format($f$create policy "delete admin only" on public.%I for delete to authenticated using (public.is_admin())$f$, t);
  end loop;

  -- تقارير المستشار: المدير بس
  create policy "admin only" on public.ai_reports for all to authenticated using (public.is_admin()) with check (public.is_admin());

  -- ملفات الفريق: كل واحد يشوف ملفه، والمدير يشوف ويغيّر الكل
  create policy "view self or admin" on public.profiles for select to authenticated using (user_id = auth.uid() or public.is_admin());
  create policy "edit admin only" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
end $$;

-- حالة الوحدة بتتحدث لوحدها مع مرحلة الصفقة (حجز ← محجوزة، بيع ← مباعة، خسارة ← ترجع متاحة)
create or replace function public.sync_property_from_deal() returns trigger
language plpgsql security definer set search_path = public as $$
declare cur text; st text;
begin
  if new.property_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.stage is not distinct from old.stage then return new; end if;
  select status into cur from public.properties where id = new.property_id;
  st := case when new.stage in ('reserved','contract') then 'reserved'
             when new.stage = 'won' then 'sold'
             when new.stage = 'lost' and cur = 'reserved' then 'available' end;
  if st is not null and st is distinct from cur then
    update public.properties set status = st where id = new.property_id;
    insert into public.activities (kind, body, property_id, created_by)
    values ('system', 'حالة الوحدة بقت «' || case st when 'reserved' then 'محجوزة' when 'sold' then 'مباعة' else 'متاحة' end || '»', new.property_id, 'النظام');
  end if;
  return new;
end $$;
drop trigger if exists deals_sync_property on public.deals;
create trigger deals_sync_property after insert or update of stage on public.deals
for each row execute function public.sync_property_from_deal();

-- منع تكرار العملاء: بيقول الرقم متسجل عند مين، من غير ما يكشف بيانات العميل
create or replace function public.phone_owner(p text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(assigned_to, created_by, '')
  from public.contacts
  where public.my_role() in ('admin','sales')
    and length(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g')) >= 8
    and right(regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g'), 10) = right(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 10)
  limit 1 $$;

-- ================================================================
-- ترتيب الفريق ونظام النقاط (ظاهر لكل الفريق)
-- بيرجّع الإجماليات بس لكل عضو، من غير أي بيانات عملاء.
-- حجم المبيعات بالجنيه بيظهر للمدير بس.
--   بيع صفقة ............................ 100
--   تعاقد 40 · حجز/عربون 30 · تفاوض 15 · معاينة (مرحلة) 10 · تحديد احتياج 3 · تواصل 2
--     (كل مرحلة بتتحسب مرة واحدة بس لكل صفقة، فالرجوع والتقديم مايزودش نقط)
--   معاينة مسجلة 8 · مكالمة/واتساب/اجتماع 1 (مرة واحدة لكل عميل في اليوم)
--   عميل جديد 2 · رد في أول ساعة +5 · رد في أول 24 ساعة +2
--   متابعة اتعملت في ميعادها +2 · متابعة متأخرة دلوقتي -2 (بحد أقصى -30)
-- ================================================================
drop function if exists public.leaderboard(timestamptz, timestamptz);
create or replace function public.leaderboard(p_from timestamptz, p_to timestamptz)
returns table (
  username text, role text, points int, breakdown jsonb,
  wins int, lost int, revenue numeric, advances int, touches int, visits int,
  new_clients int, fast_1h int, fast_24h int, resp_minutes numeric,
  tasks_due int, tasks_ontime int, overdue int
)
language sql stable security definer set search_path = public as $$
with members as (
  select p.username, p.role from public.profiles p
  where p.role in ('admin','sales') and public.my_role() in ('admin','sales')
),
first_stage as (
  select distinct on (deal_id, to_stage) deal_id, to_stage, created_by, created_at
  from public.activities
  where kind = 'stage' and to_stage is not null and deal_id is not null
  order by deal_id, to_stage, created_at
),
adv as (
  select created_by u,
    count(*) n,
    sum(case to_stage when 'contacted' then 2 when 'qualified' then 3 when 'viewing' then 10
                      when 'negotiation' then 15 when 'reserved' then 30 when 'contract' then 40 else 0 end) pts
  from first_stage where created_at >= p_from and created_at < p_to and to_stage not in ('won','lost','new')
  group by 1
),
tch as (
  select created_by u,
    count(*) filter (where kind in ('call','whatsapp','meeting')) calls,
    count(*) filter (where kind = 'visit') visits
  from (select distinct created_by, kind, coalesce(contact_id, deal_id) k, date_trunc('day', created_at) d
        from public.activities
        where kind in ('call','whatsapp','meeting','visit') and created_at >= p_from and created_at < p_to
          and coalesce(contact_id, deal_id) is not null) x
  group by 1
),
nc as (
  select coalesce(assigned_to, created_by) u, count(*) n from public.contacts
  where type = 'buyer' and created_at >= p_from and created_at < p_to group by 1
),
ft as (
  select c.id, coalesce(c.assigned_to, c.created_by) u, c.created_at c0, min(a.created_at) t
  from public.contacts c
  join public.activities a on a.contact_id = c.id and a.kind in ('call','whatsapp','meeting','visit')
  where c.type = 'buyer' and c.created_at >= p_from and c.created_at < p_to
  group by 1, 2, 3
),
resp as (
  select u,
    percentile_cont(0.5) within group (order by extract(epoch from (t - c0)) / 60) m,
    count(*) filter (where t - c0 <= interval '1 hour') f1,
    count(*) filter (where t - c0 > interval '1 hour' and t - c0 <= interval '24 hours') f24
  from ft where t >= c0 group by u
),
won as (
  select coalesce(d.assigned_to, d.created_by) u, count(*) n, sum(coalesce(d.value, p.price, 0)) v
  from public.deals d left join public.properties p on p.id = d.property_id
  where d.stage = 'won' and coalesce(d.won_at, d.stage_changed_at, d.updated_at) >= p_from
    and coalesce(d.won_at, d.stage_changed_at, d.updated_at) < p_to
  group by 1
),
lst as (
  select coalesce(assigned_to, created_by) u, count(*) n from public.deals
  where stage = 'lost' and coalesce(stage_changed_at, updated_at) >= p_from and coalesce(stage_changed_at, updated_at) < p_to
  group by 1
),
tk as (
  select coalesce(assigned_to, created_by) u,
    count(*) filter (where due_at <= now()) due,
    count(*) filter (where due_at <= now() and done and done_at <= due_at + interval '2 hours') ok
  from public.tasks where due_at >= p_from and due_at < p_to group by 1
),
od as (
  select coalesce(assigned_to, created_by) u, count(*) n from public.tasks
  where not done and due_at < now() group by 1
),
agg as (
  select m.username, m.role,
    coalesce(won.n,0)::int wins, coalesce(lst.n,0)::int lost,
    case when public.is_admin() then coalesce(won.v,0) end revenue,
    coalesce(adv.n,0)::int advances, coalesce(adv.pts,0)::int adv_pts,
    coalesce(tch.calls,0)::int touches, coalesce(tch.visits,0)::int visits,
    coalesce(nc.n,0)::int new_clients,
    coalesce(resp.f1,0)::int fast_1h, coalesce(resp.f24,0)::int fast_24h, round(resp.m::numeric,1) resp_minutes,
    coalesce(tk.due,0)::int tasks_due, coalesce(tk.ok,0)::int tasks_ontime, coalesce(od.n,0)::int overdue
  from members m
  left join won on won.u = m.username left join lst on lst.u = m.username
  left join adv on adv.u = m.username left join tch on tch.u = m.username
  left join nc on nc.u = m.username left join resp on resp.u = m.username
  left join tk on tk.u = m.username left join od on od.u = m.username
)
select username, role,
  greatest(0, wins*100 + adv_pts + visits*8 + touches + new_clients*2 + fast_1h*5 + fast_24h*2 + tasks_ontime*2 - least(30, overdue*2))::int points,
  jsonb_build_object('sale', wins*100, 'stages', adv_pts, 'visits', visits*8, 'touches', touches,
                     'new', new_clients*2, 'speed', fast_1h*5 + fast_24h*2, 'ontime', tasks_ontime*2, 'late', -least(30, overdue*2)) breakdown,
  wins, lost, revenue, advances, touches, visits, new_clients, fast_1h, fast_24h, resp_minutes, tasks_due, tasks_ontime, overdue
from agg
order by 3 desc, wins desc, touches desc;
$$;

-- ================================================================
-- الاسم الظاهر وكلمة المرور من جوه النظام
-- اسم الدخول (sales1 مثلاً) ثابت لأنه مربوط بالعملاء والصفقات،
-- والاسم الظاهر (سارة محمد مثلاً) كل عضو يغيّره بنفسه.
-- ================================================================
alter table public.profiles add column if not exists display_name text;

-- كل عضو يغيّر اسمه هو بس، ومايقدرش يلمس صلاحيته
create or replace function public.set_my_name(n text) returns text
language plpgsql security definer set search_path = public as $$
declare v text := nullif(btrim(regexp_replace(coalesce(n,''), '\s+', ' ', 'g')), '');
begin
  if public.my_role() not in ('admin','sales') then raise exception 'not allowed'; end if;
  if v is not null and (char_length(v) < 2 or char_length(v) > 40) then
    raise exception 'الاسم لازم يكون من 2 لـ 40 حرف';
  end if;
  update public.profiles set display_name = v where user_id = auth.uid();
  return v;
end $$;

-- أسماء الفريق الظاهرة (من غير أي بيانات تانية) عشان تظهر في الترتيب والسجلات
create or replace function public.team_names() returns table (username text, display_name text)
language sql stable security definer set search_path = public as $$
  select p.username, p.display_name from public.profiles p
  where public.my_role() in ('admin','sales') $$;
