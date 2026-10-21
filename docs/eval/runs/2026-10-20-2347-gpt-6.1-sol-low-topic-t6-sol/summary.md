# Eval run 2026-10-20-2347-gpt-6.1-sol-low-topic-t6-sol

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `5705c5eb09`, rubrics `8f550b6a15`
- Samples per case: 3
- Cost: subject $0.8315, judge $2.4498

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 66/102 | child_fit 4.44, coverage 3.87, precision 4.57, ranking 3.56, related_core 3.61 | 59/99 | 10.06s / 15.38s | $0.00815 |

## Worth a look (69)

- **topic_words/potty_training** #0: (30 tiles)  
  missing 'wash'; precision=3; ranking=3
- **topic_words/potty_training** #1: (30 tiles)  
  missing 'wash'; ranking=3
- **topic_words/potty_training** #2: (30 tiles)  
  missing 'wash'; precision=3; ranking=3
- **topic_words/dentist** #0: (32 tiles)  
  ranking=3
- **topic_words/dentist** #2: (32 tiles)  
  ranking=3
- **topic_words/farm_trip** #1: (32 tiles)  
  ranking=3
- **topic_words/swimming** #0: (32 tiles)  
  missing 'wet' (in the overflow); ranking=3
- **topic_words/swimming** #1: (32 tiles)  
  ranking=3
- **topic_words/hospital_stay** #0: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/hospital_stay** #1: (32 tiles)  
  missing 'mom / dad / family'; related_core=3
- **topic_words/hospital_stay** #2: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/church** #2: (32 tiles)  
  ranking=3
- **topic_words/morning_circle** #0: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/morning_circle** #1: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/morning_circle** #2: (31 tiles)  
  related_core=3; ranking=3
- **topic_words/grocery_store** #0: (32 tiles)  
  missing 'cart'
- **topic_words/grocery_store** #1: (32 tiles)  
  missing 'cart'
- **topic_words/grocery_store** #2: (32 tiles)  
  missing 'cart'
- **topic_words/bedtime** #1: (32 tiles)  
  related_core=3
- **topic_words/bedtime** #2: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/zoo_terse** #0: (32 tiles)  
  ranking=3
- **topic_words/pancakes_long** #0: (30 tiles)  
  missing 'turn / my_turn'; coverage=3; related_core=3; ranking=3
- **topic_words/pancakes_long** #1: (32 tiles)  
  missing 'turn / my_turn'; coverage=3; related_core=3; ranking=3
- **topic_words/pancakes_long** #2: (32 tiles)  
  missing 'turn / my_turn'; related_core=3; ranking=3
- **topic_words/holidays** #0: (32 tiles)  
  missing 'celebrate / party'; missing 'give' (in the overflow); missing 'family / grandma / grandpa' (in the overflow); related_core=3; ranking=3
- **topic_words/holidays** #1: (32 tiles)  
  missing 'celebrate / party'; missing 'give'; related_core=2; ranking=3
- **topic_words/holidays** #2: (32 tiles)  
  missing 'celebrate / party'; missing 'give' (in the overflow); missing 'family / grandma / grandpa'; related_core=3; ranking=3
- **topic_words/doctor_visit** #0: (32 tiles)  
  missing 'sit / lie_down' (in the overflow); ranking=3
- **topic_words/doctor_visit** #2: (32 tiles)  
  ranking=3
- **topic_words/restaurant** #0: (32 tiles)  
  missing 'drink'; related_core=3; ranking=3
- **topic_words/restaurant** #1: (32 tiles)  
  missing 'drink'; related_core=3; ranking=3
- **topic_words/restaurant** #2: (32 tiles)  
  missing 'drink'; related_core=3; ranking=3
- **topic_words/bible_stories** #0: (32 tiles)  
  missing 'love'; coverage=3; related_core=3; ranking=3
- **topic_words/bible_stories** #1: (32 tiles)  
  missing 'love'; coverage=3; related_core=3; ranking=3
- **topic_words/bible_stories** #2: (32 tiles)  
  missing 'love'; coverage=3; related_core=3; ranking=3
- **topic_words/favorite_show** #0: (32 tiles)  
  missing 'play'
- **topic_words/favorite_show** #1: (32 tiles)  
  missing 'play'; coverage=3; related_core=3
- **topic_words/favorite_show** #2: (32 tiles)  
  missing 'play'; coverage=3; related_core=3
- **topic_words/snack_time** #0: (32 tiles)  
  ranking=3
- **topic_words/snack_time** #1: (32 tiles)  
  precision=3; ranking=3
- **topic_words/snack_time** #2: (32 tiles)  
  precision=3; ranking=3
- **topic_words/movie** #0: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/movie** #1: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/movie** #2: (32 tiles)  
  coverage=3
- **topic_words/video_game** #0: (32 tiles)  
  missing 'turn / my_turn'; ranking=3
- **topic_words/video_game** #1: (32 tiles)  
  ranking=3
- **topic_words/video_game** #2: (32 tiles)  
  missing 'turn / my_turn'; related_core=3; ranking=3
- **topic_words/basketball** #0: (32 tiles)  
  missing 'ball'
- **topic_words/basketball** #1: (32 tiles)  
  missing 'ball'
- **topic_words/basketball** #2: (32 tiles)  
  missing 'ball'
- **topic_words/library** #1: (30 tiles)  
  ranking=3
- **topic_words/library** #2: (28 tiles)  
  ranking=3
- **topic_words/art_class** #0: (32 tiles)  
  ranking=3
- **topic_words/song** #2: (30 tiles)  
  ranking=3
- **topic_words/fast_food** #0: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'; related_core=3; ranking=3
- **topic_words/fast_food** #1: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'; related_core=3
- **topic_words/fast_food** #2: (32 tiles)  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'; related_core=2; ranking=2
- **topic_words/national_park** #0: (32 tiles)  
  missing 'hike'; related_core=3
- **topic_words/national_park** #1: (32 tiles)  
  missing 'hike'
- **topic_words/national_park** #2: (32 tiles)  
  missing 'hike'
