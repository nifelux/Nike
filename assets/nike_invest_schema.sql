-- Nike Investor — Supabase/PostgreSQL Schema
--
-- Purpose: implementation-ready data layer for the Nike Investor concept UI.
-- This script mirrors the supplied reference product's architecture: authentication profiles,
-- wallet/deposits/withdrawals, investment plans and positions, earnings, referrals, rewards,
-- notifications, support, administration, audit trails, row-level security, and guarded RPCs.
--
-- Important: this is a platform schema, not financial, legal, or payment-processing advice.
-- Connect live payments, KYC/AML, custody, market data, and regulatory controls through secured
-- server-side services before any production use. Do not expose the service-role key to a browser.

begin;

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- =============================================================================
-- 1. Enumerations
-- =============================================================================

do $$ begin
  create type public.user_role as enum ('INVESTOR', 'ADMIN', 'SUPPORT');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.verification_status as enum ('UNVERIFIED', 'PENDING', 'VERIFIED', 'REJECTED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.investment_status as enum ('PENDING', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'SUSPENDED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.deposit_status as enum ('PENDING', 'PROCESSING', 'COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.withdrawal_status as enum ('PENDING', 'APPROVED', 'PROCESSING', 'COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.transaction_type as enum ('DEPOSIT', 'WITHDRAWAL', 'INVESTMENT', 'EARNING', 'PRINCIPAL_RETURN', 'REFERRAL_REWARD', 'GIFT_REWARD', 'TASK_REWARD', 'ADJUSTMENT');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.transaction_direction as enum ('CREDIT', 'DEBIT');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.transaction_status as enum ('PENDING', 'COMPLETED', 'REJECTED', 'FAILED', 'REVERSED', 'CANCELLED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_type as enum ('SYSTEM', 'DEPOSIT', 'WITHDRAWAL', 'INVESTMENT', 'EARNING', 'REFERRAL', 'REWARD', 'SUPPORT');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ticket_status as enum ('OPEN', 'IN_PROGRESS', 'WAITING_ON_USER', 'RESOLVED', 'CLOSED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ticket_priority as enum ('LOW', 'NORMAL', 'HIGH', 'URGENT');
exception when duplicate_object then null;
end $$;

-- =============================================================================
-- 2. Core identity, wallet, and platform configuration
-- =============================================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email citext not null unique,
  full_name text,
  phone text,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  avatar_url text,
  role public.user_role not null default 'INVESTOR',
  verification_status public.verification_status not null default 'UNVERIFIED',
  is_suspended boolean not null default false,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  available_balance numeric(18,2) not null default 0 check (available_balance >= 0),
  allocated_balance numeric(18,2) not null default 0 check (allocated_balance >= 0),
  earned_balance numeric(18,2) not null default 0 check (earned_balance >= 0),
  pending_withdrawal_balance numeric(18,2) not null default 0 check (pending_withdrawal_balance >= 0),
  lifetime_deposited numeric(18,2) not null default 0 check (lifetime_deposited >= 0),
  lifetime_withdrawn numeric(18,2) not null default 0 check (lifetime_withdrawn >= 0),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.settings (
  key text primary key,
  value jsonb not null,
  description text,
  is_public boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- =============================================================================
-- 3. Investment catalogue, positions, earnings, and ledger
-- =============================================================================

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9_-]{3,32}$'),
  name text not null unique,
  description text not null,
  minimum_amount numeric(18,2) not null check (minimum_amount > 0),
  maximum_amount numeric(18,2) check (maximum_amount is null or maximum_amount >= minimum_amount),
  term_days integer not null check (term_days between 1 and 3650),
  target_return_bps integer not null check (target_return_bps between 0 and 100000),
  referral_commission_bps integer not null default 0 check (referral_commission_bps between 0 and 10000),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.investments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  plan_id uuid not null references public.plans(id) on delete restrict,
  plan_code_snapshot text not null,
  plan_name_snapshot text not null,
  principal_amount numeric(18,2) not null check (principal_amount > 0),
  target_return_amount numeric(18,2) not null default 0 check (target_return_amount >= 0),
  earnings_received numeric(18,2) not null default 0 check (earnings_received >= 0),
  status public.investment_status not null default 'PENDING',
  started_at timestamptz,
  matures_at timestamptz,
  completed_at timestamptz,
  user_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status in ('PENDING', 'ACTIVE', 'SUSPENDED') and completed_at is null) or (status in ('COMPLETED', 'CANCELLED') and completed_at is not null)),
  check (matures_at is null or started_at is null or matures_at > started_at)
);

create table if not exists public.investment_earnings (
  id uuid primary key default gen_random_uuid(),
  investment_id uuid not null references public.investments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  effective_on date not null,
  reference text not null unique,
  source text not null default 'SCHEDULED' check (source in ('SCHEDULED', 'MANUAL', 'ADJUSTMENT')),
  created_at timestamptz not null default now(),
  unique (investment_id, effective_on)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  transaction_type public.transaction_type not null,
  direction public.transaction_direction not null,
  status public.transaction_status not null default 'PENDING',
  amount numeric(18,2) not null check (amount > 0),
  balance_after numeric(18,2) not null check (balance_after >= 0),
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  reference text not null unique,
  related_entity_type text,
  related_entity_id uuid,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =============================================================================
-- 4. Deposits, withdrawals, and destination accounts
-- =============================================================================

create table if not exists public.deposits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  reference text not null unique,
  payment_provider text,
  provider_reference text,
  depositor_bank_name text,
  depositor_account_name text,
  proof_url text,
  status public.deposit_status not null default 'PENDING',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status in ('COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED')) = (reviewed_at is not null or status = 'FAILED'))
);

