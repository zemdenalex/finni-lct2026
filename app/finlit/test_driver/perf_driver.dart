// Драйвер для `flutter drive`: считает сводку кадров прогона и проверяет её
// по порогу (§3.4 ТЗ — отклик интерфейса).
//
// Сводку считает flutter_driver, а он работает на хосте, не на устройстве,
// поэтому порог по кадрам стоит здесь, а не в самом тесте. Прогон падает —
// падает и `flutter drive`, то есть замер годится для CI.
//
// Результат: build/perf/finlit.timeline_summary.json (сводка),
// build/perf/finlit.timeline.json (сырая трасса для DevTools) и
// build/perf/perf_response.json (время отклика по действиям).

// Это CLI-инструмент: печать — и есть его интерфейс.
// ignore_for_file: avoid_print

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

/// Тот же порог, что и в самом тесте: половина бюджета кадра при 60 Гц.
const double kFrameBudgetMs = 8.0;

Future<void> main() => integrationDriver(
      responseDataCallback: (Map<String, dynamic>? data) async {
        if (data == null) {
          throw StateError('прогон не вернул данных — трассировка не снята');
        }
        final TimelineSummary summary = TimelineSummary.summarize(
          Timeline.fromJson(data['perf_timeline'] as Map<String, dynamic>),
        );
        await summary.writeTimelineToFile(
          'finlit',
          destinationDirectory: 'build/perf',
          pretty: true,
        );
        await writeResponseData(
          <String, dynamic>{
            'response_ms': data['response_ms'],
            'budget': data['budget'],
            'frame_summary': summary.summaryJson,
          },
          testOutputFilename: 'perf_response',
          destinationDirectory: 'build/perf',
        );

        final Map<String, dynamic> j = summary.summaryJson;
        final double p90Build =
            j['90th_percentile_frame_build_time_millis'] as double;
        final double p90Raster =
            j['90th_percentile_frame_rasterizer_time_millis'] as double;
        print('');
        print('КАДРЫ (${j['frame_count']} кадров)');
        print('  сборка   p90 ${p90Build.toStringAsFixed(2)} мс · '
            'худший ${(j['worst_frame_build_time_millis'] as double).toStringAsFixed(2)} мс');
        print('  растр    p90 ${p90Raster.toStringAsFixed(2)} мс · '
            'худший ${(j['worst_frame_rasterizer_time_millis'] as double).toStringAsFixed(2)} мс');
        print('  отклик, мс: ${data['response_ms']}');

        // 🔴 Гейт по p90, а не по среднему: среднее прячет рывки, ради
        // которых замер и делается.
        if (p90Build > kFrameBudgetMs || p90Raster > kFrameBudgetMs) {
          throw StateError('p90 кадра выше порога $kFrameBudgetMs мс: '
              'сборка $p90Build, растеризация $p90Raster');
        }
      },
    );
