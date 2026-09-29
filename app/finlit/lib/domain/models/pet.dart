/// Показатели состояния питомца.
///
/// Каждая шкала — целое число 0..[PetMeters.max]. Маленькая шкала выбрана
/// сознательно: ТЗ §3.6 требует возрастной уместности, и «5 из 10» ребёнок 7 лет
/// читает, а «47 %» — нет. На экране шкала рисуется точками, а не процентами,
/// и цвет не единственный носитель смысла (§3.6.5).
enum Meter {
  // 🔴 Последнее поле — согласование по роду. «Сытость» и «Чистота»
  // женского рода, «Настроение» среднего, и общий шаблон «у Финни
  // {показатель} уже полная» давал на экране «настроение почти полная».
  // Видно это было только в игре: тексты собираются из двух кусков,
  // и ни один тест не проверял получившуюся фразу целиком.
  fullness('Сытость', 'сыт', 'перекусил бы', 'проголодался', 'полная'),
  cleanliness('Чистота', 'чистый', 'пора прибраться', 'нужна уборка', 'полная'),
  mood('Настроение', 'радуется', 'спокоен', 'скучает', 'отличное');

  const Meter(this.title, this.high, this.mid, this.low, this.atMax);

  final String title;

  /// Прилагательное для фразы «уже {atMax}» — в роде названия показателя.
  final String atMax;

  final String high;
  final String mid;
  final String low;

  /// Подпись словами, а не числом. 🔴 Ни одна из подписей не описывает
  /// страдание: ТЗ §2 запрещает негативные последствия, §3.5 — запугивание.
  /// Нижняя граница — «проголодался» и «скучает», и она всегда чинится
  /// следующей покупкой.
  String label(int value) {
    if (value >= 7) return high;
    if (value >= 4) return mid;
    return low;
  }
}

/// Состояние питомца: три обратимые шкалы (см. Термины ТЗ).
class PetMeters {
  const PetMeters({
    required this.fullness,
    required this.cleanliness,
    required this.mood,
  });

  static const int max = 10;
  static const PetMeters zero =
      PetMeters(fullness: 0, cleanliness: 0, mood: 0);

  final int fullness;
  final int cleanliness;
  final int mood;

  int byMeter(Meter m) => switch (m) {
        Meter.fullness => fullness,
        Meter.cleanliness => cleanliness,
        Meter.mood => mood,
      };

  /// Сложение с обрезкой по границам 0..max. Обрезка здесь, а не в вызывающем
  /// коде, — иначе шкала уходит в минус на первом же пропущенном периоде.
  PetMeters plus(PetMeters other) => PetMeters(
        fullness: _clamp(fullness + other.fullness),
        cleanliness: _clamp(cleanliness + other.cleanliness),
        mood: _clamp(mood + other.mood),
      );

  static int _clamp(int v) => v < 0 ? 0 : (v > max ? max : v);

  /// «Нужное закрыто»: обе шкалы ухода не ниже порога из экономики.
  /// Порог живёт в контенте, а не здесь, — иначе балансировка игры
  /// превращается в правку кода.
  bool needsCovered(int threshold) =>
      fullness >= threshold && cleanliness >= threshold;

  Map<String, Object?> toJson() => <String, Object?>{
        'fullness': fullness,
        'cleanliness': cleanliness,
        'mood': mood,
      };

  static PetMeters fromJson(Map<String, Object?> json) => PetMeters(
        fullness: json['fullness']! as int,
        cleanliness: json['cleanliness']! as int,
        mood: json['mood']! as int,
      );

  @override
  String toString() =>
      'PetMeters(сытость: $fullness, чистота: $cleanliness, настроение: $mood)';

  @override
  bool operator ==(Object other) =>
      other is PetMeters &&
      other.fullness == fullness &&
      other.cleanliness == cleanliness &&
      other.mood == mood;

  @override
  int get hashCode => Object.hash(fullness, cleanliness, mood);
}

/// Стадия развития питомца. ТЗ §2.5.10 требует не менее трёх.
///
/// Формулировки намеренно про умение, а не про рост: ребёнок здесь
/// учитель Финни, а не его хозяин. Подробности и ссылки —
/// docs/etika-i-motivaciya.md.
enum PetStage {
  novice(
    0,
    'Новичок',
    'Финни только учится обращаться с монетками',
  ),
  saver(
    4,
    'Копилкин',
    'Финни научился откладывать — он видел, как это делаешь ты',
  ),
  planner(
    9,
    'Хранитель копилки',
    'Финни сам раскладывает монетки по конвертам',
  );

  const PetStage(this.threshold, this.title, this.description);

  /// Порог в очках заботы, начиная с которого стадия открыта.
  final int threshold;
  final String title;
  final String description;

  /// 🔴 Стадия не откатывается: ТЗ §2.2 «Безопасная ошибка … не обнулять
  /// ранее достигнутый прогресс». Плохая неделя стоит очков этой недели,
  /// а не стадии.
  static PetStage forPoints(int points) {
    PetStage result = PetStage.novice;
    for (final PetStage s in PetStage.values) {
      if (points >= s.threshold) result = s;
    }
    return result;
  }
}
