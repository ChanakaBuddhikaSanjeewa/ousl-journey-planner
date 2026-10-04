:- encoding(utf8).

% =====================================================================
%  Smart Route Finder - OUSL Student Journey Planner (SWI-Prolog backend)
%
%  A student anywhere in Sri Lanka picks a start point; the destination is
%  always the Open University of Sri Lanka (OUSL), Nawala campus.
%  For every travel mode we compute distance, time and an estimated cost:
%     walk | bike (motorbike) | bus | highway bus | train | three-wheeler
%
%  Real road geometry/steps come from free OpenStreetMap-based routers
%  (OSRM). Fares, train network and highway-bus corridors are Prolog facts.
% =====================================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_parameters)).
:- use_module(library(uri)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).

:- http_handler(root(api/plan),     plan_api,     []).
:- http_handler(root(api/route),    route_api,    []).
:- http_handler(root(api/campus),   campus_api,   []).
:- http_handler(root(api/stations), stations_api, []).
:- http_handler(root(api/highway),  highway_api,  []).
:- http_handler(root(api/search),   search_api,   []).
:- http_handler(root(api/reverse),  reverse_api,  []).

% ---------------------------------------------------------------------
%  1. Knowledge base
% ---------------------------------------------------------------------

campus_name("Open University of Sri Lanka (Nawala Campus)").
% Approximate position of the main OUSL campus, Nawala. Adjust if needed.
campus_coord(6.8838, 79.8887).
% Closest Kelani Valley line station to the campus.
campus_station(kirulapona).

% station(Id, Name, Lat, Lon, Line, KmFromColomboFort)   (approximate values)
station(colombo_fort,  'Colombo Fort',   6.9335, 79.8503, hub,      0).
station(maradana,      'Maradana',       6.9283, 79.8645, hub,      2.4).
% Main line
station(ragama,        'Ragama',         7.0267, 79.9223, main,    14).
station(gampaha,       'Gampaha',        7.0917, 79.9997, main,    27).
station(veyangoda,     'Veyangoda',      7.1572, 80.0960, main,    37).
station(mirigama,      'Mirigama',       7.2430, 80.1275, main,    52).
station(polgahawela,   'Polgahawela',    7.3333, 80.3000, main,    94).
station(rambukkana,    'Rambukkana',     7.3256, 80.3922, main,   103).
station(kadugannawa,   'Kadugannawa',    7.2536, 80.5231, main,   112).
station(peradeniya,    'Peradeniya Junction', 7.2578, 80.5930, main, 115).
station(kandy,         'Kandy',          7.2893, 80.6338, main,   120).
station(gampola,       'Gampola',        7.1650, 80.5700, main,   128).
station(nawalapitiya,  'Nawalapitiya',   7.0570, 80.5330, main,   145).
station(hatton,        'Hatton',         6.8918, 80.5953, main,   173).
station(nanu_oya,      'Nanu Oya',       6.9427, 80.7430, main,   183).
station(bandarawela,   'Bandarawela',    6.8260, 80.9890, main,   245).
station(ella,          'Ella',           6.8660, 81.0470, main,   263).
station(badulla,       'Badulla',        6.9890, 81.0550, main,   292).
% Northern line (branches at Polgahawela)
station(kurunegala,    'Kurunegala',     7.4900, 80.3620, northern, 116).
station(anuradhapura,  'Anuradhapura',   8.3170, 80.4130, northern, 205).
station(vavuniya,      'Vavuniya',       8.7550, 80.5000, northern, 255).
station(jaffna,        'Jaffna',         9.6600, 80.0210, northern, 396).
% Coastal line
station(mount_lavinia, 'Mount Lavinia',  6.8300, 79.8630, coastal,  12).
station(moratuwa,      'Moratuwa',       6.7810, 79.8830, coastal,  19).
station(panadura,      'Panadura',       6.7110, 79.9040, coastal,  27).
station(kalutara_south,'Kalutara South', 6.5780, 79.9600, coastal,  43).
station(beruwala,      'Beruwala',       6.4780, 79.9810, coastal,  55).
station(aluthgama,     'Aluthgama',      6.4330, 80.0010, coastal,  64).
station(ambalangoda,   'Ambalangoda',    6.2350, 80.0560, coastal,  86).
station(hikkaduwa,     'Hikkaduwa',      6.1410, 80.1000, coastal,  98).
station(galle,         'Galle',          6.0330, 80.2170, coastal, 116).
station(weligama,      'Weligama',       5.9730, 80.4290, coastal, 144).
station(matara,        'Matara',         5.9460, 80.5440, coastal, 160).
% Kelani Valley line (serves the campus area)
station(cotta_road,    'Cotta Road',     6.9140, 79.8780, kvalley,   4.9).
station(narahenpita,   'Narahenpita',    6.8980, 79.8790, kvalley,   7).
station(kirulapona,    'Kirulapona',     6.8820, 79.8770, kvalley,   9).
station(nugegoda,      'Nugegoda',       6.8700, 79.8940, kvalley,  11).
station(maharagama,    'Maharagama',     6.8480, 79.9260, kvalley,  14).
station(homagama,      'Homagama',       6.8440, 80.0020, kvalley,  22).
station(padukka,       'Padukka',        6.8420, 80.0950, kvalley,  29).
station(avissawella,   'Avissawella',    6.9540, 80.2100, kvalley,  49).

