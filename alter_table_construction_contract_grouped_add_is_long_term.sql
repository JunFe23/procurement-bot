-- construction_contract_grouped에 is_long_term_contract 컬럼 추가 (기존 테이블이 이미 있는 경우)
-- 새로 만드는 경우 create_table_construction_contract_grouped.sql 에 이미 포함됨.

USE g2b;

ALTER TABLE construction_contract_grouped
  ADD COLUMN is_long_term_contract CHAR(1) NOT NULL DEFAULT 'N' COMMENT '장기계약 여부 Y/N(contract_count>1이면 Y)' AFTER contract_count;

CREATE INDEX idx_is_long_term_contract ON construction_contract_grouped (is_long_term_contract);
