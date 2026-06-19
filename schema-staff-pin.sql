-- ============================================================
-- 江西饭店 · 在后台设置店员核销 PIN
-- 在 Supabase SQL Editor 跑一次（只需一次）。之后就能在 admin.html 里改 PIN。
-- 仅登录后台用户可调用；匿名不可。
-- ============================================================

create or replace function public.set_staff_pin(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if btrim(coalesce(p_pin,'')) = '' then
    return json_build_object('ok', false, 'status', 'empty');   -- 不允许空 PIN
  end if;
  update app_config set staff_pin = btrim(p_pin) where id = 1;
  return json_build_object('ok', true);
end; $$;
revoke all on function public.set_staff_pin(text) from public;
grant execute on function public.set_staff_pin(text) to authenticated;

create or replace function public.get_staff_pin()
returns json language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select staff_pin into v from app_config where id = 1;
  return json_build_object('pin', coalesce(v, ''));
end; $$;
revoke all on function public.get_staff_pin() from public;
grant execute on function public.get_staff_pin() to authenticated;
