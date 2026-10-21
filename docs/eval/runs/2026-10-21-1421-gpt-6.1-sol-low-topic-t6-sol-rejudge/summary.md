# Eval run 2026-10-21-1421-gpt-6.1-sol-low-topic-t6-sol-rejudge

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `5705c5eb09`, rubrics `19aa1baaa0`
- Samples per case: 3
- Cost: subject $0.8315, judge $2.3509

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 67/102 | child_fit 4.78, coverage 4.85, precision 4.49, ranking 4.66, related_core 4.88 | 5/99 | 10.06s / 15.38s | $0.00815 |

## Worth a look (36)

- **topic_words/potty_training** #0: (30 tiles)  
  missing 'wash'
- **topic_words/potty_training** #1: (30 tiles)  
  missing 'wash'
- **topic_words/potty_training** #2: (30 tiles)  
  missing 'wash'
- **topic_words/swimming** #0: (32 tiles)  
  missing 'wet' (in the overflow)
- **topic_words/hospital_stay** #1: (32 tiles)  
  missing 'mom / dad / family'
- **topic_words/morning_circle** #2: (31 tiles)  
  ranking=3
- **topic_words/grocery_store** #0: (32 tiles)  
  missing 'cart'
- **topic_words/grocery_store** #1: (32 tiles)  
  missing 'cart'
- **topic_words/grocery_store** #2: (32 tiles)  
  missing 'cart'
- **topic_words/pancakes_long** #0: (30 tiles)  
  missing 'turn / my_turn'
- **topic_words/pancakes_long** #1: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/pancakes_long** #2: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/holidays** #0: (32 tiles)  
  missing 'celebrate / party'; missing 'family / grandma / grandpa' (in the overflow)
- **topic_words/holidays** #1: (32 tiles)  
  missing 'celebrate / party'; missing 'give'; missing 'family / grandma / grandpa' (in the overflow); coverage=3; ranking=3
- **topic_words/holidays** #2: (32 tiles)  
  missing 'celebrate / party'; missing 'family / grandma / grandpa'
- **topic_words/restaurant** #0: (32 tiles)  
  missing 'drink'
- **topic_words/restaurant** #1: (32 tiles)  
  missing 'drink'
- **topic_words/restaurant** #2: (32 tiles)  
  missing 'drink'
- **topic_words/bible_stories** #0: (32 tiles)  
  missing 'love'; coverage=3
- **topic_words/bible_stories** #1: (32 tiles)  
  missing 'love'
- **topic_words/bible_stories** #2: (32 tiles)  
  missing 'love'
- **topic_words/favorite_show** #0: (32 tiles)  
  missing 'play'
- **topic_words/favorite_show** #1: (32 tiles)  
  missing 'play'; precision=3
- **topic_words/favorite_show** #2: (32 tiles)  
  missing 'play'; precision=3
- **topic_words/video_game** #0: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/video_game** #2: (32 tiles)  
  missing 'turn / my_turn'
- **topic_words/basketball** #0: (32 tiles)  
  missing 'ball'
- **topic_words/basketball** #1: (32 tiles)  
  missing 'ball'
- **topic_words/basketball** #2: (32 tiles)  
  missing 'ball'
- **topic_words/fast_food** #0: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'
- **topic_words/fast_food** #1: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'
- **topic_words/fast_food** #2: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'
- **topic_words/national_park** #0: (32 tiles)  
  missing 'hike'
- **topic_words/national_park** #1: (32 tiles)  
  missing 'hike'
- **topic_words/national_park** #2: (32 tiles)  
  missing 'hike'
- **topic_words/leaf_playground** #0: (30 tiles)  
  missing 'turn'
