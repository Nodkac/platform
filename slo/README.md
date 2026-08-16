# SLO — demo service

## SLIs (what we measure)

- **Availability:** proportion of HTTP requests that do not return 5xx
- **Latency:** proportion of requests served in under 200ms

Both are computed from `http_requests_total` and
`http_request_duration_seconds_bucket`, exported by the service and scraped by
Prometheus every 15s.

## SLO (the target)

**99.5% availability over a rolling 30 days.**

Not 100% — chasing 100% means never shipping. The SLO is a deliberate statement
of how much failure is acceptable.

## Error budget

100% − 99.5% = 0.5% of requests may fail.

Over 30 days: `0.005 × 30 × 24 × 60` = **216 minutes = 3 hours 39 minutes** of
full-outage-equivalent failure per month.

This turns reliability from an argument into arithmetic. Budget remaining →ship
features. Budget spent → stop shipping and fix reliability.

## Burn rate

Burn rate = how fast the budget is being consumed relative to a steady pace.

| Burn rate | Budget exhausted in |
|---|---|
| 1 | exactly 30 days |
| 6 | ~5 days |
| 14.4 | ~2 days |

## Alerting policy

| Alert | Condition | Response |
|---|---|---|
| **Fast burn** | 14.4× over **1h** AND **5m** | Page — something is badly broken now |
| **Slow burn** | 6× over **6h** AND **30m** | Ticket — steady drip, will hurt by month end |

Thresholds: 14.4 × 0.005 = **7.2%** error ratio; 6 × 0.005 = **3%**.

### Why two windows on each alert

The **long window** is the real signal — it confirms the budget is genuinely
burning rather than reacting to one bad second.

The **short window** is what makes the alert *resolve* quickly. Once the problem
is fixed, the 5m rate drops within minutes, the `AND` stops being satisfied, and
the page clears.

Without the short window, an outage fixed at 14:20 keeps paging until 15:20 —
and people learn to ignore alerts that stay red after recovery. Alert fatigue is
a reliability problem in itself.

## Validation

These alerts are not theoretical. Phase 3 injects errors into the service until
`DemoFastBurn` fires, then documents the incident in
[docs/postmortem.md](../docs/postmortem.md) with real timestamps and budget math.
