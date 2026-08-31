# Timing metrics

Entitlements emits timing records through its logger for deployment analysis. Each record begins with `METRIC` followed by a JSON object:

```text
METRIC {"metric":"entitlements.operation.duration_seconds","value":11.204,"phase":"apply","status":"success","run_id":"fc85bb97-48f4-4f88-bb90-63e52cb01e9f","span":"leaf","concurrent":false,"provider":"aad","target":"apps/azure_aad","count":1}
```

The fields are:

| Field | Description |
| --- | --- |
| `metric` | Metric name. Currently always `entitlements.operation.duration_seconds`. |
| `value` | Elapsed monotonic time in seconds. |
| `phase` | Operation being measured. |
| `status` | `success` or `error`. |
| `run_id` | Identifier shared by records from one process. Set `ENTITLEMENTS_RUN_ID` to correlate with an external deployment identifier. |
| `span` | `parent` for top-level wall-clock spans and `leaf` for individual operations. |
| `concurrent` | Whether the operation may overlap other records from the same phase. |
| `provider` | Backend type or audit provider identifier, when applicable. |
| `target` | Configured group or data-source name, when applicable. |
| `count` | Number of operations represented by the record, when applicable. |

`calculate_total` and `execute_total` are parent spans and report wall-clock time. Leaf spans identify initialization, reads, calculations, writes, and audit operations. Prefetch and validation run concurrently, so their durations describe provider service time and must not be summed to calculate wall-clock duration.

Raw action identifiers are not included because an action can identify an individual user and would create an unbounded metric field.
