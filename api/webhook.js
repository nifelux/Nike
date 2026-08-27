import { json } from "../lib/supabase.js";
// Intentionally disabled until a payment provider's documented signature validation is implemented.
export default async function handler(_req, res) {
  return json(res, 501, { success:false, message:"Webhook is disabled. Implement provider signature verification in lib/payment-provider.js before enabling it." });
}
