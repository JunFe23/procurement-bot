-- 물품 계약 합쳐서 보기용 테이블 (입찰공고번호 + 업체 단위 집계)
-- 탑인더스트리/탑정보통신 취급 (item_category_no, detail_item_no) 쌍 기준 시장 전체 대상
-- PK: (bid_notice_no, vendor_biz_reg_no, contract_no)
--   bid_notice_no : 입찰공고번호. 없으면 빈값('')
--   contract_no   : 공고 있으면 빈값(''). 공고 없는 계약 구분용 (서로 다른 계약이 한 행으로 뭉치는 것 방지)
-- 장기계약(is_long_term='Y'): 같은 공고+업체 묶음에 계약번호 2개 이상 OR is_long_term_continuous='Y'
-- 비장기계약(is_long_term='N'): 1건 = 1행 (같은 컬럼 구조)
-- 기간 필터 기준 컬럼: initial_contract_date (그룹 내 최초 계약일)
-- 갱신: sp_etl_procurement_contracts() UPSERT + is_active 소프트 삭제 (TRUNCATE 없음)
-- 소스: procurement_contract_flat (is_active='Y') → raw 재스캔 불필요

USE g2b;

CREATE TABLE IF NOT EXISTS procurement_contract_grouped (

  -- ===== PK =====
  bid_notice_no          VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '입찰공고번호(없으면 빈값)',
  vendor_biz_reg_no      VARCHAR(50)  NOT NULL COMMENT '업체사업자등록번호',
  contract_no            VARCHAR(100) NOT NULL DEFAULT '' COMMENT '계약번호(공고없음 시 구분용, 공고있으면 빈값)',

  -- ===== 업체·계약 정보 (그룹 내 최초 계약 기준) =====
  vendor_name            TEXT         DEFAULT NULL COMMENT '업체명',
  contract_title         TEXT         DEFAULT NULL COMMENT '계약명',
  demand_agency_name     TEXT         DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region   VARCHAR(100) DEFAULT NULL COMMENT '수요기관지역명',
  contract_method        VARCHAR(100) DEFAULT NULL COMMENT '계약방법명',
  detail_item_name       TEXT         DEFAULT NULL COMMENT '세부품명(최초 계약 기준)',

  -- ===== 집계 =====
  -- initial_contract_date  : 그룹 내 MIN(contract_date) — 기간 필터 기준
  -- initial_contract_amount: 그룹 내 contract_date = initial_contract_date 행들의 금액 합계
  -- final_contract_date    : 그룹 내 MAX(contract_date)
  -- final_contract_amount_sum: 그룹 내 전체 contract_amount 합계 (장기=연도별 합산, 단건=해당 금액)
  -- contract_count         : 그룹 내 DISTINCT contract_no 수 (장기=2+, 단건=1)
  initial_contract_date  DATE         DEFAULT NULL COMMENT '그룹 최초 계약일(기간 필터)',
  initial_contract_amount BIGINT      DEFAULT NULL COMMENT '그룹 최초 계약 시점 금액 합계',
  final_contract_date    DATE         DEFAULT NULL COMMENT '그룹 최종 계약일',
  final_contract_amount_sum BIGINT    DEFAULT NULL COMMENT '그룹 전체 계약금액 합계(화면 최종계약금액)',
  contract_count         INT          DEFAULT NULL COMMENT '그룹 내 계약 건수(장기=2+, 단건=1)',
  is_long_term           CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '장기여부(contract_count>1 OR is_long_term_continuous=Y → Y)',

  -- ===== ETL 관리 =====
  saved                  CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active              CHAR(1)      NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=flat에서 사라짐)',
  last_seen_date         DATE         DEFAULT NULL COMMENT 'ETL에서 마지막으로 확인한 날짜',
  etl_loaded_at          DATETIME     DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (bid_notice_no, vendor_biz_reg_no, contract_no),
  KEY idx_initial_contract_date   (initial_contract_date),
  KEY idx_final_contract_date     (final_contract_date),
  KEY idx_vendor                  (vendor_biz_reg_no),
  KEY idx_is_long_term            (is_long_term),
  KEY idx_saved                   (saved),
  KEY idx_is_active               (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='물품 계약 합쳐서 보기(공고+업체 단위). 탑인더스트리/탑정보통신 취급 품목 기준 시장 전체. 기간필터=initial_contract_date';
