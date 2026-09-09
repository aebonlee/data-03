-- =====================================================================
-- 스카이라이더스 — 03. CRUD 함수(RPC) + 트리거
-- ---------------------------------------------------------------------
-- 이 사이트의 쓰기 흐름은 두 갈래입니다.
--   · 로그인 회원 : RLS 정책에 기대어 테이블을 직접 다뤄도 됩니다.
--   · 비회원      : 비밀번호로 본인을 증명해야 하므로 아래 함수를 거칩니다.
-- 화면 코드를 단순하게 유지하려고 "읽기는 테이블 직접 / 쓰기는 함수" 로 통일했습니다.
-- =====================================================================

-- ---------------------------------------------------------------------
-- updated_at 자동 갱신 트리거
--   now() 는 트랜잭션 시작 시각이라 같은 트랜잭션 안의 수정이 구분되지 않습니다.
--   실제 수정 시각이 남도록 clock_timestamp() 를 씁니다.
-- ---------------------------------------------------------------------
create or replace function public.bike_touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end;
$$;

drop trigger if exists bike_profiles_touch     on public.bike_profiles;
drop trigger if exists bike_meetups_touch      on public.bike_meetups;
drop trigger if exists bike_applications_touch on public.bike_applications;
drop trigger if exists bike_posts_touch        on public.bike_posts;
drop trigger if exists bike_comments_touch     on public.bike_comments;
drop trigger if exists bike_courses_touch      on public.bike_courses;

create trigger bike_profiles_touch     before update on public.bike_profiles     for each row execute function public.bike_touch_updated_at();
create trigger bike_meetups_touch      before update on public.bike_meetups      for each row execute function public.bike_touch_updated_at();
create trigger bike_applications_touch before update on public.bike_applications for each row execute function public.bike_touch_updated_at();
create trigger bike_posts_touch        before update on public.bike_posts        for each row execute function public.bike_touch_updated_at();
create trigger bike_comments_touch     before update on public.bike_comments     for each row execute function public.bike_touch_updated_at();
create trigger bike_courses_touch      before update on public.bike_courses      for each row execute function public.bike_touch_updated_at();

