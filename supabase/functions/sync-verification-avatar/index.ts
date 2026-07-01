// ════════════════════════════════════════════════════════════════════════════
//  sync-verification-avatar
//
//  When a citizen is approved, their verification selfie needs to become their
//  public profile picture. The selfie is uploaded to the PRIVATE
//  `verification-assets` bucket, but the whole app renders avatars from the
//  PUBLIC `profile-photos` bucket via `citizen_details.profile_photo_path`.
//  Nothing copies the bytes across, so a freshly-approved citizen shows a blank
//  avatar until they manually re-upload one.
//
//  This function (service role, so it isn't blocked by storage RLS) copies the
//  selfie into `profile-photos` at the exact path the app expects. It derives
//  every path server-side from the DB — the caller only supplies a user_id — and
//  it only heals the un-migrated case, so a citizen who already set a custom
//  avatar is never overwritten. Safe to call repeatedly (idempotent).
// ════════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/rate-limit.ts"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })

  try {
    const { user_id } = await req.json()
    if (!user_id || typeof user_id !== "string") {
      return json({ success: false, message: "user_id required" }, 400)
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // Only ever act on an APPROVED submission, and take its path from the DB —
    // never a client-supplied path.
    const { data: sub } = await supabase
      .from("verification_submissions")
      .select("face_photo_path")
      .eq("user_id", user_id)
      .eq("status", "approved")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle()

    const facePath = sub?.face_photo_path as string | null | undefined
    if (!facePath) {
      return json({ success: true, copied: false, reason: "no approved selfie" })
    }

    // What the app currently reads from. If it's a custom avatar (a path other
    // than the raw selfie), the citizen already replaced it — leave it alone.
    const { data: cd } = await supabase
      .from("citizen_details")
      .select("profile_photo_path")
      .eq("user_id", user_id)
      .maybeSingle()

    const currentPath = cd?.profile_photo_path as string | null | undefined
    if (currentPath && currentPath !== facePath) {
      return json({ success: true, copied: false, reason: "custom avatar set" })
    }

    // Pull the selfie from the private bucket …
    const { data: blob, error: dlErr } = await supabase.storage
      .from("verification-assets")
      .download(facePath)
    if (dlErr || !blob) {
      return json(
        { success: false, message: `download failed: ${dlErr?.message ?? "missing"}` },
        502,
      )
    }

    // … and write it into the public bucket at the same path the app expects.
    const bytes = new Uint8Array(await blob.arrayBuffer())
    const { error: upErr } = await supabase.storage
      .from("profile-photos")
      .upload(facePath, bytes, { contentType: "image/jpeg", upsert: true })
    if (upErr) {
      return json({ success: false, message: `upload failed: ${upErr.message}` }, 500)
    }

    // If the profile row hadn't pointed at an avatar yet, point it at the selfie
    // so the citizen app actually renders it.
    if (!currentPath) {
      await supabase
        .from("citizen_details")
        .update({ profile_photo_path: facePath })
        .eq("user_id", user_id)
    }

    return json({ success: true, copied: true, path: facePath })
  } catch (e) {
    return json({ success: false, message: String(e) }, 400)
  }
})
