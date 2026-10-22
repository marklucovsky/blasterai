# Eval run 2026-10-21-1907-gpt-4o-mini-l6-ship

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 3
- Commit `007f674+dirty`, prompts `cd9854217d`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.1452, judge $1.9981

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 71 | 355 | 0 | 351/355 | grammar 4.98, intent 4.94, naturalness 4.94, stage_fit 5.00, subject 5.00 | 12/355 | 0.81s / 1.17s | $0.00018 |
| escalation | 13 | 65 | 0 | 65/65 | audible 4.92, grammar 5.00, same_want 5.00 | 0/65 | 0.95s / 1.91s | $0.00125 |

## Worth a look (13)

- **sentence/i_bus_school** #1: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #2: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #3: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/he_raptor** #0: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #1: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #2: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #4: He is a raptor.  
  intent=3; naturalness=3
- **sentence/history_more** #0: Please, I want more.  
  intent=3
- **sentence/history_more** #1: Please, I want more.  
  intent=3
- **sentence/history_more** #2: Please, I want more.  
  intent=3
- **sentence/history_more** #3: Please, I want more.  
  intent=3
- **sentence/history_more** #4: Please, I want more.  
  intent=3
- **sentence/refine_shorter** #4: I want to go to the park and play on the swing.  
  12 words, over 10
