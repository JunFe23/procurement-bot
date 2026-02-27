-- 매일 새벽 3시에 construction_contract_summary 갱신 (물품 요약 이벤트 2시와 겹치지 않음)
-- 선행: create_table_construction_contract_summary.sql, create_procedure_refresh_construction_summary.sql
-- 이벤트 스케줄러 활성화: SET GLOBAL event_scheduler = ON;

USE g2b;

DROP EVENT IF EXISTS evt_daily_refresh_construction_contract_summary;

CREATE EVENT evt_daily_refresh_construction_contract_summary
  ON SCHEDULE EVERY 1 DAY
  STARTS (CURRENT_DATE + INTERVAL 1 DAY) + INTERVAL 3 HOUR  -- 내일 03:00
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT '매일 construction_contract_summary TRUNCATE 후 INSERT'
  DO
    CALL sp_refresh_construction_contract_summary();
