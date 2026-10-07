# Research: Verb-Rich Interaction Models for BOREAL

Seven games that map ~10–20 verbs onto few inputs, and what BOREAL should steal.

## Comparison

### Old School RuneScape — LMB default + RMB "Choose Option"
- **Primary verb:** LMB executes the *top entry* of a per-target option list, ordered by anticipated priority/distance ([OSRS Wiki: Choose Option](https://oldschool.runescape.wiki/w/Choose_Option)).
- **Secondary:** RMB lists all options; Menu Entry Swapper lets players reorder — the top entry *becomes* the left-click default ([Jagex: MES Overhaul](https://secure.runescape.com/m=news/a=97/menu-entry-swapper-overhaul---live-now?oldschool=1)).
- **Targeting:** hover highlight; the menu lists overlapping targets, which is what the 2003 redesign sold as fixing crowded-area misclicks: "left-button=action, right-button=menu" ([RSC Wiki update](https://classic.runescape.wiki/w/Update:Improved_user_interface)).
- **Praise/complaint:** zero-memorization, infinitely customizable; but the default guesses wrong (accidentally eating food — [RuneLite #12653](https://github.com/runelite/runelite/issues/12653)). **Lesson: the default must be user-correctable per object type.**

### Arma 3 — default-action key + scroll-wheel action menu
- **Primary:** "default action" (Space) on the aimed object; **secondary:** mouse-wheel-down opens one long vertical list ([keylayout PDF](http://cdn.akamai.steamstatic.com/steam/apps/107410/manuals/Arma_3_keylayout_ENG.pdf), [BIS Field Manual](https://community.bistudio.com/wiki/Arma_3:_Field_Manual_-_Vehicle_Controls)).
- **The canonical horror story:** "clunky and un-immersive… extremely prone to selecting the wrong action… context action sometimes just does not appear" ([BIS tracker T69085](https://feedback.bistudio.com/T69085)); the famous fan analysis proposes tap-Use / hold-Use-for-context-menu ([dslyecxi](https://dslyecxi.com/arma-3-fixing-the-action-menu)). Root cause: one flat list mixing world-context and self-actions, aim jitter mutating it. **Lesson: never make a scroll list the primary path; separate context vs self actions.**

### Project Zomboid — LMB contextual + RMB radial + E "first option"
- **Primary:** LMB is context-specific; **RMB = radial menu of all interactions**; **E performs the first option without showing it**, hold E for the follow-up (climb through the opened window) ([pzwiki: Controls](https://pzwiki.net/wiki/Controls)).
- **Complaints:** RMB doubles as fight-mode → menu/attack conflicts ([forum bug](https://theindiestone.com/forums/topic/28351-context-menu-while-fighting/)); B42 removing RMB context menus caused sustained revolt ([r/projectzomboid](https://www.reddit.com/r/projectzomboid/comments/1hosfhk/bring_back_right_click_context_menu_for_simple/)). **Lesson: the radial is beloved as the discoverability escape hatch; removing it is a revolt.**

### Dinkum — context interact + toolbelt; held item = verb
- **Primary:** one interact key for pickup; LMB "Use Selected Item in Toolbelt" — the held tool fully determines the verb (Stardew pattern; [Dinkum wiki: Controls](https://dinkum.fandom.com/wiki/Controls), [Quick Toolbar](https://dinkum.fandom.com/wiki/Inventory)); toolbelt via 1–9/wheel.
- **Complaints:** not the verb scheme but hidden mappings (cook only works from quickbar, unexplained) ([LadiesGamers](https://ladiesgamers.com/dinkum-review/)). **Lesson: item→verb mappings must be visible on the HUD.**

### The Long Dark — context prompt + hold-Space radial + 1–4 hotkeys
- **Primary:** context-sensitive prompt on the aimed target; **secondary:** hold Space → radial of *categories* (Light/Food/Campcraft/First Aid/Drinks) → action; 1–4 = light source, weapon, bait, light fire ([TLD wiki: Radial Menu](https://thelongdark.fandom.com/wiki/Radial_Menu), [guide](https://survivethelongdark.com/basics.php?page=controls)).
- **Dev design goal:** keep the player "'in the world,' rather than buried in menus" ([Steam dev reply](https://steamcommunity.com/app/305620/discussions/0/357285562495578535/?ctp=2)) — but the launch radial (symbols only, hold-only) drove players away; a whole QoL mod restores keyboard-first flow ([TLD-QoL](https://github.com/No3371/TLD-QoL)). **Lesson: text labels, tap-open, and direct keys for the top ~4 verbs.**

### Minecraft — one Use key; verb = f(held item, faced block)
- **Primary:** RMB "Use Item/Place Block"; **if held item and faced block are both interactable, the block wins** — a documented disambiguation rule ([minecraft.wiki: Controls](https://minecraft.wiki/w/Controls)).
- Universally praised as the most learnable scheme; cost: verbs that aren't item×block need screens. **Lesson: a deterministic held-item+target rule beats guessing; publish the priority rule.**

### Zelda BotW/TotK — one context button with a changing verb label
- **Primary:** A="Interact" and the prompt renames itself per target ("Talk," "Pick up") ([BotW controls](https://gamefaqs.gamespot.com/switch/189707-the-legend-of-zelda-breath-of-the-wild/faqs/74495/controls)); Nintendo's CEDEC talks credit this "verbs disappear" design for discoverability ([Game Developer](https://www.gamedeveloper.com/design/5-design-lessons-learned-from-i-the-legend-of-zelda-breath-of-the-wild-i-)).
- **Complaints:** one-button overload grabs the wrong thing when targets overlap ([TotK retrospective](https://andrewwhitego.wordpress.com/2023/07/25/the-legend-of-zelda-tears-of-the-kingdom-2023-retrospective-review-part-6-enemies-and-combat)); no remapping ([NintendoLife](https://www.nintendolife.com/features/soapbox-zelda-tears-of-the-kingdom-straight-up-fails-in-just-one-respect-accessibility)). **Lesson: always show the verb's name before it's pressed.**

## Recommended spec for BOREAL

**BotW labeled context key (E) + OSRS hold-for-menu + Minecraft held-item override + TLD hotkeys** — the consensus end-state of every critique above.

1. **Smart default: deterministic priority table, not fuzzy guessing.** Each interactable exposes actions with static priority; nearest-in-crosshair-cone wins; prompt shows the verb: `[E] Feed fire`, `[hold] 4 more`. Defaults: campfire→Feed (fuel held) else Light; pot at fire→Boil; water→Drink; snare run→Set/Check; ice hole→Fish; shelter→Sleep at night / Repair by day; build mode + ground→Place. Treat/Flare never steal the default (panic verbs need certainty). If the player opens the menu twice on the same object type, offer "make this the default" (OSRS MES lesson).
2. **Menu with pointer lock: keep the lock.** Tap E = default; hold RMB (~150 ms) = compact vertical list of the target's actions + a separate self-actions section (Arma lesson). Navigate with wheel or A/D, confirm with E/click, close with RMB/Esc — no cursor, no lock release (browser re-lock needs a user gesture; Esc-unlock is jarring). Non-modal: walking away cancels (Zomboid); halve look-sensitivity while open. Real-cursor menus only on pause/inventory screens.
3. **Held-item mode: yes, narrow.** Held tool overrides the target default (axe+tree→Chop, wire+run→Set snare, cup+water→Fill); empty hands use the table; ties go to the target (Minecraft rule, stated in the help screen). HUD always shows held item + resulting verb (Dinkum lesson).
4. **Keyboard fallbacks (TLD lesson — top verbs get direct keys):** `1` Eat, `2` Drink, `Space`/`4` Light-or-Feed fire, `Tab` tool/craft wheel, `T` Treat, `H` Flare. Everything else (boil, cook, snare, fish, shelter, signal smoke) lives behind E/menu. Rebindable from day one (Arma/BotW lesson).

**Why:** ~90% of actions become one labeled keypress (BotW); the 15-verb tail is discoverable without memorization (OSRS/Zomboid); panic verbs stay instant (TLD); nothing needs a free mouse cursor (pointer-lock-safe, unlike a literal OSRS port).
