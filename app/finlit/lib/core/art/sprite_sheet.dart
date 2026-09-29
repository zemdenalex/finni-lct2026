import 'dart:convert';
import 'dart:ui' show Rect;

/// Спрайт-лист в формате Aseprite `json-array`: прямоугольники кадров,
/// длительности и теги анимаций (`assets/README.md`).
///
/// Чистый разбор без Flutter-виджетов — проверяется тестом на настоящих
/// файлах из `assets/art/`.
class SpriteSheet {
  const SpriteSheet({required this.frames, required this.tags});

  factory SpriteSheet.parse(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('спрайт-лист: корень не объект');
    }
    final Object? rawFrames = root['frames'];
    if (rawFrames is! List<Object?> || rawFrames.isEmpty) {
      throw const FormatException('спрайт-лист: нет frames[]');
    }
    final List<SpriteFrame> frames = <SpriteFrame>[
      for (final Object? f in rawFrames) SpriteFrame._fromJson(f),
    ];
    final Map<String, SpriteTag> tags = <String, SpriteTag>{};
    final Object? meta = root['meta'];
    if (meta is Map<String, Object?>) {
      final Object? rawTags = meta['frameTags'];
      if (rawTags is List<Object?>) {
        for (final Object? t in rawTags) {
          final SpriteTag tag = SpriteTag._fromJson(t, frames.length);
          tags[tag.name] = tag;
        }
      }
    }
    return SpriteSheet(frames: frames, tags: tags);
  }

  final List<SpriteFrame> frames;
  final Map<String, SpriteTag> tags;

  /// Индексы кадров для тега в порядке показа, один цикл.
  ///
  /// Без тега (или с неизвестным) — все кадры подряд: лучше показать лист,
  /// чем пустое место.
  List<int> sequence(String? tagName) {
    final SpriteTag? tag = tagName == null ? null : tags[tagName];
    if (tag == null) {
      return <int>[for (int i = 0; i < frames.length; i++) i];
    }
    final List<int> forward = <int>[
      for (int i = tag.from; i <= tag.to; i++) i,
    ];
    return switch (tag.direction) {
      SpriteDirection.forward => forward,
      SpriteDirection.reverse => forward.reversed.toList(),
      // Aseprite: 0 1 2 1 | 0 1 2 1 — крайние кадры не повторяются.
      SpriteDirection.pingpong => <int>[
          ...forward,
          for (int i = tag.to - 1; i > tag.from; i--) i,
        ],
    };
  }
}

class SpriteFrame {
  const SpriteFrame(this.rect, this.duration);

  factory SpriteFrame._fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('спрайт-лист: кадр не объект');
    }
    final Object? f = json['frame'];
    if (f is! Map<String, Object?>) {
      throw const FormatException('спрайт-лист: у кадра нет frame{x,y,w,h}');
    }
    double n(String k) {
      final Object? v = f[k];
      if (v is! num) throw FormatException('спрайт-лист: frame.$k не число');
      return v.toDouble();
    }

    final Object? d = json['duration'];
    return SpriteFrame(
      Rect.fromLTWH(n('x'), n('y'), n('w'), n('h')),
      Duration(milliseconds: d is num ? d.toInt() : 100),
    );
  }

  final Rect rect;
  final Duration duration;
}

enum SpriteDirection { forward, reverse, pingpong }

class SpriteTag {
  const SpriteTag(this.name, this.from, this.to, this.direction);

  factory SpriteTag._fromJson(Object? json, int frameCount) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('спрайт-лист: тег не объект');
    }
    final Object? name = json['name'];
    final Object? from = json['from'];
    final Object? to = json['to'];
    if (name is! String || from is! int || to is! int) {
      throw const FormatException('спрайт-лист: у тега нет name/from/to');
    }
    if (from < 0 || to >= frameCount || from > to) {
      throw FormatException('спрайт-лист: тег $name вне кадров ($from..$to)');
    }
    final SpriteDirection dir = switch (json['direction']) {
      'reverse' => SpriteDirection.reverse,
      'pingpong' => SpriteDirection.pingpong,
      _ => SpriteDirection.forward,
    };
    return SpriteTag(name, from, to, dir);
  }

  final String name;
  final int from;
  final int to;
  final SpriteDirection direction;
}
