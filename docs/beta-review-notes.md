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
> **No account, no sign-in, no server.** Everything is stored on the device and
> synced through the user's own iCloud. Nothing reaches a server we operate.
>
> **Nothing needs configuring to review it.** First launch loads a complete
> 492-word vocabulary and working boards. Tap a tile and the app speaks.
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
> 1. At onboarding choose **Caregiver**, then **Skip** at the API key step.
> 2. Tap tiles on the home board — each speaks immediately.
> 3. Tap a tile with a small arrow badge to open another page; the first cell of
>    every page returns home.

> 4. **Touch and hold the Home tile for about half a second** — longer than the
>    taps above, which speak instantly. That opens the caregiver menu; choose
>    **Admin**. Admin is a row of tabs: Now, Profiles, Scenes, Device, Activity.
> 5. **Scenes** → tap the board we ship. It will offer to make you an editable
>    copy and switch to it; accept. The boards we supply are read-only so an app
>    update can never overwrite a caregiver's work.
> 6. In your copy: open a page → **Select Tiles** → tick a few → **Conceal**.
>    Concealed words stay on the board for the caregiver and disappear for the
>    child.
> 7. **Scenes** → touch and hold a board → **Share** → **Printable PDF**. The
>    same board as paper, which is what many classrooms still run on.
> 8. **Device** → **Image Set** → switch styles. Every word is drawn in every
>    style; the whole board changes and nothing goes missing.
> 9. **Activity** → what was said, and which words have never been used.
>
> **Listed under Education, not Kids.** The person who installs, configures and
> maintains the app is an adult caregiver or speech-language pathologist. The
> child is who it is *for*, not who sets it up. Caregiver settings sit behind an
> optional Face ID / PIN gate, and a device can be put in a patient mode that
> keeps a child inside the board.
>
> **Privacy: no data collected.** A child's words and usage stay on the device
> and in the user's own iCloud. https://blasterai.app/privacy
>
> If you would like to exercise the AI path, we can supply a funded API key —
> contact us and we will send one.

---

## 2. What to Test — for testers, per build

> Thanks for looking at this. About half an hour, and you can stop anywhere.
>
> At onboarding, choose **Caregiver** as the device role, and **Skip** the API
> key step. Most of this needs no key, and that is the configuration most
> families will run.
>
<!-- pdf-only -->
> ### The child's side
>
> 1. **Tap tiles on the home board.** Each word should speak the instant you
>    touch it — no wait, no spinner.
> 2. **Follow a page link** into another page and back. Home is the first cell of
>    every page, always in the same place — that is deliberate, and we want to
>    know whether it feels obvious or hidden.
>
> ### Getting to the caregiver side
>
> 3. **Touch and hold the Home tile** → caregiver menu → **Admin**. Tell us
>    whether you would have found that on your own.
>
> ### Making a board of your own
>
> 4. **Scenes → New Scene.** Take either route:
>    - a ready-made example, or
>    - **Build from Collections** — tick vocabulary packs and word classes and
>      let it assemble a board.
> 5. Open your new board, open a page, and tap **Select Tiles**. With several
>    ticked, try **Conceal** and **Delete**. Conceal keeps a word on the board for
>    you and hides it from the child; delete removes it. We would like to know
>    whether that distinction is clear without being told.

> 6. Rename a page, and move tiles between pages.
>
> Nothing above needs the guides, but they exist if you want them — and we would
> like to know whether you needed them:
>
> - **blasterai.app/guides/make-your-first-scene**
> - **blasterai.app/guides/pages-and-navigation**
> - **blasterai.app/guides/adding-vocabulary**
>
<!-- /pdf-only -->
> ### Folder colours — new in this build
>
> The top row of the home board is folders. They used to be one blue. Now each
> takes the colour of the words behind it: **people** yellow for pronouns,
> **actions** green for verbs, **describe** blue, **questions** purple.
> **groups** and **keyboard** stay blue — a folder of folders is not a kind of
> word.
>
> This is the part we are least sure about.
>
> A. **Does the top row tell you anything?** A green folder standing over a
>    green block of verbs — help, or just more colour?
> B. **Turn it off.** Admin → the child's profile → **Folder Color** → *Always
>    the Link Color*. Which do you prefer, and **for whom** — the child, or you?
> C. **Print it both ways** (Share → Printable PDF). We suspect the answer
>    differs on paper, where nothing navigates and a folder is a landmark
>    rather than a category. Tell us if that is nonsense.
>
<!-- pdf-only -->
> D. **Change one by hand.** Page editor → a folder tile → **Folder color**:
>    *Automatic* (it names what it worked out), *Page Links*, or a word type.
>    Set one, then add words to the page behind it — a folder you chose stays
>    put, one left on Automatic follows the page.
>
<!-- /pdf-only -->
> If you use WordPower or TouchChat, we would especially like to know whether
> this reads the way the board you already know does.
>
<!-- pdf-only -->
> ### Taking a board off the device
>
> 7. **Scenes → touch and hold a board → Share.** Try **Printable PDF** — pick a
>    layout and paper size. Plenty of classrooms still run on paper, and a board
>    that cannot be printed is only half a board.

> 8. Same Share sheet, two more destinations:
>    - **Tile images** — the pictures as image files, for a worksheet or a label.
>    - **Blaster scene** — the board as a file. Text or email it to another
>      device running BlasterAI and tapping it rebuilds the board, artwork
>      included. That is how a therapist hands a board to a family.
>
> ### Looking at how it is used
>
> 9. **Device → Image Set.** Switch styles. Every word is drawn in every style.
> 10. **Activity.** The log of what was said, and **Coverage** — which of the
>     board's words have and have not been used. Does that screen answer a
>     question you would actually ask about a child?
<!-- /pdf-only -->
>
> ### Now add a key
>
> Add an OpenAI key in **Admin → Device**, or open the key file if one was sent
> to you.
>
> The full half-hour walk — the child's side, building a board, printing and
> sharing it — is in the PDF that came with your invitation. Below is what is
> new in this build and what we would most like you to push on.
>
> First, the tray. Tiles you tap collect along the top.
> **Tap a tile in the tray to take it back out.**
> Beside them are **Play** and **Clear**. At Stage IV+ there is also a
> backspace — see below.
>
<!-- pdf-only -->
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
<!-- /pdf-only -->
>
> ### Stage IV+ — the board as something you write with
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
> ### What we most want to hear
>
> - **The starting board is our first attempt, not a recommendation.** Where is
>   it wrong?
> - **Folder colours:** on or off, and does your answer change between the
>   screen and the printed sheet?
> - **Stage IV+:** is a tray of plain words right for a child who is building
>   sentences, or does it take away something the pictures were doing?
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
