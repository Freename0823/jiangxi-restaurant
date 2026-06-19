-- ============================================================
-- 江西饭店 · 暗号领券（服务端校验）+ 优惠券活动
-- 在 Supabase SQL Editor 跑一次。依赖 schema.sql + schema-admin.sql。可重复运行。
-- ============================================================

-- 1) app_config 增加暗号字段（存服务端，匿名读不到）
alter table public.app_config add column if not exists coupon_code text;

-- 2) 重建 claim_coupon：支持暗号校验，返回 json
drop function if exists public.claim_coupon(text, text);
drop function if exists public.claim_coupon(text, text, text);
create or replace function public.claim_coupon(
  p_offer  text default null,
  p_source text default 'web',
  p_code   text default null
) returns json
language plpgsql security definer set search_path = public as $$
declare v_code text; v_pass text;
begin
  select coupon_code into v_pass from app_config where id = 1;
  -- 设了暗号才校验；没设直接放行
  if v_pass is not null and length(btrim(v_pass)) > 0 then
    if p_code is null or upper(btrim(p_code)) <> upper(btrim(v_pass)) then
      return json_build_object('ok', false, 'status', 'bad_code');
    end if;
  end if;
  loop
    v_code := 'JX-' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 6));
    exit when not exists (select 1 from coupons c where c.code = v_code);
  end loop;
  insert into coupons(code, offer, source) values (v_code, p_offer, coalesce(p_source,'web'));
  return json_build_object('ok', true, 'code', v_code, 'offer', p_offer);
end; $$;
grant execute on function public.claim_coupon(text, text, text) to anon;

-- 3) 设置暗号（仅登录后台用户可调用；匿名不可）
create or replace function public.set_coupon_code(p_code text)
returns json language plpgsql security definer set search_path = public as $$
begin
  update app_config set coupon_code = nullif(btrim(p_code), '') where id = 1;
  return json_build_object('ok', true);
end; $$;
revoke all on function public.set_coupon_code(text) from public, anon;  -- Supabase 默认给 anon 授权，必须显式收回
grant execute on function public.set_coupon_code(text) to authenticated;

-- 4) 读取暗号（仅登录后台用户，给后台表单回显用）
create or replace function public.get_coupon_code()
returns json language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select coupon_code into v from app_config where id = 1;
  return json_build_object('code', coalesce(v, ''));
end; $$;
revoke all on function public.get_coupon_code() from public, anon;
grant execute on function public.get_coupon_code() to authenticated;
