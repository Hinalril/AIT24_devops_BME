-- Использовать схему bookings по умолчанию
SET search_path = bookings, public;


-- 1. WHERE и ORDER BY:
-- последние 20 завершённых рейсов
SELECT
    flight_no,
    departure_airport,
    arrival_airport,
    scheduled_departure,
    status
FROM flights
WHERE status = 'Arrived'
ORDER BY scheduled_departure DESC
LIMIT 20;


-- 2. GROUP BY и ORDER BY:
-- количество рейсов по каждому статусу
SELECT
    status,
    COUNT(*) AS flight_count
FROM flights
GROUP BY status
ORDER BY flight_count DESC;


-- 3. JOIN, WHERE и ORDER BY:
-- рейсы из московских аэропортов
SELECT
    f.flight_no,
    dep.airport_name AS departure_airport,
    dep.city AS departure_city,
    arr.airport_name AS arrival_airport,
    arr.city AS arrival_city,
    f.scheduled_departure,
    f.status
FROM flights AS f
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE dep.airport_code IN ('SVO', 'DME', 'VKO')
ORDER BY f.scheduled_departure DESC
LIMIT 20;


-- 4. JOIN, WHERE, GROUP BY и ORDER BY:
-- десять завершённых рейсов с наибольшей выручкой
SELECT
    f.flight_id,
    f.flight_no,
    dep.city AS departure_city,
    arr.city AS arrival_city,
    f.scheduled_departure,
    COUNT(tf.ticket_no) AS tickets_sold,
    ROUND(SUM(tf.amount), 2) AS revenue
FROM flights AS f
JOIN ticket_flights AS tf
    ON tf.flight_id = f.flight_id
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE f.status = 'Arrived'
GROUP BY
    f.flight_id,
    f.flight_no,
    dep.city,
    arr.city,
    f.scheduled_departure
ORDER BY revenue DESC
LIMIT 10;


-- 5. План выполнения сложного запроса
-- EXPLAIN выводит план выполнения запроса.
-- ANALYZE фактически выполняет запрос и показывает реальное время,
-- количество обработанных строк и число повторений каждого узла.
-- BUFFERS показывает обращения к страницам данных в памяти и на диске.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    f.flight_id,
    f.flight_no,
    dep.city AS departure_city,
    arr.city AS arrival_city,
    f.scheduled_departure,
    COUNT(tf.ticket_no) AS tickets_sold,
    ROUND(SUM(tf.amount), 2) AS revenue
FROM flights AS f
JOIN ticket_flights AS tf
    ON tf.flight_id = f.flight_id
JOIN airports AS dep
    ON dep.airport_code = f.departure_airport
JOIN airports AS arr
    ON arr.airport_code = f.arrival_airport
WHERE f.status = 'Arrived'
GROUP BY
    f.flight_id,
    f.flight_no,
    dep.city,
    arr.city,
    f.scheduled_departure
ORDER BY revenue DESC
LIMIT 10;