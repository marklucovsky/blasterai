# Eval run 2026-10-21-1425-gpt-6.1-sol-low-topic-t8-sol

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `b2394f7c5d`, rubrics `19aa1baaa0`
- Samples per case: 3
- Cost: subject $0.8278, judge $2.7928

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 89/102 | child_fit 4.72, coverage 4.89, precision 4.45, ranking 4.59, related_core 4.86 | 5/99 | 9.85s / 15.20s | $0.00812 |

## Worth a look (18)

- **topic_words/swimming** #0: (32 tiles)  
  missing 'wet' (in the overflow)
- **topic_words/swimming** #1: (32 tiles)  
  missing 'wet' (in the overflow)
- **topic_words/swimming** #2: (32 tiles)  
  missing 'wet' (in the overflow)
- **topic_words/holidays** #0: (32 tiles)  
  coverage=3; ranking=3
- **topic_words/holidays** #1: (32 tiles)  
  coverage=3
- **topic_words/holidays** #2: (32 tiles)  
  coverage=3
- **topic_words/favorite_show** #0: (32 tiles)  
  precision=3
- **topic_words/favorite_show** #2: (32 tiles)  
  precision=3
- **topic_words/video_game** #0: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/video_game** #1: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/video_game** #2: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/basketball** #0: (32 tiles)  
  missing 'throw'
- **topic_words/basketball** #1: (30 tiles)  
  missing 'throw'
- **topic_words/basketball** #2: (32 tiles)  
  missing 'throw'
- **topic_words/art_class** #1: (32 tiles)  
  missing 'messy' (in the overflow)
- **topic_words/leaf_playground** #0: (31 tiles)  
  missing 'turn'
- **topic_words/leaf_playground** #1: (31 tiles)  
  missing 'turn'
- **topic_words/leaf_playground** #2: (32 tiles)  
  missing 'turn'
