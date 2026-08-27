import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const entry = (file) => resolve(__dirname, file);

// Blacktop Ledger follows the LAS-VEGAS multi-page Vercel build architecture:
// every member and admin page is a direct, deployable HTML entry point.
export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: entry("index.html"),
        login: entry("login.html"),
        register: entry("register.html"),
        dashboard: entry("dashboard.html"),
        plans: entry("plans.html"),
        investment: entry("investment.html"),
        wallet: entry("wallet.html"),
        deposit: entry("deposit.html"),
        withdraw: entry("withdraw.html"),
        earnings: entry("earnings.html"),
        daily_checkin: entry("daily-checkin.html"),
        transactions: entry("transactions.html"),
        referrals: entry("referrals.html"),
        gift_code: entry("gift-code.html"),
        notifications: entry("notifications.html"),
        profile: entry("profile.html"),
        support: entry("support.html"),
        my_investment: entry("my-investments.html"),
        admin_login: entry("admin/login.html"),
        admin_dashboard: entry("admin/index.html"),
        admin_users: entry("admin/users.html"),
        admin_user_details: entry("admin/user-details.html"),
        admin_plans: entry("admin/plans.html"),
        admin_investments: entry("admin/investments.html"),
        admin_earnings: entry("admin/earnings.html"),
        admin_deposits: entry("admin/deposits.html"),
        admin_withdrawals: entry("admin/withdrawals.html"),
        admin_transactions: entry("admin/transactions.html"),
        admin_daily_checkins: entry("admin/daily-checkins.html"),
        admin_referrals: entry("admin/referrals.html"),
        admin_gift_codes: entry("admin/gift-codes.html"),
        admin_notifications: entry("admin/notifications.html"),
        admin_payments: entry("admin/glopayment.html"),
        admin_payout_accounts: entry("admin/payout-accounts.html"),
        admin_reports: entry("admin/reports.html"),
        admin_settings: entry("admin/settings.html"),
        admin_view_member_dashboard: entry("admin/view-member-dashboard.html")
      }
    }
  }
});