create table if not exists public.withdrawal_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text not null,
  account_holder_name text not null,
  bank_name text not null,
  bank_code text,
  account_number_encrypted text not null,
  account_last4 char(4) not null check (account_last4 ~ '^[0-9]{4}$'),
  routing_number_encrypted text,
  is_default boolean not null default false,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists withdrawal_accounts_one_default_per_user
  on public.withdrawal_accounts (user_id) where is_default;

create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  withdrawal_account_id uuid not null references public.withdrawal_accounts(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  fee_amount numeric(18,2) not null default 0 check (fee_amount >= 0),
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  reference text not null unique,
  provider_reference text,
  status public.withdrawal_status not null default 'PENDING',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_note text,
  paid_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =============================================================================
-- 5. Referral and engagement rewards
-- =============================================================================

create table if not exists public.referral_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9-]{6,40}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_user_id uuid not null references public.profiles(id) on delete restrict,
  referred_user_id uuid not null unique references public.profiles(id) on delete restrict,
  referral_code_id uuid references public.referral_codes(id) on delete set null,
  status text not null default 'REGISTERED' check (status in ('REGISTERED', 'VERIFIED', 'ACTIVE', 'INACTIVE')),
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  check (referrer_user_id <> referred_user_id)
);

create table if not exists public.referral_commissions (
  id uuid primary key default gen_random_uuid(),
  referrer_user_id uuid not null references public.profiles(id) on delete restrict,
  source_user_id uuid not null references public.profiles(id) on delete restrict,
  investment_id uuid not null references public.investments(id) on delete restrict,
  level smallint not null default 1 check (level between 1 and 5),
  commission_amount numeric(18,2) not null check (commission_amount > 0),
  reference text not null unique,
  created_at timestamptz not null default now(),
  check (referrer_user_id <> source_user_id),
  unique (referrer_user_id, investment_id, level)
);

create table if not exists public.gift_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9-]{6,64}$'),
  reward_amount numeric(18,2) not null check (reward_amount > 0),
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  redemption_count integer not null default 0 check (redemption_count >= 0),
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create table if not exists public.gift_redemptions (
  id uuid primary key default gen_random_uuid(),
  gift_code_id uuid not null references public.gift_codes(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  reward_amount numeric(18,2) not null check (reward_amount > 0),
  reference text not null unique,
  redeemed_at timestamptz not null default now(),
  unique (gift_code_id, user_id)
);

create table if not exists public.engagement_tasks (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_-]{3,64}$'),
  title text not null,
  description text not null,
  reward_amount numeric(18,2) not null check (reward_amount >= 0),
  currency char(3) not null default 'USD' check (currency = upper(currency)),
  verification_mode text not null default 'MANUAL' check (verification_mode in ('MANUAL', 'WEBHOOK', 'AUTOMATIC')),
  is_active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table if not exists public.task_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.engagement_tasks(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'PENDING' check (status in ('PENDING', 'VERIFIED', 'REJECTED', 'REWARDED')),
  proof_url text,
  verifier_note text,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  reference text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (task_id, user_id)
);

-- =============================================================================
-- 6. Notifications, support, and administration
-- =============================================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type public.notification_type not null default 'SYSTEM',
  title text not null,
  message text not null,
  action_url text,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  subject text not null check (char_length(subject) between 3 and 160),
  status public.ticket_status not null default 'OPEN',
  priority public.ticket_priority not null default 'NORMAL',
  assigned_to uuid references public.profiles(id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  body text not null check (char_length(body) between 1 and 5000),
  is_internal boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_state jsonb,
  after_state jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

-- =============================================================================
-- 7. Indexes
-- =============================================================================

create index if not exists profiles_role_idx on public.profiles(role) where is_suspended = false;
create index if not exists investments_user_status_idx on public.investments(user_id, status, created_at desc);
create index if not exists investments_maturity_idx on public.investments(status, matures_at) where status = 'ACTIVE';
create index if not exists investment_earnings_user_idx on public.investment_earnings(user_id, effective_on desc);
create index if not exists transactions_user_created_idx on public.transactions(user_id, created_at desc);
create index if not exists transactions_status_idx on public.transactions(status, created_at desc);
create index if not exists deposits_user_status_idx on public.deposits(user_id, status, created_at desc);
create index if not exists deposits_pending_idx on public.deposits(created_at) where status in ('PENDING', 'PROCESSING');
create index if not exists withdrawals_user_status_idx on public.withdrawals(user_id, status, created_at desc);
create index if not exists withdrawals_pending_idx on public.withdrawals(created_at) where status in ('PENDING', 'APPROVED', 'PROCESSING');
create index if not exists notifications_unread_idx on public.notifications(user_id, created_at desc) where read_at is null;
create index if not exists referrals_referrer_idx on public.referrals(referrer_user_id, created_at desc);
create index if not exists referral_commissions_referrer_idx on public.referral_commissions(referrer_user_id, created_at desc);
create index if not exists support_tickets_user_idx on public.support_tickets(user_id, status, updated_at desc);
create index if not exists support_messages_ticket_idx on public.support_messages(ticket_id, created_at);
create index if not exists admin_audit_logs_entity_idx on public.admin_audit_logs(entity_type, entity_id, created_at desc);

-- =============================================================================
-- 8. Triggers and guarded helper functions
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'ADMIN' and is_suspended = false
  );
$$;

create or replace function public.is_platform_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('ADMIN', 'SUPPORT') and is_suspended = false
  );
