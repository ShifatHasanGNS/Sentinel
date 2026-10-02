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
