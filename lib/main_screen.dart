import 'package:avaremp/plate_screen.dart';
import 'package:flutter/material.dart';
import 'chart.dart';
import 'csup.dart';
import 'draw_canvas.dart';
import 'find.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // for various tab screens
  final List<String> _charts = [ChartCategory.sectional, ChartCategory.tac, ChartCategory.ifrl];
  String _chartSelectedValue = ChartCategory.sectional;

  // define tabs here
  static final List<Widget> _widgetOptions = <Widget>[
    const DrawCanvas(),
    const CSup(),
    const PlateScreen(),
  ];

  void mOnItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.settings), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => Navigator.pushNamed(context, '/settings')),
        actions: [
          IconButton(icon: const Icon(Icons.download), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => Navigator.pushNamed(context, '/download')),
          DropdownButton<String>( // chart selection
            value: _chartSelectedValue,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            items: _charts.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _chartSelectedValue = val ?? _charts[0];
              });
            },
          ),
          IconButton(icon: const Icon(Icons.search), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () { showSearch(context: context, delegate: Find()); },),
        ],
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'MAP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            label: 'CSUP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: 'PLATE',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: mOnItemTapped,
      ),
    );
  }
}

