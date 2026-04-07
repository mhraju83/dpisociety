-- ============================================================
--  DPI Society — Financial Module SQL (FIXED VERSION)
--  Run this AFTER supabase-setup.sql
--
--  FIX: Renamed 'transactions' to 'finance_transactions'
--  to avoid conflict with the existing transactions table
--  created by supabase-setup.sql
-- ============================================================

-- ── 1. TRANSACTION CATEGORIES ────────────────────────────────
create table if not exists public.finance_categories (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  type        text not null check (type in ('income','expense')),
  description text,
  is_active   boolean default true,
  created_at  timestamptz default now()
);

-- Seed default categories (skip if already exists)
insert into public.finance_categories (name, type, description)
values
  ('Membership Fee',    'income',  'Annual/monthly membership dues'),
  ('Event Fee',         'income',  'Event registration payments'),
  ('Donation',          'income',  'Voluntary donations from members'),
  ('Savings Deposit',   'income',  'Member savings contributions'),
  ('Loan Repayment',    'income',  'Loan installment payments from members'),
  ('Interest Income',   'income',  'Interest earned on savings/investments'),
  ('Event Expense',     'expense', 'Costs for organizing events'),
  ('Administrative',    'expense', 'Office and admin expenses'),
  ('Loan Disbursement', 'expense', 'Loans given out to members'),
  ('Utility',           'expense', 'Utility bills and recurring costs'),
  ('Miscellaneous',     'expense', 'Other uncategorized expenses')
on conflict (name) do nothing;

