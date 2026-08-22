import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/summary_record.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('local_summaries.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE summaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_text TEXT NOT NULL,
        generated_summary TEXT NOT NULL,
        task_type TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertSummary(SummaryRecord record) async {
    final db = await database;
    return await db.insert('summaries', record.toMap());
  }

  Future<List<SummaryRecord>> getAllSummaries() async {
    final db = await database;
    final result = await db.query('summaries', orderBy: 'id DESC');
    return result.map((map) => SummaryRecord.fromMap(map)).toList();
  }

  Future<int> deleteSummary(int id) async {
    final db = await database;
    return await db.delete(
      'summaries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}