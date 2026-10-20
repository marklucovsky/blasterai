# Eval run 2026-10-19-2024-gpt-4o-mini-p3-refusal-rejudge

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `cabcc1c+dirty`, prompts `585b4e7282`, rubrics `129e37cc81`
- Samples per case: 5
- Cost: subject $0.0079, judge $0.0390

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| escalation | 2 | 10 | 0 | 10/10 | audible 4.50, grammar 5.00, same_want 4.90 | 2/10 | 0.92s / 1.22s | $0.00079 |

## Worth a look (2)

- **escalation/no_home** #1: No! I don't want to go home. → No! I really don't want to go home! → No! I really don't want to go home! I really don't want to go home right now! → No! I really don't want to go home! I really don't   
  audible=3
- **escalation/no_bed** #0: No! I don't want to go to bed. → No! I really don't want to go to bed! → No! I really don't want to go to bed! I really, really don't want to go to bed! → No! I really don't want to go to bed! I reall  
  audible=2
