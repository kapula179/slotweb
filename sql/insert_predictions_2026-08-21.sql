-- 2026-08-19、2026-08-20の実績から2026-08-21の予想を作成する。
-- 対象はマイジャグラーのみ。
--
-- 判定優先順位:
--   1. 前日がREG 1/300以下、BIG 1/300以上 → 不発据え置き候補
--   2. 2日間のいずれかがREG 1/300以下 → 回避候補
--   3. 2日間ともREG 1/300超       → 上げ候補
-- 各日の回転数が5,000未満なら、その日の判定には使用しない。

with daily as (
  select
    s.day::date as data_day,
    s.shopid,
    s.slotid::text as slotid,
    s.name,
    nullif(replace(trim(s.count::text), ',', ''), '')::numeric as spins,
    nullif(replace(trim(s.big::text), ',', ''), '')::numeric as big,
    nullif(replace(trim(s.reg::text), ',', ''), '')::numeric as reg,
    nullif(replace(trim(s.medal::text), ',', ''), '')::numeric as medal,
    case
      when nullif(replace(trim(s.reg::text), ',', ''), '')::numeric > 0
        then nullif(replace(trim(s.count::text), ',', ''), '')::numeric
          / nullif(replace(trim(s.reg::text), ',', ''), '')::numeric
      else null
    end as reg_denominator,
    case
      when nullif(replace(trim(s.big::text), ',', ''), '')::numeric > 0
        then nullif(replace(trim(s.count::text), ',', ''), '')::numeric
          / nullif(replace(trim(s.big::text), ',', ''), '')::numeric
      else null
    end as big_denominator
  from public.slot as s
  where s.day::date in (date '2026-08-19', date '2026-08-20')
    and s.name ilike '%マイジャグラー%'
),
two_days as (
  select
    shopid,
    slotid,
    max(name) filter (where data_day = date '2026-08-20') as name,

    max(spins) filter (where data_day = date '2026-08-19') as spins_19,
    max(big) filter (where data_day = date '2026-08-19') as big_19,
    max(reg) filter (where data_day = date '2026-08-19') as reg_19,
    max(reg_denominator) filter (where data_day = date '2026-08-19') as reg_denominator_19,

    max(spins) filter (where data_day = date '2026-08-20') as spins_20,
    max(big) filter (where data_day = date '2026-08-20') as big_20,
    max(reg) filter (where data_day = date '2026-08-20') as reg_20,
    max(medal) filter (where data_day = date '2026-08-20') as medal_20,
    max(reg_denominator) filter (where data_day = date '2026-08-20') as reg_denominator_20,
    max(big_denominator) filter (where data_day = date '2026-08-20') as big_denominator_20
  from daily
  group by shopid, slotid
),
classified as (
  select
    *,
    case
      -- 前日のREGは良いがBIGが付かなかった台を最優先にする。
      when spins_20 >= 5000
        and reg_20 > 0
        and reg_denominator_20 <= 300
        and (big_20 = 0 or big_denominator_20 >= 300)
        then 'hold_misfire'

      -- 2日間のどちらかに高設定傾向があれば回避する。
      when (
        spins_19 >= 5000
        and reg_19 > 0
        and reg_denominator_19 <= 300
      ) or (
        spins_20 >= 5000
        and reg_20 > 0
        and reg_denominator_20 <= 300
      )
        then 'avoid_recent_high'

      -- 2日間とも十分回され、どちらもREGが1/300を超えた台。
      when spins_19 >= 5000
        and spins_20 >= 5000
        and (reg_19 = 0 or reg_denominator_19 > 300)
        and (reg_20 = 0 or reg_denominator_20 > 300)
        then 'raise_candidate'

      else null
    end as prediction_type
  from two_days
  -- 台の入れ替えを避けるため、前日にも存在する台だけを対象にする。
  where name is not null
)
insert into public.predictions (
  prediction_day,
  source_through_day,
  shopid,
  slotid,
  name,
  score,
  positive_probability,
  grade,
  reasons,
  model_version
)
select
  date '2026-08-21',
  date '2026-08-20',
  shopid,
  slotid,
  name,
  case prediction_type
    when 'hold_misfire' then 100
    when 'raise_candidate' then 50
    when 'avoid_recent_high' then 0
  end as score,
  null as positive_probability,
  prediction_type as grade,
  jsonb_build_array(
    jsonb_build_object(
      'day', '2026-08-19',
      'spins', spins_19,
      'reg_denominator', round(reg_denominator_19, 1)
    ),
    jsonb_build_object(
      'day', '2026-08-20',
      'spins', spins_20,
      'reg_denominator', round(reg_denominator_20, 1),
      'big_denominator', round(big_denominator_20, 1),
      'medal', medal_20
    )
  ) as reasons,
  'myjuggler_2day_v1' as model_version
from classified
where prediction_type is not null
on conflict (prediction_day, shopid, slotid, model_version)
do update set
  source_through_day = excluded.source_through_day,
  name = excluded.name,
  score = excluded.score,
  positive_probability = excluded.positive_probability,
  grade = excluded.grade,
  reasons = excluded.reasons,
  updated_at = now();

-- 挿入結果の確認
select
  prediction_day,
  shopid,
  grade,
  count(*) as machines
from public.predictions
where prediction_day = date '2026-08-21'
  and model_version = 'myjuggler_2day_v1'
group by prediction_day, shopid, grade
order by shopid, grade;
