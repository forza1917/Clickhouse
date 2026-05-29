#!/usr/bin/env bash
set -euo pipefail

QUERY_FILE="query_nosorted.sql"
LOG_FILE="benchmark_nosorted.log"

cat > "$QUERY_FILE" <<'EOF'
SELECT
  toStartOfDay(toDateTime(dt)) AS dt_3017d9,
  brand AS brand_8c4d3a,
  sum(running_revenue) AS SUM_running_revenue_1f5510
FROM (
  SELECT
    dt,
    category_code,
    brand,
    revenue,
    sum(revenue) OVER (
      PARTITION BY category_code, brand
      ORDER BY dt
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_revenue
  FROM (
    SELECT
      toDate(event_time) AS dt,
      category_code,
      brand,
      sum(price) AS revenue
    FROM ecommerce_events_nosort
    WHERE
      category_code <> '' AND brand <> '' AND event_type = 'purchase'
    GROUP BY
      dt,
      category_code,
      brand
  )
  ORDER BY
    category_code,
    brand,
    dt
) AS virtual_table
GROUP BY
  dt_3017d9,
  brand_8c4d3a
ORDER BY
  SUM_running_revenue_1f5510 DESC
LIMIT 50000
EOF

: > "$LOG_FILE"

echo "concurrency,qps,p95_sec,p99_sec"
for c in $(seq 1 16); do
  output=$(clickhouse-benchmark \
    --query "$(cat "$QUERY_FILE")" \
    --concurrency "$c" \
    --iterations 10 2>&1)

  echo "=== concurrency=$c ===" >> "$LOG_FILE"
  echo "$output" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  qps=$(echo "$output" | sed -n 's/.*QPS: \([0-9.]*\).*/\1/p' | head -n1)
  p95=$(echo "$output" | awk '/^95%/ {print $2}' | head -n1)
  p99=$(echo "$output" | awk '/^99%/ {print $2}' | head -n1)

  echo "$c,$qps,$p95,$p99"
done | column -s, -t