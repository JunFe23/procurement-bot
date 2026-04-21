# 탑인더스트리 & 탑정보통신 수주현황DB - 보고서 데이터 구현 프롬프트
## G2BPlatform — Spring Boot + Vue 3 + MyBatis

아래 내용을 Cursor AI에 붙여넣고 "이 설계대로 구현해줘"라고 요청하세요.

---

## [아래부터 복사]

---

## 0. 배경 및 목적

`TopContractsReportView.vue` 화면에서 **탑인더스트리(사업자번호: `1188117437`)** 및
**탑정보통신주식회사(사업자번호: `1188119624`)** 의 물품 / 공사 / 용역 / 쇼핑몰 계약 데이터를
통합 조회할 수 있도록 백엔드 API 와 프론트엔드를 완성한다.

기능 요구사항:
- 4개 데이터 소스(물품/공사/용역/쇼핑몰)를 분류(type) 필터로 선택하거나 전체 통합 조회
- 기존 보고서 페이지와 동일한 검색 조건(수요기관명, 기간, 저장여부 등) 적용
- 서버사이드 페이지네이션 (페이지당 100건)
- 엑셀 다운로드 (SXSSFWorkbook 스트리밍)
- 저장(saved) 체크박스: 물품/공사/용역 기존 PATCH API 재사용, 쇼핑몰은 신규 PATCH API

---

## 1. 프로젝트 파일 경로

```
backend/src/main/java/org/example/g2bplatform/
  controller/ReportDataController.java               ← 엔드포인트 추가
  mapper/TopCompaniesReportMapper.java               ← 신규 생성
  service/TopCompaniesReportService.java             ← 신규 생성

backend/src/main/resources/org/example/g2bplatform/mapper/
  TopCompaniesReportMapper.xml                       ← 신규 생성

frontend/src/views/
  TopContractsReportView.vue                         ← API 연동 구현
```

---

## 2. Step 1 — DB 스키마 변경

`shopping_mall_flat` 테이블에 `saved` 컬럼을 추가한다.
다른 flat 테이블들(procurement_contract_flat, construction_contract_flat, service_contract_flat)은
이미 `saved CHAR(1)` 컬럼을 보유하고 있다.

```sql
-- shopping_mall_flat 에 saved 컬럼 추가 (없는 경우에만 실행)
ALTER TABLE shopping_mall_flat
  ADD COLUMN saved CHAR(1) NOT NULL DEFAULT 'N' COMMENT '저장 여부 (Y/N)';

-- 성능 인덱스
ALTER TABLE shopping_mall_flat
  ADD INDEX idx_smf_saved (saved),
  ADD INDEX idx_smf_vendor_ref  (vendor_biz_reg_no, ref_date),
  ADD INDEX idx_smf_vendor_first (vendor_biz_reg_no, first_ref_date);
```

---

## 3. Step 2 — 데이터 소스별 컬럼 매핑

UNION ALL 에서 공통 컬럼으로 통일할 매핑 기준이다. 각 SELECT 에서 아래 alias 를 사용한다.

| 공통 alias         | 물품 (procurement_contract_flat)       | 공사 (construction_contract_flat)          | 용역 (service_contract_flat)                    | 쇼핑몰 (shopping_mall_flat)         |
|--------------------|----------------------------------------|--------------------------------------------|-------------------------------------------------|-------------------------------------|
| `type`             | `'물품'`                               | `'공사'`                                   | `'용역'`                                        | `'쇼핑몰'`                          |
| `cmpNm`            | `vendor_name`                          | `vendor_name`                              | `vendor_name`                                   | `vendor_name`                       |
| `cntrctNm`         | `contract_title`                       | `contract_title`                           | `contract_title`                                | `contract_title`                    |
| `dminsttNm`        | `demand_agency_name`                   | `demand_agency_name`                       | `demand_agency`                                 | `demand_agency_name`                |
| `dminsttNmDetail`  | `demand_agency_region`                 | `demand_agency_region`                     | `demand_agency_region`                          | `demand_agency_region`              |
| `prdctClsfcNo`     | `detail_item_name`                     | `public_procurement_category_name`         | `public_procurement_category`                   | `detail_item_name`                  |
| `cntctCnclsMthdNm` | `contract_method`                      | `bid_contract_method`                      | `contract_method`                               | `contract_method`                   |
| `ntceNo`           | `bid_notice_no`                        | `bid_notice_no`                            | `bid_notice_no`                                 | `contract_no`                       |
| `firstCntrctDate`  | `first_contract_date`                  | `first_contract_date`                      | `first_contract_date`                           | `first_ref_date`                    |
| `firstCntrctAmt`   | `NULL`                                 | `first_contract_amount`                    | `first_contract_amount`                         | `NULL`                              |
| `cntrctDate`       | `contract_date`                        | `contract_date`                            | `contract_date`                                 | `ref_date`                          |
| `thtmCntrctAmt`    | `contract_amount`                      | `contract_amount`                          | `contract_amount`                               | `supply_amount`                     |
| `cntrctCnt`        | `latest_change_seq`                    | `latest_change_seq`                        | `latest_change_seq`                             | `NULL`                              |
| `saved`            | `IFNULL(saved,'N')`                    | `IFNULL(saved,'N')`                        | `IFNULL(saved,'N')`                             | `IFNULL(saved,'N')`                 |
| `pk1`              | `contract_no`                          | `contract_no`                              | `contract_delivery_integrated_no`               | `delivery_contract_no`              |
| `pk2`              | `CAST(item_seq AS CHAR)`               | `NULL`                                     | `vendor_biz_reg_no`                             | `CAST(delivery_contract_change_seq AS CHAR)` |
| `pk3`              | `NULL`                                 | `NULL`                                     | `NULL`                                          | `CAST(delivery_item_seq AS CHAR)`   |

> 기간 필터 컬럼: 물품/공사/용역은 `contract_date`, 쇼핑몰은 `ref_date`