% line_speed(Line, MinutesPerKm) - average including station stops
line_speed(main,     1.5).
line_speed(northern, 1.35).
line_speed(coastal,  1.2).
line_speed(kvalley,  1.9).
line_speed(hub,      1.9).

% highway_stop(Town, Lat, Lon, Corridor, Terminal, PublishedHours)
% Corridors listed on https://bustimetable.lk/tag/expressway-bus/
% PublishedHours is the travel time quoted there, or none.
highway_stop('Kandy',         7.2906, 80.6337, 'Kandy - Colombo (Makumbura) expressway bus', 'Makumbura / Colombo', 3).
highway_stop('Tangalle',      6.0240, 80.7970, 'Tangalle - Makumbura highway bus',           'Makumbura',          none).
highway_stop('Middeniya',     6.2000, 80.8900, 'Middeniya - Colombo highway bus',            'Colombo',            3.5).
highway_stop('Kamburupitiya', 6.0700, 80.5650, 'Kamburupitiya - Colombo highway bus',        'Colombo',            none).
highway_stop('Baddegama',     6.1750, 80.1750, 'Baddegama - Colombo highway bus',            'Colombo',            none).
highway_stop('Kataragama',    6.4130, 81.3350, 'Kataragama - Kadawatha highway bus',         'Kadawatha',          4).
highway_stop('Ampara',        7.2975, 81.6820, 'Ampara - Colombo highway bus',               'Colombo',            6).
highway_stop('Badulla',       6.9934, 81.0550, 'Badulla - Maharagama highway bus (via Ella, Wellawaya, Southern Expressway)', 'Maharagama', none).
highway_stop('Ella',          6.8667, 81.0466, 'Badulla - Maharagama highway bus (via Ella, Wellawaya, Southern Expressway)', 'Maharagama', none).
highway_stop('Wellawaya',     6.7333, 81.1000, 'Badulla - Maharagama highway bus (via Ella, Wellawaya, Southern Expressway)', 'Maharagama', none).
highway_stop('Negombo',       7.2086, 79.8358, 'Negombo - Makumbura highway bus',            'Makumbura',          none).

% fare(Mode, Km, Lkr) - rough estimates, NOT official tariffs
fare(foot, _, 0).
fare(bike, Km, C)        :- C is ceiling(Km * 10).                  % petrol, motorbike
fare(bus, Km, C)         :- Raw is max(30, Km * 3.0),  C is ceiling(Raw / 5) * 5.
fare(highway, Km, C)     :- Raw is max(150, Km * 7.0), C is ceiling(Raw / 10) * 10.
fare(three_wheel, Km, C) :- Raw is 100 + max(0, Km - 1) * 90, C is ceiling(Raw / 10) * 10.

% train_fare(Class, Km, Lkr)
train_fare(third,  Km, C) :- C is max(20, ceiling(Km * 2.0 / 5) * 5).
train_fare(second, Km, C) :- C is max(40, ceiling(Km * 3.7 / 5) * 5).

% ---------------------------------------------------------------------
%  2. Geometry helpers
% ---------------------------------------------------------------------

haversine(Lat1, Lon1, Lat2, Lon2, Km) :-
    R is pi / 180,
    DLat is (Lat2 - Lat1) * R,
    DLon is (Lon2 - Lon1) * R,
    A is sin(DLat / 2) ** 2 + cos(Lat1 * R) * cos(Lat2 * R) * sin(DLon / 2) ** 2,
    Km is 12742 * asin(sqrt(A)).

