-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000002_rls_initplan_auth_uid
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores all 113 policies to the exact text that was live before the forward
-- migration ran — bare `auth.uid()`, no (select ...) wrapper. Generated from the
-- live catalog at the same moment as the forward file, so this is a faithful
-- restore rather than a reconstruction from memory.
--
-- Reverting costs performance and buys nothing back: the forward change is
-- semantically inert. Only run this if a policy is somehow misbehaving and you
-- need to eliminate this migration as a variable.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

drop policy if exists admin_activity_insert on public.admin_activity_log;
create policy admin_activity_insert on public.admin_activity_log as permissive for insert to authenticated
  with check (((actor_id = auth.uid()) AND is_admin()));

drop policy if exists "Admin can view own details" on public.admin_details;
create policy "Admin can view own details" on public.admin_details as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists "Admin only access" on public.admin_details;
create policy "Admin only access" on public.admin_details as permissive for all to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text))
  with check ((get_user_role(auth.uid()) = 'admin'::text));

drop policy if exists admin_only on public.admin_details;
create policy admin_only on public.admin_details as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "admin_profiles insert own" on public.admin_profiles;
create policy "admin_profiles insert own" on public.admin_profiles as permissive for insert to authenticated
  with check ((auth.uid() = user_id));

drop policy if exists "admin_profiles select own" on public.admin_profiles;
create policy "admin_profiles select own" on public.admin_profiles as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists "admin_profiles update own" on public.admin_profiles;
create policy "admin_profiles update own" on public.admin_profiles as permissive for update to authenticated
  using ((auth.uid() = user_id));

drop policy if exists staff_reads_own_profile on public.admin_profiles;
create policy staff_reads_own_profile on public.admin_profiles as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists staff_updates_own_profile on public.admin_profiles;
create policy staff_updates_own_profile on public.admin_profiles as permissive for update to authenticated
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));

drop policy if exists "Admin manage citizen details" on public.citizen_details;
create policy "Admin manage citizen details" on public.citizen_details as permissive for all to authenticated
  using (is_admin(auth.uid()))
  with check (is_admin(auth.uid()));

drop policy if exists "Citizen can update own details" on public.citizen_details;
create policy "Citizen can update own details" on public.citizen_details as permissive for update to authenticated
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));

drop policy if exists "Citizen can view own details" on public.citizen_details;
create policy "Citizen can view own details" on public.citizen_details as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists citizen_details_read_admin_all on public.citizen_details;
create policy citizen_details_read_admin_all on public.citizen_details as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = 1)))));

drop policy if exists comment_likes_delete_own on public.community_comment_likes;
create policy comment_likes_delete_own on public.community_comment_likes as permissive for delete to authenticated
  using ((user_id = auth.uid()));

drop policy if exists comment_likes_insert on public.community_comment_likes;
create policy comment_likes_insert on public.community_comment_likes as permissive for insert to authenticated
  with check (((user_id = auth.uid()) AND (is_admin(auth.uid()) OR is_verified_citizen(auth.uid()))));

drop policy if exists comment_likes_read_own on public.community_comment_likes;
create policy comment_likes_read_own on public.community_comment_likes as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists official_inserts_own_comment_likes on public.community_comment_likes;
create policy official_inserts_own_comment_likes on public.community_comment_likes as permissive for insert to authenticated
  with check (((user_id = auth.uid()) AND (current_user_role_id() = ANY (ARRAY[1, 2]))));

drop policy if exists comments_delete_own on public.community_comments;
create policy comments_delete_own on public.community_comments as permissive for delete to authenticated
  using ((author_id = auth.uid()));

drop policy if exists comments_delete_own_or_admin on public.community_comments;
create policy comments_delete_own_or_admin on public.community_comments as permissive for delete to authenticated
  using (((author_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text))))));

drop policy if exists comments_insert on public.community_comments;
create policy comments_insert on public.community_comments as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (is_admin(auth.uid()) OR is_verified_citizen(auth.uid()))));

drop policy if exists comments_read_own on public.community_comments;
create policy comments_read_own on public.community_comments as permissive for select to authenticated
  using ((author_id = auth.uid()));

drop policy if exists comments_update_own on public.community_comments;
create policy comments_update_own on public.community_comments as permissive for update to authenticated
  using ((author_id = auth.uid()))
  with check ((author_id = auth.uid()));

drop policy if exists community_comments_admin_delete on public.community_comments;
create policy community_comments_admin_delete on public.community_comments as permissive for delete to authenticated
  using (is_admin(auth.uid()));

