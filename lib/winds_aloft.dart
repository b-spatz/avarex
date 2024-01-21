import 'package:avaremp/geo_calculations.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class WindsAloft {
  String station;
  DateTime expires;
  String? w0k; // get from metar if possible
  String w3k;
  String w6k;
  String w9k;
  String w12k;
  String w18k;
  String w24k;
  String w30k;
  String w34k;
  String w39k;

  WindsAloft(this.station, this.expires, this.w3k, this.w6k, this.w9k, this.w12k, this.w18k, this.w24k, this.w30k, this.w34k, this.w39k);

  (int?, int?) decodeWind(String wind) {

    if(wind.length < 4) {
      return (null, null);
    }

    int dir;
    int speed;
    try {
      dir = int.parse(wind.substring(0, 2)) * 10;
      speed = int.parse(wind.substring(2, 4));
    }
    catch(e) {
      return (null, null);
    }

    if(dir == 990 && speed == 0) {
      return (0, 0); // light and variable
    }
    if(dir >= 510) {
      dir -= 500;
      speed += 100;
    }

    return(dir, speed);
  }

  (double?, double?) getWindAtAltitude(double altitude) {
    String wHigher;
    String wLower;
    double higherAltitude;
    double lowerAltitude;

    // slope of line, wind at y and altitude at x, y = mx + b
    // slope = (wind_at_higher_altitude - wind_at_lower_altitude) / (higher_altitude - lower_altitude)
    // wind =  slope * altitude + wind_intercept
    // wind_intercept = wind_at_lower_altitude - slope * lower_altitude

    // fill missing wind from higher altitude
    w34k = w34k.isEmpty ? w39k : w34k;
    w30k = w30k.isEmpty ? w34k : w30k;
    w24k = w24k.isEmpty ? w30k : w24k;
    w18k = w18k.isEmpty ? w24k : w18k;
    w12k = w12k.isEmpty ? w18k : w12k;
    w9k = w9k.isEmpty ? w12k : w9k;
    w6k = w6k.isEmpty ? w9k : w6k;
    w3k = w3k.isEmpty ? w6k : w3k;
    w0k = w3k;

    if (altitude < 0) {
      return (0, 0);
    }
    else if (altitude >= 0 && altitude < 3000) {
      higherAltitude = 3000;
      lowerAltitude = 0;
      wHigher = w3k;
      wLower = w0k!;
    }
    else if (altitude >= 3000 && altitude < 6000) {
      higherAltitude = 6000;
      lowerAltitude = 3000;
      wHigher = w6k;
      wLower = w3k;
    }
    else if (altitude >= 6000 && altitude < 9000) {
      higherAltitude = 9000;
      lowerAltitude = 6000;
      wHigher = w9k;
      wLower = w6k;
    }
    else if (altitude >= 9000 && altitude < 12000) {
      higherAltitude = 12000;
      lowerAltitude = 9000;
      wHigher = w12k;
      wLower = w9k;
    }
    else if (altitude >= 12000 && altitude < 18000) {
      higherAltitude = 18000;
      lowerAltitude = 12000;
      wHigher = w18k;
      wLower = w12k;
    }
    else if (altitude >= 18000 && altitude < 24000) {
      higherAltitude = 24000;
      lowerAltitude = 18000;
      wHigher = w24k;
      wLower = w18k;
    }
    else if (altitude >= 24000 && altitude < 30000) {
      higherAltitude = 30000;
      lowerAltitude = 24000;
      wHigher = w30k;
      wLower = w24k;
    }
    else if (altitude >= 30000 && altitude < 34000) {
      higherAltitude = 34000;
      lowerAltitude = 30000;
      wHigher = w34k;
      wLower = w30k;
    }
    else {
      higherAltitude = 39000;
      lowerAltitude = 34000;
      wHigher = w39k;
      wLower = w34k;
    }

    try {
      int? higherWindDir, lowerWindDir;
      int? higherWindSpeed, lowerWindSpeed;

      (higherWindSpeed, higherWindDir) = decodeWind(wHigher);
      (lowerWindSpeed, lowerWindDir) = decodeWind(wLower);
      if(higherWindSpeed == null ||  higherWindDir == null || lowerWindSpeed == null ||  lowerWindDir == null) {
        return (null, null);
      }
      double slope = ((higherWindSpeed - lowerWindSpeed) /
          (higherAltitude - lowerAltitude));
      double intercept = lowerWindSpeed - slope * lowerAltitude;
      double speed = slope * altitude + intercept;

      slope = ((higherWindDir - lowerWindDir) / (higherAltitude - lowerAltitude));
      intercept = lowerWindDir - slope * lowerAltitude;
      double dir = slope * altitude + intercept;

      return (speed, dir);
    }
    catch (e) {}

    return (null, null);
  }
}

