-- ============================================================
-- 江西饭店 · 安全修复：禁止匿名(anon)调用敏感函数
-- 背景：Supabase 默认给 anon 角色授予新函数执行权，只 revoke from public 不够，
--       必须显式 revoke from anon。否则客人能读/改 店员PIN、暗号。
-- 用 DO 块包裹：函数不存在就跳过，不报错。在 SQL Editor 跑一次。
-- ============================================================

-- 店员 PIN（一定存在）
do $$
begin
  revoke all on function public.get_staff_pin()        from public, anon;
  revoke all on function public.set_staff_pin(text)    from public, anon;
  grant execute on function public.get_staff_pin()     to authenticated;
  grant execute on function public.set_staff_pin(text) to authenticated;
exception when undefined_function then null;
end $$;

-- 旧版单一暗号函数（多数项目没装，没装就跳过）
do $$
begin
  revoke all on function public.get_coupon_code()        from public, anon;
  revoke all on function public.set_coupon_code(text)    from public, anon;
  grant execute on function public.get_coupon_code()     to authenticated;
  grant execute on function public.set_coupon_code(text) to authenticated;
exception when undefined_function then null;
end $$;
