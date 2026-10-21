# Eval run 2026-10-20-2342-gpt-6-luna-none-topic-t7-review-luna

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `d1d0f5c+dirty`, prompts `5705c5eb09`, rubrics `8f550b6a15`
- Samples per case: 3
- Cost: subject $0.0573, judge $0.4373

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 57/102 | child_fit 4.18, coverage 3.26, precision 3.79, ranking 3.00, related_core 3.30 | 88/99 | 4.13s / 5.14s | $0.00056 |

## Worth a look (90)

- **topic_words/potty_training** #0: (24 tiles)  
  missing 'wash'; missing 'flush / wipe'; coverage=3; precision=3; ranking=3
- **topic_words/potty_training** #1: (27 tiles)  
  missing 'flush / wipe'; coverage=3; precision=3; ranking=3
- **topic_words/potty_training** #2: (25 tiles)  
  missing 'wash'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/dentist** #0: (22 tiles)  
  missing 'scared / hurt'; coverage=3; precision=3; ranking=3
- **topic_words/dentist** #1: (22 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/dentist** #2: (23 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/farm_trip** #0: (23 tiles)  
  missing 'farmer'
- **topic_words/farm_trip** #1: (24 tiles)  
  missing 'farmer'; related_core=3
- **topic_words/farm_trip** #2: (28 tiles)  
  missing 'farmer'; ranking=3
- **topic_words/birthday_party** #2: (28 tiles)  
  missing 'cake'; related_core=3; ranking=3
- **topic_words/swimming** #0: (27 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/swimming** #1: (25 tiles)  
  coverage=3; ranking=3
- **topic_words/swimming** #2: (28 tiles)  
  coverage=3
- **topic_words/hospital_stay** #0: (30 tiles)  
  missing 'doctor'; missing 'mom / dad / family' (in the overflow); coverage=3; ranking=2
- **topic_words/hospital_stay** #1: (30 tiles)  
  missing 'doctor'; coverage=3; ranking=3
- **topic_words/hospital_stay** #2: (30 tiles)  
  missing 'mom / dad / family' (in the overflow); coverage=3; related_core=3; ranking=2
- **topic_words/church** #0: (25 tiles)  
  coverage=3; ranking=3
- **topic_words/church** #1: (28 tiles)  
  missing 'quiet'; coverage=2; precision=3; related_core=3; ranking=2
- **topic_words/church** #2: (24 tiles)  
  coverage=2; ranking=2
- **topic_words/morning_circle** #0: (27 tiles)  
  coverage=2; related_core=3
- **topic_words/morning_circle** #1: (25 tiles)  
  coverage=2; related_core=3; ranking=2
- **topic_words/morning_circle** #2: (29 tiles)  
  coverage=2; related_core=3; ranking=3
- **topic_words/grocery_store** #0: (32 tiles)  
  ranking=3
- **topic_words/bedtime** #0: (25 tiles)  
  coverage=3; ranking=3
- **topic_words/bedtime** #1: (27 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/bedtime** #2: (26 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/sensory_break** #0: (24 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/sensory_break** #1: (19 tiles)  
  coverage=3; ranking=3
- **topic_words/sensory_break** #2: (23 tiles)  
  ranking=3
- **topic_words/zoo_terse** #0: (32 tiles)  
  missing 'zookeeper'; coverage=3; related_core=2; ranking=2
- **topic_words/zoo_terse** #1: (26 tiles)  
  missing 'lion'; missing 'zookeeper'; coverage=2; precision=3
- **topic_words/zoo_terse** #2: (32 tiles)  
  missing 'zookeeper'; coverage=3; precision=3; related_core=1; ranking=2
- **topic_words/pancakes_long** #0: (28 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/pancakes_long** #1: (26 tiles)  
  coverage=3; precision=3; ranking=2; child_fit=3
- **topic_words/pancakes_long** #2: (24 tiles)  
  coverage=3; precision=3; ranking=3; child_fit=3
- **topic_words/holidays** #0: (29 tiles)  
  missing 'give'; missing 'open' (in the overflow); missing 'happy / excited' (in the overflow); coverage=3; related_core=2; ranking=2
- **topic_words/holidays** #1: (30 tiles)  
  missing 'celebrate / party'; missing 'give'; missing 'happy / excited' (in the overflow); coverage=3; related_core=2; ranking=3
- **topic_words/holidays** #2: (32 tiles)  
  missing 'give'; missing 'open' (in the overflow); missing 'happy / excited' (in the overflow); coverage=3; related_core=1; ranking=2
- **topic_words/doctor_visit** #0: (32 tiles)  
  missing 'wait'; missing 'sit / lie_down'; coverage=2; precision=3; related_core=2; ranking=2
- **topic_words/doctor_visit** #1: (25 tiles)  
  coverage=3; ranking=3
- **topic_words/doctor_visit** #2: (31 tiles)  
  missing 'wait' (in the overflow); missing 'sit / lie_down' (in the overflow); coverage=3; related_core=2; ranking=2
- **topic_words/restaurant** #0: (32 tiles)  
  missing 'waiter / server'; missing 'drink'; coverage=3; related_core=3; ranking=3
- **topic_words/restaurant** #1: (32 tiles)  
  related_core=3; ranking=3
- **topic_words/restaurant** #2: (32 tiles)  
  missing 'drink' (in the overflow); coverage=3; related_core=3; ranking=2
- **topic_words/bible_stories** #0: (25 tiles)  
  coverage=3; ranking=3
- **topic_words/bible_stories** #1: (28 tiles)  
  coverage=3; related_core=3; ranking=3
- **topic_words/bible_stories** #2: (29 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/favorite_show** #0: (25 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/favorite_show** #2: (23 tiles)  
  coverage=3; ranking=3
- **topic_words/snack_time** #0: (32 tiles)  
  coverage=3; related_core=2; ranking=2
- **topic_words/snack_time** #1: (32 tiles)  
  ranking=3
- **topic_words/snack_time** #2: (30 tiles)  
  ranking=3
- **topic_words/movie** #0: (27 tiles)  
  phrase tile(s): do_you_want_to_build_a_snowman, for_the_first_time_in_forever; related_core=3; ranking=3
- **topic_words/movie** #1: (29 tiles)  
  phrase tile(s): do_you_want_to_build_a_snowman, for_the_first_time_in_forever, love_is_an_open_door; coverage=3; related_core=2; ranking=2
- **topic_words/movie** #2: (25 tiles)  
  phrase tile(s): do_you_want_to_build_a_snowman?; related_core=3; ranking=3
- **topic_words/video_game** #0: (28 tiles)  
  coverage=3; related_core=2; ranking=2
- **topic_words/video_game** #1: (24 tiles)  
  ranking=3
- **topic_words/video_game** #2: (28 tiles)  
  coverage=3; related_core=3; ranking=2
- **topic_words/basketball** #0: (27 tiles)  
  ranking=3
- **topic_words/basketball** #1: (26 tiles)  
  precision=3
