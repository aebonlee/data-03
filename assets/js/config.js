/* =====================================================================
 * config.js — Supabase 연결 설정
 * ---------------------------------------------------------------------
 * 이 파일 하나만 바꾸면 다른 Supabase 프로젝트로 옮길 수 있습니다.
 * publishable(anon) 키는 브라우저에 공개되는 값이라 노출되어도 안전합니다.
 * 실제 보안은 Supabase의 RLS(Row Level Security) 정책이 담당합니다.
 * ===================================================================== */

const SUPABASE_URL = 'https://hcmgdztsgjvzcyxyayaj.supabase.co';
const SUPABASE_KEY = 'sb_publishable_vYCKlU2lbPkXpUDj1sILow_DskJCRVS';

/* 모든 테이블 이름 앞에 붙는 접두어 — 한 DB에 여러 사이트를 둘 때 충돌을 막습니다. */
const TABLE_PREFIX = 'bike_';

/* supabase-js UMD 빌드가 만들어 준 전역 객체(supabase)로 클라이언트를 생성합니다. */
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,      // 새로고침해도 로그인 유지
    autoRefreshToken: true,
    storageKey: 'skyriders-auth'  // 같은 도메인의 다른 사이트와 세션이 섞이지 않게 분리
  }
});

/* 테이블 이름을 접두어와 함께 만들어 주는 헬퍼.  T('posts') → 'bike_posts' */
const T = (name) => TABLE_PREFIX + name;
