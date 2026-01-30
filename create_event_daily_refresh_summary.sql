-- 매일 새벽 집계용 테이블 갱신 이벤트
-- 선행: create_table_procurement_contract_summary.sql, create_procedure_refresh_contract_summary.sql
-- 이벤트 스케줄러 활성화: SET GLOBAL event_scheduler = ON;

USE g2b;

-- 기존 이벤트 제거 후 생성 (idempotent)
DROP EVENT IF EXISTS evt_daily_refresh_procurement_contract_summary;

CREATE EVENT evt_daily_refresh_procurement_contract_summary
  ON SCHEDULE EVERY 1 DAY
  STARTS (CURRENT_DATE + INTERVAL 1 DAY) + INTERVAL 2 HOUR  -- 내일 02:00
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT '매일 procurement_contract_summary TRUNCATE 후 INSERT'
  DO
    CALL sp_refresh_procurement_contract_summary();