drop policy if exists community_comments_admin_read on public.community_comments;
create policy community_comments_admin_read on public.community_comments as permissive for select to authenticated
  using (is_admin(auth.uid()));

drop policy if exists community_comments_admin_staff_insert on public.community_comments;
create policy community_comments_admin_staff_insert on public.community_comments as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (is_admin(auth.uid()) OR is_staff(auth.uid()))));

drop policy if exists official_inserts_own_comments on public.community_comments;
create policy official_inserts_own_comments on public.community_comments as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (current_user_role_id() = ANY (ARRAY[1, 2]))));

drop policy if exists community_notifs_read_own on public.community_notifications;
create policy community_notifs_read_own on public.community_notifications as permissive for select to authenticated
  using ((recipient_id = auth.uid()));

drop policy if exists community_notifs_update_own on public.community_notifications;
create policy community_notifs_update_own on public.community_notifications as permissive for update to authenticated
  using ((recipient_id = auth.uid()))
  with check ((recipient_id = auth.uid()));

drop policy if exists post_images_author_manages on public.community_post_images;
create policy post_images_author_manages on public.community_post_images as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND (p.author_id = auth.uid())))))
  with check ((EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND (p.author_id = auth.uid())))));

drop policy if exists post_images_delete_own_post on public.community_post_images;
create policy post_images_delete_own_post on public.community_post_images as permissive for delete to authenticated
  using ((EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND (p.author_id = auth.uid())))));

drop policy if exists post_images_insert_own_post on public.community_post_images;
create policy post_images_insert_own_post on public.community_post_images as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND (p.author_id = auth.uid())))));

drop policy if exists post_images_read on public.community_post_images;
create policy post_images_read on public.community_post_images as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND ((p.status = 'approved'::text) OR (p.author_id = auth.uid()) OR user_has_role(auth.uid(), 'admin'::text))))));

drop policy if exists post_images_read_admin_or_own on public.community_post_images;
create policy post_images_read_admin_or_own on public.community_post_images as permissive for select to authenticated
  using ((is_admin() OR (EXISTS ( SELECT 1
   FROM community_posts p
  WHERE ((p.id = community_post_images.post_id) AND (p.author_id = auth.uid()))))));

drop policy if exists official_inserts_own_post_likes on public.community_post_likes;
create policy official_inserts_own_post_likes on public.community_post_likes as permissive for insert to authenticated
  with check (((user_id = auth.uid()) AND (current_user_role_id() = ANY (ARRAY[1, 2]))));

drop policy if exists post_likes_delete_own on public.community_post_likes;
create policy post_likes_delete_own on public.community_post_likes as permissive for delete to authenticated
  using ((user_id = auth.uid()));

drop policy if exists post_likes_insert on public.community_post_likes;
create policy post_likes_insert on public.community_post_likes as permissive for insert to authenticated
  with check (((user_id = auth.uid()) AND (is_admin(auth.uid()) OR is_verified_citizen(auth.uid()))));

drop policy if exists post_likes_read_own on public.community_post_likes;
create policy post_likes_read_own on public.community_post_likes as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists authors_delete_own_pending_posts on public.community_posts;
create policy authors_delete_own_pending_posts on public.community_posts as permissive for delete to authenticated
  using (((author_id = auth.uid()) AND (status = 'pending_approval'::text)));

drop policy if exists posts_delete_author_or_admin on public.community_posts;
create policy posts_delete_author_or_admin on public.community_posts as permissive for delete to authenticated
  using (((author_id = auth.uid()) OR is_admin(auth.uid())));

drop policy if exists posts_insert_admin_or_staff on public.community_posts;
create policy posts_insert_admin_or_staff on public.community_posts as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (is_admin(auth.uid()) OR is_staff(auth.uid()))));

drop policy if exists posts_read_admin_all on public.community_posts;
create policy posts_read_admin_all on public.community_posts as permissive for select to authenticated
  using (is_admin(auth.uid()));

drop policy if exists posts_read_approved_own_barangay on public.community_posts;
create policy posts_read_approved_own_barangay on public.community_posts as permissive for select to public
  using (((status = 'approved'::text) AND ((barangay IS NULL) OR (barangay = ''::text) OR (barangay = ( SELECT citizen_details.barangay
   FROM citizen_details
  WHERE (citizen_details.user_id = auth.uid())
 LIMIT 1)))));

drop policy if exists posts_read_own on public.community_posts;
create policy posts_read_own on public.community_posts as permissive for select to authenticated
  using ((author_id = auth.uid()));

