<!-- SPDX-License-Identifier: Apache-2.0 -->
# TestFlight & App Review copy

Every text field App Store Connect asks for, in the order the form asks for it,
plus the invite email that goes out of band.

**Four audiences, and the tone differs.** Apple's reviewers get an honest,
superficial walk and are asked nothing. Testers get a walk *and* questions. The
invite email carries the one thing that belongs to a relationship rather than a
test.

| Where | Field | Read by |
|---|---|---|
| TestFlight → Test Information | **Beta App Description** | testers, in the TestFlight app |
| TestFlight → Test Information | **Review Notes** | Apple's beta reviewer |
| TestFlight → the build | **What to Test** | testers, per build |
| Distribution → App Review Information | **Notes** | Apple's App Store reviewer |
| Your mail client | **Invite email** | Brandi and the SLPs |

`python3 tools/make_tester_notes.py` extracts the plain text for each and builds
the tester PDF. Both ASC boxes cap at 4,000 characters and truncate silently, so
it checks.

---

## 0. Beta App Information

**Feedback Email:** support@blasterai.app
**Marketing URL:** https://blasterai.app
**Privacy Policy URL:** https://blasterai.app/privacy

### Beta App Description

> BlasterAI is an AAC app — augmentative and alternative communication — for
> non-verbal children. A child touches picture tiles and the app speaks for them.
>
> It arrives with a full vocabulary and working boards, and every board can be
> rebuilt: add words, hide them, rearrange pages, print the board on paper.
>
> Optionally, it can turn a selection of tiles into a whole spoken sentence. That
> part uses your own OpenAI key and is off until you add one — without it the app
> speaks each word as it is tapped, the way a conventional AAC device does.
>
> No account and no server. Everything stays on your device and in your own
> iCloud.

---

## 1. Review Notes — for Apple

Paste into **both**:

- TestFlight → Test Information → Beta App Review Information → **Review Notes**
- Distribution → App Review Information → **Notes**

**Sign-in required: leave unchecked.** There are no accounts.
**Contact:** Mark Lucovsky · support@blasterai.app

Apple is asked nothing here. An honest, superficial walk, and the facts a
reviewer needs so a keyless app does not read as a broken one.

> BlasterAI is an AAC (augmentative and alternative communication) app for
> non-verbal children. A child touches picture tiles; the app speaks for them.
>
> **Business model: there is none to buy.** No price, no in-app purchase, no
> subscription, no ads, no account. The optional AI features run on the
> caregiver's own OpenAI API key, which OpenAI bills to them directly; we sell
> nothing, resell nothing, and receive nothing from that use.
>
> **No account, no sign-in, no server.** Everything is stored on the device and
> synced through the user's own iCloud. Nothing reaches a server we operate.
>
> **Nothing needs configuring to review it.** First launch loads a complete
> board of more than 1,000 words. Tap a tile and the app speaks.
>
> **AI sentence generation is optional and bring-your-own-key.** A caregiver may
> add their own OpenAI API key so a child's tile selection becomes a spoken
> sentence instead of separate words. It is off by default. Without a key the app
> speaks each word as it is tapped — how a conventional AAC device behaves, and
> how we expect most families to use it. **You do not need a key to review the
> app**, and the onboarding key step offers Skip.
>
> A five-minute walkthrough that needs no key:
>
> 1. At onboarding choose **Setup mode**, then **Not now** at Enable AI
>    Features (and **Skip** if it asks for a key).
> 2. Tap tiles on the home board — each speaks immediately.
> 3. Tap a tile with a small arrow badge to open another page. **Home** and
>    **Back** are on the rail beside the board.

