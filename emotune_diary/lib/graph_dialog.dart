// graph_dialog.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MoodGraphDialog extends StatelessWidget {
  final GlobalKey _graphKey = GlobalKey();
  final List<Map<String, dynamic>> diaryEntries;

  MoodGraphDialog({super.key, required this.diaryEntries});

  double _getMinX() {
    if (diaryEntries.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thirtyDaysAgo = today.subtract(Duration(days: 30));

    var entries = diaryEntries.where((entry) {
      final date = DateTime.parse(entry['date'].toString());
      final entryDate = DateTime(date.year, date.month, date.day);
      return !entryDate.isBefore(thirtyDaysAgo) && !entryDate.isAfter(today);
    }).toList();

    if (entries.isEmpty) return 0;

    // Find oldest entry
    final oldestEntry = entries.reduce((a, b) {
      final dateA = DateTime.parse(a['date'].toString());
      final dateB = DateTime.parse(b['date'].toString());
      return dateA.isBefore(dateB) ? a : b;
    });

    final oldestDate = DateTime.parse(oldestEntry['date'].toString());
    final oldestDateNormalized =
        DateTime(oldestDate.year, oldestDate.month, oldestDate.day);

    // Calculate days from thirtyDaysAgo to oldest entry
    return oldestDateNormalized.difference(thirtyDaysAgo).inDays.toDouble();
  }

  double _getMoodValue(String mood) {
    switch (mood) {
      case '매우 좋음':
        return 2.0;
      case '좋음':
        return 1.0;
      case '보통':
        return 0.0;
      case '나쁨':
        return -1.0;
      case '매우 나쁨':
        return -2.0;
      default:
        return 0.0;
    }
  }

  List<FlSpot> _getSpots() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thirtyDaysAgo = today.subtract(Duration(days: 30));

    return diaryEntries.where((entry) {
      final date = DateTime.parse(entry['date'].toString());
      final entryDate = DateTime(date.year, date.month, date.day);
      return !entryDate.isBefore(thirtyDaysAgo) && !entryDate.isAfter(today);
    }).map((entry) {
      final date = DateTime.parse(entry['date'].toString());
      final entryDate = DateTime(date.year, date.month, date.day);

      // Calculate days from thirtyDaysAgo (0 to 30)
      final daysDiff = entryDate.difference(thirtyDaysAgo).inDays.toDouble();

      return FlSpot(daysDiff, _getMoodValue(entry['emotion']));
    }).toList();
  }

  Future<void> _captureAndShareGraph() async {
    try {
      RenderRepaintBoundary boundary =
          _graphKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/mood_graph.png');
        await file.writeAsBytes(byteData.buffer.asUint8List());

        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'EmoTune 기분 변화 그래프',
        );
      }
    } catch (e) {
      print('Error capturing graph: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(Duration(days: 30));

    return Dialog(
      child: Container(
        padding: EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '최근 한 달간의 기분 변화',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.file_upload_outlined),
                  color: Colors.black,
                  onPressed: _captureAndShareGraph,
                  tooltip: '그래프 내보내기',
                ),
              ],
            ),
            SizedBox(height: 20),
            Expanded(
              child: RepaintBoundary(
                key: _graphKey,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: true),
                    titlesData: FlTitlesData(
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 5,
                          getTitlesWidget: (value, meta) {
                            final date = thirtyDaysAgo
                                .add(Duration(days: value.toInt()));
                            if (date.isAtSameMomentAs(now)) {
                              return Text('오늘');
                            }
                            return Text('-${30 - value.toInt()}일');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            switch (value.toInt()) {
                              case 2:
                                return Text('매우 좋음',
                                    style: TextStyle(fontSize: 10));
                              case 1:
                                return Text('좋음',
                                    style: TextStyle(fontSize: 10));
                              case 0:
                                return Text('보통',
                                    style: TextStyle(fontSize: 10));
                              case -1:
                                return Text('나쁨',
                                    style: TextStyle(fontSize: 10));
                              case -2:
                                return Text('매우 나쁨',
                                    style: TextStyle(fontSize: 10));
                              default:
                                return const Text('');
                            }
                          },
                          reservedSize: 60,
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: true),
                    minX: _getMinX(),
                    maxX: 30,
                    minY: -2,
                    maxY: 2,
                    lineBarsData: [
                      LineChartBarData(
                        spots: _getSpots(),
                        isCurved: true,
                        curveSmoothness: 0.35,
                        color: Colors.grey.shade600,
                        dotData: FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.grey.shade400.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}
