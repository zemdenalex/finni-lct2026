import 'package:flutter/material.dart';

import '../../../../core/art/asset_registry.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets.dart';
import '../../../../domain/world/contract.dart';
import '../../pic_text.dart';
import '../../world_layout.dart';
import '../../../../core/world_theme.dart';

/// Ключ карточки смены: `jobId` или `jobId/variant`.
String offerKey(JobOffer o) =>
    o.variant == null ? o.jobId : '${o.jobId}/${o.variant}';

/// Число с десятичной запятой без лишних нулей: «3», «2,9», «1,25».
String energyCostText(double e) {
  if (e == e.roundToDouble()) return e.toInt().toString();
  String s = e.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}

/// Ступень ставки стадии с десятичной запятой: «×1,25», «×1,5», «×2».
String stageStepText(double step) => '×${energyCostText(step)}';

/// Ступень показывается, только если она что-то меняет (больше ×1).
bool showStageStep(double step) => step > 1 + 1e-9;

/// Условия хорошей смены — числа только из карточки: «Хорошо сделаешь —
/// +1 опыт, до +N бонус, ещё ⚡ X, −Y 😊».
String goodShiftText(JobOffer o) {
  final List<String> parts = <String>[
    '+1 опыт',
    if (o.efficiencyBonusMax > 0) 'до +${o.efficiencyBonusMax} бонус',
    if (o.goodEnergyExtra > 1e-9) 'ещё ⚡ ${energyShown(o.goodEnergyExtra)}',
    if (o.goodHappiness != 0)
      '${o.goodHappiness > 0 ? '+' : '−'}${o.goodHappiness.abs()} 😊',
  ];
  return 'Хорошо сделаешь — ${parts.join(', ')}';
}

/// Причина, по которой смену не взять, со следующим шагом.
String blockText(BlockReason b) =>
    b.nextStep == null ? b.text : '${b.text} ${b.nextStep}';

/// Карточка одной смены на доске S6.
///
/// 🔴 Все числа — поля [JobOffer] как есть: экран оплату не пересчитывает.
/// Если взять нельзя — вместо кнопки причина словами
/// ([JobOffer.blockReason]: те же правила, что у completeJob).
class JobOfferCard extends StatelessWidget {
  const JobOfferCard({
    super.key,
    required this.offer,
    required this.onTake,
  });

