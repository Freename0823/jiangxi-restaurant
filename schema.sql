-- ============================================================
-- 江西饭店 · 优惠券领取 + 核销 后端 (Supabase / PostgreSQL)
-- 用法：登录 Supabase 控制台 → 左侧 SQL Editor → 新建 query →
--       把本文件整段粘进去 → 点 Run。一次跑完即可。
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 优惠券表 ----------
create table if not exists public.coupons (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,        -- 短码，如 JX-A3F9K2
  offer       text,                        -- 优惠内容（领取时记录）
  source      text default 'web',          -- 来源渠道，如 tiktok / instagram
  claimed_at  timestamptz default now(),
  redeemed    boolean default false,       -- 是否已核销
  redeemed_at timestamptz
);

-- 关闭直接读写：匿名 key 不能直接 select/insert/update 本表，
-- 只能通过下面的 RPC 函数操作 → 券状态偷不了也改不了。
alter table public.coupons enable row level security;

-- ---------- 店员配置（单行，存核销 PIN） ----------
create table if not exists public.app_config (
  id        int primary key default 1,
  staff_pin text not null default 'CHANGE_ME',
  constraint single_row check (id = 1)
);
insert into public.app_config(id, staff_pin)
  values (1, 'CHANGE_ME') on conflict (id) do nothing;
alter table public.app_config enable row level security;   -- 无策略 => 匿名读不到 PIN

-- ============================================================
-- RPC 1：领取优惠券（任何访客都能调用）
-- ============================================================
create or replace function public.claim_coupon(
  p_offer text default null,
  p_source text default 'web'
) returns table(code text, offer text)
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  loop
    v_code := 'JX-' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 6));
    exit when not exists (select 1 from coupons c where c.code = v_code);
  end loop;
  insert into coupons(code, offer, source) values (v_code, p_offer, coalesce(p_source,'web'));
  return query select v_code, p_offer;
end; $$;

-- ============================================================
-- RPC 2：核销（必须带正确店员 PIN）
-- ============================================================
create or replace function public.redeem_coupon(
  p_code text,
  p_pin text
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_pin text;
  v_row coupons%rowtype;
begin
  select staff_pin into v_pin from app_config where id = 1;
  if p_pin is distinct from v_pin then
    return json_build_object('ok', false, 'status', 'bad_pin');
  end if;

  select * into v_row from coupons where code = upper(trim(p_code));
  if not found then
    return json_build_object('ok', false, 'status', 'not_found');
  end if;
  if v_row.redeemed then
    return json_build_object('ok', false, 'status', 'already',
                             'redeemed_at', v_row.redeemed_at);
  end if;

  update coupons set redeemed = true, redeemed_at = now() where id = v_row.id;
  return json_build_object('ok', true, 'status', 'redeemed',
                           'code', v_row.code, 'offer', v_row.offer,
                           'source', v_row.source);
end; $$;

-- ============================================================
-- RPC 3：统计（必须带正确店员 PIN）—— 看活动效果
-- ============================================================
create or replace function public.coupon_stats(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_pin text;
begin
  select staff_pin into v_pin from app_config where id = 1;
  if p_pin is distinct from v_pin then
    return json_build_object('ok', false);
  end if;
  return (select json_build_object(
    'ok', true,
    'claimed',        count(*),
    'redeemed',       count(*) filter (where redeemed),
    'today_claimed',  count(*) filter (where claimed_at::date  = current_date),
    'today_redeemed', count(*) filter (where redeemed and redeemed_at::date = current_date)
  ) from coupons);
end; $$;

-- ============================================================
-- RPC 4：查询券状态（顾客页加载时用，无需 PIN）
-- ============================================================
create or replace function public.coupon_status(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_row coupons%rowtype;
begin
  select * into v_row from coupons where code = upper(trim(p_code));
  if not found then return json_build_object('found', false); end if;
  return json_build_object('found', true, 'redeemed', v_row.redeemed,
                           'redeemed_at', v_row.redeemed_at, 'offer', v_row.offer);
end; $$;

-- ============================================================
-- RPC 5：顾客自助使用（无需 PIN，请在店员当面确认后点击）
--        每张券只能成功一次，之后再调用都会返回 already。
-- ============================================================
create or replace function public.use_coupon(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_row coupons%rowtype;
begin
  select * into v_row from coupons where code = upper(trim(p_code));
  if not found then
    return json_build_object('ok', false, 'status', 'not_found');
  end if;
  if v_row.redeemed then
    return json_build_object('ok', false, 'status', 'already', 'redeemed_at', v_row.redeemed_at);
  end if;
  update coupons set redeemed = true, redeemed_at = now() where id = v_row.id;
  return json_build_object('ok', true, 'status', 'redeemed', 'redeemed_at', now());
end; $$;

-- ---------- 授权匿名 key 调用这些函数 ----------
grant execute on function public.claim_coupon(text, text)  to anon;
grant execute on function public.coupon_status(text)       to anon;  -- 查状态
grant execute on function public.use_coupon(text)          to anon;  -- 顾客自助核销
grant execute on function public.redeem_coupon(text, text) to anon;  -- 店员后备核销
grant execute on function public.coupon_stats(text)        to anon;  -- 店员看统计

-- ============================================================
-- ⚠️ 部署后务必改掉默认 PIN（换成你自己的，店员才知道）：
--   update public.app_config set staff_pin = '你的核销密码' where id = 1;
-- ============================================================