in_sri_lanka(Lat, Lon) :-
    Lat >= 5.7, Lat =< 10.0, Lon >= 79.4, Lon =< 82.1.

r1(X, Y) :- Y is round(X * 10) / 10.0.

nearest_station(Lat, Lon, Id, Km) :-
    findall(D-I, ( station(I, _, SLat, SLon, _, _),
                   haversine(Lat, Lon, SLat, SLon, D) ), Pairs),
    keysort(Pairs, [Km-Id|_]).

nearest_highway_stop(Lat, Lon, stop(Town, Corr, Term, Hours), Km) :-
    findall(D-stop(T, C, Tm, H),
            ( highway_stop(T, SLat, SLon, C, Tm, H),
              haversine(Lat, Lon, SLat, SLon, D) ), Pairs),
    keysort(Pairs, [Km-stop(Town, Corr, Term, Hours)|_]).

station_point(Id, _{lat:Lat, lon:Lon}) :-
    station(Id, _, Lat, Lon, _, _).

station_name(Id, Name) :-
    station(Id, Name, _, _, _, _).

thin_points(Pts, Max, Out) :-
    length(Pts, N),
    (   N =< Max
    ->  Out = Pts
    ;   Step is ceiling(N / Max),
        every_nth(Pts, Step, 0, Out0),
        last(Pts, L),
        last(Out0, L0),
        (   L0 == L -> Out = Out0 ; append(Out0, [L], Out) )
    ).

every_nth([], _, _, []).
every_nth([P|T], Step, I, Out) :-
    (   I mod Step =:= 0 -> Out = [P|Rest] ; Out = Rest ),
    I1 is I + 1,
    every_nth(T, Step, I1, Rest).

% ---------------------------------------------------------------------
%  3. Routing adapters (OSRM, OpenStreetMap data)
% ---------------------------------------------------------------------

profile_url(foot, 'https://routing.openstreetmap.de/routed-foot/route/v1/driving/').
profile_url(car,  'https://routing.openstreetmap.de/routed-car/route/v1/driving/').
profile_url(car,  'https://router.project-osrm.org/route/v1/driving/').

osrm_profile_route(Profile, SLat, SLon, DLat, DLon, Route) :-
    profile_url(Profile, Base),
    osrm_request(Base, SLat, SLon, DLat, DLon, Route),
    !.

osrm_request(Base, SLat, SLon, DLat, DLon, Route) :-
    format(string(URL),
           '~w~w,~w;~w,~w?overview=full&geometries=geojson&steps=true',
           [Base, SLon, SLat, DLon, DLat]),
    catch(fetch_json(URL, Json), E,
          ( format(user_error, 'OSRM request failed: ~q~n', [E]), fail )),
    get_dict(code, Json, Code), Code == "Ok",
    get_dict(routes, Json, [R|_]),
    get_dict(distance, R, Meters),
    get_dict(duration, R, Seconds),
    Km is Meters / 1000.0,
    get_dict(geometry, R, G),
    get_dict(coordinates, G, Coords),
    maplist(coord_point, Coords, Pts0),
    thin_points(Pts0, 1200, Pts),
    findall(St, ( get_dict(legs, R, Legs), member(L, Legs),
                  get_dict(steps, L, Ss), member(S0, Ss),
                  step_summary(S0, St) ), Steps),
    Route = _{km:Km, seconds:Seconds, geometry:Pts, steps:Steps}.

fetch_json(URL, Json) :-
    setup_call_cleanup(
        http_open(URL, In, [ timeout(15),
                             request_header('User-Agent', 'SmartRouteFinder/2.0 (OUSL student practical)') ]),
        json_read_dict(In, Json),
        close(In)).

coord_point([Lon, Lat], _{lat:Lat, lon:Lon}).

step_summary(Step, _{distance:D, duration:Dur, name:Name, instruction:Instr, lat:Lat, lon:Lon}) :-
    get_dict(distance, Step, D),
    get_dict(duration, Step, Dur),
    (   get_dict(name, Step, N0), N0 \== "" -> Name = N0 ; Name = "the road" ),
    get_dict(maneuver, Step, M),
    get_dict(location, M, [Lon, Lat]),
    (   get_dict(type, M, T) -> true ; T = "continue" ),
    (   get_dict(modifier, M, Mod) -> true ; Mod = "" ),
    step_text(T, Mod, Name, Instr).

step_text(T, Mod, Name, Text) :-
    term_to_atom_safe(T, TA),
    term_to_atom_safe(Mod, MA),
    step_text_(TA, MA, Name, Text), !.

