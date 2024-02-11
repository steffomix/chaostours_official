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

import 'package:chaostours/address.dart';
import 'package:flutter/material.dart';
import 'package:chaostours/logger.dart';
import 'package:chaostours/database/cache.dart';
import 'dart:math' as math;
// import 'package:chaostours/logger.dart';

abstract class EnumUserSetting<T> {
  final Widget title;
  final int index = 0;
  const EnumUserSetting(this.title);
}

enum OsmLookupConditions implements EnumUserSetting<OsmLookupConditions> {
  never(Text('Never, completely restricted')),
  onUserRequest(Text('On user requests')),
  onUserCreateLocation(Text('On user create location')),
  onAutoCreateLocation(Text('On auto create location')),
  onStatusChanged(Text('On tracking status changed')),
  onBackgroundGps(Text('On every background GPS interval')),
  always(Text('Always, no restrictions'));

  static Map<OsmLookupConditions, Address> address = {};
  @override
  final Widget title;
  const OsmLookupConditions(this.title);

  static OsmLookupConditions? byName(String name) {
    for (var value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  Future<bool> allowLookup() async {
    OsmLookupConditions setting = await Cache.appSettingOsmLookupCondition
        .load<OsmLookupConditions>(OsmLookupConditions.never);
    bool licenseConsent = await Cache.osmLicenseAccepted.load<bool>(false);
    return licenseConsent && setting.index > 0 && index <= setting.index;
  }
}

enum Weekdays implements EnumUserSetting<OsmLookupConditions> {
  mondayFirst(['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'], Text('Monday')),
  sundayFirst(['', 'So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'], Text('Sunday'));

  final List<String> weekdays;
  @override
  final Widget title;

  const Weekdays(this.weekdays, this.title);
}

enum DateFormat implements EnumUserSetting<OsmLookupConditions> {
  yyyymmdd(Text('YYYY:MM:DD')),
  ddmmyyyy(Text('DD:MM:YYYY'));

  @override
  final Widget title;

  const DateFormat(this.title);
}

enum GpsPrecision implements EnumUserSetting<OsmLookupConditions> {
  best(Text('Best')),
  coarse(Text('Coarse')),
  ;

  @override
  final Widget title;
  const GpsPrecision(this.title);
}

enum Unit {
  piece(1),
  minute(60),
  second(1),
  meter(1),
  km(1000),
  option(1);

  final int multiplicator;
  const Unit(this.multiplicator);
}

class AppUserSetting {
  static final Logger logger = Logger.logger<AppUserSetting>();

  static final Map<Cache, AppUserSetting> _appUserSettings = {};
  Cache cache;
  dynamic _cachedValue;
  dynamic defaultValue;
  int? minValue;
  int? maxValue;
  Unit unit = Unit.piece;
  Future<void> Function() resetToDefault;
  Future<int> Function(int value)? extraCheck;
  Widget? title;
  Widget? description;

  AppUserSetting._option(this.cache,
      {required this.title,
      required this.description,
      required this.defaultValue,
      required this.resetToDefault,
      this.extraCheck,
      this.minValue,
      this.maxValue,
      required this.unit});

  static Future<void> resetAllToDefault() async {
    for (var setting in [
      Cache.appSettingTimeRangeTreshold,
      Cache.appSettingAutocreateLocationDuration,
      Cache.appSettingBackgroundTrackingInterval,
      Cache.appSettingBackgroundTrackingEnabled,
      Cache.appSettingDistanceTreshold,
      Cache.appSettingOsmLookupCondition,
      Cache.appSettingWeekdays,
      Cache.appSettingAutocreateLocation,
      Cache.appSettingStatusStandingRequireLocation,
      Cache.appSettingTimeZone
    ]) {
      await AppUserSetting(setting).resetToDefault();
    }
  }

  factory AppUserSetting(Cache cache) {
    switch (cache) {
      ///
      /// Tracking Values
      ///

      case Cache.appSettingBackgroundTrackingInterval:
        return _appUserSettings[cache] ??= AppUserSetting._option(cache, //
            title: const Text('Background GPS tracking interval duration.'),
            description: const Text('A higher value consumes less battery, '
                'but it also takes longer to measure the status of stopping or moving.\n'
                'NOTE:\n'
                'The tracking execution time can take some seconds and will be added.'),
            unit: Unit.second,
            minValue: 3,
            defaultValue: const Duration(seconds: 30),
            resetToDefault: () async {
          await cache
              .save<Duration>(AppUserSetting(cache).defaultValue as Duration);
        }, //
            extraCheck: (int value) async {
          /// timeRange must at least allow 4 lookups
          int minTimeRange = value * 4;
          Cache cTimeRange = Cache.appSettingTimeRangeTreshold;
          int timeRange = (await cTimeRange.load<Duration>(
                  AppUserSetting(cTimeRange).defaultValue as Duration))
              .inSeconds;
          if (minTimeRange > timeRange) {
            // modify timeRange
            await cTimeRange.save<Duration>(Duration(seconds: minTimeRange));
          }

          // recheck autocreate location duration
          int minCreate = minTimeRange * 2;
          Cache cAutoCreate = Cache.appSettingAutocreateLocationDuration;
          int autoCreate = (await cAutoCreate.load<Duration>(
                  AppUserSetting(cAutoCreate).defaultValue as Duration))
              .inSeconds;
          if (autoCreate < minCreate) {
            await cAutoCreate.save<Duration>(Duration(seconds: minCreate));
          }
          return value;
        });

      case Cache.appSettingTimeRangeTreshold:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Tracking status calculation time period'),
          description: const Text(
              'The time period in which the Moving or Stopping status is calculated.\n'
              'The System requires at least 3x time as the above "Background GPS Tracking Interval Duration" '
              'and will increase false values if necessary.'),
          unit: Unit.minute,
          minValue: 60, // 1 minute
          maxValue: null,
          defaultValue: const Duration(minutes: 3),
          resetToDefault: () async {
            await cache
                .save<Duration>(AppUserSetting(cache).defaultValue as Duration);
          },
          extraCheck: (int timeRangeSeconds) async {
            //
            // must be min 3x appSettingBackgroundTrackingInterval
            Cache cache = Cache.appSettingBackgroundTrackingInterval;
            int trackingSeconds = (await cache.load<Duration>(
                    AppUserSetting(cache).defaultValue as Duration))
                .inSeconds;
            timeRangeSeconds = math.max(timeRangeSeconds, trackingSeconds * 3);
            //
            // recheck autocreate location duration
            int minCreateSeconds = timeRangeSeconds * 2;
            cache = Cache.appSettingAutocreateLocationDuration;
            int createSeconds = (await cache.load<Duration>(
                    AppUserSetting(cache).defaultValue as Duration))
                .inSeconds;
            if (createSeconds < minCreateSeconds) {
              await cache.save<Duration>(Duration(seconds: minCreateSeconds));
            }

            return timeRangeSeconds;
          },
        );

      case Cache.appSettingAutocreateLocationDuration:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Auto create location time period.'),
          description: const Text(
              'The period after which an location will be created automatically if none is found. '
              'The "Status Standing Requires Location" option must be activated to make it work. '
              'The system requires at least 2x time as the above "Time Range Threshold" '
              'and will automatically increase false values if necessary.'),
          unit: Unit.minute,
          minValue: 60 * 5, // 5 minutes
          defaultValue: const Duration(seconds: 60 * 15),
          resetToDefault: () async {
            await cache
                .save<Duration>(AppUserSetting(cache).defaultValue as Duration);
          }, //
          extraCheck: (int value) async {
            /// must be at least appSettingTimeRangeTreshold * 2
            Cache cTimeRange = Cache.appSettingTimeRangeTreshold;
            int timeRange = (await cTimeRange.load<Duration>(
                    AppUserSetting(cTimeRange).defaultValue as Duration))
                .inSeconds;
            int min = timeRange * 2;
            if (value < min) {
              return min;
            }
            return value;
          }, //
        ); // 15 minutes

      case Cache.appSettingBackgroundTrackingEnabled:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Activate GPS tracking service'),
          description: const Text(
              'This service runs in background, even if the app is closed. \n'
              'If this service seems to stop from alone, please look if you have granted the permission to disable battery optimization.'),
          unit: Unit.option,
          defaultValue: true,
          resetToDefault: () async {
            await cache.save<bool>(AppUserSetting(cache).defaultValue as bool);
          },
        );

      case Cache.appSettingDistanceTreshold:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Default location radius.'),
          description: const Text(
              'Used as default when a new location is created or if gps tracking can\'t find a location and its radius.'),
          unit: Unit.meter,
          defaultValue: 100,
          resetToDefault: () async {
            await cache.save<int>(AppUserSetting(cache).defaultValue as int);
          },
          minValue: 20,
        );

