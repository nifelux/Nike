import { json, requireUser } from "../lib/supabase.js";

export default async function handler(req, res) {
  try {
    const context = await requireUser(req);
    if (!context) return json(res, 401, { success:false, message:"Authentication required" });
    const resource = String(req.query.resource || "");
    const action = String(req.query.action || "");
    const { supabase, user } = context;

    if (req.method === "GET" && resource === "investments" && action === "plans") {
      const { data, error } = await supabase.from("plans").select("*").eq("is_active", true).order("sort_order");
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ plans:data } });
    }
    if (req.method === "GET" && resource === "investments" && action === "list") {
      const { data, error } = await supabase.from("investments").select("*").eq("user_id", user.id).order("created_at", { ascending:false });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ investments:data } });
    }
    if (req.method === "POST" && resource === "investments" && action === "purchase") {
      const { plan_id, amount, user_note } = req.body || {};
      const { data, error } = await supabase.rpc("process_investment_purchase", { p_plan_id:plan_id, p_amount:amount, p_user_note:user_note || null });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ investment_id:data } });
    }
    if (req.method === "GET" && resource === "withdrawals" && action === "accounts") {
      const { data, error } = await supabase.from("withdrawal_accounts").select("id,label,account_holder_name,bank_name,account_last4,is_default,is_verified").eq("user_id", user.id).order("is_default", { ascending:false });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ accounts:data } });
    }
    if (req.method === "POST" && resource === "withdrawals" && action === "request") {
      const { withdrawal_account_id, amount } = req.body || {};
      const { data, error } = await supabase.rpc("request_withdrawal", { p_withdrawal_account_id:withdrawal_account_id, p_amount:amount });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ withdrawal_id:data } });
    }
    if (req.method === "POST" && resource === "payments" && action === "submit-manual-deposit") {
      const { amount, reference, payment_provider, proof_url } = req.body || {};
      if (!Number(amount) || Number(amount) <= 0 || !reference) return json(res, 400, { success:false, message:"Amount and reference are required" });
      const { data, error } = await supabase.from("deposits").insert({ user_id:user.id, amount:Number(amount), reference:String(reference).trim(), payment_provider:payment_provider || "MANUAL", proof_url:proof_url || null, status:"PENDING" }).select().single();
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ deposit:data } });
    }
    if (req.method === "POST" && resource === "rewards" && action === "redeem-gift") {
      const { code } = req.body || {}; const { data, error } = await supabase.rpc("redeem_gift_code", { p_code:code });
      return json(res, error ? 400 : 200, error ? { success:false, message:error.message } : { success:true, data:{ redemption_id:data } });
    }
    return json(res, 404, { success:false, message:"Unsupported finance resource or action" });
  } catch (error) { return json(res, 500, { success:false, message:error.message || "Finance service error" }); }
}
