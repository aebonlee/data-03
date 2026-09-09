-- =====================================================================
-- 스카이라이더스(로드 자전거 동호회) — 01. 테이블 스키마
-- 접두어: bike_   |  한 Supabase 프로젝트에 여러 사이트를 둘 때 이름 충돌을 막습니다.
-- 실행 순서: 01 → 02 → 03 → 04 → 05
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1) 회원 프로필 (auth.users 와 1:1)
--    Supabase Auth 가 만든 계정에 우리 사이트에서 쓸 정보를 덧붙이는 표입니다.
-- ---------------------------------------------------------------------
create table if not exists public.bike_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  name        text not null default '라이더',
  nickname    text,
  phone       text,
  region      text default '서울',
  bike_model  text,
  level       text not null default 'beginner' check (level in ('beginner','intermediate','advanced')),
  role        text not null default 'member'  check (role in ('member','admin')),
  intro       text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.bike_profiles is '자전거 동호회 회원 프로필 (auth.users와 1:1)';

-- ---------------------------------------------------------------------
-- 2) 모임 : 연 4회 정기모임(regular) + 매달 소규모 모임(small)
-- ---------------------------------------------------------------------
create table if not exists public.bike_meetups (
  id            bigserial primary key,
  meetup_type   text not null default 'small' check (meetup_type in ('regular','small')),
  title         text not null,
  region        text not null default '서울',
  summary       text,
  content       text,
  cover_emoji   text default '🚴',
  cover_image   text,
  start_at      timestamptz not null,
  end_at        timestamptz,
  place         text,
  meeting_point text,
  course        text,
  distance_km   numeric(6,1),
  difficulty    text not null default 'easy' check (difficulty in ('easy','normal','hard')),
  capacity      integer not null default 20,
  fee           integer not null default 0,
  status        text not null default 'open' check (status in ('open','closed','done')),
  applied_count integer not null default 0,   -- 트리거가 자동으로 채웁니다 (03 참고)
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.bike_meetups is '정기모임(연 4회) / 소규모 모임(매월) 일정';

-- ---------------------------------------------------------------------
-- 3) 모임 신청 (회원 / 비회원 공통)
-- ---------------------------------------------------------------------
create table if not exists public.bike_applications (
  id         bigserial primary key,
  meetup_id  bigint not null references public.bike_meetups(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete set null,   -- 비회원이면 NULL
  name       text not null,
  phone      text,
  email      text,
  region     text,
  bike_type  text,
  message    text,
  status     text not null default 'pending' check (status in ('pending','confirmed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bike_applications_uniq_member unique (meetup_id, user_id)
);
comment on table public.bike_applications is '모임 참가 신청 (회원/비회원 공통)';

-- ---------------------------------------------------------------------
-- 4) 통합 게시판
--    게시판을 표 4개로 나누지 않고 board 컬럼 하나로 구분합니다.
--    → CRUD 코드를 한 벌만 만들면 되고, 게시판을 늘릴 때 CHECK 만 고치면 됩니다.
-- ---------------------------------------------------------------------
create table if not exists public.bike_posts (
  id          bigserial primary key,
  board       text not null check (board in ('notice','free','review','qna')),
  title       text not null,
  content     text not null,
  author_id   uuid references auth.users(id) on delete set null,  -- 비회원이면 NULL
  author_name text not null default '익명',
  region      text,
  image_url   text,
  images      text[] not null default '{}',
  view_count  integer not null default 0,
  is_pinned   boolean not null default false,
  is_secret   boolean not null default false,
  is_answered boolean not null default false,
  answer      text,
  answered_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.bike_posts is '통합 게시판 (notice 공지 / free 자유 / review 후기 / qna 문의)';

-- ---------------------------------------------------------------------
-- 5) 댓글
-- ---------------------------------------------------------------------
create table if not exists public.bike_comments (
  id          bigserial primary key,
  post_id     bigint not null references public.bike_posts(id) on delete cascade,
  content     text not null,
  author_id   uuid references auth.users(id) on delete set null,
  author_name text not null default '익명',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.bike_comments is '게시글 댓글';

-- ---------------------------------------------------------------------
-- 6) 지역별 추천 코스
-- ---------------------------------------------------------------------
create table if not exists public.bike_courses (
  id             bigserial primary key,
  region         text not null,
  title          text not null,
  summary        text,
  content        text,
  distance_km    numeric(6,1),
  duration_hours numeric(4,1),
  difficulty     text not null default 'easy' check (difficulty in ('easy','normal','hard')),
  season         text,
  emoji          text default '🚵',
  image_url      text,
  map_url        text,
  sort_order     integer not null default 0,
  is_published   boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
comment on table public.bike_courses is '지역별 자전거 여행 추천 코스';

-- ---------------------------------------------------------------------
-- 7) 비회원 비밀번호 저장소
--    비밀번호 해시를 게시글 표에 같이 두면 목록 조회 때 함께 노출됩니다.
--    별도 표로 빼고 RLS 정책을 하나도 만들지 않아 클라이언트에서 전혀 읽을 수 없게 합니다.
--    (읽고 쓰는 건 03의 SECURITY DEFINER 함수뿐입니다)
-- ---------------------------------------------------------------------
create table if not exists public.bike_secrets (
  entity     text   not null check (entity in ('post','comment','application')),
  entity_id  bigint not null,
  pw_hash    text   not null,
  created_at timestamptz not null default now(),
  primary key (entity, entity_id)
);
comment on table public.bike_secrets is '비회원 글/댓글/신청의 비밀번호 해시. RLS 정책 없음 = 클라이언트 직접 접근 불가';

-- ---------------------------------------------------------------------
-- 인덱스
-- ---------------------------------------------------------------------
create index if not exists bike_posts_board_created_idx   on public.bike_posts (board, created_at desc);
create index if not exists bike_posts_pinned_idx          on public.bike_posts (board, is_pinned desc, created_at desc);
create index if not exists bike_comments_post_idx         on public.bike_comments (post_id, created_at);
create index if not exists bike_meetups_start_idx         on public.bike_meetups (start_at);
create index if not exists bike_meetups_type_idx          on public.bike_meetups (meetup_type, start_at desc);
create index if not exists bike_applications_meetup_idx   on public.bike_applications (meetup_id, created_at desc);
create index if not exists bike_applications_user_idx     on public.bike_applications (user_id);
create index if not exists bike_courses_region_idx        on public.bike_courses (region, sort_order);

-- ---------------------------------------------------------------------
-- RLS 활성화 — 정책은 02 파일에서 만듭니다.
-- ---------------------------------------------------------------------
alter table public.bike_profiles     enable row level security;
alter table public.bike_meetups      enable row level security;
alter table public.bike_applications enable row level security;
alter table public.bike_posts        enable row level security;
alter table public.bike_comments     enable row level security;
alter table public.bike_courses      enable row level security;
alter table public.bike_secrets      enable row level security;