term_to_atom_safe(X, A) :- atom_string(A, X), !.
term_to_atom_safe(X, X).

step_text_(depart, _, N, Text)  :- format(string(Text), 'Head out along ~w', [N]).
step_text_(arrive, _, _, "You have arrived at your destination").
step_text_(turn, M, N, Text)    :- modifier_words(M, W), format(string(Text), 'Turn ~w onto ~w', [W, N]).
step_text_('end of road', M, N, Text) :- modifier_words(M, W), format(string(Text), 'At the end of the road turn ~w onto ~w', [W, N]).
step_text_(fork, M, N, Text)    :- modifier_words(M, W), format(string(Text), 'Keep ~w at the fork onto ~w', [W, N]).
step_text_('on ramp', _, N, Text) :- format(string(Text), 'Take the ramp onto ~w', [N]).
step_text_('off ramp', _, N, Text) :- format(string(Text), 'Take the exit towards ~w', [N]).
step_text_(roundabout, _, N, Text) :- format(string(Text), 'At the roundabout continue onto ~w', [N]).
step_text_(rotary, _, N, Text)  :- format(string(Text), 'At the roundabout continue onto ~w', [N]).
step_text_(merge, _, N, Text)   :- format(string(Text), 'Merge onto ~w', [N]).
step_text_(_, M, N, Text)       :- M \== '', modifier_words(M, W), !, format(string(Text), 'Continue ~w on ~w', [W, N]).
step_text_(_, _, N, Text)       :- format(string(Text), 'Continue on ~w', [N]).

modifier_words('slight left',  'slightly left')  :- !.
modifier_words('slight right', 'slightly right') :- !.
modifier_words('sharp left',   'sharp left')     :- !.
modifier_words('sharp right',  'sharp right')    :- !.
modifier_words(straight,       'straight')       :- !.
modifier_words(uturn,          'around (U-turn)') :- !.
modifier_words(M, M).

% ---------------------------------------------------------------------
%  4. Building the journey options
% ---------------------------------------------------------------------

option_base(Mode, Label, Km, Min, Cost, Note,
            _{mode:Mode, label:Label, available:true,
              distance_km:Km1, minutes:Min1, cost_lkr:Cost, note:Note}) :-
    r1(Km, Km1),
    Min1 is max(1, round(Min)).

unavailable(Mode, Label, Reason,
            _{mode:Mode, label:Label, available:false, reason:Reason}).

is_available(O) :- get_dict(available, O, true).

% --- walking ---------------------------------------------------------
walk_option(Air, _, _, _, _, Opt) :-
    Air > 10, !,
    format(string(R), 'About ~0f km away - too far to walk.', [Air]),
    unavailable(foot, "Walk", R, Opt).
walk_option(_, SLat, SLon, CLat, CLon, Opt) :-
    osrm_profile_route(foot, SLat, SLon, CLat, CLon, F), !,
    get_dict(km, F, Km),
    Min is Km / 5 * 60,                      % 5 km/h walking pace
    (   Km =< 8
    ->  option_base(foot, "Walk", Km, Min, 0, "Walking pace of 5 km/h.", B),
        get_dict(geometry, F, G),
        get_dict(steps, F, S),
        put_dict(_{geometry:G, steps:S}, B, Opt)
    ;   format(string(R), '~1f km is too far to walk comfortably.', [Km]),
        unavailable(foot, "Walk", R, Opt)
    ).
walk_option(_, _, _, _, _, Opt) :-
    unavailable(foot, "Walk", "Walking route could not be loaded right now.", Opt).

% --- road based: bike, bus, three-wheeler -----------------------------
bike_option(CarKm, CarMin, Opt) :-
    Min is CarMin * 0.9 + 3,
    fare(bike, CarKm, Cost),
    option_base(bike, "Bike", CarKm, Min, Cost,
                "Motorbike. Cost is a fuel estimate (about LKR 10 per km).", B),
    put_dict(_{geometry_ref:"road"}, B, Opt).

bus_option(CarKm, CarMin, Opt) :-
    Min is CarMin * 1.5 + 10,                % stops + waiting
    fare(bus, CarKm, Cost),
    option_base(bus, "Bus", CarKm, Min, Cost,
                "Normal bus (approximate stage fare). Ask the conductor for the Open University, Nawala halt.", B),
    put_dict(_{geometry_ref:"road"}, B, Opt).