drop policy if exists posts_update_admin on public.community_posts;
create policy posts_update_admin on public.community_posts as permissive for update to authenticated
  using (is_admin(auth.uid()));

drop policy if exists posts_update_own_pending on public.community_posts;
create policy posts_update_own_pending on public.community_posts as permissive for update to authenticated
  using (((author_id = auth.uid()) AND (status = 'pending_approval'::text)))
  with check ((author_id = auth.uid()));

drop policy if exists staff_inserts_own_pending_posts on public.community_posts;
create policy staff_inserts_own_pending_posts on public.community_posts as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (current_user_role_id() = ANY (ARRAY[1, 2])) AND (status = 'pending_approval'::text)));

drop policy if exists "Admins can manage all tickets" on public.concern_tickets;
create policy "Admins can manage all tickets" on public.concern_tickets as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Citizens can create their own tickets" on public.concern_tickets;
create policy "Citizens can create their own tickets" on public.concern_tickets as permissive for insert to authenticated
  with check ((auth.uid() = user_id));

drop policy if exists "Citizens can delete their own ghost tickets" on public.concern_tickets;
create policy "Citizens can delete their own ghost tickets" on public.concern_tickets as permissive for delete to authenticated
  using (((auth.uid() = user_id) AND (is_ghost = true) AND (assigned_staff_id IS NULL) AND (NOT ticket_has_staff_message(id))));

drop policy if exists "Citizens can read their own tickets" on public.concern_tickets;
create policy "Citizens can read their own tickets" on public.concern_tickets as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists device_tokens_delete on public.device_tokens;
create policy device_tokens_delete on public.device_tokens as permissive for delete to public
  using ((auth.uid() = user_id));

drop policy if exists device_tokens_insert on public.device_tokens;
create policy device_tokens_insert on public.device_tokens as permissive for insert to public
  with check ((auth.uid() = user_id));

drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens as permissive for select to public
  using ((auth.uid() = user_id));

drop policy if exists device_tokens_update on public.device_tokens;
create policy device_tokens_update on public.device_tokens as permissive for update to public
  using ((auth.uid() = user_id));

drop policy if exists "Admin: delete event" on public.events;
create policy "Admin: delete event" on public.events as permissive for delete to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admin: insert any event" on public.events;
create policy "Admin: insert any event" on public.events as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admin: see all events" on public.events;
create policy "Admin: see all events" on public.events as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admin: update any event" on public.events;
create policy "Admin: update any event" on public.events as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Staff: insert pending event" on public.events;
create policy "Staff: insert pending event" on public.events as permissive for insert to authenticated
  with check (((auth.uid() = created_by) AND (status = 'pending'::event_status) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'staff'::text))))));

drop policy if exists "Staff: see own submissions" on public.events;
create policy "Staff: see own submissions" on public.events as permissive for select to authenticated
  using (((auth.uid() = created_by) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'staff'::text))))));

drop policy if exists "Staff: update own pending event" on public.events;
create policy "Staff: update own pending event" on public.events as permissive for update to authenticated
  using (((auth.uid() = created_by) AND (status = 'pending'::event_status) AND (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'staff'::text))))));

drop policy if exists feedbacks_read_own on public.feedbacks;
create policy feedbacks_read_own on public.feedbacks as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists feedbacks_update_admin on public.feedbacks;
create policy feedbacks_update_admin on public.feedbacks as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))))
  with check ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))));

drop policy if exists notif_prefs_own on public.notification_preferences;
create policy notif_prefs_own on public.notification_preferences as permissive for all to authenticated
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));

drop policy if exists system_insert_receipts on public.notification_receipts;
create policy system_insert_receipts on public.notification_receipts as permissive for insert to authenticated
  with check ((auth.uid() = user_id));

drop policy if exists users_read_own_receipts on public.notification_receipts;
create policy users_read_own_receipts on public.notification_receipts as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists users_update_own_receipts on public.notification_receipts;
create policy users_update_own_receipts on public.notification_receipts as permissive for update to authenticated
  using ((user_id = auth.uid()));

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications as permissive for update to authenticated
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));

drop policy if exists staff_admin_send on public.notifications;
create policy staff_admin_send on public.notifications as permissive for insert to authenticated
  with check (((sent_by = auth.uid()) AND (is_staff(auth.uid()) OR is_admin(auth.uid())) AND ((COALESCE(target_all, false) = false) OR is_admin(auth.uid()))));