$$;

create or replace function public.write_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_before_state jsonb default null,
  p_after_state jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_audit_logs(actor_id, action, entity_type, entity_id, before_state, after_state)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_before_state, p_after_state);
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_referral_code text;
  v_referrer_id uuid;
  v_referral_code_id uuid;
begin
  insert into public.profiles (id, email, full_name, phone, country_code)
  values (
    new.id,
    coalesce(new.email, concat(new.id::text, '@invalid.local')),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), ''),
    nullif(upper(trim(coalesce(new.raw_user_meta_data ->> 'country_code', ''))), '')
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.referral_codes (user_id, code)
  values (new.id, concat('NKE-', upper(substring(replace(new.id::text, '-', '') from 1 for 10))))
  on conflict (user_id) do nothing;

  v_referral_code := upper(nullif(trim(coalesce(new.raw_user_meta_data ->> 'referral_code', '')), ''));
  if v_referral_code is not null then
    select rc.user_id, rc.id into v_referrer_id, v_referral_code_id
    from public.referral_codes rc
    where rc.code = v_referral_code and rc.is_active = true
    limit 1;

    if v_referrer_id is not null and v_referrer_id <> new.id then
      insert into public.referrals(referrer_user_id, referred_user_id, referral_code_id)
      values (v_referrer_id, new.id, v_referral_code_id)
      on conflict (referred_user_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.record_transaction(
  p_user_id uuid,
  p_transaction_type public.transaction_type,
  p_direction public.transaction_direction,
  p_amount numeric,
  p_status public.transaction_status,
  p_reference text,
  p_related_entity_type text default null,
  p_related_entity_id uuid default null,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction_id uuid;
  v_balance numeric(18,2);
begin
  if p_amount <= 0 then
    raise exception 'Transaction amount must be positive';
  end if;

  select available_balance into v_balance from public.wallets where user_id = p_user_id;
  if v_balance is null then
    raise exception 'Wallet not found for user %', p_user_id;
  end if;

  insert into public.transactions (
    user_id, transaction_type, direction, status, amount, balance_after, reference,
    related_entity_type, related_entity_id, description, metadata
  ) values (
    p_user_id, p_transaction_type, p_direction, p_status, p_amount, v_balance, p_reference,
    p_related_entity_type, p_related_entity_id, p_description, coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_transaction_id;

  return v_transaction_id;
end;
$$;

-- Create an investment safely. The browser should call this RPC with the anonymous key;
-- the wallet debit and position creation are made atomic by row locking.
create or replace function public.process_investment_purchase(p_plan_id uuid, p_amount numeric, p_user_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan public.plans%rowtype;
  v_wallet public.wallets%rowtype;
  v_investment_id uuid;
  v_target_return numeric(18,2);
  v_reference text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;

  select * into v_plan from public.plans where id = p_plan_id and is_active = true;
  if not found then raise exception 'Investment plan is unavailable'; end if;
  if p_amount < v_plan.minimum_amount then raise exception 'Amount is below plan minimum'; end if;
  if v_plan.maximum_amount is not null and p_amount > v_plan.maximum_amount then raise exception 'Amount exceeds plan maximum'; end if;

  select * into v_wallet from public.wallets where user_id = v_user_id for update;
  if not found or v_wallet.available_balance < p_amount then raise exception 'Insufficient available balance'; end if;

  v_target_return := round(p_amount * v_plan.target_return_bps / 10000.0, 2);
  insert into public.investments (
    user_id, plan_id, plan_code_snapshot, plan_name_snapshot, principal_amount, target_return_amount,
    status, started_at, matures_at, user_note
  ) values (
    v_user_id, v_plan.id, v_plan.code, v_plan.name, p_amount, v_target_return,
    'ACTIVE', now(), now() + make_interval(days => v_plan.term_days), nullif(trim(p_user_note), '')
  ) returning id into v_investment_id;

  update public.wallets
  set available_balance = available_balance - p_amount,
      allocated_balance = allocated_balance + p_amount,
      version = version + 1
  where user_id = v_user_id;

  v_reference := concat('INV-', upper(substring(replace(v_investment_id::text, '-', '') from 1 for 12)));
  perform public.record_transaction(v_user_id, 'INVESTMENT', 'DEBIT', p_amount, 'COMPLETED', v_reference, 'investment', v_investment_id, concat('Allocation opened: ', v_plan.name), jsonb_build_object('plan_code', v_plan.code));

  insert into public.notifications(user_id, notification_type, title, message, action_url, metadata)
  values (v_user_id, 'INVESTMENT', 'Allocation opened', concat('Your ', v_plan.name, ' allocation is active.'), '/portfolio', jsonb_build_object('investment_id', v_investment_id));

  return v_investment_id;
end;
$$;

-- Request a withdrawal while atomically reserving available balance.
create or replace function public.request_withdrawal(p_withdrawal_account_id uuid, p_amount numeric)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.wallets%rowtype;
  v_withdrawal_id uuid;
  v_reference text;
  v_locked boolean;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  select coalesce((value ->> 'enabled')::boolean, false) into v_locked from public.settings where key = 'withdrawals_locked';
  if coalesce(v_locked, false) then raise exception 'Withdrawals are temporarily unavailable'; end if;
  if not exists (select 1 from public.withdrawal_accounts where id = p_withdrawal_account_id and user_id = v_user_id) then raise exception 'Invalid withdrawal account'; end if;

  select * into v_wallet from public.wallets where user_id = v_user_id for update;
  if not found or v_wallet.available_balance < p_amount then raise exception 'Insufficient available balance'; end if;

  v_reference := concat('WD-', upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12)));
  insert into public.withdrawals(user_id, withdrawal_account_id, amount, reference)
  values (v_user_id, p_withdrawal_account_id, p_amount, v_reference)
  returning id into v_withdrawal_id;

  update public.wallets
  set available_balance = available_balance - p_amount,
      pending_withdrawal_balance = pending_withdrawal_balance + p_amount,
      version = version + 1
  where user_id = v_user_id;

  perform public.record_transaction(v_user_id, 'WITHDRAWAL', 'DEBIT', p_amount, 'PENDING', v_reference, 'withdrawal', v_withdrawal_id, 'Withdrawal request submitted');
  insert into public.notifications(user_id, notification_type, title, message, action_url, metadata)
  values (v_user_id, 'WITHDRAWAL', 'Withdrawal request received', concat('Your request for $', to_char(p_amount, 'FM999,999,999,990.00'), ' is pending review.'), '/transactions', jsonb_build_object('withdrawal_id', v_withdrawal_id));
  return v_withdrawal_id;
end;
$$;

-- Approve a completed deposit and credit its wallet exactly once.
create or replace function public.approve_deposit(p_deposit_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit public.deposits%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'Administrator permission required'; end if;
  select * into v_deposit from public.deposits where id = p_deposit_id for update;
  if not found then raise exception 'Deposit not found'; end if;
  if v_deposit.status <> 'PENDING' then raise exception 'Deposit is not pending'; end if;

  update public.deposits set status = 'COMPLETED', reviewed_by = auth.uid(), reviewed_at = now(), reviewer_note = nullif(trim(p_note), '') where id = p_deposit_id;
  update public.wallets set available_balance = available_balance + v_deposit.amount, lifetime_deposited = lifetime_deposited + v_deposit.amount, version = version + 1 where user_id = v_deposit.user_id;
  perform public.record_transaction(v_deposit.user_id, 'DEPOSIT', 'CREDIT', v_deposit.amount, 'COMPLETED', v_deposit.reference, 'deposit', v_deposit.id, 'Capital addition approved');
  insert into public.notifications(user_id, notification_type, title, message, action_url) values (v_deposit.user_id, 'DEPOSIT', 'Capital added', concat('$', to_char(v_deposit.amount, 'FM999,999,999,990.00'), ' is now available for allocation.'), '/wallet');
  perform public.write_audit_log('APPROVE_DEPOSIT', 'deposit', p_deposit_id, to_jsonb(v_deposit), jsonb_build_object('status', 'COMPLETED', 'note', p_note));
end;
$$;

-- Complete a withdrawal request already reserved by request_withdrawal().
create or replace function public.complete_withdrawal(p_withdrawal_id uuid, p_provider_reference text default null, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_withdrawal public.withdrawals%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'Administrator permission required'; end if;
  select * into v_withdrawal from public.withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Withdrawal not found'; end if;
  if v_withdrawal.status not in ('PENDING', 'APPROVED', 'PROCESSING') then raise exception 'Withdrawal cannot be completed from its current state'; end if;

  update public.withdrawals set status = 'COMPLETED', provider_reference = nullif(trim(p_provider_reference), ''), reviewed_by = auth.uid(), reviewed_at = coalesce(reviewed_at, now()), reviewer_note = nullif(trim(p_note), ''), paid_at = now() where id = p_withdrawal_id;
  update public.wallets set pending_withdrawal_balance = pending_withdrawal_balance - v_withdrawal.amount, lifetime_withdrawn = lifetime_withdrawn + v_withdrawal.amount, version = version + 1 where user_id = v_withdrawal.user_id;
  update public.transactions set status = 'COMPLETED' where reference = v_withdrawal.reference and transaction_type = 'WITHDRAWAL';
  insert into public.notifications(user_id, notification_type, title, message, action_url) values (v_withdrawal.user_id, 'WITHDRAWAL', 'Withdrawal completed', concat('$', to_char(v_withdrawal.amount, 'FM999,999,999,990.00'), ' was marked paid.'), '/transactions');
  perform public.write_audit_log('COMPLETE_WITHDRAWAL', 'withdrawal', p_withdrawal_id, to_jsonb(v_withdrawal), jsonb_build_object('status', 'COMPLETED', 'provider_reference', p_provider_reference));
end;
$$;

-- Reject a withdrawal and safely release its reserved balance.
create or replace function public.reject_withdrawal(p_withdrawal_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_withdrawal public.withdrawals%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'Administrator permission required'; end if;
  if nullif(trim(p_note), '') is null then raise exception 'A rejection note is required'; end if;
  select * into v_withdrawal from public.withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Withdrawal not found'; end if;
  if v_withdrawal.status not in ('PENDING', 'APPROVED', 'PROCESSING') then raise exception 'Withdrawal cannot be rejected from its current state'; end if;

  update public.withdrawals set status = 'REJECTED', reviewed_by = auth.uid(), reviewed_at = now(), reviewer_note = p_note where id = p_withdrawal_id;
  update public.wallets set available_balance = available_balance + v_withdrawal.amount, pending_withdrawal_balance = pending_withdrawal_balance - v_withdrawal.amount, version = version + 1 where user_id = v_withdrawal.user_id;
  update public.transactions set status = 'REVERSED' where reference = v_withdrawal.reference and transaction_type = 'WITHDRAWAL';
  insert into public.notifications(user_id, notification_type, title, message, action_url) values (v_withdrawal.user_id, 'WITHDRAWAL', 'Withdrawal returned', concat('$', to_char(v_withdrawal.amount, 'FM999,999,999,990.00'), ' was restored to available capital. ', p_note), '/wallet');
  perform public.write_audit_log('REJECT_WITHDRAWAL', 'withdrawal', p_withdrawal_id, to_jsonb(v_withdrawal), jsonb_build_object('status', 'REJECTED', 'note', p_note));
end;
$$;

-- Credit a position's earnings. Call only from an authorised scheduled worker or admin workflow.
create or replace function public.post_investment_earning(p_investment_id uuid, p_amount numeric, p_effective_on date default current_date, p_source text default 'SCHEDULED')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_investment public.investments%rowtype;
  v_earning_id uuid;
  v_reference text;
begin
  if not public.is_platform_admin() then raise exception 'Administrator permission required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Earning amount must be positive'; end if;
  if p_source not in ('SCHEDULED', 'MANUAL', 'ADJUSTMENT') then raise exception 'Invalid earning source'; end if;
  select * into v_investment from public.investments where id = p_investment_id for update;
  if not found or v_investment.status <> 'ACTIVE' then raise exception 'Active investment not found'; end if;

  v_reference := concat('ER-', upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12)));
  insert into public.investment_earnings(investment_id, user_id, amount, effective_on, reference, source)
  values (v_investment.id, v_investment.user_id, p_amount, coalesce(p_effective_on, current_date), v_reference, p_source)
  returning id into v_earning_id;
  update public.investments set earnings_received = earnings_received + p_amount where id = v_investment.id;
  update public.wallets set available_balance = available_balance + p_amount, earned_balance = earned_balance + p_amount, version = version + 1 where user_id = v_investment.user_id;
  perform public.record_transaction(v_investment.user_id, 'EARNING', 'CREDIT', p_amount, 'COMPLETED', v_reference, 'investment_earning', v_earning_id, concat('Earnings posted: ', v_investment.plan_name_snapshot));
  insert into public.notifications(user_id, notification_type, title, message, action_url) values (v_investment.user_id, 'EARNING', 'Earnings posted', concat('$', to_char(p_amount, 'FM999,999,999,990.00'), ' was added to available capital.'), '/earnings');
  return v_earning_id;
end;
$$;

-- Return principal for matured active investments. Schedule this through a trusted server task.
create or replace function public.settle_matured_investments()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_investment public.investments%rowtype;
  v_count integer := 0;
  v_reference text;
begin
  if not public.is_platform_admin() then raise exception 'Administrator permission required'; end if;
  for v_investment in select * from public.investments where status = 'ACTIVE' and matures_at <= now() for update skip locked loop
    update public.investments set status = 'COMPLETED', completed_at = now() where id = v_investment.id;
    update public.wallets set available_balance = available_balance + v_investment.principal_amount, allocated_balance = allocated_balance - v_investment.principal_amount, version = version + 1 where user_id = v_investment.user_id;
    v_reference := concat('PR-', upper(substring(replace(v_investment.id::text, '-', '') from 1 for 12)));
    perform public.record_transaction(v_investment.user_id, 'PRINCIPAL_RETURN', 'CREDIT', v_investment.principal_amount, 'COMPLETED', v_reference, 'investment', v_investment.id, concat('Principal returned: ', v_investment.plan_name_snapshot));
    insert into public.notifications(user_id, notification_type, title, message, action_url) values (v_investment.user_id, 'INVESTMENT', 'Position maturity reached', concat('Principal for ', v_investment.plan_name_snapshot, ' is available in your wallet.'), '/portfolio');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Redeem an active gift code exactly once per user.
create or replace function public.redeem_gift_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_gift public.gift_codes%rowtype;
  v_redemption_id uuid;
  v_reference text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select * into v_gift from public.gift_codes where code = upper(trim(p_code)) for update;
  if not found or not v_gift.is_active then raise exception 'Gift code is invalid or inactive'; end if;
  if v_gift.starts_at is not null and v_gift.starts_at > now() then raise exception 'Gift code is not active yet'; end if;
  if v_gift.expires_at is not null and v_gift.expires_at <= now() then raise exception 'Gift code has expired'; end if;
  if v_gift.max_redemptions is not null and v_gift.redemption_count >= v_gift.max_redemptions then raise exception 'Gift code has reached its redemption limit'; end if;

  v_reference := concat('GF-', upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12)));
  insert into public.gift_redemptions(gift_code_id, user_id, reward_amount, reference)
  values (v_gift.id, v_user_id, v_gift.reward_amount, v_reference)
  returning id into v_redemption_id;
  update public.gift_codes set redemption_count = redemption_count + 1 where id = v_gift.id;
  update public.wallets set available_balance = available_balance + v_gift.reward_amount, earned_balance = earned_balance + v_gift.reward_amount, version = version + 1 where user_id = v_user_id;
  perform public.record_transaction(v_user_id, 'GIFT_REWARD', 'CREDIT', v_gift.reward_amount, 'COMPLETED', v_reference, 'gift_redemption', v_redemption_id, concat('Gift code redeemed: ', v_gift.code));
  return v_redemption_id;
end;
$$;

-- Updated-at triggers.
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists wallets_set_updated_at on public.wallets;
create trigger wallets_set_updated_at before update on public.wallets for each row execute function public.set_updated_at();
drop trigger if exists plans_set_updated_at on public.plans;
create trigger plans_set_updated_at before update on public.plans for each row execute function public.set_updated_at();
drop trigger if exists investments_set_updated_at on public.investments;
create trigger investments_set_updated_at before update on public.investments for each row execute function public.set_updated_at();
drop trigger if exists transactions_set_updated_at on public.transactions;
create trigger transactions_set_updated_at before update on public.transactions for each row execute function public.set_updated_at();
drop trigger if exists deposits_set_updated_at on public.deposits;
create trigger deposits_set_updated_at before update on public.deposits for each row execute function public.set_updated_at();
drop trigger if exists withdrawal_accounts_set_updated_at on public.withdrawal_accounts;
create trigger withdrawal_accounts_set_updated_at before update on public.withdrawal_accounts for each row execute function public.set_updated_at();
drop trigger if exists withdrawals_set_updated_at on public.withdrawals;
create trigger withdrawals_set_updated_at before update on public.withdrawals for each row execute function public.set_updated_at();
drop trigger if exists referral_codes_set_updated_at on public.referral_codes;
create trigger referral_codes_set_updated_at before update on public.referral_codes for each row execute function public.set_updated_at();
drop trigger if exists gift_codes_set_updated_at on public.gift_codes;
create trigger gift_codes_set_updated_at before update on public.gift_codes for each row execute function public.set_updated_at();
drop trigger if exists engagement_tasks_set_updated_at on public.engagement_tasks;
create trigger engagement_tasks_set_updated_at before update on public.engagement_tasks for each row execute function public.set_updated_at();
drop trigger if exists task_completions_set_updated_at on public.task_completions;
create trigger task_completions_set_updated_at before update on public.task_completions for each row execute function public.set_updated_at();
drop trigger if exists support_tickets_set_updated_at on public.support_tickets;
create trigger support_tickets_set_updated_at before update on public.support_tickets for each row execute function public.set_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- =============================================================================
-- 9. Row-level security policies
-- =============================================================================

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.settings enable row level security;
alter table public.plans enable row level security;
alter table public.investments enable row level security;
alter table public.investment_earnings enable row level security;
alter table public.transactions enable row level security;
alter table public.deposits enable row level security;
alter table public.withdrawal_accounts enable row level security;
alter table public.withdrawals enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_commissions enable row level security;
alter table public.gift_codes enable row level security;
alter table public.gift_redemptions enable row level security;
alter table public.engagement_tasks enable row level security;
alter table public.task_completions enable row level security;
alter table public.notifications enable row level security;
alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
alter table public.admin_audit_logs enable row level security;

drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles for select to authenticated using ((select auth.uid()) = id or public.is_platform_staff());
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles for update to authenticated using ((select auth.uid()) = id or public.is_platform_admin()) with check ((select auth.uid()) = id or public.is_platform_admin());

drop policy if exists wallets_owner_read on public.wallets;
create policy wallets_owner_read on public.wallets for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());

