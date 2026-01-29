-- 장기계약 쿼리 최적화용 인덱스 (query_long_term_contracts.sql 실행 전 적용 권장)
-- 1) WHERE contract_type 제외 + GROUP BY bid_notice_no + MIN(reference_date) 에 사용

USE g2b;

CREATE INDEX idx_contract_type_bid_ref
  ON procurement_raw (contract_type, bid_notice_no, reference_date);
