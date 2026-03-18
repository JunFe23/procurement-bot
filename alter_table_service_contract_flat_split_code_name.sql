-- service_contract_flat: 코드/명칭 분리 ALTER
-- 변경 내용:
--   representative_item_category (코드값) → representative_item_category_code
--   + ADD representative_item_category (명칭)
--   detail_item_name (코드값) → detail_item_code
--   + ADD detail_item_name (명칭)
--   demand_agency (코드값) → demand_agency_code
--   + ADD demand_agency (명칭)
-- ETL 재실행 후 명칭 컬럼이 채워짐
USE g2b;

ALTER TABLE service_contract_flat
  CHANGE COLUMN representative_item_category
    representative_item_category_code VARCHAR(50) DEFAULT NULL
    COMMENT '대표물품분류코드',

  CHANGE COLUMN detail_item_name
    detail_item_code VARCHAR(50) DEFAULT NULL
    COMMENT '세부품명코드',

  CHANGE COLUMN demand_agency
    demand_agency_code VARCHAR(50) DEFAULT NULL
    COMMENT '수요기관코드';

ALTER TABLE service_contract_flat
  ADD COLUMN representative_item_category VARCHAR(200) DEFAULT NULL
    COMMENT '대표물품분류명칭'
    AFTER representative_item_category_code,

  ADD COLUMN detail_item_name VARCHAR(200) DEFAULT NULL
    COMMENT '세부품명명칭'
    AFTER detail_item_code,

  ADD COLUMN demand_agency TEXT DEFAULT NULL
    COMMENT '수요기관명칭'
    AFTER demand_agency_code;
