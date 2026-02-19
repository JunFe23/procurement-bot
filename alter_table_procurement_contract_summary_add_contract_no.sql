-- 기존 procurement_contract_summary 테이블에 contract_no 컬럼 추가 및 PK 변경
-- (공고번호 없을 때 계약별 행 분리용. 프로시저 실행 전 적용)
-- 한 번에 실행: 아래 ALTER 한 문장만 실행하면 됨

USE g2b;

ALTER TABLE procurement_contract_summary
  ADD COLUMN contract_no VARCHAR(100) NOT NULL DEFAULT '' COMMENT '계약번호(공고없음 시 계약 구분용, 공고있으면 빈값)' AFTER vendor_biz_reg_no,
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (bid_notice_no, vendor_biz_reg_no, contract_no);
