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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE summaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_text TEXT NOT NULL,
        generated_summary TEXT NOT NULL,
        task_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        latency_seconds REAL,
        ttft_seconds REAL,
        tokens_per_sec REAL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE summaries ADD COLUMN latency_seconds REAL;');
      await db.execute('ALTER TABLE summaries ADD COLUMN ttft_seconds REAL;');
      await db.execute('ALTER TABLE summaries ADD COLUMN tokens_per_sec REAL;');
    }
  }

  Future<int> insertSummary(SummaryRecord record) async {
    final db = await instance.database;
    return await db.insert(
      'summaries',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SummaryRecord>> getAllSummaries() async {
    final db = await instance.database;
    final result = await db.query('summaries', orderBy: 'id DESC');
    return result.map((map) => SummaryRecord.fromMap(map)).toList();
  }

  Future<List<SummaryRecord>> searchSummaries(String query, {String? taskType}) async {
    final db = await instance.database;
    String whereClause = '(generated_summary LIKE ? OR original_text LIKE ?)';
    List<dynamic> whereArgs = ['%$query%', '%$query%'];

    if (taskType != null && taskType != 'All') {
      whereClause += ' AND task_type = ?';
      whereArgs.add(taskType);
    }

    final result = await db.query(
      'summaries',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'id DESC',
    );
    return result.map((map) => SummaryRecord.fromMap(map)).toList();
  }

  Future<int> deleteSummary(int id) async {
    final db = await instance.database;
    return await db.delete('summaries', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }
}