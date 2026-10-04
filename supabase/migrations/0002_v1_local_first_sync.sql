-- Separate from the v0 event-batch contract. Only authenticated owners can
-- read their data. Writes pass through atomic, idempotent RPC functions.
create table public.v1_entity_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_kind text not null, entity_id text not null,
  revision bigint not null, payload jsonb not null,
  restored boolean not null default false,
  primary key(user_id, entity_kind, entity_id)
);
create table public.v1_operation_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id text not null, response jsonb not null,
  primary key(user_id, operation_id)
);
create table public.v1_change_feed (
  sequence bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_kind text not null, entity_id text not null,
  revision bigint not null, payload jsonb not null,
  restored boolean not null default false
);
create index v1_change_feed_owner_cursor on public.v1_change_feed(user_id,sequence);
alter table public.v1_entity_state enable row level security;
alter table public.v1_operation_receipts enable row level security;
alter table public.v1_change_feed enable row level security;
create policy v1_state_owner on public.v1_entity_state for select to authenticated using(user_id=auth.uid());
create policy v1_receipt_owner on public.v1_operation_receipts for select to authenticated using(user_id=auth.uid());
create policy v1_feed_owner on public.v1_change_feed for select to authenticated using(user_id=auth.uid());
revoke all on public.v1_entity_state,public.v1_operation_receipts,public.v1_change_feed from anon,authenticated;
grant select on public.v1_entity_state,public.v1_operation_receipts,public.v1_change_feed to authenticated;

create function public.apply_v1_operation(p_operation jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  oid text := p_operation->>'operation_id';
  kind text := p_operation->>'entity_kind';
  eid text := p_operation->>'entity_id';
  base_revision bigint := (p_operation->>'base_revision')::bigint;
  incoming jsonb := p_operation->'payload';
  current_row public.v1_entity_state%rowtype;
  receipt jsonb;
  entity jsonb;
  next_revision bigint;
  old_deleted boolean;
  new_deleted boolean;
  restore_requested boolean := coalesce((p_operation->>'explicit_restore')::boolean,false);
  restored boolean := false;
begin
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if oid is null or length(oid)=0 or length(oid)>128 or eid is null or length(eid)=0 or length(eid)>1024
     or base_revision is null or base_revision<0 or jsonb_typeof(incoming) is distinct from 'object'
     or kind is null or kind not in ('projects','milestones','tasks','tags','subtasks','dependencies','task_tags',
       'activity_events','preferences','work_schedule_windows','weekend_overrides','daily_plan_blocks',
       'planner_task_overrides','focus_sessions','weekly_reports','weekly_notes','report_style_profiles','milestone_history')
     or octet_length(incoming::text)>10485760 then raise exception 'INVALID_OPERATION'; end if;
  if jsonb_path_exists(incoming,'$.**.access_token') or jsonb_path_exists(incoming,'$.**.refresh_token')
     or jsonb_path_exists(incoming,'$.**.authorization') then raise exception 'CREDENTIAL_FIELD_REJECTED'; end if;
  -- An operation ID is immutable, including when its response was lost.
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':operation:'||oid,0));
  select response into receipt from public.v1_operation_receipts where user_id=uid and operation_id=oid;
  if receipt is not null then return receipt; end if;
  -- Serialize each owner's feed through commit, so a pull cursor cannot skip a
  -- lower sequence from a still-uncommitted operation on another entity.
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':feed',0));
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':entity:'||kind||':'||eid,0));
  select * into current_row from public.v1_entity_state where user_id=uid and entity_kind=kind and entity_id=eid for update;
  old_deleted := current_row.payload->>'deleted_at' is not null or coalesce(current_row.payload->'_deleted' in ('true'::jsonb,'1'::jsonb),false);
  new_deleted := incoming->>'deleted_at' is not null or coalesce(incoming->'_deleted' in ('true'::jsonb,'1'::jsonb),false);
  if coalesce(current_row.revision,0)<>base_revision or (old_deleted and not new_deleted and not restore_requested) then
    entity := jsonb_build_object('entity_kind',kind,'entity_id',eid,'revision',current_row.revision,'payload',current_row.payload,'restored',current_row.restored);
    receipt := jsonb_build_object('accepted',false,'entity',entity);
  else
    next_revision := coalesce(current_row.revision,0)+1;
    restored := coalesce(old_deleted,false) and not new_deleted and restore_requested;
    insert into public.v1_entity_state(user_id,entity_kind,entity_id,revision,payload,restored)
      values(uid,kind,eid,next_revision,incoming,restored)
      on conflict(user_id,entity_kind,entity_id) do update set revision=excluded.revision,payload=excluded.payload,restored=excluded.restored;
    insert into public.v1_change_feed(user_id,entity_kind,entity_id,revision,payload,restored)
      values(uid,kind,eid,next_revision,incoming,restored);
    entity := jsonb_build_object('entity_kind',kind,'entity_id',eid,'revision',next_revision,'payload',incoming,'restored',restored);
    receipt := jsonb_build_object('accepted',true,'entity',entity);
  end if;
  insert into public.v1_operation_receipts(user_id,operation_id,response) values(uid,oid,receipt);
  return receipt;
end;
$$;

create function public.pull_v1_changes(p_after_seq bigint,p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  result jsonb;
  next_cursor bigint;
  limit_count integer := greatest(1,least(coalesce(p_limit,100),500));
begin
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_after_seq is null or p_after_seq<0 then raise exception 'INVALID_CURSOR'; end if;
  select coalesce(jsonb_agg(to_jsonb(page)-'user_id' order by sequence),'[]'::jsonb),coalesce(max(sequence),p_after_seq)
    into result,next_cursor from
    (select * from public.v1_change_feed where user_id=uid and sequence>p_after_seq order by sequence limit limit_count) page;
  return jsonb_build_object('changes',result,'cursor',next_cursor,'has_more',
    exists(select 1 from public.v1_change_feed where user_id=uid and sequence>next_cursor));
end;
$$;
revoke all on function public.apply_v1_operation(jsonb) from public,anon;
revoke all on function public.pull_v1_changes(bigint,integer) from public,anon;
grant execute on function public.apply_v1_operation(jsonb),public.pull_v1_changes(bigint,integer) to authenticated;