class WindsParser {

  String _winds = "";
  final Map<String, WindsAloft> _windsMap = {};
  DateTime _expires = DateTime.fromMicrosecondsSinceEpoch(0);

  Future<void> _download() async {

    http.Response response = await http.get(
        Uri.parse('https://aviationweather.gov/api/data/windtemp?level=low&fcst=06'));
    _winds = response.body;

    _parse();
  }

  bool _isExpired() {
    Duration diff = _expires.difference(DateTime.now().toUtc());
    return (diff.inSeconds < 0);
  }

  void _parse() {

    // parse winds, set expire time
    RegExp exp1 = RegExp("VALID\\s*([0-9]*)Z\\s*FOR USE\\s*([0-9]*)-([0-9]*)Z");

    List<String> lines = _winds.split('\n');
    for (String line in lines) {
      line = line.trim();
      RegExpMatch? match = exp1.firstMatch(line);
      if (match != null) {
        DateTime now = DateTime.now().toUtc();
        _expires = DateTime.utc(
            now.year,
            now.month,
            now.day, //day
            0,
            0);
        int from = int.parse(match[2]!);
        int to = int.parse(match[3]!);
        // if from > to then its next day
        _expires = _expires.add(Duration(days: to < from ? 1 : 0, hours: int.parse(match[3]!.substring(0, 2))));
        break;
      }
    }

    bool start = false;
    // parse winds, first check if a new download is needed
    RegExp exp2 = RegExp("FT.*39000");
    for (String line in lines) {
      line = line.trim();
      RegExpMatch? match = exp2.firstMatch(line);
      if(match != null) {
        start = true;
        continue;
      }
      if(!start) {
        continue;
      }
      try {
        String station = line.substring(0, 3);
        String k3 = line.substring(4, 8);
        String k6 = line.substring(9, 16);
        String k9 = line.substring(17, 24);
        String k12 = line.substring(25, 32);
        String k18 = line.substring(33, 40);
        String k24 = line.substring(41, 48);
        String k30 = line.substring(49, 55);
        String k34 = line.substring(56, 62);
        String k39 = line.substring(63, 69);
        WindsAloft w = WindsAloft(station, _expires, k3, k6, k9, k12, k18, k24, k30, k34, k39);
        _windsMap[station] = w;
      }
      catch (e) {};
    }

  }

  void init() {
    getWind(0, const LatLng(0, 0));
  }

  // dir, speed
  (double?, double?) getWind(double altitude, LatLng location) {
    if(_isExpired()) {
      _download(); // download when expired
    }
    // find distance
    GeoCalculations geo = GeoCalculations();
    double distanceMin = double.maxFinite;
    String station = "";
    for(MapEntry<String, LatLng> map in _stationMap.entries) {
      double distance = geo.calculateDistance(map.value, location);
      if(distance < distanceMin) {
        distanceMin = distance;
        station = map.key;
      }
    }
    WindsAloft? w = _windsMap[station];
    if(w != null) {
      return(w.getWindAtAltitude(altitude));
    }
    return (null, null);
  }

