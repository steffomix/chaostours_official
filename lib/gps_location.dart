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

import 'dart:math' as math;

///
import 'package:chaostours/channel/notification_channel.dart';
import 'package:chaostours/model/model_task.dart';
import 'package:chaostours/model/model_user.dart';
import 'package:chaostours/shared/shared_trackpoint_location.dart';
import 'package:chaostours/shared/shared_trackpoint_task.dart';
import 'package:chaostours/shared/shared_trackpoint_user.dart';
import 'package:chaostours/address.dart';
import 'package:chaostours/channel/data_channel.dart';
import 'package:chaostours/database/cache.dart';
import 'package:chaostours/conf/app_user_settings.dart';
import 'package:chaostours/gps.dart';
import 'package:chaostours/logger.dart';
import 'package:chaostours/model/model_location.dart';
import 'package:chaostours/model/model_trackpoint.dart';
import 'package:chaostours/channel/tracking.dart';

//
class GpsLocation {
  static final Logger logger = Logger.logger<GpsLocation>();

  final GPS gps;
  Address? address;
  LocationPrivacy get privacy => _privacy ?? LocationPrivacy.none;
  LocationPrivacy? _privacy;
  int radius = 0;

  final tracker = Tracker();
  final channel = DataChannel();
  final List<ModelLocation> locationModels;

  GpsLocation._location({required this.gps, required this.locationModels});

  static Future<GpsLocation> gpsLocation(GPS gps,
      [bool updateSharedLocations = false]) async {
    List<ModelLocation> allModels = await ModelLocation.byArea(
        gps: gps,
        gpsArea: math.max(
            1000,
            await Cache.appSettingDistanceTreshold.load(
                AppUserSetting(Cache.appSettingDistanceTreshold).defaultValue
                    as int)));

    LocationPrivacy? priv;
    List<ModelLocation> models = [];
    int rad = 0;
    for (var model in allModels) {
      if (model.privacy.level >= LocationPrivacy.private.level) {
        continue;
      }
      if (GPS.distance(gps, model.gps) <= model.radius) {
        model.sortDistance = model.radius;
        models.add(model);
        rad = math.max(rad, model.radius);
        priv ??= model.privacy;
        if (model.privacy.level > priv.level) {
          priv = model.privacy;
        }
      }
    }
    models.sort((a, b) => a.sortDistance.compareTo(b.sortDistance));
    if (rad == 0) {
      rad =
          AppUserSetting(Cache.appSettingDistanceTreshold).defaultValue as int;
    }

    final location = GpsLocation._location(
      gps: gps,
      locationModels: models,
    );

    location._privacy = priv;
    location.radius = rad;
    if (updateSharedLocations) {
      await Cache.backgroundSharedLocationList
          .save<List<SharedTrackpointLocation>>(location.locationModels
              .map((model) => SharedTrackpointLocation(id: model.id, notes: ''))
              .toList());
    }

    return location;
  }

  Future<ModelTrackPoint> createTrackPoint() async {
    address ??= await Address(gps)
        .lookup(OsmLookupConditions.onStatusChanged, saveToCache: true);
    return await ModelTrackPoint(
            gps: gps,
            timeStart: (tracker.gpsLastStatusStanding ?? gps).time,
            timeEnd: gps.time,
            address: address?.address ?? '',
            notes: await Cache.backgroundTrackPointNotes.load<String>(''))
        .addSharedAssets(this);
  }

  Future<GpsLocation> autocreateLocation() async {
    /// get address
    tracker.address = await Address(gps)
        .lookup(OsmLookupConditions.onAutoCreateLocation, saveToCache: true);

    /// create location
    ModelLocation newModel = ModelLocation(
        gps: gps,
        lastVisited: tracker.gpsCalcPoints.lastOrNull?.time ?? gps.time,
        timesVisited: 1,
        title: tracker.address?.address ?? '',
        description: tracker.address?.addressDetails ?? '',
        radius: radius);

    await newModel.insert();
    final newLocation = await gpsLocation(gps, true);
    return newLocation;
  }

