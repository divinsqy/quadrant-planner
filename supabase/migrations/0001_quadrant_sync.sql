create table if not exists public.entity_state (
  user_id uuid not null,
  entity_kind text not null,
  entity_id text not null,
  revision bigint not null default 0,
  state jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, entity_kind, entity_id)
);

create table if not exists public.entity_events (
  user_id uuid not null,
  event_id text not null,
  entity_kind text not null,
  entity_id text not null,
  revision bigint not null,
  event jsonb not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

create table if not exists public.batch_receipts (
  user_id uuid not null,
  batch_id text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, batch_id)
);

create table if not exists public.change_feed (
  seq bigserial primary key,
  user_id uuid not null,
  entity_kind text not null,
  entity_id text not null,
  revision bigint not null,
  state jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.entity_state enable row level security;
alter table public.entity_events enable row level security;
alter table public.batch_receipts enable row level security;
alter table public.change_feed enable row level security;

drop policy if exists entity_state_owner on public.entity_state;
create policy entity_state_owner on public.entity_state
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists entity_events_owner on public.entity_events;
create policy entity_events_owner on public.entity_events
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists batch_receipts_owner on public.batch_receipts;
create policy batch_receipts_owner on public.batch_receipts
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists change_feed_owner on public.change_feed;
create policy change_feed_owner on public.change_feed
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.apply_entity_batch(p_batch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  bid text := p_batch->>'batch_id';
  kind text := p_batch->>'entity_kind';
  eid text := p_batch->>'entity_id';
  base_rev bigint := coalesce((p_batch->>'base_revision')::bigint, 0);
  current_rev bigint := 0;
  next_rev bigint;
  last_after jsonb;
  receipt jsonb;
  ev jsonb;
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select response into receipt
    from public.batch_receipts
    where user_id = uid and batch_id = bid;
  if receipt is not null then
    return receipt;
  end if;

  select revision into current_rev
    from public.entity_state
    where user_id = uid and entity_kind = kind and entity_id = eid
    for update;
  current_rev := coalesce(current_rev, 0);

  if current_rev <> base_rev then
    receipt := jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'REVISION_CONFLICT',
        'cloud', (select state from public.entity_state
                  where user_id = uid and entity_kind = kind and entity_id = eid)
      )
    );
    insert into public.batch_receipts(user_id,batch_id,response)
      values(uid,bid,receipt)
      on conflict do nothing;
    return receipt;
  end if;

  next_rev := current_rev + 1;
  for ev in select * from jsonb_array_elements(coalesce(p_batch->'events','[]'::jsonb))
  loop
    last_after := ev->'after';
    insert into public.entity_events(user_id,event_id,entity_kind,entity_id,revision,event)
      values(uid,ev->>'id',kind,eid,next_rev,ev)
      on conflict (user_id,event_id) do nothing;
  end loop;

  if last_after is null then
    return jsonb_build_object('ok', false, 'error', jsonb_build_object('code','EMPTY_BATCH'));
  end if;

  insert into public.entity_state(user_id,entity_kind,entity_id,revision,state,updated_at)
    values(uid,kind,eid,next_rev,last_after,now())
    on conflict (user_id,entity_kind,entity_id)
    do update set revision=excluded.revision,state=excluded.state,updated_at=excluded.updated_at;

  insert into public.change_feed(user_id,entity_kind,entity_id,revision,state)
    values(uid,kind,eid,next_rev,last_after);

  receipt := jsonb_build_object('ok',true,'revision',next_rev);
  insert into public.batch_receipts(user_id,batch_id,response)
    values(uid,bid,receipt)
    on conflict (user_id,batch_id) do update set response=excluded.response;
  return receipt;
end;
$$;

create or replace function public.pull_changes(p_after_seq bigint, p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  changes jsonb;
  next_cursor bigint;
  head_seq bigint;
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select coalesce(jsonb_agg(x order by (x->>'seq')::bigint), '[]'::jsonb)
  into changes
  from (
    select jsonb_build_object(
      'seq', seq,
      'entity_kind', entity_kind,
      'entity_id', entity_id,
      'revision', revision,
      'state', state
    ) x
    from public.change_feed
    where user_id = uid and seq > p_after_seq
    order by seq
    limit greatest(1, least(p_limit, 500))
  ) q;

  select coalesce(max((x->>'seq')::bigint), p_after_seq)
  into next_cursor
  from jsonb_array_elements(changes) x;

  select coalesce(max(seq), next_cursor)
  into head_seq
  from public.change_feed
  where user_id = uid;

  return jsonb_build_object(
    'ok', true,
    'changes', changes,
    'next_cursor', next_cursor,
    'head_seq', head_seq
  );
end;
$$;

grant execute on function public.apply_entity_batch(jsonb) to authenticated;
grant execute on function public.pull_changes(bigint,int) to authenticated;
