import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/summary_record.dart';

class DatabaseService {
  DatabaseService._init();
  static final DatabaseService instance = DatabaseService._init();

  static Database? _database;

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
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';

    await db.execute('''
      CREATE TABLE summaries (
        id $idType,
        original_text $textType,
        generated_summary $textType,
        task_type $textType,
        created_at $textType
      )
    ''');
  }

  Future<int> insertSummary(SummaryRecord record) async {
    final db = await database;
    return await db.insert(
      'summaries',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SummaryRecord>> getAllSummaries() async {
    final db = await database;
    final result = await db.query(
      'summaries',
      orderBy: 'created_at DESC',
    );
    return result.map((json) => SummaryRecord.fromMap(json)).toList();
  }

  Future<List<SummaryRecord>> searchSummaries({
    String? query,
    String? taskType,
  }) async {
    final db = await database;

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (query != null && query.trim().isNotEmpty) {
      final sanitizedQuery = '%${query.trim()}%';
      whereClauses.add(
        '(original_text LIKE ? OR generated_summary LIKE ?)',
      );
      whereArgs.addAll([sanitizedQuery, sanitizedQuery]);
    }

    if (taskType != null && taskType.isNotEmpty && taskType != 'All') {
      whereClauses.add('task_type = ?');
      whereArgs.add(taskType);
    }

    final whereString =
        whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final result = await db.query(
      'summaries',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
    );

    return result.map((json) => SummaryRecord.fromMap(json)).toList();
  }

  Future<int> deleteSummary(int id) async {
    final db = await database;
    return await db.delete(
      'summaries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}