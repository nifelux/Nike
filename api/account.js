import { json, requireUser } from "../lib/supabase.js";

export default async function handler(req, res) {
  try {
    const context = await requireUser(req);
    if (!context) return json(res, 401, { success:false, message:"Authentication required" });
    if (req.method === "GET") {
      const [{ data: profile }, { data: wallet }, { data: referral }] = await Promise.all([
        context.supabase.from("profiles").select("id,email,full_name,phone,country_code,verification_status").eq("id", context.user.id).single(),
        context.supabase.from("wallets").select("*").eq("user_id", context.user.id).single(),
        context.supabase.from("referral_codes").select("code,is_active").eq("user_id", context.user.id).single()
      ]);
      return json(res, 200, { success:true, data:{ profile, wallet, referral } });
    }
    if (req.method === "PATCH") {
      const allowed = (({ full_name, phone, country_code, avatar_url }) => ({ full_name, phone, country_code, avatar_url }))(req.body || {});
      const { data, error } = await context.supabase.from("profiles").update(allowed).eq("id", context.user.id).select().single();
      if (error) return json(res, 400, { success:false, message:error.message });
      return json(res, 200, { success:true, data });
    }
    return json(res, 405, { success:false, message:"Method not allowed" });
  } catch (error) { return json(res, 500, { success:false, message:error.message || "Account service error" }); }
}