three_wheel_option(CarKm, CarMin, Opt) :-
    Min is CarMin * 1.1 + 5,
    fare(three_wheel, CarKm, Cost),
    option_base(three_wheel, "Three-wheeler", CarKm, Min, Cost,
                "Metered fare estimate. Agree the price or use the meter before you start.", B),
    put_dict(_{geometry_ref:"road"}, B, Opt).

% --- highway / expressway bus ----------------------------------------
highway_option(_, _, Air, _, _, Opt) :-
    Air < 30, !,
    unavailable(highway, "Highway bus",
                "Highway buses are for long journeys (30 km or more).", Opt).
highway_option(SLat, SLon, _Air, CarKm, CarMin, Opt) :-
    nearest_highway_stop(SLat, SLon, stop(Town, Corr, Term, Hours), DKm),
    DKm =< 30, !,
    AccRoad is DKm * 1.3,
    AccMin is AccRoad * 3 + 3,
    (   AccRoad < 1 -> AccCost = 0 ; fare(bus, AccRoad, AccCost) ),
    (   number(Hours) -> BusMin is Hours * 60 ; BusMin is CarMin * 1.15 ),
    Wait = 25, Local = 35,
    Min is AccMin + Wait + BusMin + Local,
    HwKm is max(0, CarKm - 12),
    fare(highway, HwKm, HwFare),
    LocalFare = 40,
    Cost is AccCost + HwFare + LocalFare,
    format(string(L1), 'Get to the ~w highway bus stand (about ~1f km).', [Town, AccRoad]),
    format(string(L2), '~w. Check departure times and book a seat with the conductor/operator.', [Corr]),
    format(string(L3), 'Get off at ~w, then take a local bus or three-wheeler to OUSL Nawala.', [Term]),
    Legs = [ _{type:access,  text:L1},
             _{type:highway, text:L2},
             _{type:egress,  text:L3} ],
    option_base(highway, "Highway bus", CarKm, Min, Cost,
                "Expressway bus fares are estimated. Corridors from bustimetable.lk.", B),
    put_dict(_{geometry_ref:"road", legs:Legs, corridor:Corr}, B, Opt).
highway_option(_, _, _, _, _, Opt) :-
    unavailable(highway, "Highway bus",
                "No highway-bus town from the bustimetable.lk list within 30 km of your start.", Opt).

% --- train ------------------------------------------------------------
train_option(_, _, Air, Opt) :-
    Air < 4, !,
    unavailable(train, "Train", "Too close for a train journey - use walk, bus or three-wheeler.", Opt).
train_option(SLat, SLon, _Air, Opt) :-
    nearest_station(SLat, SLon, S, AccKm0),
    AccKm0 =< 25, !,
    station(S, SName, _, _, _, _),
    campus_station(CS), station(CS, CSName, CSLat, CSLon, _, _),
    campus_coord(CLat, CLon),
    % first / last mile
    AccRoad is AccKm0 * 1.3,
    AccMin is AccRoad * 3 + 5,
    (   AccRoad < 1 -> AccCost = 0 ; fare(bus, AccRoad, AccCost) ),
    haversine(CSLat, CSLon, CLat, CLon, EgAir),
    EgKm is EgAir * 1.3,
    EgMin is EgKm * 3 + 4,
    fare(bus, EgKm, EgCost),
    % rail rides
    train_rides(S, Rides),
    findall(K, member(ride(_, _, _, K, _, _, _), Rides), Ks), sum_list(Ks, RideKm),
    findall(M, member(ride(_, _, _, _, M, _, _), Rides), Ms), sum_list(Ms, RideMin),
    findall(F3, member(ride(_, _, _, _, _, F3, _), Rides), F3s), sum_list(F3s, Fare3),
    findall(F2, member(ride(_, _, _, _, _, _, F2), Rides), F2s), sum_list(F2s, Fare2),
    length(Rides, NRides),
    Transfer is (NRides - 1) * 15,
    Wait = 20,
    TotalKm  is AccRoad + RideKm + EgKm,
    TotalMin is AccMin + Wait + RideMin + Transfer + EgMin,
    Cost3 is AccCost + Fare3 + EgCost,
    Cost2 is AccCost + Fare2 + EgCost,
    % human readable legs
    format(string(A1), 'Go to ~w station (about ~1f km) by bus, three-wheeler or on foot.', [SName, AccRoad]),
    findall(_{type:train, text:T, km:K1, minutes:M1, cost_lkr:C1},
            ( member(ride(FromId, ToId, Line, K, M, F3b, F2b), Rides),
              station_name(FromId, FN), station_name(ToId, TN),
              r1(K, K1), M1 is round(M), C1 = F3b,
              format(string(T), 'Train (~w line) from ~w to ~w - about ~1f km, ~w min, 3rd class about LKR ~w / 2nd class about LKR ~w.',
                     [Line, FN, TN, K1, M1, F3b, F2b]) ),
            RideLegs),
    format(string(E1), 'From ~w station take a short bus or three-wheeler (about ~1f km) to OUSL Nawala.', [CSName, EgKm]),
    append([[_{type:access, text:A1}], RideLegs, [_{type:egress, text:E1}]], Legs),
    rail_geometry(S, RailPts),
    StartPt = _{lat:SLat, lon:SLon},
    EndPt   = _{lat:CLat, lon:CLon},
    append([[StartPt], RailPts, [EndPt]], Geo),
    format(string(Note), 'Third-class estimate. Second class is about LKR ~w. Rail line drawn schematically; check the Sri Lanka Railways timetable (also listed on 12go.asia).', [Cost2]),
    option_base(train, "Train", TotalKm, TotalMin, Cost3, Note, B),
    put_dict(_{legs:Legs, geometry:Geo, schematic:true, cost_second_lkr:Cost2,
               boarding_station:SName}, B, Opt).
