import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Jabar Open 2026 — Turnstile-guarded public submissions.
//
// Flow: browser sends { action, turnstile_token, payload } with its anonymous JWT.
// We verify the Turnstile token server-side, resolve the real uid from the JWT, then
// call a service_role-only RPC wrapper that impersonates that uid for one transaction.
// The browser's identity is preserved, so rate limiting and the bukti/<uid>/ storage
// folder policy keep working exactly as before.
//
// Deploy: Supabase → Edge Functions → guarded-submit (verify_jwt = true).
// Pasangan SQL: supabase/patch_2026-11-02_turnstile.sql.

const ALLOWED_ORIGINS = new Set([
  "https://gimnastikjabaropen2026.com",
  "https://www.gimnastikjabaropen2026.com",
]);

const SITEVERIFY = "https://challenges.cloudflare.com/turnstile/v0/siteverify";

type Action = "register" | "resend_link";

// 4 Nov 2026: daftar.js memanggil rpc('public_register', { p: payload }), jadi payload
// yang sampai di sini berbentuk { p: {...} }. Tanpa unwrap, register_verified menerima
// { p: { p: {...} } } dan public_register gagal dengan "Pilih disiplin terlebih dahulu."
// Unwrap bila ada, tetap terima bentuk datar bila klien kelak mengirim tanpa pembungkus.
function unwrapP(payload: Record<string, unknown>): Record<string, unknown> {
  const inner = (payload as { p?: unknown })?.p;
  return inner && typeof inner === "object" && !Array.isArray(inner)
    ? inner as Record<string, unknown>
    : payload;
}

const ACTIONS: Record<Action, (payload: Record<string, unknown>, uid: string) => {
  fn: string;
  args: Record<string, unknown>;
}> = {
  register: (payload, uid) => ({
    fn: "register_verified",
    args: { p: unwrapP(payload), p_uid: uid },
  }),
  resend_link: (payload, uid) => ({
    fn: "resend_link_verified",
    args: {
      p_code: String(payload?.code ?? ""),
      p_email: String(payload?.email ?? ""),
      p_uid: uid,
    },
  }),
};

function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.has(origin)
    ? origin
    : "https://gimnastikjabaropen2026.com";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req.headers.get("Origin"));
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ message: "Metode tidak diizinkan." }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) {
    return json({ message: "Sesi browser belum siap. Muat ulang halaman.", hint: "ERR_SESSION" }, 401);
  }

  const body = await req.json().catch(() => null);
  const action = body?.action as Action | undefined;
  if (!action || !(action in ACTIONS)) {
    return json({ message: "Permintaan tidak dikenal." }, 400);
  }
  if (!body?.payload || typeof body.payload !== "object") {
    return json({ message: "Permintaan tidak lengkap." }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Kill switch. Fail CLOSED: if we cannot read it, require Turnstile.
  let needTurnstile = true;
  const { data: flag, error: flagErr } = await admin.rpc("turnstile_enabled");
  if (!flagErr && flag === false) needTurnstile = false;

  if (needTurnstile) {
    const secret = Deno.env.get("TURNSTILE_SECRET_KEY");
    if (!secret) {
      console.error("TURNSTILE_SECRET_KEY is not set");
      return json({ message: "Verifikasi keamanan belum dikonfigurasi. Hubungi panitia." }, 503);
    }
    const token = body?.turnstile_token;
    if (!token || typeof token !== "string") {
      return json(
        { message: "Verifikasi keamanan belum selesai. Tunggu tanda \"Berhasil!\" di bawah formulir, lalu tekan Kirim lagi. Isian Anda tidak hilang.", hint: "ERR_TURNSTILE" },
        400,
      );
    }

    const form = new FormData();
    form.append("secret", secret);
    form.append("response", token);
    const ip = req.headers.get("CF-Connecting-IP") ?? req.headers.get("X-Forwarded-For");
    if (ip) form.append("remoteip", ip.split(",")[0].trim());

    let ok = false;
    try {
      const res = await fetch(SITEVERIFY, {
        method: "POST",
        body: form,
        signal: AbortSignal.timeout(8000),
      });
      const verdict = await res.json();
      ok = verdict?.success === true;
      if (!ok) console.warn("turnstile rejected", verdict?.["error-codes"]);
    } catch (e) {
      console.error("siteverify unreachable", String(e));
      return json(
        { message: "Verifikasi keamanan tidak tersedia. Tekan Kirim lagi beberapa saat lagi. Isian Anda tidak hilang.", hint: "ERR_TURNSTILE" },
        503,
      );
    }
    if (!ok) {
      // 4 Nov 2026: jangan suruh muat ulang halaman — berkas yang sudah diunggah akan hilang.
      // Penyebab tersering: token kedaluwarsa (timeout-or-duplicate) karena tab/ponsel sempat tidur.
      return json(
        { message: "Verifikasi keamanan kedaluwarsa. Tunggu tanda \"Berhasil!\" di bawah formulir, lalu tekan Kirim lagi. Isian Anda tidak hilang.", hint: "ERR_TURNSTILE" },
        403,
      );
    }
  }

  // Resolve the caller's real uid from their JWT.
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user?.id) {
    return json({ message: "Sesi browser tidak valid. Muat ulang halaman.", hint: "ERR_SESSION" }, 401);
  }

  const call = ACTIONS[action](body.payload as Record<string, unknown>, userData.user.id);
  const { data, error } = await admin.rpc(call.fn, call.args);

  if (error) {
    // Forward message, hint AND code, so the thrown Error on the client is shaped
    // exactly like the one the original rpc() helper produced. daftar.js error
    // handling then behaves identically whether or not the call was guarded.
    const e = error as { message?: string; hint?: string; code?: string };
    return json({ message: e.message, hint: e.hint, code: e.code }, 400);
  }
  return json(data, 200);
});