drop policy if exists users_delete_own on public.notifications;
create policy users_delete_own on public.notifications as permissive for delete to authenticated
  using ((auth.uid() = user_id));

drop policy if exists users_insert_own on public.notifications;
create policy users_insert_own on public.notifications as permissive for insert to authenticated
  with check ((auth.uid() = user_id));

drop policy if exists users_read_own on public.notifications;
create policy users_read_own on public.notifications as permissive for select to authenticated
  using (((auth.uid() = user_id) AND ((type <> 'staff_message'::text) OR (is_approved = true))));

drop policy if exists "Admin manage profiles" on public.profiles;
create policy "Admin manage profiles" on public.profiles as permissive for all to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text))
  with check (((get_user_role(auth.uid()) = 'admin'::text) AND (NOT ((COALESCE(is_deactivated, false) = true) AND (EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = profiles.id) AND (ur.role_id = 1))))))));

drop policy if exists "Admin view all profiles" on public.profiles;
create policy "Admin view all profiles" on public.profiles as permissive for select to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text));

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles as permissive for select to authenticated
  using ((id = auth.uid()));

drop policy if exists own_profile_insert on public.profiles;
create policy own_profile_insert on public.profiles as permissive for insert to authenticated
  with check ((id = auth.uid()));

drop policy if exists own_profile_update on public.profiles;
create policy own_profile_update on public.profiles as permissive for update to authenticated
  using ((auth.uid() = id))
  with check ((auth.uid() = id));

drop policy if exists profiles_read_admin_all on public.profiles;
create policy profiles_read_admin_all on public.profiles as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))));

drop policy if exists "Admins can view all report media" on public.report_media;
create policy "Admins can view all report media" on public.report_media as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Citizens can insert own report media" on public.report_media;
create policy "Citizens can insert own report media" on public.report_media as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
   FROM reports
  WHERE ((reports.id = report_media.report_id) AND (reports.user_id = auth.uid())))));

drop policy if exists "Citizens can view own report media" on public.report_media;
create policy "Citizens can view own report media" on public.report_media as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM reports
  WHERE ((reports.id = report_media.report_id) AND (reports.user_id = auth.uid())))));

drop policy if exists report_notes_staff_insert on public.report_notes;
create policy report_notes_staff_insert on public.report_notes as permissive for insert to authenticated
  with check (((author_id = auth.uid()) AND (author_role = 'staff'::text) AND staff_can_see_report(report_id)));

drop policy if exists rrm_insert on public.report_resolution_media;
create policy rrm_insert on public.report_resolution_media as permissive for insert to authenticated
  with check (((uploaded_by = auth.uid()) AND (is_admin() OR staff_can_see_report(report_id))));

drop policy if exists "Admins can manage all reports" on public.reports;
create policy "Admins can manage all reports" on public.reports as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admins can update reports" on public.reports;
create policy "Admins can update reports" on public.reports as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))))
  with check ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admins can view all reports" on public.reports;
create policy "Admins can view all reports" on public.reports as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Citizens can view own reports" on public.reports;
create policy "Citizens can view own reports" on public.reports as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists reports_insert_verified_citizen on public.reports;
create policy reports_insert_verified_citizen on public.reports as permissive for insert to authenticated
  with check (((auth.uid() = user_id) AND is_verified_citizen()));

drop policy if exists "Admin manage staff" on public.staff_details;
create policy "Admin manage staff" on public.staff_details as permissive for all to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text))
  with check ((get_user_role(auth.uid()) = 'admin'::text));

drop policy if exists "Admin view all staff" on public.staff_details;
create policy "Admin view all staff" on public.staff_details as permissive for select to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text));

drop policy if exists "Staff can view own details" on public.staff_details;
create policy "Staff can view own details" on public.staff_details as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists "Admins can view all suggestion media" on public.suggestion_media;
create policy "Admins can view all suggestion media" on public.suggestion_media as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Staff can view suggestion media" on public.suggestion_media;
create policy "Staff can view suggestion media" on public.suggestion_media as permissive for select to authenticated
  using (((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['staff'::text, 'admin'::text]))))) AND (EXISTS ( SELECT 1
   FROM suggestions
  WHERE (suggestions.id = suggestion_media.suggestion_id)))));

drop policy if exists suggestion_media_read_admin_all on public.suggestion_media;
create policy suggestion_media_read_admin_all on public.suggestion_media as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))));

drop policy if exists "Admins can manage all suggestions" on public.suggestions;
create policy "Admins can manage all suggestions" on public.suggestions as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))))
  with check ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admins can update suggestions" on public.suggestions;