drop policy if exists settings_authenticated_read on public.settings;
create policy settings_authenticated_read on public.settings for select to authenticated using (is_public or public.is_platform_staff());
drop policy if exists settings_admin_manage on public.settings;
create policy settings_admin_manage on public.settings for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists plans_read_active on public.plans;
create policy plans_read_active on public.plans for select to authenticated using (is_active or public.is_platform_staff());
drop policy if exists plans_admin_manage on public.plans;
create policy plans_admin_manage on public.plans for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists investments_owner_read on public.investments;
create policy investments_owner_read on public.investments for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists investment_earnings_owner_read on public.investment_earnings;
create policy investment_earnings_owner_read on public.investment_earnings for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists transactions_owner_read on public.transactions;
create policy transactions_owner_read on public.transactions for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());

drop policy if exists deposits_owner_read on public.deposits;
create policy deposits_owner_read on public.deposits for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists deposits_owner_submit on public.deposits;
create policy deposits_owner_submit on public.deposits for insert to authenticated with check ((select auth.uid()) = user_id and status = 'PENDING');
drop policy if exists deposits_admin_manage on public.deposits;
create policy deposits_admin_manage on public.deposits for update to authenticated using (public.is_platform_staff()) with check (public.is_platform_staff());

drop policy if exists withdrawal_accounts_owner_manage on public.withdrawal_accounts;
create policy withdrawal_accounts_owner_manage on public.withdrawal_accounts for all to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff()) with check ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists withdrawals_owner_read on public.withdrawals;
create policy withdrawals_owner_read on public.withdrawals for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists withdrawals_admin_manage on public.withdrawals;
create policy withdrawals_admin_manage on public.withdrawals for update to authenticated using (public.is_platform_staff()) with check (public.is_platform_staff());