  static const Map<String, LatLng> _stationMap = {
    "BHM": LatLng(33.55, -86.73333333333333),
    "HSV": LatLng(34.55, -86.76666666666667),
    "MGM": LatLng(32.21666666666667, -86.31666666666666),
    "MOB": LatLng(30.683333333333334, -88.23333333333333),
    "ADK": LatLng(51.93333333333333, -176.41666666666666),
    "ADQ": LatLng(57.766666666666666, -152.58333333333334),
    "AKN": LatLng(58.733333333333334, -156.75),
    "ANC": LatLng(61.233333333333334, -149.55),
    "ANN": LatLng(55.05, -131.61666666666667),
    "BET": LatLng(60.583333333333336, -161.58333333333334),
    "BRW": LatLng(71.28333333333333, -156.51666666666668),
    "BTI": LatLng(70.16666666666667, -143.91666666666666),
    "BTT": LatLng(66.9, -151.5),
    "CDB": LatLng(55.18333333333333, -162.36666666666667),
    "CZF": LatLng(61.78333333333333, -166.03333333333333),
    "EHM": LatLng(58.65, -162.06666666666666),
    "FAI": LatLng(64.71666666666667, -148.18333333333334),
    "FYU": LatLng(66.58333333333333, -145.08333333333334),
    "GAL": LatLng(64.73333333333333, -156.93333333333334),
    "GKN": LatLng(62.15, -145.45),
    "HOM": LatLng(59.65, -151.48333333333332),
    "JNU": LatLng(58.43333333333333, -134.68333333333334),
    "LUR": LatLng(68.88333333333334, -166.11666666666667),
    "MCG": LatLng(62.81666666666667, -155.4),
    "MDO": LatLng(59.5, -146.3),
    "OME": LatLng(64.61666666666666, -165.08333333333334),
    "ORT": LatLng(63.06666666666667, -142.06666666666666),
    "OTZ": LatLng(66.65, -162.9),
    "SNP": LatLng(57.15, -170.61666666666667),
    "TKA": LatLng(62.31666666666667, -150.1),
    "UNK": LatLng(63.88333333333333, -160.8),
    "YAK": LatLng(59.61666666666667, -139.5),
    "IKO": LatLng(52.95, -168.85),
    "AFM": LatLng(67.1, -157.85),
    "5AB": LatLng(52.416666666666664, 176.0),
    "5AC": LatLng(52.0, -135.0),
    "5AD": LatLng(54.0, -145.0),
    "5AE": LatLng(55.0, -155.0),
    "5AF": LatLng(56.0, -137.0),
    "5AG": LatLng(58.0, -142.0),
    "FSM": LatLng(35.38333333333333, -94.26666666666667),
    "LIT": LatLng(34.666666666666664, -92.16666666666667),
    "PHX": LatLng(33.416666666666664, -111.88333333333334),
    "PRC": LatLng(34.7, -112.46666666666667),
    "TUS": LatLng(32.11666666666667, -110.81666666666666),
    "BIH": LatLng(37.36666666666667, -118.35),
    "BLH": LatLng(33.583333333333336, -114.75),
    "FAT": LatLng(36.88333333333333, -119.8),
    "FOT": LatLng(40.666666666666664, -124.23333333333333),
    "ONT": LatLng(34.05, -117.6),
    "RBL": LatLng(40.083333333333336, -122.23333333333333),
    "SAC": LatLng(38.43333333333333, -121.55),
    "SAN": LatLng(32.733333333333334, -117.18333333333334),
    "SBA": LatLng(34.5, -119.76666666666667),
    "SFO": LatLng(37.61666666666667, -122.36666666666666),
    "SIY": LatLng(41.78333333333333, -122.45),
    "WJF": LatLng(34.733333333333334, -118.21666666666667),
    "ALS": LatLng(37.333333333333336, -105.8),
    "DEN": LatLng(39.8, -104.88333333333334),
    "GJT": LatLng(39.05, -108.78333333333333),
    "PUB": LatLng(38.28333333333333, -104.41666666666667),
    "BDL": LatLng(41.93333333333333, -72.68333333333334),
    "EYW": LatLng(24.583333333333332, -81.8),
    "JAX": LatLng(30.433333333333334, -81.55),
    "MIA": LatLng(25.95, -80.45),
    "MLB": LatLng(28.1, -80.63333333333334),
    "PFN": LatLng(30.2, -85.66666666666667),
    "PIE": LatLng(27.9, -82.68333333333334),
    "TLH": LatLng(30.55, -84.36666666666666),
    "ATL": LatLng(33.61666666666667, -84.43333333333334),
    "CSG": LatLng(32.6, -85.01666666666667),
    "SAV": LatLng(32.15, -81.1),
    "ITO": LatLng(19.716666666666665, -155.05),
    "HNL": LatLng(21.316666666666666, -157.91666666666666),
    "LIH": LatLng(21.983333333333334, -159.33333333333334),
    "OGG": LatLng(20.9, -156.43333333333334),
    "BOI": LatLng(43.56666666666667, -116.23333333333333),
    "LWS": LatLng(46.36666666666667, -116.86666666666666),
    "PIH": LatLng(42.86666666666667, -112.65),
    "JOT": LatLng(41.53333333333333, -88.31666666666666),
    "SPI": LatLng(39.833333333333336, -89.66666666666667),
    "EVV": LatLng(38.03333333333333, -87.51666666666667),
    "FWA": LatLng(40.96666666666667, -85.18333333333334),
    "IND": LatLng(39.8, -86.36666666666666),
    "BRL": LatLng(40.71666666666667, -90.91666666666667),
    "DBQ": LatLng(42.4, -90.7),
    "DSM": LatLng(41.43333333333333, -93.63333333333334),
    "MCW": LatLng(43.083333333333336, -93.31666666666666),
    "GCK": LatLng(37.916666666666664, -100.71666666666667),
    "GLD": LatLng(39.38333333333333, -101.68333333333334),
    "ICT": LatLng(37.71666666666667, -97.45),
    "SLN": LatLng(38.86666666666667, -97.61666666666666),
    "LOU": LatLng(38.1, -85.56666666666666),
    "LCH": LatLng(30.133333333333333, -93.1),
    "MSY": LatLng(30.016666666666666, -90.16666666666667),
    "SHV": LatLng(32.766666666666666, -93.8),
    "BGR": LatLng(44.833333333333336, -68.86666666666666),
    "CAR": LatLng(46.86666666666667, -68.01666666666667),
    "PWM": LatLng(43.63333333333333, -70.3),
    "EMI": LatLng(39.483333333333334, -76.96666666666667),
    "ACK": LatLng(41.266666666666666, -70.01666666666667),
    "BOS": LatLng(42.35, -70.98333333333333),
    "ECK": LatLng(43.25, -82.71666666666667),
    "MKG": LatLng(43.166666666666664, -86.03333333333333),
    "MQT": LatLng(46.516666666666666, -87.58333333333333),
    "SSM": LatLng(46.4, -84.3),
    "TVC": LatLng(44.666666666666664, -85.53333333333333),
    "AXN": LatLng(45.95, -95.21666666666667),
    "DLH": LatLng(46.8, -92.2),
    "INL": LatLng(48.55, -93.4),
    "MSP": LatLng(45.13333333333333, -93.36666666666666),
    "CGI": LatLng(37.21666666666667, -89.56666666666666),
    "COU": LatLng(38.8, -92.21666666666667),
    "MKC": LatLng(39.266666666666666, -94.58333333333333),
    "SGF": LatLng(37.35, -93.33333333333333),
    "STL": LatLng(38.85, -90.46666666666667),
    "JAN": LatLng(32.5, -90.16666666666667),
    "BIL": LatLng(45.8, -108.61666666666666),
    "DLN": LatLng(45.233333333333334, -112.53333333333333),
    "GPI": LatLng(48.2, -114.16666666666667),
    "GGW": LatLng(48.2, -106.61666666666666),
    "GTF": LatLng(47.45, -111.4),
    "MLS": LatLng(46.36666666666667, -105.95),
    "HAT": LatLng(35.266666666666666, -75.55),
    "ILM": LatLng(34.35, -77.86666666666666),
    "RDU": LatLng(35.86666666666667, -78.78333333333333),
    "DIK": LatLng(46.85, -102.76666666666667),
    "GFK": LatLng(47.95, -97.18333333333334),
    "MOT": LatLng(48.25, -101.28333333333333),
    "BFF": LatLng(41.88333333333333, -103.46666666666667),
    "GRI": LatLng(40.983333333333334, -98.3),
    "OMA": LatLng(41.166666666666664, -95.73333333333333),
    "ONL": LatLng(42.46666666666667, -98.68333333333334),
    "BML": LatLng(44.63333333333333, -71.18333333333334),
    "ACY": LatLng(39.45, -74.56666666666666),
    "ABQ": LatLng(35.03333333333333, -106.8),
    "FMN": LatLng(36.733333333333334, -108.08333333333333),
    "ROW": LatLng(33.333333333333336, -104.61666666666666),
    "TCC": LatLng(35.166666666666664, -103.58333333333333),
    "ZUN": LatLng(34.95, -109.15),
    "BAM": LatLng(40.56666666666667, -116.91666666666667),
    "ELY": LatLng(39.28333333333333, -114.83333333333333),
    "LAS": LatLng(36.06666666666667, -115.15),
    "RNO": LatLng(39.516666666666666, -119.65),
    "ALB": LatLng(42.733333333333334, -73.8),
    "BUF": LatLng(42.916666666666664, -78.63333333333334),
    "JFK": LatLng(40.61666666666667, -73.76666666666667),
    "PLB": LatLng(44.8, -73.4),
    "SYR": LatLng(43.15, -76.2),
    "CLE": LatLng(41.35, -82.15),
    "CMH": LatLng(39.983333333333334, -82.91666666666667),
    "CVG": LatLng(39.0, -84.7),
    "GAG": LatLng(36.333333333333336, -99.86666666666666),
    "OKC": LatLng(35.4, -97.63333333333334),
    "TUL": LatLng(36.18333333333333, -95.78333333333333),
    "AST": LatLng(46.15, -123.86666666666666),
    "IMB": LatLng(44.63333333333333, -119.7),
    "LKV": LatLng(42.483333333333334, -120.5),
    "OTH": LatLng(43.4, -124.16666666666667),
    "PDX": LatLng(45.733333333333334, -122.58333333333333),
    "RDM": LatLng(44.25, -121.3),
    "AGC": LatLng(40.266666666666666, -80.03333333333333),
    "AVP": LatLng(41.266666666666666, -75.68333333333334),
    "PSB": LatLng(40.9, -77.98333333333333),
    "CAE": LatLng(33.85, -81.05),
    "CHS": LatLng(32.88333333333333, -80.03333333333333),
    "FLO": LatLng(34.21666666666667, -79.65),
    "GSP": LatLng(34.88333333333333, -82.21666666666667),
    "ABR": LatLng(45.416666666666664, -98.36666666666666),
    "FSD": LatLng(43.63333333333333, -96.76666666666667),
    "PIR": LatLng(44.38333333333333, -100.15),
    "RAP": LatLng(43.96666666666667, -103.0),
    "BNA": LatLng(36.11666666666667, -86.66666666666667),
    "MEM": LatLng(35.05, -89.96666666666667),
    "TRI": LatLng(36.46666666666667, -82.4),
    "TYS": LatLng(35.9, -83.88333333333334),
    "ABI": LatLng(32.46666666666667, -99.85),
    "AMA": LatLng(35.28333333333333, -101.63333333333334),
    "BRO": LatLng(25.916666666666668, -97.36666666666666),
    "CLL": LatLng(30.6, -96.41666666666667),
    "CRP": LatLng(27.9, -97.43333333333334),
    "DAL": LatLng(32.833333333333336, -96.85),
    "DRT": LatLng(29.366666666666667, -100.91666666666667),
    "ELP": LatLng(31.8, -106.26666666666667),
    "HOU": LatLng(29.633333333333333, -95.26666666666667),
    "INK": LatLng(31.866666666666667, -103.23333333333333),
    "LBB": LatLng(33.7, -101.9),
    "LRD": LatLng(27.466666666666665, -99.41666666666667),
    "MRF": LatLng(30.283333333333335, -103.61666666666666),
    "PSX": LatLng(28.75, -96.3),
    "SAT": LatLng(28.633333333333333, -98.45),
    "SPS": LatLng(33.983333333333334, -98.58333333333333),
    "BCE": LatLng(37.68333333333333, -112.3),
    "SLC": LatLng(40.85, -111.96666666666667),
    "ORF": LatLng(36.88333333333333, -76.2),
    "RIC": LatLng(37.5, -77.31666666666666),
    "ROA": LatLng(37.333333333333336, -80.06666666666666),
    "GEG": LatLng(47.55, -117.61666666666666),
    "SEA": LatLng(47.43333333333333, -122.3),
    "YKM": LatLng(46.56666666666667, -120.43333333333334),
    "GRB": LatLng(44.55, -88.18333333333334),
    "LSE": LatLng(43.86666666666667, -91.25),
    "CRW": LatLng(38.333333333333336, -81.76666666666667),
    "EKN": LatLng(38.9, -80.08333333333333),
    "CZI": LatLng(43.983333333333334, -106.43333333333334),
    "LND": LatLng(42.8, -108.71666666666667),
    "MBW": LatLng(41.833333333333336, -106.0),
    "RKS": LatLng(41.583333333333336, -109.0),
    "2XG": LatLng(30.333333333333332, -78.5),
    "T01": LatLng(28.5, -93.5),
    "T06": LatLng(28.5, -91.0),
    "T07": LatLng(28.5, -88.0),
    "4J3": LatLng(28.5, -85.0),
    "H51": LatLng(26.5, -95.0),
    "H52": LatLng(26.0, -89.5),
    "H61": LatLng(26.5, -84.0),
    "JON": LatLng(16.733333333333334, -169.53333333333333),
    "MAJ": LatLng(7.066666666666666, 171.26666666666668),
    "KWA": LatLng(8.716666666666667, 167.73333333333332),
    "MDY": LatLng(28.2, -177.38333333333333),
    "PPG": LatLng(-14.333333333333334, -170.71666666666667),
    "TTK": LatLng(5.35, 162.96666666666667),
    "AWK": LatLng(19.283333333333335, 166.65),
    "GRO": LatLng(14.183333333333334, 145.23333333333332),
    "GSN": LatLng(15.116666666666667, 145.73333333333332),
    "TNI": LatLng(15.0, 145.61666666666667),
    "GUM": LatLng(13.483333333333333, 144.8),
    "TKK": LatLng(7.466666666666667, 151.85),
    "PNI": LatLng(6.983333333333333, 158.21666666666667),
    "ROR": LatLng(7.366666666666666, 134.55),
    "T11": LatLng(9.5, 138.08333333333334),
    "LNY": LatLng(20 + 47 / 60, -156 - 57 / 60),
    "KOA": LatLng(19 + 44 / 60, -156 - 3 / 60),
  };

}