create policy "Admins can update suggestions" on public.suggestions as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))))
  with check ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Admins can view all suggestions" on public.suggestions;
create policy "Admins can view all suggestions" on public.suggestions as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Citizens can view own suggestions" on public.suggestions;
create policy "Citizens can view own suggestions" on public.suggestions as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists suggestions_insert_verified_citizen on public.suggestions;
create policy suggestions_insert_verified_citizen on public.suggestions as permissive for insert to authenticated
  with check (((auth.uid() = user_id) AND is_verified_citizen()));

drop policy if exists suggestions_update_admin on public.suggestions;
create policy suggestions_update_admin on public.suggestions as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))))
  with check ((EXISTS ( SELECT 1
   FROM user_roles ur
  WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))));

drop policy if exists "Ticket participants can read attachments" on public.ticket_attachments;
create policy "Ticket participants can read attachments" on public.ticket_attachments as permissive for select to authenticated
  using (((EXISTS ( SELECT 1
   FROM concern_tickets ct
  WHERE ((ct.id = ticket_attachments.ticket_id) AND (ct.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM concern_tickets ct
  WHERE ((ct.id = ticket_attachments.ticket_id) AND (ct.assigned_staff_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text))))));

drop policy if exists "Ticket participants can upload attachments" on public.ticket_attachments;
create policy "Ticket participants can upload attachments" on public.ticket_attachments as permissive for insert to authenticated
  with check (((EXISTS ( SELECT 1
   FROM concern_tickets ct
  WHERE ((ct.id = ticket_attachments.ticket_id) AND ((ct.user_id = auth.uid()) OR (ct.assigned_staff_id = auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text))))));

drop policy if exists "Ticket participants can read messages" on public.ticket_messages;
create policy "Ticket participants can read messages" on public.ticket_messages as permissive for select to authenticated
  using (((EXISTS ( SELECT 1
   FROM concern_tickets ct
  WHERE ((ct.id = ticket_messages.ticket_id) AND (ct.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text))))));

drop policy if exists "Ticket participants can send messages" on public.ticket_messages;
create policy "Ticket participants can send messages" on public.ticket_messages as permissive for insert to authenticated
  with check (((auth.uid() = sender_id) AND (sender_type = 'citizen'::text) AND ticket_accepts_messages(ticket_id) AND (EXISTS ( SELECT 1
   FROM concern_tickets ct
  WHERE ((ct.id = ticket_messages.ticket_id) AND (ct.user_id = auth.uid()))))));

drop policy if exists staff_writes_department_messages on public.ticket_messages;
create policy staff_writes_department_messages on public.ticket_messages as permissive for insert to authenticated
  with check (((auth.uid() = sender_id) AND (sender_type = 'staff'::text) AND ticket_accepts_messages(ticket_id) AND staff_can_see_ticket(ticket_id)));

drop policy if exists user_restrictions_read_own on public.user_restrictions;
create policy user_restrictions_read_own on public.user_restrictions as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists "Admin manage roles" on public.user_roles;
create policy "Admin manage roles" on public.user_roles as permissive for all to authenticated
  using ((get_user_role(auth.uid()) = 'admin'::text))
  with check ((get_user_role(auth.uid()) = 'admin'::text));

drop policy if exists user_view_own_roles on public.user_roles;
create policy user_view_own_roles on public.user_roles as permissive for select to authenticated
  using ((auth.uid() = user_id));

drop policy if exists user_suspensions_read_own on public.user_suspensions;
create policy user_suspensions_read_own on public.user_suspensions as permissive for select to authenticated
  using ((user_id = auth.uid()));

drop policy if exists "Admin manage all submissions" on public.verification_submissions;
create policy "Admin manage all submissions" on public.verification_submissions as permissive for all to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((r.id = ur.role_id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = 'admin'::text)))));

drop policy if exists "Citizens submit own verification" on public.verification_submissions;
create policy "Citizens submit own verification" on public.verification_submissions as permissive for insert to authenticated
  with check ((user_id = auth.uid()));

drop policy if exists admin_update_status on public.verification_submissions;
create policy admin_update_status on public.verification_submissions as permissive for update to authenticated
  using ((EXISTS ( SELECT 1
   FROM (user_roles ur
     JOIN roles r ON ((ur.role_id = r.id)))
  WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['admin'::text, 'staff'::text]))))));

drop policy if exists citizen_view_own on public.verification_submissions;
create policy citizen_view_own on public.verification_submissions as permissive for select to authenticated
  using ((user_id = auth.uid()));

commit;
