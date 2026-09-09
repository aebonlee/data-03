-- =====================================================================
-- 스카이라이더스 — 04. 이미지 업로드용 Storage 버킷
-- ---------------------------------------------------------------------
-- 라이딩 후기 사진을 올리는 곳입니다.
--   · 읽기   : 누구나 (public 버킷)
--   · 업로드 : 로그인 회원만, 자기 UUID 폴더 아래에만
--   · 삭제   : 본인 파일 또는 관리자
-- 비회원은 업로드 대신 이미지 주소(URL)를 붙여넣는 방식으로 씁니다.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bike-photos', 'bike-photos', true, 5242880,
        array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update
  set public = true,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists bike_photos_read   on storage.objects;
drop policy if exists bike_photos_insert on storage.objects;
drop policy if exists bike_photos_delete on storage.objects;

create policy bike_photos_read on storage.objects
  for select using (bucket_id = 'bike-photos');

create policy bike_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'bike-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy bike_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'bike-photos'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.bike_is_admin()));
