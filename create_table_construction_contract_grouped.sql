-- 공사 합쳐서 보기용 조회 테이블 (시설공사 전체)
-- group_key = COALESCE(initial_year_contract_no, contract_no) 당 1건
-- 장기계약: 그룹 집계(1행). 비장기: 단건 그대로 같은 양식으로 1행(contract_count=1).
-- 토글 ON이면 이 테이블만 조회 → 장기=합쳐서, 비장기=단건 동일 컬럼. 기간 필터: initial_contract_date
-- 문자열 컬럼: 그룹이면 초기 계약 기준, 단건이면 해당 행 그대로

USE g2b;

CREATE TABLE IF NOT EXISTS construction_contract_grouped (
  group_key                          VARCHAR(100)  NOT NULL COMMENT 'COALESCE(initial_year_contract_no, contract_no)',
  vendor_name                        TEXT          DEFAULT NULL COMMENT '업체명(초기 계약 기준)',
  contract_title                     TEXT          DEFAULT NULL COMMENT '계약건명(초기 계약 기준)',
  demand_agency_name                 TEXT          DEFAULT NULL COMMENT '수요기관명(초기 계약 기준)',
  demand_agency_region               VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역명(초기 계약 기준)',
  public_procurement_category_name   TEXT          DEFAULT NULL COMMENT '품명내용(초기 계약 기준)',
  bid_contract_method                VARCHAR(100)  DEFAULT NULL COMMENT '입찰계약방법(초기 계약 기준)',
  bid_notice_no                      VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호(초기 계약 기준)',
  initial_contract_date              DATE          DEFAULT NULL COMMENT '그룹 최초 계약일자(기간 필터 기준)',
  initial_contract_amount            BIGINT        DEFAULT NULL COMMENT '그룹 최초 계약금액',
  final_contract_date                DATE          DEFAULT NULL COMMENT '그룹 마지막 계약일자',
  final_contract_amount_sum          BIGINT        DEFAULT NULL COMMENT '그룹 계약금액 합계(화면 최종계약금액)',
  final_change_seq                   BIGINT        DEFAULT NULL COMMENT '그룹 최대 변경차수',
  contract_count                     INT           DEFAULT NULL COMMENT '그룹 내 계약 건수(1=단건, 2+=장기)',
  is_long_term_contract              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '장기계약 여부 Y/N(contract_count>1이면 Y)',
  saved                              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active                          CHAR(1)       NOT NULL DEFAULT 'Y' COMMENT '활성 여부',
  last_seen_date                     DATE          DEFAULT NULL COMMENT '마지막 반영일',
  etl_loaded_at                      DATETIME      DEFAULT NULL COMMENT 'ETL 적재 시각',
  PRIMARY KEY (group_key),
  KEY idx_initial_contract_date (initial_contract_date),
  KEY idx_final_contract_date (final_contract_date),
  KEY idx_is_long_term_contract (is_long_term_contract),
  KEY idx_saved (saved),
  KEY idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='공사 합쳐서 보기. 시설공사 전체(장기=그룹1행, 비장기=단건1행). 기간필터=initial_contract_date';
