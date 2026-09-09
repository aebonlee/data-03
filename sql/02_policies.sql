-- =====================================================================
-- 스카이라이더스 — 02. RLS(Row Level Security) 정책
-- ---------------------------------------------------------------------
-- 이 사이트의 보안은 전적으로 아래 정책이 담당합니다.
-- 브라우저에 박혀 있는 publishable 키는 "누구세요"만 알려줄 뿐,
-- "무엇을 할 수 있는가"는 여기서 정해집니다.
--
-- 큰 원칙
--   · 읽기(SELECT)  : 공개 콘텐츠는 누구나
--   · 쓰기          : 회원은 본인 것만 / 비회원은 03의 비밀번호 RPC 로만
--   · 관리자        : bike_profiles.role = 'admin' 이면 전부 가능
-- =====================================================================

-- ---------------------------------------------------------------------
-- 관리자 판별 헬퍼
--   정책 안에서 bike_profiles 를 조회하면 그 조회에도 RLS가 걸려 무한 재귀가 됩니다.
--   SECURITY DEFINER 로 만들어 소유자 권한으로 조회하게 해 재귀를 끊습니다.
-- ---------------------------------------------------------------------
create or replace function public.bike_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.bike_profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------
-- bike_profiles : 본인 + 관리자만 (개인정보 보호)
-- ---------------------------------------------------------------------
drop policy if exists bike_profiles_select on public.bike_profiles;
drop policy if exists bike_profiles_insert on public.bike_profiles;
drop policy if exists bike_profiles_update on public.bike_profiles;
drop policy if exists bike_profiles_delete on public.bike_profiles;

create policy bike_profiles_select on public.bike_profiles
  for select using (id = auth.uid() or public.bike_is_admin());
create policy bike_profiles_insert on public.bike_profiles
  for insert with check (id = auth.uid());
create policy bike_profiles_update on public.bike_profiles
  for update using (id = auth.uid() or public.bike_is_admin())
              with check (id = auth.uid() or public.bike_is_admin());
create policy bike_profiles_delete on public.bike_profiles
  for delete using (public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_meetups : 누구나 조회 / 관리자만 등록·수정·삭제
-- ---------------------------------------------------------------------
drop policy if exists bike_meetups_select on public.bike_meetups;
drop policy if exists bike_meetups_write  on public.bike_meetups;
drop policy if exists bike_meetups_update on public.bike_meetups;
drop policy if exists bike_meetups_delete on public.bike_meetups;

create policy bike_meetups_select on public.bike_meetups for select using (true);
create policy bike_meetups_write  on public.bike_meetups for insert with check (public.bike_is_admin());
create policy bike_meetups_update on public.bike_meetups for update using (public.bike_is_admin()) with check (public.bike_is_admin());
create policy bike_meetups_delete on public.bike_meetups for delete using (public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_courses : 공개된 코스는 누구나 / 관리자만 관리
-- ---------------------------------------------------------------------
drop policy if exists bike_courses_select on public.bike_courses;
drop policy if exists bike_courses_write  on public.bike_courses;
drop policy if exists bike_courses_update on public.bike_courses;
drop policy if exists bike_courses_delete on public.bike_courses;

create policy bike_courses_select on public.bike_courses for select using (is_published or public.bike_is_admin());
create policy bike_courses_write  on public.bike_courses for insert with check (public.bike_is_admin());
create policy bike_courses_update on public.bike_courses for update using (public.bike_is_admin()) with check (public.bike_is_admin());
create policy bike_courses_delete on public.bike_courses for delete using (public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_posts
--   · 비밀글은 작성자 본인/관리자에게만 보입니다.
--     (비회원 작성자는 03의 bike_read_secret_post 로 비밀번호를 넣어 확인)
--   · 공지사항은 관리자만 작성할 수 있습니다.
-- ---------------------------------------------------------------------
drop policy if exists bike_posts_select on public.bike_posts;
drop policy if exists bike_posts_insert on public.bike_posts;
drop policy if exists bike_posts_update on public.bike_posts;
drop policy if exists bike_posts_delete on public.bike_posts;

create policy bike_posts_select on public.bike_posts
  for select using (is_secret = false or author_id = auth.uid() or public.bike_is_admin());

create policy bike_posts_insert on public.bike_posts
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and (board <> 'notice' or public.bike_is_admin())
  );

create policy bike_posts_update on public.bike_posts
  for update to authenticated
  using (author_id = auth.uid() or public.bike_is_admin())
  with check (author_id = auth.uid() or public.bike_is_admin());

create policy bike_posts_delete on public.bike_posts
  for delete to authenticated
  using (author_id = auth.uid() or public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_comments
-- ---------------------------------------------------------------------
drop policy if exists bike_comments_select on public.bike_comments;
drop policy if exists bike_comments_insert on public.bike_comments;
drop policy if exists bike_comments_update on public.bike_comments;
drop policy if exists bike_comments_delete on public.bike_comments;

create policy bike_comments_select on public.bike_comments for select using (true);
create policy bike_comments_insert on public.bike_comments
  for insert to authenticated with check (author_id = auth.uid());
create policy bike_comments_update on public.bike_comments
  for update to authenticated
  using (author_id = auth.uid() or public.bike_is_admin())
  with check (author_id = auth.uid() or public.bike_is_admin());
create policy bike_comments_delete on public.bike_comments
  for delete to authenticated using (author_id = auth.uid() or public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_applications : 본인 신청 + 관리자
-- ---------------------------------------------------------------------
drop policy if exists bike_applications_select on public.bike_applications;
drop policy if exists bike_applications_insert on public.bike_applications;
drop policy if exists bike_applications_update on public.bike_applications;
drop policy if exists bike_applications_delete on public.bike_applications;

create policy bike_applications_select on public.bike_applications
  for select using (user_id = auth.uid() or public.bike_is_admin());
create policy bike_applications_insert on public.bike_applications
  for insert to authenticated with check (user_id = auth.uid());
create policy bike_applications_update on public.bike_applications
  for update to authenticated
  using (user_id = auth.uid() or public.bike_is_admin())
  with check (user_id = auth.uid() or public.bike_is_admin());
create policy bike_applications_delete on public.bike_applications
  for delete to authenticated using (user_id = auth.uid() or public.bike_is_admin());

-- ---------------------------------------------------------------------
-- bike_secrets : 정책을 하나도 만들지 않습니다.
--   RLS가 켜져 있는데 정책이 없으면 = 모든 접근 거부.
--   Supabase 린터가 INFO 로 알려주지만 여기서는 "의도된 설정"입니다.
-- ---------------------------------------------------------------------
