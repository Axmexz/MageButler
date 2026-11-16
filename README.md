# MageButler: Because Mages Deserve a Butler Too!

I got sick and tired of doing everything manually as a Mage. Constantly
restocking reagents, conjuring food and water, handing out buffs, trading
supplies, and digging through spellbooks just to open a portal.

So I made MageButler!

A lightweight, all-in-one Mage utility addon that takes care of the boring
stuff, so you can focus on what really matters: throwing fireballs, topping the
damage meters, and pretending you're not just the raid's personal vending
machine.

## What does MageButler do?

- **Smart Reagent Restocking:** Automatically stock up when visiting vendors.
- **Portal & Teleport Menu:** All your travel spells in one convenient radial menu.
- **Food & Water:** Quick access to conjuring without digging through your spellbook.
- **Auto-Trade:** Automatically fill trades with food and water.
- **Buff Watch:** Keep your party and raid buffed with intelligent Arcane
  Intellect and Arcane Brilliance management.
- **Portal Announcements:** Tell your group, or the whole street, that the
  portal is open, in your own words.
- **Fully Customizable:** Adjust everything to your liking.

Less clicking. Less micromanagement. More pew pew.

Because being a Mage shouldn't feel like a full-time catering job.

## Requires

**WoW Forever** (interface 16001). MageButler uses that client's APIs and will
not work on Retail, Classic Era or the TBC Anniversary realms.

It only wakes up on Mage characters; on anything else it stays out of the way.

## Installing

1. Put the `MageButler` folder in your `Interface\AddOns` directory, so that
   `Interface\AddOns\MageButler\MageButler.toc` exists.
2. Start the game, or `/reload` if it was already running.

## Using it

Everything starts at the orb, which you can drag wherever you like.

| Click | What it does |
|---|---|
| Left | Open the radial menu |
| Right | Cast whichever buff your group needs most |
| Ctrl + right | The Buff Watch player list |
| Shift + right | Settings |
| Middle | The preparation check |

The radial menu holds Portals, Teleports, Conjure Water, Conjure Food, Mana Gem
and the trade assistant. Portals and teleports list only the destinations you
have actually learned.

`/mb` opens the settings. It also takes `menu`, `orb`, `ready`, `buffs`,
`fill`, `reset` and `debug`; `/mb help` lists them. `/magebutler` works too.

Portal announcements are off until you switch them on under Settings,
Announcements, where you also write the message: `{portal}` becomes the
destination and `{player}` your name. Party and raid chat are announced by
themselves as the portal opens. `/say` and `/yell` are different: outside a
dungeon or raid the game only lets an addon speak there at your own click, so
MageButler shows a button when the portal opens and your click on it sends the
message. A portal that is interrupted is never announced, and one cast is
announced once.

If a counter ever looks wrong, `/mb debug` prints what MageButler has counted
beside what the game reports at that moment, with a short history of how it got
there. It survives a `/reload`, so it is worth pasting into a bug report even
after you have reloaded to clear the problem.

Every spell is cast by your own click. MageButler never casts for you, and it
never accepts a trade for you.

## Licence

All Rights Reserved. See [LICENSE.txt](LICENSE.txt). You are welcome to use
MageButler; you may not redistribute or modify it without permission.
