// Envia a fila public.notifications_outbox pelo FCM HTTP v1.
// O texto fica igual a lib/core/push/push_copy.dart.
// Segredo: FIREBASE_SERVICE_ACCOUNT (JSON da conta de serviço do Firebase).
import { createClient } from "npm:@supabase/supabase-js@2";

const channelId = "radar_familiar";
const fcmScope = "https://www.googleapis.com/auth/firebase.messaging";

type OutboxRow = {
  id: number;
  user_id: string;
  type: string;
  payload: Record<string, unknown> | null;
};

type DeviceRow = {
  id: string;
  fcm_token: string;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!isServiceRole(req)) {
    return json({ error: "unauthorized" }, 401);
  }

  const account = serviceAccount();
  if (!account) {
    return json({ error: "firebase_not_configured" }, 503);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: Record<string, unknown> = {};
  try {
    const parsed = await req.json();
    if (parsed && typeof parsed === "object") body = parsed;
  } catch {
    body = {};
  }
  const record = body.record;
  const rawId = body.id ??
    (record && typeof record === "object" ? record.id : undefined);

  let query = admin
    .from("notifications_outbox")
    .select("id, user_id, type, payload")
    .is("sent_at", null)
    .order("created_at", { ascending: true })
    .limit(rawId == null ? 20 : 1);
  if (rawId != null) query = query.eq("id", rawId);

  const { data, error } = await query;
  if (error) return json({ error: error.message }, 500);

  const rows = (data ?? []) as OutboxRow[];
  if (rows.length === 0) return json({ ok: true, processed: 0 });

  let accessToken: string;
  try {
    accessToken = await googleAccessToken(account);
  } catch (e) {
    return json({ error: `oauth: ${errorText(e)}` }, 502);
  }

  let processed = 0;
  for (const row of rows) {
    const delivered = await deliver(admin, account.project_id, accessToken, row);
    if (delivered) processed += 1;
  }
  return json({ ok: true, processed });
});

function isServiceRole(req: Request): boolean {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!token || !expected || token !== expected) return false;
  return true;
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    parsed.private_key = parsed.private_key.replace(/\\n/g, "\n");
    return parsed;
  } catch {
    return null;
  }
}

async function deliver(
  admin: ReturnType<typeof createClient>,
  projectId: string,
  accessToken: string,
  row: OutboxRow,
): Promise<boolean> {
  const payload = row.payload ?? {};
  const text = pushText(row.type, payload);
  const data = stringData(payload, {
    type: row.type,
    title: text.title,
    body: text.body,
  });

  const { data: devices, error } = await admin
    .from("devices")
    .select("id, fcm_token")
    .eq("user_id", row.user_id);
  if (error) {
    await mark(admin, row.id, null, error.message);
    return false;
  }

  const list = (devices ?? []) as DeviceRow[];
  if (list.length === 0) {
    await mark(admin, row.id, new Date().toISOString(), "no_device");
    return true;
  }

  let delivered = 0;
  const transient: string[] = [];
  for (const device of list) {
    const result = await sendFcm(
      projectId,
      accessToken,
      device.fcm_token,
      text,
      data,
    );
    if (result.ok) {
      delivered += 1;
    } else if (result.invalid) {
      await admin.from("devices").delete().eq("id", device.id);
    } else {
      transient.push(result.error ?? "fcm");
    }
  }

  if (delivered > 0 || transient.length === 0) {
    await mark(admin, row.id, new Date().toISOString(), null);
    return true;
  }
  await mark(admin, row.id, null, transient.join("; ").slice(0, 500));
  return false;
}

async function mark(
  admin: ReturnType<typeof createClient>,
  id: number,
  sentAt: string | null,
  error: string | null,
) {
  await admin
    .from("notifications_outbox")
    .update({ sent_at: sentAt, error })
    .eq("id", id);
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  text: { title: string; body: string },
  data: Record<string, string>,
): Promise<{ ok: boolean; invalid: boolean; error?: string }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: text.title, body: text.body },
          data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channelId,
              sound: "default",
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                alert: { title: text.title, body: text.body },
                sound: "default",
                badge: 1,
              },
            },
          },
        },
      }),
    },
  );
  if (res.ok) return { ok: true, invalid: false };
  const raw = await res.text();
  const invalid = res.status === 404 ||
    /UNREGISTERED|NOT_FOUND|INVALID_ARGUMENT/.test(raw);
  return { ok: false, invalid, error: raw.slice(0, 300) };
}

function pushText(type: string, payload: Record<string, unknown>) {
  const member = clean(payload.member_name);
  const watcher = clean(payload.watcher_name);
  const place = clean(payload.place_name);
  switch (type) {
    case "member_joined":
      return {
        title: "Novo integrante",
        body: member ? `${member} entrou no grupo` : "Alguém entrou no grupo",
      };
    case "alert_created_about_you":
      return {
        title: "Alerta sobre você",
        body: alertBody(watcher, place),
      };
    default:
      return {
        title: clean(payload.title) ?? "Radar Familiar",
        body: clean(payload.body) ?? "Você tem uma nova notificação",
      };
  }
}

function alertBody(watcher: string | null, place: string | null) {
  if (watcher && place) return `${watcher} criou um alerta em ${place}`;
  if (watcher) return `${watcher} criou um alerta sobre você`;
  if (place) return `Criaram um alerta sobre você em ${place}`;
  return "Criaram um alerta sobre você";
}

function clean(value: unknown): string | null {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text || text === "null") return null;
  return text;
}

function stringData(
  payload: Record<string, unknown>,
  extra: Record<string, string>,
): Record<string, string> {
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(payload)) {
    if (value == null) continue;
    data[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return { ...data, ...extra };
}

async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: account.client_email,
    scope: fcmScope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${b64url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error(json.error_description ?? json.error ?? "oauth");
  }
  return json.access_token as string;
}

function pemToBytes(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(b64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
