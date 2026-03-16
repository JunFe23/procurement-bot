-- 물품 계약 아이템별 조회(펼쳐서 보기)용 테이블
-- 탑인더스트리(1188117437), 탑정보통신(1188119624) 취급 (item_category_no, detail_item_no) 쌍 기준 시장 전체 대상
-- PK: (contract_no, item_seq) — 계약번호 + 물품순번 = 최종 계약 기준 1건
-- 최종행 선택: is_final_contract='Y' + 최고 contract_change_seq
-- 기간 필터 기준 컬럼: contract_date (reference_date → DATE 변환)
-- 갱신: sp_etl_procurement_contracts() UPSERT + is_active 소프트 삭제 (TRUNCATE 없음)

USE g2b;

CREATE TABLE IF NOT EXISTS procurement_contract_flat (

  -- ===== PK =====
  contract_no            VARCHAR(100) NOT NULL COMMENT '계약번호',
  item_seq               BIGINT       NOT NULL COMMENT '물품순번',

  -- ===== 계약 정보 =====
  vendor_biz_reg_no      VARCHAR(50)  DEFAULT NULL COMMENT '업체사업자등록번호',
  vendor_name            TEXT         DEFAULT NULL COMMENT '업체명',
  contract_title         TEXT         DEFAULT NULL COMMENT '계약명',
  demand_agency_name     TEXT         DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region   VARCHAR(100) DEFAULT NULL COMMENT '수요기관지역명',
  contract_method        VARCHAR(100) DEFAULT NULL COMMENT '계약방법명',
  bid_notice_no          VARCHAR(50)  DEFAULT NULL COMMENT '입찰공고번호',
  is_long_term           CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '장기계속여부(is_long_term_continuous)',

  -- ===== 물품 정보 =====
  item_category_no       VARCHAR(20)  DEFAULT NULL COMMENT '물품분류번호',
  item_category_name     TEXT         DEFAULT NULL COMMENT '물품분류명',
  detail_item_no         VARCHAR(50)  DEFAULT NULL COMMENT '세부품명번호',
  detail_item_name       TEXT         DEFAULT NULL COMMENT '세부품명',
  item_identifier_no     VARCHAR(50)  DEFAULT NULL COMMENT '물품식별번호',
  item_identifier_name   TEXT         DEFAULT NULL COMMENT '물품식별명',
  unit                   VARCHAR(100) DEFAULT NULL COMMENT '단위',
  unit_price             BIGINT       DEFAULT NULL COMMENT '단가',
  quantity               BIGINT       DEFAULT NULL COMMENT '수량',
  is_mas                 VARCHAR(10)  DEFAULT NULL COMMENT 'MAS여부',
  is_excellent_product   VARCHAR(10)  DEFAULT NULL COMMENT '우수제품여부',
  is_sme_competitive     VARCHAR(10)  DEFAULT NULL COMMENT '중기간경쟁물품여부',

  -- ===== 날짜·금액 =====
  -- first_contract_date: first_reference_date(BIGINT YYYYMMDD) → DATE
  -- contract_date      : reference_date(BIGINT YYYYMMDD) → DATE  (기간 필터 기준)
  first_contract_date    DATE         DEFAULT NULL COMMENT '최초계약일자(first_reference_date→DATE)',
  contract_date          DATE         DEFAULT NULL COMMENT '계약일자(reference_date→DATE, 기간 필터)',
  contract_amount        BIGINT       DEFAULT NULL COMMENT '계약금액',
  latest_change_seq      BIGINT       DEFAULT NULL COMMENT '반영된 계약변경차수',

  -- ===== ETL 관리 =====
  saved                  CHAR(1)      NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active              CHAR(1)      NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=raw에서 사라짐)',
  last_seen_date         DATE         DEFAULT NULL COMMENT 'ETL에서 마지막으로 확인한 날짜',
  etl_loaded_at          DATETIME     DEFAULT NULL COMMENT 'ETL 적재/갱신 시각',

  PRIMARY KEY (contract_no, item_seq),
  KEY idx_contract_date        (contract_date),
  KEY idx_first_contract_date  (first_contract_date),
  KEY idx_vendor               (vendor_biz_reg_no),
  KEY idx_bid_notice_no        (bid_notice_no),
  KEY idx_item_category_no     (item_category_no),
  KEY idx_detail_item_no       (detail_item_no),
  KEY idx_is_long_term         (is_long_term),
  KEY idx_saved                (saved),
  KEY idx_is_active            (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='물품 계약 아이템별(펼쳐서 보기). 탑인더스트리/탑정보통신 취급 품목 기준 시장 전체. PK=(contract_no,item_seq). 기간필터=contract_date';
