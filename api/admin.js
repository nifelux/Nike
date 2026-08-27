import { json, requireAdmin } from "../lib/supabase.js";

export default async function handler(req, res) {
  try {
    const context = await requireAdmin(req);
    if (!context) return json(res, 403, { success:false, message:"Administrator permission required" });
    const resource = String(req.query.resource || ""); const action = String(req.query.action || ""); const { supabase } = context;
    if (req.method === "GET" && resource === "dashboard") {
      const [deposits, withdrawals, investors, tickets] = await Promise.all([
        supabase.from("deposits").select("id", { count:"exact", head:true }).in("status", ["PENDING","PROCESSING"]),
        supabase.from("withdrawals").select("id", { count:"exact", head:true }).in("status", ["PENDING","APPROVED","PROCESSING"]),
        supabase.from("profiles").select("id", { count:"exact", head:true }).eq("role", "INVESTOR"),
        supabase.from("support_tickets").select("id", { count:"exact", head:true }).in("status", ["OPEN","IN_PROGRESS"])
      ]);
      return json(res, 200, { success:true, data:{ pending_deposits:deposits.count || 0, pending_withdrawals:withdrawals.count || 0, active_investors:investors.count || 0, unresolved_tickets:tickets.count || 0 } });
    }
    if (req.method === "GET" && resource === "settings") {
      const { data, error } = await supabase.from("settings").select("*").order("key");
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ settings:data } });
    }
    if (req.method === "POST" && resource === "deposits" && action === "approve") {
      const { deposit_id, note } = req.body || {}; const { error } = await supabase.rpc("approve_deposit", { p_deposit_id:deposit_id, p_note:note || null });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true });
    }
    if (req.method === "POST" && resource === "withdrawals" && action === "complete") {
      const { withdrawal_id, provider_reference, note } = req.body || {}; const { error } = await supabase.rpc("complete_withdrawal", { p_withdrawal_id:withdrawal_id, p_provider_reference:provider_reference || null, p_note:note || null });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true });
    }
    return json(res, 404, { success:false, message:"Unsupported admin resource or action" });
  } catch (error) { return json(res, 500, { success:false, message:error.message || "Admin service error" }); }
}