> 4. **Touch and hold Home on the rail for about half a second.** That opens
>    the caregiver menu; choose **Settings**, one list: Profile, Current Board,
>    Message Box, Look, Sound, Feel, Boards and Vocabulary, Activity, AI,
>    Help, About, Advanced.
> 5. **Boards and Vocabulary** → tap the board we ship. It will offer to make you an editable
>    copy and switch to it; accept. The boards we supply are read-only so an app
>    update can never overwrite a caregiver's work.
> 6. In your copy: open a page, tap a tile → **Visibility** → **Conceal**.
>    Concealed words stay on the board for the caregiver and disappear for the
>    person using it.
> 7. **Boards and Vocabulary** → touch and hold a board → **Share** →
>    **Printable PDF**. The
>    same board as paper, which is what many classrooms still run on.
> 8. **Look, Sound, Feel** → **Tile Style** → switch styles. Every word is drawn in every
>    style; the whole board changes and nothing goes missing.
> 9. **Activity** → what was said, and which words have never been used.
>
> **Listed under Education, not Kids.** The person who installs, configures and
> maintains the app is an adult caregiver or speech-language pathologist. The
> child is who it is *for*, not who sets it up. Caregiver settings sit behind an
> optional Face ID / PIN gate, and a device can be put in Talk mode, which
> keeps the person using it inside the board.
>
> **Privacy: no data collected.** A child's words and usage stay on the device
> and in the user's own iCloud. https://blasterai.app/privacy
>
> If you would like to exercise the AI path, we can supply a funded API key —
> contact us and we will send one.

---

## 2. What to Test — for testers, per build

**How this section is organised.** The top of it is per build: *What's new in
build N* and *What to test in build N*, newest build first. Those two go to both
places — the App Store Connect **What to Test** box for that build, and the PDF.
Below them, inside `pdf-only`, is the standing walk everyone does once and the
sections from earlier builds, which only the PDF carries. Each new build adds
its two sections at the top and moves the previous build's down under
*Earlier builds* — and the same two lists are the habit App Review's "What's
New in This Version" will need.

> Thanks for looking at this. Start with what is new in this build. The full
> walk is in the TestFlight PDF that came with your invitation.
>
> At onboarding, choose **Setup mode**, and **Not now** at **Enable AI
> Features**. Most of this needs no key, and that is the
> configuration most families will run.
>
> ### What's new in build 13
>
> **A keyboard.** The Keyboard button on the rail opens it, and so does
> any sys:keyboard link you put in a navigation bar.
>
> - **QWERTY and ABC keyboards.** Each key is said as it's pressed, and
>   Space says the word. The word being typed shows in red in the message
>   box. A word we have becomes its tile, picture and all. A typed line is
>   said as typed and never sent for a sentence.
> - **Word prediction.** Once a word is started, the row above the keys
>   offers words with their pictures. Tap one to type it.
> - **Numbers.** The **123** key opens digits, signs, money and the clock
>   (:15, :30). Sums are said as sums: 12÷4 is "12 divided by 4".
> - **The ? key works sums out.** Type 1+2+3+4= and press **?**: the sum
>   shrinks a pair at a time, each step said, and the answer goes in the
>   message box. It finds missing numbers (3+?=7), checks answers
>   (5+5=9? comes back "not 9, it's 10") and picks signs (3?5).
> - **A calculator.** **Calc** on the numbers page: brackets, squares,
>   roots and powers, with its own display.
> - **Each sum is said once.** Type and play sums one after another; tap
>   one to hear its working again.
> - **On a phone** the keyboards are laid out for portrait.
> - **Settings › Look, Sound, Feel › Keyboard:** which keyboard the button
>   opens, vowel and sign tints, prediction, and the math helper.
> - **Also:** Search is full size on the Talk rail, Find Word searches the
>   whole board, received word packs offer to install, and older boards
>   offer the standard layout.
>
> ### What to test in build 13
>
> - **Type a few words** on QWERTY, then on ABC. Are the keys big enough,
>   and is each one said the way you'd want?
> - **Use prediction:** type two letters and pick a word. Is the word you
>   wanted there, and in the same place each time?
> - **Do some sums** with a learner who does maths: type 5+5=10 and
>   play it, then try **?** on one. Does the working help or get in the way?
> - **Try the calculator on a phone.**
>
<!-- pdf-only -->
> ---
>
> ### The walk
>
> About half an hour, done once, and you can stop anywhere.
>
> ### The user's side
>
> 1. **Tap tiles on the home board.** Each word should speak the instant you
>    touch it — no wait, no spinner.
> 2. **Follow a folder** into another page and back. Home and Back are on the
>    rail beside the board, always in the same place — that is deliberate, and
>    we want to know whether it feels obvious or hidden.
>
> ### Getting to the caregiver side
>
> 3. **Touch and hold Home** on the rail → **Settings**. Tell us whether you
>    would have found that on your own. **Settings › Help** has the guides.
>
> ### Making a board of your own
>
> 4. **Boards and Vocabulary → + → New Board.** Take either route:
>    - a ready-made example, or
>    - **Build from Collections** — tick vocabulary packs and word classes and
>      let it assemble a board.
> 5. Open your new board and open a page. Tap a word, then **Visibility** →
>    **Concealed**; tap another, then **Clear**. Conceal keeps a word on the
>    board for you and hides it from the child; Clear removes it. We would like
>    to know whether that distinction is clear without being told.

