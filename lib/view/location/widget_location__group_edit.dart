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

import 'package:chaostours/statistics/location_statistics.dart';
import 'package:chaostours/view/trackpoint/widget_trackpoint_list.dart';
import 'package:flutter/material.dart';

///
import 'package:chaostours/view/system/app_widgets.dart';
import 'package:chaostours/logger.dart';
import 'package:chaostours/model/model_location_group.dart';
import 'package:chaostours/conf/app_routes.dart';

class WidgetLocationGroupEdit extends StatefulWidget {
  const WidgetLocationGroupEdit({super.key});

  @override
  State<WidgetLocationGroupEdit> createState() => _WidgetLocationGroupEdit();
}

class _WidgetLocationGroupEdit extends State<WidgetLocationGroupEdit> {
  // ignore: unused_field
  static final Logger logger = Logger.logger<WidgetLocationGroupEdit>();
  ModelLocationGroup? _model;
  int _countLocation = 0;
  final _titleUndoController = UndoHistoryController();

  final _descriptionUndoController = UndoHistoryController();

  @override
  void dispose() {
    super.dispose();
  }

  void render() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<ModelLocationGroup> createLocationGroup() async {
    var count = await ModelLocationGroup.count();
    var model = await ModelLocationGroup(title: '#${count + 1}').insert();
    return model;
  }

  Future<ModelLocationGroup?> loadLocationGroup(int? id) async {
    if (id == null) {
      _model = await createLocationGroup();
    } else {
      _model = await ModelLocationGroup.byId(id);
    }
    if (_model == null && mounted) {
      if (mounted) {
        Future.microtask(() => Navigator.pop(context));
      }
      throw 'Group #$id not found';
    } else {
      _countLocation = await _model!.locationCount();
      return _model;
    }
  }

  @override
  Widget build(BuildContext context) {
    int? id = ModalRoute.of(context)?.settings.arguments as int?;

    return FutureBuilder<ModelLocationGroup?>(
      future: loadLocationGroup(id),
      builder: (context, snapshot) {
        return AppWidgets.checkSnapshot(context, snapshot) ?? body();
      },
    );
  }

  Widget body() {
    return scaffold(editGroup());
  }

  Widget scaffold(Widget body) {
    return AppWidgets.scaffold(context,
        title: 'Edit Location Group',
        body: body,
        navBar: AppWidgets.navBarCreateItem(context, name: 'Location group',
            onCreate: () async {
          final model = await AppWidgets.createLocationGroup(context);
          if (model != null && mounted) {
            await Navigator.pushNamed(
                context, AppRoutes.editLocationGroup.route,
                arguments: model.id);
            render();
          }
        }));
  }

  Widget editGroup() {
    return ListView(padding: const EdgeInsets.all(5), children: [
      /// Trackpoints button
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FilledButton(
                  onPressed: () => Navigator.pushNamed(
                      context, AppRoutes.listTrackpoints.route,
                      arguments: TrackpointListArguments.locationGroup
                          .arguments(_model!.id)),
                  child: const Text('Trackpoints'))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FilledButton(
                  onPressed: () async {
                    var stats =
                        await LocationStatistics.groupStatistics(_model!);

                    if (mounted) {
                      AppWidgets.statistics(context, stats: stats,
                          reload: (DateTime start, DateTime end) async {
                        return await LocationStatistics.groupStatistics(
                            stats.model,
                            start: start,
                            end: end);
                      });
                    }
                  },
                  child: const Text('Statistics')))
        ],
      ),

      /// groupname
      ListTile(
          dense: true,
          trailing: ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _titleUndoController,
            builder: (context, value, child) {
              return IconButton(
                icon: const Icon(Icons.undo),
                onPressed: value.canUndo
                    ? () {
                        _titleUndoController.undo();
                      }
                    : null,
              );
            },
          ),
          title: Container(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration:
                    const InputDecoration(label: Text('Location Group Name')),
                onChanged: ((value) {
                  _model!.title = value;
                  _model!.update();
                }),
                maxLines: 3,
                minLines: 3,
                controller: TextEditingController(text: _model?.title),
              ))),
      AppWidgets.divider(),

      /// notes
      ListTile(
          dense: true,
          trailing: ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _descriptionUndoController,
            builder: (context, value, child) {
              return IconButton(
                icon: const Icon(Icons.undo),
                onPressed: value.canUndo
                    ? () {
                        _descriptionUndoController.undo();
                      }
                    : null,
              );
            },
          ),
          title: Container(
              padding: const EdgeInsets.all(10),
              child: TextField(
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(label: Text('Notizen')),
                maxLines: null,
                minLines: 3,
                controller: TextEditingController(text: _model?.description),
                onChanged: (value) {
                  _model!.description = value.trim();
                  _model!.update();
                },
              ))),
      AppWidgets.divider(),

      /// deleted
      ListTile(
          title: const Text('Active'),
          subtitle: const Text('This Group is active and visible'),
          leading: AppWidgets.checkbox(
            value: _model!.isActive,
            onChanged: (val) {
              _model!.isActive = val ?? false;
              _model!.update();
            },
          )),

      AppWidgets.divider(),

      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: FilledButton(
          child: Text('Show $_countLocation locations from this group'),
          onPressed: () => Navigator.pushNamed(
                  context, AppRoutes.listLocationsFromLocationGroup.route,
                  arguments: _model!.id)
              .then((value) {
            render();
          }),
        ),
      ),
    ]);
  }
}
