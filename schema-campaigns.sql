-- ============================================================
-- 江西饭店 · 多个优惠活动（campaigns）
-- 在 Supabase SQL Editor 跑一次。依赖前面的 schema.sql / schema-admin.sql / schema-coupon-code.sql。
-- 可重复运行。
-- ============================================================

-- 1) 活动表
create table if not exists public.campaigns (
  id           uuid primary key default gen_random_uuid(),
  sort         int default 0,
  title_zh     text, title_ja text,
  offer_zh     text, offer_ja text,
  code         text,                 -- 暗号（服务端，匿名读不到）
  require_code boolean default false,
  enabled      boolean default true,
  created_at   timestamptz default now()
);

alter table public.campaigns enable row level security;
drop policy if exists campaigns_admin on public.campaigns;
-- 仅登录后台用户可读写（含暗号）；匿名【没有】任何 select 策略 => 读不到这张表 => 暗号不外泄
create policy campaigns_admin on public.campaigns for all to authenticated using (true) with check (true);

-- coupons 记录归属哪个活动
alter table public.coupons add column if not exists campaign_id uuid;

-- 2) 列出启用中的活动（只回安全字段，绝不含暗号），匿名可调
create or replace function public.list_active_campaigns()
returns json language plpgsql security definer set search_path = public as $$
begin
  return coalesce((
    select json_agg(json_build_object(
      'id', id, 'title_zh', title_zh, 'title_ja', title_ja,
      'offer_zh', offer_zh, 'offer_ja', offer_ja, 'require_code', require_code
    ) order by sort, created_at)
    from campaigns where enabled = true
  ), '[]'::json);
end; $$;
grant execute on function public.list_active_campaigns() to anon, authenticated;

-- 3) 领取（按活动校验暗号），返回 json
drop function if exists public.claim_coupon(text, text);
drop function if exists public.claim_coupon(text, text, text);
drop function if exists public.claim_coupon(uuid, text);
drop function if exists public.claim_coupon(uuid, text, text);
create or replace function public.claim_coupon(
  p_campaign_id uuid,
  p_code   text default null,
  p_source text default 'web'
) returns json
language plpgsql security definer set search_path = public as $$
declare c campaigns%rowtype; v_code text; v_offer text;
begin
  select * into c from campaigns where id = p_campaign_id and enabled = true;
  if not found then return json_build_object('ok', false, 'status', 'not_found'); end if;
  if c.require_code and c.code is not null and length(btrim(c.code)) > 0 then
    if p_code is null or upper(btrim(p_code)) <> upper(btrim(c.code)) then
      return json_build_object('ok', false, 'status', 'bad_code');
    end if;
  end if;
  v_offer := coalesce(c.title_zh,'')
           || case when coalesce(c.offer_zh,'')<>'' then ' · '||c.offer_zh else '' end;
  loop
    v_code := 'JX-' || upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
    exit when not exists (select 1 from coupons cc where cc.code = v_code);
  end loop;
  insert into coupons(code, offer, source, campaign_id)
    values (v_code, v_offer, coalesce(p_source,'web'), p_campaign_id);
  return json_build_object('ok', true, 'code', v_code);
end; $$;
grant execute on function public.claim_coupon(uuid, text, text) to anon, authenticated;

-- 4) 把旧的单一优惠券设置迁移成一个活动（仅当 campaigns 为空时）
insert into public.campaigns (sort, title_zh, title_ja, offer_zh, offer_ja, code, require_code, enabled)
select 1,
  coalesce(nullif(d->>'coupon_title_zh',''),'到店优惠券'),
  coalesce(nullif(d->>'coupon_title_ja',''),'来店クーポン'),
  coalesce(nullif(d->>'coupon_offer_zh',''),'到店专享优惠'),
  coalesce(nullif(d->>'coupon_offer_ja',''),'ご来店限定特典'),
  (select coupon_code from app_config where id = 1),
  coalesce((d->>'coupon_require_code')::boolean, false),
  coalesce((d->>'coupon_enabled')::boolean, true)
from (select data as d from public.site_content where id = 1) s
where not exists (select 1 from public.campaigns);
