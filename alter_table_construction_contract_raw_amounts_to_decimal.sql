-- 금액·추정금액 등이 BIGINT(2^63-1)를 초과하는 행으로 인한 Out of range 방지
-- BIGINT → DECIMAL(20,0): 20자리 정수까지 저장 가능 (2^63 초과값도 저장)

USE g2b;

ALTER TABLE construction_contract_raw
  MODIFY COLUMN contract_amount              DECIMAL(20,0) DEFAULT NULL COMMENT '계약금액',
  MODIFY COLUMN contract_amount_delta       DECIMAL(20,0) DEFAULT NULL COMMENT '계약증감금액',
  MODIFY COLUMN first_contract_amount       DECIMAL(20,0) DEFAULT NULL COMMENT '최초계약금액',
  MODIFY COLUMN total_supplementary_amount   DECIMAL(20,0) DEFAULT NULL COMMENT '총부기계약금액',
  MODIFY COLUMN estimated_price             DECIMAL(20,0) DEFAULT NULL COMMENT '예정가격',
  MODIFY COLUMN estimated_amount            DECIMAL(20,0) DEFAULT NULL COMMENT '추정금액',
  MODIFY COLUMN award_amount                DECIMAL(20,0) DEFAULT NULL COMMENT '낙찰금액';