      case Cache.appSettingOsmLookupCondition:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('OpenStreetMap Address Lookup Conditions'),
          description: const Text(
              'The requirements for when the app is allowed to search for an address. '
              'Higher restrictions reduce the app\'s data consumption.'),
          unit: Unit.option,
          defaultValue: OsmLookupConditions.onAutoCreateLocation,
          resetToDefault: () async {
            await cache.save<OsmLookupConditions>(
                AppUserSetting(cache).defaultValue as OsmLookupConditions);
          },
        );

      case Cache.appSettingDateFormat:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Date Format'),
          description: const Text('How Dates are displayed.'),
          unit: Unit.option,
          defaultValue: DateFormat.yyyymmdd,
          resetToDefault: () async {
            await cache.save<DateFormat>(
                AppUserSetting(cache).defaultValue as DateFormat);
          },
        );

      case Cache.appSettingWeekdays:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('First Weekday'),
          description: null,
          unit: Unit.option,
          defaultValue: Weekdays.mondayFirst,
          resetToDefault: () async {
            await cache
                .save<Weekdays>(AppUserSetting(cache).defaultValue as Weekdays);
          },
        );

      case Cache.appSettingAutocreateLocation:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Auto create location.'),
          description: const Text(
              'The App can create a location for you automatically after a certain time of standing. '
              ' It also can lookup an Address from OpenStreetMap.com for free, just make sure you have set the lookup permissions below.'),
          unit: Unit.option,
          defaultValue: true,
          resetToDefault: () async {
            await cache.save<bool>(AppUserSetting(cache).defaultValue as bool);
          },
        );

      case Cache.appSettingStatusStandingRequireLocation:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Status stop requires location'),
          description: const Text(
              'If deactivated, the Movement measuring range is used as a virtual location.'),
          unit: Unit.option,
          defaultValue: true,
          resetToDefault: () async {
            await cache.save<bool>(AppUserSetting(cache).defaultValue as bool);
          },
        );

      case Cache.appSettingRecordWithoutLocation:
        return _appUserSettings[cache] ??= AppUserSetting._option(
          cache,
          title: const Text('Record trackpoint without known location'),
          description: const Text(
              'If activated, a record is made even if no konwn location was found. \n'
              'This option requires the option "Status stop requires location" to be disabled.'),
          unit: Unit.option,
          defaultValue: true,
          resetToDefault: () async {
            await cache.save<bool>(AppUserSetting(cache).defaultValue as bool);
          },
        );

      case Cache.appSettingGpsPrecision:
        return _appUserSettings[cache] ??= AppUserSetting._option(cache,
            title: const Text('GPS precision'),
            description:
                const Text('Higher GPS precision consumes more battery power'),
            unit: Unit.piece,
            defaultValue: GpsPrecision.best, //
            resetToDefault: () async {
          await cache.save<GpsPrecision>(
              AppUserSetting(cache).defaultValue as GpsPrecision);
        });

      case Cache.appSettingTimeZone:
        return _appUserSettings[cache] ??= AppUserSetting._option(cache,
            title: const Text('ToDo - implement timezones'),
            description: Text('Description of ${cache.toString()}'),
            unit: Unit.piece,
            defaultValue: 'Europe/Berlin', //
            resetToDefault: () async {
          await cache
              .save<String>(AppUserSetting(cache).defaultValue as String);
        });

      default:
        throw 'AppUserSettings for ${cache.name} not implemented';
    }
  }

  Future<int> pruneInt(String? data) async {
    int value = (int.tryParse(data ?? '') ??
            (cache.cacheType == int
                ? defaultValue as int
                : ((defaultValue as Duration).inSeconds / unit.multiplicator)
                    .round())) *
        unit.multiplicator;

    if (minValue != null && value < minValue!) {
      value = math.max(minValue!, value);
    }
    if (maxValue != null && value > maxValue!) {
      value = math.min(maxValue!, value);
    }
    value = (await extraCheck?.call(value)) ?? value;
    return value;
  }

  Future<void> save(String? data) async {
    switch (cache.cacheType) {
      case const (String):
        String value = data?.trim() ?? defaultValue as String;
        await cache.save<String>(value);
        break;

      case const (int):
        int value = await pruneInt(data ?? defaultValue.toString());
        await cache.save<int>(value);
        break;

      case const (bool):
        bool value =
            (data != null && (data == '1' || data == 'true')) ? true : false;
        await cache.save<bool>(value);
        break;

      case const (Duration):
        int value = await pruneInt(data ??
            ((defaultValue as Duration).inSeconds / unit.multiplicator)
                .round()
                .toString());
        await cache.save<Duration>(Duration(seconds: value));
        break;

      case const (OsmLookupConditions):
        var value = OsmLookupConditions.byName(
                data ?? (defaultValue as OsmLookupConditions).name) ??
            (defaultValue as OsmLookupConditions);
        await cache.save<OsmLookupConditions>(value);
        break;

      default:
        logger.warn(
            'save ${cache.name}: Type ${data.runtimeType} not implemented');
    }
  }

  Future<String> load() async {
    switch (cache.cacheType) {
      case const (String):
        return (_cachedValue ??= await cache.load<String>(defaultValue))
            as String;

      case const (int):
        int value = await cache.load<int>(defaultValue as int);
        return (value / unit.multiplicator).round().toString();

      case const (bool):
        bool value = await cache.load<bool>(defaultValue as bool);
        return value ? '1' : '0';

      case const (Duration):
        Duration value = await cache.load<Duration>(defaultValue as Duration);
        return (value.inSeconds / unit.multiplicator).round().toString();

      case const (OsmLookupConditions):
        OsmLookupConditions value = await cache
            .load<OsmLookupConditions>(defaultValue as OsmLookupConditions);
        return value.name;

      case const (GpsPrecision):
        GpsPrecision value =
            await cache.load<GpsPrecision>(defaultValue as GpsPrecision);
        return value.name;

      default:
        logger.warn('load: ${cache.cacheType} not implemented');
    }
    return '${cache.cacheType} Not implemented!';
  }
}
