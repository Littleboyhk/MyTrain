// POST { train_number, journey_date }
//
// Creates (or fetches) the caller's per-journey pseudonym for a train's chat
// room, creating the room on first join. Returns ONLY the caller's own view:
// their display id, nickname and verification progress. It never returns the
// participant list, and never returns any user_id — including the caller's.
//
// Requires a real end-user JWT. There is no anonymous path: without a durable
// account there is nothing to attach a mute to, so the gate fails closed.
import { corsHeaders, json } from "../_shared/cors.ts";
import { admin } from "../_shared/supabaseAdmin.ts";
import { loadRoute } from "../_shared/chat_route.ts";
import { scheduledArrivalEpochMs } from "../_shared/journey_match.ts";

/** Hours after scheduled arrival that the room and its messages are deleted. */
const RETENTION_HOURS = 3;

/** Fallback when the route has no usable arrival time: keep it short. */
const FALLBACK_LIFETIME_HOURS = 12;

function displayId(): string {
  // 'Traveler' + 3 digits. Fresh per journey, not derived from the user id, so
  // two journeys by the same person are unlinkable to other passengers.
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 900 + 100;
  return `Traveler${n}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "authentication required", code: "auth_required" }, 401);

    const db = admin();

    // Identify the caller from their JWT. The anon key is also a valid JWT, so
    // we must confirm this token belongs to an actual user.
    const { data: userData, error: userErr } = await db.auth.getUser(jwt);
    const user = userData?.user;
    if (userErr || !user || !user.id) {
      return json({
        error:
          "Chat requires a signed-in account. This build has no sign-in yet, " +
          "so journey chat is unavailable.",
        code: "auth_required",
      }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const trainNumber = String(body?.train_number ?? "").trim();
    const journeyDate = String(body?.journey_date ?? "").trim();

    if (!/^\d{3,6}$/.test(trainNumber)) {
      return json({ error: "valid train_number required", code: "validation" }, 400);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(journeyDate)) {
      return json({ error: "journey_date must be YYYY-MM-DD", code: "validation" }, 400);
    }

    // ---- room ----------------------------------------------------------
    let { data: room } = await db
      .from("journey_chats")
      .select("*")
      .eq("train_number", trainNumber)
      .eq("journey_date", journeyDate)
      .maybeSingle();

    if (!room) {
      // Expiry comes from the train's own schedule. The route is already cached
      // for 24h by the timeline feature, so this normally costs no API quota.
      let arrivalMs: number | null = null;
      let trainName: string | null = null;
      let originCode: string | null = null;
      let destCode: string | null = null;

      try {
        const loaded = await loadRoute(db, trainNumber);
        arrivalMs = scheduledArrivalEpochMs(loaded.route, journeyDate);
        trainName = loaded.trainName;
        originCode = loaded.route.at(0)?.code ?? null;
        destCode = loaded.route.at(-1)?.code ?? null;
      } catch (e) {
        // No route => no verification is possible anyway, but we still create
        // the room with a short lifetime so the state machine has somewhere to
        // record the failure.
        console.error("[chat-join] route lookup failed:", String(e));
      }

      const expiresAt = arrivalMs
        ? new Date(arrivalMs + RETENTION_HOURS * 3600_000)
        : new Date(Date.now() + FALLBACK_LIFETIME_HOURS * 3600_000);

      const { data: created, error: createErr } = await db
        .from("journey_chats")
        .upsert({
          train_number: trainNumber,
          journey_date: journeyDate,
          train_name: trainName,
          origin_code: originCode,
          destination_code: destCode,
          scheduled_arrival_at: arrivalMs ? new Date(arrivalMs).toISOString() : null,
          expires_at: expiresAt.toISOString(),
          retention_hours: RETENTION_HOURS,
        }, { onConflict: "train_number,journey_date" })
        .select("*")
        .single();
      if (createErr) throw createErr;
      room = created;
    }

    if (new Date(room.expires_at).getTime() <= Date.now()) {
      return json({
        error: "This journey chat has ended.",
        code: "expired",
      }, 410);
    }
    if (room.locked) {
      return json({ error: "This journey chat is closed.", code: "locked" }, 403);
    }

    // ---- participant (pseudonym) ---------------------------------------
    let { data: me } = await db
      .from("chat_participants")
      .select("*")
      .eq("chat_id", room.id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!me) {
      // Retry on the (chat_id, display_id) uniqueness collision.
      for (let attempt = 0; attempt < 5 && !me; attempt++) {
        const { data: inserted, error } = await db
          .from("chat_participants")
          .insert({
            chat_id: room.id,
            user_id: user.id,
            display_id: displayId(),
          })
          .select("*")
          .single();
        if (!error) {
          me = inserted;
          break;
        }
        if (error.code !== "23505") throw error;
      }
      if (!me) {
        return json({ error: "could not allocate a display id", code: "retry" }, 503);
      }
    } else {
      await db
        .from("chat_participants")
        .update({ last_seen_at: new Date().toISOString() })
        .eq("id", me.id);
    }

    const { data: vstate } = await db
      .from("chat_verification_state")
      .select("status, sustained_seconds, progress_km, reason, accepted_samples")
      .eq("chat_id", room.id)
      .eq("user_id", user.id)
      .maybeSingle();

    const muted = me.muted_until && new Date(me.muted_until).getTime() > Date.now();

    // Note the shape: no user_id, no participant list, no message content.
    return json({
      chat: {
        id: room.id,
        train_number: room.train_number,
        journey_date: room.journey_date,
        train_name: room.train_name,
        expires_at: room.expires_at,
      },
      me: {
        display_id: me.display_id,
        nickname: me.nickname,
        verification_status: me.verification_status,
        can_read: me.verification_status === "verified",
        can_post: me.verification_status === "verified" && !muted,
        muted_until: muted ? me.muted_until : null,
      },
      verification: {
        status: vstate?.status ?? "pending",
        sustained_seconds: vstate?.sustained_seconds ?? 0,
        required_seconds: 300,
        progress_km: vstate?.progress_km ?? 0,
        accepted_samples: vstate?.accepted_samples ?? 0,
        reason: vstate?.reason ?? "collecting_samples",
      },
    });
  } catch (err) {
    console.error("[chat-join]", String(err));
    return json({ error: String(err), code: "internal" }, 500);
  }
});
