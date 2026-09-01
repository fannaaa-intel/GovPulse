-- Rollback for 20260901000002 — restores the is_anonymous gate on both
-- citizen-facing update triggers, returning them byte-for-byte to the bodies
-- shipped by 20260829000001 §9 and 20260829000004.
--
-- Reverting means anonymous reporters stop being told about updates they can
-- still read in the app. That is the defect the forward migration fixes, so
-- this is here for completeness, not because it is a good state to be in.

begin;

create or replace function public.notify_report_update_decision()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.status = old.status then return new; end if;

  if new.status = 'approved' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select r.user_id, 'report_update',
             'New update on your report',
             left(new.body, 120),
             'report_update', 4279203438, 0, true, auth.uid(), r.id::text
        from public.reports r
       where r.id = new.report_id
         and r.user_id is not null
         and r.is_anonymous = false;
    exception when others then null;
    end;
  end if;

  if new.author_id is not null and new.author_id is distinct from auth.uid() then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      values (
        new.author_id, 'report_update',
        case when new.status = 'approved'
             then 'Your progress update was approved'
             else 'Your progress update was returned' end,
        case when new.status = 'approved'
             then left(new.body, 120)
             else coalesce(nullif(btrim(new.rejected_reason), ''), '')
        end,
        'report_update',
        case when new.status = 'approved' then 4281257073 else 4293348412 end,
        0, true, auth.uid(), new.report_id::text
      );
    exception when others then null;
    end;
  end if;

  return new;
end;
$$;

create or replace function public.notify_citizen_of_approved_insert()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select r.user_id,
           'report_update',
           'New update on your report',
           left(new.body, 120),
           'report_update',
           4279203438,
           0,
           true,
           auth.uid(),
           r.id::text
      from public.reports r
     where r.id = new.report_id
       and r.user_id is not null
       and r.is_anonymous = false;
  exception when others then
    null;
  end;
  return new;
end;
$$;

commit;
