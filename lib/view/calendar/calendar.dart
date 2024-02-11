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

import 'package:chaostours/model/model_trackpoint.dart';
import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';

///
import 'package:chaostours/conf/app_user_settings.dart';
import 'package:chaostours/statistics/location_statistics.dart';
import 'package:chaostours/view/system/app_widgets.dart';
import 'package:chaostours/gps.dart';
import 'package:chaostours/address.dart';
import 'package:chaostours/logger.dart';
import 'package:chaostours/model/model_location.dart';
import 'package:chaostours/model/model_location_group.dart';
import 'package:chaostours/view/trackpoint/widget_trackpoint_list.dart';
import 'package:chaostours/conf/app_routes.dart';
//import 'package:chaostours/util.dart' as util;

class WidgetCalendar extends StatefulWidget {
  const WidgetCalendar({super.key});

  @override
  State<WidgetCalendar> createState() => _WidgetCalendar();
}

class _WidgetCalendar extends State<WidgetCalendar> {
  // ignore: unused_field
  static final Logger logger = Logger.logger<WidgetCalendar>();

  static List<CalendarEventData> filter(
      DateTime t, List<CalendarEventData> list) {
    return list;
  }

  @override
  void initState() {
    super.initState();
  }

  Future<bool> loadEvents() async {
    AppWidgets.calendarEventController.removeWhere((element) => true);

    var trackpoints = await ModelTrackPoint.search('');
    var currentDate = DateTime.now().subtract(const Duration(days: 5));
    const dur = Duration(hours: 5);
    List<CalendarEventData<ModelTrackPoint>> events = [];
    for (var tp in trackpoints) {
      final event = CalendarEventData<ModelTrackPoint>(
          title: tp.address,
          date: tp.timeStart,
          endDate: tp.timeEnd,
          startTime: tp.timeStart,
          endTime: tp.timeEnd,
          event: tp
          /* 
          endDate: currentDate.add(dur),
          startTime: currentDate,
          endTime: currentDate.add(dur)
          */
          );
      currentDate = currentDate.add(dur).add(dur);
      AppWidgets.calendarEventController.add(event);
    }

    return true;
    /*
    var trackpoints = await ModelTrackPoint.search('');
    final events = <CalendarEventData>[];
    for (var point in trackpoints) {
      final event = CalendarEventData(
        title: point.locationModels.firstOrNull?.title ?? point.address,
        startTime: point.timeStart,
        endTime: point.timeEnd,
        date: point.timeStart,
        endDate: point.timeEnd,
        event: "Event ${point.id}",
      );
      var dur = point.timeEnd.difference(point.timeStart);
      events.add(event);
    }
    _controller.addAll(events);
    */
  }

  @override
  Widget build(BuildContext context) {
    return AppWidgets.scaffold(context,
        body: FutureBuilder(
          future: loadEvents(),
          builder: (context, snapshot) {
            return AppWidgets.checkSnapshot(context, snapshot) ??
                MonthView(
                  onPageChange: (date, page) {
                    print(date);
                    print(page);
                  },
                  onEventTap: (events, date) {
                    /* 
            Navigator.pushNamed(context, AppRoutes.editTrackPoint.route,
                arguments: events.firstOrNull?.event?.id); */
                  },
                  controller: AppWidgets.calendarEventController,
                  //weekTitleHeight: 70,
                );
          },
        ));
  }
}
