-- 공사 계약 단건(펼쳐서 보기)용 조회 테이블
-- 시설공사만, contract_no당 최종 1건. 기간 필터: contract_date
-- 최종행 선택: is_final_contract='Y' 우선 → change_seq DESC → contract_date DESC

USE g2b;

CREATE TABLE IF NOT EXISTS construction_contract_flat (
  contract_no                        VARCHAR(100)  NOT NULL COMMENT '계약번호',
  vendor_biz_reg_no                  VARCHAR(50)   DEFAULT NULL COMMENT '업체사업자등록번호',
  domain_type                        VARCHAR(20)   NOT NULL DEFAULT 'CONST' COMMENT '도메인 구분',
  initial_year_contract_no           VARCHAR(100)  DEFAULT NULL COMMENT '초년도계약번호(장기계약 group_key)',
  is_long_term_contract              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '장기계속계약 여부 Y/N',
  vendor_name                        TEXT          DEFAULT NULL COMMENT '업체명',
  contract_title                     TEXT          DEFAULT NULL COMMENT '계약건명',
  demand_agency_name                 TEXT          DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region               VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역명',
  public_procurement_category_name   TEXT          DEFAULT NULL COMMENT '품명내용',
  bid_contract_method                VARCHAR(100)  DEFAULT NULL COMMENT '입찰계약방법',
  bid_notice_no                      VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호',
  first_contract_date                 DATE          DEFAULT NULL COMMENT '최초계약일자',
  first_contract_amount              BIGINT        DEFAULT NULL COMMENT '최초계약금액',
  contract_date                      DATE          DEFAULT NULL COMMENT '계약일자(기간 필터 기준)',
  contract_amount                    BIGINT        DEFAULT NULL COMMENT '계약금액',
  latest_change_seq                  BIGINT        DEFAULT NULL COMMENT '계약변경차수',
  saved                              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  is_active                          CHAR(1)       NOT NULL DEFAULT 'Y' COMMENT '활성 여부(N=raw에 없음)',
  last_seen_date                     DATE          DEFAULT NULL COMMENT 'raw에 마지막으로 본 날짜',
  etl_loaded_at                      DATETIME      DEFAULT NULL COMMENT 'ETL 적재 시각',
  PRIMARY KEY (contract_no),
  KEY idx_contract_date (contract_date),
  KEY idx_first_contract_date (first_contract_date),
  KEY idx_initial_year_contract_no (initial_year_contract_no),
  KEY idx_is_long_term_contract (is_long_term_contract),
  KEY idx_saved (saved),
  KEY idx_is_active (is_active),
  KEY idx_vendor_biz_reg_no (vendor_biz_reg_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='공사 단건 조회(펼쳐서 보기). 시설공사, contract_no당 최종 1건. 기간필터=contract_date';
