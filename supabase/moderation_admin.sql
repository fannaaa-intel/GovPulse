-- ════════════════════════════════════════════════════════════════════════════
--  Moderation admin API — edit banned words + thresholds from the console
--
--  Lets the admin Settings screen read and edit public.moderation_terms and
--  public.moderation_settings WITHOUT exposing those tables to citizens. Every
--  function is admin-only (role_id = 1) and SECURITY DEFINER, so no table RLS is
--  needed and citizens can never touch the lists.
--
--  Requires: profanity_moderation.sql (moderation_terms, normalize_text) and
--            spam_detection.sql (moderation_settings).
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public._is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role_id = 1
  );
$$;

-- ── Banned words ─────────────────────────────────────────────────────────────
create or replace function public.admin_moderation_terms()
returns setof text language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'admin only'; end if;
  return query select term from public.moderation_terms order by term;
end;
$$;

create or replace function public.admin_add_banned_term(p_term text)
returns text language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if not public._is_admin() then raise exception 'admin only'; end if;
  -- Normalize the same way matching does (lowercase, de-leet/-accent, letters
  -- only) so admins can type "G4go" and it stores the canonical root "gago".
  t := regexp_replace(public.normalize_text(p_term), '[^a-z]', '', 'g');
  if length(t) < 2 then raise exception 'term too short'; end if;
  insert into public.moderation_terms(term) values (t) on conflict do nothing;
  return t;
end;
$$;

create or replace function public.admin_remove_banned_term(p_term text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'admin only'; end if;
  delete from public.moderation_terms where term = p_term;
end;
$$;

-- ── Thresholds ───────────────────────────────────────────────────────────────
create or replace function public.admin_moderation_settings()
returns table (key text, value numeric, description text)
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'admin only'; end if;
  return query
    select ms.key, ms.value, ms.description
      from public.moderation_settings ms
     order by ms.key;
end;
$$;

create or replace function public.admin_set_moderation_setting(p_key text, p_value numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin() then raise exception 'admin only'; end if;
  update public.moderation_settings
     set value = greatest(p_value, 0)
   where key = p_key;
end;
$$;

grant execute on function public.admin_moderation_terms() to authenticated;
grant execute on function public.admin_add_banned_term(text) to authenticated;
grant execute on function public.admin_remove_banned_term(text) to authenticated;
grant execute on function public.admin_moderation_settings() to authenticated;
grant execute on function public.admin_set_moderation_setting(text, numeric) to authenticated;
