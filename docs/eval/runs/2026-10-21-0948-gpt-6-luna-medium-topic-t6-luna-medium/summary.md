# Eval run 2026-10-21-0948-gpt-6-luna-medium-topic-t6-luna-medium

- Subject: `gpt-6-luna` (effort `medium`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `5705c5eb09`, rubrics `8f550b6a15`
- Samples per case: 3
- Cost: subject $0.1054, judge $2.2128

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 65/102 | child_fit 4.09, coverage 3.21, precision 3.81, ranking 2.66, related_core 3.25 | 89/99 | 15.99s / 25.13s | $0.00103 |

## Worth a look (89)

- **topic_words/potty_training** #0: (23 tiles)  
  missing 'wash'; missing 'flush / wipe'; coverage=3; precision=3; ranking=3
- **topic_words/potty_training** #1: (24 tiles)  
  missing 'wash'; missing 'flush / wipe'; coverage=3; precision=3; ranking=3
- **topic_words/potty_training** #2: (25 tiles)  
  missing 'wash'; missing 'flush / wipe'; coverage=3; precision=3; ranking=3
- **topic_words/dentist** #0: (29 tiles)  
  related_core=3; ranking=3
- **topic_words/dentist** #1: (32 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/dentist** #2: (28 tiles)  
  coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/farm_trip** #0: (30 tiles)  
  related_core=3; ranking=2
- **topic_words/farm_trip** #2: (30 tiles)  
  missing 'farmer'; related_core=3; ranking=3
- **topic_words/birthday_party** #0: (25 tiles)  
  missing 'cake'; missing 'present / gift'; coverage=2; precision=3; ranking=2
- **topic_words/swimming** #0: (30 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/swimming** #2: (32 tiles)  
  missing 'scared / cold'; coverage=2; precision=3; related_core=3; ranking=2
- **topic_words/hospital_stay** #0: (32 tiles)  
  missing 'mom / dad / family'; coverage=3; ranking=2
- **topic_words/hospital_stay** #1: (32 tiles)  
  missing 'hurt'; missing 'mom / dad / family'; coverage=3; related_core=3; ranking=2
- **topic_words/hospital_stay** #2: (32 tiles)  
  missing 'mom / dad / family'; coverage=3; related_core=3; ranking=2
- **topic_words/church** #0: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/church** #1: (27 tiles)  
  missing 'quiet'; coverage=2; precision=3; related_core=3; ranking=2
- **topic_words/church** #2: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/morning_circle** #0: (32 tiles)  
  coverage=3; related_core=2; ranking=3
- **topic_words/morning_circle** #1: (32 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/morning_circle** #2: (32 tiles)  
  coverage=2; related_core=3; ranking=3
- **topic_words/grocery_store** #0: (28 tiles)  
  missing 'cart'; coverage=3
- **topic_words/grocery_store** #1: (31 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/bedtime** #0: (25 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/bedtime** #1: (27 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/bedtime** #2: (25 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/zoo_terse** #0: (32 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/zoo_terse** #1: (25 tiles)  
  missing 'lion'; missing 'zookeeper'; coverage=2; precision=3; ranking=2
- **topic_words/zoo_terse** #2: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/pancakes_long** #0: (30 tiles)  
  coverage=3; related_core=3; ranking=2; child_fit=3
- **topic_words/pancakes_long** #1: (28 tiles)  
  missing 'turn / my_turn'; coverage=3; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/pancakes_long** #2: (32 tiles)  
  missing 'stir'; coverage=2; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/holidays** #0: (32 tiles)  
  missing 'give'; missing 'family / grandma / grandpa'; coverage=3; related_core=3; ranking=2
- **topic_words/holidays** #1: (32 tiles)  
  new word(s) with an unknown wordClass: stocking; missing 'family / grandma / grandpa'; coverage=3; related_core=3; ranking=2
- **topic_words/holidays** #2: (31 tiles)  
  missing 'give'; missing 'family / grandma / grandpa' (in the overflow); coverage=3; related_core=3; ranking=2
- **topic_words/doctor_visit** #0: (32 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/doctor_visit** #1: (32 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/doctor_visit** #2: (32 tiles)  
  coverage=3; ranking=2
- **topic_words/restaurant** #0: (32 tiles)  
  ranking=3
- **topic_words/restaurant** #1: (32 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/restaurant** #2: (32 tiles)  
  coverage=3; ranking=2
- **topic_words/bible_stories** #0: (32 tiles)  
  missing 'love'; coverage=3; related_core=2; ranking=2; child_fit=3
- **topic_words/bible_stories** #1: (32 tiles)  
  missing 'love'; coverage=3; related_core=2; ranking=2
- **topic_words/bible_stories** #2: (31 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/favorite_show** #0: (32 tiles)  
  coverage=3; ranking=3
- **topic_words/favorite_show** #1: (31 tiles)  
  coverage=3; ranking=3
- **topic_words/favorite_show** #2: (30 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/snack_time** #0: (32 tiles)  
  coverage=3; ranking=2
- **topic_words/snack_time** #1: (30 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/snack_time** #2: (32 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/movie** #0: (32 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/movie** #1: (32 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/movie** #2: (25 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/video_game** #0: (32 tiles)  
  missing 'win / lose'; missing 'turn / my_turn'; coverage=3; related_core=2; ranking=2
- **topic_words/video_game** #1: (32 tiles)  
  missing 'win / lose' (in the overflow); coverage=3; related_core=2; ranking=2
- **topic_words/video_game** #2: (28 tiles)  
  missing 'turn / my_turn'; coverage=3; related_core=3; ranking=2
- **topic_words/basketball** #0: (28 tiles)  
  ranking=3
- **topic_words/basketball** #1: (28 tiles)  
  missing 'hoop / basket'; missing 'coach'; coverage=2; precision=3; related_core=3; ranking=2
- **topic_words/basketball** #2: (30 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/library** #0: (30 tiles)  
  precision=3; ranking=3
- **topic_words/library** #2: (28 tiles)  
  ranking=3