> 6. Rename a page (tap its name on the card above the grid), and drag a
>    tile to a new cell.
>
> Nothing above needs the guides, but they exist if you want them — and we would
> like to know whether you needed them:
>
> - **blasterai.app/guides/boards-pages-and-packs**
> - **blasterai.app/guides/pages-and-navigation**
> - **blasterai.app/guides/adding-vocabulary**
> - **blasterai.app/guides/editing-a-board**
> - **blasterai.app/guides/spreadsheet-boards**
> - **blasterai.app/guides/the-me-page**
>
> ### Taking a board off the device
>
> 7. **Boards and Vocabulary → touch and hold a board → Share.** Try **Printable PDF** — pick a
>    layout and paper size. Plenty of classrooms still run on paper, and a board
>    that cannot be printed is only half a board.

> 8. Same Share sheet, two more destinations:
>    - **Images** — the pictures as image files, for a worksheet or a label.
>    - **Blaster Board** — the board as a file. Text or email it to another
>      device running BlasterAI and tapping it rebuilds the board, artwork
>      included. That is how a therapist hands a board to a family.
>
> ### Looking at how it is used
>
> 9. **Look, Sound, Feel → Tile Style.** Switch styles. Every word is drawn
>    in every style.
> 10. **Activity.** The log of what was said, and **Coverage** — which of the
>     board's words have and have not been used. Does that screen answer a
>     question you would actually ask about the person using it?
> ### Now add a key
>
> **Settings → AI**: read the screen, turn it on, then add an OpenAI key — or
> open the key file if one was sent to you. Then **Message Box → Message →
> Sentences**.
>
> First, the message box. Tiles you tap collect along the top.
> **Tap a tile in the message box to take it back out.**
> Beside them are **Play** and **Clear**. At Stage IV+ there is also a
> backspace — see below.
>
> 11. **Start deliberately.** Tap three tiles, then press **Play**. You decide
>     when it speaks. Press **Clear** and do it again with different words.
> 12. **Now let it decide.** Tap four and pause without pressing anything — it
>     generates on its own once you stop. Try: **mom**, then the **places** page
>     link, then **park**, then **slide**. Note that walking to another page
>     mid-sentence does not lose what you already picked.
> 13. **Ask again, more urgently.** With a sentence on screen, press **Play**
>     again — or re-tap the last tile. Either repeats the request, and the
>     phrasing escalates rather than repeating verbatim, the way a child who was
>     not heard the first time would ask again. Try: from **home**, tap **dad**,
>     tap **chocolate**, press **Play**, then tap **chocolate** again.
> 14. **Add a new word** to one of your boards and let it draw a picture for it.
> 15. **Go back to Activity.** It should now show the sentences, and what they
>     cost.
> ### Earlier builds
>
> ### What's new in build 12
>
> **Some words changed.** A *scene* is now a **board**. The device modes are
> **Talk mode** (for the person using the board to talk) and **Setup mode**
> (for you). The tray is the **message box**, and the top row is the
> **navigation bar**. Image sets are now **Tile Styles**.
>
> - **Settings is one short list:** Profile, Current Board, Message Box, Look,
>   Sound, Feel, Boards and Vocabulary, Activity, AI, Help, About, Advanced.
>   On an iPad it opens on the current profile and Quick Settings.
> - **Each profile has its own message settings:** Single Words or
>   Sentences, words per message (4 to 8), and pictures in the message box.
>   The stage you pick only sets where they start.
> - **Help is in the app.** Settings › Help opens the blasterai.app guides,
>   and any guide you've opened before still opens offline.
> - **Boards and Vocabulary** has a search field, a filter (All · Mine ·
>   Built-in · Topics) and a **+** menu for new and imported boards.
> - **The board editor** puts Pages first. Artwork shows what each tile
>   style still needs, and asks before any run that costs money, with an
>   estimate.
> - **The Me page has rules.** **Always** shows a word every time. **Pinned**
>   puts a tile in a cell you choose. **Includes** brings in another Me page:
>   one "Room 4" page reaches every student who includes it. **Preview**
>   shows where each added tile lands and why. My Topics is always the first
>   cell.
> - **Share a Me page** along with its topic boards.
> - **Choosing a word or a page.** One word chooser: search, plus a chip for
>   each kind of word in its colour. Pages are listed by folder, the way you
>   reach them on the board. A search also finds a page by a word on it. In
>   the page editor, type **>** and tap **Browse** to pick a folder's page.
> - **Sharing keeps every tile setting,** including folder colours and labels.
>   Board files are now `.blasterboard`; older `.blasterscene` files still
>   open.
> - **Word packs stay put.** An app update used to hide the words of any
>   pack you had added, leaving a Tide Pools board with only *fish*. They
>   stay now, and words an update hid come back on first launch.
> - **A board made with New Board** has the navigation bar like every other
>   board, so it can be one of the user's topics.
>
> ### What's new in build 10
>
> **If you made your own board in an earlier build, start a fresh one.**
> Boards made before build 10 are full copies and won't pick up what's new
> here. Make a new one, or write to support@blasterai.app and we'll help.
>
> - **A new board editor.** A page is a grid, cell for cell the board the child
>   sees. Tap a cell and type: “cat”, or “cat, animal” for a new word,
>   “go > places” for a word that opens a page, “> animals” for a folder. On a
>   phone it scrolls in bands; on an iPad with a keyboard it works like a
>   spreadsheet.
> - **Boards from spreadsheets.** Write a whole board in Google Sheets, Excel or
>   Numbers, one tab per page, and import it. Any board exports back the same
>   way.
> - **Edit BlasterAI 60 by copying it.** Your copy follows BlasterAI 60 except
>   for the pages you change.
> - **Your own navigation bar**, across the top or the bottom.
> - **Templates.** Build a board on another board, the way every board builds
>   on BlasterAI 60. A board shared from one device brings its template with it.
> - **Me** on the rail: the child's own page, with My Topics and words that
>   change with the page they're on.
> - **New words don't need a class.** They show white with a **?** until you
>   give them one, and the app suggests one.
> - **Faster:** the page editor opens without a pause.
>
> ### What to test in build 10
>
> - **Make a board in the editor.** Copy BlasterAI 60 (tap it in Scenes), open
>   a page, and type a row of words and a folder. Was it obvious what to type?
> - **Try a spreadsheet.** Start from our sample: Scenes → Import Scene, paste
>   https://docs.google.com/spreadsheets/d/1EuMTqNVZIwCpm-exIO9BM_Im6QJ4pLSQkJGjYvfUVTw
>   (in Sheets, File → Make a copy to change it). Or export a board (Share →
>   Spreadsheet), change it, and import it back. From Google Sheets, share it as
>   "Anyone with the link" first. The guide: blasterai.app/guides/spreadsheet-boards
> - **Bar along the bottom:** your board → Navigation Bar → make it the
>   board's own → Placement: Bottom. Better or worse for your child?
> - **On a phone:** edit a page. Usable, or iPad-only?
> - **Share a board** to a second device. Does it arrive looking the same?
>
> ### What's new in build 9 — 1.0.0
>
> - **A bigger board with a shape you can see.** BlasterAI 60 grew by about
>   430 words, sorted into folders: Places › House, Food › Snacks & treats,
>   Actions › Moving, People › Family and more. The top row is the same ten
>   folders on every page, so you can always jump across.
> - **Doorway words** speak and open a page: *go* opens Places, *eat* opens
>   Food, *I* opens the I page, wherever the word sits.
> - **You are here.** The path shows over the board (Home › Places › House),
>   and the folder you came through is underlined.
> - **Home, Back and Keyboard live on a rail** beside the board (below it on
>   iPad portrait and iPhone), with Search, Level and Edit for caregivers.
>   **Child mode** keeps only what a child needs.
> - **Square tiles:** the picture on a light tint of its word colour, the word
>   across the bottom.
> - **Phrases:** Small words › Phrases holds 30 starter phrases from an SLP who
>   works with gestalt language learners ("Oh no, it's stuck!", "What's next?").
> - **iPhone, rebuilt:** the top row scrolls sideways and a page scrolls in
>   bands of four columns. Turn it sideways for the whole iPad board.
> - **Printing** follows the board, each page titled by its path.
> - **Sentences** come from OpenAI's GPT-6 Luna.
>
> ### What to test in build 9
>
> - **Find five words your child needs.** How many taps? Was the folder you
>   tried first the right one? What is still missing?
> - **Try a doorway:** tap *go* on Home. Expected, or a surprise?
> - **Turn on Child mode and hand it over.** Is the rail clear to a child?
> - **Phrases:** the right starters? Should a phrase speak the moment it is
>   tapped, instead of joining a sentence?
> - **iPhone:** upright and sideways. Which would you actually use?
> - **Print the board** (Share → Printable PDF). Would you use the book?
>
> ### What's new in build 8
>
> - **Levels.** BlasterAI 60 can now grow with the child. Touch and hold
>   **Home** and step the level down: at Level 1 only 13 first words show, Level
>   2 adds the rest of Home, Level 3 opens the folders, Level 4 is the whole
>   board. Hidden words keep their place, so nothing moves as words appear. This
>   is a first map, there to be argued with, not a clinical recommendation.
> - **Quick actions.** The same Home menu now switches the scene, the level, the
>   picture style, and Single Words or AI Sentences, without opening Admin.
> - **Find Word.** Home menu → **Find Word**: type a word and the board goes to
>   its page and highlights it. Words hidden by the current level show greyed,
>   with the level that reveals them.
> - **Your own levels.** In a copy of BlasterAI 60, or your own board: select
>   tiles, then **Show From Level** in the visibility menu.
> - **Since build 5:** new pictures are drawn with OpenAI's newer image model; "I"
>   and TV capitalised; am, are and was on Actions; faster scene and page
>   editors.
>
> ### What to test in build 8
>
> - **Step BlasterAI 60 down to Level 1, then up.** Are those the right first
>   words? Would you split Level 1 more finely, or open some folders sooner?
> - **Find Word:** look up the words your child needs. **What is missing?**
>   Tell us — we keep a running list of known gaps (days of the week, small
>   words like *of* and *from*, more feelings) and want yours on it.
> - **Is the Home menu too much** for a caregiver in the moment, or just right?
>   On iPhone, does it fit?
> - **Set levels on a board of your own.** Was **Show From Level** where you
>   expected it?
>
> ### What's new in build 5
>
> - **84 new words**, among them potty, pee, poop, medicine, bandaid, hand, foot,
>   tummy, calm, worried, upset, hug, climb, share, hide, because, but and will —
>   and four new folders on **Groups**: Animals, Clothes, Things and Vehicles.
>   Every word is drawn in every picture style.
> - **Actions, Describe and Body & Health are laid out by hand**, so related words
>   sit together: opposites side by side, the toileting words in a row.
> - **because** and **but** are drawn as a pair of symbols rather than pictures.
> - **The default board is called BlasterAI 60** — its home page holds 60 cells.
> - **Back.** Two folders deep, the Home cell splits into Home and Back.
> - **Board Layout** (Admin → Device) replaces Tile Density: Standard, Large and
>   Largest are fixed grids, so a word stays where the child learned it. The
>   iPad mini now matches the other iPads.
> - **AI features ask first.** Enable AI Features says what is sent to OpenAI
>   and needs a yes before any key is used. If you added a key in an earlier
>   build you will be asked once; until you say yes, the board works one word
>   at a time.
> - **Key files work from anywhere** — opened before setup is finished, or from
>   Admin → Device → Install key from file…
> - **Manage Vocabulary shows where each word is**: every route from Home, on
>   every board.
> - **Copies are numbered** — BlasterAI 60 (1), (2) — and each says what it was
>   copied from.
> - **Printing** starts from the board's own grid and can break pages where the
>   screen does.
>
> ### What to test in build 5
>
> - **Look for the new words** under Groups, on Body & Health and on the second
>   page of Actions. What is still missing? What sits next to the wrong
>   neighbour?
> - **because and but:** could a child learn those two marks? Better or worse
>   than a picture, or than the written word?
> - **Admin → Scenes → Manage Vocabulary.** Search for **hurt**, then
>   **because**. Do the routes match where you would look?
> - **Go two folders deep** (Groups → Animals) and use Back. Is half a cell
>   enough for a child's finger?
> - **Try Large and Largest** under Board Layout. Which would you choose for a
>   child, and why?
> - **If you had a key:** read the Enable AI Features screen before you answer.
>   Did it tell you what you would want to know?
> - **Make a copy of BlasterAI 60, then a copy of the copy.** Do the names and
>   the "Copied from" lines make sense?
>
> ### Build 4 — folder colours
>
> The top row of the home board is folders, and they arrive all one blue. The
> app can also colour each one by the words behind it — **people** yellow for
> pronouns, **actions** green for verbs, **describe** blue, **questions**
> purple — and we would like you to decide which is right.
>
> Blue is the default only because the SLP advising us preferred it. We are
> genuinely unsure, and this is the part we most want argued with.
>
> A. **Turn the colours on.** Admin → the child's profile → **Folder Color** →
>    *As Each Link Is Set*. Look at the top row before and after.
> B. **Which do you prefer, and for whom** — the child, or you? Does a green
>    folder standing over a green block of verbs help, or is it just more
>    colour?
> C. **Print it both ways** (Share → Printable PDF). We suspect the answer
>    differs on paper, where nothing navigates and a folder is a landmark
>    rather than a category. Tell us if that is nonsense.
>
> D. **Change one by hand.** Page editor → a folder tile → **Folder color**:
>    *Automatic* (it names what it worked out), *Page Links*, or a word type.
>    Set one, then add words to the page behind it — a folder you chose stays
>    put, one left on Automatic follows the page.
>
> If you use WordPower or TouchChat, we would especially like to know whether
> this reads the way the board you already know does.
>
> ### Build 4 — Stage IV+, the board as something you write with
>
> **Admin → the child's profile → Brown's Stage → IV+**, the most advanced
> stage. The tray stops looking like a row of tiles and starts looking like a
> line of text — words as words, no picture, no coloured card. The child is
> writing a sentence and picking the words off a board instead of a keyboard.
>
> - **Type a sentence.** Tap four or five words. A small **backspace** appears
>   at the end of them, only while there is something to delete. **Clear**
>   still empties the tray; tapping a word still removes that word.
> - **Build the same line in both modes** — long-press Home → caregiver menu.
>   **Sentence mode**: Play turns the words into a sentence, as at other
>   stages. **Word mode**: Play speaks them exactly as you arranged them,
>   sentence or not. That is deliberate — better to say what the child
>   assembled than to tidy it into something they did not.
> - **Can you tell which mode you are in?** Probably not from the board, which
>   is what we are least happy about. It is in the caregiver menu. Enough, or
>   should the screen say so?
>
> Then put the stage back where it belongs and watch the pictures return.
>
<!-- /pdf-only -->
> ### What we most want to hear
>
> - **The starting board is our first attempt, not a recommendation.** Where is
>   it wrong?
> - Did anything feel broken, slow or confusing **before** you added a key?
> - Is the child-facing screen calm enough to hand to a child?
> - Did anything in Admin look like it needs a manual?
> - What did you expect to find and could not?
>
> TestFlight feedback, or support@blasterai.app.

