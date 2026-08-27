import { json, requireUser } from "../lib/supabase.js";
export default async function handler(req, res) {
  if (req.method !== "GET") return json(res, 405, { success:false, message:"Method not allowed" });
  try { const context = await requireUser(req); return json(res, 200, { success:true, authenticated:Boolean(context), user:context ? { id:context.user.id, role:context.profile.role } : null }); }
  catch (error) { return json(res, 500, { success:false, message:error.message || "Auth service error" }); }
}