---

## 4. Step 3 — TopCompaniesReportMapper.java (신규)

```java
// backend/src/main/java/org/example/g2bplatform/mapper/TopCompaniesReportMapper.java
package org.example.g2bplatform.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.session.ResultHandler;

import java.util.List;
import java.util.Map;

@Mapper
public interface TopCompaniesReportMapper {

    List<Map<String, Object>> selectList(
            @Param("type")                String type,
            @Param("dminsttNm")           String dminsttNm,
            @Param("dminsttNmDetail")     String dminsttNmDetail,
            @Param("prdctClsfcNo")        String prdctClsfcNo,
            @Param("cntctCnclsMthdNm")    String cntctCnclsMthdNm,
            @Param("firstCntrctDate")     String firstCntrctDate,
            @Param("year")                Integer year,
            @Param("month")               String month,
            @Param("rangeStart")          String rangeStart,
            @Param("rangeEnd")            String rangeEnd,
            @Param("showSavedOnly")       boolean showSavedOnly,
            @Param("start")               int start,
            @Param("length")              int length
    );

    int selectCount(
            @Param("type")                String type,
            @Param("dminsttNm")           String dminsttNm,
            @Param("dminsttNmDetail")     String dminsttNmDetail,
            @Param("prdctClsfcNo")        String prdctClsfcNo,
            @Param("cntctCnclsMthdNm")    String cntctCnclsMthdNm,
            @Param("firstCntrctDate")     String firstCntrctDate,
            @Param("year")                Integer year,
            @Param("month")               String month,
            @Param("rangeStart")          String rangeStart,
            @Param("rangeEnd")            String rangeEnd,
            @Param("showSavedOnly")       boolean showSavedOnly
    );

    void selectForExport(
            @Param("type")                String type,
            @Param("dminsttNm")           String dminsttNm,
            @Param("dminsttNmDetail")     String dminsttNmDetail,
            @Param("prdctClsfcNo")        String prdctClsfcNo,
            @Param("cntctCnclsMthdNm")    String cntctCnclsMthdNm,
            @Param("firstCntrctDate")     String firstCntrctDate,
            @Param("year")                Integer year,
            @Param("month")               String month,
            @Param("rangeStart")          String rangeStart,
            @Param("rangeEnd")            String rangeEnd,
            @Param("showSavedOnly")       boolean showSavedOnly,
            ResultHandler<Map<String, Object>> handler
    );

    /** 쇼핑몰 saved 갱신 */
    int updateShoppingMallSaved(
            @Param("deliveryContractNo")          String deliveryContractNo,
            @Param("deliveryContractChangeSeq")   Long deliveryContractChangeSeq,
            @Param("deliveryItemSeq")             Long deliveryItemSeq,
            @Param("saved")                       String saved
    );
}
```

---

## 5. Step 4 — TopCompaniesReportMapper.xml (신규)

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE mapper
        PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
        "http://mybatis.org/dtd/mybatis-3-mapper.dtd">

