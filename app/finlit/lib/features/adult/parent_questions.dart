import '../../domain/ledger/ledger_entry.dart';
import '../../domain/models/envelope.dart';

/// Вопрос, который взрослому предлагается задать ребёнку.
///
/// 🔴 Главное отличие нашего раздела для взрослого. ТЗ §2.5.12.2 требует
/// показать цели, пройденные темы и прогресс **без негативных оценок
/// ребёнка** — то есть раздел не может отвечать на вопрос «как он учится».
/// Зато Единая рамка компетенций для 7–11 лет прямо требует использования
/// приложения «при участии значимого взрослого»: значит, раздел должен
/// отвечать на вопрос «о чём с ним поговорить».
///
/// Поэтому вопрос состоит из двух частей: [about] — что на самом деле
/// произошло в игре на этой неделе, [ask] — что спросить. Без первой части
/// взрослый спрашивает вслепую, и разговор не случается.
class ParentQuestion {
  const ParentQuestion({required this.about, required this.ask});

  /// Что произошло. Факт из журнала, без оценки.
  final String about;

  /// Что спросить. Открытый вопрос — не «правильно ли он сделал».
  final String ask;
}

/// Подбор вопросов по журналу последней игровой недели.
///
/// Здесь нет ни одной формулы: только сопоставление видов записей
/// ([LedgerKind]) с формулировками. Что произошло — решил домен.
abstract final class ParentQuestions {
  /// Максимум вопросов на экране. Три — потолок: список из десяти вопросов
  /// взрослый не задаст ни одного.
  static const int maxQuestions = 3;

  static const ParentQuestion _withdraw = ParentQuestion(
    about: 'На этой неделе Финни взял монетки из копилки.',
    ask: 'Спроси: на что не хватило и не жалко ли было брать из копилки?',
  );

  static const ParentQuestion _declined = ParentQuestion(
    about: 'Была покупка, на которую монеток не хватило.',
    ask: 'Спроси, чего не хватило и что решено делать дальше.',
  );

  static const ParentQuestion _deferred = ParentQuestion(
    about: 'Неожиданную трату решили перенести на следующую неделю.',
    ask: 'Спроси, почему покупку перенесли и что будет на той неделе.',
  );

  static const ParentQuestion _unexpectedPaid = ParentQuestion(
    about: 'Случилась неожиданная трата, и её оплатили.',
    ask: 'Спроси, из какого конверта взяты монетки и почему именно оттуда.',
  );

  static const ParentQuestion _wantPurchase = ParentQuestion(
    about: 'Была покупка из конверта «Хочу».',
    ask: 'Спроси, чему он обрадовался больше всего и что купил бы в '
        'следующий раз.',
  );

  static const ParentQuestion _needPurchase = ParentQuestion(
    about: 'Были покупки из конверта «Нужное».',
    ask: 'Спроси, почему еда и вода идут раньше игрушек.',
  );

  static const ParentQuestion _task = ParentQuestion(
    about: 'За неделю выполнено задание, и за него пришли монетки.',
    ask: 'Спроси, какое задание было интересным и что из него стало понятно.',
  );

  static const ParentQuestion _deposit = ParentQuestion(
    about: 'В копилку на этой неделе ушли монетки.',
    ask: 'Спроси, на что копит и сколько ещё осталось отложить.',
  );

  static const ParentQuestion _plan = ParentQuestion(
    about: 'Монетки разложены по трём конвертам на неделю вперёд.',
    ask: 'Спроси, почему монетки разложены именно так.',
  );

  /// Общие вопросы — когда на неделе не случилось ничего особенного
  /// или неделя ещё не началась.
  static const ParentQuestion goalQuestion = ParentQuestion(
    about: 'Пока на неделе не произошло ничего необычного.',
    ask: 'Спроси, на что Финни копит сейчас и сколько ещё нужно отложить.',
  );

  static const ParentQuestion _choiceQuestion = ParentQuestion(
    about: 'Каждую неделю в игре три решения: на нужное, на желаемое и '
        'отложить.',
    ask: 'Спроси, какое решение на этой неделе было самым трудным.',
  );