drop policy if exists referral_codes_owner_read on public.referral_codes;
create policy referral_codes_owner_read on public.referral_codes for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists referrals_owner_read on public.referrals;
create policy referrals_owner_read on public.referrals for select to authenticated using ((select auth.uid()) = referrer_user_id or (select auth.uid()) = referred_user_id or public.is_platform_staff());
drop policy if exists referral_commissions_owner_read on public.referral_commissions;
create policy referral_commissions_owner_read on public.referral_commissions for select to authenticated using ((select auth.uid()) = referrer_user_id or public.is_platform_staff());

drop policy if exists gift_codes_read_active on public.gift_codes;
create policy gift_codes_read_active on public.gift_codes for select to authenticated using (is_active or public.is_platform_staff());
drop policy if exists gift_codes_admin_manage on public.gift_codes;
create policy gift_codes_admin_manage on public.gift_codes for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
drop policy if exists gift_redemptions_owner_read on public.gift_redemptions;
create policy gift_redemptions_owner_read on public.gift_redemptions for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());

drop policy if exists engagement_tasks_read_active on public.engagement_tasks;
create policy engagement_tasks_read_active on public.engagement_tasks for select to authenticated using (is_active or public.is_platform_staff());
drop policy if exists engagement_tasks_admin_manage on public.engagement_tasks;
create policy engagement_tasks_admin_manage on public.engagement_tasks for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
drop policy if exists task_completions_owner_read on public.task_completions;
create policy task_completions_owner_read on public.task_completions for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists task_completions_owner_submit on public.task_completions;
create policy task_completions_owner_submit on public.task_completions for insert to authenticated with check ((select auth.uid()) = user_id and status = 'PENDING');
drop policy if exists task_completions_staff_update on public.task_completions;
create policy task_completions_staff_update on public.task_completions for update to authenticated using (public.is_platform_staff()) with check (public.is_platform_staff());

