# Eval run 2026-10-20-1232-gpt-4o-mini-baseline-sentence-2

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 3
- Commit `2b9d352+dirty`, prompts `7eebdcde7b`, rubrics `605e7a9d0a`
- Samples per case: 5
- Cost: subject $0.0451, judge $1.5470

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 70 | 350 | 0 | 349/350 | grammar 5.00, intent 4.90, naturalness 4.95, stage_fit 5.00, subject 5.00 | 17/350 | 0.80s / 1.07s | $0.00013 |

## Worth a look (18)

- **sentence/tv_stop** #0: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #2: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #4: I want to stop the TV.  
  naturalness=3
- **sentence/grandma_book** #4: Grandma, I have a book.  
  intent=3
- **sentence/he_raptor** #0: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #1: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #2: He is a raptor.  
  intent=2; naturalness=3
- **sentence/he_raptor** #3: He is a raptor.  
  intent=2
- **sentence/he_raptor** #4: He is a raptor.  
  intent=2; naturalness=3
- **sentence/see_cat** #0: I want to see the cat.  
  intent=2
- **sentence/see_cat** #1: I want to see a cat.  
  intent=2
- **sentence/see_cat** #2: I want to see the cat.  
  intent=3
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
