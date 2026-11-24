create schema if not exists parcel;
revoke all on schema parcel from public, anon, authenticated;
grant usage on schema parcel to authenticated;
create table parcel.catalog (
  id integer primary key, title text not null, category text not null, description text not null,
  price numeric(12,2) not null, detail text not null, lat numeric, lng numeric
);
create table parcel.accounts (uid uuid primary key references auth.users on delete cascade, role text not null check(role in ('demo','admin')));
create table parcel.profiles (uid uuid references auth.users on delete cascade, space uuid, display_name text not null, primary key(uid,space));
create table parcel.records (
  id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users on delete cascade,
  space uuid not null, pool uuid not null, item integer references parcel.catalog, kind text not null,
  status text not null, slot text, payload jsonb not null default '{}', created_at timestamptz not null default now()
);
create unique index on parcel.records(pool,item,slot) where kind in ('seat','appointment','viewing','assignment') and status <> 'Cancelled';
create unique index on parcel.records(owner,space,item,kind) where kind in ('favorite','course');
alter table parcel.catalog enable row level security;
alter table parcel.accounts enable row level security;
alter table parcel.profiles enable row level security;
alter table parcel.records enable row level security;
revoke all on all tables in schema parcel from public,anon,authenticated;

insert into parcel.catalog values ('1','Pearl bookshop drop','North route','Collect the book crate from Union Station dispatch.','0','Powell’s district','45.523','-122.681'),
('2','Riverfront provisions','Central route','Pick up the sealed grocery tote at city dispatch.','0','Waterfront Park','45.519','-122.671'),
('3','Museum print delivery','West route','Collect the flat art parcel from the dispatch desk.','0','Museum district','45.516','-122.683');

create or replace function parcel.handle(action text, args jsonb, installation uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
<<handle>>
declare
  uid uuid := auth.uid();
  mode text;
  scope uuid;
  pool_id uuid := '00000000-0000-0000-0000-000000000000';
  product parcel.catalog%rowtype;
  rec parcel.records%rowtype;
  target integer;
  slot_key text;
  day date;
  amount numeric := 0;
  qty int;
  line jsonb;
  lines jsonb := '[]';
  info jsonb := '{}';
  label text;
begin
  if uid is null or installation is null then raise exception 'Sign in to continue'; end if;
  select a.role into mode from parcel.accounts a where a.uid=handle.uid;
  if mode is null and (auth.jwt()->>'email') like '%@demo.mobile.invalid' then raise exception 'Use this app’s demo account'; end if;
  scope := case when mode='demo' then installation else uid end;
  if mode='demo' then if installation=pool_id then raise exception 'Invalid demo installation'; end if; pool_id := installation; end if;
  if action='profile' then
    label := trim(args->>'name');
    if coalesce(length(label),0) not between 1 and 60 then raise exception 'Enter a name of 1–60 characters'; end if;
    insert into parcel.profiles values(uid,scope,label) on conflict on constraint profiles_pkey do update set display_name=excluded.display_name;
  elsif action='cancel' then
    update parcel.records r set status='Cancelled' where r.id=(args->>'id')::uuid and r.owner=uid and r.space=scope and r.kind in ('seat','viewing','appointment') and r.status='Confirmed';
    if not found then raise exception 'Reservation no longer available'; end if;
  elsif action not in ('state','availability') then
    
if action='claim' then
  insert into parcel.records(owner,space,pool,item,kind,status,slot) values(uid,scope,pool_id,(args->>'item')::int,'assignment','Assigned',current_date::text);
elsif action in ('start','location','deliver') then
  select * into strict rec from parcel.records r where r.id=(args->>'id')::uuid and r.owner=uid and r.space=scope and r.kind='assignment' for update;
  if action='start' and rec.status='Assigned' then
    update parcel.records set status='En route' where id=rec.id;
  elsif action='location' and rec.status='En route' then
    if (args->>'lat')::numeric not between -90 and 90 or (args->>'lng')::numeric not between -180 and 180 or not (args ?& array['lat','lng']) then raise exception 'Invalid location'; end if;
    update parcel.records set payload=payload || jsonb_build_object('lat',(args->>'lat')::numeric,'lng',(args->>'lng')::numeric,'located',now()) where id=rec.id;
  elsif action='deliver' and rec.status='En route' then
    label:=trim(args->>'recipient');
    if coalesce(length(label),0) not between 2 and 60 then raise exception 'Enter a recipient name'; end if;
    update parcel.records set status='Delivered',payload=(payload-'lat'-'lng'-'located') || jsonb_build_object('recipient',label,'completed',now()) where id=rec.id;
  else raise exception 'Assignment status has changed'; end if;
else raise exception 'Unknown dispatch action'; end if;

  end if;
  if action='availability' then
    select coalesce(jsonb_agg(r.slot),'[]') into info from parcel.records r where r.pool=pool_id and r.item=(args->>'item')::integer and r.status <> 'Cancelled' and r.kind in ('seat','viewing','appointment','assignment');
    return info;
  end if;
  return jsonb_build_object(
    'catalog',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') from parcel.catalog c),
    'records',(select coalesce(jsonb_agg(to_jsonb(r)-'owner'-'space'-'pool' order by r.created_at desc),'[]') from parcel.records r where (r.owner=uid and r.space=scope) or (mode='admin' and r.pool=pool_id)),
    'name',(select p.display_name from parcel.profiles p where p.uid=handle.uid and p.space=scope),
    'demo',coalesce(mode='demo',false),'admin',coalesce(mode in ('demo','admin'),false)
  );
exception when unique_violation then raise exception 'Just reserved. Choose another option.';
end $body$;
revoke all on function parcel.handle(text,jsonb,uuid) from public,anon;
grant execute on function parcel.handle(text,jsonb,uuid) to authenticated;
create or replace function public.parcel_workspace(action text,args jsonb,installation uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select parcel.handle(action,args,installation);
$$;
revoke all on function public.parcel_workspace(text,jsonb,uuid) from public,anon;
grant execute on function public.parcel_workspace(text,jsonb,uuid) to authenticated;
notify pgrst,'reload schema';