-- ── 2. FINANCE TRANSACTIONS TABLE ────────────────────────────
--  Named 'finance_transactions' to avoid conflict with the
--  existing 'transactions' table from supabase-setup.sql
-- ─────────────────────────────────────────────────────────────
create table if not exists public.finance_transactions (
  id               bigint generated always as identity primary key,
  receipt_no       text unique,
  member_id        uuid references public.profiles(id) on delete set null,
  type             text not null check (type in ('income','expense')),
  category_id      bigint references public.finance_categories(id),
  amount           numeric(12,2) not null check (amount > 0),
  description      text,
  payment_method   text default 'cash'
    check (payment_method in ('cash','bank','bkash','nagad','rocket','cheque','other')),
  reference_no     text,
  transaction_date date not null default current_date,
  recorded_by      uuid references public.profiles(id),
  notes            text,
  status           text default 'approved'
    check (status in ('approved','pending','cancelled')),
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

-- Auto-generate receipt number: DPI-YYYY-NNNN
create or replace function generate_receipt_no()
returns trigger as $$
declare
  year_str text;
  seq_num  bigint;
begin
  year_str := to_char(now(), 'YYYY');
  select coalesce(max(cast(split_part(receipt_no, '-', 3) as bigint)), 0) + 1
    into seq_num
    from public.finance_transactions
    where receipt_no like 'DPI-' || year_str || '-%';
  new.receipt_no := 'DPI-' || year_str || '-' || lpad(seq_num::text, 4, '0');
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_receipt_no on public.finance_transactions;
create trigger set_receipt_no
  before insert on public.finance_transactions
  for each row
  when (new.receipt_no is null)
  execute function generate_receipt_no();

-- ── 3. SAVINGS ACCOUNTS ──────────────────────────────────────
create table if not exists public.savings_accounts (
  id              bigint generated always as identity primary key,
  member_id       uuid references public.profiles(id) on delete cascade unique,
  account_no      text unique,
  balance         numeric(12,2) default 0,
  total_deposited numeric(12,2) default 0,
  total_withdrawn numeric(12,2) default 0,
  interest_rate   numeric(5,2) default 5.0,
  opened_at       date default current_date,
  status          text default 'active'
    check (status in ('active','frozen','closed')),
  created_at      timestamptz default now()
);

-- Auto-generate savings account number
create or replace function generate_savings_account_no()
returns trigger as $$
declare seq_num bigint;
begin
  select coalesce(max(cast(split_part(account_no, '-', 2) as bigint)), 0) + 1
    into seq_num from public.savings_accounts;
  new.account_no := 'SAV-' || lpad(seq_num::text, 4, '0');
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_savings_account_no on public.savings_accounts;
create trigger set_savings_account_no
  before insert on public.savings_accounts
  for each row
  when (new.account_no is null)
  execute function generate_savings_account_no();

-- ── 4. LOANS TABLE ───────────────────────────────────────────
create table if not exists public.loans (
  id                  bigint generated always as identity primary key,
  loan_no             text unique,
  member_id           uuid references public.profiles(id) on delete cascade,
  principal_amount    numeric(12,2) not null check (principal_amount > 0),
  interest_rate       numeric(5,2) default 10.0,
  tenure_months       integer not null,
  monthly_installment numeric(12,2),
  disbursed_amount    numeric(12,2),
  total_repaid        numeric(12,2) default 0,
  outstanding         numeric(12,2),
  disbursement_date   date,
  due_date            date,
  purpose             text,
  guarantor_id        uuid references public.profiles(id),
  approved_by         uuid references public.profiles(id),
  status              text default 'pending'
    check (status in ('pending','approved','disbursed','repaid','defaulted','cancelled')),
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

-- Auto-generate loan number
create or replace function generate_loan_no()
returns trigger as $$
declare year_str text; seq_num bigint;
begin
  year_str := to_char(now(), 'YYYY');
  select coalesce(max(cast(split_part(loan_no, '-', 3) as bigint)), 0) + 1
    into seq_num from public.loans
    where loan_no like 'LOAN-' || year_str || '-%';
  new.loan_no := 'LOAN-' || year_str || '-' || lpad(seq_num::text, 4, '0');
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_loan_no on public.loans;
create trigger set_loan_no
  before insert on public.loans
  for each row
  when (new.loan_no is null)
  execute function generate_loan_no();

-- ── 5. MEMBER DUES TABLE ─────────────────────────────────────
create table if not exists public.member_dues (
  id             bigint generated always as identity primary key,
  member_id      uuid references public.profiles(id) on delete cascade,
  due_type       text not null,
  amount         numeric(12,2) not null,
  due_date       date not null,
  paid_date      date,
  transaction_id bigint references public.finance_transactions(id),
  status         text default 'unpaid'
    check (status in ('unpaid','paid','waived','partial')),
  notes          text,
  created_at     timestamptz default now()
);

-- ── 6. ROW LEVEL SECURITY ────────────────────────────────────
alter table public.finance_transactions  enable row level security;
alter table public.finance_categories    enable row level security;
alter table public.savings_accounts      enable row level security;
alter table public.loans                 enable row level security;
alter table public.member_dues           enable row level security;

-- Finance categories: everyone can read
create policy "Everyone can view finance categories"
  on public.finance_categories for select using (true);

-- Finance transactions: members view their own + approved, admins see all
create policy "Members view own or approved finance transactions"
  on public.finance_transactions for select
  using (
    status = 'approved' or
    member_id = auth.uid() or
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

create policy "Admins manage finance transactions"
  on public.finance_transactions for all
  using (
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

-- Savings: members see their own, admins see all
create policy "Members view own savings"
  on public.savings_accounts for select
  using (
    member_id = auth.uid() or
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

create policy "Admins manage savings accounts"
  on public.savings_accounts for all
  using (
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

-- Loans: members see own, admins see all
create policy "Members view own loans"
  on public.loans for select
  using (
    member_id = auth.uid() or
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

create policy "Admins manage loans"
  on public.loans for all
  using (
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

-- Dues: members see own, admins see all
create policy "Members view own dues"
  on public.member_dues for select
  using (
    member_id = auth.uid() or
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

create policy "Admins manage member dues"
  on public.member_dues for all
  using (
    exists (select 1 from public.profiles where id = auth.uid() and user_type = 'admin')
  );

-- ── 7. VIEWS ─────────────────────────────────────────────────

-- Full transaction list with member + category info
create or replace view public.transactions_full as
select
  t.*,
  p.full_name    as member_name,
  p.batch        as member_batch,
  p.department   as member_dept,
  fc.name        as category_name,
  fc.type        as category_type,
  rb.full_name   as recorded_by_name
from public.finance_transactions t
left join public.profiles p         on p.id  = t.member_id
left join public.finance_categories fc on fc.id = t.category_id
left join public.profiles rb        on rb.id = t.recorded_by
where t.status = 'approved';

-- Member financial summary
create or replace view public.member_finance_summary as
select
  p.id,
  p.full_name,
  p.batch,
  p.department,
  coalesce(sum(case when t.type = 'income' then t.amount end), 0) as total_paid,
  coalesce(sa.balance, 0)        as savings_balance,
  coalesce(sa.account_no, '—')   as savings_account,
  coalesce(
    (select sum(l.outstanding)
       from public.loans l
      where l.member_id = p.id and l.status = 'disbursed'), 0
  ) as loan_outstanding,
  coalesce(
    (select count(*)
       from public.member_dues d
      where d.member_id = p.id and d.status = 'unpaid'), 0
  ) as unpaid_dues_count,
  coalesce(
    (select sum(d.amount)
       from public.member_dues d
      where d.member_id = p.id and d.status = 'unpaid'), 0
  ) as unpaid_dues_amount
from public.profiles p
left join public.finance_transactions t  on t.member_id = p.id and t.status = 'approved'
left join public.savings_accounts sa     on sa.member_id = p.id
where p.status = 'active'
group by p.id, p.full_name, p.batch, p.department, sa.balance, sa.account_no;

-- Society-level summary
create or replace view public.society_finance_summary as
select
  coalesce(sum(case when type = 'income'  then amount end), 0) as total_income,
  coalesce(sum(case when type = 'expense' then amount end), 0) as total_expense,
  coalesce(sum(case when type = 'income'  then amount end), 0) -
  coalesce(sum(case when type = 'expense' then amount end), 0) as net_balance,
  count(*) as total_transactions,
  coalesce(sum(case when type = 'income'  and transaction_date >= date_trunc('month', current_date) then amount end), 0) as income_this_month,
  coalesce(sum(case when type = 'expense' and transaction_date >= date_trunc('month', current_date) then amount end), 0) as expense_this_month
from public.finance_transactions
where status = 'approved';

-- Monthly breakdown for charts
create or replace view public.monthly_finance_chart as
select
  to_char(transaction_date, 'YYYY-MM')  as month,
  to_char(transaction_date, 'Mon YYYY') as month_label,
  sum(case when type = 'income'  then amount else 0 end) as income,
  sum(case when type = 'expense' then amount else 0 end) as expense,
  count(*) as transaction_count
from public.finance_transactions
where status = 'approved'
  and transaction_date >= current_date - interval '12 months'
group by
  to_char(transaction_date, 'YYYY-MM'),
  to_char(transaction_date, 'Mon YYYY')
order by month;

-- ── 8. HELPER FUNCTIONS ──────────────────────────────────────

-- Auto-update savings balance on deposit
create or replace function update_savings_balance()
returns trigger as $$
begin
  if new.type = 'income' and exists (
    select 1 from public.finance_categories
    where id = new.category_id and name = 'Savings Deposit'
  ) then
    update public.savings_accounts
    set balance         = balance + new.amount,
        total_deposited = total_deposited + new.amount
    where member_id = new.member_id;
  end if;

  if new.type = 'income' and exists (
    select 1 from public.finance_categories
    where id = new.category_id and name = 'Loan Repayment'
  ) then
    update public.loans
    set total_repaid = total_repaid + new.amount,
        outstanding  = greatest(0, outstanding - new.amount),
        updated_at   = now()
    where member_id = new.member_id
      and status = 'disbursed'
    order by created_at asc
    limit 1;
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_finance_transaction_insert on public.finance_transactions;
create trigger on_finance_transaction_insert
  after insert on public.finance_transactions
  for each row execute function update_savings_balance();

-- Amount in words for receipts (Crore/Lakh system)
create or replace function amount_in_words(amount numeric)
returns text as $$
declare
  ones text[] := array['','One','Two','Three','Four','Five','Six','Seven',
                        'Eight','Nine','Ten','Eleven','Twelve','Thirteen',
                        'Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
  tens text[] := array['','','Twenty','Thirty','Forty','Fifty',
                        'Sixty','Seventy','Eighty','Ninety'];
  result   text    := '';
  n        integer := amount::integer;
  crore    int; lakh int; thousand int; hundred int; remainder int;
begin
  if n = 0 then return 'Zero Taka Only'; end if;
  crore    := n / 10000000; n := n % 10000000;
  lakh     := n / 100000;   n := n % 100000;
  thousand := n / 1000;     n := n % 1000;
  hundred  := n / 100;      remainder := n % 100;
  if crore    > 0 then result := result || ones[crore+1]    || ' Crore ';    end if;
  if lakh     > 0 then result := result || ones[lakh+1]     || ' Lakh ';     end if;
  if thousand > 0 then result := result || ones[thousand+1] || ' Thousand '; end if;
  if hundred  > 0 then result := result || ones[hundred+1]  || ' Hundred ';  end if;
  if remainder >= 20 then
    result := result || tens[remainder/10+1] || ' ';
    if remainder % 10 > 0 then result := result || ones[remainder%10+1] || ' '; end if;
  elsif remainder > 0 then
    result := result || ones[remainder+1] || ' ';
  end if;
  return trim(result) || ' Taka Only';
end;
$$ language plpgsql immutable;

-- ── 9. HELPER FUNCTIONS FOR finance.html ─────────────────────

create or replace function increment_downloads(resource_id bigint)
returns void as $$
  update resources set downloads = downloads + 1 where id = resource_id;
$$ language sql security definer;

create or replace function increment_views(post_id bigint)
returns void as $$
  update posts set views = views + 1 where id = post_id;
$$ language sql security definer;

-- ============================================================
--  ✅ DONE! Finance module tables created successfully.
--  Tables created:
--    finance_categories
--    finance_transactions  (renamed from 'transactions')
--    savings_accounts
--    loans
--    member_dues
--  Views created:
--    transactions_full
--    member_finance_summary
--    society_finance_summary
--    monthly_finance_chart
-- ============================================================
