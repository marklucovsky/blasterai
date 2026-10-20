# Eval run 2026-10-19-2023-gpt-4o-mini-p2-rejudge

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `cabcc1c+dirty`, prompts `585b4e7282`, rubrics `129e37cc81`
- Samples per case: 3
- Cost: subject $0.0220, judge $0.0956

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| escalation | 10 | 30 | 0 | 27/30 | audible 4.40, grammar 5.00, same_want 5.00 | 5/30 | 0.87s / 1.17s | $0.00073 |

## Worth a look (5)

- **escalation/watch_tv** #0: I want to watch TV. → I really want to watch TV right now, please! → I really NEED to watch TV right now, please! → I really, really NEED to watch TV right now! Please, please! I can't wait! → I reall  
  rung 4: insisting phrase stacked (can'?t wait); audible=3
- **escalation/watch_tv** #1: I want to watch TV. → I want to watch TV right now! → I really NEED to watch TV right now, please! → I really, really NEED to watch TV right now! Please, please! I can't wait! → I really, really NEED   
  rung 4: insisting phrase stacked (can'?t wait); audible=3
- **escalation/watch_tv** #2: I want to watch TV. → I want to watch TV right now! → I really need to watch TV right now, please! → I really, really NEED to watch TV right now! Please, please! I can't wait! → I really, really NEED   
  rung 4: insisting phrase stacked (please,\s*please, can'?t wait); audible=3
- **escalation/she_pool** #0: She is at the pool. → She is at the pool! → She IS at the pool! → Listen to me! She IS at the pool, right now!  
  audible=3
- **escalation/she_pool** #1: She is at the pool. → She is at the pool! → She IS at the pool! → Listen to me! She IS at the pool, right now!  
  audible=3
