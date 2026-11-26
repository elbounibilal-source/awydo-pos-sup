-- Awydo — Supabase schema (run once in Supabase → SQL Editor → New query → Run)
-- Design: tables are locked (RLS on, no policies). The app can only call two
-- functions, and every call must carry the shop code + shop password.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.pos_shops (
  shop_id         text primary key check (shop_id ~ '^[a-z0-9-]{3,40}$'),
  key_hash        text not null,
  name            text,
  snapshot        jsonb,
  snapshot_device text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.pos_events (
  id          bigserial primary key,
  shop_id     text not null references public.pos_shops(shop_id) on delete cascade,
  device      text,
  op          jsonb not null,
  client_ts   timestamptz,
  received_at timestamptz not null default now()
);
create index if not exists pos_events_shop_idx on public.pos_events (shop_id, received_at desc);

alter table public.pos_shops  enable row level security;
alter table public.pos_events enable row level security;
-- No policies on purpose: direct reads/writes with the public key are refused.

-- Push: records the pending operations of one device and stores the latest full copy.
create or replace function public.pos_push(p_shop text, p_key text, p_device text, p_events jsonb, p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text; n int := 0;
begin
  if p_key is null or length(p_key) < 8 then raise exception 'shop password too short'; end if;
  select key_hash into h from pos_shops where shop_id = p_shop;
  if h is null then
    insert into pos_shops (shop_id, key_hash) values (p_shop, crypt(p_key, gen_salt('bf')));
  elsif h <> crypt(p_key, h) then
    raise exception 'wrong shop password' using errcode = '28000';
  end if;
  insert into pos_events (shop_id, device, op, client_ts)
    select p_shop, p_device, e->'op', to_timestamp((e->>'t')::double precision / 1000)
    from jsonb_array_elements(coalesce(p_events, '[]'::jsonb)) e;
  get diagnostics n = row_count;
  if p_snapshot is not null then
    update pos_shops set snapshot = p_snapshot, snapshot_device = p_device, updated_at = now(),
                         name = p_snapshot->'shop'->>'name'
     where shop_id = p_shop;
  end if;
  return jsonb_build_object('ok', true, 'events', n, 'at', now());
end $$;

-- Pull: returns the latest full copy (to restore on another phone).
create or replace function public.pos_pull(p_shop text, p_key text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r pos_shops;
begin
  select * into r from pos_shops where shop_id = p_shop;
  if r.shop_id is null then return jsonb_build_object('snapshot', null); end if;
  if r.key_hash <> crypt(p_key, r.key_hash) then raise exception 'wrong shop password' using errcode = '28000'; end if;
  return jsonb_build_object('snapshot', r.snapshot, 'updated_at', r.updated_at, 'device', r.snapshot_device);
end $$;

revoke all on function public.pos_push(text, text, text, jsonb, jsonb) from public;
revoke all on function public.pos_pull(text, text) from public;
grant execute on function public.pos_push(text, text, text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.pos_pull(text, text) to anon, authenticated;
