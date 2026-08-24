-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 20260824000000_stable_role_helpers
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores the three overloads to VOLATILE, which is what they were before the
-- forward migration (by omission, not by intent — none of them declared a
-- volatility class at all).
--
-- Reverting costs performance and buys nothing back: all three functions are
-- stable by inspection, so STABLE is the truthful label. Only run this if you
-- need to eliminate this migration as a variable while debugging something else.
--
-- NOTE: the no-argument forms `is_admin()` and `_is_admin()` were ALREADY STABLE
-- before this migration and are deliberately NOT touched here. Setting them
-- volatile would be a regression, not a rollback.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

alter function public.is_admin(uuid)            volatile;
alter function public.is_staff(uuid)            volatile;
alter function public.user_has_role(uuid, text) volatile;

commit;
