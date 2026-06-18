-- ============================================================
-- 江西饭店 · 后台可编辑内容 (在 Supabase SQL Editor 跑一次)
-- 依赖：已先跑过 schema.sql（优惠券）。本脚本可重复运行。
-- ============================================================

-- ---------- 1. 站点内容（单行 JSON） ----------
create table if not exists public.site_content (
  id         int primary key default 1,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now(),
  constraint site_content_single check (id = 1)
);

-- 初始内容（与当前页面一致；关于/创业年份留空，由后台填）
insert into public.site_content(id, data) values (1, '{
  "hero_sub_zh": "瓦罐煨汤、藜蒿腊肉、辣得地道。把江西的烟火气，端到你面前的这张桌上。",
  "hero_sub_ja": "土鍋でじっくり煮込んだスープ、青菜と干し肉の炒め、本場の辛さ。江西の温かな食卓を、そのままこのテーブルへ。",
  "hours_zh": "11:00–15:00 / 17:00–22:00\n全年无休",
  "hours_ja": "11:00–15:00 / 17:00–22:00\n年中無休",
  "address_zh": "〒171-0021 东京都丰岛区西池袋 1-44-4\nHF西池袋大厦 3F",
  "address_ja": "〒171-0021 東京都豊島区西池袋 1-44-4\nエイチエフ西池袋ビル 3F",
  "tel": "03-5810-2203",
  "access_zh": "JR / 地铁「池袋站」西口 · 步行约 3 分钟",
  "access_ja": "JR・各線「池袋駅」西口より徒歩約 3 分",
  "map_query": "〒171-0021 東京都豊島区西池袋1-44-4",
  "coupon_enabled": true,
  "coupon_offer_zh": "到店专享优惠",
  "coupon_offer_ja": "ご来店限定特典",
  "announce_enabled": false,
  "announce_zh": "",
  "announce_ja": ""
}'::jsonb)
on conflict (id) do nothing;

alter table public.site_content enable row level security;
drop policy if exists site_content_read  on public.site_content;
drop policy if exists site_content_write on public.site_content;
create policy site_content_read  on public.site_content for select using (true);                     -- 任何人可读
create policy site_content_write on public.site_content for all to authenticated using (true) with check (true); -- 登录后可改

-- ---------- 2. 菜品 ----------
create table if not exists public.dishes (
  id         uuid primary key default gen_random_uuid(),
  sort       int default 0,
  tag_zh     text, tag_ja text,
  glyph      text,                 -- 无图时显示的大字，如 汤/腊
  name_zh    text, name_ja text, name_en text,
  desc_zh    text, desc_ja text,
  photo_url  text,
  visible    boolean default true,
  created_at timestamptz default now()
);

alter table public.dishes enable row level security;
drop policy if exists dishes_read  on public.dishes;
drop policy if exists dishes_write on public.dishes;
create policy dishes_read  on public.dishes for select using (true);
create policy dishes_write on public.dishes for all to authenticated using (true) with check (true);

-- 初始 6 道菜（仅当表为空时灌入）
insert into public.dishes (sort, tag_zh, tag_ja, glyph, name_zh, name_ja, name_en, desc_zh, desc_ja)
select * from (values
  (1,'招牌','看板','汤','瓦罐煨汤','土鍋煮込みスープ','Wǎguàn Soup','陶罐炭火慢煨数小时，汤色清亮、入口醇厚，南昌人的早餐魂。','炭火で何時間も煮込んだ滋味深い一椀。南昌の朝の定番。'),
  (2,null,null,'腊','藜蒿炒腊肉','ヨモギと干し肉炒め','Líhāo & Cured Pork','鄱阳湖畔的春日野菜，配上自家烟熏腊肉，清香与咸鲜碰撞。','鄱陽湖のほとりの春の野草と自家製干し肉、香りと旨味の競演。'),
  (3,null,null,'粉','南昌拌粉','南昌混ぜビーフン','Nanchang Mixed Noodles','劲道米粉拌上特调酱料与花生萝卜干，一碗下去通身爽利。','コシのある米粉に特製ダレ、ピーナッツと漬物。さっぱり爽快。'),
  (4,'名菜','名物','鸡','三杯鸡','三杯鶏','Three-Cup Chicken','一杯酒、一杯酱油、一杯油，慢火收汁，香气扑鼻。','酒・醤油・油を各一杯、弱火で煮詰めた香り高い一品。'),
  (5,null,null,'蒸','米粉蒸肉','米粉蒸し肉','Steamed Pork in Rice Flour','五花肉裹上炒香米粉，蒸到软糯，肥而不腻。','炒り米粉をまとった豚バラを蒸し上げ、とろける柔らかさ。'),
  (6,'够辣','辛口','辣','余干辣椒炒肉','唐辛子と豚肉炒め','Yúgān Pepper & Pork','江西人下饭的灵魂，青辣椒的鲜辣，越吃越上头。','江西人のご飯のお供。青唐辛子の鮮烈な辛さがクセになる。')
) as v
where not exists (select 1 from public.dishes);

-- ---------- 3. 菜品照片存储桶（公开读） ----------
insert into storage.buckets (id, name, public)
values ('dish-photos','dish-photos', true)
on conflict (id) do nothing;

drop policy if exists dishphotos_read  on storage.objects;
drop policy if exists dishphotos_write on storage.objects;
create policy dishphotos_read  on storage.objects for select using (bucket_id = 'dish-photos');
create policy dishphotos_write on storage.objects for all to authenticated
  using (bucket_id = 'dish-photos') with check (bucket_id = 'dish-photos');

-- ============================================================
-- 跑完后：在 Authentication → Users → Add user 建一个后台账号
-- （填邮箱+密码，勾 Auto Confirm User），就能登录 admin.html 了。
-- ============================================================
