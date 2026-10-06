import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDb {
  AppDb._();
  static final instance = AppDb._();
  late Database db;

  Future<void> init() async {
    final p = join(await getDatabasesPath(), 'transport_stock_asiri.db');
    db = await openDatabase(p, version: 2, onCreate: (d, v) async {
      await d.execute("CREATE TABLE parts(id TEXT PRIMARY KEY, name TEXT NOT NULL, code TEXT NOT NULL UNIQUE, in_qty INTEGER NOT NULL DEFAULT 0, out_qty INTEGER NOT NULL DEFAULT 0, low_limit INTEGER NOT NULL DEFAULT 5, created_at TEXT NOT NULL)");
      await d.execute("CREATE TABLE movements(id INTEGER PRIMARY KEY AUTOINCREMENT, part_id TEXT NOT NULL, type TEXT NOT NULL, qty INTEGER NOT NULL, note TEXT, created_at TEXT NOT NULL)");
      await d.execute("CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL)");
    }, onUpgrade: (d, old, newV) async {
      if (old < 2) {
        await d.execute("ALTER TABLE parts ADD COLUMN low_limit INTEGER NOT NULL DEFAULT 5");
        await d.execute("ALTER TABLE parts ADD COLUMN created_at TEXT NOT NULL DEFAULT ''");
      }
    });
  }

  Future<bool> hasUsers() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users'))! > 0;

  Future<void> createUser(String username, String hash) async {
    await db.insert('users', {'username': username, 'password_hash': hash});
  }

  Future<bool> login(String username, String hash) async {
    final r = await db.query('users',
        where: 'username = ? AND password_hash = ?',
        whereArgs: [username, hash], limit: 1);
    return r.isNotEmpty;
  }

  Future<void> addPart({required String id, required String name, required String code,
      required int qty, required int lowLimit}) async {
    await db.transaction((txn) async {
      await txn.insert('parts', {'id': id, 'name': name, 'code': code,
        'in_qty': qty, 'out_qty': 0, 'low_limit': lowLimit,
        'created_at': DateTime.now().toIso8601String()});
      if (qty > 0) {
        await txn.insert('movements', {'part_id': id, 'type': 'IN', 'qty': qty,
          'note': 'Initial stock', 'created_at': DateTime.now().toIso8601String()});
      }
    });
  }

  Future<void> editPart(String id, String name, String code, int lowLimit) async {
    await db.update('parts', {'name': name, 'code': code, 'low_limit': lowLimit},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePart(String id) async {
    await db.transaction((txn) async {
      await txn.delete('movements', where: 'part_id = ?', whereArgs: [id]);
      await txn.delete('parts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, dynamic>>> parts(String q) async {
    final rows = await db.query('parts',
      where: q.trim().isEmpty ? null : 'name LIKE ? OR code LIKE ?',
      whereArgs: q.trim().isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name COLLATE NOCASE');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['balance'] = (m['in_qty'] as int) - (m['out_qty'] as int);
      return m;
    }).toList();
  }

  Future<Map<String, dynamic>?> getPart(String id) async {
    final rows = await db.query('parts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first);
    m['balance'] = (m['in_qty'] as int) - (m['out_qty'] as int);
    return m;
  }

  Future<bool> addStock(String id, int qty, String note) async {
    if (qty <= 0) return false;
    return db.transaction((txn) async {
      final r = await txn.query('parts', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return false;
      await txn.update('parts', {'in_qty': (r.first['in_qty'] as int) + qty},
          where: 'id = ?', whereArgs: [id]);
      await txn.insert('movements', {'part_id': id, 'type': 'IN', 'qty': qty,
        'note': note, 'created_at': DateTime.now().toIso8601String()});
      return true;
    });
  }

  Future<Map<String, dynamic>?> stockOut(String id, int qty, String note) async {
    if (qty <= 0) return null;
    Map<String, dynamic>? result;
    await db.transaction((txn) async {
      final r = await txn.query('parts', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) return;
      final balance = (r.first['in_qty'] as int) - (r.first['out_qty'] as int);
      if (qty > balance) return;
      await txn.update('parts', {'out_qty': (r.first['out_qty'] as int) + qty},
          where: 'id = ?', whereArgs: [id]);
      await txn.insert('movements', {'part_id': id, 'type': 'OUT', 'qty': qty,
        'note': note, 'created_at': DateTime.now().toIso8601String()});
      result = {'name': r.first['name'], 'balance': balance - qty};
    });
    return result;
  }

  Future<List<Map<String, dynamic>>> movements() async {
    final r = await db.rawQuery('SELECT m.*, p.name, p.code FROM movements m JOIN parts p ON p.id=m.part_id ORDER BY m.created_at DESC');
    return r.map((x) => Map<String, dynamic>.from(x)).toList();
  }

  Future<Map<String, int>> summary() async {
    final rows = await db.query('parts');
    int stock = 0, inQ = 0, outQ = 0, low = 0;
    for (final r in rows) {
      final i = r['in_qty'] as int, o = r['out_qty'] as int;
      final b = i - o;
      stock += b; inQ += i; outQ += o;
      if (b <= (r['low_limit'] as int)) low++;
    }
    return {'parts': rows.length, 'stock': stock, 'in': inQ, 'out': outQ, 'low': low};
  }

  Future<String> exportJson() async {
    return jsonEncode({'version': 1, 'parts': await db.query('parts'), 'movements': await db.query('movements')});
  }
}