train_option(_, _, _, Opt) :-
    unavailable(train, "Train", "No railway station within 25 km of your start.", Opt).

% train_rides(+StartStation, -Rides): Rides = [ride(From,To,Line,Km,Min,Fare3,Fare2)]
train_rides(S, [Ride]) :-
    station(S, _, _, _, Line, Ch),
    kv_line(Line), !,
    campus_station(CS), station(CS, _, _, _, _, CCh),
    Km is abs(Ch - CCh),
    make_ride(S, CS, kvalley, Km, Ride).
train_rides(S, [R1, R2]) :-
    station(S, _, _, _, Line, Ch),
    make_ride(S, colombo_fort, Line, Ch, R1),
    campus_station(CS), station(CS, _, _, _, _, CCh),
    make_ride(colombo_fort, CS, kvalley, CCh, R2).

make_ride(From, To, Line, Km, ride(From, To, Line, Km, Min, F3, F2)) :-
    line_speed(Line, Speed),
    Min is Km * Speed + 4,
    train_fare(third, Km, F3),
    train_fare(second, Km, F2).

kv_line(hub).
kv_line(kvalley).

% rail_geometry(+StartStation, -Points) - schematic station-to-station polyline
rail_geometry(S, Pts) :-
    station(S, _, _, _, Line, Ch),
    campus_station(CS), station(CS, _, _, _, _, CCh),
    (   kv_line(Line)
    ->  kv_between(Ch, CCh, Ids)
    ;   own_line_ids(Line, Ch, Own),
        kv_between(0, CCh, Kv),
        append(Own, Kv, Ids)
    ),
    maplist(station_point, Ids, Pts).

kv_between(A, B, Ids) :-
    Lo is min(A, B), Hi is max(A, B),
    findall(C-I, ( station(I, _, _, _, L, C), kv_line(L), C >= Lo, C =< Hi ), Ps),
    keysort(Ps, Asc),
    (   A =< B -> Ordered = Asc ; reverse(Asc, Ordered) ),
    pairs_values(Ordered, Ids).

own_line_ids(northern, Ch, Ids) :- !,
    desc_ids(northern, 94, Ch, A),
    desc_ids(main, 0.1, 94, B),
    append(A, B, Ids).
own_line_ids(Line, Ch, Ids) :-
    desc_ids(Line, 0.1, Ch, Ids).

desc_ids(Line, Min, Max, Ids) :-
    findall(C-I, ( station(I, _, _, _, Line, C), C >= Min, C =< Max ), Ps),
    keysort(Ps, Asc),
    reverse(Asc, Desc),
    pairs_values(Desc, Ids).

% ---------------------------------------------------------------------
%  5. Recommendation + student message
% ---------------------------------------------------------------------

best_by(Key, Opts, Mode) :-
    findall(V-M, ( member(O, Opts), get_dict(Key, O, V), get_dict(mode, O, M) ), Ps),
    keysort(Ps, [_-Mode|_]).

