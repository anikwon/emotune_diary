import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:emotune_diary/graph_dialog.dart';
import 'package:emotune_diary/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top],
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmoTune',
      //debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Colors.grey.shade800,
          secondary: Colors.grey.shade800,
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.all(Colors.grey.shade800),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
          ),
        ),
      ),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ko', 'KR'),
      ],
      home: SplashScreen(),
    );
  }
}

class EmotionDiary extends StatefulWidget {
  const EmotionDiary({super.key});

  @override
  _EmotionDiaryState createState() => _EmotionDiaryState();
}

class _EmotionDiaryState extends State<EmotionDiary> {
  late Database _database;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final Map<DateTime, List<Map<String, dynamic>>> _diaryEntries = {};
  final TextEditingController _contentController = TextEditingController();
  String _selectedEmotion = '보통';
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late ScrollController _scrollController;
  final double diaryCardHeight = 200.0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _showMoodWarning = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
    _scrollController = ScrollController();
  }

  Future<void> _clearSharePlusCache() async {
    final cacheDir = await getTemporaryDirectory();
    final sharePlusCache = Directory('${cacheDir.path}/share_plus');
    if (await sharePlusCache.exists()) {
      await sharePlusCache.delete(recursive: true);
    }
  }

  Future<void> _initializeDatabase() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), 'diary.db'),
      onCreate: (db, version) {
        return db.execute(
          "CREATE TABLE diaries(id INTEGER PRIMARY KEY, date TEXT, content TEXT, emotion TEXT)",
        );
      },
      version: 1,
    );
    _loadDiaryEntries();
  }

  Future<void> _loadDiaryEntries() async {
    final maps = await _database.query('diaries');
    setState(() {
      _diaryEntries.clear();
      for (var map in maps) {
        DateTime date = DateTime.parse(map['date'].toString());
        if (_diaryEntries[date] == null) {
          _diaryEntries[date] = [];
        }
        _diaryEntries[date]!.add(map);
      }
    });

    // Scroll to last entry after loading
    if (_diaryEntries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    _checkMoodChanges();
  }

  Future<void> _playClickSound() async {
    await _audioPlayer.play(AssetSource('sounds/click.mp3'));
  }

  Future<void> _addOrUpdateDiary() async {
    await _database.insert(
      'diaries',
      {
        'date': _selectedDay.toString(),
        'content': _contentController.text,
        'emotion': _selectedEmotion,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _playClickSound(); // 클릭 사운드 재생
    _loadDiaryEntries();
  }

  Future<void> _updateDiaryContent(int id) async {
    await _database.update(
      'diaries',
      {
        'content': _contentController.text,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _playClickSound(); // 클릭 사운드 재생
    _loadDiaryEntries();
  }

  Future<void> _deleteDiary(int id) async {
    await _database.delete(
      'diaries',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _playClickSound(); // 클릭 사운드 재생
    _loadDiaryEntries();
  }

  List<Map<String, dynamic>> _getDiariesForDay(DateTime day) {
    // Normalize input date to remove time component
    final normalizedDay = DateTime(day.year, day.month, day.day);

    // Get entries and normalize stored dates
    final entries = _diaryEntries.entries.where((entry) {
      final entryDate =
          DateTime(entry.key.year, entry.key.month, entry.key.day);
      return entryDate.isAtSameMomentAs(normalizedDay);
    });

    return entries.isEmpty ? [] : entries.first.value;
  }

  List<DateTime> get _sortedDates {
    return _diaryEntries.keys.toList()..sort();
  }

  @override
  void dispose() {
    _clearSharePlusCache();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  IconData _getEmotionIcon(String emotion) {
    switch (emotion) {
      case '매우 좋음':
        return Icons.sentiment_very_satisfied;
      case '좋음':
        return Icons.sentiment_satisfied;
      case '보통':
        return Icons.sentiment_neutral;
      case '나쁨':
        return Icons.sentiment_dissatisfied;
      case '매우 나쁨':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey.shade500,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          'EmoTune Diary',
          style: TextStyle(
            fontSize: 24,
            fontStyle: FontStyle.italic,
          ),
        ),
        leading: PopupMenuButton<String>(
          icon: Icon(Icons.menu),
          onSelected: (value) async {
            switch (value) {
              case '그래프':
                final now = DateTime.now();
                final thirtyDaysAgo = now.subtract(Duration(days: 30));

                final diaries = await _database.query(
                  'diaries',
                  where: 'date > ?',
                  whereArgs: [thirtyDaysAgo.toIso8601String()],
                  orderBy: 'date ASC',
                );

                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) =>
                        MoodGraphDialog(diaryEntries: diaries),
                  );
                }
                break;
              case '일기 내보내기':
                _exportDiaries();
                break;
              case '백업/복원':
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      '어떤 작업을 하시겠습니까?',
                      style: TextStyle(fontSize: 18),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _backupDatabase();
                        },
                        child: Text('백업'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _restoreDatabase();
                        },
                        child: Text('복원'),
                      ),
                    ],
                  ),
                );
                break;
              case '유용한 링크':
                _showLinksDialog(context);
                break;
              case '정보':
                showDialog(
                  context: context,
                  builder: (context) => AboutDialog(
                    applicationName: 'EmoTune Diary',
                    applicationVersion: '1.0.0',
                    applicationIcon: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 50,
                      height: 50,
                    ),
                    children: [
                      SizedBox(height: 5),
                      Text(
                        '기분을 관리하는 일기장 앱',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '매일의 감정을 기록하고 돌아보며\n자신의 마음을 이해하는 시간을 가져보세요.\n\n* 이 앱은 외부 저장소에 데이터를 저장하지 않습니다.',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 16),
                      Text(
                        '© 2024 Paul Jack Kwon. All rights reserved.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<String>(
              value: '그래프',
              child: Row(
                children: [
                  Icon(
                    Icons.bar_chart,
                    color: Colors.grey.shade600,
                  ),
                  SizedBox(width: 8),
                  Text('기분 그래프'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: '일기 내보내기',
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file,
                    color: Colors.grey.shade600,
                  ),
                  SizedBox(width: 8),
                  Text('일기 내보내기'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: '백업/복원',
              child: Row(
                children: [
                  Icon(Icons.backup, color: Colors.grey.shade600),
                  SizedBox(width: 8),
                  Text('백업/복원'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              key: UniqueKey(),
              value: '유용한 링크',
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    color: Colors.grey.shade600,
                  ),
                  SizedBox(width: 8),
                  Text('유용한 링크'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: '정보',
              child: Row(
                children: [
                  Icon(
                    Icons.info,
                    color: Colors.grey.shade600,
                  ),
                  SizedBox(width: 8),
                  Text('정보'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.mode_edit_outline),
            onPressed: () {
              _showAddDiaryDialog(context);
            },
            color: Colors.white.withOpacity(
                (_getDiariesForDay(_selectedDay).isEmpty &&
                        DateTime(_selectedDay.year, _selectedDay.month,
                                    _selectedDay.day)
                                .compareTo(DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day)) <=
                            0)
                    ? 1.0
                    : 0.2),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: EdgeInsets.only(bottom: 10),
            child: TableCalendar(
              locale: 'ko_KR',
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              availableCalendarFormats: const {
                CalendarFormat.month: '월',
                CalendarFormat.twoWeeks: '2주',
                CalendarFormat.week: '1주',
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(color: Colors.white),
                selectedTextStyle: TextStyle(color: Colors.white),
                markersAlignment: Alignment.bottomCenter,
                markerDecoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                markerSize: 6.0,
                markersMaxCount: 1,
                outsideDaysVisible: true, // Show days outside current month
                cellMargin: EdgeInsets.all(6),
                markersOffset: PositionedOffset(bottom: 7),
              ),
              daysOfWeekHeight: 24,
              rowHeight: 40,
              selectedDayPredicate: (day) {
                return isSameDay(_selectedDay, day);
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _scrollToSelectedDay(selectedDay);
              },
              onFormatChanged: (format) {
                setState(() {
                  _calendarFormat = format;
                });
              },
              eventLoader: (day) {
                return _getDiariesForDay(day);
              },
              calendarBuilders: CalendarBuilders(
                headerTitleBuilder: (context, day) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<DateTime>(
                        value: DateTime(day.year, day.month),
                        items: List.generate(12, (index) {
                          final month = DateTime(day.year, index + 1);
                          return DropdownMenuItem(
                            value: month,
                            child: Text('${month.year}년 ${month.month}월'),
                          );
                        }),
                        onChanged: (date) {
                          if (date != null) {
                            setState(() {
                              _focusedDay = date;
                            });
                          }
                        },
                        underline: Container(), // Remove underline
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  );
                },
                markerBuilder: (context, date, events) {
                  if (events.isNotEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(
                          top: 4), // Add margin to prevent cutoff
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      width: 6.0,
                      height: 6.0,
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
            ),
          ),
          SizedBox(height: 10),
          (_showMoodWarning) ? _buildMoodWarning() : SizedBox.shrink(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _sortedDates.length,
              itemBuilder: (context, index) {
                final date = _sortedDates[index];
                final diaries = _getDiariesForDay(date);
                return Dismissible(
                  key: Key(diaries[0]['id'].toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.grey.shade400,
                    child: Text('삭제',
                        style: TextStyle(fontSize: 20, color: Colors.white)),
                  ),
                  onDismissed: (direction) {
                    _deleteDiary(diaries[0]['id']);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () =>
                          _showEditDiaryDialog(context, diaries[0]['id'], date),
                      child: Card(
                        color: Colors.grey.shade200,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${date.year}년 ${date.month}월 ${date.day}일',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w400),
                                  ),
                                  if (diaries.isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(_getEmotionIcon(
                                            diaries[0]['emotion'])),
                                        SizedBox(width: 8),
                                        Text(diaries[0]['emotion']),
                                      ],
                                    ),
                                ],
                              ),
                              SizedBox(height: 12),
                              SizedBox(
                                height: diaryCardHeight - 70,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Text(
                                          diaries[0]['content'],
                                          style: GoogleFonts.nanumMyeongjo(
                                            fontSize: 14,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToSelectedDay(DateTime selectedDay) {
    if (_sortedDates.isEmpty) return;

    final double cardTotalHeight = 224; // 전체 높이

    final index = _sortedDates.indexWhere((date) =>
        date.year == selectedDay.year &&
        date.month == selectedDay.month &&
        date.day == selectedDay.day);

    if (index != -1) {
      _scrollController.animateTo(
        index * cardTotalHeight,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showAddDiaryDialog(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);

    // 선택된 날짜가 오늘보다 미래인 경우에만 스낵바 표시
    if (selectedDate.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('미래 날짜에는 일기를 작성할 수 없습니다'),
          backgroundColor: Colors.grey.shade600,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 선택된 날짜의 일기 확인
    var diaries = _getDiariesForDay(_selectedDay);

    if (diaries.isNotEmpty) {
      // 이미 일기가 존재하는 경우 스낵바 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미 작성된 일기가 있습니다'),
          backgroundColor: Colors.grey.shade600,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _contentController.clear();
    _selectedEmotion = '보통';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('오늘의 기분'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  children: [
                    RadioListTile<String>(
                      title: Text('매우 좋음'),
                      value: '매우 좋음',
                      groupValue: _selectedEmotion,
                      onChanged: (value) {
                        setState(() {
                          _selectedEmotion = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text('좋음'),
                      value: '좋음',
                      groupValue: _selectedEmotion,
                      onChanged: (value) {
                        setState(() {
                          _selectedEmotion = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text('보통'),
                      value: '보통',
                      groupValue: _selectedEmotion,
                      onChanged: (value) {
                        setState(() {
                          _selectedEmotion = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text('나쁨'),
                      value: '나쁨',
                      groupValue: _selectedEmotion,
                      onChanged: (value) {
                        setState(() {
                          _selectedEmotion = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text('매우 나쁨'),
                      value: '매우 나쁨',
                      groupValue: _selectedEmotion,
                      onChanged: (value) {
                        setState(() {
                          _selectedEmotion = value!;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('취소'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DiaryWritePage(
                        contentController: _contentController,
                        onSave: _addOrUpdateDiary,
                      ),
                    ),
                  );
                },
                child: Text('다음'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showEditDiaryDialog(BuildContext context, int id, DateTime cardDate) {
    final diary = _diaryEntries[cardDate]?.firstWhere((d) => d['id'] == id);
    if (diary == null) return;

    _contentController.text = diary['content'];

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '일기 수정',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // 수정 불가능한 기분 상태 표시
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_getEmotionIcon(diary['emotion'])),
                      SizedBox(width: 8),
                      Text(
                        diary['emotion'],
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '일기를 수정해주세요...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('취소'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        _updateDiaryContent(id);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                          // backgroundColor: Colors.grey.shade600,
                          ),
                      child: Text('저장'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 스와이프로 일기 삭제 기능 추가 후 필요 없어진 코드
  // void _showDeleteConfirmationDialog(BuildContext context, int id) {
  //   showDialog(
  //     context: context,
  //     builder: (context) {
  //       return AlertDialog(
  //         title: Text('삭제하시겠습니까?'),
  //         actions: [
  //           TextButton(
  //             onPressed: () {
  //               Navigator.of(context).pop();
  //             },
  //             child: Text('아니오'),
  //           ),
  //           TextButton(
  //             onPressed: () {
  //               _deleteDiary(id);
  //               Navigator.of(context).pop();
  //             },
  //             child: Text('예'),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  Future<void> _exportDiaries() async {
    bool? confirm = await showDialog<bool>(
      context: this.context,
      builder: (context) => AlertDialog(
        title: Text('일기 내보내기'),
        content: Text('모든 일기를 텍스트 파일로 내보내시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('확인'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final allDiaries = await _database.query('diaries', orderBy: 'date ASC');
      final StringBuffer buffer = StringBuffer();
      buffer.writeln('=== EmoTune 일기장 ===\n');

      for (var diary in allDiaries) {
        final date = DateTime.parse(diary['date'] as String);
        final dateStr = '${date.year}년 ${date.month}월 ${date.day}일';
        final emotion = diary['emotion'] as String;
        final content = diary['content'] as String;

        buffer.writeln('날짜: $dateStr');
        buffer.writeln('감정: $emotion');
        buffer.writeln('내용:');
        buffer.writeln(content);
        buffer.writeln('\n${'-' * 40}\n');
      }

      // Get download folder path
      final downloadPath = '/storage/emulated/0/Download';
      final fileName = 'emotune_diary_${_getFormattedDateTime()}.txt';
      final file = File('$downloadPath/$fileName');

      // Write with UTF-8 encoding
      await file.writeAsString(
        buffer.toString(),
        encoding: utf8,
      );

      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('다운로드 폴더에 일기가 저장되었습니다'),
          backgroundColor: Colors.grey.shade600,
        ),
      );
    }
  }

  void _showLinksDialog(BuildContext context) => showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('유용한 링크'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => Share.share('자살예방상담전화: 109'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: Colors.black),
                      SizedBox(width: 8),
                      Text('자살예방 상담전화: 109',
                          style: TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => Share.share('국립정신건강센터: 1577-0199'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.link, color: Colors.black),
                      SizedBox(width: 8),
                      Text('국립정신건강센터: 1577-0199',
                          style: TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () =>
                    Share.share('개발자 블로그: https://brunch.co.kr/@pauljack'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Colors.black),
                      SizedBox(width: 8),
                      Text('개발자 블로그:\nhttps://brunch.co.kr/@pauljack',
                          style: TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('닫기'),
            ),
          ],
        ),
      );

  void _checkMoodChanges() {
    // 최근 14일간의 데이터 분석
    final now = DateTime.now();
    final fourteenDaysAgo = now.subtract(Duration(days: 14));
    final recentDiaries = _diaryEntries.entries
        .where((e) => e.key.isAfter(fourteenDaysAgo))
        .expand((e) => e.value)
        .toList();

    final hasWarning = MoodAnalyzer.hasSevereMoodChange(recentDiaries);

    if (hasWarning && !_showMoodWarning) {
      setState(() {
        _showMoodWarning = true;
      });
      _audioPlayer.play(AssetSource('sounds/ring_drop.mp3'));
    } else if (!hasWarning && _showMoodWarning) {
      setState(() {
        _showMoodWarning = false;
      });
    }
  }

  // Add method to get Download directory
  Future<String> _getDownloadPath() async {
    final directory = Directory('/storage/emulated/0/Download');
    return directory.path;
  }

  // Add helper method for filename generation
  String _getFormattedDateTime() {
    final now = DateTime.now();
    return now.toString().replaceAll(RegExp(r'[^0-9]'), '');
  }

  // Update backup method
  Future<void> _backupDatabase() async {
    bool? confirm = await showDialog<bool>(
      context: this.context,
      builder: (context) => AlertDialog(
        title: Text('백업'),
        content: Text('데이터베이스를 백업하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('확인'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final downloadPath = await _getDownloadPath();
        final dbPath = join(await getDatabasesPath(), 'diary.db');
        final backupPath = join(downloadPath, 'emotune_diary_backup.db');

        await File(dbPath).copy(backupPath);

        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text('데이터베이스가 다운로드 폴더에 백업되었습니다'),
            backgroundColor: Colors.grey.shade600,
          ),
        );
      } catch (e) {
        debugPrint('Backup error: $e');
      }
    }
  }

// Update restore method
  Future<void> _restoreDatabase() async {
    bool? confirm = await showDialog<bool>(
      context: this.context,
      builder: (context) => AlertDialog(
        title: Text('복원'),
        content: Text('경고:\n백업 데이터가 현재 데이터를 덮어씁니다.\n\n계속하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('확인'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final downloadPath = await _getDownloadPath();
        final backupPath = join(downloadPath, 'emotune_diary_backup.db');

        if (await File(backupPath).exists()) {
          final dbPath = join(await getDatabasesPath(), 'diary.db');
          await File(backupPath).copy(dbPath);
          await _loadDiaryEntries();

          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text('데이터베이스가 복원되었습니다'),
              backgroundColor: Colors.grey.shade600,
            ),
          );
        } else {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text('백업 파일을 찾을 수 없습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Restore error: $e');
      }
    }
  }
}

class DiaryWritePage extends StatelessWidget {
  final TextEditingController contentController;
  final Function onSave;

  const DiaryWritePage({
    required this.contentController,
    required this.onSave,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey.shade500,
        foregroundColor: Colors.white,
        title: Text('일기 작성'),
        actions: [
          TextButton(
            onPressed: () {
              onSave();
              Navigator.pop(context);
            },
            child: Text(
              '저장',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: contentController,
          maxLines: null,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '일기를 작성해주세요...',
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }
}

// 기분 분석 클래스
class MoodAnalyzer {
  static double getMoodValue(String mood) {
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

  static bool hasSevereMoodChange(List<Map<String, dynamic>> diaries) {
    if (diaries.length < 3) return false;

    // Sort diaries by date
    diaries.sort((a, b) => DateTime.parse(a['date'].toString())
        .compareTo(DateTime.parse(b['date'].toString())));

    // Convert to mood values
    List<double> moodValues =
        diaries.map((d) => getMoodValue(d['emotion'])).toList();

    // Calculate moving average with window size 3
    int windowSize = 3;
    List<double> movingAverages = [];

    for (int i = 0; i <= moodValues.length - windowSize; i++) {
      double sum = 0;
      for (int j = 0; j < windowSize; j++) {
        sum += moodValues[i + j];
      }
      movingAverages.add(sum / windowSize);
    }

    // Check for significant deviations
    double deviationThreshold =
        1.5; // Alert if mood deviates more than 1.5 points

    for (int i = windowSize - 1; i < moodValues.length; i++) {
      double currentValue = moodValues[i];
      double movingAvg = movingAverages[i - windowSize + 1];

      // Check if current mood deviates significantly from moving average
      if ((currentValue - movingAvg).abs() > deviationThreshold) {
        return true;
      }
    }

    return false;
  }
}

// 경고 메시지 위젯
Widget _buildMoodWarning() {
  return Container(
    margin: EdgeInsets.all(8),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text(
              '급격한 기분 변화가 감지되었습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          '도움이 필요하시다면:\n'
          '• 자살예방상담전화: 109\n'
          '• 국립정신건강센터 상담: 1577-0199\n'
          '• 가까운 정신건강복지센터를 방문해보세요',
          style: TextStyle(fontSize: 14),
        ),
      ],
    ),
  );
}
