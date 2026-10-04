# OUSL Student Journey Planner (SWI-Prolog)

A student anywhere in Sri Lanka picks a start location. The destination is always the
**Open University of Sri Lanka, Nawala campus**. For every travel mode the app shows
distance, time and estimated cost, a student message, and a rotating navigation map.

Modes: Walk, Bike (motorbike), Bus, Highway bus, Train, Three-wheeler.

## Run

```powershell
& 'C:\Program Files\swipl\bin\swipl.exe' -q -s app_server.pl -g start
```

Open http://localhost:8080/. Render deploy is unchanged (Dockerfile + render.yaml).

## Structure

```text
app_server.pl                   # unchanged server entrypoint
backend/smart_route_api.pl      # Prolog facts, rules and HTTP API
frontend/route_finder_ui.html   # HTML + CSS + JS (MapLibre GL map with rotation)
```

## Prolog knowledge base (backend/smart_route_api.pl)

- `station/6` - railway stations, line and km from Colombo Fort (approximate).
- `highway_stop/6` - highway/expressway bus towns and corridors from bustimetable.lk.
- `fare/3`, `train_fare/3` - fare rules (estimates, not official tariffs).
- `campus_coord/2`, `campus_station/1` - the destination.
- Rules: `walk_option`, `bike_option`, `bus_option`, `highway_option`, `train_option`,
  `three_wheel_option`, `recommend/2`, `student_message/6`.

## API

| Endpoint | Purpose |
| --- | --- |
| `POST /api/plan` | `{start_coord:{lat,lon,name}}` returns all mode options, message, geometry |
| `POST /api/route` | `{start_coord, mode}` returns one mode and its geometry |
| `GET /api/campus` | destination details |
| `GET /api/stations` | railway stations used by the train rules |
| `GET /api/highway` | highway bus towns/corridors |
| `GET /api/search?q=` | Nominatim place search (Sri Lanka only) |
| `GET /api/reverse?lat=&lon=` | reverse geocoding |

## Notes and limits

- Walking uses a 5 km/h pace on the OSM foot router; the other road modes use the car router.
- Bus, highway bus, train and three-wheeler costs are estimates. Highway bus departure times
  and seat booking are not available from the source page; the app lists corridors only.
- The train line on the map is a schematic station-to-station line, not exact track.
- Public OSRM/Nominatim servers are rate limited and have no uptime guarantee.
