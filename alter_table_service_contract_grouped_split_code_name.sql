-- service_contract_grouped: 코드/명칭 분리 ALTER
-- 변경 내용:
--   detail_item_name (코드값) → detail_item_code + detail_item_name (명칭)
--   demand_agency (코드값) → demand_agency_code + demand_agency (명칭)
-- ETL 재실행 후 명칭 컬럼이 채워짐
USE g2b;

ALTER TABLE service_contract_grouped
  CHANGE COLUMN detail_item_name
    detail_item_code VARCHAR(50) DEFAULT NULL
    COMMENT '세부품명코드',

  CHANGE COLUMN demand_agency
    demand_agency_code VARCHAR(50) DEFAULT NULL
    COMMENT '수요기관코드';

ALTER TABLE service_contract_grouped
  ADD COLUMN detail_item_name VARCHAR(200) DEFAULT NULL
    COMMENT '세부품명명칭'
    AFTER detail_item_code,

  ADD COLUMN demand_agency TEXT DEFAULT NULL
    COMMENT '수요기관명칭'
    AFTER demand_agency_code;
