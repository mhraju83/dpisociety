-- ============================================================
--  DPI Society — Supabase Database Setup
--  Run this entire file in Supabase SQL Editor
-- ============================================================

-- ── 1. PROFILES TABLE ──
-- Extends Supabase built-in auth.users with alumni info
create table public.profiles (
  id           uuid references auth.users(id) on delete cascade primary key,
  full_name    text not null,
  email        text,
  batch        text,                        -- e.g. "Batch 71"
  department   text,                        -- e.g. "Computer Technology"
  passing_year integer,
  phone        text,
  location     text,
  profession   text,
  bio          text,
  linkedin_url text,
  avatar_url   text,
  user_type    text default 'member',       -- 'member' | 'admin'
  status       text default 'pending',      -- 'active' | 'pending' | 'banned'
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- Auto-create profile row when a user signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', 'New Member')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── 2. POSTS TABLE ──
create table public.posts (
  id          bigint generated always as identity primary key,
  author_id   uuid references public.profiles(id) on delete cascade,
  title       text not null,
  body        text not null,
  category    text not null,               -- 'career'|'study'|'tech'|'general'|'news'|'batch'
  tags        text[],
  votes       integer default 0,
  views       integer default 0,
  is_pinned   boolean default false,
  is_answered boolean default false,
  status      text default 'active',       -- 'active' | 'flagged' | 'removed'
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── 3. REPLIES TABLE ──
create table public.replies (
  id          bigint generated always as identity primary key,
  post_id     bigint references public.posts(id) on delete cascade,
  author_id   uuid references public.profiles(id) on delete cascade,
  body        text not null,
  likes       integer default 0,
  is_best     boolean default false,
  status      text default 'active',
  created_at  timestamptz default now()
);

-- ── 4. VOTES TABLE (prevent double voting) ──
create table public.votes (
  id        bigint generated always as identity primary key,
  post_id   bigint references public.posts(id) on delete cascade,
  user_id   uuid references public.profiles(id) on delete cascade,
  unique(post_id, user_id)
);

-- ── 5. RESOURCES TABLE ──
create table public.resources (
  id           bigint generated always as identity primary key,
  uploader_id  uuid references public.profiles(id) on delete cascade,
  title        text not null,
  description  text,
  department   text,
  content_type text,                       -- 'Lecture Notes'|'Project Report' etc
  file_url     text,                       -- Supabase Storage URL
  file_type    text,                       -- 'pdf'|'doc'|'ppt'|'xls'|'video'|'link'
  file_size    text,
  tags         text[],
  downloads    integer default 0,
  saves        integer default 0,
  status       text default 'review',      -- 'review' | 'approved' | 'rejected'
  created_at   timestamptz default now()
);

-- ── 6. SAVED RESOURCES TABLE ──
create table public.saved_resources (
  id          bigint generated always as identity primary key,
  user_id     uuid references public.profiles(id) on delete cascade,
  resource_id bigint references public.resources(id) on delete cascade,
  created_at  timestamptz default now(),
  unique(user_id, resource_id)
);

-- ── 7. EVENTS TABLE ──
create table public.events (
  id          bigint generated always as identity primary key,
  title       text not null,
  description text,
  event_type  text,                        -- 'reunion'|'seminar'|'workshop'|'sports'|'cultural'
  event_date  date not null,
  event_time  text,
  venue       text,
  capacity    integer default 100,
  is_featured boolean default false,
  status      text default 'upcoming',     -- 'upcoming' | 'past' | 'cancelled'
  created_at  timestamptz default now()
);

-- ── 8. RSVPS TABLE ──
create table public.rsvps (
  id         bigint generated always as identity primary key,
  event_id   bigint references public.events(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(event_id, user_id)
);

-- ── 9. REPLY LIKES TABLE ──
create table public.reply_likes (
  id         bigint generated always as identity primary key,
  reply_id   bigint references public.replies(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  unique(reply_id, user_id)
);

-- ============================================================
--  ROW LEVEL SECURITY (RLS)
--  Controls who can read/write what
-- ============================================================

-- Enable RLS on all tables
alter table public.profiles        enable row level security;
alter table public.posts           enable row level security;
alter table public.replies         enable row level security;
alter table public.votes           enable row level security;
alter table public.resources       enable row level security;
alter table public.saved_resources enable row level security;
alter table public.events          enable row level security;
alter table public.rsvps           enable row level security;
alter table public.reply_likes     enable row level security;

-- ── PROFILES policies ──
create policy "Profiles are viewable by everyone"
  on public.profiles for select using (true);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- ── POSTS policies ──
create policy "Posts are viewable by everyone"
  on public.posts for select using (status = 'active');

create policy "Logged-in members can create posts"
  on public.posts for insert
  with check (auth.uid() = author_id);

create policy "Authors can update their own posts"
  on public.posts for update
  using (auth.uid() = author_id);

-- ── REPLIES policies ──
create policy "Replies are viewable by everyone"
  on public.replies for select using (status = 'active');

create policy "Logged-in members can reply"
  on public.replies for insert
  with check (auth.uid() = author_id);

-- ── VOTES policies ──
create policy "Users can vote once per post"
  on public.votes for insert
  with check (auth.uid() = user_id);

create policy "Users can remove their vote"
  on public.votes for delete
  using (auth.uid() = user_id);

create policy "Votes are viewable by everyone"
  on public.votes for select using (true);

-- ── RESOURCES policies ──
create policy "Approved resources viewable by everyone"
  on public.resources for select
  using (status = 'approved');

create policy "Members can upload resources"
  on public.resources for insert
  with check (auth.uid() = uploader_id);

-- ── SAVED RESOURCES policies ──
create policy "Users manage their own saved resources"
  on public.saved_resources for all
  using (auth.uid() = user_id);

-- ── EVENTS policies ──
create policy "Events are viewable by everyone"
  on public.events for select using (true);

-- ── RSVPS policies ──
create policy "RSVPs are viewable by everyone"
  on public.rsvps for select using (true);

create policy "Members can RSVP"
  on public.rsvps for insert
  with check (auth.uid() = user_id);

create policy "Members can cancel their RSVP"
  on public.rsvps for delete
  using (auth.uid() = user_id);

-- ── REPLY LIKES policies ──
create policy "Reply likes viewable by everyone"
  on public.reply_likes for select using (true);

create policy "Members can like replies"
  on public.reply_likes for insert
  with check (auth.uid() = user_id);

create policy "Members can unlike replies"
  on public.reply_likes for delete
  using (auth.uid() = user_id);

-- ============================================================
--  HELPER VIEWS (makes querying easier)
-- ============================================================

-- Post list with author info and reply count
create view public.posts_with_details as
select
  p.*,
  pr.full_name    as author_name,
  pr.batch        as author_batch,
  pr.department   as author_dept,
  pr.avatar_url   as author_avatar,
  (select count(*) from public.replies r where r.post_id = p.id and r.status = 'active') as reply_count,
  (select count(*) from public.votes v where v.post_id = p.id) as vote_count
from public.posts p
join public.profiles pr on pr.id = p.author_id
where p.status = 'active';

-- Resource list with uploader info
create view public.resources_with_uploader as
select
  r.*,
  pr.full_name  as uploader_name,
  pr.batch      as uploader_batch,
  pr.department as uploader_dept
from public.resources r
join public.profiles pr on pr.id = r.uploader_id
where r.status = 'approved';

-- Event list with RSVP count
create view public.events_with_rsvp_count as
select
  e.*,
  (select count(*) from public.rsvps rv where rv.event_id = e.id) as rsvp_count
from public.events e;

-- ============================================================
--  SAMPLE DATA — remove this section before going live
-- ============================================================

-- Sample events
insert into public.events (title, description, event_type, event_date, event_time, venue, capacity, is_featured, status)
values
  ('Annual Alumni Grand Reunion 2025', 'The biggest alumni gathering of the year! Join thousands of DPI graduates from all batches.', 'reunion', '2025-05-15', '10:00 AM – 6:00 PM', 'DPI Main Campus, Dhaka', 500, true, 'upcoming'),
  ('Career in Engineering: Alumni Panel', 'Senior alumni from top engineering firms share their career journeys.', 'seminar', '2025-04-22', '2:00 PM – 5:00 PM', 'BTEB Auditorium, Dhaka', 200, false, 'upcoming'),
  ('AutoCAD & Civil Design Workshop', 'Hands-on AutoCAD training for civil and architecture alumni.', 'workshop', '2025-06-10', '9:00 AM – 4:00 PM', 'DPI Computer Lab, Block C', 40, false, 'upcoming'),
  ('DPI Sports Day 2025', 'Annual inter-batch cricket, football and badminton tournament.', 'sports', '2025-07-05', '8:00 AM – 5:00 PM', 'DPI Sports Ground', 300, false, 'upcoming');

-- ============================================================
--  DONE! Your database is ready.
-- ============================================================
