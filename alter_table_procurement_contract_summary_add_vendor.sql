-- 기존 procurement_contract_summary 테이블에 업체사업자등록번호 반영 (입찰공고+업체 단위로 변경 시)
-- 신규 설치 시에는 create_table_procurement_contract_summary.sql 만 실행하면 됨

USE g2b;

-- 1) 컬럼 추가 (기존 PK가 bid_notice_no 단일일 때)
ALTER TABLE procurement_contract_summary
  ADD COLUMN vendor_biz_reg_no VARCHAR(50) NULL COMMENT '업체사업자등록번호' AFTER bid_notice_no;

-- 2) 기존 데이터가 있으면 업체 구분이 없으므로 빈 값 또는 마이그레이션 로직 필요. 여기서는 기본값 ''
UPDATE procurement_contract_summary SET vendor_biz_reg_no = '' WHERE vendor_biz_reg_no IS NULL;
ALTER TABLE procurement_contract_summary MODIFY COLUMN vendor_biz_reg_no VARCHAR(50) NOT NULL DEFAULT '';

-- 3) PK 변경 (기존 PK 제거 후 복합 PK 추가)
ALTER TABLE procurement_contract_summary DROP PRIMARY KEY;
ALTER TABLE procurement_contract_summary ADD PRIMARY KEY (bid_notice_no, vendor_biz_reg_no);