-- ---------------------------------------------------------------------
-- 내부 헬퍼 : 비회원 비밀번호 확인 (bcrypt)
--   ※ 이 함수는 외부(anon/authenticated)에 열어두면 안 됩니다.
--     열려 있으면 비밀번호를 무제한으로 대입해 볼 수 있는 통로가 됩니다.
--     파일 맨 아래에서 EXECUTE 권한을 회수합니다.
-- ---------------------------------------------------------------------
create or replace function public.bike_check_pw(p_entity text, p_id bigint, p_password text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare v_hash text;
begin
  select pw_hash into v_hash from public.bike_secrets
   where entity = p_entity and entity_id = p_id;
  if v_hash is null then return false; end if;
  if p_password is null or p_password = '' then return false; end if;
  return v_hash = crypt(p_password, v_hash);
end;
$$;

-- =====================================================================
-- 게시글 CREATE
-- =====================================================================
create or replace function public.bike_create_post(
  p_board       text,
  p_title       text,
  p_content     text,
  p_author_name text default null,
  p_password    text default null,
  p_region      text default null,
  p_image_url   text default null,
  p_images      text[] default '{}',
  p_is_secret   boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text;
  v_id   bigint;
begin
  if p_board not in ('notice','free','review','qna') then
    raise exception '알 수 없는 게시판입니다: %', p_board;
  end if;
  if coalesce(trim(p_title), '') = '' then raise exception '제목을 입력해 주세요.'; end if;
  if coalesce(trim(p_content), '') = '' then raise exception '내용을 입력해 주세요.'; end if;
  if p_board = 'notice' and not public.bike_is_admin() then
    raise exception '공지사항은 관리자만 작성할 수 있습니다.';
  end if;

  if v_uid is null then
    -- 비회원 : 이름 + 비밀번호 필수
    if coalesce(trim(p_author_name), '') = '' then raise exception '작성자 이름을 입력해 주세요.'; end if;
    if coalesce(p_password, '') = '' or length(p_password) < 4 then
      raise exception '비밀번호는 4자 이상 입력해 주세요.';
    end if;
    v_name := trim(p_author_name);
  else
    v_name := coalesce(nullif(trim(p_author_name), ''),
                       (select coalesce(nickname, name) from public.bike_profiles where id = v_uid),
                       '회원');
  end if;

  insert into public.bike_posts (board, title, content, author_id, author_name,
                                 region, image_url, images, is_secret)
  values (p_board, trim(p_title), p_content, v_uid, v_name,
          p_region, p_image_url, coalesce(p_images, '{}'), coalesce(p_is_secret, false))
  returning id into v_id;

  if v_uid is null then
    insert into public.bike_secrets (entity, entity_id, pw_hash)
    values ('post', v_id, crypt(p_password, gen_salt('bf')));
  end if;

  return v_id;
end;
$$;

-- =====================================================================
-- 게시글 UPDATE
-- =====================================================================
create or replace function public.bike_update_post(
  p_id        bigint,
  p_password  text default null,
  p_title     text default null,
  p_content   text default null,
  p_region    text default null,
  p_image_url text default null,
  p_images    text[] default null,
  p_is_secret boolean default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
begin
  select author_id into v_author from public.bike_posts where id = p_id;
  if not found then raise exception '게시글을 찾을 수 없습니다.'; end if;

  if v_author is not null then                    -- 회원이 쓴 글
    if v_uid is null or (v_uid <> v_author and not public.bike_is_admin()) then
      raise exception '수정 권한이 없습니다.';
    end if;
  else                                            -- 비회원이 쓴 글
    if not public.bike_is_admin() and not public.bike_check_pw('post', p_id, p_password) then
      raise exception '비밀번호가 일치하지 않습니다.';
    end if;
  end if;

  update public.bike_posts set
    title     = coalesce(nullif(trim(coalesce(p_title,'')),''), title),
    content   = coalesce(nullif(p_content,''), content),
    region    = coalesce(p_region, region),
    image_url = coalesce(p_image_url, image_url),
    images    = coalesce(p_images, images),
    is_secret = coalesce(p_is_secret, is_secret)
  where id = p_id;

  return true;
end;
$$;

-- =====================================================================
-- 게시글 DELETE
-- =====================================================================
create or replace function public.bike_delete_post(p_id bigint, p_password text default null)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
begin
  select author_id into v_author from public.bike_posts where id = p_id;
  if not found then raise exception '게시글을 찾을 수 없습니다.'; end if;

  if v_author is not null then
    if v_uid is null or (v_uid <> v_author and not public.bike_is_admin()) then
      raise exception '삭제 권한이 없습니다.';
    end if;
  else
    if not public.bike_is_admin() and not public.bike_check_pw('post', p_id, p_password) then
      raise exception '비밀번호가 일치하지 않습니다.';
    end if;
  end if;

  delete from public.bike_secrets where entity = 'post' and entity_id = p_id;
  delete from public.bike_posts where id = p_id;
  return true;
end;
$$;

-- =====================================================================
-- 게시판 목록 조회 (검색 + 페이지네이션 + 전체 건수 + 댓글 수를 한 번에)
--   비밀글은 목록에는 보이되 내용은 가려서 내려줍니다.
--   ※ author_id 와 auth.uid() 가 모두 NULL 이면 비교 결과가 NULL 이 되어
--     내용이 새어 나갑니다. coalesce(..., false) 로 반드시 감싸주세요.
-- =====================================================================
create or replace function public.bike_list_posts(
  p_board  text,
  p_search text default null,
  p_region text default null,
  p_limit  integer default 10,
  p_offset integer default 0
)
returns table (
  id bigint, board text, title text, content text,
  author_id uuid, author_name text, region text, image_url text,
  view_count integer, is_pinned boolean, is_secret boolean, is_answered boolean,
  created_at timestamptz, comment_count bigint, can_open boolean, total_count bigint
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with base as (
    select p.*
      from public.bike_posts p
     where p.board = p_board
       and (p_region is null or p_region = '' or p.region = p_region)
       and (
         p_search is null or p_search = ''
         or p.title   ilike '%' || p_search || '%'
         or p.content ilike '%' || p_search || '%'
         or p.author_name ilike '%' || p_search || '%'
       )
  ), counted as (
    select b.*,
           coalesce(b.author_id = auth.uid(), false) or public.bike_is_admin() as mine,
           count(*) over() as total_count
      from base b
  )
  select
    c.id, c.board, c.title,
    case when c.is_secret and not c.mine
         then '🔒 비밀글입니다. 작성 시 입력한 비밀번호를 입력해 주세요.'
         else c.content end as content,
    c.author_id, c.author_name, c.region, c.image_url,
    c.view_count, c.is_pinned, c.is_secret, c.is_answered, c.created_at,
    (select count(*) from public.bike_comments cm where cm.post_id = c.id) as comment_count,
    (not c.is_secret or c.mine) as can_open,
    c.total_count
  from counted c
  order by c.is_pinned desc, c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 100))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- =====================================================================
-- 비밀글 열람 (비회원용)
-- =====================================================================
create or replace function public.bike_read_secret_post(p_id bigint, p_password text)
returns setof public.bike_posts
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.bike_check_pw('post', p_id, p_password) then
    raise exception '비밀번호가 일치하지 않습니다.';
  end if;
  return query select * from public.bike_posts where id = p_id;
end;
$$;

-- =====================================================================
-- 조회수 증가
-- =====================================================================
create or replace function public.bike_increment_view(p_id bigint)
returns void
language sql
security definer
set search_path = public, extensions
as $$
  update public.bike_posts set view_count = view_count + 1 where id = p_id;
$$;

-- =====================================================================
-- 댓글 CREATE / DELETE
-- =====================================================================
create or replace function public.bike_create_comment(
  p_post_id     bigint,
  p_content     text,
  p_author_name text default null,
  p_password    text default null
)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text;
  v_id   bigint;
begin
  if coalesce(trim(p_content), '') = '' then raise exception '댓글 내용을 입력해 주세요.'; end if;
  if not exists (select 1 from public.bike_posts where id = p_post_id) then
    raise exception '게시글을 찾을 수 없습니다.';
  end if;

  if v_uid is null then
    if coalesce(trim(p_author_name), '') = '' then raise exception '이름을 입력해 주세요.'; end if;
    if coalesce(p_password, '') = '' or length(p_password) < 4 then
      raise exception '비밀번호는 4자 이상 입력해 주세요.';
    end if;
    v_name := trim(p_author_name);
  else
    v_name := coalesce(nullif(trim(p_author_name), ''),
                       (select coalesce(nickname, name) from public.bike_profiles where id = v_uid),
                       '회원');
  end if;

  insert into public.bike_comments (post_id, content, author_id, author_name)
  values (p_post_id, p_content, v_uid, v_name)
  returning id into v_id;

  if v_uid is null then
    insert into public.bike_secrets (entity, entity_id, pw_hash)
    values ('comment', v_id, crypt(p_password, gen_salt('bf')));
  end if;

  return v_id;
end;
$$;

create or replace function public.bike_delete_comment(p_id bigint, p_password text default null)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_author uuid;
begin
  select author_id into v_author from public.bike_comments where id = p_id;
  if not found then raise exception '댓글을 찾을 수 없습니다.'; end if;

  if v_author is not null then
    if v_uid is null or (v_uid <> v_author and not public.bike_is_admin()) then
      raise exception '삭제 권한이 없습니다.';
    end if;
  else
    if not public.bike_is_admin() and not public.bike_check_pw('comment', p_id, p_password) then
      raise exception '비밀번호가 일치하지 않습니다.';
    end if;
  end if;

  delete from public.bike_secrets where entity = 'comment' and entity_id = p_id;
  delete from public.bike_comments where id = p_id;
  return true;
end;
$$;

-- =====================================================================
-- 모임 신청 / 취소 / 조회
-- =====================================================================
create or replace function public.bike_apply_meetup(
  p_meetup_id bigint,
  p_name      text,
  p_phone     text default null,
  p_email     text default null,
  p_region    text default null,
  p_bike_type text default null,
  p_message   text default null,
  p_password  text default null
)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_m   record;
  v_id  bigint;
begin
  select * into v_m from public.bike_meetups where id = p_meetup_id;
  if not found then raise exception '모임을 찾을 수 없습니다.'; end if;
  if v_m.status <> 'open' then raise exception '현재 신청을 받지 않는 모임입니다.'; end if;
  if v_m.applied_count >= v_m.capacity then raise exception '정원이 모두 찼습니다.'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception '이름을 입력해 주세요.'; end if;

  if v_uid is null then
    if coalesce(p_password, '') = '' or length(p_password) < 4 then
      raise exception '취소용 비밀번호를 4자 이상 입력해 주세요.';
    end if;
  else
    if exists (select 1 from public.bike_applications
                where meetup_id = p_meetup_id and user_id = v_uid and status <> 'cancelled') then
      raise exception '이미 신청한 모임입니다.';
    end if;
  end if;

  insert into public.bike_applications (meetup_id, user_id, name, phone, email, region, bike_type, message)
  values (p_meetup_id, v_uid, trim(p_name), p_phone, p_email, p_region, p_bike_type, p_message)
  returning id into v_id;

  if v_uid is null then
    insert into public.bike_secrets (entity, entity_id, pw_hash)
    values ('application', v_id, crypt(p_password, gen_salt('bf')));
  end if;

  return v_id;
end;
$$;

create or replace function public.bike_cancel_application(p_id bigint, p_password text default null)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_user uuid;
begin
  select user_id into v_user from public.bike_applications where id = p_id;
  if not found then raise exception '신청 내역을 찾을 수 없습니다.'; end if;

  if v_user is not null then
    if v_uid is null or (v_uid <> v_user and not public.bike_is_admin()) then
      raise exception '취소 권한이 없습니다.';
    end if;
  else
    if not public.bike_is_admin() and not public.bike_check_pw('application', p_id, p_password) then
      raise exception '비밀번호가 일치하지 않습니다.';
    end if;
  end if;

  update public.bike_applications set status = 'cancelled' where id = p_id;
  return true;
end;
$$;

-- 비회원이 이름 + 연락처로 자기 신청 내역을 찾습니다.
create or replace function public.bike_find_applications(p_name text, p_phone text)
returns table (id bigint, meetup_id bigint, meetup_title text, start_at timestamptz, status text, created_at timestamptz)
language sql
security definer
set search_path = public, extensions
as $$
  select a.id, a.meetup_id, m.title, m.start_at, a.status, a.created_at
    from public.bike_applications a
    join public.bike_meetups m on m.id = a.meetup_id
   where a.user_id is null
     and a.name = trim(p_name)
     and coalesce(a.phone,'') = coalesce(trim(p_phone),'')
   order by a.created_at desc;
$$;

-- =====================================================================
-- 트리거 : 신청 인원 자동 집계 / 삭제 시 비밀번호 해시 정리
-- =====================================================================
create or replace function public.bike_sync_applied_count()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_meetup bigint;
begin
  v_meetup := coalesce(new.meetup_id, old.meetup_id);
  update public.bike_meetups m
     set applied_count = (select count(*) from public.bike_applications a
                           where a.meetup_id = v_meetup and a.status <> 'cancelled')
   where m.id = v_meetup;
  return null;
end;
$$;

drop trigger if exists bike_applications_count on public.bike_applications;
create trigger bike_applications_count
  after insert or update or delete on public.bike_applications
  for each row execute function public.bike_sync_applied_count();

create or replace function public.bike_cleanup_secret()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.bike_secrets
   where entity = tg_argv[0] and entity_id = old.id;
  return null;
end;
$$;

drop trigger if exists bike_posts_secret_cleanup on public.bike_posts;
create trigger bike_posts_secret_cleanup after delete on public.bike_posts
  for each row execute function public.bike_cleanup_secret('post');

drop trigger if exists bike_comments_secret_cleanup on public.bike_comments;
create trigger bike_comments_secret_cleanup after delete on public.bike_comments
  for each row execute function public.bike_cleanup_secret('comment');

drop trigger if exists bike_applications_secret_cleanup on public.bike_applications;
create trigger bike_applications_secret_cleanup after delete on public.bike_applications
  for each row execute function public.bike_cleanup_secret('application');

-- =====================================================================
-- 관리자 권한 부여 (강의 실습용)
--   ⚠️ 실제 운영 사이트에서는 이 함수를 반드시 삭제하고
--      Supabase 대시보드에서 role 을 직접 바꾸세요.
--      drop function public.bike_claim_admin(text);
-- =====================================================================
create or replace function public.bike_claim_admin(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then raise exception '로그인 후 이용해 주세요.'; end if;
  -- ⚠️ 아래 'CHANGE-ME' 를 직접 정한 코드로 바꾼 뒤 실행하세요. 저장소에는 실제 코드를 남기지 않습니다.
  if p_code is distinct from 'CHANGE-ME' then raise exception '관리자 코드가 올바르지 않습니다.'; end if;
  update public.bike_profiles set role = 'admin' where id = auth.uid();
  return true;
end;
$$;

-- =====================================================================
-- 실행 권한 정리
--   화면에서 부르는 함수만 열고, 내부 전용 함수는 닫습니다.
-- =====================================================================
grant execute on function
  public.bike_create_post(text,text,text,text,text,text,text,text[],boolean),
  public.bike_update_post(bigint,text,text,text,text,text,text[],boolean),
  public.bike_delete_post(bigint,text),
  public.bike_list_posts(text,text,text,integer,integer),
  public.bike_read_secret_post(bigint,text),
  public.bike_increment_view(bigint),
  public.bike_create_comment(bigint,text,text,text),
  public.bike_delete_comment(bigint,text),
  public.bike_apply_meetup(bigint,text,text,text,text,text,text,text),
  public.bike_cancel_application(bigint,text),
  public.bike_find_applications(text,text),
  public.bike_claim_admin(text),
  public.bike_is_admin()
to anon, authenticated;

-- 내부 전용(트리거·비밀번호 검증)은 API 에서 부를 수 없게 회수
revoke execute on function public.bike_check_pw(text,bigint,text)   from public, anon, authenticated;
revoke execute on function public.bike_cleanup_secret()             from public, anon, authenticated;
revoke execute on function public.bike_sync_applied_count()         from public, anon, authenticated;
revoke execute on function public.bike_touch_updated_at()           from public, anon, authenticated;
