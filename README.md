# 🚴 스카이라이더스 (SKY RIDERS) — 로드 자전거 동호회 웹사이트

강의 실습용 샘플 사이트입니다.
**순수 HTML / CSS / JavaScript + Supabase** 조합으로, 빌드 도구 없이 파일만 올리면 바로 동작합니다.

- 주 컬러: 스카이블루 (`#38bdf8` → `#0284c7`)
- 배경: CSS 하늘 그라디언트 + 떠다니는 구름·자전거 이모지 (외부 이미지 의존 없음)
- 테이블 접두어: `bike_`

---

## 1. 파일 구조

```
bike-club/
├── index.html          홈 (히어로, 다가오는 모임, 코스, 후기, 최신 글)
├── about.html          동호회 소개 (활동 방식, 안전 수칙, 가입 안내)
├── meetups.html        모임 일정 목록 (정기/소모임·지역·기간 필터)
├── meetup.html         모임 상세 + 참가 신청 + (관리자) 신청자 관리
├── courses.html        지역별 자전거 코스
├── board.html          게시판 목록 (공지·자유·후기·Q&A / 검색 · 페이지네이션)
├── post.html           게시글 보기 + 댓글 + Q&A 답변
├── write.html          글쓰기 / 글수정 (+ 사진 업로드)
├── login.html          로그인 / 회원가입
├── mypage.html         마이페이지 (회원) · 비회원 신청 조회
├── admin.html          관리자 (대시보드·모임·코스·게시글·신청자·회원)
├── assets/
│   ├── css/style.css   전체 스타일 (디자인 토큰 → 컴포넌트 순서)
│   └── js/
│       ├── config.js   ★ Supabase URL / 키 / 접두어 — 여기만 바꾸면 이전 완료
│       └── app.js      공통 스크립트 (헤더·푸터, 로그인 상태, 유틸, 토스트)
└── sql/
    ├── 01_schema.sql   테이블 · 인덱스 · RLS 활성화
    ├── 02_policies.sql RLS 정책
    ├── 03_functions.sql CRUD 함수(RPC) · 트리거 · 권한
    ├── 04_storage.sql  사진 업로드용 Storage 버킷
    └── 05_seed.sql     샘플 데이터
```

---

## 2. 설치

### 이미 설정이 끝난 상태입니다
연결된 Supabase 프로젝트(`hcmgdztsgjvzcyxyayaj`)에 테이블·정책·함수·샘플 데이터가 모두 반영되어 있습니다.
**웹 서버에 파일만 올리면 바로 동작합니다.**

### 다른 프로젝트에 새로 올릴 때
1. Supabase 대시보드 → SQL Editor에서 `sql/01 → 02 → 03 → 04 → 05` 순서로 실행
2. `assets/js/config.js`의 `SUPABASE_URL`, `SUPABASE_KEY`를 새 프로젝트 값으로 교체
3. 파일 전체를 웹 서버에 업로드

> 로컬에서 열 때는 `file://`이 아니라 간단한 서버를 띄우세요.
> `python3 -m http.server 8080` → http://localhost:8080

### GitHub Pages로 공개하기
저장소 **Settings → Pages → Source: `main` / `/ (root)`** 로 두면
`https://aebonlee.github.io/data-03/` 에서 바로 열립니다.
빌드 과정이 없는 정적 사이트라 별도 워크플로가 필요 없습니다.

---

## 3. 관리자 계정 만들기

1. `login.html`에서 회원가입 → 로그인
2. `mypage.html` → **프로필 설정** 탭 → 관리자 코드 입력
3. 헤더에 **⚙️ 관리자** 버튼이 생깁니다

> 🔑 실제 관리자 코드는 이 저장소에 올리지 않았습니다.
> `sql/03_functions.sql`의 `bike_claim_admin` 함수에 `'CHANGE-ME'`로 표시되어 있으니,
> 직접 정한 값으로 바꿔 SQL Editor에서 실행하세요.
>
> ⚠️ 코드 방식은 **강의 실습 편의를 위한 것**입니다. 실제 운영 시에는
> `drop function public.bike_claim_admin(text);` 로 제거하고,
> Supabase 대시보드에서 `bike_profiles.role`을 직접 `admin`으로 바꾸세요.

---

## 4. 데이터베이스 설계

| 테이블 | 용도 |
|---|---|
| `bike_profiles` | 회원 프로필 (`auth.users`와 1:1) |
| `bike_meetups` | 정기모임(연 4회) + 소규모 모임(매달) |
| `bike_applications` | 모임 참가 신청 (회원·비회원 공통) |
| `bike_posts` | 통합 게시판 — `board` 컬럼으로 4종 구분 |
| `bike_comments` | 댓글 |
| `bike_courses` | 지역별 추천 코스 |
| `bike_secrets` | 비회원 비밀번호 해시 (**RLS 정책 없음 = 외부 접근 완전 차단**) |

### 게시판을 표 하나로 합친 이유
`board` 컬럼(`notice` / `free` / `review` / `qna`)으로 나누면
목록·상세·작성 화면과 CRUD 코드를 **한 벌만** 만들면 됩니다.
게시판을 추가할 때는 `CHECK` 제약과 `app.js`의 `BOARDS` 객체에 한 줄씩만 더하면 끝입니다.