<mapper namespace="org.example.g2bplatform.mapper.TopCompaniesReportMapper">

    <!--
      대상 업체 사업자번호
        탑인더스트리        : 1188117437
        탑정보통신주식회사  : 1188119624
    -->

    <!-- ======================================================= -->
    <!-- 공통 SQL 조각: 각 소스별 SELECT 절                        -->
    <!-- ======================================================= -->

    <!-- 물품 SELECT 본문 -->
    <sql id="procurementSelect">
        SELECT
            '물품'                                                              AS type,
            contract_no                                                         AS pk1,
            CAST(item_seq AS CHAR)                                              AS pk2,
            NULL                                                                AS pk3,
            vendor_name                                                         AS cmpNm,
            contract_title                                                      AS cntrctNm,
            demand_agency_name                                                  AS dminsttNm,
            demand_agency_region                                                AS dminsttNmDetail,
            detail_item_name                                                    AS prdctClsfcNo,
            contract_method                                                     AS cntctCnclsMthdNm,
            bid_notice_no                                                       AS ntceNo,
            DATE_FORMAT(first_contract_date, '%Y-%m-%d')                       AS firstCntrctDate,
            NULL                                                                AS firstCntrctAmt,
            DATE_FORMAT(contract_date, '%Y-%m-%d')                             AS cntrctDate,
            contract_amount                                                     AS thtmCntrctAmt,
            latest_change_seq                                                   AS cntrctCnt,
            IFNULL(saved, 'N')                                                  AS saved
        FROM procurement_contract_flat
        WHERE is_active = 'Y'
          AND vendor_biz_reg_no IN ('1188117437', '1188119624')
        <if test="dminsttNm != null and dminsttNm != ''">
            AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')
        </if>
        <if test="dminsttNmDetail != null and dminsttNmDetail != ''">
            AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')
        </if>
        <if test="prdctClsfcNo != null and prdctClsfcNo != ''">
            AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')
        </if>
        <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">
            AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')
        </if>
        <if test="firstCntrctDate != null and firstCntrctDate != ''">
            AND first_contract_date = #{firstCntrctDate}
        </if>
        <if test="year != null">
            AND contract_date &gt;= CONCAT(#{year}, '-01-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{year}, '-01-01'), INTERVAL 1 YEAR)
        </if>
        <if test="month != null and month != ''">
            AND contract_date &gt;= CONCAT(#{month}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{month}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">
            AND contract_date &gt;= CONCAT(#{rangeStart}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{rangeEnd}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="showSavedOnly == true">
            AND saved = 'Y'
        </if>
    </sql>

    <!-- 공사 SELECT 본문 -->
    <sql id="constructionSelect">
        SELECT
            '공사'                                                              AS type,
            contract_no                                                         AS pk1,
            NULL                                                                AS pk2,
            NULL                                                                AS pk3,
            vendor_name                                                         AS cmpNm,
            contract_title                                                      AS cntrctNm,
            demand_agency_name                                                  AS dminsttNm,
            demand_agency_region                                                AS dminsttNmDetail,
            public_procurement_category_name                                    AS prdctClsfcNo,
            bid_contract_method                                                 AS cntctCnclsMthdNm,
            bid_notice_no                                                       AS ntceNo,
            DATE_FORMAT(first_contract_date, '%Y-%m-%d')                       AS firstCntrctDate,
            first_contract_amount                                               AS firstCntrctAmt,
            DATE_FORMAT(contract_date, '%Y-%m-%d')                             AS cntrctDate,
            contract_amount                                                     AS thtmCntrctAmt,
            latest_change_seq                                                   AS cntrctCnt,
            IFNULL(saved, 'N')                                                  AS saved
        FROM construction_contract_flat
        WHERE is_active = 'Y'
          AND vendor_biz_reg_no IN ('1188117437', '1188119624')
        <if test="dminsttNm != null and dminsttNm != ''">
            AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')
        </if>
        <if test="dminsttNmDetail != null and dminsttNmDetail != ''">
            AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')
        </if>
        <if test="prdctClsfcNo != null and prdctClsfcNo != ''">
            AND public_procurement_category_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')
        </if>
        <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">
            AND bid_contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')
        </if>
        <if test="firstCntrctDate != null and firstCntrctDate != ''">
            AND first_contract_date = #{firstCntrctDate}
        </if>
        <if test="year != null">
            AND contract_date &gt;= CONCAT(#{year}, '-01-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{year}, '-01-01'), INTERVAL 1 YEAR)
        </if>
        <if test="month != null and month != ''">
            AND contract_date &gt;= CONCAT(#{month}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{month}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">
            AND contract_date &gt;= CONCAT(#{rangeStart}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{rangeEnd}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="showSavedOnly == true">
            AND saved = 'Y'
        </if>
    </sql>

    <!-- 용역 SELECT 본문 -->
    <sql id="serviceSelect">
        SELECT
            '용역'                                                              AS type,
            contract_delivery_integrated_no                                     AS pk1,
            vendor_biz_reg_no                                                   AS pk2,
            NULL                                                                AS pk3,
            vendor_name                                                         AS cmpNm,
            contract_title                                                      AS cntrctNm,
            demand_agency                                                       AS dminsttNm,
            demand_agency_region                                                AS dminsttNmDetail,
            public_procurement_category                                         AS prdctClsfcNo,
            contract_method                                                     AS cntctCnclsMthdNm,
            bid_notice_no                                                       AS ntceNo,
            DATE_FORMAT(first_contract_date, '%Y-%m-%d')                       AS firstCntrctDate,
            first_contract_amount                                               AS firstCntrctAmt,
            DATE_FORMAT(contract_date, '%Y-%m-%d')                             AS cntrctDate,
            contract_amount                                                     AS thtmCntrctAmt,
            latest_change_seq                                                   AS cntrctCnt,
            IFNULL(saved, 'N')                                                  AS saved
        FROM service_contract_flat
        WHERE is_active = 'Y'
          AND vendor_biz_reg_no IN ('1188117437', '1188119624')
        <if test="dminsttNm != null and dminsttNm != ''">
            AND demand_agency LIKE CONCAT('%', #{dminsttNm}, '%')
        </if>
        <if test="dminsttNmDetail != null and dminsttNmDetail != ''">
            AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')
        </if>
        <if test="prdctClsfcNo != null and prdctClsfcNo != ''">
            AND public_procurement_category LIKE CONCAT('%', #{prdctClsfcNo}, '%')
        </if>
        <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">
            AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')
        </if>
        <if test="firstCntrctDate != null and firstCntrctDate != ''">
            AND first_contract_date = #{firstCntrctDate}
        </if>
        <if test="year != null">
            AND contract_date &gt;= CONCAT(#{year}, '-01-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{year}, '-01-01'), INTERVAL 1 YEAR)
        </if>
        <if test="month != null and month != ''">
            AND contract_date &gt;= CONCAT(#{month}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{month}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">
            AND contract_date &gt;= CONCAT(#{rangeStart}, '-01')
            AND contract_date &lt;  DATE_ADD(CONCAT(#{rangeEnd}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="showSavedOnly == true">
            AND saved = 'Y'
        </if>
    </sql>

    <!-- 쇼핑몰 SELECT 본문 -->
    <sql id="shoppingMallSelect">
        SELECT
            '쇼핑몰'                                                            AS type,
            delivery_contract_no                                                AS pk1,
            CAST(delivery_contract_change_seq AS CHAR)                         AS pk2,
            CAST(delivery_item_seq AS CHAR)                                    AS pk3,
            vendor_name                                                         AS cmpNm,
            contract_title                                                      AS cntrctNm,
            demand_agency_name                                                  AS dminsttNm,
            demand_agency_region                                                AS dminsttNmDetail,
            detail_item_name                                                    AS prdctClsfcNo,
            contract_method                                                     AS cntctCnclsMthdNm,
            contract_no                                                         AS ntceNo,
            DATE_FORMAT(first_ref_date, '%Y-%m-%d')                            AS firstCntrctDate,
            NULL                                                                AS firstCntrctAmt,
            DATE_FORMAT(ref_date, '%Y-%m-%d')                                  AS cntrctDate,
            supply_amount                                                       AS thtmCntrctAmt,
            NULL                                                                AS cntrctCnt,
            IFNULL(saved, 'N')                                                  AS saved
        FROM shopping_mall_flat
        WHERE is_active = 'Y'
          AND vendor_biz_reg_no IN ('1188117437', '1188119624')
        <if test="dminsttNm != null and dminsttNm != ''">
            AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')
        </if>
        <if test="dminsttNmDetail != null and dminsttNmDetail != ''">
            AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')
        </if>
        <if test="prdctClsfcNo != null and prdctClsfcNo != ''">
            AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')
        </if>
        <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">
            AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')
        </if>
        <if test="year != null">
            AND ref_date &gt;= CONCAT(#{year}, '-01-01')
            AND ref_date &lt;  DATE_ADD(CONCAT(#{year}, '-01-01'), INTERVAL 1 YEAR)
        </if>
        <if test="month != null and month != ''">
            AND ref_date &gt;= CONCAT(#{month}, '-01')
            AND ref_date &lt;  DATE_ADD(CONCAT(#{month}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">
            AND ref_date &gt;= CONCAT(#{rangeStart}, '-01')
            AND ref_date &lt;  DATE_ADD(CONCAT(#{rangeEnd}, '-01'), INTERVAL 1 MONTH)
        </if>
        <if test="showSavedOnly == true">
            AND saved = 'Y'
        </if>
    </sql>

    <!-- ======================================================= -->
    <!-- selectList: 페이지네이션 조회                             -->
    <!-- ======================================================= -->
    <select id="selectList" resultType="map">
        <choose>
            <when test="type == '물품'">
                <include refid="procurementSelect"/>
                ORDER BY cntrctDate DESC, pk1
                LIMIT #{start}, #{length}
            </when>
            <when test="type == '공사'">
                <include refid="constructionSelect"/>
                ORDER BY cntrctDate DESC, pk1
                LIMIT #{start}, #{length}
            </when>
            <when test="type == '용역'">
                <include refid="serviceSelect"/>
                ORDER BY cntrctDate DESC, pk1
                LIMIT #{start}, #{length}
            </when>
            <when test="type == '쇼핑몰'">
                <include refid="shoppingMallSelect"/>
                ORDER BY cntrctDate DESC, pk1
                LIMIT #{start}, #{length}
            </when>
            <otherwise>
                SELECT * FROM (
                    <include refid="procurementSelect"/>
                    UNION ALL
                    <include refid="constructionSelect"/>
                    UNION ALL
                    <include refid="serviceSelect"/>
                    UNION ALL
                    <include refid="shoppingMallSelect"/>
                ) AS combined
                ORDER BY cntrctDate DESC, pk1
                LIMIT #{start}, #{length}
            </otherwise>
        </choose>
    </select>

    <!-- ======================================================= -->
    <!-- selectCount: 전체 건수 (페이지네이션용)                    -->
    <!-- ======================================================= -->
    <select id="selectCount" resultType="int">
        <choose>
            <when test="type == '물품'">
                SELECT COUNT(*) FROM procurement_contract_flat
                WHERE is_active = 'Y'
                  AND vendor_biz_reg_no IN ('1188117437', '1188119624')
                <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                <if test="showSavedOnly == true">AND saved = 'Y'</if>
            </when>
            <when test="type == '공사'">
                SELECT COUNT(*) FROM construction_contract_flat
                WHERE is_active = 'Y'
                  AND vendor_biz_reg_no IN ('1188117437', '1188119624')
                <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND public_procurement_category_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND bid_contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                <if test="showSavedOnly == true">AND saved = 'Y'</if>
            </when>
            <when test="type == '용역'">
                SELECT COUNT(*) FROM service_contract_flat
                WHERE is_active = 'Y'
                  AND vendor_biz_reg_no IN ('1188117437', '1188119624')
                <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND public_procurement_category LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                <if test="showSavedOnly == true">AND saved = 'Y'</if>
            </when>
            <when test="type == '쇼핑몰'">
                SELECT COUNT(*) FROM shopping_mall_flat
                WHERE is_active = 'Y'
                  AND vendor_biz_reg_no IN ('1188117437', '1188119624')
                <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                <if test="year != null">AND ref_date &gt;= CONCAT(#{year},'-01-01') AND ref_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                <if test="month != null and month != ''">AND ref_date &gt;= CONCAT(#{month},'-01') AND ref_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND ref_date &gt;= CONCAT(#{rangeStart},'-01') AND ref_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                <if test="showSavedOnly == true">AND saved = 'Y'</if>
            </when>
            <otherwise>
                SELECT COUNT(*) FROM (
                    SELECT contract_no FROM procurement_contract_flat
                    WHERE is_active = 'Y' AND vendor_biz_reg_no IN ('1188117437','1188119624')
                    <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                    <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                    <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                    <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                    <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                    <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                    <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="showSavedOnly == true">AND saved = 'Y'</if>
                    UNION ALL
                    SELECT contract_no FROM construction_contract_flat
                    WHERE is_active = 'Y' AND vendor_biz_reg_no IN ('1188117437','1188119624')
                    <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                    <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                    <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND public_procurement_category_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                    <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND bid_contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                    <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                    <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                    <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="showSavedOnly == true">AND saved = 'Y'</if>
                    UNION ALL
                    SELECT contract_delivery_integrated_no FROM service_contract_flat
                    WHERE is_active = 'Y' AND vendor_biz_reg_no IN ('1188117437','1188119624')
                    <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                    <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                    <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND public_procurement_category LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                    <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                    <if test="firstCntrctDate != null and firstCntrctDate != ''">AND first_contract_date = #{firstCntrctDate}</if>
                    <if test="year != null">AND contract_date &gt;= CONCAT(#{year},'-01-01') AND contract_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                    <if test="month != null and month != ''">AND contract_date &gt;= CONCAT(#{month},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND contract_date &gt;= CONCAT(#{rangeStart},'-01') AND contract_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="showSavedOnly == true">AND saved = 'Y'</if>
                    UNION ALL
                    SELECT delivery_contract_no FROM shopping_mall_flat
                    WHERE is_active = 'Y' AND vendor_biz_reg_no IN ('1188117437','1188119624')
                    <if test="dminsttNm != null and dminsttNm != ''">AND demand_agency_name LIKE CONCAT('%', #{dminsttNm}, '%')</if>
                    <if test="dminsttNmDetail != null and dminsttNmDetail != ''">AND demand_agency_region LIKE CONCAT('%', #{dminsttNmDetail}, '%')</if>
                    <if test="prdctClsfcNo != null and prdctClsfcNo != ''">AND detail_item_name LIKE CONCAT('%', #{prdctClsfcNo}, '%')</if>
                    <if test="cntctCnclsMthdNm != null and cntctCnclsMthdNm != ''">AND contract_method LIKE CONCAT('%', #{cntctCnclsMthdNm}, '%')</if>
                    <if test="year != null">AND ref_date &gt;= CONCAT(#{year},'-01-01') AND ref_date &lt; DATE_ADD(CONCAT(#{year},'-01-01'),INTERVAL 1 YEAR)</if>
                    <if test="month != null and month != ''">AND ref_date &gt;= CONCAT(#{month},'-01') AND ref_date &lt; DATE_ADD(CONCAT(#{month},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="rangeStart != null and rangeStart != '' and rangeEnd != null and rangeEnd != ''">AND ref_date &gt;= CONCAT(#{rangeStart},'-01') AND ref_date &lt; DATE_ADD(CONCAT(#{rangeEnd},'-01'),INTERVAL 1 MONTH)</if>
                    <if test="showSavedOnly == true">AND saved = 'Y'</if>
                ) AS total_count
            </otherwise>
        </choose>
    </select>

    <!-- ======================================================= -->
    <!-- selectForExport: 엑셀용 스트리밍 (ResultHandler)          -->
    <!-- ======================================================= -->
    <select id="selectForExport" fetchSize="1000" resultType="map">
        <choose>
            <when test="type == '물품'">
                <include refid="procurementSelect"/>
                ORDER BY cntrctDate DESC, pk1
            </when>
            <when test="type == '공사'">
                <include refid="constructionSelect"/>
                ORDER BY cntrctDate DESC, pk1
            </when>
            <when test="type == '용역'">
                <include refid="serviceSelect"/>
                ORDER BY cntrctDate DESC, pk1
            </when>
            <when test="type == '쇼핑몰'">
                <include refid="shoppingMallSelect"/>
                ORDER BY cntrctDate DESC, pk1
            </when>
            <otherwise>
                SELECT * FROM (
                    <include refid="procurementSelect"/>
                    UNION ALL
                    <include refid="constructionSelect"/>
                    UNION ALL
                    <include refid="serviceSelect"/>
                    UNION ALL
                    <include refid="shoppingMallSelect"/>
                ) AS combined
                ORDER BY cntrctDate DESC, pk1
            </otherwise>
        </choose>
    </select>

    <!-- ======================================================= -->
    <!-- 쇼핑몰 saved 갱신                                         -->
    <!-- ======================================================= -->
    <update id="updateShoppingMallSaved">
        UPDATE shopping_mall_flat
        SET saved = #{saved}
        WHERE delivery_contract_no = #{deliveryContractNo}
          AND delivery_contract_change_seq = #{deliveryContractChangeSeq}
          AND delivery_item_seq = #{deliveryItemSeq}
    </update>

</mapper>
```

---

## 6. Step 5 — TopCompaniesReportService.java (신규)

```java
// backend/src/main/java/org/example/g2bplatform/service/TopCompaniesReportService.java
package org.example.g2bplatform.service;

import org.apache.ibatis.session.ResultHandler;
import org.example.g2bplatform.mapper.TopCompaniesReportMapper;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class TopCompaniesReportService {

    private final TopCompaniesReportMapper mapper;

    public TopCompaniesReportService(TopCompaniesReportMapper mapper) {
        this.mapper = mapper;
    }

    public List<Map<String, Object>> getList(
            String type, String dminsttNm, String dminsttNmDetail,
            String prdctClsfcNo, String cntctCnclsMthdNm, String firstCntrctDate,
            Integer year, String month, String rangeStart, String rangeEnd,
            boolean showSavedOnly, int start, int length) {
        return mapper.selectList(type, dminsttNm, dminsttNmDetail,
                prdctClsfcNo, cntctCnclsMthdNm, firstCntrctDate,
                year, month, rangeStart, rangeEnd, showSavedOnly, start, length);
    }

    public int getCount(
            String type, String dminsttNm, String dminsttNmDetail,
            String prdctClsfcNo, String cntctCnclsMthdNm, String firstCntrctDate,
            Integer year, String month, String rangeStart, String rangeEnd,
            boolean showSavedOnly) {
        return mapper.selectCount(type, dminsttNm, dminsttNmDetail,
                prdctClsfcNo, cntctCnclsMthdNm, firstCntrctDate,
                year, month, rangeStart, rangeEnd, showSavedOnly);
    }

    public void streamForExcel(
            String type, String dminsttNm, String dminsttNmDetail,
            String prdctClsfcNo, String cntctCnclsMthdNm, String firstCntrctDate,
            Integer year, String month, String rangeStart, String rangeEnd,
            boolean showSavedOnly, ResultHandler<Map<String, Object>> handler) {
        mapper.selectForExport(type, dminsttNm, dminsttNmDetail,
                prdctClsfcNo, cntctCnclsMthdNm, firstCntrctDate,
                year, month, rangeStart, rangeEnd, showSavedOnly, handler);
    }

    public int updateShoppingMallSaved(
            String deliveryContractNo, Long deliveryContractChangeSeq,
            Long deliveryItemSeq, String saved) {
        return mapper.updateShoppingMallSaved(
                deliveryContractNo, deliveryContractChangeSeq, deliveryItemSeq, saved);
    }
}
```

---

## 7. Step 6 — ReportDataController.java 에 엔드포인트 추가

`ReportDataController.java` 에 아래 내용을 추가한다.

### 7-1. 클래스 상단 필드/생성자에 `TopCompaniesReportService` 추가

```java
private final TopCompaniesReportService topCompaniesReportService;

// 생성자에 파라미터 및 주입 추가
public ReportDataController(ReportDataService reportDataService,
                            ReportConstructionService reportConstructionService,
                            ReportProcurementService reportProcurementService,
                            ReportServiceContractService reportServiceContractService,
                            ShoppingMallService shoppingMallService,
                            TopCompaniesReportService topCompaniesReportService) {
    // 기존 필드 주입 ...
    this.topCompaniesReportService = topCompaniesReportService;
}
```

### 7-2. 신규 엔드포인트 3개 추가 (클래스 맨 아래에 추가)

```java
// ================================================================
// 탑인더스트리 & 탑정보통신 수주현황 (top-companies)
// ================================================================

@Operation(summary = "탑 수주현황 목록", description = "탑인더스트리+탑정보통신 물품/공사/용역/쇼핑몰 통합 조회")
@GetMapping("/top-companies")
public ResponseEntity<Map<String, Object>> getTopCompanies(
        @RequestParam(required = false, defaultValue = "") String type,
        @RequestParam(required = false) String dminsttNm,
        @RequestParam(required = false) String dminsttNmDetail,
        @RequestParam(required = false) String prdctClsfcNo,
        @RequestParam(required = false) String cntctCnclsMthdNm,
        @RequestParam(required = false) String firstCntrctDate,
        @RequestParam(required = false) Integer year,
        @RequestParam(required = false) String month,
        @RequestParam(required = false) String rangeStart,
        @RequestParam(required = false) String rangeEnd,
        @RequestParam(required = false, defaultValue = "false") boolean showSavedOnly,
        @RequestParam(defaultValue = "0") int start,
        @RequestParam(defaultValue = "100") int length
) {
    List<Map<String, Object>> list = topCompaniesReportService.getList(
            type, dminsttNm, dminsttNmDetail, prdctClsfcNo, cntctCnclsMthdNm,
            firstCntrctDate, year, month, rangeStart, rangeEnd, showSavedOnly, start, length);
    int filtered = topCompaniesReportService.getCount(
            type, dminsttNm, dminsttNmDetail, prdctClsfcNo, cntctCnclsMthdNm,
            firstCntrctDate, year, month, rangeStart, rangeEnd, showSavedOnly);
    Map<String, Object> body = new HashMap<>();
    body.put("success", true);
    body.put("data", list);
    body.put("recordsFiltered", filtered);
    return ResponseEntity.ok(body);
}

@Operation(summary = "탑 수주현황 엑셀 다운로드")
@GetMapping("/top-companies/excel")
public ResponseEntity<Resource> getTopCompaniesExcel(
        @RequestParam(required = false, defaultValue = "") String type,
        @RequestParam(required = false) String dminsttNm,
        @RequestParam(required = false) String dminsttNmDetail,
        @RequestParam(required = false) String prdctClsfcNo,
        @RequestParam(required = false) String cntctCnclsMthdNm,
        @RequestParam(required = false) String firstCntrctDate,
        @RequestParam(required = false) Integer year,
        @RequestParam(required = false) String month,
        @RequestParam(required = false) String rangeStart,
        @RequestParam(required = false) String rangeEnd,
        @RequestParam(required = false, defaultValue = "false") boolean showSavedOnly
) throws IOException {
    final String[] headerNames = new String[]{
            "분류", "업체명", "계약건명", "수요기관명", "수요기관지역명",
            "품명내용", "입찰계약방법", "입찰공고번호",
            "최초계약일자", "최초계약금액", "최종계약일자", "최종계약금액", "계약변경차수", "저장"
    };
    final String[] keys = new String[]{
            "type", "cmpNm", "cntrctNm", "dminsttNm", "dminsttNmDetail",
            "prdctClsfcNo", "cntctCnclsMthdNm", "ntceNo",
            "firstCntrctDate", "firstCntrctAmt", "cntrctDate", "thtmCntrctAmt", "cntrctCnt", "saved"
    };
    final Set<String> amountKeys = new HashSet<>(Arrays.asList("firstCntrctAmt", "thtmCntrctAmt"));

    Path tempFile = Files.createTempFile("report_top_companies_", ".xlsx");
    try {
        try (SXSSFWorkbook workbook = new SXSSFWorkbook(500);
             OutputStream out = Files.newOutputStream(tempFile)) {
            Sheet sheet = workbook.createSheet("탑수주현황");
            DataFormat dataFormat = workbook.createDataFormat();
            CellStyle numStyle = workbook.createCellStyle();
            numStyle.setDataFormat(dataFormat.getFormat("#,##0"));

            Row headerRow = sheet.createRow(0);
            for (int i = 0; i < headerNames.length; i++) {
                headerRow.createCell(i).setCellValue(headerNames[i]);
            }
            final int[] rowNumRef = {1};
            topCompaniesReportService.streamForExcel(
                    type, dminsttNm, dminsttNmDetail, prdctClsfcNo, cntctCnclsMthdNm,
                    firstCntrctDate, year, month, rangeStart, rangeEnd, showSavedOnly,
                    resultContext -> {
                        Map<String, Object> row = resultContext.getResultObject();
                        Row excelRow = sheet.createRow(rowNumRef[0]++);
                        for (int colNum = 0; colNum < keys.length; colNum++) {
                            Object value = row != null ? row.getOrDefault(keys[colNum], "") : "";
                            Cell cell = excelRow.createCell(colNum);
                            if (amountKeys.contains(keys[colNum]) && value != null && !value.toString().isEmpty()) {
                                try {
                                    cell.setCellValue(Long.parseLong(value.toString()));
                                    cell.setCellStyle(numStyle);
                                } catch (NumberFormatException e) {
                                    cell.setCellValue(value.toString());
                                }
                            } else {
                                cell.setCellValue(value != null ? String.valueOf(value) : "");
                            }
                        }
                    });
            workbook.write(out);
            workbook.dispose();
        }

        long fileSize = Files.size(tempFile);
        String filename = "top_companies_" + System.currentTimeMillis() + ".xlsx";
        InputStream in = Files.newInputStream(tempFile);
        InputStream deletingStream = new FilterInputStream(in) {
            @Override public void close() throws IOException {
                try { super.close(); } finally { Files.deleteIfExists(tempFile); }
            }
        };
        return ResponseEntity.ok()
                .contentLength(fileSize)
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"" + URLEncoder.encode(filename, StandardCharsets.UTF_8) + "\""
                        + "; filename*=UTF-8''" + URLEncoder.encode(filename, StandardCharsets.UTF_8))
                .body(new InputStreamResource(deletingStream));
    } catch (IOException e) {
        Files.deleteIfExists(tempFile);
        throw e;
    } catch (Exception e) {
        Files.deleteIfExists(tempFile);
        throw new IOException(e);
    }
}

@Operation(summary = "쇼핑몰 saved 업데이트")
@PatchMapping("/shopping-mall/saved")
public ResponseEntity<Map<String, Object>> updateShoppingMallSaved(@RequestBody Map<String, Object> body) {
    if (body == null) {
        Map<String, Object> err = new HashMap<>();
        err.put("success", false);
        err.put("message", "요청 본문이 없습니다.");
        return ResponseEntity.badRequest().body(err);
    }
    String deliveryContractNo = body.get("deliveryContractNo") != null
            ? body.get("deliveryContractNo").toString() : null;
    Object changeSeqObj = body.get("deliveryContractChangeSeq");
    Object itemSeqObj  = body.get("deliveryItemSeq");
    String saved = body.get("saved") != null
            ? ("Y".equalsIgnoreCase(body.get("saved").toString()) ? "Y" : "N") : "N";

    if (deliveryContractNo == null || changeSeqObj == null || itemSeqObj == null) {
        Map<String, Object> err = new HashMap<>();
        err.put("success", false);
        err.put("message", "deliveryContractNo, deliveryContractChangeSeq, deliveryItemSeq 필요");
        return ResponseEntity.badRequest().body(err);
    }
    int updated = topCompaniesReportService.updateShoppingMallSaved(
            deliveryContractNo,
            Long.parseLong(changeSeqObj.toString()),
            Long.parseLong(itemSeqObj.toString()),
            saved);
    Map<String, Object> res = new HashMap<>();
    res.put("success", updated > 0);
    res.put("updated", updated);
    return ResponseEntity.ok(res);
}
```

---

## 8. Step 7 — TopContractsReportView.vue 수정

기존 파일의 `<script setup>` 전체를 아래로 교체한다.
변경 포인트:
1. type 옵션에 `쇼핑몰` 추가
2. `handleSearch()` API 연동 구현
3. `handleDownloadExcel()` 구현
4. `toggleSave(item)` 구현 — type 별 분기
5. 페이지 이동 시 자동 재조회

### 8-1. `<template>` 의 `<select v-model="filters.type">` 에 쇼핑몰 추가

```html
<select v-model="filters.type" class="type-select">
  <option value="">전체</option>
  <option value="물품">물품</option>
  <option value="용역">용역</option>
  <option value="공사">공사</option>
  <option value="쇼핑몰">쇼핑몰</option>
</select>
```

### 8-2. `<template>` 의 저장 체크박스 `:checked` 수정

```html
<input type="checkbox" :checked="item.saved === 'Y'" @change="toggleSave(item)" />
```

### 8-3. WIP 배너 제거 또는 숨김

구현 완료 후 WIP 배너(`<div class="wip-banner">`) 블록 전체를 삭제한다.

### 8-4. `<script setup>` 교체

```javascript
import { ref, reactive, computed, watch } from 'vue'
import axios from 'axios'
import LegacySidebarLayout from './components/LegacySidebarLayout.vue'

const API_BASE = '/api/report/top-companies'
const PAGE_SIZE = 100

const isLoading      = ref(false)
const isLoadingExcel = ref(false)
const items          = ref([])
const recordsFiltered = ref(0)
const currentPage    = ref(1)

const currentYear = new Date().getFullYear()
const years = Array.from({ length: currentYear - 2014 }, (_, i) => currentYear - i)

const filters = reactive({
  type: '',
  dminsttNm: '',
  dminsttNmDetail: '',
  prdctClsfcNo: '',
  cntctCnclsMthdNm: '',
  firstCntrctDate: '',
  dateType: 'year',
  year: String(currentYear),
  month: '',
  rangeStart: '',
  rangeEnd: '',
  showSavedOnly: false,
})

// 검색 실행 시점의 조건을 스냅샷으로 보관 (페이지 이동 시 동일 조건 재사용)
let appliedFilters = { ...filters }

const totalPages = computed(() => Math.ceil(recordsFiltered.value / PAGE_SIZE) || 1)
const startDisplay = computed(() => recordsFiltered.value === 0 ? 0 : (currentPage.value - 1) * PAGE_SIZE + 1)
const endDisplay   = computed(() => Math.min(currentPage.value * PAGE_SIZE, recordsFiltered.value))
const pageNumbers  = computed(() => {
  const total = totalPages.value
  const cur   = currentPage.value
  const delta = 2
  const pages = []
  for (let i = Math.max(1, cur - delta); i <= Math.min(total, cur + delta); i++) pages.push(i)
  return pages
})

function buildParams(page) {
  const f = appliedFilters
  const start = (page - 1) * PAGE_SIZE
  const p = {
    type:             f.type || '',
    dminsttNm:        f.dminsttNm        || undefined,
    dminsttNmDetail:  f.dminsttNmDetail  || undefined,
    prdctClsfcNo:     f.prdctClsfcNo     || undefined,
    cntctCnclsMthdNm: f.cntctCnclsMthdNm || undefined,
    firstCntrctDate:  f.firstCntrctDate  || undefined,
    showSavedOnly:    f.showSavedOnly,
    start,
    length: PAGE_SIZE,
  }
  if (f.dateType === 'year'  && f.year)        { p.year = f.year }
  if (f.dateType === 'month' && f.month)       { p.month = f.month }
  if (f.dateType === 'range' && f.rangeStart && f.rangeEnd) {
    p.rangeStart = f.rangeStart
    p.rangeEnd   = f.rangeEnd
  }
  return p
}

async function fetchPage(page) {
  isLoading.value = true
  try {
    const res = await axios.get(API_BASE, { params: buildParams(page) })
    items.value          = res.data.data || []
    recordsFiltered.value = res.data.recordsFiltered || 0
    currentPage.value    = page
  } catch (e) {
    console.error('탑 수주현황 조회 오류', e)
    items.value           = []
    recordsFiltered.value = 0
  } finally {
    isLoading.value = false
  }
}

function handleSearch() {
  appliedFilters = { ...filters }
  fetchPage(1)
}

async function handleDownloadExcel() {
  isLoadingExcel.value = true
  try {
    const f = appliedFilters
    const p = {
      type:             f.type || '',
      dminsttNm:        f.dminsttNm        || undefined,
      dminsttNmDetail:  f.dminsttNmDetail  || undefined,
      prdctClsfcNo:     f.prdctClsfcNo     || undefined,
      cntctCnclsMthdNm: f.cntctCnclsMthdNm || undefined,
      firstCntrctDate:  f.firstCntrctDate  || undefined,
      showSavedOnly:    f.showSavedOnly,
    }
    if (f.dateType === 'year'  && f.year)        { p.year = f.year }
    if (f.dateType === 'month' && f.month)       { p.month = f.month }
    if (f.dateType === 'range' && f.rangeStart && f.rangeEnd) {
      p.rangeStart = f.rangeStart
      p.rangeEnd   = f.rangeEnd
    }
    const res = await axios.get(API_BASE + '/excel', { params: p, responseType: 'blob' })
    const url  = window.URL.createObjectURL(new Blob([res.data]))
    const link = document.createElement('a')
    link.href = url
    const cd = res.headers['content-disposition'] || ''
    const match = cd.match(/filename\*=UTF-8''(.+)/)
    link.download = match ? decodeURIComponent(match[1]) : 'top_companies.xlsx'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)
  } catch (e) {
    console.error('엑셀 다운로드 오류', e)
  } finally {
    isLoadingExcel.value = false
  }
}

async function toggleSave(item) {
  const nextSaved = item.saved === 'Y' ? 'N' : 'Y'
  try {
    if (item.type === '물품') {
      await axios.patch('/api/report/procurements/saved', {
        grouped:    false,
        contractNo: item.pk1,
        itemSeq:    item.pk2,
        saved:      nextSaved,
      })
    } else if (item.type === '공사') {
      await axios.patch('/api/report/constructions/saved', {
        grouped:    false,
        contractNo: item.pk1,
        saved:      nextSaved,
      })
    } else if (item.type === '용역') {
      await axios.patch('/api/report/services/saved', {
        grouped:                      false,
        contractDeliveryIntegratedNo: item.pk1,
        vendorBizRegNo:               item.pk2,
        saved:                        nextSaved,
      })
    } else if (item.type === '쇼핑몰') {
      await axios.patch('/api/report/shopping-mall/saved', {
        deliveryContractNo:        item.pk1,
        deliveryContractChangeSeq: Number(item.pk2),
        deliveryItemSeq:           Number(item.pk3),
        saved:                     nextSaved,
      })
    }
    item.saved = nextSaved
  } catch (e) {
    console.error('저장 상태 변경 오류', e)
  }
}

function goPage(page) {
  if (page < 1 || page > totalPages.value) return
  fetchPage(page)
}

function formatNumber(val) {
  if (val === null || val === undefined || val === '') return ''
  const num = Number(val)
  return isNaN(num) ? val : num.toLocaleString('ko-KR')
}
```

---

## 9. 검증 포인트

구현 완료 후 아래 항목을 순서대로 확인한다.

1. **DB**: `SHOW COLUMNS FROM shopping_mall_flat LIKE 'saved';` 로 컬럼 존재 확인
2. **물품 단독 조회**: `type=물품`, year=현재년도 → 데이터 조회 및 건수 확인
3. **전체 조회**: `type=` (빈값) → 4개 소스 UNION ALL 결과 확인
4. **저장 토글**: 각 분류(물품/공사/용역/쇼핑몰)에서 체크박스 클릭 → saved 컬럼 반영 확인
5. **저장만 보기**: `showSavedOnly=true` 조회 시 saved='Y' 행만 조회되는지 확인
6. **엑셀 다운로드**: 조건 지정 후 다운로드 → 파일 열림 및 데이터 정합성 확인
7. **페이지네이션**: 2페이지 이동 후 조건 유지(appliedFilters 스냅샷) 확인

---

## 10. 주의 사항

- `shopping_mall_flat` 의 `saved` 컬럼은 **이 작업에서 처음 추가**하므로 ALTER TABLE 을 반드시 먼저 실행한다.
- `selectForExport` 는 MyBatis `ResultHandler` 를 사용하는 스트리밍 방식이다. 메서드 반환 타입이 `void` 임에 주의한다.
- UNION ALL COUNT 쿼리에서 각 소스를 서브쿼리로 감싸고 컬럼 1개만 SELECT 해야 MySQL 이 최적화할 수 있다.
- `TopContractsReportView.vue` 에서 `toggleSave` 시 `item.pk1 / pk2 / pk3` 를 사용하므로 백엔드 응답에 반드시 `pk1`, `pk2`, `pk3` 필드가 포함되어야 한다.
- 쇼핑몰의 `firstCntrctDate` 검색 필터(firstCntrctDate 파라미터)는 `first_ref_date` 를 검색하지 않고 무시한다 (납품 데이터 특성상 최초계약일 개념이 없음). 필요 시 구현 확장 가능.
