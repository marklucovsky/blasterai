# Eval run 2026-10-20-1049-gpt-4o-mini-baseline-sentence

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 3
- Commit `cabcc1c+dirty`, prompts `585b4e7282`, rubrics `605e7a9d0a`
- Samples per case: 5
- Cost: subject $0.0431, judge $1.4767

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 68 | 340 | 0 | 340/340 | grammar 5.00, intent 4.93, naturalness 4.94, stage_fit 5.00, subject 5.00 | 15/340 | 0.82s / 1.14s | $0.00013 |

## Worth a look (15)

- **sentence/tv_stop** #0: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #1: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #2: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #3: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #4: I want to stop the TV.  
  naturalness=3
- **sentence/he_raptor** #0: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #1: He is a raptor.  
  intent=3; naturalness=3
- **sentence/he_raptor** #2: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #3: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #4: He is a raptor.  
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