---

## 5. 권한 설계 (RLS)

브라우저에 들어 있는 publishable 키는 "누구세요"만 알려줍니다.
**"무엇을 할 수 있는가"는 전부 Supabase의 RLS 정책이 정합니다.**

| 대상 | 읽기 | 쓰기 |
|---|---|---|
| 비회원(anon) | 모임·코스·게시글(비밀글 제외)·댓글 | 비밀번호 RPC를 통해서만 |
| 회원(authenticated) | 위 + 내 프로필 / 내 신청 | 본인 글·댓글·신청 |
| 관리자(admin) | 전부 | 전부 |

### 읽기는 테이블 직접, 쓰기는 함수로
- **읽기** — `sb.from('bike_posts').select()` 처럼 테이블을 바로 조회 (RLS가 걸러줍니다)
- **쓰기** — `sb.rpc('bike_create_post', {...})` 처럼 함수 호출
  회원이면 `auth.uid()`로, 비회원이면 비밀번호(bcrypt)로 본인을 확인합니다.
  덕분에 화면 코드에서 회원/비회원 분기를 거의 안 해도 됩니다.

### 주요 함수
| 함수 | 하는 일 |
|---|---|
| `bike_list_posts(board, search, region, limit, offset)` | 목록 + 검색 + 페이지네이션 + 전체 건수 + 댓글 수 (비밀글 마스킹) |
| `bike_create_post` / `bike_update_post` / `bike_delete_post` | 글 CRUD |
| `bike_read_secret_post(id, pw)` | 비회원 비밀글 열람 |
| `bike_create_comment` / `bike_delete_comment` | 댓글 |
| `bike_apply_meetup` / `bike_cancel_application` | 모임 신청·취소 |
| `bike_find_applications(name, phone)` | 비회원 신청 조회 |
| `bike_increment_view(id)` | 조회수 (세션당 1회) |

### 설계에서 짚어둘 점 (강의 포인트)
- **비밀번호 해시를 별도 표로 뺀 이유** — 게시글 표에 같이 두면 목록을 조회할 때 해시까지 딸려 나옵니다. `bike_secrets`는 RLS 정책을 하나도 만들지 않아 클라이언트가 아예 읽을 수 없고, `SECURITY DEFINER` 함수만 접근합니다.
- **`bike_check_pw`는 API에서 회수** — 비밀번호 검증 함수가 외부에 열려 있으면 무제한 대입 통로가 됩니다. `revoke execute ... from anon, authenticated` 로 닫아 두었습니다.
- **NULL 비교 함정** — 비회원 글은 `author_id`가 `NULL`, 비로그인 사용자는 `auth.uid()`도 `NULL`이라 `author_id = auth.uid()`가 `NULL`이 됩니다. `coalesce(..., false)`로 감싸지 않으면 비밀글 내용이 새어 나갑니다. (`bike_list_posts` 참고)
- **`applied_count`는 트리거로 집계** — 신청 표는 관리자만 읽을 수 있어서, 신청 인원을 화면에 보여주려면 모임 표에 캐시 컬럼이 필요합니다.

---

## 6. 사진 업로드

- 버킷: `bike-photos` (공개 읽기, 5MB, 이미지 형식만)
- 업로드: **로그인 회원만**, 자기 UUID 폴더 아래에만 저장
- 비회원: 이미지 주소(URL) 붙여넣기로 사용

---

## 7. 실습용 샘플 데이터

`05_seed.sql`을 다시 실행하면 언제든 초기 상태로 되돌릴 수 있습니다.

- 정기모임 4건 (봄·여름 종료 / 가을·겨울 접수중)
- 소규모 모임 7건
- 지역 코스 8건 (서울~제주)
- 게시글 18건 (공지 4 · 자유 5 · 후기 5 · Q&A 4), 댓글 6건, 신청 5건
- **비회원 글·댓글·신청의 비밀번호는 모두 `1234`** — 수정·삭제 실습에 쓰세요

---

## 8. 수업에서 바로 써먹을 수 있는 실습 과제

1. 게시판 한 종류(예: `gallery`) 추가하기 — `CHECK` 제약 + `app.js`의 `BOARDS`
2. 좋아요 기능 붙이기 — `bike_likes` 표 + RLS 정책 + 토글 RPC
3. 모임 정원이 찼을 때 대기자 명단 만들기
4. 게시글에 태그(배열 컬럼) 추가하고 태그별 필터 만들기
5. 지역별 라이딩 통계 차트 넣기 (모임 수·총 거리)
6. RLS 정책을 일부러 지우고 무슨 일이 벌어지는지 확인하기 ← 이게 제일 인상 깊습니다

---

## 9. 운영 전환 시 체크리스트

- [ ] `bike_claim_admin` 함수 삭제 (또는 코드 교체)
- [ ] Supabase Auth → 이메일 인증(Confirm email) 켜기
- [ ] `bike_find_applications`는 이름+연락처만으로 조회됩니다 — 필요하면 비밀번호 확인 추가
- [ ] 첨부 이미지 URL 화이트리스트 검토
- [ ] 샘플 데이터 정리 (`05_seed.sql`의 `truncate` 부분만 실행)

---

*본 사이트의 동호회·회원·후기는 모두 강의용으로 만든 가상의 내용입니다.*
