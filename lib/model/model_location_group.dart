// ignore_for_file: unused_import

/*
Copyright 2023 Stefan Brinkmann <st.brinkmann@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:chaostours/database/cache.dart';
import 'package:chaostours/database/database.dart';
import 'package:chaostours/database/type_adapter.dart';
import 'package:chaostours/logger.dart';
import 'package:chaostours/model/model_location.dart';
import 'package:chaostours/model/model_group.dart';
import 'package:sqflite/sqflite.dart';

class ModelLocationGroup implements ModelGroup {
  static final Logger logger = Logger.logger<ModelLocationGroup>();
  int _id = 0;
  @override
  int get id => _id;
  bool isActive = true;
  LocationPrivacy privacy = LocationPrivacy.normal;
  @override
  String title = '';
  @override
  String description = '';

  ModelLocationGroup({
    this.isActive = true,
    this.privacy = LocationPrivacy.normal,
    this.title = '',
    this.description = '',
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      TableLocationGroup.primaryKey.column: id,
      TableLocationGroup.isActive.column: TypeAdapter.serializeBool(isActive),
      TableLocationGroup.privacy.column: privacy.level,
      TableLocationGroup.title.column: title,
      TableLocationGroup.description.column: description,
    };
  }

  static ModelLocationGroup fromMap(Map<String, Object?> map) {
    var model = ModelLocationGroup(
      isActive:
          TypeAdapter.deserializeBool(map[TableLocationGroup.isActive.column]),
      privacy: LocationPrivacy.byId(map[TableLocationGroup.privacy.column]),
      title:
          TypeAdapter.deserializeString(map[TableLocationGroup.title.column]),
      description: TypeAdapter.deserializeString(
          map[TableLocationGroup.description.column]),
    );
    model._id =
        TypeAdapter.deserializeInt(map[TableLocationGroup.primaryKey.column]);
    return model;
  }

  static Future<int> count() async {
    return await DB.execute<int>(
      (Transaction txn) async {
        const col = 'ct';
        final rows = await txn
            .query(TableLocationGroup.table, columns: ['count(*) as $col']);

        if (rows.isNotEmpty) {
          return TypeAdapter.deserializeInt(rows.first[col], fallback: 0);
        } else {
          return 0;
        }
      },
    );
  }

  static Future<ModelLocationGroup?> byId(int id, [Transaction? txn]) async {
    Future<ModelLocationGroup?> select(Transaction txn) async {
      final rows = await txn.query(TableLocationGroup.table,
          columns: TableLocationGroup.columns,
          where: '${TableLocationGroup.primaryKey.column} = ?',
          whereArgs: [id]);

      return rows.isEmpty ? null : fromMap(rows.first);
    }

    return txn != null
        ? await select(txn)
        : await DB.execute(
            (Transaction txn) async {
              return await select(txn);
            },
          );
  }

  static Future<List<ModelLocationGroup>> byIdList(List<int> ids) async {
    final rows = await DB.execute<List<Map<String, Object?>>>(
      (Transaction txn) async {
        return await txn.query(TableLocationGroup.table,
            columns: TableLocationGroup.columns,
            where:
                '${TableLocationGroup.primaryKey.column} IN (${List.filled(ids.length, '?').join(', ')})',
            whereArgs: ids);
      },
    );
    List<ModelLocationGroup> models = [];
    for (var row in rows) {
      try {
        models.add(fromMap(row));
      } catch (e, stk) {
        logger.error('byIdList iter through rows: $e', stk);
      }
    }
    return models;
  }

  static Future<List<ModelLocationGroup>> _search(String text,
      {int offset = 0, int limit = 50}) async {
    text = '%$text%';
    var rows = await DB.execute<List<Map<String, Object?>>>(
      (txn) async {
        return await txn.query(TableLocationGroup.table,
            where:
                '${TableLocationGroup.title} like ? OR ${TableLocationGroup.description} like ?',
            whereArgs: [text, text],
            offset: offset,
            limit: limit);
      },
    );
    var models = <ModelLocationGroup>[];
    for (var row in rows) {
      try {
        models.add(fromMap(row));
      } catch (e, stk) {
        logger.error('search: $e', stk);
      }
    }
    return models;
  }

  static Future<List<ModelLocationGroup>> select(
      {int offset = 0,
      int limit = 50,
      bool activated = true,
      String search = ''}) async {
    if (search.isNotEmpty) {
      return await ModelLocationGroup._search(search,
          offset: offset, limit: limit);
    }
    final rows = await DB.execute<List<Map<String, Object?>>>(
      (Transaction txn) async {
        return await txn.query(TableLocationGroup.table,
            columns: TableLocationGroup.columns,
            where: '${TableLocationGroup.isActive.column} = ?',
            whereArgs: [TypeAdapter.serializeBool(activated)],
            limit: limit,
            offset: offset,
            orderBy: TableLocationGroup.title.column);
      },
    );
    return rows
        .map(
          (e) => fromMap(e),
        )
        .toList();
  }

  Future<ModelLocationGroup> insert() async {
    var map = toMap();
    map.removeWhere(
        (key, value) => key == TableLocationGroup.primaryKey.column);
    await DB.execute(
      (Transaction txn) async {
        _id = await txn.insert(TableLocationGroup.table, map);
      },
    );
    return this;
  }

  Future<int> update() async {
    if (id <= 0) {
      throw ('update model "$title" has no id');
    }
    var count = await DB.execute<int>(
      (Transaction txn) async {
        return await txn.update(TableLocationGroup.table, toMap(),
            where: '${TableLocationGroup.primaryKey.column} = ?',
            whereArgs: [id]);
      },
    );
    return count;
  }

  Future<List<int>> locationIds() async {
    var col = TableLocationLocationGroup.idLocation.column;
    final rows = await DB.execute<List<Map<String, Object?>>>((txn) async {
      return await txn.query(TableLocationLocationGroup.table,
          columns: [col],
          where: '${TableLocationLocationGroup.idLocationGroup.column} = ?',
          whereArgs: [id]);
    });
    return rows.map((e) => TypeAdapter.deserializeInt(e[col])).toList();
  }

  Future<int> locationCount() async {
    return await DB.execute<int>((txn) async {
      var col = 'ct';
      final rows = await txn.query(TableLocationLocationGroup.table,
          columns: ['count(*) as $col'],
          where: '${TableLocationLocationGroup.idLocationGroup.column} = ?',
          whereArgs: [id]);
      return TypeAdapter.deserializeInt(rows.firstOrNull?[col]);
    });
  }

  /// select a list of distinct Groups from a List of Location IDs
  static Future<List<ModelLocationGroup>> groups(
      List<ModelLocation> locationModels) async {
    final rows = await DB.execute<List<Map<String, Object?>>>((txn) async {
      var ids = locationModels
          .map(
            (e) => e.id,
          )
          .toList();
      var q = '''
SELECT ${TableLocationGroup.columns.join(', ')} FROM ${TableLocationLocationGroup.table}
LEFT JOIN ${TableLocationGroup.table} ON ${TableLocationLocationGroup.idLocationGroup} = ${TableLocationGroup.primaryKey}
WHERE ${TableLocationLocationGroup.idLocation} IN (${List.filled(ids.length, '?').join(', ')})
GROUP by  ${TableLocationGroup.primaryKey}
ORDER BY ${TableLocationGroup.primaryKey}
''';
      return await txn.rawQuery(q, ids);
    });
    return rows
        .map(
          (e) => fromMap(e),
        )
        .toList();
  }

  ModelLocationGroup clone() {
    return fromMap(toMap());
  }
}
