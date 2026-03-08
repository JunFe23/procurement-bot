-- 공사 장기계약 그룹(합쳐서 보기)용 조회 테이블
-- 시설공사만, group_key = COALESCE(initial_year_contract_no, contract_no) 당 1건
-- 장기계약(is_long_term_contract='Y')만 적재. 기간 필터: initial_contract_date
-- 문자열 컬럼(업체명/계약건명/기관명 등): 초기 계약 기준(그룹 내 contract_change_seq 최소인 행)

USE g2b;

CREATE TABLE IF NOT EXISTS construction_contract_longterm_group (
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
  contract_count                     INT           DEFAULT NULL COMMENT '그룹 내 계약 건수',
  saved                              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active                          CHAR(1)       NOT NULL DEFAULT 'Y' COMMENT '활성 여부',
  last_seen_date                     DATE          DEFAULT NULL COMMENT '마지막 반영일',
  etl_loaded_at                      DATETIME      DEFAULT NULL COMMENT 'ETL 적재 시각',
  PRIMARY KEY (group_key),
  KEY idx_initial_contract_date (initial_contract_date),
  KEY idx_final_contract_date (final_contract_date),
  KEY idx_saved (saved),
  KEY idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='공사 장기계약 그룹(합쳐서 보기). group_key당 1건. 기간필터=initial_contract_date';
