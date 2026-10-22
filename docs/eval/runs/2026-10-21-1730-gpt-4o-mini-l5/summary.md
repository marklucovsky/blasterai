# Eval run 2026-10-21-1730-gpt-4o-mini-l5

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 3
- Commit `660c8d0+dirty`, prompts `e41fa53658`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.1338, judge $2.0333

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 70 | 350 | 0 | 344/350 | grammar 4.97, intent 4.96, naturalness 4.95, stage_fit 5.00, subject 5.00 | 11/350 | 0.75s / 1.06s | $0.00017 |
| escalation | 13 | 65 | 0 | 65/65 | audible 4.83, grammar 5.00, same_want 4.94 | 2/65 | 0.82s / 1.07s | $0.00114 |

## Worth a look (14)

- **sentence/i_bus_school** #0: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #1: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #2: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #3: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/i_bus_school** #4: I want the bus to school.  
  matches /want the bus/; grammar=3; naturalness=3
- **sentence/he_raptor** #0: He is a raptor.  
  intent=3
- **sentence/he_raptor** #1: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #3: He is a raptor.  
  intent=3; naturalness=3
- **sentence/history_more** #1: Please, I want more.  
  intent=3
- **sentence/history_more** #3: Please, I want more.  
  intent=3
- **sentence/history_more** #4: Please, I want more.  
  intent=3
- **sentence/refine_shorter** #2: I want to go to the park and play on the swing.  
  12 words, over 10
- **escalation/she_pool** #0: She is at the pool. → She IS at the pool! → She IS at the pool right now! → She IS at the pool right now! Please, please!  
  audible=2; same_want=3
- **escalation/she_pool** #3: She is at the pool. → She IS at the pool! → She IS at the pool right now! → She IS at the pool right now! Please, please!  
  audible=2; same_want=3
