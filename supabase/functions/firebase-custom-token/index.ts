const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const base64Url = (bytes: Uint8Array) => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
};

const encodeJson = (value: unknown) =>
  base64Url(new TextEncoder().encode(JSON.stringify(value)));

const privateKeyBytes = (pem: string) => {
  const normalized = pem.replaceAll("\\n", "\n");
  const content = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const binary = atob(content);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return jsonResponse({ error: "missing_supabase_session" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  let injectedPublishableKey = "";
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    injectedPublishableKey = typeof keys.default === "string" ? keys.default : "";
  } catch (_) {
    // Older Supabase projects expose a single anon or publishable key instead.
  }
  const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? injectedPublishableKey;
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  const expectedProject = Deno.env.get("FIREBASE_PROJECT_ID") ?? "ecoscanai-66682";
  if (!supabaseUrl || !supabaseKey || !serviceAccountJson) {
    return jsonResponse({ error: "server_not_configured" }, 503);
  }

  try {
    const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${match[1]}`,
      },
    });
    if (!userResponse.ok) return jsonResponse({ error: "invalid_supabase_session" }, 401);

    const user = await userResponse.json();
    if (typeof user.id !== "string" || !user.id) {
      return jsonResponse({ error: "invalid_supabase_user" }, 401);
    }

    const serviceAccount = JSON.parse(serviceAccountJson);
    if (serviceAccount.project_id !== expectedProject) {
      return jsonResponse({ error: "firebase_project_mismatch" }, 500);
    }
    const now = Math.floor(Date.now() / 1000);
    const unsigned = `${encodeJson({ alg: "RS256", typ: "JWT" })}.${encodeJson({
      iss: serviceAccount.client_email,
      sub: serviceAccount.client_email,
      aud: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
      iat: now,
      exp: now + 3600,
      uid: user.id,
      claims: { supabase_uid: user.id },
    })}`;

    const key = await crypto.subtle.importKey(
      "pkcs8",
      privateKeyBytes(serviceAccount.private_key),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    );
    return jsonResponse({ customToken: `${unsigned}.${base64Url(new Uint8Array(signature))}` });
  } catch (_error) {
    // Never return credential material or raw authentication tokens to clients.
    return jsonResponse({ error: "firebase_session_creation_failed" }, 500);
  }
});
