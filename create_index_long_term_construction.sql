-- 공사 계약 요약 파이프라인용 인덱스 (원본·조회 테이블)
-- 선행: construction_contract_raw 테이블 존재
-- create_table_construction_contract_summary.sql 적용 후 summary 테이블 인덱스 생성

USE g2b;

-- 1) 원본 테이블: 요약 필터(시설공사·중분류·최종계약)
CREATE INDEX idx_construction_summary_filter
  ON construction_contract_raw (public_procurement_category_major, public_procurement_category_mid, is_final_contract);

-- 2) 원본 테이블: 장기계약 조회·합산용 (first_contract_date, initial_year_contract_no)
CREATE INDEX idx_construction_first_contract_date
  ON construction_contract_raw (first_contract_date);

CREATE INDEX idx_construction_initial_year_contract_no
  ON construction_contract_raw (initial_year_contract_no);

-- 3) 조회 테이블 인덱스(first_contract_date, initial_year_contract_no, saved)는
--    create_table_construction_contract_summary.sql 내 KEY 정의에 포함됨.
