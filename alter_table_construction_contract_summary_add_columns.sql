-- construction_contract_summary 에 조회용 컬럼 추가
-- (업체명·계약건명·수요기관지역명·품명내용·입찰계약방법·입찰공고번호·최초계약금액 등)
-- 이미 컬럼이 있으면 에러 나므로, 필요 시 해당 줄 주석 처리 후 실행

USE g2b;

ALTER TABLE construction_contract_summary
  ADD COLUMN demand_agency_region          VARCHAR(255)  DEFAULT NULL COMMENT '수요기관지역명' AFTER demand_agency_name,
  ADD COLUMN public_procurement_category_name TEXT      DEFAULT NULL COMMENT '품명내용(공공조달분류명)' AFTER demand_agency_region,
  ADD COLUMN bid_contract_method           VARCHAR(100)  DEFAULT NULL COMMENT '입찰계약방법' AFTER public_procurement_category_name,
  ADD COLUMN bid_notice_no                 VARCHAR(50)   DEFAULT NULL COMMENT '입찰공고번호' AFTER bid_contract_method,
  ADD COLUMN first_contract_amount         BIGINT        DEFAULT NULL COMMENT '최초계약금액' AFTER first_contract_date;
