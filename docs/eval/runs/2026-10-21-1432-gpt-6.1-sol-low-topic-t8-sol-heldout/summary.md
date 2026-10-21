# Eval run 2026-10-21-1432-gpt-6.1-sol-low-topic-t8-sol-heldout

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `b2394f7c5d`, rubrics `19aa1baaa0`
- Samples per case: 3
- Cost: subject $0.3163, judge $1.0406

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 12 | 36 | 0 | 24/36 | child_fit 4.75, coverage 4.78, precision 4.53, ranking 4.69, related_core 4.78 | 0/36 | 10.78s / 13.40s | $0.00879 |

## Worth a look (12)

- **topic_words/ho_chuck_e_cheese** #0: (32 tiles)  
  missing 'token / tokens / card'; missing 'game / games'
- **topic_words/ho_chuck_e_cheese** #1: (32 tiles)  
  missing 'token / tokens / card'; missing 'game / games'
- **topic_words/ho_chuck_e_cheese** #2: (32 tiles)  
  missing 'token / tokens / card'; missing 'game / games'
- **topic_words/ho_disney_world** #2: (32 tiles)  
  phrase tile(s): mickey_ice_cream_bar
- **topic_words/ho_easter** #0: (30 tiles)  
  missing 'egg / eggs'
- **topic_words/ho_easter** #1: (31 tiles)  
  missing 'egg / eggs'
- **topic_words/ho_easter** #2: (30 tiles)  
  missing 'candy'
- **topic_words/ho_hungry_caterpillar** #0: (32 tiles)  
  missing 'cocoon / egg' (in the overflow)
- **topic_words/ho_hungry_caterpillar** #2: (32 tiles)  
  missing 'cocoon / egg' (in the overflow)
- **topic_words/ho_taco_night** #0: (32 tiles)  
  missing 'put / add'
- **topic_words/ho_taco_night** #1: (32 tiles)  
  missing 'meat / beef / chicken'
- **topic_words/ho_taco_night** #2: (32 tiles)  
  missing 'meat / beef / chicken'