recommend(Options, _{fastest:F, cheapest:C, best_value:V}) :-
    include(is_available, Options, Av),
    Av \== [],
    best_by(minutes, Av, F),
    best_by(cost_lkr, Av, C),
    findall(Score-M,
            ( member(O, Av), get_dict(minutes, O, Mi), get_dict(cost_lkr, O, Co),
              get_dict(mode, O, M), Score is Co + Mi * 4 ),   % 1 minute ~ LKR 4
            Ps),
    keysort(Ps, [_-V|_]).

fmt_minutes(M, T) :-
    (   M >= 60
    ->  H is M // 60, R is M mod 60,
        format(string(T), '~w h ~w min', [H, R])
    ;   format(string(T), '~w min', [M])
    ).

option_line(Opt, Line) :-
    get_dict(label, Opt, L),
    get_dict(distance_km, Opt, Km),
    get_dict(minutes, Opt, Min),
    get_dict(cost_lkr, Opt, C),
    fmt_minutes(Min, T),
    format(string(Line), '- ~w: ~1f km, about ~w, approx. LKR ~w', [L, Km, T, C]).

label_of(Mode, Options, Label) :-
    member(O, Options), get_dict(mode, O, Mode), get_dict(label, O, Label), !.

student_message(SName, Air, CarKm, Options, Rec, Message) :-
    campus_name(CN),
    include(is_available, Options, Av),
    maplist(option_line, Av, Lines),
    get_dict(fastest, Rec, F), get_dict(cheapest, Rec, C), get_dict(best_value, Rec, V),
    label_of(F, Options, FL), label_of(C, Options, CL), label_of(V, Options, VL),
    format(string(Head), 'Journey to ~w~nFrom: ~w~nStraight-line distance: ~1f km | By road: ~1f km', [CN, SName, Air, CarKm]),
    format(string(Pick), 'Fastest: ~w | Cheapest: ~w | Best value: ~w', [FL, CL, VL]),
    Intro = "Distance, time and estimated cost for each travel mode:",
    Foot  = "Costs are estimates, not official fares. Check live bus, train and highway-bus timetables before you travel.",
    append([[Head, "", Intro], Lines, ["", Pick, "", Foot]], Parts),
    atomic_list_concat(Parts, '\n', Atom),
    atom_string(Atom, Message).

% ---------------------------------------------------------------------
%  6. HTTP API
% ---------------------------------------------------------------------

% plan_journey(+Lat, +Lon, +Name, -PlanDict)
plan_journey(SLat, SLon, SName, Plan) :-
    campus_coord(CLat, CLon),
    campus_name(CName),
    haversine(SLat, SLon, CLat, CLon, Air),
    osrm_profile_route(car, SLat, SLon, CLat, CLon, Car),
    get_dict(km, Car, CarKm),
    get_dict(seconds, Car, CarSec),
    CarMin is CarSec / 60,
    get_dict(geometry, Car, RoadGeo),
    get_dict(steps, Car, RoadSteps),
    walk_option(Air, SLat, SLon, CLat, CLon, WalkOpt),
    bike_option(CarKm, CarMin, BikeOpt),
    bus_option(CarKm, CarMin, BusOpt),
    highway_option(SLat, SLon, Air, CarKm, CarMin, HwOpt),
    train_option(SLat, SLon, Air, TrainOpt),
    three_wheel_option(CarKm, CarMin, TwOpt),
    Options = [WalkOpt, BikeOpt, BusOpt, HwOpt, TrainOpt, TwOpt],
    recommend(Options, Rec),
    student_message(SName, Air, CarKm, Options, Rec, Message),
    r1(Air, Air1), r1(CarKm, CarKm1),
    Plan = _{ ok:true,
              campus:_{name:CName, lat:CLat, lon:CLon},
              start:_{name:SName, lat:SLat, lon:SLon},
              air_km:Air1, road_km:CarKm1,
              options:Options,
              recommended:Rec,
              message:Message,
              road_geometry:RoadGeo,
              road_steps:RoadSteps }.

valid_start(Data, Lat, Lon, Name) :-
    get_dict(start_coord, Data, SC), is_dict(SC),
    get_dict(lat, SC, Lat), get_dict(lon, SC, Lon),
    number(Lat), number(Lon),
    (   get_dict(name, SC, N), N \== "" -> Name = N ; Name = "Your location" ).

plan_api(Request) :-
    catch(plan_api_(Request), Error,
          ( format(user_error, 'plan_api error: ~q~n', [Error]),
            format(string(Detail), '~q', [Error]),
            reply_json_dict(_{ok:false, message:"Internal server error", detail:Detail}) )).

