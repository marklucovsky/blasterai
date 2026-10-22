# Eval run 2026-10-21-1639-gpt-4o-mini-baseline-current-rejudge

- Subject: `gpt-4o-mini`
- Judge: none
- Commit `660c8d0+dirty`, prompts `9382d07e6c`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.1094, judge $2.1949

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 70 | 350 | 0 | 347/350 | grammar 5.00, intent 4.93, naturalness 4.92, stage_fit 5.00, subject 5.00 | 18/350 | 0.77s / 1.06s | $0.00013 |
| escalation | 13 | 65 | 0 | 65/65 | audible 4.86, grammar 5.00, same_want 5.00 | 0/65 | 0.85s / 1.10s | $0.00099 |

## Worth a look (21)

- **sentence/tv_stop** #0: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #1: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #3: I want to stop the TV.  
  naturalness=3
- **sentence/i_park_bus** #0: I go to the park in the bus.  
  naturalness=3
- **sentence/i_park_bus** #1: I go to the park in the bus.  
  naturalness=3
- **sentence/i_park_bus** #2: I want the bus to the park.  
  naturalness=3
- **sentence/i_park_bus** #3: I want the bus to the park.  
  naturalness=3
- **sentence/i_park_bus** #4: I want the bus to the park.  
  naturalness=3
- **sentence/he_raptor** #1: He is a raptor.  
  intent=3
- **sentence/he_raptor** #2: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #3: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #4: He is a raptor.  
  intent=3; naturalness=3
- **sentence/see_cat** #3: I want to see a cat.  
  intent=2
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
- **sentence/refine_shorter** #1: I want to go to the park and play on the swing.  
  12 words, over 10
- **sentence/refine_shorter** #2: I want to go to the park and play on the swing.  
  12 words, over 10
- **sentence/refine_shorter** #4: I want to go to the park and play on the swing.  
  12 words, over 10
