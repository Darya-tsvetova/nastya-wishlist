-- Выполните в новом проекте Supabase. Замените NASTYA_EMAIL_HERE трижды.
-- Предназначено для личного семейного проекта, не для публичного сервиса.
create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text not null default '' check (char_length(description) <= 600),
  price numeric(12,2) check (price is null or price >= 0),
  image_url text not null default '' check (char_length(image_url) <= 2000 and (image_url='' or image_url ~* '^https://[^ ]+$')),
  shop_url text not null check (char_length(shop_url) between 9 and 2000 and shop_url ~* '^https://[^ ]+$'),
  priority text not null default 'Классный вариант' check (priority in ('Очень хочу','Классный вариант','Всегда надо')),
  category text not null default 'Другое' check (category in ('Красота','Одежда','Гаджеты','Творчество','Другое')),
  reserved boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.gifts enable row level security;
revoke all on public.gifts from public, anon, authenticated;
grant select on public.gifts to anon, authenticated;
-- Важно: поле reserved НЕ входит в разрешённые столбцы для записи.
grant insert (title,description,price,image_url,shop_url,priority,category) on public.gifts to authenticated;
grant update (title,description,price,image_url,shop_url,priority,category) on public.gifts to authenticated;
grant delete on public.gifts to authenticated;

drop policy if exists "anyone can view gifts" on public.gifts;
create policy "anyone can view gifts" on public.gifts for select to anon,authenticated using (true);
drop policy if exists "owner can create" on public.gifts;
create policy "owner can create" on public.gifts for insert to authenticated
with check ((auth.jwt()->>'email') = 'NASTYA_EMAIL_HERE' and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false and reserved = false);
drop policy if exists "owner can edit" on public.gifts;
create policy "owner can edit" on public.gifts for update to authenticated
using ((auth.jwt()->>'email') = 'NASTYA_EMAIL_HERE' and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false)
with check ((auth.jwt()->>'email') = 'NASTYA_EMAIL_HERE' and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false);
drop policy if exists "owner can delete" on public.gifts;
create policy "owner can delete" on public.gifts for delete to authenticated
using ((auth.jwt()->>'email') = 'NASTYA_EMAIL_HERE' and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false);

create or replace function public.reserve_gift(p_gift_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_reserved uuid;
begin
  if auth.uid() is null then raise exception 'Authorization required'; end if;
  -- Атомарный UPDATE гарантирует одну успешную бронь даже при одновременных кликах.
  update public.gifts set reserved = true
  where id = p_gift_id and reserved = false and shop_url ~* '^https://[^ ]+$'
  returning id into v_reserved;
  return v_reserved is not null;
end;
$$;
revoke all on function public.reserve_gift(uuid) from public,anon,authenticated;
grant execute on function public.reserve_gift(uuid) to authenticated;

-- Реальное обновление статусов у открывших страницу пользователей.
-- Не включайте REPLICA IDENTITY FULL: в таблице нет личных данных гостя.
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='gifts'
  ) then
    alter publication supabase_realtime add table public.gifts;
  end if;
end $$;