---

## 3. Invite email — out of band, from Mark

Not in App Store Connect. This is the covering note that goes with the
invitation, and it carries the one thing that belongs to a relationship rather
than to a test.

> Hi —
>
> Thanks for agreeing to look at this. TestFlight will send you an invitation;
> installing takes a minute and there is nothing to sign up for.
>
> I have attached two things.
>
> **A short walkthrough.** About half an hour, and you can stop anywhere. Most
> of it works without any setup — please do the first part without adding an AI
> key, because that is how most families will run it.
>
> **A key file** (`.blasterkey`), which turns on the AI features at the end. It
> runs on my account, so there is nothing to pay for and no card to put down.
> Tap it and it should open straight into BlasterAI, which shows you what is in
> it and asks before installing. If you read mail in the Gmail app rather than
> Apple's Mail, it will download the file instead of opening it — in that case
> go to **Files → Downloads** and tap it there. If you have already added an
> OpenAI key of your own, it will decline rather than overwrite it, and tell you
> how to swap them.
>
> One last thing, and it is the part I most want your help with. **The default
> board is a placeholder.** Claude and I put it together by looking at existing
> boards and at roughly what is on my granddaughter's device. It is a first stab
> in what I hope is the right direction, and I do not want anyone to mistake it
> for the app — the app is the thing that lets you rebuild it.
>
> What I would really like is two or three SLPs working with us on what the
> default *should* be. If that is interesting to you, it is real design work and
> I would want to credit it as such: the board carrying the names of the
> clinicians who shaped it, not mine.
>
> Either way, tell me where the current one is wrong.
>
> Mark