  /// Вопросы по записям одной игровой недели.
  ///
  /// Порядок важен: сверху то, что говорит о выборе между «сейчас» и
  /// «потом», — именно этот выбор ребёнок обсуждает со взрослым тяжелее
  /// всего и полезнее всего.
  static List<ParentQuestion> from(List<LedgerEntry> week) {
    final Set<LedgerKind> kinds =
        week.map((LedgerEntry e) => e.kind).toSet();

    bool bought(Envelope envelope) => week.any((LedgerEntry e) =>
        e.kind == LedgerKind.purchase && e.envelope == envelope);

    final List<ParentQuestion> out = <ParentQuestion>[];
    void add({required bool when, required ParentQuestion question}) {
      if (when && out.length < maxQuestions) out.add(question);
    }

    add(when: kinds.contains(LedgerKind.savingsWithdraw), question: _withdraw);
    add(when: kinds.contains(LedgerKind.purchaseDeclined), question: _declined);
    add(
      when: kinds.contains(LedgerKind.unexpectedDeferred),
      question: _deferred,
    );
    add(
      when: kinds.contains(LedgerKind.unexpectedCost),
      question: _unexpectedPaid,
    );
    add(when: bought(Envelope.wants), question: _wantPurchase);
    add(when: kinds.contains(LedgerKind.taskReward), question: _task);
    add(when: bought(Envelope.needs), question: _needPurchase);
    add(when: kinds.contains(LedgerKind.savingsDeposit), question: _deposit);
    add(when: kinds.contains(LedgerKind.planConfirmed), question: _plan);

    // Меньше двух вопросов — это пустой экран, ради которого взрослый
    // сюда больше не зайдёт. Добиваем общими, но честно подписанными.
    for (final ParentQuestion q in <ParentQuestion>[
      goalQuestion,
      _choiceQuestion,
    ]) {
      if (out.length >= 2) break;
      if (!out.contains(q)) out.add(q);
    }
    return out;
  }
}

/// Вопрос, который **ребёнок** задаёт взрослому.
///
/// 🔴 Обратное направление разговора, и оно не симметрично первому.
/// Раздел для взрослого отвечает на вопрос «о чём спросить ребёнка» —
/// то есть взрослый остаётся проверяющим. Между тем самое надёжное, что
/// даёт школьное финансовое образование по данным испытаний, — это не
/// знания и не самоконтроль, а **разговоры о деньгах дома**; и щедрость
/// ребёнка растёт не от того, что родитель жертвует (+18 %), а от того,
/// что родитель жертвует и **обсуждает это** (+33 %). Значит, половина
/// вопросов должна идти в другую сторону: не «проверь его», а «расскажи
/// ему о себе».
///
/// Осторожно с формулировками: ни один вопрос не спрашивает, сколько
/// взрослый зарабатывает и хватает ли семье денег. Ребёнку, у которого
/// дома не хватает, такой вопрос сделает хуже, а не лучше.
class ChildQuestion {
  const ChildQuestion({required this.ask, required this.why});

  /// Что ребёнок спрашивает у взрослого.
  final String ask;

  /// Зачем это взрослому — короткая строка на его экране.
  final String why;
}

abstract final class ChildQuestions {
  static const List<ChildQuestion> all = <ChildQuestion>[
    ChildQuestion(
      ask: 'Спроси у взрослого: а на что копит ваша семья?',
      why: 'Ребёнок видит, что откладывать — это не игра, а то, что делают '
          'и дома.',
    ),
    ChildQuestion(
      ask: 'Спроси у взрослого: а ты когда-нибудь копил на что-то долго?',
      why: 'История из вашей жизни работает сильнее любого объяснения.',
    ),
    ChildQuestion(
      ask: 'Спроси у взрослого: а бывает так: купишь, а потом жалеешь?',
      why: 'Взрослый, который признаёт свою ошибку с деньгами, снимает '
          'с ребёнка страх ошибиться.',
    ),
    ChildQuestion(
      ask: 'Спроси у взрослого: что в вашем доме — «нужное», а что — «хочу»?',
      why: 'Граница между нужным и желаемым не универсальна: в каждой '
          'семье она своя, и её стоит проговорить вслух.',
    ),
    ChildQuestion(
      ask: 'Спроси у взрослого: а как ты решаешь, что купить первым?',
      why: 'Ребёнок узнаёт, что у взрослых нет готового ответа — есть '
          'способ выбирать.',
    ),
    ChildQuestion(
      ask: 'Спроси у взрослого: а тебе в детстве давали карманные деньги?',
      why: 'Разговор о деньгах начинается легче с прошлого, чем '
          'с настоящего.',
    ),
  ];

  /// Один вопрос на игровую неделю: список из шести никто не задаст.
  /// Выбор по номеру недели, а не случайный, — чтобы вопрос не менялся
  /// при каждом открытии экрана.
  static ChildQuestion ofPeriod(int periodNo) =>
      all[(periodNo - 1).clamp(0, 1 << 30) % all.length];
}
