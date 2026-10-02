# World design

Open-world military base. Catalogue (built as `Part` tables):
- Buildings: barracks, HQ, hangar, mess hall, generator shed, fuel depot tanks, water tower, watchtower, guard post, bunker, helipad, radio mast, radar dish.
- Fortifications: chain-link fence with razor wire, T-walls, Hesco barriers, sandbags, gate, checkpoint barrier.
- Vehicles: jeep, truck, APC, tank, helicopter.
- Props: crates, barrels, pallets, tents, camo netting, floodlights, signs, flag.
- Weapons: rifle, pistol, rocket launcher, grenade, mounted turret.
- Characters: rifleman, officer, sniper, guard, enemy variant.
Layout (see `Game/Base/Layout.odin`): a fenced circular compound of radius 62 m on the plateau, gate on the south side with guard posts, sandbags and Hesco barriers outside; command area (HQ, three barracks, mess hall, generator, fuel, water tower, radar, mast, bunkers, T-walls) in the north and west, airfield (hangar, helipad and helicopter) in the east, motor pool (jeeps, trucks, carriers, tanks under a camouflage net) by the gate, a supply yard, tents, and floodlights.
Gameplay: walk/run/jump/crouch, hitscan and projectile weapons, health, enemy AI (patrol, spot, chase, shoot, dead). Out of scope: audio, inventory, quests, save/load, multiplayer.

## Combat rules (numbers live in `Game/Gameplay`)
- Enemy senses: sight 50 m inside a 100 degree cone, plus awareness of anything within 5 m from any direction; a wall or hill between eye and target blocks sight. Heard shots alert enemies within 70 m. An enemy turns at 3.5 rad/s, so flanking works.
- Enemy fire: after opening fire an enemy takes 0.6 s to settle its aim; it shoots every 0.35 s for 4 damage; the hit chance is `0.35 - 0.007 * distance` clamped to 0.05-0.3; attacks start within 30 m.
- Player: 100 health; regenerates 8 per second after 5 s without being hit. Starts outside the garrison's sight at (0, 100), south of the gate.
- The player has a body (a rifleman skeleton, seen when looking down and in shadows) standing 0.25 m behind, 0.2 m right of and 0.15 m above the eye, holding the selected weapon in its right hand.