---

## Notes for us, not for them

**Keyless first, and most of the walk is keyless.** Gate 6 was originally framed
defensively — "verify the app is usable with no key", as though keyless were a
review workaround to survive. It is not: it is the majority configuration on a
child's device, and it is also exactly the road a reviewer takes. Ordering the
walk this way puts the most eyes on the path most families live on.

**The reviewer walk is deliberately complete without a key.** A reviewer who
never adds one should still have seen the child surface, the board editor,
conceal, PDF export, image sets and Activity — enough to judge the app as what
it claims to be rather than as a demo waiting for a credential. The offer of a
funded key is at the end, as an option rather than a prerequisite.

**No feature list.** The order-of-the-pitch discipline in
`docs/final-countdown-plan.md` applies here too: no OBF/OBZ, packs by name,
Fitzgerald colours or Brown's Stages. A tester told to look at everything looks
at nothing. Coverage appears once, as a question rather than a feature.

**Patient mode is missing from the walk on purpose**, and is asked for
separately. Everyone here is told to choose Caregiver, so nobody exercises the
locked-down configuration a child's device actually runs in — Admin gated, the
caregiver menu restricted, no way out of the board by accident.

Mark is asking Kurt to do that pass specifically, standing in for Brandi: set a
device to Patient and then try to get out of it without knowing the PIN. It is a
safety property, it has only ever been tested by people who expected it to hold,
and the person best placed to break it is a UX researcher who did not build it.

**Round 1 is internal only**, so section 1 is not needed yet. It becomes required
at the first external invite, alongside Beta App Review and the gifted evaluator
keys.
