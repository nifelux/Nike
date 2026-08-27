// Payment-provider boundary. Keep live provider credentials and signatures server-side only.
export function paymentProviderConfigured() {
  return Boolean(process.env.PAYMENT_PROVIDER_BASE_URL && process.env.PAYMENT_PROVIDER_MERCHANT_ID && process.env.PAYMENT_PROVIDER_SIGNING_KEY);
}

export async function createFundingIntent() {
  if (!paymentProviderConfigured()) throw new Error("Payment provider is not configured.");
  throw new Error("Implement the provider's signed server-side request here after confirming its API contract.");
}

export async function verifyWebhook() {
  if (!process.env.PAYMENT_WEBHOOK_SECRET) throw new Error("PAYMENT_WEBHOOK_SECRET is not configured.");
  throw new Error("Implement the provider's documented webhook signature verification here before enabling this endpoint.");
}
