-- 보고서 테이블 Collation 통일: utf8mb4_unicode_ci → utf8mb4_0900_ai_ci
-- 대상: procurement_contract_summary, construction_contract_* 5개 테이블
-- CONVERT TO CHARACTER SET: 테이블 + 모든 컬럼 collation 일괄 변경
-- 실행: mysql -u root g2b < alter_table_collation_to_0900.sql

USE g2b;

ALTER TABLE procurement_contract_summary
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE construction_contract_raw
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE construction_contract_flat
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE construction_contract_grouped
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE construction_contract_change_history
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