drop policy if exists notifications_owner_read on public.notifications;
create policy notifications_owner_read on public.notifications for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists notifications_owner_update on public.notifications;
create policy notifications_owner_update on public.notifications for update to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff()) with check ((select auth.uid()) = user_id or public.is_platform_staff());

drop policy if exists support_tickets_owner_read on public.support_tickets;
create policy support_tickets_owner_read on public.support_tickets for select to authenticated using ((select auth.uid()) = user_id or public.is_platform_staff());
drop policy if exists support_tickets_owner_create on public.support_tickets;
create policy support_tickets_owner_create on public.support_tickets for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists support_tickets_staff_update on public.support_tickets;
create policy support_tickets_staff_update on public.support_tickets for update to authenticated using (public.is_platform_staff()) with check (public.is_platform_staff());
drop policy if exists support_messages_visible_read on public.support_messages;
create policy support_messages_visible_read on public.support_messages for select to authenticated using (
  public.is_platform_staff() or exists (
    select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid() and (not is_internal or public.is_platform_staff())
  )
);
drop policy if exists support_messages_author_insert on public.support_messages;
create policy support_messages_author_insert on public.support_messages for insert to authenticated with check (
  (author_id = auth.uid() and exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid()))
  or public.is_platform_staff()
);

