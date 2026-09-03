/* =========================================================
   Анализ рынка жилой недвижимости Санкт-Петербурга
   и городов Ленинградской области
   PostgreSQL

   Данные: архив объявлений Яндекс Недвижимости
   Схема: real_estate
   Период анализа: 2015–2018 годы
   ========================================================= */


/* =========================================================
   ЗАДАЧА 1. ВРЕМЯ АКТИВНОСТИ ОБЪЯВЛЕНИЙ

   Цель:
   - разделить объявления по длительности публикации;
   - сравнить Санкт-Петербург и города Ленинградской области;
   - изучить характеристики объектов в каждой категории.
   ========================================================= */

WITH limits AS (
    -- Границы выбросов по шаблону проекта.
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    -- Оставляем только объявления без выбросов.
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (
                ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
                AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
            )
            OR ceiling_height IS NULL
        )
),
base_data AS (
    SELECT
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.floor,
        f.floors_total,
        c.city,
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS region,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN a.days_exposition > 180 THEN '181+ days'
        END AS activity_category
    FROM real_estate.advertisement AS a
    INNER JOIN filtered_id AS fi
        ON a.id = fi.id
    INNER JOIN real_estate.flats AS f
        ON a.id = f.id
    INNER JOIN real_estate.city AS c
        ON f.city_id = c.city_id
    INNER JOIN real_estate.type AS t
        ON f.type_id = t.type_id
    WHERE
        a.first_day_exposition >= DATE '2015-01-01'
        AND a.first_day_exposition < DATE '2019-01-01'
        AND t.type = 'город'
)
SELECT
    region,
    activity_category,
    COUNT(*) AS ads_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY region),
        2
    ) AS share_in_region_pct,
    ROUND(AVG(a.last_price::numeric / NULLIF(a.total_area, 0)), 2) AS avg_price_per_sq_m,
    ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
    ROUND(AVG(rooms)::numeric, 2) AS avg_rooms,
    ROUND(AVG(balcony)::numeric, 2) AS avg_balcony,
    ROUND(AVG(ceiling_height)::numeric, 2) AS avg_ceiling_height,
    ROUND(AVG(floor)::numeric, 2) AS avg_floor,
    ROUND(AVG(floors_total)::numeric, 2) AS avg_floors_total,
    ROUND(AVG(days_exposition)::numeric, 2) AS avg_days_exposition
FROM base_data AS a
GROUP BY
    region,
    activity_category
ORDER BY
    region,
    CASE activity_category
        WHEN '1-30 days' THEN 1
        WHEN '31-90 days' THEN 2
        WHEN '91-180 days' THEN 3
        WHEN '181+ days' THEN 4
        WHEN 'non category' THEN 5
    END;


/* =========================================================
   ЗАДАЧА 2. СЕЗОННОСТЬ ОБЪЯВЛЕНИЙ

   Цель:
   - определить месяцы максимальной активности продавцов;
   - определить месяцы повышенного снятия объявлений;
   - сравнить цену за м² и площадь объектов по месяцам.
   ========================================================= */

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (
                ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
                AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
            )
            OR ceiling_height IS NULL
        )
),
base_data AS (
    SELECT
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        CASE
            WHEN a.days_exposition IS NOT NULL
            THEN (a.first_day_exposition + a.days_exposition::int)::date
        END AS removed_day,
        a.last_price,
        f.total_area
    FROM real_estate.advertisement AS a
    INNER JOIN filtered_id AS fi
        ON a.id = fi.id
    INNER JOIN real_estate.flats AS f
        ON a.id = f.id
    INNER JOIN real_estate.type AS t
        ON f.type_id = t.type_id
    WHERE
        a.first_day_exposition >= DATE '2015-01-01'
        AND a.first_day_exposition < DATE '2019-01-01'
        AND t.type = 'город'
),
publication_stats AS (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition)::int AS month_num,
        COUNT(*) AS publication_count,
        ROUND(AVG(last_price::numeric / NULLIF(total_area, 0)), 2) AS avg_price_per_sq_m_pub,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area_pub
    FROM base_data
    GROUP BY EXTRACT(MONTH FROM first_day_exposition)
),
removal_stats AS (
    SELECT
        EXTRACT(MONTH FROM removed_day)::int AS month_num,
        COUNT(*) AS removal_count,
        ROUND(AVG(last_price::numeric / NULLIF(total_area, 0)), 2) AS avg_price_per_sq_m_rem,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area_rem
    FROM base_data
    WHERE days_exposition IS NOT NULL
    GROUP BY EXTRACT(MONTH FROM removed_day)
)
SELECT
    COALESCE(p.month_num, r.month_num) AS month_num,
    CASE COALESCE(p.month_num, r.month_num)
        WHEN 1 THEN 'Январь'
        WHEN 2 THEN 'Февраль'
        WHEN 3 THEN 'Март'
        WHEN 4 THEN 'Апрель'
        WHEN 5 THEN 'Май'
        WHEN 6 THEN 'Июнь'
        WHEN 7 THEN 'Июль'
        WHEN 8 THEN 'Август'
        WHEN 9 THEN 'Сентябрь'
        WHEN 10 THEN 'Октябрь'
        WHEN 11 THEN 'Ноябрь'
        WHEN 12 THEN 'Декабрь'
    END AS month_name,
    COALESCE(p.publication_count, 0) AS publication_count,
    COALESCE(r.removal_count, 0) AS removal_count,
    p.avg_price_per_sq_m_pub,
    r.avg_price_per_sq_m_rem,
    p.avg_total_area_pub,
    r.avg_total_area_rem
FROM publication_stats AS p
FULL OUTER JOIN removal_stats AS r
    ON p.month_num = r.month_num
ORDER BY month_num;
