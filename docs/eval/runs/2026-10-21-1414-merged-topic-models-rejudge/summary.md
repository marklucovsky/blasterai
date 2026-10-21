# Eval run 2026-10-21-1414-merged-topic-models-rejudge

- Subject: `merged`
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `5705c5eb09`, rubrics `19aa1baaa0`
- Samples per case: 1
- Cost: subject $0.4376, judge $2.8413

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|

## Worth a look (63)

- **topic_words/gpt-4o-mini/potty_training** #0: {
  "refused": false,
  "name": "Potty Training",
  "description": "Words to help with potty training at home.",
  "words": [
    { "word": "bathroom", "wordClass": "places" },
    { "word": "potty",   
  new word(s) with an unknown wordClass: done; coverage=3; precision=2
- **topic_words/gpt-6-luna-none+review/potty_training** #0: {
  "refused": false,
  "name": "Potty training at home",
  "description": "Words for asking to use the potty, saying when you're finished, and washing hands.",
  "words": [
    { "word": "potty", "wo  
  missing 'wash'; missing 'flush / wipe'
- **topic_words/gpt-6.1-sol-low/potty_training** #0: {
  "refused": false,
  "name": "Potty at Home",
  "description": "Words to ask for the potty, tell when finished, and wash hands afterward.",
  "words": [
    { "word": "potty", "wordClass": "health"  
  missing 'wash'
- **topic_words/gpt-4o-mini/dentist** #0: {
  "refused": false,
  "name": "First Visit to the Dentist",
  "description": "Words to use during a visit to the dentist.",
  "words": [
    { "word": "dentist", "wordClass": "people" },
    { "word  
  missing 'sit'; precision=3; child_fit=3
- **topic_words/gpt-6-luna-none+review/dentist** #0: {
  "refused": false,
  "name": "Dentist",
  "description": "Words for visiting the dentist, sitting in the chair, and having teeth checked and cleaned.",
  "words": [
    { "word": "dentist", "wordCl  
  missing 'scared / hurt'
- **topic_words/gpt-4o-mini/farm_trip** #0: {
  "refused": false,
  "name": "Field Trip to the Farm",
  "description": "Words for a fun trip to the farm to see animals and ride on a hay wagon.",
  "words": [
    { "word": "farm", "wordClass": "  
  missing 'farmer'
- **topic_words/gpt-6-luna-none+review/farm_trip** #0: {
  "refused": false,
  "name": "Farm Field Trip",
  "description": "Words for visiting a farm, feeding goats, and riding in a hay wagon.",
  "words": [
    { "word": "farm", "wordClass": "places" },
  
  missing 'farmer'
- **topic_words/gpt-4o-mini/birthday_party** #0: {
  "refused": false,
  "name": "Friend's Birthday Party",
  "description": "Words to use at a friend's birthday party.",
  "words": [
    { "word": "friend", "wordClass": "people" },
    { "word": "c  
  missing 'open'; precision=3
- **topic_words/gpt-4o-mini/swimming** #0: {
  "refused": false,
  "name": "Swim Lesson at the Community Pool",
  "description": "Words to use during swim lessons at the pool.",
  "words": [
    { "word": "pool", "wordClass": "places" },
    {  
  missing 'scared / cold'; precision=3
- **topic_words/gpt-6-luna-none+review/swimming** #0: {"refused":false,"name":"Swim lesson at the community pool","description":"Words for swim lesson activities, pool equipment, and how the water feels.","words":[{"word":"pool","wordClass":"places"},{"w  
  coverage=3
- **topic_words/gpt-6.1-sol-low/swimming** #0: {
  "refused": false,
  "name": "Swim Lesson",
  "description": "Words for swimming lessons, pool equipment, water safety, and feelings at the community pool.",
  "words": [
    { "word": "pool", "wor  
  missing 'wet' (in the overflow)
- **topic_words/gpt-4o-mini/hospital_stay** #0: {
  "refused": false,
  "name": "hospital stay",
  "description": "Words to use during a hospital stay.",
  "words": [
    { "word": "hospital", "wordClass": "places" },
    { "word": "nurse", "wordCl  
  missing 'hurt'; missing 'mom / dad / family' (in the overflow)
- **topic_words/gpt-6-luna-none+review/hospital_stay** #0: {
  "refused": false,
  "name": "Hospital stay",
  "description": "Words for a three-day hospital stay, including nurses, checks, meals, and how it feels.",
  "words": [
    { "word": "hospital", "wor  
  missing 'doctor'; missing 'mom / dad / family' (in the overflow)
- **topic_words/gpt-4o-mini/church** #0: {
  "refused": false,
  "name": "Sunday Church Service",
  "description": "Words to use during Sunday church service and Sunday school with family.",
  "words": [
    { "word": "church", "wordClass":   
  missing 'quiet'; precision=3; ranking=3
- **topic_words/gpt-6-luna-none+review/church** #0: {
  "refused": false,
  "name": "Church and Sunday school",
  "description": "Words for a family visit to church, worship, and Sunday school.",
  "words": [
    { "word": "church", "wordClass": "place  
  coverage=3
- **topic_words/gpt-4o-mini/morning_circle** #0: {
  "refused": false,
  "name": "Morning Circle Time",
  "description": "Words for talking about morning circle time in kindergarten.",
  "words": [
    { "word": "calendar", "wordClass": "object" },
  
  coverage=3; precision=3; ranking=3
- **topic_words/gpt-6-luna-none+review/morning_circle** #0: {
  "refused": false,
  "name": "Morning Circle Time",
  "description": "Words for checking the calendar and weather, talking about the days, and singing in class.",
  "words": [
    { "word": "class"  
  coverage=3
- **topic_words/gpt-6.1-sol-low/grocery_store** #0: {
  "refused": false,
  "name": "Grocery shopping with dad",
  "description": "Words for finding groceries, helping Dad shop, and checking out.",
  "words": [
    { "word": "grocery_store", "wordClass  
  missing 'cart'
- **topic_words/gpt-4o-mini/bedtime** #0: {
  "refused": false,
  "name": "Bedtime Routine",
  "description": "Words for getting ready for bed.",
  "words": [
    { "word": "bath", "wordClass": "object" },
    { "word": "pajamas", "wordClass"  
  ranking=3
- **topic_words/gpt-6-luna-none+review/bedtime** #0: {
  "refused": false,
  "name": "Bedtime routine",
  "description": "Words for bath time, getting into pajamas, brushing teeth, reading a bedtime story, and turning out the lights.",
  "words": [
      
  coverage=3
- **topic_words/gpt-4o-mini/sensory_break** #0: {
  "refused": false,
  "name": "Sensory Break",
  "description": "Words to ask for a quiet break when it's too loud.",
  "words": [
    { "word": "quiet", "wordClass": "describe" },
    { "word": "he  
  coverage=3; precision=3
- **topic_words/gpt-6-luna-none+review/sensory_break** #0: {
  "refused": false,
  "name": "Sensory break",
  "description": "Words for asking for a quiet corner, headphones, or a squeeze ball when the classroom feels too loud.",
  "words": [
    { "word": "b  
  coverage=3
- **topic_words/gpt-4o-mini/zoo_terse** #0: {
  "refused": false,
  "name": "zoo",
  "description": "This page is about the zoo and all the fun things to see and do there!",
  "words": [
    { "word": "zoo", "wordClass": "places" },
    { "word  
  missing 'zookeeper'
- **topic_words/gpt-6-luna-none+review/zoo_terse** #0: {"refused":false,"name":"Zoo","description":"Animals, places, and things to see and do at the zoo.","words":[{"word":"zoo","wordClass":"places"},{"word":"animals","wordClass":"object"},{"word":"monkey  
  missing 'zookeeper'
- **topic_words/gpt-4o-mini/pancakes_long** #0: {
  "refused": false,
  "name": "Cooking Activity",
  "description": "This page is for our cooking activity where we make pancakes!",
  "words": [
    { "word": "pancakes", "wordClass": "food" },
      
  precision=3; ranking=3
- **topic_words/gpt-6-luna-none+review/pancakes_long** #0: {
  "refused": false,
  "name": "Making Pancakes",
  "description": "Words for making and eating pancakes together in speech group.",
  "words": [
    { "word": "pancakes", "wordClass": "food" },
      
  ranking=3
- **topic_words/gpt-6.1-sol-low/pancakes_long** #0: {
  "refused": false,
  "name": "Making Pancakes",
  "description": "Words for mixing pancakes, taking turns, watching an adult cook on the hot griddle, and eating with syrup and berries.",
  "words":  
  missing 'turn / my_turn'
- **topic_words/gpt-4o-mini/holidays** #0: {
  "refused": false,
  "name": "Holidays",
  "description": "Words about different holidays throughout the year.",
  "words": [
    { "word": "birthday", "wordClass": "object" },
    { "word": "Hallo  
  missing 'give'; missing 'open'; precision=3
- **topic_words/gpt-6-luna-none+review/holidays** #0: {
  "refused": false,
  "name": "Holidays through the year",
  "description": "Words for birthdays, Halloween, Thanksgiving, Christmas, Hanukkah, and the Fourth of July.",
  "words": [
    { "word": "  
  missing 'give'; coverage=3; ranking=3
- **topic_words/gpt-6.1-sol-low/holidays** #0: {
  "refused": false,
  "name": "Holidays Through the Year",
  "description": "Words for birthday celebrations, Halloween, Thanksgiving, Christmas, Hanukkah and the Fourth of July.",
  "words": [
      
  missing 'celebrate / party'; missing 'family / grandma / grandpa' (in the overflow)
- **topic_words/gpt-4o-mini/doctor_visit** #0: {
  "refused": false,
  "name": "Going to the doctor",
  "description": "Words for visiting the doctor for a checkup.",
  "words": [
    { "word": "doctor", "wordClass": "people" },
    { "word": "nur  
  missing 'wait'; missing 'sit / lie_down'
- **topic_words/gpt-6-luna-none+review/doctor_visit** #0: {"refused":false,"name":"Doctor checkup","description":"Words for the people, tools, and actions involved in a checkup.","words":[{"word":"doctor","wordClass":"places"},{"word":"nurse","wordClass":"pe  
  missing 'wait'; missing 'sit / lie_down'; coverage=3
- **topic_words/gpt-6-luna-none+review/restaurant** #0: {
  "refused": false,
  "name": "Family restaurant",
  "description": "Words for choosing food, ordering, waiting, eating, and asking for the check.",
  "words": [
    { "word": "restaurant", "wordCla  
  missing 'waiter / server'; missing 'drink'
- **topic_words/gpt-6.1-sol-low/restaurant** #0: {
  "refused": false,
  "name": "Family Restaurant",
  "description": "Words for ordering a meal, waiting for food, and asking for the check at a family restaurant.",
  "words": [
    { "word": "resta  
  missing 'drink'
- **topic_words/gpt-4o-mini/bible_stories** #0: {
  "refused": false,
  "name": "Sunday School Stories",
  "description": "Words to help talk about stories about Jesus.",
  "words": [
    { "word": "Jesus", "wordClass": "people" },
    { "word": "B  
  coverage=3; precision=3; child_fit=3
- **topic_words/gpt-6.1-sol-low/bible_stories** #0: {
  "refused": false,
  "name": "Stories About Jesus",
  "description": "Words for sharing Sunday school stories about Jesus, his family, and the people he helped.",
  "words": [
    { "word": "Jesus"  
  missing 'love'; coverage=3
- **topic_words/gpt-4o-mini/favorite_show** #0: {
  "refused": false,
  "name": "Watching Bluey",
  "description": "Words to use while watching Bluey with my sister and playing games from the show.",
  "words": [
    { "word": "Bluey", "wordClass":  
  missing 'watch'; coverage=2; precision=2; child_fit=3
- **topic_words/gpt-6.1-sol-low/favorite_show** #0: {
  "refused": false,
  "name": "Bluey with My Sister",
  "description": "Words for watching Bluey with a sister and acting out the family's pretend games.",
  "words": [
    { "word": "Bluey", "wordC  
  missing 'play'
- **topic_words/gpt-4o-mini/snack_time** #0: {
  "refused": false,
  "name": "Snack Time at Preschool",
  "description": "These are words to use during snack time at preschool.",
  "words": [
    { "word": "snack", "wordClass": "food" },
    { "  
  coverage=3; precision=3; ranking=2
- **topic_words/gpt-4o-mini/movie** #0: {
  "refused": false,
  "name": "Watching Frozen",
  "description": "Words to use while watching Frozen and singing the songs.",
  "words": [
    { "word": "Frozen", "wordClass": "object" },
    { "wo  
  precision=3
- **topic_words/gpt-6-luna-none+review/movie** #0: {
  "refused": false,
  "name": "Watching Frozen and singing",
  "description": "Words for watching Frozen at home and singing along to its songs.",
  "words": [
    { "word": "Frozen", "wordClass": "  
  phrase tile(s): do_you_want_to_build_a_snowman, for_the_first_time_in_forever; precision=3
- **topic_words/gpt-4o-mini/video_game** #0: {
  "refused": false,
  "name": "Playing Super Mario",
  "description": "Words to use while playing Super Mario on the Switch.",
  "words": [
    { "word": "Mario", "wordClass": "object" },
    { "wor  
  missing 'turn / my_turn'; coverage=3; precision=3; ranking=3
- **topic_words/gpt-6.1-sol-low/video_game** #0: {
  "refused": false,
  "name": "Mario with My Brother",
  "description": "Words for playing Mario on the Nintendo Switch, sharing with a brother, and talking about characters, actions, and feelings."  
  missing 'turn / my_turn'
- **topic_words/gpt-4o-mini/basketball** #0: {
  "refused": false,
  "name": "Basketball Practice",
  "description": "Words to use during basketball practice.",
  "words": [
    { "word": "basketball", "wordClass": "sports" },
    { "word": "pra  
  missing 'throw'; missing 'catch'; precision=3; child_fit=3
- **topic_words/gpt-6.1-sol-low/basketball** #0: {
  "refused": false,
  "name": "Basketball Practice",
  "description": "Words for basketball practice after school, including equipment, skills, and feelings.",
  "words": [
    { "word": "basketball  
  missing 'ball'
- **topic_words/gpt-4o-mini/library** #0: {
  "refused": false,
  "name": "library",
  "description": "Words to use at the library for picking books and story time.",
  "words": [
    { "word": "library", "wordClass": "places" },
    { "word"  
  missing 'librarian'
- **topic_words/gpt-6-luna-none+review/library** #0: {"refused":false,"name":"Library","description":"Words for choosing books, joining story time, and keeping quiet at the library.","words":[{"word":"library","wordClass":"places"},{"word":"book","wordC  
  missing 'librarian'
- **topic_words/gpt-4o-mini/airplane** #0: {
  "refused": false,
  "name": "Airplane Trip",
  "description": "Words for our first trip on an airplane.",
  "words": [
    { "word": "airplane", "wordClass": "object" },
    { "word": "airport", "  
  missing 'fly'; precision=3
- **topic_words/gpt-6-luna-none+review/airplane** #0: {
  "refused": false,
  "name": "Our first trip on an airplane",
  "description": "Words for the airport, boarding, and taking a first airplane ride.",
  "words": [
    { "word": "airplane", "wordClas  
  missing 'pilot'
- **topic_words/gpt-4o-mini/art_class** #0: {
  "refused": false,
  "name": "Art Class",
  "description": "Words to use in art class for painting, gluing, and cutting.",
  "words": [
    { "word": "art", "wordClass": "art" },
    { "word": "pai  
  precision=3
- **topic_words/gpt-4o-mini/song** #0: {
  "refused": false,
  "name": "Singing Wheels on the Bus",
  "description": "Words to use while singing the song 'Wheels on the Bus' together.",
  "words": [
    { "word": "bus", "wordClass": "objec  
  coverage=3; precision=3
- **topic_words/gpt-4o-mini/fast_food** #0: {
  "refused": false,
  "name": "Ordering at McDonald's",
  "description": "Words to help you order food at McDonald's.",
  "words": [
    { "word": "McDonald's", "wordClass": "places" },
    { "word"  
  missing 'please'; ranking=3
- **topic_words/gpt-6-luna-none+review/fast_food** #0: {
  "refused": false,
  "name": "Ordering at McDonald's",
  "description": "Words for choosing, ordering, and eating food at McDonald's.",
  "words": [
    { "word": "McDonald's", "wordClass": "places  
  missing 'happy_meal'; missing 'small / large'
- **topic_words/gpt-6.1-sol-low/fast_food** #0: {
  "refused": false,
  "name": "Ordering at McDonald's",
  "description": "Words for choosing a McDonald's meal, ordering politely, and saying how you feel.",
  "words": [
    { "word": "McDonald's",  
  missing 'nuggets / chicken_nuggets'; missing 'small / large'
- **topic_words/gpt-4o-mini/national_park** #0: {
  "refused": false,
  "name": "Yellowstone National Park",
  "description": "Words to use during a family trip to Yellowstone National Park.",
  "words": [
    { "word": "Yellowstone", "wordClass":   
  missing 'bear / grizzly_bear'; missing 'ranger / park_ranger'; precision=3; ranking=3
- **topic_words/gpt-6-luna-none+review/national_park** #0: {"refused":false,"name":"Yellowstone National Park","description":"Words for a family trip to Yellowstone, its famous sights, wildlife, and things to do.","words":[{"word":"Yellowstone","wordClass":"p  
  missing 'ranger / park_ranger'; missing 'hike'
- **topic_words/gpt-6.1-sol-low/national_park** #0: {
  "refused": false,
  "name": "Yellowstone Family Trip",
  "description": "Words for exploring Yellowstone’s geysers, spotting wildlife, and staying safe with family.",
  "words": [
    { "word": "Y  
  missing 'hike'
- **topic_words/gpt-4o-mini/leaf_playground** #0: {
  "refused": false,
  "name": "The Playground",
  "description": "Words to use at the playground with slides, swings, and sandboxes.",
  "words": [
    { "word": "playground", "wordClass": "places"   
  missing 'turn'; precision=3; ranking=3
- **topic_words/gpt-6-luna-none+review/leaf_playground** #0: {
  "refused": false,
  "name": "The playground",
  "description": "Words for playing on the slide and swings and in the sandbox.",
  "words": [
    { "word": "playground", "wordClass": "places" },
    
  missing 'turn'
- **topic_words/gpt-6.1-sol-low/leaf_playground** #0: {
  "refused": false,
  "name": "Playground",
  "description": "Words for sliding, swinging, digging in the sandbox, and taking turns.",
  "words": [
    { "word": "playground", "wordClass": "places"   
  missing 'turn'