drop policy if exists admin_audit_logs_admin_read on public.admin_audit_logs;
create policy admin_audit_logs_admin_read on public.admin_audit_logs for select to authenticated using (public.is_platform_admin());

-- =============================================================================
-- 10. Grants for browser-safe RPC entry points
-- =============================================================================

revoke all on function public.process_investment_purchase(uuid, numeric, text) from public;
grant execute on function public.process_investment_purchase(uuid, numeric, text) to authenticated;
revoke all on function public.request_withdrawal(uuid, numeric) from public;
grant execute on function public.request_withdrawal(uuid, numeric) to authenticated;
revoke all on function public.redeem_gift_code(text) from public;
grant execute on function public.redeem_gift_code(text) to authenticated;

-- The following are server-side/admin-only functions. Keep them unavailable to browser roles.
revoke all on function public.approve_deposit(uuid, text) from public, anon, authenticated;
revoke all on function public.complete_withdrawal(uuid, text, text) from public, anon, authenticated;
revoke all on function public.reject_withdrawal(uuid, text) from public, anon, authenticated;
revoke all on function public.post_investment_earning(uuid, numeric, date, text) from public, anon, authenticated;
revoke all on function public.settle_matured_investments() from public, anon, authenticated;

-- =============================================================================
-- 11. Reference seed data
-- =============================================================================

