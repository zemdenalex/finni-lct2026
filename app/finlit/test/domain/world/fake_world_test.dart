import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'week_growth_scenario.dart';
import 'week_one_scenario.dart';

void main() {
  group('FakeWorld', () {
    weekOneEnergyScenario(FakeWorld.new);
    weekGrowthScenario((WorldConfig c) => FakeWorld(config: c));
  });
}
