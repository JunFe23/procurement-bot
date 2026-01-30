-- 집계용 테이블: procurement_raw 기반 장기/비장기 계약 집계 결과 (입찰공고번호 + 업체사업자등록번호 단위)
-- API·조회 페이지는 이 테이블을 조회 (매일 프로시저로 TRUNCATE 후 INSERT)
-- 기존 테이블이 이미 있으면: alter_table_procurement_contract_summary_add_vendor.sql 로 컬럼/PK 추가

USE g2b;

CREATE TABLE IF NOT EXISTS procurement_contract_summary (
  bid_notice_no        VARCHAR(50)  NOT NULL COMMENT '입찰공고번호',
  vendor_biz_reg_no     VARCHAR(50)  NOT NULL COMMENT '업체사업자등록번호',
  contract_no           VARCHAR(100) NOT NULL DEFAULT '' COMMENT '계약번호(공고없음 시 계약 구분용, 공고있으면 빈값)',
  vendor_name           TEXT         DEFAULT NULL COMMENT '업체명',
  contract_title        TEXT         DEFAULT NULL COMMENT '계약명',
  demand_agency_name    TEXT         DEFAULT NULL COMMENT '수요기관명',
  demand_agency_region   VARCHAR(255) DEFAULT NULL COMMENT '수요기관지',
  detail_item_name      TEXT         DEFAULT NULL COMMENT '품명내용',
  contract_method       VARCHAR(100) DEFAULT NULL COMMENT '입찰계약방법',
  first_contract_date   DATE         DEFAULT NULL COMMENT '최초계약일자',
  first_contract_amount BIGINT       DEFAULT NULL COMMENT '최초계약금액',
  final_contract_date   DATE         DEFAULT NULL COMMENT '최종계약일자',
  final_contract_amount BIGINT       DEFAULT NULL COMMENT '최종계약금액',
  contract_count        INT          DEFAULT NULL COMMENT '계약차수',
  is_long_term          CHAR(1)      DEFAULT NULL COMMENT '장기계약여부 Y/N',
  PRIMARY KEY (bid_notice_no, vendor_biz_reg_no, contract_no),
  KEY idx_is_long_term (is_long_term),
  KEY idx_first_contract_date (first_contract_date),
  KEY idx_final_contract_date (final_contract_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='procurement_raw 집계 결과 (매일 갱신)';
