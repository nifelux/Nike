import { getAdminClient, json } from "../lib/supabase.js";
export default async function handler(req, res) {
  if (req.headers.authorization !== "Bearer " + process.env.CRON_SECRET) return json(res, 401, { success:false, message:"Unauthorized cron request" });
  try { const supabase = getAdminClient(); const { data, error } = await supabase.rpc("settle_matured_investments"); if (error) throw error; return json(res, 200, { success:true, settled:data }); }
  catch (error) { return json(res, 500, { success:false, message:error.message || "Cron service error" }); }
}
