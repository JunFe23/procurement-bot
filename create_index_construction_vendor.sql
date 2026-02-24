-- construction_contract_raw: 사업자번호(업체사업자등록번호) 조건 SELECT용 인덱스
-- 테이블을 이미 만든 경우에만 실행 (create_table_construction_contract_raw.sql 에는 인덱스 포함됨)

USE g2b;

CREATE INDEX idx_vendor_biz_reg_no ON construction_contract_raw (vendor_biz_reg_no);