insert into public.plans (code, name, description, minimum_amount, maximum_amount, term_days, target_return_bps, referral_commission_bps, is_active, sort_order)
values
  ('SPRINT', 'Sprint', 'A compact entry allocation with a 30-day holding horizon.', 250.00, 4999.99, 30, 800, 100, true, 10),
  ('CORE', 'Core', 'A measured three-month mandate for focused conviction.', 1000.00, 24999.99, 90, 1480, 150, true, 20),
  ('MARATHON', 'Marathon', 'A long-horizon allocation program for patient capital.', 2500.00, null, 180, 2800, 200, true, 30)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  minimum_amount = excluded.minimum_amount,
  maximum_amount = excluded.maximum_amount,
  term_days = excluded.term_days,
  target_return_bps = excluded.target_return_bps,
  referral_commission_bps = excluded.referral_commission_bps,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;

insert into public.settings (key, value, description, is_public)
values
  ('withdrawals_locked', '{"enabled": false}'::jsonb, 'Platform-wide withdrawal safety switch.', false),
  ('minimum_deposit', '{"amount": 250, "currency": "USD"}'::jsonb, 'Minimum account funding amount.', true),
  ('platform_notice', '{"title": "Concept environment", "message": "All interface data is illustrative until live services are integrated."}'::jsonb, 'Public dashboard notice.', true),
  ('referral_levels', '{"levels": [{"level": 1, "commission_bps": 150}, {"level": 2, "commission_bps": 50}]}'::jsonb, 'Default referral commission configuration.', false)
on conflict (key) do update set value = excluded.value, description = excluded.description, is_public = excluded.is_public;

insert into public.engagement_tasks (code, title, description, reward_amount, currency, verification_mode, is_active)
values
  ('complete_profile', 'Complete your profile', 'Add the account details required for platform operations.', 10.00, 'USD', 'AUTOMATIC', true),
  ('verify_identity', 'Verify account identity', 'Complete the production identity-verification workflow once connected.', 25.00, 'USD', 'MANUAL', true),
  ('market_brief', 'Read the market brief', 'Review the current investor brief and confirm acknowledgement.', 2.50, 'USD', 'AUTOMATIC', true)
on conflict (code) do update set title = excluded.title, description = excluded.description, reward_amount = excluded.reward_amount, currency = excluded.currency, verification_mode = excluded.verification_mode, is_active = excluded.is_active;

insert into public.gift_codes (code, reward_amount, currency, max_redemptions, is_active)
values ('START-STRIDE', 25.00, 'USD', 500, false)
on conflict (code) do update set reward_amount = excluded.reward_amount, currency = excluded.currency, max_redemptions = excluded.max_redemptions, is_active = excluded.is_active;

-- Optional development seed for an existing Auth user.
-- Run only in a non-production Supabase project after signing up a test user, e.g.:
--   select public.seed_demo_investor('YOUR-AUTH-USER-UUID'::uuid);
-- Never run demo records against a production investor account.
create or replace function public.seed_demo_investor(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_core_plan uuid;
  v_sprint_plan uuid;
  v_core_investment uuid;
  v_sprint_investment uuid;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Create the Auth user first so the profile trigger can run';
  end if;
  select id into v_core_plan from public.plans where code = 'CORE';
  select id into v_sprint_plan from public.plans where code = 'SPRINT';

  update public.profiles set full_name = coalesce(full_name, 'Demo Investor'), verification_status = 'VERIFIED' where id = p_user_id;
  update public.wallets set available_balance = 5100.00, allocated_balance = 17200.00, earned_balance = 2112.50, lifetime_deposited = 24500.00, lifetime_withdrawn = 87.50 where user_id = p_user_id;

  insert into public.investments(user_id, plan_id, plan_code_snapshot, plan_name_snapshot, principal_amount, target_return_amount, earnings_received, status, started_at, matures_at, user_note)
  values (p_user_id, v_core_plan, 'CORE', 'Nike Core', 12400.00, 1835.20, 1736.00, 'ACTIVE', now() - interval '137 days', now() + interval '43 days', 'Development-only portfolio seed')
  on conflict do nothing
  returning id into v_core_investment;

  insert into public.investments(user_id, plan_id, plan_code_snapshot, plan_name_snapshot, principal_amount, target_return_amount, earnings_received, status, started_at, matures_at, user_note)
  values (p_user_id, v_sprint_plan, 'SPRINT', 'Innovation Index', 4800.00, 384.00, 312.00, 'ACTIVE', now() - interval '13 days', now() + interval '17 days', 'Development-only portfolio seed')
  on conflict do nothing
  returning id into v_sprint_investment;

  insert into public.transactions(user_id, transaction_type, direction, status, amount, balance_after, reference, description)
  values
    (p_user_id, 'DEPOSIT', 'CREDIT', 'COMPLETED', 2000.00, 5100.00, concat('DEMO-DP-', substring(replace(p_user_id::text, '-', '') from 1 for 8)), 'Development seed: capital added'),
    (p_user_id, 'EARNING', 'CREDIT', 'COMPLETED', 86.00, 3100.00, concat('DEMO-ER-', substring(replace(p_user_id::text, '-', '') from 1 for 8)), 'Development seed: earnings posted')
  on conflict (reference) do nothing;

  insert into public.notifications(user_id, notification_type, title, message, action_url)
  values
    (p_user_id, 'INVESTMENT', 'Portfolio checkpoint', 'Nike Core is approaching its scheduled review window.', '/portfolio'),
    (p_user_id, 'DEPOSIT', 'Capital status', 'Your development seed account has been funded.', '/wallet')
  on conflict do nothing;
end;
$$;

commit;
