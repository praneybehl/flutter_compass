import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors/sensors.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flare_dart/math/mat2d.dart';
import 'package:flare_flutter/flare.dart';
import 'package:flare_flutter/flare_controller.dart';
import 'package:flare_flutter/flare_actor.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

void main() {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(
    title: 'Compass',
    theme: ThemeData.dark(),
    home: HomePage(),
  ));
}

class Anim {
  String name;
  double _value = 0, pos = 0, min, max, speed;
  bool endless = false;
  ActorAnimation actor;
  Anim(this.name, this.min, this.max, this.speed, this.endless);
  get value => _value * (max - min) + min;
  set value(double v) => _value = (v - min) / (max - min);
}

class AniControler implements FlareController {
  List<Anim> items;
  @override
  bool advance(FlutterActorArtboard board, double elapsed) {
    for (var a in items) {
      if (a.actor == null) continue;
      var d = (a.pos - a._value).abs();
      var m = a.pos > a._value ? -1 : 1;
      if (a.endless && d > 0.5) {
        m = -m;
        d = 1.0 - d;
      }
      var e = elapsed / a.actor.duration * (1 + d * a.speed);
      a.pos = e < d ? (a.pos + e * m) : a._value;
      if (a.endless) a.pos %= 1.0;
      a.actor.apply(a.actor.duration * a.pos, board, 1.0);
    }
    return true;
  }

  @override
  void initialize(FlutterActorArtboard board) {
    items.forEach((a) => a.actor = board.getAnimation(a.name));
  }

  @override
  void setViewTransform(Mat2D viewTransform) {}

  AniControler(this.items);

  operator [](String name) {
    for (var a in items) if (a.name == name) return a;
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AniControler compass;
  AniControler earth;
  double lat, lon;

  String city = '', weather = '', icon = '01d';
  double temp = 0.0, humidity = 0.0;

  void getWeather() async {
    var key = '7c5c03c8acacd8dea3abd517ae22af34';
    var url = 'http://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$key';
    var resp = await http.Client().get(url);
    var data = json.decode(resp.body);
    city = data['name'];
    var m = data['weather'][0];
    weather = m['main'];
    icon = m['icon'];
    m = data['main'];
    temp = m['temp'] - 273.15;
    humidity = m['humidity'] + 0.0;
    setState(() {});
  }

  void setLocation(double lati, long, [bool weather = true]) {
    earth['lat'].value = lat = lati;
    earth['lon'].value = lon = long;
    if (weather) getWeather();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();

    compass = AniControler([
      Anim('dir', 0.0, 360.0, 30.0, true),
      Anim('hor', -9.6, 9.6, 20.0, false),
      Anim('ver', -9.6, 9.6, 20.0, false),
    ]);

    earth = AniControler([
      Anim('dir', 0.0, 360.0, 20.0, true),
      Anim('lat', -90.0, 90.0, 10.0, false),
      Anim('lon', -180.0, 180.0, 0.5, true),
    ]);

    FlutterCompass.events.listen((angle) {
      compass['dir'].value = angle;
      earth['dir'].value = angle;
    });

    accelerometerEvents.listen((event) {
      compass['hor'].value = -event.x;
      compass['ver'].value = -event.y;
    });

    setLocation(0.0, 0.0);
    Timer.periodic(Duration(seconds: 15), (t) {
      Location().getLocation().then((p) => setLocation(p.latitude, p.longitude));
    });
  }

  Widget EarthActor() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(city, style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)),
      Text('lat:${lat.toStringAsFixed(2)}  lon:${lon.toStringAsFixed(2)}'),
      Expanded(
        child: GestureDetector(
          onPanUpdate: (pan) => setLocation((lat - pan.delta.dy).clamp(-90.0, 90.0), (lon - pan.delta.dx + 180.0) % 360.0 - 180.0, false),
          onPanEnd: (pan) => getWeather(),
          child: FlareActor("assets/earth.flr", animation: "pulse", controller: earth),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 128.0, height: 128.0, child: FlareActor('assets/weather.flr', animation: icon)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${temp.toInt()}°', style: TextStyle(fontSize: 60.0)),
          Text(weather),
          Text('Humidity ${humidity.toInt()}%'),
        ]),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: PageController(viewportFraction: 0.8),
        scrollDirection: Axis.vertical,
        children: [
          FlareActor("assets/compass.flr", controller: compass),
          EarthActor(),
        ],
      ),
    );
  }
}