  final JobOffer offer;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final JobOffer o = offer;
    final String k = offerKey(o);
    final bool locked = o.locked;
    final String energy = energyShown(o.energyCost);
    final BlockReason? block = o.blockReason;
    // Замок называет вещь и цену всегда, даже до плана недели (ревью
    // 2b58bdb §3.3): ребёнок сразу видит, что открыть. Другая причина
    // (фаза недели, лимит, ⚡) — отдельной строкой под ним.
    final String? lock = o.lockedReason;
    final String? other =
        block == null || block.code == 'job.locked' ? null : blockText(block);
    return Panel(
      key: ValueKey<String>('jobs:card:$k'),
      color: locked ? WorldColors.raised : WorldColors.panel,
      padding: const EdgeInsets.all(Gap.sm + Gap.xs),
      // В сетке альбомной карточки ряда одной высоты: сведения сверху,
      // «Взяться» или причина — по низу.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _JobPicture(jobId: o.jobId, locked: locked),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(o.title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: WorldColors.text)),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Semantics(
                label: 'Заплатят ${o.pay} монет',
                excludeSemantics: true,
                child: Row(
                  children: <Widget>[
                    const CoinDot(size: 20),
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: Text('Заплатят ${o.pay}',
                          key: ValueKey<String>('jobs:pay:$k'),
                          style: AppType.number(20, color: WorldColors.text)
                              .copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xs),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: <Widget>[
                  _Fact(
                      key: ValueKey<String>('jobs:energy:$k'),
                      pic: Pic.spark,
                      text: 'энергия $energy',
                      semantic: 'Потратит энергии: $energy'),
                  _Fact(
                      key: ValueKey<String>('jobs:exp:$k'),
                      pic: Pic.chart,
                      text: 'опыт +${o.experiencePercent} %',
                      semantic:
                          'Прибавка за опыт: ${o.experiencePercent} процентов'),
                  if (showStageStep(o.stageStep))
                    _Fact(
                        key: ValueKey<String>('jobs:step:$k'),
                        pic: Pic.city,
                        text: 'ставка ${stageStepText(o.stageStep)}',
                        semantic: 'Ставка на этой стадии: '
                            '${stageStepText(o.stageStep)}'),
                  _Fact(
                      key: ValueKey<String>('jobs:bonus:$k'),
                      pic: Pic.star,
                      text: goodShiftText(o),
                      semantic: goodShiftText(o)),
                  _Fact(
                      key: ValueKey<String>('jobs:left:$k'),
                      pic: Pic.week,
                      text: 'смен на неделе: ${o.shiftsLeft}',
                      semantic: 'Можно взять ещё ${o.shiftsLeft} смен '
                          'на этой неделе'),
                ],
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          if (block == null)
            SizedBox(
              // Альбомная: высота дороже — кнопка 48 dp (минимум ТЗ).
              height: WorldLayout.isLandscape(context) ? 48 : TapSize.min,
              child: FilledButton.icon(
                key: ValueKey<String>('jobs:take:$k'),
                onPressed: onTake,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Взяться',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            )
          else
            Semantics(
              label: 'Сейчас не взять: '
                  '${<String>[
                if (lock != null) lock,
                if (other != null) other
              ].join('. ')}',
              excludeSemantics: true,
              child: Container(
                key: ValueKey<String>('jobs:blocked:$k'),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm, vertical: Gap.xs),
                decoration: BoxDecoration(
                  color: WorldColors.night,
                  borderRadius: BorderRadius.circular(Radii.chip),
                  border: Border.all(color: WorldColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (lock != null)
                      _ReasonLine(
                          key: ValueKey<String>('jobs:lock:$k'),
                          icon: Icons.lock_outline_rounded,
                          text: lock),
                    if (lock != null && other != null)
                      const SizedBox(height: Gap.xs),
                    if (other != null)
                      _ReasonLine(
                          icon: Icons.info_outline_rounded, text: other),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка причины «не взять»: значок и текст.
class _ReasonLine extends StatelessWidget {
  const _ReasonLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, color: WorldColors.textSoft),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 16, color: WorldColors.text)),
          ),
        ],
      );
}

/// Одно число карточки: значок и подпись словами (цвет — не единственный
/// сигнал, ТЗ 3.6.5). Значок векторный, не эмодзи.
class _Fact extends StatelessWidget {
  const _Fact(
      {super.key,
      required this.pic,
      required this.text,
      required this.semantic});

  final Pic pic;
  final String text;
  final String semantic;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semantic,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
          decoration: BoxDecoration(
            color: WorldColors.night,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Pictogram(pic, size: 18, color: WorldColors.textSoft),
              const SizedBox(width: Gap.xs),
              Flexible(
                child: PicText(text,
                    style:
                        const TextStyle(fontSize: 16, color: WorldColors.text)),
              ),
            ],
          ),
        ),
      );
}

/// Картинка работы (реестр `job_pictures`: касса, лейка, сумка курьера…);
/// нет арта — прежний значок. Закрытая работа — картинка бледнее, с замком.
class _JobPicture extends StatefulWidget {
  const _JobPicture({required this.jobId, required this.locked});

  final String jobId;
  final bool locked;

  @override
  State<_JobPicture> createState() => _JobPictureState();
}

class _JobPictureState extends State<_JobPicture> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Карточки доски без ключей: состояние переходит к другой работе —
  // картинку ищем заново.
  @override
  void didUpdateWidget(_JobPicture old) {
    super.didUpdateWidget(old);
    if (old.jobId != widget.jobId) {
      _path = null;
      _load();
    }
  }

  void _load() {
    final String id = widget.jobId;
    AssetRegistry.load().then((AssetRegistry r) {
      if (mounted && widget.jobId == id) {
        setState(() => _path = r.jobPicture(id));
      }
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = Icon(
        widget.locked ? Icons.lock_rounded : Icons.work_rounded,
        size: 22,
        color: widget.locked ? WorldColors.textSoft : WorldColors.text);
    final String? p = _path;
    if (p == null) return icon;
    return ExcludeSemantics(
      child: SizedBox.square(
        key: ValueKey<String>('jobs:picture:${widget.jobId}'),
        dimension: 40,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Opacity(
                opacity: widget.locked ? 0.45 : 1,
                child: Image.asset(p,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => icon),
              ),
            ),
            if (widget.locked)
              const Align(
                alignment: Alignment.bottomRight,
                child: Icon(Icons.lock_rounded,
                    size: 16, color: WorldColors.textSoft),
              ),
          ],
        ),
      ),
    );
  }
}
