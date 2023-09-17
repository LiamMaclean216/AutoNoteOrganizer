import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note Cock',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: CardsComponent(),
    );
  }
}

class CardsComponent extends StatefulWidget {
  @override
  _CardsComponentState createState() => _CardsComponentState();
}

class _CardsComponentState extends State<CardsComponent>
    with TickerProviderStateMixin {
  List<List<Map<String, String>>> columns =
      List.generate(2, (_) => <Map<String, String>>[]);
  final TextEditingController textController = TextEditingController();
  List<GlobalKey<AnimatedListState>> listKeys = [GlobalKey(), GlobalKey()];

  AnimationController? _controller;
  Animation<Color?>? _colorAnimation;

  @override
  void initState() {
    super.initState();
    loadData();
    _controller = AnimationController(
      duration:
          const Duration(seconds: 1), // Adjust the total duration as needed
      vsync: this,
    );

    _colorAnimation = TweenSequence<Color?>(
      [
        TweenSequenceItem(
          tween: ColorTween(
            begin: Colors.transparent,
            end: Colors.green,
          ),
          weight:
              2, // Adjust the weight to control the relative speed of the transition to green
        ),
        TweenSequenceItem(
          tween: ColorTween(
            begin: Colors.green,
            end: Colors.transparent,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
          weight:
              30, // Adjust the weight to control the relative speed of the transition back to transparent
        ),
      ],
    ).animate(_controller!);

    _controller!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller!.reset();
      }
    });
  }

  void addCard() async {
    try {
      FirebaseFunctions functions = FirebaseFunctions.instance;
      String prompt = textController.text;
      setState(() {
        _controller!.forward();
        textController.clear();
      });
      final result = await functions.httpsCallable('helloWorld').call(
        <String, dynamic>{
          'prompt': prompt,
          'existingTitles': columns
              .expand((column) => column.map((card) => card['title']!))
              .toList()
        },
      );

      if (!result.data['functionCall']) {
        result.data['title'] = 'misc';
        result.data['content'] = prompt;
      }
      setState(() {
        bool foundExistingTitle = false;
        for (List<Map<String, String>> column in columns) {
          for (Map<String, String> card in column) {
            if (card['title'] == result.data['title']) {
              card['content'] =
                  (card['content'] ?? '') + '\n' + result.data['content'];
              foundExistingTitle = true;
              break;
            }
          }
          if (foundExistingTitle) break;
        }

        if (!foundExistingTitle) {
          int minColumnIndex = 0;
          for (int i = 1; i < columns.length; i++) {
            if (columns[i].length < columns[minColumnIndex].length) {
              minColumnIndex = i;
            }
          }

          columns[minColumnIndex].insert(0, {
            'title': result.data['title'],
            'content': result.data['content']
          });
          listKeys[minColumnIndex]
              .currentState
              ?.insertItem(0, duration: Duration(milliseconds: 250));
        }
      });
      print("YOOOOOOO");
      print(result.data);
    } catch (e) {
      print(e);
    }
    saveData();
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('columns', jsonEncode(columns));
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? columnsData = prefs.getString('columns');
    if (columnsData != null) {
      setState(() {
        final List<dynamic> columnList = jsonDecode(columnsData);
        columns = columnList.map<List<Map<String, String>>>((column) {
          return (column as List).map<Map<String, String>>((item) {
            return Map<String, String>.from(item);
          }).toList();
        }).toList();

        // Updating listKeys
        listKeys = List.generate(columns.length, (_) => GlobalKey());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes and shit'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: List.generate(columns.length, (index) {
                return Expanded(
                  child: AnimatedList(
                    key: listKeys[index],
                    initialItemCount: columns[index].length,
                    itemBuilder: (context, itemIndex, animation) {
                      return SizeTransition(
                        sizeFactor: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => CardEditScreen(
                                        index: index,
                                        itemIndex: itemIndex,
                                        initialContent: () =>
                                            columns[index][itemIndex],
                                        title: columns[index][itemIndex]
                                                ['title'] ??
                                            '',
                                        onSaved: (newContent, newTitle) {
                                          setState(() {
                                            columns[index][itemIndex]
                                                ['content'] = newContent;

                                            columns[index][itemIndex]['title'] =
                                                newTitle;
                                            saveData(); // Save data after editing
                                          });
                                        },
                                        onDelete: () {
                                          setState(() {
                                            columns[index].removeAt(itemIndex);
                                            listKeys[index]
                                                .currentState
                                                ?.removeItem(
                                                    itemIndex,
                                                    (context, animation) =>
                                                        Container());
                                            saveData(); // Save data after deletion
                                          });
                                        }),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: 'card-$index-$itemIndex',
                                child: Card(
                                  child: Container(
                                    width: double.infinity,
                                    constraints: BoxConstraints(minHeight: 100),
                                    padding: EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          columns[index][itemIndex]['title'] ??
                                              '',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 8.0),
                                        Text(columns[index][itemIndex]
                                                ['content'] ??
                                            ''),
                                      ],
                                    ),
                                  ),
                                ),
                              )),
                        ),
                      );
                    },
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: AnimatedBuilder(
              animation: _colorAnimation!,
              builder: (context, child) {
                return TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    fillColor: _colorAnimation!.value,
                    filled: true,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.send),
                      onPressed: addCard,
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
}

class CardEditScreen extends StatefulWidget {
  final int index;
  final int itemIndex;
  final String title;
  final Function() initialContent;
  final Function(String, String) onSaved;
  final Function onDelete;

  CardEditScreen({
    required this.initialContent,
    required this.onSaved,
    required this.onDelete,
    required this.index,
    required this.itemIndex,
    required this.title,
  });

  @override
  _CardEditScreenState createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  late TextEditingController contentController;
  late TextEditingController titleController;

  @override
  void initState() {
    super.initState();
    var initialContent = widget.initialContent() as Map<String, String>; // Assuming it returns a Map
    contentController = TextEditingController(text: initialContent['content']);
    titleController = TextEditingController(text: initialContent['title']);

    contentController.addListener(() {
      widget.onSaved(contentController.text, titleController.text);
    });

    titleController.addListener(() {
      widget.onSaved(contentController.text, titleController.text);
    });
  }

  @override
  void dispose() {
    contentController.dispose();
    titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
        tag: 'card-${widget.index}-${widget.itemIndex}',
        child: Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  widget.onDelete();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextFormField(
                  controller: titleController,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(border: InputBorder.none),
                ),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    decoration: InputDecoration(border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
