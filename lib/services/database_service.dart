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

    return openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
        tokens_per_sec REAL,
        engine_type TEXT,
        model_name TEXT,
        token_count INTEGER
      )
    ''');

    await _createBenchmarkTables(db);
  }

  Future<void> _createBenchmarkTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS benchmark_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        passage TEXT NOT NULL,
        instruction TEXT NOT NULL,
        runs_per_model INTEGER NOT NULL,
        model_count INTEGER NOT NULL,
        completed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS benchmark_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        model_order INTEGER NOT NULL,
        run_number INTEGER NOT NULL,
        model_id TEXT NOT NULL,
        model_name TEXT NOT NULL,
        model_path TEXT NOT NULL,
        engine_type TEXT NOT NULL,
        prompt_format TEXT NOT NULL,
        ttft_seconds REAL,
        latency_seconds REAL NOT NULL,
        token_count INTEGER NOT NULL,
        output_text TEXT NOT NULL,
        error_message TEXT,
        FOREIGN KEY (session_id)
          REFERENCES benchmark_sessions (id)
          ON DELETE CASCADE,
        UNIQUE (session_id, model_order, run_number)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_benchmark_runs_session_id
      ON benchmark_runs (session_id)
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN latency_seconds REAL;',
      );
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN ttft_seconds REAL;',
      );
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN tokens_per_sec REAL;',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN engine_type TEXT;',
      );
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN model_name TEXT;',
      );
      await db.execute(
        'ALTER TABLE summaries ADD COLUMN token_count INTEGER;',
      );
    }
    if (oldVersion < 4) {
      await _createBenchmarkTables(db);
    }
  }

  Future<int> insertSummary(SummaryRecord record) async {
    final db = await instance.database;
    return db.insert(
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

  Future<List<SummaryRecord>> searchSummaries(
    String query, {
    String? taskType,
  }) async {
    final db = await instance.database;
    String whereClause = '(generated_summary LIKE ? OR original_text LIKE ?)';
    final List<dynamic> whereArgs = ['%$query%', '%$query%'];

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
    return db.delete('summaries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertCompletedBenchmark({
    required String passage,
    required String instruction,
    required int runsPerModel,
    required int modelCount,
    required List<Map<String, Object?>> runs,
  }) async {
    final db = await instance.database;

    return db.transaction((txn) async {
      final sessionId = await txn.insert('benchmark_sessions', {
        'passage': passage,
        'instruction': instruction,
        'runs_per_model': runsPerModel,
        'model_count': modelCount,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      });

      for (final run in runs) {
        await txn.insert('benchmark_runs', {
          'session_id': sessionId,
          ...run,
        });
      }

      return sessionId;
    });
  }

  Future<Map<String, Object?>?> getLatestCompletedBenchmark() async {
    final db = await instance.database;
    final sessions = await db.query(
      'benchmark_sessions',
      orderBy: 'completed_at DESC, id DESC',
      limit: 1,
    );

    if (sessions.isEmpty) return null;

    final session = Map<String, Object?>.from(sessions.first);
    final sessionId = session['id'] as int;
    final runs = await db.query(
      'benchmark_runs',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'model_order ASC, run_number ASC, id ASC',
    );

    return {
      ...session,
      'runs': runs.map((row) => Map<String, Object?>.from(row)).toList(),
    };
  }

  Future<void> close() async {
    final db = await instance.database;
    await db.close();
    _database = null;
  }
}
