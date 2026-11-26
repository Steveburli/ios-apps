# Fishers Cruise

An open-world driving game for the PC browser, set on the real map of Fishers, Indiana and the edges of
Carmel, Noblesville, McCordsville and Lawrence. Walk around, borrow cars, drive the real roads, ride bikes on the Monon and Nickel Plate trails, talk to
people, take on ten jobs around town and hunt for 30 golden fish. No weapons and no violence: cars bump,
people jump out of the way, and nobody gets hurt.

Everything is built with [three.js](https://threejs.org) from OpenStreetMap data. Roads, buildings,
parks, lakes, parking lots and driveways come from the map, so your own street is in there.

## Play

Open `web/index.html` through any local web server (browsers block the map files when the page is opened
straight from disk):

- Windows: double-click `play.bat` (uses Python if installed, otherwise Node).
- Mac/Linux: `cd web && python3 -m http.server 8000`, then open http://localhost:8000.

### Controls

| | Keyboard and mouse | Gamepad |
|---|---|---|
| Walk / steer | W A S D | Left stick |
| Gas / brake and reverse | W / S | Right / left trigger |
| Run | Shift | A (hold) |
| Jump / handbrake | Space | A / B |
| Get in or out, talk | E | X or Y |
| Look around | Mouse | Right stick |
| Map (click to set a waypoint) | M | Back/View |
| Horn (bell on a bike) | H | Right stick click |
| Pedal hard on a bike | Shift + W | A + right trigger |
| Quit the current job | X | |

## Real 3D city (Google Photorealistic 3D Tiles)

With a Google Maps Platform API key, the game draws the city from Google's photorealistic 3D model
instead of the simplified preview: the real houses, trees, storefronts and terrain, to scale. OpenStreetMap
data stays underneath for the road network (traffic, GPS, trail rides) and is projected into the same
Earth-centred frame, so the two line up.

1. In Google Cloud Console, enable the **Map Tiles API** for the project that owns your key.
2. Restrict the key to the address you play from (Application restrictions: Websites, for example
   `http://localhost:8000/*`) and to the Map Tiles API.
3. Start the game with `play.bat` and paste the key into **Real 3D city** on the title screen.
   The key is saved only in that browser's local storage and is sent only to Google.

Notes:
- The real city does not load inside the Claude artifact link (the link blocks requests to other sites).
  Without a key, or if Google refuses it, the game says why and starts the map preview.
- Google's credits are shown at the bottom of the screen while the tiles are on, as their terms require.
  Their terms also ask for the Google logo image; the text "Google" stands in for it for now.
- Tiles stream live and are not saved; usage beyond Google's free monthly allowance is billed to your project.
- Interiors are not part of Google's tiles.

### What is real and what is generated

- **Real**: in real-city mode, everything you see of the city is Google's 3D model. In both modes, road and
  trail positions, building outlines, parks, water and bike parking come from OpenStreetMap.
- **Preview estimates**: without the 3D tiles, buildings are the real outlines extruded to an estimated
  height in one neutral colour. Trees and lane markings are not drawn because the map does not record them.
- **Generated on purpose**: the moving parts of the game: people, traffic, parked cars, bikes, the
  characters who give out jobs, and the jobs themselves.

## Jobs

1. **Welcome to Fishers**: Mom, at home. Pick up a cake and library books in the family minivan.
2. **Pizza Rush**: deliver three pizzas before they go cold.
3. **Field Trip**: drive a school bus to Conner Prairie without making the kids carsick.
4. **Lost Ducklings**: find eight ducklings around Geist Reservoir.
5. **Grand Tour**: race to Noblesville Square, Hamilton Town Center and Ruoff Music Center. Wins a sports car.
6. **Tee Time**: get Grandpa Joe from the Carmel Arts District to Topgolf on time.
7. **Roundabout Rally**: a timed run through Carmel's roundabouts.
8. **Ice Cream Emergency**: catch the ice cream truck.
9. **Farmers Market Run**: collect produce from farms on the edge of town.
10. **Picture Perfect**: photograph six landmarks.
11. **Nickel Plate Pedal**: a timed bike ride down the Nickel Plate Trail.
12. **Monon Mileage**: a timed bike ride on the Monon Trail through Carmel.

## Biking

The Monon Trail and Nickel Plate Trail show green on the maps. Bikes wait at the real bike-parking spots
along both trails (from OpenStreetMap), and there is a bike in your driveway. Other cyclists and walkers
use the trails too. On a bike, the GPS routes you along trails and quieter roads.

Progress (money, finished jobs, golden fish) is saved in the browser.

## Rebuilding the map

The game reads compact binary map files from `web/data/`. To regenerate them from fresh OpenStreetMap data:

```bash
python3 tools/fetch_osm.py /tmp/osm          # downloads from the Overpass API (takes a while)
python3 tools/build_map.py /tmp/osm web/data # writes roads, buildings, areas and lines (.b64.txt) plus meta.json
```

The map area is set by `BBOX` in `fetch_osm.py`. If you change it, update the bounds in `build_map.py` too.

## Code layout

| File | What it does |
|---|---|
| `web/game/main.js` | Boot, game loop, player on foot, camera, day and night, saving |
| `web/game/world.js` | Builds roads, areas, buildings and trees; collisions and map queries |
| `web/game/vehicle.js` | Arcade car physics |
| `web/game/traffic.js` | Traffic AI on the road graph, parked cars, pedestrians |
| `web/game/nav.js` | GPS routing (A*) over the road graph |
| `web/game/missions.js` | Jobs, mission givers, golden fish |
| `web/game/hud.js` | Minimap, full map, prompts, dialogue |
| `web/game/models.js` | Procedural cars, people and textures |
| `web/game/audio.js` | Synthesised engine, horn and chimes |

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL).
