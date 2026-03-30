-- 공사 계약 요약 테이블 (화면 1:1 매핑)
-- construction_contract_raw 중 시설공사·최종계약만 필터 후 contract_no 당 최신 1건만 보관 (매일 프로시저로 TRUNCATE 후 INSERT)

USE g2b;

CREATE TABLE IF NOT EXISTS construction_contract_summary (
  contract_no                        VARCHAR(100)  NOT NULL COMMENT '계약번호',
  vendor_biz_reg_no                  VARCHAR(50)   DEFAULT NULL COMMENT '업체사업자등록번호(백엔드)',
  domain_type                        VARCHAR(20)   NOT NULL DEFAULT 'CONST' COMMENT '도메인 구분(백엔드)',
  initial_year_contract_no           VARCHAR(100)  DEFAULT NULL COMMENT '초년도계약번호(장기계약 합산 Key)',
  is_long_term_contract              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '장기계속계약 여부 Y/N',
  vendor_name                        TEXT          DEFAULT NULL COMMENT '업체명',
  contract_title                     TEXT          DEFAULT NULL COMMENT '계약건명',
  demand_agency_name                 TEXT          DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region               VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역명',
  public_procurement_category_name  TEXT          DEFAULT NULL COMMENT '품명내용',
  bid_contract_method                VARCHAR(100)  DEFAULT NULL COMMENT '입찰계약방법',
  bid_notice_no                      VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호',
  first_contract_date                VARCHAR(20)   DEFAULT NULL COMMENT '최초계약일자',
  first_contract_amount              BIGINT        DEFAULT NULL COMMENT '최초계약금액',
  contract_date                      VARCHAR(20)   DEFAULT NULL COMMENT '최종계약일자',
  contract_amount                    BIGINT        DEFAULT NULL COMMENT '최종계약금액',
  latest_change_seq                  BIGINT        DEFAULT NULL COMMENT '계약변경차수',
  saved                              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '화면 저장 체크박스용',
  PRIMARY KEY (contract_no),
  KEY idx_first_contract_date (first_contract_date),
  KEY idx_initial_year_contract_no (initial_year_contract_no),
  KEY idx_is_long_term_contract (is_long_term_contract),
  KEY idx_saved (saved)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='공사 계약 요약 (시설공사·최종계약, contract_no당 최신 1건)';