  bool _standingExecuted = false;
  Future<void> executeStatusStanding() async {
    if (_standingExecuted || privacy == LocationPrivacy.restricted) {
      return;
    }
    try {
      await _notifyStanding();
      await _recordStanding();
    } catch (e, stk) {
      logger.error('executeStatusStanding: $e', stk);
    }
    _standingExecuted = true;
  }

  bool _movingExecuted = false;
  Future<void> executeStatusMoving() async {
    if (_movingExecuted || privacy == LocationPrivacy.restricted) {
      return;
    }

    if (privacy == LocationPrivacy.none &&
        !(await Cache.appSettingRecordWithoutLocation.load<bool>(false))) {
      return;
    }

    try {
      await _notifyMoving();
      await _recordMoving();

      // reset notes
      await Cache.backgroundTrackPointNotes.save<String>('');
      // reset tasks with preselected
      await Cache.backgroundSharedTaskList
          .save<List<SharedTrackpointTask>>((await ModelTask.preselected())
              .map(
                (e) => SharedTrackpointTask(id: e.id, notes: ''),
              )
              .toList());
      // reset users with preselected
      await Cache.backgroundSharedUserList
          .save<List<SharedTrackpointUser>>((await ModelUser.preselected())
              .map(
                (e) => SharedTrackpointUser(id: e.id, notes: ''),
              )
              .toList());
    } catch (e, stk) {
      logger.error('executeStatusMoving: $e', stk);
    }
    _movingExecuted = true;
  }

  Future<void> _notifyStanding() async {
    // update address
    if (privacy.level <= LocationPrivacy.normal.level) {
      tracker.address = await Address(gps)
          .lookup(OsmLookupConditions.onStatusChanged, saveToCache: true);
    }
    // check privacy
    if (privacy.level > LocationPrivacy.private.level) {
      return;
    }

    NotificationChannel.sendTrackingUpdateNotification(
        title: 'Tick Update',
        message: 'New Status: ${tracker.trackingStatus?.name.toUpperCase()}'
            '${tracker.address != null ? '\n${tracker.address?.address}' : ''}',
        details: NotificationChannel.trackingStatusChangedConfiguration);
  }

  Future<void> _recordStanding() async {
    // check privacy
    if (privacy.level > LocationPrivacy.normal.level) {
      return;
    }

    tracker.address = await Address(tracker.gpsLastStatusStanding ?? gps)
        .lookup(OsmLookupConditions.onStatusChanged, saveToCache: true);

    // update last visited
    for (var model in locationModels) {
      model.lastVisited = (tracker.gpsLastStatusStanding ?? gps).time;
      await model.update();
    }
  }

  Future<void> _notifyMoving() async {
    // check privacy
    if (privacy.level > LocationPrivacy.private.level) {
      return;
    }
  }

  Future<ModelTrackPoint?> _recordMoving() async {
    // check privacy
    if (privacy.level > LocationPrivacy.normal.level) {
      return null;
    }

    // check if location is required and present
    bool locationRequired =
        await Cache.appSettingStatusStandingRequireLocation.load<bool>(true);
    if (locationRequired && locationModels.isEmpty) {
      return null;
    }

    final Address address = await Address(gps)
        .lookup(OsmLookupConditions.onStatusChanged, saveToCache: true);
    ModelTrackPoint newTrackPoint = ModelTrackPoint(
        gps: gps,
        timeStart: gps.time,
        timeEnd: DateTime.now(),
        address: address.address,
        fullAddress: address.addressDetails,
        notes: await Cache.backgroundTrackPointNotes.load<String>(''));

    await newTrackPoint.addSharedAssets(this);

    /// save new TrackPoint with user- and task ids
    await newTrackPoint.insert();
    //_debugInsert(newTrackPoint);
    return newTrackPoint;
  }
}