plan_api_(Request) :-
    memberchk(method(get), Request), !,
    reply_json_dict(_{ok:true,
        message:"POST JSON {start_coord:{lat,lon,name}} to receive travel options to OUSL Nawala."}).
plan_api_(Request) :-
    http_read_json_dict(Request, Data),
    (   valid_start(Data, Lat, Lon, Name)
    ->  (   in_sri_lanka(Lat, Lon)
        ->  (   plan_journey(Lat, Lon, Name, Plan)
            ->  reply_json_dict(Plan)
            ;   reply_json_dict(_{ok:false,
                    message:"Could not calculate a route. The routing service may be busy - please try again."})
            )
        ;   reply_json_dict(_{ok:false, message:"Please choose a start location inside Sri Lanka."})
        )
    ;   reply_json_dict(_{ok:false, message:"Send start_coord with numeric lat and lon."})
    ).

% /api/route - kept for compatibility: POST {start_coord, mode} returns one mode.
route_api(Request) :-
    catch(route_api_(Request), Error,
          ( format(string(Detail), '~q', [Error]),
            reply_json_dict(_{ok:false, message:"Internal server error", detail:Detail}) )).

route_api_(Request) :-
    memberchk(method(get), Request), !,
    reply_json_dict(_{ok:true, message:"POST JSON {start_coord:{lat,lon}, mode:foot|bike|bus|highway|train|three_wheel}."}).
route_api_(Request) :-
    http_read_json_dict(Request, Data),
    (   valid_start(Data, Lat, Lon, Name), in_sri_lanka(Lat, Lon),
        get_dict(mode, Data, ModeRaw), atom_string(Mode, ModeRaw),
        plan_journey(Lat, Lon, Name, Plan),
        get_dict(options, Plan, Opts),
        member(O, Opts), get_dict(mode, O, Mode), is_available(O)
    ->  get_dict(road_geometry, Plan, RG),
        (   get_dict(geometry, O, G) -> true ; G = RG ),
        reply_json_dict(_{ok:true, option:O, geometry:G})
    ;   reply_json_dict(_{ok:false, message:"Mode not available for this start location."})
    ).

campus_api(_Request) :-
    campus_name(N), campus_coord(Lat, Lon),
    reply_json_dict(_{ok:true, name:N, lat:Lat, lon:Lon}).

stations_api(_Request) :-
    findall(_{id:I, name:N, lat:La, lon:Lo, line:L, km_from_fort:C},
            station(I, N, La, Lo, L, C), Stations),
    reply_json_dict(_{ok:true, stations:Stations}).

highway_api(_Request) :-
    findall(_{town:T, lat:La, lon:Lo, corridor:C, terminal:Tm, published_hours:H1},
            ( highway_stop(T, La, Lo, C, Tm, H), ( H == none -> H1 = null ; H1 = H ) ),
            Stops),
    reply_json_dict(_{ok:true, source:"https://bustimetable.lk/tag/expressway-bus/", stops:Stops}).

% --- Nominatim proxies (Sri Lanka only) -------------------------------
search_api(Request) :-
    catch(search_api_(Request), E,
          ( format(user_error, 'Nominatim search failed: ~q~n', [E]),
            reply_json_dict(_{ok:false, message:"Search failed"}) )).

search_api_(Request) :-
    http_parameters(Request, [q(Q, [default(''), atom])]),
    (   atom_length(Q, L), L >= 3
    ->  uri_encoded(query_value, Q, QE),
        format(string(URL),
               'https://nominatim.openstreetmap.org/search?format=jsonv2&limit=6&countrycodes=lk&q=~w', [QE]),
        fetch_json(URL, Json),
        reply_json_dict(_{ok:true, results:Json})
    ;   reply_json_dict(_{ok:true, results:[]})
    ).

reverse_api(Request) :-
    catch(reverse_api_(Request), E,
          ( format(user_error, 'Nominatim reverse failed: ~q~n', [E]),
            reply_json_dict(_{ok:false, message:"Reverse geocode failed"}) )).

reverse_api_(Request) :-
    http_parameters(Request, [lat(Lat, [number]), lon(Lon, [number])]),
    format(string(URL),
           'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=~w&lon=~w', [Lat, Lon]),
    fetch_json(URL, Json),
    (   get_dict(display_name, Json, DN)
    ->  reply_json_dict(_{ok:true, display_name:DN})
    ;   reply_json_dict(_{ok:false, message:"No address found"})
    ).
