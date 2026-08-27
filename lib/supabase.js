import { createClient } from "@supabase/supabase-js";

export function json(res, status, payload) { return res.status(status).json(payload); }

export function getAdminClient() {
  const url = process.env.VITE_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Server-side Supabase configuration is missing.");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export async function requireUser(req) {
  const authorization = req.headers.authorization || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : null;
  if (!token) return null;
  const supabase = getAdminClient();
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;
  const { data: profile } = await supabase.from("profiles").select("id, role, is_suspended").eq("id", data.user.id).single();
  if (!profile || profile.is_suspended) return null;
  return { user: data.user, profile, supabase };
}

export async function requireAdmin(req) {
  const context = await requireUser(req);
  if (!context || context.profile.role !== "ADMIN") return null;
  return context;
}
