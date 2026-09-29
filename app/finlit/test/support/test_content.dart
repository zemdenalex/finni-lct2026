import 'dart:io';

import 'package:finlit/data/content_loader.dart';
import 'package:finlit/domain/content.dart';

/// Читает те же самые файлы, которые поедут в сборку.
///
/// Тест, читающий свою копию контента, проверяет не тот контент, который
/// увидит ребёнок, — поэтому здесь именно assets/, а не фикстуры.
Future<GameContent> loadRealContent({int scale = 1}) =>
    ContentLoader((String path) => File(path).readAsString()).load(scale: scale);
