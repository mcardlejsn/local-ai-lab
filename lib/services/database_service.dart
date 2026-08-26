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
      version: 6,
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
        accuracy_score INTEGER,
        score_note TEXT,
        recall_found INTEGER,
        recall_total INTEGER,
        missed_fact_ids TEXT,
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
      // Creates the benchmark tables at their current shape, scoring and
      // recall columns included, so neither migration below is needed here.
      await _createBenchmarkTables(db);
    } else {
      if (oldVersion < 5) {
        await db.execute(
          'ALTER TABLE benchmark_runs ADD COLUMN accuracy_score INTEGER;',
        );
        await db.execute(
          'ALTER TABLE benchmark_runs ADD COLUMN score_note TEXT;',
        );
      }
      if (oldVersion < 6) {
        await db.execute(
          'ALTER TABLE benchmark_runs ADD COLUMN recall_found INTEGER;',
        );
        await db.execute(
          'ALTER TABLE benchmark_runs ADD COLUMN recall_total INTEGER;',
        );
        await db.execute(
          'ALTER TABLE benchmark_runs ADD COLUMN missed_fact_ids TEXT;',
        );
      }
    }
  }

  /// Sets or clears the manual accuracy score on a single saved run.
  /// Passing null for either field clears it.
  Future<int> updateBenchmarkRunScore({
    required int runId,
    int? accuracyScore,
    String? scoreNote,
  }) async {
    final db = await instance.database;
    return db.update(
      'benchmark_runs',
      {
        'accuracy_score': accuracyScore,
        'score_note': scoreNote,
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
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

  /// Deletes a completed benchmark session. Its rows in `benchmark_runs` go
  /// with it via `ON DELETE CASCADE`, which is live because `onConfigure`
  /// turns on `PRAGMA foreign_keys`.
  Future<int> deleteBenchmarkSession(int sessionId) async {
    final db = await instance.database;
    return db.delete(
      'benchmark_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
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

    return _loadSessionWithRuns(db, sessions.first);
  }

  /// Loads one saved session by id, with all of its ordered run records.
  /// Read-only; returns null if the session no longer exists.
  Future<Map<String, Object?>?> getCompletedBenchmarkById(int sessionId) async {
    final db = await instance.database;
    final sessions = await db.query(
      'benchmark_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (sessions.isEmpty) return null;

    return _loadSessionWithRuns(db, sessions.first);
  }

  /// Lightweight archive listing: every completed session newest first, with
  /// its model names in saved order but without loading any output text.
  Future<List<Map<String, Object?>>> getBenchmarkSessionSummaries() async {
    final db = await instance.database;
    final sessions = await db.query(
      'benchmark_sessions',
      orderBy: 'completed_at DESC, id DESC',
    );

    if (sessions.isEmpty) return [];

    final ids = sessions.map((row) => row['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final nameRows = await db.rawQuery(
      'SELECT DISTINCT session_id, model_order, model_name '
      'FROM benchmark_runs '
      'WHERE session_id IN ($placeholders) '
      'ORDER BY session_id ASC, model_order ASC',
      ids,
    );

    final namesBySession = <int, List<String>>{};
    for (final row in nameRows) {
      final sessionId = row['session_id'] as int;
      namesBySession
          .putIfAbsent(sessionId, () => <String>[])
          .add(row['model_name'] as String);
    }

    return sessions.map((row) {
      final session = Map<String, Object?>.from(row);
      final sessionId = session['id'] as int;
      return {
        ...session,
        'model_names': namesBySession[sessionId] ?? const <String>[],
      };
    }).toList();
  }

  Future<Map<String, Object?>> _loadSessionWithRuns(
    Database db,
    Map<String, Object?> sessionRow,
  ) async {
    final session = Map<String, Object?>.from(sessionRow);
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